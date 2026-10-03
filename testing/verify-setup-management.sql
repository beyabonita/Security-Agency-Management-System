-- Only template/schema counts, no personnel or attendance data.
select
  exists(select 1 from supabase_migrations.schema_migrations where version='20260912000003') as migration_applied,
  (select relrowsecurity from pg_class where oid='public.shift_roster_setups'::regclass) as rls_enabled,
  (select count(*) from public.shift_roster_setups where archived_at is null and shift_signature in
    ('06:00-18:00,18:00-06:00','06:00-14:00,14:00-22:00,22:00-06:00')) as active_standard_duplicates,
  (select count(*) from (select organization_id,shift_signature from public.shift_roster_setups
    where archived_at is null group by organization_id,shift_signature having count(*)>1) d) as duplicate_time_groups,
  has_function_privilege('anon','public.update_shift_roster_setup(uuid,text,jsonb,integer)','execute') as anonymous_edit_allowed,
  has_function_privilege('authenticated','public.update_shift_roster_setup(uuid,text,jsonb,integer)','execute') as head_edit_rpc_available,
  has_function_privilege('authenticated','public.remove_shift_roster_setup(uuid,integer)','execute') as head_remove_rpc_available;
