from __future__ import annotations
import re, time, uuid
from collections import defaultdict, deque
from datetime import datetime, timezone
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Depends, status
from pydantic import BaseModel, Field
from supabase import create_client
from .config import settings
from .repository import supabase_admin
from .security import current_user

router = APIRouter(prefix="/api/v1/auth", tags=["authentication"])

# Persistent in-process tracking with timestamps
_failed_attempts: dict[str, list[float]] = defaultdict(list)
WINDOW_SECONDS = settings.lockout_duration_seconds
MAX_ATTEMPTS = settings.max_login_attempts

WEAK_PINS = {"000000", "111111", "123456", "654321", "222222", "333333", "444444", "555555", "666666", "777777", "888888", "999999"}

def _internal_email(user_id: str) -> str:
    return f"{user_id}@{settings.internal_auth_domain}"

def _client():
    if not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Authentication service is not configured")
    return create_client(settings.supabase_url, settings.supabase_service_role_key)

class LoginRequest(BaseModel):
    login_id: str = Field(min_length=8, max_length=64, pattern=r"^PY-[A-Z0-9]+(-[A-Z0-9]+){1,4}$")
    pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10)

class ChangePinRequest(BaseModel):
    current_pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")
    new_pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

class UserStatusRequest(BaseModel):
    status: str = Field(pattern=r"^(active|suspended|deactivated)$")
    reason: str = Field(default="Administrative status update", max_length=255)

class ProvisionRequest(BaseModel):
    login_id: str = Field(min_length=8, max_length=64, pattern=r"^PY-[A-Z0-9]+(-[A-Z0-9]+){1,4}$")
    full_name: str = Field(min_length=2, max_length=160)
    facility_id: UUID
    role: str
    pin: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

@router.post("/login")
def login(payload: LoginRequest, request: Request):
    login_id = payload.login_id.upper()
    now = time.time()
    
    # Check rate limit and lockout state
    attempts = [t for t in _failed_attempts[login_id] if now - t <= WINDOW_SECONDS]
    _failed_attempts[login_id] = attempts
    if len(attempts) >= MAX_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many failed attempts. Account temporarily locked. Try again in {int(WINDOW_SECONDS / 60)} minutes.",
        )

    db = supabase_admin()
    profile = (
        db.table("user_profiles")
        .select("user_id,login_id,full_name,is_active,account_status,must_change_pin,internal_auth_email")
        .eq("login_id", login_id)
        .maybe_single()
        .execute()
        .data
    )

    if not profile or not profile.get("is_active", False):
        _failed_attempts[login_id].append(now)
        raise HTTPException(status_code=401, detail="Invalid ID or PIN")

    account_status = profile.get("account_status", "pending")
    if account_status == "suspended":
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail="Account is locked due to security policy. Contact your facility administrator to reactivate.",
        )
    if account_status != "active":
        raise HTTPException(status_code=403, detail=f"Account is {account_status}. Access not permitted.")

    email = profile.get("internal_auth_email") or _internal_email(profile["user_id"])

    try:
        auth = _client().auth.sign_in_with_password({"email": email, "password": payload.pin})
        # Reset failed attempts upon successful authentication
        _failed_attempts.pop(login_id, None)

        assignments = (
            db.table("user_facility_assignments")
            .select("facility_id,role,is_active,facilities(id,name,facility_type,facility_code)")
            .eq("user_id", profile["user_id"])
            .eq("is_active", True)
            .execute()
            .data
            or []
        )
        if not assignments:
            raise HTTPException(status_code=403, detail="No active facility assignment found for this worker")

        return {
            "access_token": auth.session.access_token,
            "refresh_token": auth.session.refresh_token,
            "token_type": "bearer",
            "expires_in": auth.session.expires_in,
            "user": {
                "id": profile["user_id"],
                "login_id": profile["login_id"],
                "full_name": profile["full_name"],
                "must_change_pin": profile.get("must_change_pin", True),
                "assignments": assignments,
            },
        }
    except HTTPException:
        raise
    except Exception:
        _failed_attempts[login_id].append(now)
        if len(_failed_attempts[login_id]) >= MAX_ATTEMPTS:
            # Persist suspension in DB upon reaching threshold
            try:
                db.table("user_profiles").update({"account_status": "suspended"}).eq("user_id", profile["user_id"]).execute()
                db.table("account_provisioning_audit").insert({
                    "target_user_id": profile["user_id"],
                    "action": "deactivated",
                    "details": {"reason": "exceeded_failed_pin_threshold", "attempts": MAX_ATTEMPTS},
                }).execute()
            except Exception:
                pass
            raise HTTPException(
                status_code=status.HTTP_423_LOCKED,
                detail="Account has been locked after 5 failed attempts. Contact your facility administrator.",
            )
        raise HTTPException(status_code=401, detail="Invalid ID or PIN")

@router.post("/refresh")
def refresh_session(payload: RefreshRequest):
    try:
        auth = _client().auth.refresh_session(payload.refresh_token)
        if not auth or not auth.session:
            raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
        return {
            "access_token": auth.session.access_token,
            "refresh_token": auth.session.refresh_token,
            "token_type": "bearer",
            "expires_in": auth.session.expires_in,
        }
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Could not refresh session. Please sign in again.") from exc

@router.post("/change-pin")
def change_pin(payload: ChangePinRequest, user: dict = Depends(current_user)):
    user_id = user["sub"]
    if payload.current_pin == payload.new_pin:
        raise HTTPException(status_code=422, detail="New PIN cannot be identical to the current PIN")
    if payload.new_pin in WEAK_PINS:
        raise HTTPException(status_code=422, detail="New PIN is too predictable. Choose a less common 6-digit PIN.")

    db = supabase_admin()
    profile = db.table("user_profiles").select("user_id,internal_auth_email").eq("user_id", user_id).maybe_single().execute().data
    if not profile:
        raise HTTPException(status_code=404, detail="User profile not found")

    email = profile.get("internal_auth_email") or _internal_email(user_id)

    # Verify current PIN
    try:
        _client().auth.sign_in_with_password({"email": email, "password": payload.current_pin})
    except Exception:
        raise HTTPException(status_code=401, detail="Current PIN is incorrect")

    # Update password in Supabase Auth
    try:
        _client().auth.admin.update_user_by_id(user_id, {"password": payload.new_pin})
        db.table("user_profiles").update({
            "must_change_pin": False,
            "pin_changed_at": datetime.now(timezone.utc).isoformat(),
        }).eq("user_id", user_id).execute()

        db.table("audit_logs").insert({
            "actor_user_id": user_id,
            "action": "pin_changed",
            "entity_type": "user_profile",
            "entity_id": user_id,
            "metadata": {"timestamp": datetime.now(timezone.utc).isoformat()},
        }).execute()

        return {"status": "success", "message": "PIN updated successfully", "must_change_pin": False}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Failed to update PIN: {str(exc)[:120]}")

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
            if not af:
                continue
            if ar["role"] in ("THC_ADMIN", "THC_MO") and af["facility_type"] == "THC" and target.get("facility_type") == "CHC" and target.get("parent_facility_id") == af["id"] and role in ("CHC_ADMIN", "CHC_MO"):
                permitted = True
            if ar["role"] in ("CHC_ADMIN", "CHC_MO") and af["facility_type"] == "CHC" and target.get("facility_type") == "PHC" and target.get("parent_facility_id") == af["id"] and role == "PHC_MO":
                permitted = True
            if ar["role"] == "PHC_MO" and af["facility_type"] == "PHC" and target.get("id") == af["id"] and role in ("ANM", "ASHA", "VHN"):
                permitted = True

    if not permitted:
        raise HTTPException(status_code=403, detail="You cannot provision this role at the selected facility")

    allowed = {"ANM", "ASHA", "VHN", "PHC_MO", "CHC_MO", "CHC_ADMIN", "THC_MO", "THC_ADMIN", "RECEIVING_STAFF", "SUPERVISOR"}
    if role not in allowed:
        raise HTTPException(status_code=422, detail="Unsupported role")

    existing = db.table("user_profiles").select("user_id").eq("login_id", payload.login_id.upper()).maybe_single().execute().data
    if existing:
        raise HTTPException(status_code=409, detail="Login ID already exists")

    auth_user = None
    try:
        auth_email = f"{uuid.uuid4()}@{settings.internal_auth_domain}"
        created = _client().auth.admin.create_user({
            "email": auth_email,
            "password": payload.pin,
            "email_confirm": True,
            "user_metadata": {"login_id": payload.login_id.upper()},
        })
        auth_user = created.user

        db.table("user_profiles").insert({
            "user_id": auth_user.id,
            "full_name": payload.full_name,
            "login_id": payload.login_id.upper(),
            "is_active": True,
            "account_status": "active",
            "must_change_pin": True,
            "internal_auth_email": auth_email,
        }).execute()

        db.table("user_facility_assignments").insert({
            "user_id": auth_user.id,
            "facility_id": str(payload.facility_id),
            "role": role,
            "is_active": True,
        }).execute()

        # Corrected action to match CHECK constraint ('created', 'role_assigned', etc.)
        db.table("account_provisioning_audit").insert({
            "actor_user_id": actor_id,
            "target_user_id": auth_user.id,
            "facility_id": str(payload.facility_id),
            "assigned_role": role,
            "action": "created",
            "details": {"provisioned_by": actor_id, "role": role, "timestamp": datetime.now(timezone.utc).isoformat()},
        }).execute()

        return {
            "user_id": auth_user.id,
            "login_id": payload.login_id.upper(),
            "role": role,
            "status": "active",
            "must_change_pin": True,
        }
    except Exception as exc:
        if auth_user:
            try:
                _client().auth.admin.delete_user(auth_user.id)
            except Exception:
                pass
        raise HTTPException(status_code=400, detail=f"Account provisioning failed: {str(exc)[:180]}")

@router.post("/users/{target_user_id}/status")
def update_user_status(target_user_id: UUID, payload: UserStatusRequest, actor: dict = Depends(current_user)):
    db = supabase_admin()
    actor_id = actor["sub"]
    actor_assignments = db.table("user_facility_assignments").select("role").eq("user_id", actor_id).eq("is_active", True).execute().data or []
    is_admin = any(a["role"] in ("SYSTEM_ADMIN", "THC_ADMIN", "CHC_ADMIN") for a in actor_assignments)
    if not is_admin:
        raise HTTPException(status_code=403, detail="Only facility or system administrators can update account status")

    target_user_id_str = str(target_user_id)
    target_profile = db.table("user_profiles").select("user_id,login_id,account_status").eq("user_id", target_user_id_str).maybe_single().execute().data
    if not target_profile:
        raise HTTPException(status_code=404, detail="User not found")

    action = "reactivated" if payload.status == "active" else "deactivated"
    db.table("user_profiles").update({"account_status": payload.status}).eq("user_id", target_user_id_str).execute()

    db.table("account_provisioning_audit").insert({
        "actor_user_id": actor_id,
        "target_user_id": target_user_id_str,
        "action": action,
        "details": {"new_status": payload.status, "reason": payload.reason},
    }).execute()

    # Reset in-memory failed attempts if reactivating
    if payload.status == "active" and target_profile.get("login_id"):
        _failed_attempts.pop(target_profile["login_id"], None)

    return {"user_id": target_user_id_str, "status": payload.status, "action": action}
