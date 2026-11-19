-- Migration 0009: Seed Puducherry Tertiary Maternity Hospitals
-- Adds JIPMER, IGMC&RI, PIMS, and SMVMCH as specialized receiving referral hospitals.
-- (Rajiv Gandhi Women and Children Hospital already exists as PY-THC-01).

begin;

-- 1) Ensure unique constraint exists on facility_code for conflict resolution
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'facilities_facility_code_key'
  ) then
    alter table public.facilities add constraint facilities_facility_code_key unique (facility_code);
  end if;
end $$;

-- 2) Insert or update tertiary maternity care referral facilities
insert into public.facilities (name, facility_type, facility_code, district_id, address, is_active)
values
  ('JIPMER (Jawaharlal Institute of Postgraduate Medical Education & Research)', 'HOSPITAL', 'PY-HOSP-JIPMER', 'PUDUCHERRY', 'Gorimedu, Puducherry', true),
  ('IGMC&RI (Indira Gandhi Medical College & Research Institute)', 'HOSPITAL', 'PY-HOSP-IGMCRI', 'PUDUCHERRY', 'Kathirkamam, Puducherry', true),
  ('PIMS (Pondicherry Institute of Medical Sciences)', 'HOSPITAL', 'PY-HOSP-PIMS', 'PUDUCHERRY', 'Kalapet, East Coast Road (ECR), Puducherry', true),
  ('SMVMCH (Sri Manakula Vinayagar Medical College and Hospital)', 'HOSPITAL', 'PY-HOSP-SMVMCH', 'PUDUCHERRY', 'Madagadipet, Puducherry', true)
on conflict (facility_code) do update set
  name = excluded.name,
  facility_type = excluded.facility_type,
  address = excluded.address,
  is_active = excluded.is_active;

commit;
