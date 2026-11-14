-- Preeclampsia 360 | Migration 0002: Identity, facility hierarchy and account provisioning
-- Run once, after 0001_initial_schema.sql.
-- Account creation in Supabase Auth MUST be performed by the FastAPI backend using a
-- server-side service-role secret. Never expose that secret to Flutter or a browser.

begin;

-- 1) Enforce the approved facility tree: THC -> CHC -> PHC.
-- Hospitals are separate receiving facilities and may optionally be linked to a THC.
create or replace function public.validate_facility_hierarchy()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare parent_type public.facility_type;
begin
  if new.parent_facility_id is null then
    if new.facility_type in ('PHC','CHC') then
      raise exception 'A % must belong to its parent facility', new.facility_type;
    end if;
    return new;
  end if;

  select facility_type into parent_type
  from public.facilities
  where id = new.parent_facility_id and is_active = true;

  if parent_type is null then
    raise exception 'Parent facility does not exist or is inactive';
  end if;

  if new.facility_type = 'CHC' and parent_type <> 'THC' then
    raise exception 'A CHC must belong to a THC';
  elsif new.facility_type = 'PHC' and parent_type <> 'CHC' then
    raise exception 'A PHC must belong to a CHC';
  elsif new.facility_type = 'THC' then
    raise exception 'A THC cannot have a parent facility';
  elsif new.facility_type = 'HOSPITAL' and parent_type not in ('THC') then
    raise exception 'A linked hospital may only belong to a THC';
  end if;

  if new.parent_facility_id = new.id then
    raise exception 'A facility cannot be its own parent';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_facility_hierarchy on public.facilities;
create trigger trg_validate_facility_hierarchy
before insert or update of facility_type, parent_facility_id
on public.facilities
for each row execute function public.validate_facility_hierarchy();

-- 2) Provisioning audit trail. The backend records account creation, role changes,
-- deactivation and facility reassignment here after the Auth operation succeeds.
create table if not exists public.account_provisioning_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id),
  target_user_id uuid references auth.users(id),
  facility_id uuid references public.facilities(id),
  assigned_role public.app_role,
  action text not null check (action in ('created','role_assigned','role_revoked','deactivated','reactivated','facility_transferred')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists account_provisioning_audit_target_idx
  on public.account_provisioning_audit(target_user_id, created_at desc);
create index if not exists account_provisioning_audit_actor_idx
  on public.account_provisioning_audit(actor_user_id, created_at desc);
alter table public.account_provisioning_audit enable row level security;

-- 3) Facility scope helpers. These functions are intended for backend authorization
-- and controlled SQL policy use. They do not create Auth users or grant roles.
create or replace function public.facility_is_in_scope(
  p_scope_facility_id uuid,
  p_target_facility_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with recursive descendants(id) as (
    select id from public.facilities where id = p_scope_facility_id and is_active = true
    union all
    select f.id
    from public.facilities f
    join descendants d on f.parent_facility_id = d.id
    where f.is_active = true
  )
  select exists (
    select 1 from descendants where id = p_target_facility_id
  );
$$;

-- 4) Hierarchical account-management rules:
-- SYSTEM_ADMIN: all facilities and roles.
-- THC_MO / THC_ADMIN: create/manage CHC_MO / CHC_ADMIN at CHCs directly below their THC.
-- CHC_MO / CHC_ADMIN: create/manage PHC_MO at PHCs directly below their CHC.
-- PHC_MO: create/manage ANM, VHN and ASHA at their own PHC.
-- Patient and receiving-hospital accounts remain centrally provisioned in V1.
create or replace function public.can_manage_facility_assignment(
  p_actor_user_id uuid,
  p_target_facility_id uuid,
  p_target_role public.app_role
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_facility_assignments actor
    join public.facilities target on target.id = p_target_facility_id and target.is_active = true
    where actor.user_id = p_actor_user_id
      and actor.is_active = true
      and (
        actor.role = 'SYSTEM_ADMIN'
        or (
          actor.role in ('THC_MO','THC_ADMIN')
          and target.facility_type = 'CHC'
          and public.facility_is_in_scope(actor.facility_id, target.parent_facility_id)
          and p_target_role in ('CHC_MO','CHC_ADMIN')
        )
        or (
          actor.role in ('CHC_MO','CHC_ADMIN')
          and target.facility_type = 'PHC'
          and public.facility_is_in_scope(actor.facility_id, target.parent_facility_id)
          and p_target_role = 'PHC_MO'
        )
        or (
          actor.role = 'PHC_MO'
          and target.facility_type = 'PHC'
          and actor.facility_id = target.id
          and p_target_role in ('ANM','VHN','ASHA')
        )
      )
  );
$$;

-- 5) Backend-callable assignment validation. The backend must pass the authenticated
-- actor ID from the verified Supabase JWT, never an actor ID supplied by the client.
create or replace function public.assert_can_manage_facility_assignment(
  p_actor_user_id uuid,
  p_target_facility_id uuid,
  p_target_role public.app_role
)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.can_manage_facility_assignment(
    p_actor_user_id, p_target_facility_id, p_target_role
  ) then
    raise exception 'Not authorised to provision this role at this facility'
      using errcode = '42501';
  end if;
end;
$$;

-- Avoid exposing SECURITY DEFINER helpers to untrusted clients. FastAPI calls them
-- with its server-side service-role connection after JWT verification.
revoke all on function public.facility_is_in_scope(uuid, uuid) from public, anon, authenticated;
revoke all on function public.can_manage_facility_assignment(uuid, uuid, public.app_role) from public, anon, authenticated;
revoke all on function public.assert_can_manage_facility_assignment(uuid, uuid, public.app_role) from public, anon, authenticated;
grant execute on function public.facility_is_in_scope(uuid, uuid) to service_role;
grant execute on function public.can_manage_facility_assignment(uuid, uuid, public.app_role) to service_role;
grant execute on function public.assert_can_manage_facility_assignment(uuid, uuid, public.app_role) to service_role;

-- 6) Explicitly keep the provisioning audit table inaccessible to direct client roles.
revoke all on table public.account_provisioning_audit from anon, authenticated;
grant all on table public.account_provisioning_audit to service_role;

commit;

-- After applying this migration, create the first SYSTEM_ADMIN account through a
-- trusted one-time backend/admin bootstrap process. Do not insert Auth credentials
-- manually and do not put the service-role key in Flutter.
