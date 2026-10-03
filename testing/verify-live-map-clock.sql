-- Read-only snapshot metadata, without exposing guard names or coordinates.
select
  exists(select 1 from supabase_migrations.schema_migrations where version='20260913000000') as migration_applied,
  public.live_guard_map_snapshot()->>'server_now' as snapshot_server_time,
  jsonb_typeof(public.live_guard_map_snapshot()->'locations') as locations_type,
  has_function_privilege('anon','public.live_guard_map_snapshot()','execute') as anonymous_access,
  has_function_privilege('authenticated','public.live_guard_map_snapshot()','execute') as authenticated_access;
