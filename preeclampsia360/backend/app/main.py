from datetime import datetime, timezone
from fastapi import FastAPI, Depends, HTTPException, Query, Header, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from .config import settings
from .security import current_user
from .schemas import PatientCreate, PatientUpdate, BPMeasurementCreate, ObstetricHistoryCreate
from .repository import supabase_admin
from .auth import router as auth_router
from .workflows import router as workflows_router
from .sync import router as sync_router
from .ocr import router as ocr_router
from .trends import router as trends_router
from .authorization import (
    assert_patient_access,
    get_accessible_facility_ids,
    get_all_facilities_map,
    get_user_assignments,
)

app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="Maternal monitoring and referral coordination API",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Facility-ID"],
)

app.include_router(auth_router)
app.include_router(workflows_router)
app.include_router(sync_router)
app.include_router(ocr_router)
app.include_router(trends_router)

@app.get("/health")
def health():
    return {"status": "ok", "service": "preeclampsia360-api", "environment": settings.app_env}

@app.get("/api/v1/me")
def me(user: dict = Depends(current_user)):
    db = supabase_admin()
    profile = db.table("user_profiles").select("user_id,login_id,full_name,account_status,must_change_pin").eq("user_id", user["sub"]).maybe_single().execute().data
    assignments = get_user_assignments(db, user["sub"])
    return {
        "id": user["sub"],
        "email": user.get("email"),
        "profile": profile,
        "assignments": assignments,
    }

@app.get("/api/v1/facilities")
def list_facilities(user: dict = Depends(current_user)):
    db = supabase_admin()
    rows = (
        db.table("facilities")
        .select("id,name,facility_type,parent_facility_id,facility_code,district_id,is_active")
        .eq("is_active", True)
        .order("name")
        .execute()
        .data
        or []
    )
    return {"items": rows}

@app.get("/api/v1/facilities/my-scope")
def facility_scope(user: dict = Depends(current_user)):
    db = supabase_admin()
    assignments = get_user_assignments(db, user["sub"])
    if not assignments:
        raise HTTPException(status_code=403, detail="No active facility assignment")
    accessible = get_accessible_facility_ids(db, user["sub"])
    return {"assignments": assignments, "accessible_facility_ids": list(accessible)}

@app.post("/api/v1/patients", status_code=201)
def create_patient(
    payload: PatientCreate,
    user: dict = Depends(current_user),
    x_facility_id: str | None = Header(None, alias="X-Facility-ID"),
):
    db = supabase_admin()
    assignments = get_user_assignments(db, user["sub"])
    if not assignments:
        raise HTTPException(status_code=403, detail="No active facility assignment")

    # Select target facility from header if assigned, else default to first assignment
    assigned_fids = {a["facility_id"] for a in assignments}
    if x_facility_id:
        if x_facility_id not in assigned_fids and not any(a["role"] == "SYSTEM_ADMIN" for a in assignments):
            raise HTTPException(status_code=403, detail="You are not assigned to the requested facility")
        facility_id = x_facility_id
    else:
        facility_id = assignments[0]["facility_id"]

    data = payload.model_dump(mode="json")
    questionnaire = data.pop("questionnaire", {})
    row = {
        **data,
        "facility_id": facility_id,
        "created_by": user["sub"],
        "questionnaire_data": questionnaire,
    }

    result = db.table("patients").insert(row).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Patient could not be created")
    
    patient = result.data[0]
    # Log patient creation audit event
    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": facility_id,
        "action": "patient_created",
        "entity_type": "patient",
        "entity_id": patient["id"],
        "metadata": {"patient_code": patient.get("patient_code")},
    }).execute()

    return patient

@app.get("/api/v1/patients")
def list_patients(
    q: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=100, ge=1, le=200),
    user: dict = Depends(current_user),
    x_facility_id: str | None = Header(None, alias="X-Facility-ID"),
):
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        raise HTTPException(status_code=403, detail="No active facility assignment found")

    # Filter to specific facility if requested in header and accessible
    if x_facility_id:
        if x_facility_id not in accessible_fids:
            raise HTTPException(status_code=403, detail="Requested facility is outside your scope")
        target_fids = [x_facility_id]
    else:
        target_fids = list(accessible_fids)

    # PostgREST in_ filter
    query = (
        db.table("patients")
        .select("id,patient_code,full_name,date_of_birth,phone,created_at,facility_id,blood_group,questionnaire_data")
        .in_("facility_id", target_fids)
        .order("created_at", desc=True)
        .limit(limit)
    )

    if q:
        query = query.ilike("full_name", f"%{q}%")

    rows = query.execute().data or []

    # Calculate 2-week Antenatal Visit due status (Every patient must be checked every 2 weeks)
    if rows:
        p_ids = [r["id"] for r in rows]
        try:
            recent_bps = (
                db.table("bp_measurements")
                .select("patient_id,measured_at,systolic_mmhg,diastolic_mmhg")
                .in_("patient_id", p_ids)
                .order("measured_at", desc=True)
                .execute()
                .data or []
            )
            latest_bp_map = {}
            for bp in recent_bps:
                pid = bp["patient_id"]
                if pid not in latest_bp_map:
                    latest_bp_map[pid] = bp

            now_utc = datetime.now(timezone.utc)
            for r in rows:
                latest = latest_bp_map.get(r["id"])
                if latest:
                    r["last_visit_at"] = latest["measured_at"]
                    r["latest_bp"] = f"{latest['systolic_mmhg']}/{latest['diastolic_mmhg']}"
                    try:
                        m_dt = datetime.fromisoformat(latest["measured_at"].replace("Z", "+00:00"))
                        days = (now_utc - m_dt).days
                    except Exception:
                        days = 0
                else:
                    r["last_visit_at"] = r.get("created_at")
                    r["latest_bp"] = None
                    try:
                        c_dt = datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
                        days = (now_utc - c_dt).days
                    except Exception:
                        days = 14
                r["days_since_last_visit"] = days
                r["anc_due_2_weeks"] = days >= 14
        except Exception:
            pass

    return {"items": rows}

@app.get("/api/v1/anm/due-visits")
def get_anm_due_visits(user: dict = Depends(current_user)):
    """
    Returns patients assigned to ANM/facility who are due or overdue
    for their mandatory 2-week routine antenatal visit / BP check.
    """
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        return {"items": [], "total_due": 0}

    patients = (
        db.table("patients")
        .select("id,patient_code,full_name,date_of_birth,phone,created_at,facility_id,blood_group,questionnaire_data")
        .in_("facility_id", list(accessible_fids))
        .order("created_at", desc=True)
        .execute()
        .data or []
    )
    if not patients:
        return {"items": [], "total_due": 0}

    p_ids = [p["id"] for p in patients]
    latest_bp_map = {}
    try:
        recent_bps = (
            db.table("bp_measurements")
            .select("patient_id,measured_at,systolic_mmhg,diastolic_mmhg")
            .in_("patient_id", p_ids)
            .order("measured_at", desc=True)
            .execute()
            .data or []
        )
        for bp in recent_bps:
            pid = bp["patient_id"]
            if pid not in latest_bp_map:
                latest_bp_map[pid] = bp
    except Exception:
        pass

    now_utc = datetime.now(timezone.utc)
    due_list = []
    for p in patients:
        latest = latest_bp_map.get(p["id"])
        if latest:
            p["last_visit_at"] = latest["measured_at"]
            p["latest_bp"] = f"{latest['systolic_mmhg']}/{latest['diastolic_mmhg']}"
            try:
                m_dt = datetime.fromisoformat(latest["measured_at"].replace("Z", "+00:00"))
                days = (now_utc - m_dt).days
            except Exception:
                days = 0
        else:
            p["last_visit_at"] = p.get("created_at")
            p["latest_bp"] = None
            try:
                c_dt = datetime.fromisoformat(p["created_at"].replace("Z", "+00:00"))
                days = (now_utc - c_dt).days
            except Exception:
                days = 14
        p["days_since_last_visit"] = days
        p["anc_due_2_weeks"] = days >= 14
        if p["anc_due_2_weeks"]:
            due_list.append(p)

    return {"items": due_list, "total_due": len(due_list)}

@app.get("/api/v1/patients/{patient_id}")
def get_patient(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    # Unified authorization: supports direct, hierarchy, and active referral access
    patient = assert_patient_access(db, user["sub"], patient_id, action="read")
    return patient

@app.get("/api/v1/patients/{patient_id}/investigations")
def get_patient_investigations(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="read")
    
    # Try dedicated table first
    try:
        rows = (
            db.table("patient_investigations")
            .select("*")
            .eq("patient_id", patient_id)
            .order("recorded_at", desc=True)
            .execute()
            .data
            or []
        )
        if rows:
            return {"items": rows, "latest": rows[0]}
    except Exception:
        pass
    
    # Fallback to questionnaire_data on patient record
    inv = (patient.get("questionnaire_data") or {}).get("investigations") or {}
    return {"items": [inv] if inv else [], "latest": inv if inv else None}

@app.put("/api/v1/patients/{patient_id}")
def update_patient(patient_id: str, payload: PatientUpdate, user: dict = Depends(current_user)):
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="patient_edit")
    
    update_data = {k: v for k, v in payload.model_dump(mode="json").items() if v is not None}
    if not update_data:
        return patient

    update_data["updated_at"] = datetime.now(timezone.utc).isoformat()
    result = db.table("patients").update(update_data).eq("id", patient_id).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Failed to update patient profile")

    updated = result.data[0]

    # If investigations are present, also sync to dedicated patient_investigations table if migrated
    inv = (payload.questionnaire_data or {}).get("investigations") if isinstance(payload.questionnaire_data, dict) else None
    if inv and isinstance(inv, dict):
        try:
            db.table("patient_investigations").insert({
                "patient_id": patient_id,
                "facility_id": patient.get("facility_id"),
                "hb": str(inv.get("hb") or ""),
                "urea": str(inv.get("urea") or ""),
                "platelet": str(inv.get("platelet") or ""),
                "creatinine": str(inv.get("creatinine") or ""),
                "lft": str(inv.get("lft") or ""),
                "recorded_by": user["sub"],
            }).execute()
        except Exception:
            pass  # Fallback if table migration 0008 has not yet been run

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": patient.get("facility_id"),
        "action": "patient_updated",
        "entity_type": "patient",
        "entity_id": patient_id,
        "metadata": {"updated_fields": list(update_data.keys())},
    }).execute()
    return updated

@app.get("/api/v1/patients/{patient_id}/obstetric-history")
def get_obstetric_history(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    assert_patient_access(db, user["sub"], patient_id, action="obstetric_history_read")
    rows = (
        db.table("obstetric_history")
        .select("*")
        .eq("patient_id", patient_id)
        .order("pregnancy_number", desc=False)
        .execute()
        .data
        or []
    )
    return {"items": rows}

@app.post("/api/v1/patients/{patient_id}/obstetric-history", status_code=201)
def add_obstetric_history(patient_id: str, payload: ObstetricHistoryCreate, user: dict = Depends(current_user)):
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="obstetric_history_write")
    
    row = {
        "patient_id": patient_id,
        **payload.model_dump(mode="json"),
    }
    existing = (
        db.table("obstetric_history")
        .select("id")
        .eq("patient_id", patient_id)
        .eq("pregnancy_number", payload.pregnancy_number)
        .maybe_single()
        .execute()
        .data
    )
    if existing:
        res = db.table("obstetric_history").update(row).eq("id", existing["id"]).execute()
        saved = res.data[0] if res.data else row
    else:
        res = db.table("obstetric_history").insert(row).execute()
        saved = res.data[0] if res.data else row

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": patient.get("facility_id"),
        "action": "obstetric_history_saved",
        "entity_type": "obstetric_history",
        "entity_id": saved.get("id"),
        "metadata": {"pregnancy_number": payload.pregnancy_number},
    }).execute()
    return saved

@app.delete("/api/v1/patients/{patient_id}/obstetric-history/{history_id}")
def delete_obstetric_history(patient_id: str, history_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    assert_patient_access(db, user["sub"], patient_id, action="obstetric_history_write")
    db.table("obstetric_history").delete().eq("id", history_id).eq("patient_id", patient_id).execute()
    return {"status": "deleted"}

@app.get("/api/v1/patients/{patient_id}/questionnaires")
def get_patient_questionnaires(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="questionnaire_read")
    revisions = (
        db.table("questionnaire_revisions")
        .select("*")
        .eq("patient_id", patient_id)
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )
    return {
        "patient_id": patient_id,
        "questionnaire_data": patient.get("questionnaire_data") or {},
        "revisions": revisions,
    }

@app.post("/api/v1/bp/measurements", status_code=201)
def create_bp_measurement(payload: BPMeasurementCreate, user: dict = Depends(current_user)):
    if not payload.worker_confirmed:
        raise HTTPException(status_code=422, detail="Worker must visually verify the displayed reading before saving")
    if payload.systolic_mmhg <= payload.diastolic_mmhg:
        raise HTTPException(status_code=422, detail="Systolic value must exceed diastolic value")

    db = supabase_admin()
    # Check access to patient
    patient = assert_patient_access(db, user["sub"], payload.patient_id, action="bp_write")

    row = {
        "patient_id": payload.patient_id,
        "systolic_mmhg": payload.systolic_mmhg,
        "diastolic_mmhg": payload.diastolic_mmhg,
        "pulse_bpm": payload.pulse_bpm,
        "device_id": payload.device_id,
        "capture_method": payload.capture_method,
        "ocr_confidence": payload.ocr_confidence,
        "worker_confirmed": payload.worker_confirmed,
        "measured_at": payload.measured_at.isoformat(),
        "facility_id": patient["facility_id"],
        "recorded_by": user["sub"],
        "verification_status": "worker_verified",
    }
    result = db.table("bp_measurements").insert(row).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Measurement could not be saved")
    
    measurement = result.data[0]

    # Store clinical markers (urine protein & imminent symptoms) in measurement_captures
    if payload.urine_protein or payload.imminent_symptoms:
        try:
            db.table("measurement_captures").insert({
                "measurement_id": measurement["id"],
                "extracted_values": {
                    "urine_protein": payload.urine_protein,
                    "imminent_symptoms": payload.imminent_symptoms,
                },
                "ocr_engine": payload.capture_method,
            }).execute()
        except Exception:
            pass

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": patient["facility_id"],
        "action": "bp_measurement_saved",
        "entity_type": "bp_measurement",
        "entity_id": measurement["id"],
        "metadata": {
            "systolic": payload.systolic_mmhg,
            "diastolic": payload.diastolic_mmhg,
            "patient_id": payload.patient_id,
            "urine_protein": payload.urine_protein,
            "imminent_symptoms": payload.imminent_symptoms,
        },
    }).execute()

    # Backend alert evaluation:
    # Trigger elevated BP alert when SBP >= 140 OR DBP >= 90 mmHg OR imminent symptoms OR proteinuria
    has_symptoms = bool(payload.imminent_symptoms)
    has_protein = bool(payload.urine_protein and payload.urine_protein not in {"nil", "not_tested", "trace"})
    is_elevated = (payload.systolic_mmhg >= 140 or payload.diastolic_mmhg >= 90) or has_symptoms or has_protein
    alert_record = None
    if is_elevated:
        is_critical = (
            payload.systolic_mmhg >= 160 or
            payload.diastolic_mmhg >= 110 or
            has_symptoms or
            payload.urine_protein in {"2+", "3+", "4+"}
        )
        severity = "red" if is_critical else "amber"

        trigger_parts = [f"BP: {payload.systolic_mmhg}/{payload.diastolic_mmhg} mmHg"]
        if payload.urine_protein and payload.urine_protein not in {"nil", "not_tested"}:
            trigger_parts.append(f"Proteinuria: {payload.urine_protein}")
        if payload.imminent_symptoms:
            trigger_parts.append(f"Imminent Symptoms: {', '.join(payload.imminent_symptoms)}")
        trigger_reason = " • ".join(trigger_parts)

        alert_row = {
            "patient_id": str(payload.patient_id),
            "measurement_id": measurement["id"],
            "facility_id": patient["facility_id"],
            "worker_user_id": user["sub"],
            "alert_type": "ELEVATED_BP",
            "severity": severity,
            "trigger_reason": trigger_reason,
            "systolic_mmhg": payload.systolic_mmhg,
            "diastolic_mmhg": payload.diastolic_mmhg,
            "status": "active",
        }
        alert_res = db.table("clinical_alerts").insert(alert_row).execute()
        alert_record = alert_res.data[0] if alert_res.data else alert_row

        db.table("audit_logs").insert({
            "actor_user_id": user["sub"],
            "facility_id": patient["facility_id"],
            "action": "clinical_alert_triggered",
            "entity_type": "clinical_alert",
            "entity_id": alert_record.get("id"),
            "metadata": {
                "severity": severity,
                "reason": alert_row["trigger_reason"],
                "measurement_id": measurement["id"],
            },
        }).execute()

    return {
        **measurement,
        "alert_triggered": is_elevated,
        "alert": alert_record,
    }

class AlertReviewRequest(BaseModel):
    status: str = Field(pattern="^(reviewed|referred|dismissed)$")
    review_notes: str = Field(min_length=2, max_length=1000)

@app.get("/api/v1/alerts")
def list_clinical_alerts(
    status: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    user: dict = Depends(current_user),
):
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        raise HTTPException(status_code=403, detail="No active facility assignments")

    query = (
        db.table("clinical_alerts")
        .select("*")
        .in_("facility_id", list(accessible_fids))
        .order("created_at", desc=True)
        .limit(limit)
    )
    if status:
        query = query.eq("status", status)

    rows = query.execute().data or []
    if not rows:
        return {"items": []}

    pat_ids = list({r["patient_id"] for r in rows if r.get("patient_id")})
    pat_map = {}
    if pat_ids:
        patients = (
            db.table("patients")
            .select("id,patient_code,full_name,phone,blood_group,lmp,edd,facility_id")
            .in_("id", pat_ids)
            .execute()
            .data
            or []
        )
        pat_map = {p["id"]: p for p in patients}

    fac_map = get_all_facilities_map(db)

    for r in rows:
        r["patient"] = pat_map.get(r.get("patient_id"), {})
        r["facility_name"] = fac_map.get(r.get("facility_id"), {}).get("name", "Unknown Facility")

    return {"items": rows}

@app.post("/api/v1/alerts/{alert_id}/review")
def review_clinical_alert(
    alert_id: str,
    payload: AlertReviewRequest,
    user: dict = Depends(current_user),
):
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    alert = db.table("clinical_alerts").select("*").eq("id", alert_id).maybe_single().execute().data
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")

    if alert["facility_id"] not in accessible_fids:
        raise HTTPException(status_code=403, detail="Alert belongs to a facility outside your jurisdiction")

    update_row = {
        "status": payload.status,
        "reviewed_by": user["sub"],
        "reviewed_at": datetime.now(timezone.utc).isoformat(),
        "review_notes": payload.review_notes,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    res = db.table("clinical_alerts").update(update_row).eq("id", alert_id).execute()
    updated = res.data[0] if res.data else {**alert, **update_row}

    # When alert is acknowledged/reviewed, tag patient for active surveillance tracking
    try:
        pat_res = db.table("patients").select("id,questionnaire_data").eq("id", alert["patient_id"]).maybe_single().execute().data
        if pat_res:
            qd = pat_res.get("questionnaire_data") or {}
            qd["is_tracked"] = True
            qd["tracking_status"] = "active_surveillance"
            qd["tracked_at"] = datetime.now(timezone.utc).isoformat()
            qd["tracking_reason"] = f"Yellow Alert Acknowledged: {alert.get('trigger_reason', 'Elevated BP')}"
            qd["last_alert_severity"] = alert.get("severity", "amber")
            qd["last_alert_bp"] = f"{alert.get('systolic_mmhg')}/{alert.get('diastolic_mmhg')}"
            db.table("patients").update({"questionnaire_data": qd}).eq("id", alert["patient_id"]).execute()
    except Exception:
        pass

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": alert["facility_id"],
        "action": f"clinical_alert_{payload.status}",
        "entity_type": "clinical_alert",
        "entity_id": alert_id,
        "metadata": {"review_notes": payload.review_notes},
    }).execute()

    return updated

@app.get("/api/v1/dashboard/metrics")
def get_dashboard_metrics(user: dict = Depends(current_user)):
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        return {
            "registered_patients": 0,
            "active_alerts": 0,
            "severe_alerts": 0,
            "active_referrals": 0,
            "incoming_referrals": 0,
        }

    fids = list(accessible_fids)
    user_assignments = get_user_assignments(db, user["sub"])
    user_direct_fids = [a["facility_id"] for a in user_assignments]

    patients = db.table("patients").select("id").in_("facility_id", fids).execute().data or []
    alerts = db.table("clinical_alerts").select("id,severity,status").in_("facility_id", fids).eq("status", "active").execute().data or []
    active_referrals = db.table("referrals").select("id").in_("origin_facility_id", fids).in_("status", ["generated", "sent", "acknowledged", "departed", "arrived", "assessed"]).execute().data or []
    incoming_referrals = db.table("referrals").select("id").in_("receiving_facility_id", user_direct_fids).in_("status", ["sent", "acknowledged", "departed"]).execute().data or []

    return {
        "registered_patients": len(patients),
        "active_alerts": len(alerts),
        "severe_alerts": sum(1 for a in alerts if a.get("severity") == "red"),
        "active_referrals": len(active_referrals),
        "incoming_referrals": len(incoming_referrals),
    }
