from __future__ import annotations
from datetime import datetime, timezone
from uuid import UUID
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from .security import current_user
from .repository import supabase_admin
from .authorization import (
    assert_patient_access,
    get_accessible_facility_ids,
    get_user_assignments,
)

router = APIRouter(prefix="/api/v1", tags=["clinical-workflows"])

ROLE_HOME = {
    "ASHA": ["My Mothers", "Visit Log", "Symptom Reports", "Follow-up Tasks", "Referral Companion"],
    "ANM": ["Smart Pregnancy Registration", "Patient List", "BP Scanner", "Risk Radar", "Follow-ups", "Referrals", "Postpartum"],
    "VHN": ["Smart Pregnancy Registration", "Patient List", "BP Scanner", "Risk Radar", "Follow-ups", "Referrals", "Postpartum"],
    "PHC_MO": ["PHC Dashboard", "Clinical Review", "Risk Radar", "Referral Board", "Team & Follow-ups", "Reports"],
    "CHC_MO": ["CHC Dashboard", "PHC Overview", "Clinical Alerts", "Referral Coordination", "Workload Analytics"],
    "CHC_ADMIN": ["CHC Dashboard", "PHC Overview", "User Management", "Referral Coordination", "Reports"],
    "THC_MO": ["THC Dashboard", "CHC Comparison", "Clinical Alerts", "Referral Performance", "Reports"],
    "THC_ADMIN": ["THC Dashboard", "Facility Hierarchy", "User Management", "Analytics", "Audit"],
    "RECEIVING_STAFF": ["Incoming Referrals", "Referral Details", "Arrival Check-in", "Assessment & Outcome"],
    "SUPERVISOR": ["Jurisdiction Dashboard", "Escalations", "Facility Performance", "Reports"],
    "SYSTEM_ADMIN": ["System Overview", "Users & Roles", "Facilities", "Clinical Rules", "Audit Logs", "Device Health"],
}

@router.get("/workspace")
def workspace(user: dict = Depends(current_user)):
    db = supabase_admin()
    uid = user["sub"]
    profile = db.table("user_profiles").select("user_id,full_name,login_id,preferred_language,is_active,account_status").eq("user_id", uid).maybe_single().execute().data
    if not profile or not profile.get("is_active") or profile.get("account_status") not in (None, "active"):
        raise HTTPException(403, "Account inactive or suspended")

    assignments = get_user_assignments(db, uid)
    if not assignments:
        raise HTTPException(403, "No active facility assignment")

    roles = list(dict.fromkeys(a["role"] for a in assignments))
    return {
        "profile": profile,
        "assignments": assignments,
        "workspaces": [{"role": r, "navigation": ROLE_HOME.get(r, [])} for r in roles],
    }

class QuestionnaireSection(BaseModel):
    patient_id: UUID
    pregnancy_id: UUID | None = None
    section_key: str = Field(min_length=2, max_length=80)
    answers: dict[str, Any]
    schema_version: str = "1.0"
    completed: bool = False

@router.post("/questionnaires/sections", status_code=201)
def save_questionnaire_section(payload: QuestionnaireSection, user: dict = Depends(current_user)):
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], str(payload.patient_id), action="questionnaire_write")

    row = {
        "patient_id": str(payload.patient_id),
        "pregnancy_id": str(payload.pregnancy_id) if payload.pregnancy_id else None,
        "section_key": payload.section_key,
        "answers": payload.answers,
        "schema_version": payload.schema_version,
        "completed_by": user["sub"],
        "completed_at": datetime.now(timezone.utc).isoformat() if payload.completed else None,
    }
    out = db.table("questionnaire_revisions").insert(row).execute().data

    # Update denormalized questionnaire_data snapshot
    current = patient.get("questionnaire_data") or {}
    current[payload.section_key] = payload.answers
    db.table("patients").update({"questionnaire_data": current}).eq("id", str(payload.patient_id)).execute()

    return out[0] if out else {"saved": True}

class ReferralCreate(BaseModel):
    patient_id: UUID
    receiving_facility_id: UUID
    reason: str = Field(min_length=3, max_length=2000)
    clinical_summary: dict[str, Any] = {}

TRANSITIONS = {
    "generated": {"sent"},
    "sent": {"acknowledged", "rejected"},
    "acknowledged": {"departed", "rejected"},
    "departed": {"arrived"},
    "arrived": {"assessed"},
    "assessed": {"completed", "redirected"},
    "rejected": {"redirected"},
    "redirected": {"sent"},
    "completed": set(),
}

@router.post("/referrals", status_code=201)
def create_referral(p: ReferralCreate, user: dict = Depends(current_user)):
    db = supabase_admin()
    pat = assert_patient_access(db, user["sub"], str(p.patient_id), action="referral_create")

    # Validate receiving facility exists and is active
    recv_id_str = str(p.receiving_facility_id)
    if recv_id_str == pat["facility_id"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Receiving facility must be different from origin facility",
        )

    target_fac = db.table("facilities").select("id,name,facility_type,is_active").eq("id", recv_id_str).maybe_single().execute().data
    if not target_fac or not target_fac.get("is_active"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Receiving facility does not exist or is inactive",
        )

    row = {
        "patient_id": str(p.patient_id),
        "origin_facility_id": pat["facility_id"],
        "receiving_facility_id": recv_id_str,
        "reason": p.reason,
        "clinical_summary": p.clinical_summary,
        "created_by": user["sub"],
        "status": "generated",
    }
    result = db.table("referrals").insert(row).execute().data
    if not result:
        raise HTTPException(status_code=400, detail="Referral creation failed")

    ref = result[0]
    db.table("referral_events").insert({
        "referral_id": ref["id"],
        "to_status": "generated",
        "actor_user_id": user["sub"],
        "note": f"Referral created to {target_fac.get('name', 'receiving facility')}",
    }).execute()

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": pat["facility_id"],
        "action": "referral_created",
        "entity_type": "referral",
        "entity_id": ref["id"],
        "metadata": {
            "patient_id": str(p.patient_id),
            "receiving_facility_id": recv_id_str,
        },
    }).execute()

    return ref

class ReferralTransition(BaseModel):
    status: str
    note: str | None = None

@router.post("/referrals/{referral_id}/transition")
def transition_referral(referral_id: UUID, p: ReferralTransition, user: dict = Depends(current_user)):
    db = supabase_admin()
    ref = db.table("referrals").select("*").eq("id", str(referral_id)).maybe_single().execute().data
    if not ref:
        raise HTTPException(404, "Referral not found")

    assignments = get_user_assignments(db, user["sub"])
    facilities = {a["facility_id"]: a["role"] for a in assignments}
    is_admin = "SYSTEM_ADMIN" in facilities.values()

    is_origin = ref["origin_facility_id"] in facilities
    is_receiver = ref.get("receiving_facility_id") in facilities

    if not (is_origin or is_receiver or is_admin):
        raise HTTPException(403, "No access to this referral: you belong to neither origin nor receiving facility")

    nxt = p.status.lower()
    allowed = TRANSITIONS.get(ref["status"], set())
    if nxt not in allowed:
        raise HTTPException(status_code=409, detail=f"Invalid referral transition: {ref['status']} -> {nxt}")

    # Enforce origin vs receiver responsibilities
    receiver_only = {"acknowledged", "arrived", "assessed", "completed", "rejected"}
    origin_only = {"sent", "departed"}

    if nxt in receiver_only and not (is_receiver or is_admin):
        raise HTTPException(status_code=403, detail="Receiving facility action required for this transition")

    if nxt in origin_only and not (is_origin or is_admin):
        raise HTTPException(status_code=403, detail="Origin facility action required for this transition")

    now_iso = datetime.now(timezone.utc).isoformat()
    db.table("referrals").update({
        "status": nxt,
        "updated_at": now_iso,
    }).eq("id", str(referral_id)).execute()

    db.table("referral_events").insert({
        "referral_id": str(referral_id),
        "from_status": ref["status"],
        "to_status": nxt,
        "actor_user_id": user["sub"],
        "note": p.note,
    }).execute()

    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": ref.get("origin_facility_id"),
        "action": f"referral_{nxt}",
        "entity_type": "referral",
        "entity_id": str(referral_id),
        "metadata": {"from_status": ref["status"], "to_status": nxt, "note": p.note},
    }).execute()

    return {
        "referral_id": str(referral_id),
        "previous_status": ref["status"],
        "status": nxt,
    }

@router.get("/referrals")
def list_referrals(status: str | None = Query(None), user: dict = Depends(current_user)):
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        raise HTTPException(403, "No active facility assignment")

    # Fetch referrals where user facility is origin OR receiving
    found = []
    for fid in accessible_fids:
        q_orig = db.table("referrals").select("*,facilities!origin_facility_id(name,facility_type),receiving:facilities!receiving_facility_id(name,facility_type)").eq("origin_facility_id", fid)
        q_recv = db.table("referrals").select("*,facilities!origin_facility_id(name,facility_type),receiving:facilities!receiving_facility_id(name,facility_type)").eq("receiving_facility_id", fid)

        if status:
            q_orig = q_orig.eq("status", status)
            q_recv = q_recv.eq("status", status)

        found.extend(q_orig.order("created_at", desc=True).limit(100).execute().data or [])
        found.extend(q_recv.order("created_at", desc=True).limit(100).execute().data or [])

    uniq = {x["id"]: x for x in found}
    return {"items": list(uniq.values())}

@router.get("/patients/{patient_id}/timeline")
def patient_timeline(patient_id: UUID, user: dict = Depends(current_user)):
    db = supabase_admin()
    # Unified authorization: direct, hierarchy, and active referral access
    assert_patient_access(db, user["sub"], str(patient_id), action="timeline")

    pat_id_str = str(patient_id)
    return {
        "bp_measurements": (
            db.table("bp_measurements")
            .select("*")
            .eq("patient_id", pat_id_str)
            .order("measured_at", desc=True)
            .limit(100)
            .execute()
            .data
            or []
        ),
        "screenings": (
            db.table("clinical_screenings")
            .select("*")
            .eq("patient_id", pat_id_str)
            .order("assessed_at", desc=True)
            .limit(50)
            .execute()
            .data
            or []
        ),
        "follow_ups": (
            db.table("follow_ups")
            .select("*")
            .eq("patient_id", pat_id_str)
            .order("due_at")
            .limit(50)
            .execute()
            .data
            or []
        ),
        "referrals": (
            db.table("referrals")
            .select("*,referral_events(*)")
            .eq("patient_id", pat_id_str)
            .order("created_at", desc=True)
            .limit(50)
            .execute()
            .data
            or []
        ),
    }
