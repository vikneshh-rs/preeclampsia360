-- Migration 0007: Clinical Alerts for Elevated Blood Pressure Screening
-- Can be applied on top of 0001-0006 in Supabase SQL Editor.
begin;

-- =========================================================================
-- 1) Create Table: clinical_alerts
-- =========================================================================

create table if not exists public.clinical_alerts (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  measurement_id uuid not null references public.bp_measurements(id) on delete cascade,
  facility_id uuid not null references public.facilities(id),
  worker_user_id uuid not null references auth.users(id),
  alert_type text not null default 'ELEVATED_BP',
  severity text not null check (severity in ('amber', 'red')),
  trigger_reason text not null,
  systolic_mmhg integer not null check (systolic_mmhg between 40 and 300),
  diastolic_mmhg integer not null check (diastolic_mmhg between 20 and 200),
  status text not null default 'active' check (status in ('active', 'reviewed', 'referred', 'dismissed')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists clinical_alerts_fac_status_idx on public.clinical_alerts(facility_id, status, created_at desc);
create index if not exists clinical_alerts_patient_idx on public.clinical_alerts(patient_id, created_at desc);

comment on table public.clinical_alerts is 'Screening alerts generated upon verified elevated BP (SBP >= 140 or DBP >= 90 mmHg). Screening trigger only; not an automated clinical diagnosis.';

-- =========================================================================
-- 2) Idempotent RLS Helper Functions (Ensures existence & compatibility)
-- =========================================================================

-- System Admin check (zero arguments, reads auth.uid() from session)
create or replace function public.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_facility_assignments
    where user_id = auth.uid()
      and role = 'SYSTEM_ADMIN'
      and is_active = true
  );
$$;

-- Overloaded System Admin check accepting explicit user_id (for backwards-compatibility)
create or replace function public.is_system_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_facility_assignments
    where user_id = p_user_id
      and role = 'SYSTEM_ADMIN'
      and is_active = true
  );
$$;

-- Current user accessible facility hierarchy ids
create or replace function public.current_user_facility_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with recursive user_direct as (
    select facility_id, role
    from public.user_facility_assignments
    where user_id = auth.uid()
      and is_active = true
  ),
  descendants as (
    select f.id
    from public.facilities f
    join user_direct ud on f.id = ud.facility_id
    where f.is_active = true
    union
    select child.id
    from public.facilities child
    join descendants parent on child.parent_facility_id = parent.id
    where child.is_active = true
      and exists (
        select 1 from user_direct
        where role in ('SYSTEM_ADMIN', 'THC_ADMIN', 'THC_MO', 'CHC_ADMIN', 'CHC_MO', 'SUPERVISOR')
      )
  )
  select id from descendants;
$$;

-- Facility accessibility helper accepting (user_id, facility_id)
create or replace function public.is_facility_accessible(p_user_id uuid, p_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.facilities f
    where f.id = p_facility_id
      and f.id in (
        with recursive user_direct as (
          select facility_id, role
          from public.user_facility_assignments
          where user_id = p_user_id
            and is_active = true
        ),
        descendants as (
          select d.id
          from public.facilities d
          join user_direct ud on d.id = ud.facility_id
          where d.is_active = true
          union
          select child.id
          from public.facilities child
          join descendants parent on child.parent_facility_id = parent.id
          where child.is_active = true
            and exists (
              select 1 from user_direct
              where role in ('SYSTEM_ADMIN', 'THC_ADMIN', 'THC_MO', 'CHC_ADMIN', 'CHC_MO', 'SUPERVISOR')
            )
        )
        select id from descendants
      )
  );
$$;

-- Grant execution to authenticated & service_role
grant execute on function public.is_system_admin() to authenticated, service_role;
grant execute on function public.is_system_admin(uuid) to authenticated, service_role;
grant execute on function public.current_user_facility_ids() to authenticated, service_role;
grant execute on function public.is_facility_accessible(uuid, uuid) to authenticated, service_role;

-- =========================================================================
-- 3) Row Level Security Policies
-- =========================================================================

alter table public.clinical_alerts enable row level security;

-- Drop any previous variants of the policies
drop policy if exists alerts_facility_hierarchy_select on public.clinical_alerts;
drop policy if exists "alerts_select_scope" on public.clinical_alerts;
create policy "alerts_select_scope" on public.clinical_alerts
  for select to authenticated
  using (
    public.is_system_admin()
    or facility_id in (select public.current_user_facility_ids())
  );

drop policy if exists alerts_facility_insert on public.clinical_alerts;
drop policy if exists "alerts_insert_scope" on public.clinical_alerts;
create policy "alerts_insert_scope" on public.clinical_alerts
  for insert to authenticated
  with check (
    public.is_system_admin()
    or facility_id in (
      select facility_id
      from public.user_facility_assignments
      where user_id = auth.uid() and is_active = true
    )
  );

drop policy if exists alerts_facility_update on public.clinical_alerts;
drop policy if exists "alerts_update_scope" on public.clinical_alerts;
create policy "alerts_update_scope" on public.clinical_alerts
  for update to authenticated
  using (
    public.is_system_admin()
    or facility_id in (select public.current_user_facility_ids())
  );

commit;
