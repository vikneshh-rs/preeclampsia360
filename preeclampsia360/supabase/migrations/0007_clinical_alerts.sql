-- Migration 0007: Clinical Alerts for Elevated Blood Pressure Screening
begin;

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

alter table public.clinical_alerts enable row level security;

-- RLS policies for clinical_alerts matching Migration 0006 standards
drop policy if exists alerts_facility_hierarchy_select on public.clinical_alerts;
create policy alerts_facility_hierarchy_select on public.clinical_alerts
  for select
  using (
    public.is_system_admin(auth.uid()) or
    public.is_facility_accessible(auth.uid(), facility_id)
  );

drop policy if exists alerts_facility_insert on public.clinical_alerts;
create policy alerts_facility_insert on public.clinical_alerts
  for insert
  with check (
    public.is_system_admin(auth.uid()) or
    public.is_facility_accessible(auth.uid(), facility_id)
  );

drop policy if exists alerts_facility_update on public.clinical_alerts;
create policy alerts_facility_update on public.clinical_alerts
  for update
  using (
    public.is_system_admin(auth.uid()) or
    public.is_facility_accessible(auth.uid(), facility_id)
  );

comment on table public.clinical_alerts is 'Screening alerts generated upon verified elevated BP (SBP >= 140 or DBP >= 90 mmHg). Screening trigger only; not an automated clinical diagnosis.';

commit;
