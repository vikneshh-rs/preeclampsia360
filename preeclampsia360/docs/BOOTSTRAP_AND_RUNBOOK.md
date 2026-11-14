# One-time System Administrator bootstrap

This is a trusted-operator CLI operation. It is **not** a public API endpoint and must never run in Flutter, a browser, or an untrusted machine.

## Prerequisites

1. Migrations `0001`, `0002`, `0003`, and `0005_system_admin_bootstrap.sql` have succeeded. Migration 0005 is idempotent and adds `internal_auth_email` if it is not already present (migration 0004 also adds it).
2. At least one active THC facility exists with a unique `facility_code`, e.g. `PY-THC-01`.
3. Python dependencies from `backend/requirements.txt` are installed.
4. You have the Supabase project URL and **service-role secret** available only in a trusted terminal's environment. Never paste it into chat, source control, Flutter, or a public deployment variable exposed to the client.

## Run

From the `preeclampsia360/backend` directory:

```bash
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVER_SIDE_SERVICE_ROLE_SECRET"
export INTERNAL_AUTH_DOMAIN="staff.preeclampsia360.invalid"
python scripts/bootstrap_admin.py
```

The script prompts for the administrator's name, the facility code of the existing THC to use as the administrator's anchor assignment, and a temporary six-digit PIN (entered without echo). It always uses `PY-SYS-ADMIN-001` as the first administrator ID.

## Safety behaviour

- Refuses to run if an active `SYSTEM_ADMIN` assignment already exists or the reserved login ID is taken.
- Acquires a singleton database bootstrap lock to prevent two operators from racing.
- Requires an active facility of type `THC`.
- Creates a confirmed Supabase Auth identity with a random internal email alias; workers never enter or see this alias.
- Calls `complete_system_admin_bootstrap` to atomically create the profile, SYSTEM_ADMIN facility assignment, audit row, and mark the bootstrap complete.
- If finalization fails, it attempts to delete the just-created Auth identity and release the in-progress claim.
- Does not store the PIN in public tables. Supabase Auth stores the password hash.

If the process is interrupted after acquiring the lock, inspect `system_bootstrap_state`, `auth.users`, `user_profiles`, and `user_facility_assignments` before making any change. Do not blindly delete a completed lock or rerun the bootstrap. A trusted operator must establish that no administrator was created before manually clearing a stale `in_progress` claim.

## Important follow-up

The bootstrap marks `must_change_pin = true`. The normal application must enforce a PIN-change step before allowing routine use. Do not treat the bootstrap as complete operational authentication until the PIN-change endpoint/UI, rate limiting, lockout persistence, and live login tests have been implemented and reviewed. Six-digit PINs are low entropy; rate limits must be shared across API instances (not only in-memory).

The System Administrator is assigned to the selected THC as an anchor because the current schema represents roles through `user_facility_assignments`. The SYSTEM_ADMIN role is globally privileged in backend authorization and must not be treated as a normal THC clinical account.
