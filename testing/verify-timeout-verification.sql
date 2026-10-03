select
  exists(select 1 from supabase_migrations.schema_migrations where version='20260908000002') as migration_applied,
  to_regclass('public.attendance_timeout_reviews') is not null as audit_table_exists,
  position('Ask your admin to verify' in pg_get_functiondef('public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure))>0 as guard_deadline_enforced,
  position('timeout_verified_at' in pg_get_functiondef('public.evaluate_time_record(uuid,date,date)'::regprocedure))>0 as unverified_hours_excluded,
  has_function_privilege('authenticated','public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid)','execute') as admin_rpc_available,
  not has_function_privilege('anon','public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid)','execute') as anonymous_rpc_denied,
  not has_table_privilege('authenticated','public.attendance_timeout_reviews','UPDATE,DELETE,INSERT') as audit_read_only,
  (select relrowsecurity from pg_class where oid='public.attendance_timeout_reviews'::regclass) as audit_rls_enabled;
