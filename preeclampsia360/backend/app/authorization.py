from __future__ import annotations
from typing import Any
from uuid import UUID
from fastapi import HTTPException, status
from supabase import Client

SUPERVISORY_ROLES = {"SYSTEM_ADMIN", "THC_ADMIN", "THC_MO", "CHC_ADMIN", "CHC_MO", "SUPERVISOR"}
ACTIVE_REFERRAL_STATUSES = {"generated", "sent", "acknowledged", "departed", "arrived", "assessed"}

def get_user_assignments(db: Client, user_id: str) -> list[dict[str, Any]]:
    return (
        db.table("user_facility_assignments")
        .select("facility_id,role,is_active,facilities(id,name,facility_type,parent_facility_id,facility_code)")
        .eq("user_id", user_id)
        .eq("is_active", True)
        .execute()
        .data
        or []
    )

def get_all_facilities_map(db: Client) -> dict[str, dict[str, Any]]:
    facilities = db.table("facilities").select("id,name,facility_type,parent_facility_id,is_active").execute().data or []
    return {f["id"]: f for f in facilities}

def is_descendant(facilities_by_id: dict[str, dict[str, Any]], ancestor_id: str, target_id: str) -> bool:
    if ancestor_id == target_id:
        return True
    current = facilities_by_id.get(target_id)
    seen: set[str] = set()
    while current and current.get("parent_facility_id") and current["id"] not in seen:
        seen.add(current["id"])
        parent_id = current["parent_facility_id"]
        if parent_id == ancestor_id:
            return True
        current = facilities_by_id.get(parent_id)
    return False

def get_accessible_facility_ids(db: Client, user_id: str) -> set[str]:
    assignments = get_user_assignments(db, user_id)
    if not assignments:
        return set()
    
    # SYSTEM_ADMIN has access to all active facilities
    if any(a["role"] == "SYSTEM_ADMIN" for a in assignments):
        all_facs = db.table("facilities").select("id").eq("is_active", True).execute().data or []
        return {f["id"] for f in all_facs}

    fac_map = get_all_facilities_map(db)
    accessible: set[str] = set()

    for a in assignments:
        fid = a["facility_id"]
        role = a["role"]
        accessible.add(fid)
        if role in SUPERVISORY_ROLES:
            # Add all children/descendants in the hierarchy
            for target_id in fac_map.keys():
                if is_descendant(fac_map, fid, target_id):
                    accessible.add(target_id)
            # Tertiary hospitals (THC / Referral Hospitals) supervise & monitor all regional PHCs & CHCs
            if role in ("THC_ADMIN", "THC_MO") or fac_map.get(fid, {}).get("facility_type") in ("THC", "HOSPITAL"):
                for target_id, fac in fac_map.items():
                    if fac.get("facility_type") in ("PHC", "CHC"):
                        accessible.add(target_id)

    return accessible

def get_active_referred_patient_ids(db: Client, user_facility_ids: set[str]) -> set[str]:
    if not user_facility_ids:
        return set()
    # Query referrals where receiving_facility_id is in user_facility_ids
    found = []
    for fid in user_facility_ids:
        res = (
            db.table("referrals")
            .select("patient_id,status")
            .eq("receiving_facility_id", fid)
            .execute()
            .data
            or []
        )
        found.extend(res)
    return {r["patient_id"] for r in found if r.get("status") in ACTIVE_REFERRAL_STATUSES}

def assert_patient_access(
    db: Client,
    user_id: str,
    patient_id: str,
    action: str = "read",
    log_audit: bool = True,
) -> dict[str, Any]:
    patient_res = db.table("patients").select("*").eq("id", str(patient_id)).maybe_single().execute()
    if not patient_res.data:
        raise HTTPException(status_code=404, detail="Patient not found")
    patient = patient_res.data
    patient_facility_id = patient["facility_id"]

    # 0. Patient self-access
    if str(user_id) == str(patient_id):
        _log_patient_audit(db, user_id, patient, action, "patient_self_access", log_audit)
        return patient

    assignments = get_user_assignments(db, user_id)
    if not assignments:
        raise HTTPException(status_code=403, detail="No active facility assignment found")

    user_roles = {a["role"] for a in assignments}
    user_facilities = {a["facility_id"] for a in assignments}

    # 1. System Admin
    if "SYSTEM_ADMIN" in user_roles:
        _log_patient_audit(db, user_id, patient, action, "system_admin_override", log_audit)
        return patient

    # 2. Direct facility assignment
    if patient_facility_id in user_facilities:
        _log_patient_audit(db, user_id, patient, action, "direct_facility_assignment", log_audit)
        return patient

    # 3. Hierarchy traversal (THC -> CHC -> PHC)
    fac_map = get_all_facilities_map(db)
    for a in assignments:
        if a["role"] in SUPERVISORY_ROLES:
            if is_descendant(fac_map, a["facility_id"], patient_facility_id):
                _log_patient_audit(db, user_id, patient, action, "supervisory_hierarchy_scope", log_audit)
                return patient

    # 4. Referral-based clinical access for receiving clinicians
    if action in ("read", "timeline", "bp_read", "obstetric_history_read", "questionnaire_read"):
        active_patient_ids = get_active_referred_patient_ids(db, user_facilities)
        if str(patient_id) in active_patient_ids:
            _log_patient_audit(db, user_id, patient, action, "active_referral_clinical_grant", log_audit)
            return patient

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Patient is outside your assigned facility hierarchy and has no active referral to your facility",
    )

def _log_patient_audit(db: Client, user_id: str, patient: dict[str, Any], action: str, grant_reason: str, should_log: bool):
    if not should_log:
        return
    try:
        is_self_patient = str(user_id) == str(patient.get("id"))
        actor_id = None if is_self_patient else user_id
        db.table("audit_logs").insert({
            "actor_user_id": actor_id,
            "facility_id": patient.get("facility_id"),
            "action": f"patient_{action}",
            "entity_type": "patient",
            "entity_id": patient.get("id"),
            "metadata": {
                "patient_code": patient.get("patient_code"),
                "grant_reason": grant_reason,
                "is_self_patient": is_self_patient,
            },
        }).execute()
    except Exception:
        # Audit logging failure should not crash request but should be traced
        pass

