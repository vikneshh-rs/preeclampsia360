-- Migration 0004: workflow persistence, offline idempotency and referral lifecycle support.
-- Run after 0001-0003. Does not define clinical thresholds or diagnoses.
begin;

alter table public.user_profiles add column if not exists internal_auth_email text;
create unique index if not exists user_profiles_internal_auth_email_uidx
  on public.user_profiles(internal_auth_email) where internal_auth_email is not null;


create table if not exists public.sync_events (
 id uuid primary key,
 user_id uuid not null references auth.users(id),
 facility_id uuid not null references public.facilities(id),
 event_type text not null check (event_type in ('patient.upsert','questionnaire.upsert','bp.measurement','followup.upsert','postpartum.upsert','referral.event')),
 entity_id uuid,
 payload jsonb not null,
 client_created_at timestamptz,
 received_at timestamptz not null default now(),
 processing_status text not null default 'accepted' check (processing_status in ('accepted','processed','rejected')),
 processing_error text
);
create index if not exists sync_events_user_received_idx on public.sync_events(user_id,received_at desc);

create table if not exists public.questionnaire_revisions (
 id uuid primary key default gen_random_uuid(),
 patient_id uuid not null references public.patients(id) on delete cascade,
 pregnancy_id uuid references public.pregnancy_records(id),
 section_key text not null,
 answers jsonb not null default '{}'::jsonb,
 schema_version text not null default '1.0',
 completed_by uuid references auth.users(id),
 completed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists questionnaire_patient_idx on public.questionnaire_revisions(patient_id,created_at desc);

alter table public.sync_events enable row level security;
alter table public.questionnaire_revisions enable row level security;
revoke all on public.sync_events from anon, authenticated;
revoke all on public.questionnaire_revisions from anon, authenticated;

-- Append-only referral history is enforced at API level; events remain auditable.
create index if not exists referral_events_referral_created_idx on public.referral_events(referral_id,created_at);
create index if not exists referrals_origin_status_idx on public.referrals(origin_facility_id,status,created_at desc);
create index if not exists referrals_receiving_status_idx on public.referrals(receiving_facility_id,status,created_at desc);

-- Preserve original questionnaire answers while allowing structured section revisions.
comment on column public.patients.questionnaire_data is 'Versioned ANM/ASHA proforma payload. Keep source wording; clinical interpretation is separate.';

commit;
