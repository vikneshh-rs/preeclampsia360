-- Preeclampsia 360 | Migration 0006: Clinical Row Level Security (RLS) Policies
-- Run after migrations 0001 through 0005.
-- Enforces multi-tenant data isolation and referral-based access directly at the PostgreSQL layer.

begin;

-- 1) Helper function to retrieve all facility IDs in scope for an authenticated user
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
    -- Direct facility assignments
    select f.id
    from public.facilities f
    join user_direct ud on f.id = ud.facility_id
    where f.is_active = true

    union

    -- Hierarchical descendants for supervisory roles
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

-- 2) Helper function to check if an active referral grants clinical access to the user
create or replace function public.has_active_referral_access(p_patient_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.referrals r
    join public.user_facility_assignments ufa
      on ufa.facility_id = r.receiving_facility_id
     and ufa.user_id = auth.uid()
     and ufa.is_active = true
    where r.patient_id = p_patient_id
      and r.status in ('generated', 'sent', 'acknowledged', 'departed', 'arrived', 'assessed')
  );
$$;

-- 3) Helper function to check if current user is System Administrator
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

-- Grant execution to authenticated users
grant execute on function public.current_user_facility_ids() to authenticated, service_role;
grant execute on function public.has_active_referral_access(uuid) to authenticated, service_role;
grant execute on function public.is_system_admin() to authenticated, service_role;

-- =========================================================================
-- Patients RLS Policies
-- =========================================================================

drop policy if exists "patient_select_scope" on public.patients;
create policy "patient_select_scope" on public.patients
for select to authenticated
using (
  public.is_system_admin()
  or facility_id in (select public.current_user_facility_ids())
  or public.has_active_referral_access(id)
);

drop policy if exists "patient_insert_scope" on public.patients;
create policy "patient_insert_scope" on public.patients
for insert to authenticated
with check (
  public.is_system_admin()
  or facility_id in (
    select facility_id
    from public.user_facility_assignments
    where user_id = auth.uid()
      and is_active = true
      and role in ('ANM', 'VHN', 'PHC_MO', 'CHC_MO', 'SYSTEM_ADMIN')
  )
);

drop policy if exists "patient_update_scope" on public.patients;
create policy "patient_update_scope" on public.patients
for update to authenticated
using (
  public.is_system_admin()
  or facility_id in (select public.current_user_facility_ids())
);

-- =========================================================================
-- BP Measurements RLS Policies
-- =========================================================================

drop policy if exists "bp_measurements_select_scope" on public.bp_measurements;
create policy "bp_measurements_select_scope" on public.bp_measurements
for select to authenticated
using (
  public.is_system_admin()
  or facility_id in (select public.current_user_facility_ids())
  or public.has_active_referral_access(patient_id)
);

drop policy if exists "bp_measurements_insert_scope" on public.bp_measurements;
create policy "bp_measurements_insert_scope" on public.bp_measurements
for insert to authenticated
with check (
  public.is_system_admin()
  or (
    facility_id in (
      select facility_id
      from public.user_facility_assignments
      where user_id = auth.uid() and is_active = true
    )
    and recorded_by = auth.uid()
  )
);

-- =========================================================================
-- Referrals RLS Policies
-- =========================================================================

drop policy if exists "referrals_select_scope" on public.referrals;
create policy "referrals_select_scope" on public.referrals
for select to authenticated
using (
  public.is_system_admin()
  or origin_facility_id in (select public.current_user_facility_ids())
  or receiving_facility_id in (select public.current_user_facility_ids())
);

drop policy if exists "referrals_insert_scope" on public.referrals;
create policy "referrals_insert_scope" on public.referrals
for insert to authenticated
with check (
  public.is_system_admin()
  or (
    origin_facility_id in (
      select facility_id
      from public.user_facility_assignments
      where user_id = auth.uid() and is_active = true
    )
    and receiving_facility_id is not null
    and receiving_facility_id <> origin_facility_id
  )
);

drop policy if exists "referrals_update_scope" on public.referrals;
create policy "referrals_update_scope" on public.referrals
for update to authenticated
using (
  public.is_system_admin()
  or origin_facility_id in (select public.current_user_facility_ids())
  or receiving_facility_id in (select public.current_user_facility_ids())
);

-- =========================================================================
-- Referral Events RLS Policies
-- =========================================================================

drop policy if exists "referral_events_select_scope" on public.referral_events;
create policy "referral_events_select_scope" on public.referral_events
for select to authenticated
using (
  exists (
    select 1 from public.referrals r
    where r.id = referral_id
      and (
        public.is_system_admin()
        or r.origin_facility_id in (select public.current_user_facility_ids())
        or r.receiving_facility_id in (select public.current_user_facility_ids())
      )
  )
);

drop policy if exists "referral_events_insert_scope" on public.referral_events;
create policy "referral_events_insert_scope" on public.referral_events
for insert to authenticated
with check (
  actor_user_id = auth.uid()
  and exists (
    select 1 from public.referrals r
    where r.id = referral_id
      and (
        public.is_system_admin()
        or r.origin_facility_id in (select public.current_user_facility_ids())
        or r.receiving_facility_id in (select public.current_user_facility_ids())
      )
  )
);

-- =========================================================================
-- Facilities RLS Policy (Read Active Facilities)
-- =========================================================================

drop policy if exists "facilities_read_active" on public.facilities;
create policy "facilities_read_active" on public.facilities
for select to authenticated
using (is_active = true);

-- =========================================================================
-- Audit Logs RLS Policies
-- =========================================================================

drop policy if exists "audit_logs_insert" on public.audit_logs;
create policy "audit_logs_insert" on public.audit_logs
for insert to authenticated
with check (actor_user_id = auth.uid() or actor_user_id is null);

drop policy if exists "audit_logs_select_admin" on public.audit_logs;
create policy "audit_logs_select_admin" on public.audit_logs
for select to authenticated
using (
  public.is_system_admin()
  or exists (
    select 1 from public.user_facility_assignments
    where user_id = auth.uid()
      and role in ('THC_ADMIN', 'CHC_ADMIN')
      and is_active = true
  )
);

commit;

