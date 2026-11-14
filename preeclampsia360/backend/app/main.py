from fastapi import FastAPI, Depends, HTTPException, Query, Header, status
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .security import current_user
from .schemas import PatientCreate, BPMeasurementCreate
from .repository import supabase_admin
from .auth import router as auth_router
from .workflows import router as workflows_router
from .sync import router as sync_router
from .ocr import router as ocr_router
from .authorization import (
    assert_patient_access,
    get_accessible_facility_ids,
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
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Facility-ID"],
)

app.include_router(auth_router)
app.include_router(workflows_router)
app.include_router(sync_router)
app.include_router(ocr_router)

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
        .select("id,patient_code,full_name,date_of_birth,phone,created_at,facility_id,blood_group")
        .in_("facility_id", target_fids)
        .order("created_at", desc=True)
        .limit(limit)
    )

    if q:
        query = query.ilike("full_name", f"%{q}%")

    rows = query.execute().data or []
    return {"items": rows}

@app.get("/api/v1/patients/{patient_id}")
def get_patient(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    # Unified authorization: supports direct, hierarchy, and active referral access
    patient = assert_patient_access(db, user["sub"], patient_id, action="read")
    return patient

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
        **payload.model_dump(mode="json"),
        "facility_id": patient["facility_id"],
        "recorded_by": user["sub"],
        "verification_status": "worker_verified",
    }
    result = db.table("bp_measurements").insert(row).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Measurement could not be saved")
    
    measurement = result.data[0]
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
        },
    }).execute()

    return measurement
