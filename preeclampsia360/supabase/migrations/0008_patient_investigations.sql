-- Migration 0008: Laboratory Investigations (HB, Urea, Platelet, Creatinine, LFT)
-- Can be applied in Supabase SQL Editor on top of 0001-0007.

begin;

-- =========================================================================
-- 1) Create Table: patient_investigations
-- =========================================================================
create table if not exists public.patient_investigations (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  facility_id uuid references public.facilities(id),
  hb text,
  urea text,
  platelet text,
  creatinine text,
  lft text,
  notes text,
  recorded_by uuid references auth.users(id),
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists patient_investigations_patient_idx 
  on public.patient_investigations(patient_id, recorded_at desc);

create index if not exists patient_investigations_facility_idx 
  on public.patient_investigations(facility_id, recorded_at desc);

comment on table public.patient_investigations is 
  'Maternal laboratory investigation parameters: Hemoglobin (HB), Urea, Platelets, Creatinine, and Liver Function Tests (LFT) for preeclampsia screening.';

-- =========================================================================
-- 2) Row Level Security (RLS) Policies
-- =========================================================================
alter table public.patient_investigations enable row level security;

drop policy if exists patient_investigations_select_policy on public.patient_investigations;
create policy patient_investigations_select_policy on public.patient_investigations
  for select using (
    public.is_system_admin() or
    exists (
      select 1 from public.user_facility_assignments ufa
      where ufa.user_id = auth.uid()
        and ufa.is_active = true
        and (ufa.facility_id = patient_investigations.facility_id or patient_investigations.facility_id is null)
    )
  );

drop policy if exists patient_investigations_insert_policy on public.patient_investigations;
create policy patient_investigations_insert_policy on public.patient_investigations
  for insert with check (
    public.is_system_admin() or
    exists (
      select 1 from public.user_facility_assignments ufa
      where ufa.user_id = auth.uid()
        and ufa.is_active = true
    )
  );

drop policy if exists patient_investigations_update_policy on public.patient_investigations;
create policy patient_investigations_update_policy on public.patient_investigations
  for update using (
    public.is_system_admin() or
    exists (
      select 1 from public.user_facility_assignments ufa
      where ufa.user_id = auth.uid()
        and ufa.is_active = true
    )
  );

commit;

