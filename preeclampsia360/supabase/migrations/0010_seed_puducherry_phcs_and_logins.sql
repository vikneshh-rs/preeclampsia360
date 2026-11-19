-- Migration 0010: Puducherry Primary Health Centres (PHCs) Network & Logins
-- Adds all official Primary Health Centres across Puducherry region.
-- Standardizes login codes:
--   PHC MO / Facility ID: PY-PHC-[FIRST 4 LETTERS]
--   ANM ID:               PY-PHC-ANM-[FIRST 4 LETTERS]

begin;

-- 1) Ensure unique constraint exists on facility_code
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'facilities_facility_code_key'
  ) then
    alter table public.facilities add constraint facilities_facility_code_key unique (facility_code);
  end if;
end $$;

-- 2) Drop the legacy check constraint requiring mandatory CHC parent
alter table public.facilities drop constraint if exists facility_parent_type;

-- 3) Relax facility hierarchy to allow PHCs to link directly to THC or exist independently
create or replace function public.validate_facility_hierarchy()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare parent_type public.facility_type;
begin
  if new.parent_facility_id is null then
    if new.facility_type = 'CHC' then
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
  elsif new.facility_type = 'PHC' and parent_type not in ('CHC', 'THC') then
    raise exception 'A PHC must belong to a CHC or THC';
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

-- 4) Insert all Puducherry Primary Health Centres
-- Links to default CHC (PY-CHC-01) if available
insert into public.facilities (name, facility_type, facility_code, district_id, address, parent_facility_id, is_active)
values
  ('Muthialpet Primary Health Centre', 'PHC', 'PY-PHC-MUTH', 'PUDUCHERRY', 'Muthialpet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Lawspet Primary Health Centre', 'PHC', 'PY-PHC-LAWS', 'PUDUCHERRY', 'Lawspet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Reddiarpalayam Primary Health Centre', 'PHC', 'PY-PHC-REDD', 'PUDUCHERRY', 'Reddiarpalayam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Mudaliarpet Primary Health Centre', 'PHC', 'PY-PHC-MUDA', 'PUDUCHERRY', 'Mudaliarpet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Murungapakkam Primary Health Centre', 'PHC', 'PY-PHC-MURU', 'PUDUCHERRY', 'Murungapakkam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Mettupalayam Primary Health Centre', 'PHC', 'PY-PHC-METT', 'PUDUCHERRY', 'Mettupalayam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Dubrayapet Primary Health Centre', 'PHC', 'PY-PHC-DUBR', 'PUDUCHERRY', 'Dubrayapet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Ariankuppam Primary Health Centre', 'PHC', 'PY-PHC-ARIA', 'PUDUCHERRY', 'Ariankuppam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Gorimedu Primary Health Centre', 'PHC', 'PY-PHC-GORI', 'PUDUCHERRY', 'Gorimedu, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Kalapet Primary Health Centre', 'PHC', 'PY-PHC-KALA', 'PUDUCHERRY', 'Kalapet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Kosapalayam Primary Health Centre', 'PHC', 'PY-PHC-KOSA', 'PUDUCHERRY', 'Kosapalayam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Abishegapakkam Primary Health Centre', 'PHC', 'PY-PHC-ABIS', 'PUDUCHERRY', 'Abishegapakkam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Ariyur Primary Health Centre', 'PHC', 'PY-PHC-ARIY', 'PUDUCHERRY', 'Ariyur, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Bahour Primary Health Centre', 'PHC', 'PY-PHC-BAHO', 'PUDUCHERRY', 'Bahour, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Karayamputhur Primary Health Centre', 'PHC', 'PY-PHC-KARA', 'PUDUCHERRY', 'Karayamputhur, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Katterikuppam Primary Health Centre', 'PHC', 'PY-PHC-KATT', 'PUDUCHERRY', 'Katterikuppam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Kirumampakkam Primary Health Centre', 'PHC', 'PY-PHC-KIRU', 'PUDUCHERRY', 'Kirumampakkam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Koodapakkam Primary Health Centre', 'PHC', 'PY-PHC-KOOD', 'PUDUCHERRY', 'Koodapakkam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Nettapakkam Primary Health Centre', 'PHC', 'PY-PHC-NETT', 'PUDUCHERRY', 'Nettapakkam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Sedarapet Primary Health Centre', 'PHC', 'PY-PHC-SEDA', 'PUDUCHERRY', 'Sedarapet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Sooramangalam Primary Health Centre', 'PHC', 'PY-PHC-SOOR', 'PUDUCHERRY', 'Sooramangalam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Sorapet Primary Health Centre', 'PHC', 'PY-PHC-SORA', 'PUDUCHERRY', 'Sorapet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Thavalakuppam Primary Health Centre', 'PHC', 'PY-PHC-THAV', 'PUDUCHERRY', 'Thavalakuppam, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Thirubuvanai Primary Health Centre', 'PHC', 'PY-PHC-THIR', 'PUDUCHERRY', 'Thirubuvanai, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Thirukkanur Primary Health Centre', 'PHC', 'PY-PHC-THIK', 'PUDUCHERRY', 'Thirukkanur, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Villianur Primary Health Centre', 'PHC', 'PY-PHC-VILL', 'PUDUCHERRY', 'Villianur, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true),
  ('Madagadipet Primary Health Centre', 'PHC', 'PY-PHC-MADA', 'PUDUCHERRY', 'Madagadipet, Puducherry', (select id from public.facilities where facility_code = 'PY-CHC-01' limit 1), true)
on conflict (facility_code) do update set
  name = excluded.name,
  facility_type = excluded.facility_type,
  address = excluded.address,
  parent_facility_id = coalesce(excluded.parent_facility_id, facilities.parent_facility_id),
  is_active = excluded.is_active;

commit;
