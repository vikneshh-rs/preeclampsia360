-- Preeclampsia 360 | Migration 0005: One-time System Administrator bootstrap guard
-- Safe to run after migrations 0001-0003. Also adds the internal Auth alias column
-- if migration 0004 has not yet been applied.
begin;

alter table public.user_profiles
  add column if not exists internal_auth_email text;

create unique index if not exists user_profiles_internal_auth_email_uidx
  on public.user_profiles(internal_auth_email)
  where internal_auth_email is not null;

create table if not exists public.system_bootstrap_state (
  singleton boolean primary key default true check (singleton = true),
  status text not null check (status in ('in_progress','completed')),
  claim_token uuid not null,
  claimed_by text not null default 'operator_cli',
  claimed_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table public.system_bootstrap_state enable row level security;
revoke all on public.system_bootstrap_state from public, anon, authenticated;
grant select, insert, update, delete on public.system_bootstrap_state to service_role;

-- Finalize all public-schema writes in one transaction after the Auth identity exists.
create or replace function public.complete_system_admin_bootstrap(
  p_claim_token uuid,
  p_user_id uuid,
  p_login_id text,
  p_full_name text,
  p_internal_auth_email text,
  p_facility_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_facility_type public.facility_type;
begin
  if p_login_id <> 'PY-SYS-ADMIN-001' then
    raise exception 'Unexpected bootstrap login ID';
  end if;
  if length(trim(p_full_name)) < 2 then
    raise exception 'Administrator name is required';
  end if;
  if p_internal_auth_email is null or position('@' in p_internal_auth_email) < 2 then
    raise exception 'Internal Auth identity is invalid';
  end if;

  perform 1 from public.system_bootstrap_state
   where singleton = true and status = 'in_progress' and claim_token = p_claim_token
   for update;
  if not found then
    raise exception 'Bootstrap claim is missing, expired, or already completed';
  end if;

  if exists (
    select 1 from public.user_facility_assignments
    where role = 'SYSTEM_ADMIN' and is_active = true
  ) then
    raise exception 'An active System Administrator already exists';
  end if;
  if exists (select 1 from public.user_profiles where upper(login_id) = p_login_id) then
    raise exception 'System Administrator login ID already exists';
  end if;

  select facility_type into v_facility_type
    from public.facilities
   where id = p_facility_id and is_active = true;
  if v_facility_type is distinct from 'THC'::public.facility_type then
    raise exception 'The System Administrator must be anchored to an active THC facility';
  end if;

  insert into public.user_profiles (
    user_id, full_name, preferred_language, is_active,
    login_id, account_status, must_change_pin, internal_auth_email
  ) values (
    p_user_id, trim(p_full_name), 'en', true,
    p_login_id, 'active', true, p_internal_auth_email
  );

  insert into public.user_facility_assignments (user_id, facility_id, role, is_active)
  values (p_user_id, p_facility_id, 'SYSTEM_ADMIN', true);

  insert into public.account_provisioning_audit (
    actor_user_id, target_user_id, facility_id, assigned_role, action, details
  ) values (
    p_user_id, p_user_id, p_facility_id, 'SYSTEM_ADMIN', 'created',
    jsonb_build_object('bootstrap', true, 'login_id', p_login_id, 'method', 'trusted_cli')
  );

  update public.system_bootstrap_state
     set status = 'completed', completed_at = now()
   where singleton = true and claim_token = p_claim_token;
end;
$$;

revoke all on function public.complete_system_admin_bootstrap(uuid,uuid,text,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.complete_system_admin_bootstrap(uuid,uuid,text,text,text,uuid)
  to service_role;

commit;
