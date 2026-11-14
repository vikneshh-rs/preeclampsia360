create extension if not exists pgcrypto;

create type public.facility_type as enum ('PHC','CHC','THC','HOSPITAL');
create type public.app_role as enum ('ASHA','ANM','VHN','PHC_MO','CHC_MO','CHC_ADMIN','THC_MO','THC_ADMIN','RECEIVING_STAFF','SUPERVISOR','SYSTEM_ADMIN','PATIENT');
create type public.referral_status as enum ('generated','sent','acknowledged','departed','arrived','assessed','completed','rejected','redirected');

create table public.facilities (
 id uuid primary key default gen_random_uuid(), name text not null, facility_type public.facility_type not null,
 parent_facility_id uuid references public.facilities(id), district_id text, address text, is_active boolean not null default true,
 created_at timestamptz not null default now(),
 constraint facility_parent_type check (
   (facility_type='PHC' and parent_facility_id is not null) or
   (facility_type='CHC' and parent_facility_id is not null) or
   (facility_type in ('THC','HOSPITAL'))
 )
);
create index facilities_parent_idx on public.facilities(parent_facility_id);

create table public.user_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade, full_name text not null,
 phone text, preferred_language text not null default 'en', is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.user_facility_assignments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 facility_id uuid not null references public.facilities(id), role public.app_role not null,
 is_active boolean not null default true, assigned_at timestamptz not null default now(),
 unique(user_id, facility_id, role)
);
create index ufa_user_idx on public.user_facility_assignments(user_id, is_active);

create table public.patients (
 id uuid primary key default gen_random_uuid(), patient_code text unique not null default ('PE360-' || upper(substr(encode(gen_random_bytes(8),'hex'),1,10))),
 full_name text not null, date_of_birth date, phone text, address text, blood_group text,
 lmp date, edd date, gravida integer check (gravida is null or gravida between 1 and 30),
 parity integer check (parity is null or parity between 0 and 30), abortions integer check (abortions is null or abortions between 0 and 30),
 living_children integer check (living_children is null or living_children between 0 and 30),
 facility_id uuid not null references public.facilities(id), questionnaire_data jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 archived_at timestamptz
);
create index patients_facility_created_idx on public.patients(facility_id, created_at desc);
create index patients_name_idx on public.patients using gin (to_tsvector('simple', full_name));

create table public.pregnancy_records (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 pregnancy_number integer not null, lmp date, edd date, gravida integer, parity integer, abortions integer, living_children integer,
 conception_type text, booking_facility_id uuid references public.facilities(id), status text not null default 'active',
 created_at timestamptz not null default now(), unique(patient_id,pregnancy_number)
);
create table public.obstetric_history (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id), pregnancy_number integer not null,
 conception_type text, pregnancy_confirmation jsonb not null default '{}'::jsonb, booked_and_immunized jsonb not null default '{}'::jsonb,
 antenatal_complications text, supplements_taken text, delivery_details jsonb not null default '{}'::jsonb,
 baby_details jsonb not null default '{}'::jsonb, abortion_details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(patient_id,pregnancy_number)
);
create table public.bp_devices (
 id uuid primary key default gen_random_uuid(), facility_id uuid not null references public.facilities(id), manufacturer text,
 model text, serial_number text, device_code text unique, status text not null default 'active', metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table public.device_assignments (
 id uuid primary key default gen_random_uuid(), device_id uuid not null references public.bp_devices(id),
 worker_user_id uuid not null references auth.users(id), facility_id uuid not null references public.facilities(id),
 assigned_at timestamptz not null default now(), unassigned_at timestamptz, assigned_by uuid references auth.users(id)
);
create table public.bp_measurements (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id), facility_id uuid not null references public.facilities(id),
 device_id uuid references public.bp_devices(id), systolic_mmhg integer not null check(systolic_mmhg between 40 and 300),
 diastolic_mmhg integer not null check(diastolic_mmhg between 20 and 200), pulse_bpm integer check(pulse_bpm between 20 and 250),
 capture_method text not null default 'manual', ocr_confidence numeric(5,4), verification_status text not null default 'pending',
 worker_confirmed boolean not null default false, measured_at timestamptz not null, recorded_by uuid references auth.users(id),
 created_at timestamptz not null default now(), rule_version text
);
create index bp_patient_time_idx on public.bp_measurements(patient_id, measured_at desc);
create table public.measurement_captures (
 id uuid primary key default gen_random_uuid(), measurement_id uuid references public.bp_measurements(id),
 storage_path text, extracted_values jsonb not null default '{}'::jsonb, ocr_engine text, confidence numeric(5,4),
 retention_state text not null default 'pending_policy', created_at timestamptz not null default now()
);

create table public.clinical_screenings (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 facility_id uuid not null references public.facilities(id), assessed_by uuid references auth.users(id),
 screening_inputs jsonb not null default '{}'::jsonb, result_category text, rule_version text not null,
 clinician_review_status text not null default 'pending', assessed_at timestamptz not null default now()
);
create table public.referrals (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 origin_facility_id uuid not null references public.facilities(id), receiving_facility_id uuid references public.facilities(id),
 status public.referral_status not null default 'generated', reason text not null, clinical_summary jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.referral_events (
 id uuid primary key default gen_random_uuid(), referral_id uuid not null references public.referrals(id),
 from_status public.referral_status, to_status public.referral_status not null, actor_user_id uuid references auth.users(id),
 note text, created_at timestamptz not null default now()
);
create table public.follow_ups (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 facility_id uuid not null references public.facilities(id), due_at timestamptz not null, status text not null default 'pending',
 assigned_to uuid references auth.users(id), notes text, created_at timestamptz not null default now()
);
create table public.postpartum_visits (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 facility_id uuid not null references public.facilities(id), visit_date date not null, postpartum_day integer,
 assessment jsonb not null default '{}'::jsonb, recorded_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table public.audit_logs (
 id uuid primary key default gen_random_uuid(), actor_user_id uuid references auth.users(id), facility_id uuid references public.facilities(id),
 action text not null, entity_type text not null, entity_id uuid, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

-- RLS is enabled as a secure default. API service role bypasses RLS, therefore FastAPI MUST enforce scope on every request.
alter table public.facilities enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_facility_assignments enable row level security;
alter table public.patients enable row level security;
alter table public.pregnancy_records enable row level security;
alter table public.obstetric_history enable row level security;
alter table public.bp_devices enable row level security;
alter table public.device_assignments enable row level security;
alter table public.bp_measurements enable row level security;
alter table public.measurement_captures enable row level security;
alter table public.clinical_screenings enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_events enable row level security;
alter table public.follow_ups enable row level security;
alter table public.postpartum_visits enable row level security;
alter table public.audit_logs enable row level security;

-- Users can read their own profile and assignments. Clinical tables are intentionally not exposed to client direct access in V1.
create policy "read own profile" on public.user_profiles for select using (auth.uid() = user_id);
create policy "read own assignments" on public.user_facility_assignments for select using (auth.uid() = user_id);
