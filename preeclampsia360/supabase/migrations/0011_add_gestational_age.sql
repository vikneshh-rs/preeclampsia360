-- Migration 0011: Add Gestational Age columns to patients table
-- Supports tracking initial gestational age in weeks (<= 42) and days (<= 7)
-- and allows dynamic progression tracking from registration date.

begin;

alter table public.patients
  add column if not exists gestational_age_weeks integer check (gestational_age_weeks is null or (gestational_age_weeks between 0 and 42)),
  add column if not exists gestational_age_days integer check (gestational_age_days is null or (gestational_age_days between 0 and 7)),
  add column if not exists ga_recorded_at timestamptz default now();

commit;

