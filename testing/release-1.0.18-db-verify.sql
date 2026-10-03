select
 (select count(*) from supabase_migrations.schema_migrations where version in ('20260914000000','20260914000001','20260914000002','20260914000003'))=4 as migrations_applied,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='incidents' and column_name='review_history') as reviewer_history_present,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='incidents' and column_name='photo_data' and is_nullable='YES') as video_only_supported,
 exists(select 1 from pg_constraint where conrelid='public.incidents'::regclass and pg_get_constraintdef(oid) like '%photo_data IS NOT NULL%video_path IS NOT NULL%') as evidence_check_present,
 exists(select 1 from pg_proc where pronamespace='public'::regnamespace and proname='file_incident_report' and prosrc like '%Enter an incident narrative%' and prosrc like '%[^[:space:]]%') as narrative_validation_present,
 exists(select 1 from pg_trigger where tgrelid='auth.sessions'::regclass and tgname='record_account_auth_session' and tgenabled='O') as session_history_trigger_enabled,
 (select relrowsecurity from pg_class where oid='public.account_presence_sessions'::regclass) as presence_rls_enabled,
 exists(select 1 from pg_index where indexrelid='public.profiles_email_case_insensitive_key'::regclass and indisunique and indisvalid) as email_unique_index_valid,
 (select count(*) from public.profiles) as profiles,
 (select count(*) from public.profiles where role::text='it_admin') as it_admins;
