-- Preeclampsia 360 | Migration 0003: Staff ID + PIN identity foundation
-- Run once, after migrations 0001 and 0002.
-- No personal email address or phone number is required for staff login.
-- PINs are NEVER stored in PostgreSQL by this migration. Supabase Auth stores
-- the password hash; FastAPI performs ID-to-internal-Auth-identity resolution.

begin;

-- Stable facility codes such as PY-CHC-01 and PY-PHC-01.
alter table public.facilities
  add column if not exists facility_code text;

create unique index if not exists facilities_facility_code_uidx
  on public.facilities (upper(facility_code))
  where facility_code is not null;

-- Unique staff login IDs such as PY-PHC-ANM-MUTHIALPET.
alter table public.user_profiles
  add column if not exists login_id text,
  add column if not exists account_status text not null default 'pending'
    check (account_status in ('pending','active','suspended','deactivated')),
  add column if not exists pin_changed_at timestamptz,
  add column if not exists must_change_pin boolean not null default true;

create unique index if not exists user_profiles_login_id_uidx
  on public.user_profiles (upper(login_id))
  where login_id is not null;

-- Login IDs are identifiers, not secrets. Restrict the format to uppercase
-- letters, digits and hyphens; require a PY- prefix for this initial deployment.
alter table public.user_profiles
  add constraint user_profiles_login_id_format_chk
  check (
    login_id is null
    or (
      login_id = upper(login_id)
      and login_id ~ '^PY-[A-Z0-9]+(-[A-Z0-9]+){1,4}$'
      and length(login_id) between 8 and 64
    )
  );

-- Enforce at most one active ANM and one active ASHA assignment per PHC.
-- This does not force a PHC to have both accounts immediately; provisioning
-- can create them as staffing is completed.
create unique index if not exists one_active_anm_per_phc_uidx
  on public.user_facility_assignments (facility_id)
  where role = 'ANM' and is_active = true;

create unique index if not exists one_active_asha_per_phc_uidx
  on public.user_facility_assignments (facility_id)
  where role = 'ASHA' and is_active = true;

-- Validate role/facility combinations and the single-worker staffing rule.
create or replace function public.validate_user_facility_assignment()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare target_type public.facility_type;
begin
  select facility_type into target_type
  from public.facilities
  where id = new.facility_id and is_active = true;

  if target_type is null then
    raise exception 'Target facility does not exist or is inactive';
  end if;

  if new.role in ('ANM','ASHA','VHN','PHC_MO') and target_type <> 'PHC' then
    raise exception 'This role must be assigned to a PHC';
  elsif new.role in ('CHC_MO','CHC_ADMIN') and target_type <> 'CHC' then
    raise exception 'This role must be assigned to a CHC';
  elsif new.role in ('THC_MO','THC_ADMIN') and target_type <> 'THC' then
    raise exception 'This role must be assigned to a THC';
  elsif new.role = 'RECEIVING_STAFF' and target_type <> 'HOSPITAL' then
    raise exception 'Receiving staff must be assigned to a hospital';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_user_facility_assignment
  on public.user_facility_assignments;
create trigger trg_validate_user_facility_assignment
before insert or update of facility_id, role, is_active
on public.user_facility_assignments
for each row execute function public.validate_user_facility_assignment();

-- The login ID is not a credential. Keep profiles and assignments unavailable
-- for anonymous direct access. FastAPI uses service_role after authenticating.
revoke all on table public.user_profiles from anon;
revoke all on table public.user_facility_assignments from anon;

commit;

-- IMPORTANT IMPLEMENTATION NOTES:
-- 1. FastAPI creates the Supabase Auth user with a generated internal email alias
--    and the PIN as the Auth password. The alias is never shown to the worker.
-- 2. FastAPI resolves login_id -> user_profiles.user_id, then verifies account_status
--    and active facility assignment before completing sign-in.
-- 3. Never store a raw PIN, reversible PIN, or client-side PIN hash in this database.
-- 4. Enforce server-side throttling/lockout by login ID and source IP. A six-digit
--    PIN has only 1,000,000 combinations; use strict attempt limits and audit logs.
-- 5. Do not expose Supabase service_role credentials to Flutter/Web clients.
-- 6. Do not enable public signup. Only authorised provisioning endpoints create users.
-- 7. Supabase Auth email/password sign-in still uses an internal synthetic email
--    behind the scenes; the worker enters only their staff ID and PIN.
