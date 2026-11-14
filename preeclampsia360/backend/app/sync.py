from uuid import UUID
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from .security import current_user
from .repository import supabase_admin
from .authorization import get_accessible_facility_ids, get_user_assignments

router = APIRouter(prefix="/api/v1/sync", tags=["offline-sync"])

VALID_EVENT_TYPES = {
    "patient.upsert",
    "questionnaire.upsert",
    "bp.measurement",
    "followup.upsert",
    "postpartum.upsert",
    "referral.event",
}

class SyncItem(BaseModel):
    id: UUID
    event_type: str = Field(description="Must match one of the supported sync event types")
    entity_id: UUID | None = None
    facility_id: UUID
    client_created_at: str | None = None
    payload: dict[str, Any]

class SyncBatch(BaseModel):
    items: list[SyncItem] = Field(min_length=1, max_length=100)

@router.post("/push")
def push(batch: SyncBatch, user: dict = Depends(current_user)):
    db = supabase_admin()
    results = []
    assignments = get_user_assignments(db, user["sub"])
    allowed = {str(x["facility_id"]) for x in assignments}

    for item in batch.items:
        if str(item.facility_id) not in allowed:
            results.append({
                "id": str(item.id),
                "status": "rejected",
                "reason": "facility_not_assigned",
            })
            continue

        if item.event_type not in VALID_EVENT_TYPES:
            results.append({
                "id": str(item.id),
                "status": "rejected",
                "reason": f"unsupported_event_type: {item.event_type}",
            })
            continue

        existing = (
            db.table("sync_events")
            .select("id,processing_status")
            .eq("id", str(item.id))
            .maybe_single()
            .execute()
            .data
        )
        if existing:
            results.append({
                "id": str(item.id),
                "status": "duplicate",
                "server_status": existing["processing_status"],
            })
            continue

        row = {
            "id": str(item.id),
            "user_id": user["sub"],
            "facility_id": str(item.facility_id),
            "event_type": item.event_type,
            "entity_id": str(item.entity_id) if item.entity_id else None,
            "payload": item.payload,
            "client_created_at": item.client_created_at,
            "processing_status": "accepted",
        }

        try:
            db.table("sync_events").insert(row).execute()
            results.append({"id": str(item.id), "status": "accepted"})
        except Exception:
            results.append({
                "id": str(item.id),
                "status": "rejected",
                "reason": "persistence_error",
            })

    return {"results": results}

@router.get("/pull")
def pull(since: str | None = Query(None), user: dict = Depends(current_user)):
    """Pull updated patient records and referrals for offline caching."""
    db = supabase_admin()
    accessible_fids = get_accessible_facility_ids(db, user["sub"])
    if not accessible_fids:
        raise HTTPException(status_code=403, detail="No active facility assignment")

    target_fids = list(accessible_fids)
    q_pat = db.table("patients").select("*").in_("facility_id", target_fids)
    if since:
        q_pat = q_pat.gt("updated_at", since)
    patients = q_pat.order("updated_at", desc=True).limit(200).execute().data or []

    # Pull active referrals
    q_ref = db.table("referrals").select("*").in_("origin_facility_id", target_fids)
    if since:
        q_ref = q_ref.gt("updated_at", since)
    referrals = q_ref.order("updated_at", desc=True).limit(100).execute().data or []

    return {
        "sync_timestamp": since or "full",
        "patients": patients,
        "referrals": referrals,
    }

@router.get("/status")
def status(user: dict = Depends(current_user)):
    db = supabase_admin()
    r = db.table("sync_events").select("processing_status").eq("user_id", user["sub"]).execute().data or []
    return {
        "accepted": sum(x["processing_status"] == "accepted" for x in r),
        "processed": sum(x["processing_status"] == "processed" for x in r),
        "rejected": sum(x["processing_status"] == "rejected" for x in r),
    }
