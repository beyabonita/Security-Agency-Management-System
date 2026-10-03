-- Read-only deployment verification. No test records are created in production.
select version from supabase_migrations.schema_migrations
where version='20260912000002';
select relrowsecurity as row_security_enabled
from pg_class where oid='public.shift_roster_setups'::regclass;
select has_table_privilege('authenticated','public.shift_roster_setups','SELECT') as head_can_query_under_rls,
  has_table_privilege('authenticated','public.shift_roster_setups','INSERT,UPDATE,DELETE') as direct_writes_allowed,
  has_function_privilege('anon','public.save_shift_roster_setup(text,jsonb)','EXECUTE') as anonymous_save_allowed,
  has_function_privilege('authenticated','public.save_shift_roster_setup(text,jsonb)','EXECUTE') as authenticated_save_available,
  has_function_privilege('authenticated','public.assign_saved_shift_roster(uuid,uuid,date,uuid[])','EXECUTE') as authenticated_assign_available;
