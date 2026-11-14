"""Create the one-time Preeclampsia 360 System Administrator.

Run only from a trusted operator terminal after applying migrations 0001-0003
and 0005. The script never prints the service-role key or PIN.
"""
from __future__ import annotations

import getpass
import os
import re
import sys
import uuid
from typing import Any

from supabase import create_client

LOGIN_ID = "PY-SYS-ADMIN-001"
LOGIN_ID_PATTERN = re.compile(r"^PY-SYS-ADMIN-001$")


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def release_claim(db: Any, token: str) -> None:
    try:
        db.table("system_bootstrap_state").delete().eq("singleton", True).eq("claim_token", token).eq("status", "in_progress").execute()
    except Exception:
        # A stale in_progress claim can be removed manually by a trusted DB operator
        # after confirming no System Administrator was created.
        print("WARNING: Could not release the bootstrap claim. Inspect system_bootstrap_state before retrying.", file=sys.stderr)


def main() -> int:
    supabase_url = required_env("SUPABASE_URL")
    service_key = required_env("SUPABASE_SERVICE_ROLE_KEY")
    internal_domain = os.getenv("INTERNAL_AUTH_DOMAIN", "staff.preeclampsia360.invalid").strip().lower()
    if not internal_domain or "@" in internal_domain or "/" in internal_domain:
        raise SystemExit("INTERNAL_AUTH_DOMAIN must be a domain only, without @ or path")

    db = create_client(supabase_url, service_key)

    # Refuse if any administrator already exists, even if this script was run before.
    existing_admin = (
        db.table("user_facility_assignments")
        .select("id")
        .eq("role", "SYSTEM_ADMIN")
        .eq("is_active", True)
        .limit(1)
        .execute()
        .data
    ) or []
    if existing_admin:
        raise SystemExit("An active SYSTEM_ADMIN already exists. Bootstrap is one-time and will not run again.")

    existing_login = (
        db.table("user_profiles")
        .select("user_id")
        .eq("login_id", LOGIN_ID)
        .limit(1)
        .execute()
        .data
    ) or []
    if existing_login:
        raise SystemExit(f"{LOGIN_ID} already exists. Refusing to create a duplicate administrator.")

    print("Preeclampsia 360 — One-time System Administrator bootstrap")
    print("The administrator is globally privileged; anchor it to the appropriate active THC.\n")
    full_name = input("Administrator full name: ").strip()
    if len(full_name) < 2:
        raise SystemExit("Enter a valid full name.")

    facility_code = input("Existing THC facility code (for example PY-THC-01): ").strip().upper()
    if not re.fullmatch(r"PY-[A-Z0-9-]{3,40}", facility_code):
        raise SystemExit("Facility code format is invalid.")
    facility_rows = (
        db.table("facilities")
        .select("id,name,facility_type,facility_code,is_active")
        .eq("facility_code", facility_code)
        .eq("is_active", True)
        .limit(2)
        .execute()
        .data
    ) or []
    if len(facility_rows) != 1 or facility_rows[0].get("facility_type") != "THC":
        raise SystemExit("That code must identify exactly one active THC facility. Create the THC first, then retry.")
    facility = facility_rows[0]
    print(f"Selected anchor: {facility['name']} ({facility['facility_code']})")

    pin = getpass.getpass("Temporary 6-digit PIN: ")
    if not re.fullmatch(r"[0-9]{6}", pin):
        raise SystemExit("PIN must contain exactly six digits.")
    if pin in {"000000", "111111", "123456", "654321", "222222", "333333", "444444", "555555", "666666", "777777", "888888", "999999"}:
        raise SystemExit("Choose a less predictable six-digit temporary PIN.")
    confirm = getpass.getpass("Confirm temporary PIN: ")
    if pin != confirm:
        raise SystemExit("PIN confirmation does not match.")

    claim_token = str(uuid.uuid4())
    claim = db.table("system_bootstrap_state").insert({
        "singleton": True,
        "status": "in_progress",
        "claim_token": claim_token,
        "claimed_by": os.getenv("USER", "operator_cli")[:120],
    }).execute()
    if not claim.data:
        raise SystemExit("Could not acquire the one-time bootstrap lock. Check system_bootstrap_state; it may already be claimed or completed.")

    internal_email = f"{uuid.uuid4()}@{internal_domain}"
    auth_user = None
    try:
        created = db.auth.admin.create_user({
            "email": internal_email,
            "password": pin,
            "email_confirm": True,
            "user_metadata": {
                "login_id": LOGIN_ID,
                "account_type": "system_administrator",
                "must_change_pin": True,
            },
        })
        auth_user = created.user
        if auth_user is None:
            raise RuntimeError("Supabase Auth did not return the created user")

        db.rpc("complete_system_admin_bootstrap", {
            "p_claim_token": claim_token,
            "p_user_id": str(auth_user.id),
            "p_login_id": LOGIN_ID,
            "p_full_name": full_name,
            "p_internal_auth_email": internal_email,
            "p_facility_id": str(facility["id"]),
        }).execute()

        print("\nBootstrap completed successfully.")
        print(f"Login ID: {LOGIN_ID}")
        print("A temporary PIN was set. Keep it private and change it immediately after the PIN-change flow is enabled.")
        print("The service-role key was not written to the database or printed.")
        return 0
    except Exception as exc:
        if auth_user is not None:
            try:
                db.auth.admin.delete_user(str(auth_user.id))
            except Exception:
                print("WARNING: Auth-user cleanup failed. Check Supabase Auth users before retrying.", file=sys.stderr)
        release_claim(db, claim_token)
        raise SystemExit(f"Bootstrap failed; no success is claimed. Review the error and database state: {str(exc)[:240]}") from exc


if __name__ == "__main__":
    raise SystemExit(main())
