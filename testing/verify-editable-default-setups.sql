-- Read-only verification of the deployed starting templates and duplicate guard.
select exists(select 1 from supabase_migrations.schema_migrations where version='20260912000004') as migration_applied,
  (select count(*) from public.shift_roster_setups where archived_at is null and name in ('2 Shifts','3 Shifts')) as editable_initial_setups,
  (select count(*) from (select organization_id,shift_signature from public.shift_roster_setups where archived_at is null
    group by organization_id,shift_signature having count(*)>1) d) as duplicate_time_groups,
  (select relrowsecurity from pg_class where oid='public.shift_roster_setups'::regclass) as rls_enabled,
  exists(select 1 from pg_trigger where tgname='seed_initial_roster_setups' and not tgisinternal) as new_agency_seed_enabled;
