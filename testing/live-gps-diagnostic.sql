select
  (select count(*) from public.attendance_sessions where status='open' and clock_out_at is null and scheduled_end_at>now()) as current_open_duties,
  (select count(*) from public.guard_live_locations) as stored_locations,
  (select count(*) from public.guard_live_locations where received_at>now()-interval '5 minutes') as recent_locations,
  (select max(received_at) from public.guard_live_locations) as last_location_received,
  exists(select 1 from supabase_migrations.schema_migrations where version='20260907000000') as tracking_migration_applied;
