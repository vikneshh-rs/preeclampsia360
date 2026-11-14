"""Seed demonstration facilities and healthcare worker accounts for Preeclampsia 360."""
import os, sys, uuid
from supabase import create_client

def seed():
    supabase_url = os.getenv("SUPABASE_URL", "https://ymkqatqxuohrwlfajpdc.supabase.co")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlta3FhdHF4dW9ocndsZmFqcGRjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5NDU5MDM3MywiZXhwIjoyMTEwMTY2MzczfQ.6JjLHexnkl7B3jzE5qi9C3i0hzAqMPxePRkKSwrFRWc")
    internal_domain = os.getenv("INTERNAL_AUTH_DOMAIN", "staff.preeclampsia360.invalid")

    client = create_client(supabase_url, service_key)

    print("Checking facilities...")
    existing_facs = client.table("facilities").select("id,facility_code").execute().data or []
    code_to_id = {f.get("facility_code"): f["id"] for f in existing_facs}

    # 1. Seed Facilities (THC -> CHC -> PHC)
    if "PY-THC-01" not in code_to_id:
        thc = client.table("facilities").insert({
            "name": "Rajiv Gandhi Women and Children Hospital",
            "facility_type": "THC",
            "facility_code": "PY-THC-01",
            "district_id": "PUDUCHERRY",
            "address": "Ellaipillaichavady, Puducherry",
            "is_active": True,
        }).execute().data[0]
        code_to_id["PY-THC-01"] = thc["id"]
        print("Created THC:", thc["name"])

    thc_id = code_to_id["PY-THC-01"]

    if "PY-CHC-01" not in code_to_id:
        chc = client.table("facilities").insert({
            "name": "Karikalampakkam CHC",
            "facility_type": "CHC",
            "facility_code": "PY-CHC-01",
            "parent_facility_id": thc_id,
            "district_id": "PUDUCHERRY",
            "address": "Karikalampakkam, Puducherry",
            "is_active": True,
        }).execute().data[0]
        code_to_id["PY-CHC-01"] = chc["id"]
        print("Created CHC:", chc["name"])

    chc_id = code_to_id["PY-CHC-01"]

    if "PY-PHC-01" not in code_to_id:
        phc = client.table("facilities").insert({
            "name": "Muthialpet PHC",
            "facility_type": "PHC",
            "facility_code": "PY-PHC-01",
            "parent_facility_id": chc_id,
            "district_id": "PUDUCHERRY",
            "address": "Muthialpet, Puducherry",
            "is_active": True,
        }).execute().data[0]
        code_to_id["PY-PHC-01"] = phc["id"]
        print("Created PHC:", phc["name"])

    phc_id = code_to_id["PY-PHC-01"]

    # 2. Seed Users
    users_to_seed = [
        {
            "login_id": "PY-PHC-ANM-MUTHIALPET",
            "full_name": "Ananya Sharma (ANM)",
            "role": "ANM",
            "facility_id": phc_id,
            "pin": "123456",
        },
        {
            "login_id": "PY-PHC-ASHA-001",
            "full_name": "Lakshmi Priya (ASHA)",
            "role": "ASHA",
            "facility_id": phc_id,
            "pin": "123456",
        },
        {
            "login_id": "PY-PHC-MO-001",
            "full_name": "Dr. K. Rajesh (PHC MO)",
            "role": "PHC_MO",
            "facility_id": phc_id,
            "pin": "123456",
        },
        {
            "login_id": "PY-THC-MO-001",
            "full_name": "Dr. V. Meenakshi (THC MO)",
            "role": "THC_MO",
            "facility_id": thc_id,
            "pin": "123456",
        },
    ]

    for u in users_to_seed:
        login_id = u["login_id"]
        res = client.table("user_profiles").select("user_id").eq("login_id", login_id).execute()
        existing = res.data[0] if (res and res.data) else None
        if existing:
            print(f"User {login_id} already exists.")
            continue

        email = f"{uuid.uuid4().hex}@{internal_domain}"
        print(f"Provisioning {login_id} ({u['full_name']})...")
        auth_user = client.auth.admin.create_user({
            "email": email,
            "password": u["pin"],
            "email_confirm": True,
            "user_metadata": {"login_id": login_id},
        }).user

        client.table("user_profiles").insert({
            "user_id": auth_user.id,
            "full_name": u["full_name"],
            "login_id": login_id,
            "is_active": True,
            "account_status": "active",
            "must_change_pin": False,
            "internal_auth_email": email,
        }).execute()

        client.table("user_facility_assignments").insert({
            "user_id": auth_user.id,
            "facility_id": u["facility_id"],
            "role": u["role"],
            "is_active": True,
        }).execute()

        client.table("account_provisioning_audit").insert({
            "actor_user_id": auth_user.id,
            "target_user_id": auth_user.id,
            "facility_id": u["facility_id"],
            "assigned_role": u["role"],
            "action": "created",
            "details": {"seeded": True},
        }).execute()

        print(f"Successfully created {login_id} with PIN {u['pin']}!")

    print("\nSeed completed successfully!")

if __name__ == "__main__":
    seed()
