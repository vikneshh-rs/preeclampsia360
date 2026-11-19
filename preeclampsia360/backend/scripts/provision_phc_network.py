"""
Provision all Puducherry Primary Health Centres (PHCs) and Healthcare Worker Accounts.
Generates:
  - PHC Facility Record in public.facilities
  - PHC Medical Officer Login: PY-PHC-[CODE] (e.g. PY-PHC-MUTH)
  - ANM Login:                PY-PHC-ANM-[CODE] (e.g. PY-PHC-ANM-MUTH)
Default PIN for all accounts: 123456
"""

import os
import uuid
from supabase import create_client

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://ymkqatqxuohrwlfajpdc.supabase.co")
SERVICE_KEY = os.getenv(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlta3FhdHF4dW9ocndsZmFqcGRjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5NDU5MDM3MywiZXhwIjoyMTEwMTY2MzczfQ.6JjLHexnkl7B3jzE5qi9C3i0hzAqMPxePRkKSwrFRWc"
)
INTERNAL_DOMAIN = os.getenv("INTERNAL_AUTH_DOMAIN", "staff.preeclampsia360.invalid")
DEFAULT_PIN = "123456"

# List of 27 Puducherry District Primary Health Centres
PHC_LIST = [
    {"name": "Muthialpet Primary Health Centre", "code": "MUTH", "address": "Muthialpet, Puducherry"},
    {"name": "Lawspet Primary Health Centre", "code": "LAWS", "address": "Lawspet, Puducherry"},
    {"name": "Reddiarpalayam Primary Health Centre", "code": "REDD", "address": "Reddiarpalayam, Puducherry"},
    {"name": "Mudaliarpet Primary Health Centre", "code": "MUDA", "address": "Mudaliarpet, Puducherry"},
    {"name": "Murungapakkam Primary Health Centre", "code": "MURU", "address": "Murungapakkam, Puducherry"},
    {"name": "Mettupalayam Primary Health Centre", "code": "METT", "address": "Mettupalayam, Puducherry"},
    {"name": "Dubrayapet Primary Health Centre", "code": "DUBR", "address": "Dubrayapet, Puducherry"},
    {"name": "Ariankuppam Primary Health Centre", "code": "ARIA", "address": "Ariankuppam, Puducherry"},
    {"name": "Gorimedu Primary Health Centre", "code": "GORI", "address": "Gorimedu, Puducherry"},
    {"name": "Kalapet Primary Health Centre", "code": "KALA", "address": "Kalapet, Puducherry"},
    {"name": "Kosapalayam Primary Health Centre", "code": "KOSA", "address": "Kosapalayam, Puducherry"},
    {"name": "Abishegapakkam Primary Health Centre", "code": "ABIS", "address": "Abishegapakkam, Puducherry"},
    {"name": "Ariyur Primary Health Centre", "code": "ARIY", "address": "Ariyur, Puducherry"},
    {"name": "Bahour Primary Health Centre", "code": "BAHO", "address": "Bahour, Puducherry"},
    {"name": "Karayamputhur Primary Health Centre", "code": "KARA", "address": "Karayamputhur, Puducherry"},
    {"name": "Katterikuppam Primary Health Centre", "code": "KATT", "address": "Katterikuppam, Puducherry"},
    {"name": "Kirumampakkam Primary Health Centre", "code": "KIRU", "address": "Kirumampakkam, Puducherry"},
    {"name": "Koodapakkam Primary Health Centre", "code": "KOOD", "address": "Koodapakkam, Puducherry"},
    {"name": "Nettapakkam Primary Health Centre", "code": "NETT", "address": "Nettapakkam, Puducherry"},
    {"name": "Sedarapet Primary Health Centre", "code": "SEDA", "address": "Sedarapet, Puducherry"},
    {"name": "Sooramangalam Primary Health Centre", "code": "SOOR", "address": "Sooramangalam, Puducherry"},
    {"name": "Sorapet Primary Health Centre", "code": "SORA", "address": "Sorapet, Puducherry"},
    {"name": "Thavalakuppam Primary Health Centre", "code": "THAV", "address": "Thavalakuppam, Puducherry"},
    {"name": "Thirubuvanai Primary Health Centre", "code": "THIR", "address": "Thirubuvanai, Puducherry"},
    {"name": "Thirukkanur Primary Health Centre", "code": "THIK", "address": "Thirukkanur, Puducherry"},
    {"name": "Villianur Primary Health Centre", "code": "VILL", "address": "Villianur, Puducherry"},
    {"name": "Madagadipet Primary Health Centre", "code": "MADA", "address": "Madagadipet, Puducherry"},
]

def provision_network():
    client = create_client(SUPABASE_URL, SERVICE_KEY)
    print("Connected to Supabase. Fetching existing facilities and users...")

    # Fetch existing facilities
    fac_res = client.table("facilities").select("id,facility_code").execute().data or []
    fac_map = {f["facility_code"]: f["id"] for f in fac_res}

    # Fetch existing user profiles
    users_res = client.table("user_profiles").select("user_id,login_id").execute().data or []
    existing_logins = {u["login_id"] for u in users_res if u.get("login_id")}

    # 1. Seed Facilities
    print(f"\n--- Checking {len(PHC_LIST)} PHC Facilities ---")
    for phc in PHC_LIST:
        f_code = f"PY-PHC-{phc['code']}"
        if f_code not in fac_map:
            try:
                # Link to existing CHC or null
                new_fac = client.table("facilities").insert({
                    "name": phc["name"],
                    "facility_type": "PHC",
                    "facility_code": f_code,
                    "district_id": "PUDUCHERRY",
                    "address": phc["address"],
                    "parent_facility_id": "11049b35-4fe8-4027-b50b-0e986db7d666", # Karikalampakkam CHC
                    "is_active": True,
                }).execute().data[0]
                fac_map[f_code] = new_fac["id"]
                print(f"Created Facility: {phc['name']} ({f_code})")
            except Exception as e:
                print(f"Failed to create facility {f_code}: {e}")
        else:
            print(f"Facility already exists: {f_code}")

    # 2. Provision Users for each PHC
    #   A) PHC MO: PY-PHC-[CODE]
    #   B) ANM:    PY-PHC-ANM-[CODE]
    print(f"\n--- Provisioning User Logins (PIN: {DEFAULT_PIN}) ---")
    created_count = 0

    for phc in PHC_LIST:
        f_code = f"PY-PHC-{phc['code']}"
        fac_id = fac_map.get(f_code)
        if not fac_id:
            print(f"Skipping {phc['code']}: facility not found.")
            continue

        users_to_create = [
            # 1) PHC MO / Admin
            {
                "login_id": f"PY-PHC-{phc['code']}",
                "full_name": f"Dr. MO ({phc['name'].replace(' Primary Health Centre', '')})",
                "role": "PHC_MO",
            },
            # 2) ANM
            {
                "login_id": f"PY-PHC-ANM-{phc['code']}",
                "full_name": f"ANM ({phc['name'].replace(' Primary Health Centre', '')})",
                "role": "ANM",
            },
        ]

        for u in users_to_create:
            login_id = u["login_id"]
            if login_id in existing_logins:
                # print(f"Login {login_id} already exists.")
                continue

            try:
                email = f"{uuid.uuid4().hex}@{INTERNAL_DOMAIN}"
                auth_user = client.auth.admin.create_user({
                    "email": email,
                    "password": DEFAULT_PIN,
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
                    "facility_id": fac_id,
                    "role": u["role"],
                    "is_active": True,
                }).execute()

                existing_logins.add(login_id)
                created_count += 1
                print(f"Created: {login_id.ljust(18)} | {u['role'].ljust(8)} | Facility: {phc['code']}")
            except Exception as e:
                print(f"Error provisioning {login_id}: {e}")

    print(f"\n[DONE] Provisioned {created_count} new healthcare accounts.")

if __name__ == "__main__":
    provision_network()

