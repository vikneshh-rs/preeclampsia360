from __future__ import annotations
import re, time, uuid
from collections import defaultdict, deque
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel, Field
from supabase import create_client
from .config import settings
from .repository import supabase_admin
from .security import current_user

router = APIRouter(prefix="/api/v1/auth", tags=["authentication"])
_attempts: dict[str, deque[float]] = defaultdict(deque)
WINDOW_SECONDS = 300
MAX_ATTEMPTS = 5

def _internal_email(user_id: str) -> str:
    return f"{user_id}@{settings.internal_auth_domain}"

def _client():
    if not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Authentication service is not configured")
    return create_client(settings.supabase_url, settings.supabase_service_role_key)

class LoginRequest(BaseModel):
    login_id: str = Field(min_length=8, max_length=64, pattern=r"^PY-[A-Z0-9]+(-[A-Z0-9]+){1,4}$")
    pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

class ProvisionRequest(BaseModel):
    login_id: str = Field(min_length=8, max_length=64, pattern=r"^PY-[A-Z0-9]+(-[A-Z0-9]+){1,4}$")
    full_name: str = Field(min_length=2, max_length=160)
    facility_id: UUID
    role: str
    pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

@router.post("/login")
def login(payload: LoginRequest, request: Request):
    key = f"{request.client.host if request.client else 'unknown'}:{payload.login_id.upper()}"
    now = time.time(); bucket = _attempts[key]
    while bucket and now - bucket[0] > WINDOW_SECONDS: bucket.popleft()
    if len(bucket) >= MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Try again in five minutes.")
    db = supabase_admin()
    profile = db.table("user_profiles").select("user_id,login_id,full_name,is_active,account_status,must_change_pin,internal_auth_email").eq("login_id", payload.login_id.upper()).maybe_single().execute().data
    if not profile or not profile.get("is_active", False) or profile.get("account_status") != "active":
        bucket.append(now)
        raise HTTPException(status_code=401, detail="Invalid ID or PIN")
    try:
        auth = _client().auth.sign_in_with_password({"email": profile.get("internal_auth_email") or _internal_email(profile["user_id"]), "password": payload.pin})
        bucket.clear()
        assignments = db.table("user_facility_assignments").select("facility_id,role,facilities(id,name,facility_type,facility_code)").eq("user_id", profile["user_id"]).eq("is_active", True).execute().data or []
        if not assignments:
            raise HTTPException(status_code=403, detail="No active facility assignment")
        return {"access_token": auth.session.access_token, "refresh_token": auth.session.refresh_token, "token_type": "bearer", "expires_in": auth.session.expires_in, "user": {"id": profile["user_id"], "login_id": profile["login_id"], "full_name": profile["full_name"], "must_change_pin": profile.get("must_change_pin", True), "assignments": assignments}}
    except HTTPException:
        raise
    except Exception:
        bucket.append(now)
        raise HTTPException(status_code=401, detail="Invalid ID or PIN")

@router.post("/provision", status_code=201)
def provision(payload: ProvisionRequest, actor: dict = Depends(current_user)):
    db = supabase_admin()
    actor_id = actor["sub"]
    actor_rows = db.table("user_facility_assignments").select("facility_id,role").eq("user_id", actor_id).eq("is_active", True).execute().data or []
    actor_roles = {r["role"] for r in actor_rows}
    role = payload.role.upper()
    target = db.table("facilities").select("id,facility_type,parent_facility_id,is_active").eq("id", str(payload.facility_id)).maybe_single().execute().data
    if not target or not target.get("is_active"):
        raise HTTPException(status_code=422, detail="Target facility does not exist or is inactive")
    permitted = "SYSTEM_ADMIN" in actor_roles
    if not permitted:
        for ar in actor_rows:
            af = db.table("facilities").select("id,facility_type").eq("id", ar["facility_id"]).maybe_single().execute().data
            if not af: continue
            if ar["role"] in ("THC_ADMIN","THC_MO") and af["facility_type"] == "THC" and target.get("facility_type") == "CHC" and target.get("parent_facility_id") == af["id"] and role in ("CHC_ADMIN","CHC_MO"):
                permitted = True
            if ar["role"] in ("CHC_ADMIN","CHC_MO") and af["facility_type"] == "CHC" and target.get("facility_type") == "PHC" and target.get("parent_facility_id") == af["id"] and role == "PHC_MO":
                permitted = True
            if ar["role"] == "PHC_MO" and af["facility_type"] == "PHC" and target.get("id") == af["id"] and role in ("ANM","ASHA","VHN"):
                permitted = True
    if not permitted:
        raise HTTPException(status_code=403, detail="You cannot provision this role at the selected facility")
    allowed = {"ANM","ASHA","VHN","PHC_MO","CHC_MO","CHC_ADMIN","THC_MO","THC_ADMIN","RECEIVING_STAFF","SUPERVISOR"}
    if role not in allowed:
        raise HTTPException(status_code=422, detail="Unsupported role")
    existing = db.table("user_profiles").select("user_id").eq("login_id", payload.login_id.upper()).maybe_single().execute().data
    if existing:
        raise HTTPException(status_code=409, detail="Login ID already exists")
    auth_user = None
    try:
        auth_email = f"{uuid.uuid4()}@{settings.internal_auth_domain}"
        created = _client().auth.admin.create_user({"email": auth_email, "password": payload.pin, "email_confirm": True, "user_metadata": {"login_id": payload.login_id.upper()}})
        auth_user = created.user
        db.table("user_profiles").insert({"user_id": auth_user.id, "full_name": payload.full_name, "login_id": payload.login_id.upper(), "is_active": True, "account_status": "active", "must_change_pin": True, "internal_auth_email": auth_email}).execute()
        db.table("user_facility_assignments").insert({"user_id": auth_user.id, "facility_id": str(payload.facility_id), "role": role, "is_active": True}).execute()
        db.table("account_provisioning_audit").insert({"actor_user_id": actor_id, "target_user_id": auth_user.id, "facility_id": str(payload.facility_id), "assigned_role": role, "action": "account_created"}).execute()
        return {"user_id": auth_user.id, "login_id": payload.login_id.upper(), "role": role, "status": "active", "must_change_pin": True}
    except Exception as exc:
        if auth_user:
            try: _client().auth.admin.delete_user(auth_user.id)
            except Exception: pass
        raise HTTPException(status_code=400, detail=f"Account provisioning failed: {str(exc)[:180]}")
