# System Administrator bootstrap verification checklist

After running migration 0005 and the trusted CLI:

```sql
select p.login_id, p.full_name, p.account_status, p.must_change_pin,
       f.facility_code, f.facility_type, ufa.role, ufa.is_active
from public.user_profiles p
join public.user_facility_assignments ufa on ufa.user_id = p.user_id
join public.facilities f on f.id = ufa.facility_id
where p.login_id = 'PY-SYS-ADMIN-001';
```

Expected: one row; `account_status = active`, `must_change_pin = true`, `facility_type = THC`, `role = SYSTEM_ADMIN`, `is_active = true`.

Check the one-time guard:

```sql
select status, claimed_at, completed_at
from public.system_bootstrap_state
where singleton = true;
```

Expected: exactly one row with `status = completed` and a non-null `completed_at`.

Check audit:

```sql
select action, details, created_at
from public.account_provisioning_audit
where target_user_id = (
  select user_id from public.user_profiles where login_id = 'PY-SYS-ADMIN-001'
)
order by created_at desc;
```

Expected: a `created` action with `details.bootstrap = true`.

Do not share query results containing internal UUIDs publicly. The PIN is never returned by these queries.
