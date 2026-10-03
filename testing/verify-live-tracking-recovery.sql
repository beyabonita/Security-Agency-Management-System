select
  exists(select 1 from supabase_migrations.schema_migrations where version='20260912000000') as recovery_migration_applied,
  exists(select 1 from pg_trigger where tgname='signal_guard_duty_location_change' and not tgisinternal) as duty_realtime_signal_installed,
  position('left join public.guard_live_locations' in pg_get_functiondef('public.list_live_guard_locations()'::regprocedure))>0 as waiting_guards_supported,
  (select count(*) from public.attendance_sessions where status='open' and clock_out_at is null and scheduled_end_at>now()) as current_open_duties,
  (select count(*) from public.guard_live_locations where received_at>now()-interval '5 minutes') as recent_real_locations;
