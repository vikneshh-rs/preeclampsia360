# ID + PIN authentication

Workers sign in using a staff ID (for example `PY-PHC-ANM-MUTHIALPET`) and a six-digit PIN. No personal email or phone number is required. Supabase Auth remains the credential/session provider; each Auth user receives a random synthetic email address under `INTERNAL_AUTH_DOMAIN`. The synthetic address is never shown to the worker.

## Required server secrets

Set `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWKS_URL`, and `INTERNAL_AUTH_DOMAIN` in the backend environment. Never place the service-role key in Flutter, source control, or a public build. `SUPABASE_SERVICE_ROLE_KEY` is available only to FastAPI.

## Endpoints

- `POST /api/v1/auth/login` accepts `{ "login_id": "PY-...", "pin": "123456" }` and returns Supabase access/refresh tokens plus active assignments.
- `POST /api/v1/auth/provision` creates an account. In this initial implementation it is restricted to an existing `SYSTEM_ADMIN` assignment. Hierarchical THC/CHC/PHC provisioning is intentionally not enabled until the facility ancestry authorization tests are implemented.

## Bootstrap limitation

There is no public bootstrap endpoint. Create the first system administrator through a one-time, operator-controlled bootstrap script after creating the first Supabase Auth user and facility assignment. Never enable public signup.

## Security notes

- Six-digit PINs have low entropy. Rate-limit login attempts at the gateway and use a shared Redis-backed limiter in production; the included in-process limiter is development-only and does not coordinate across instances.
- Add progressive lockout, monitoring and alerting before deployment.
- Force PIN change after initial activation before exposing patient data.
- Rotate/revoke refresh sessions on account suspension.
- Verify the live project JWT signing algorithm and JWKS URL.
- Test all account roles, facility scopes, RLS policies and referral access before production.
- Do not store raw PINs or PIN hashes in application tables. Supabase Auth stores the password hash.
