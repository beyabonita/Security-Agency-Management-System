select
 exists(select 1 from supabase_migrations.schema_migrations where version='20260908000001') as migration_applied,
 position('p_accuracy_meters<=500' in pg_get_functiondef('public.publish_guard_location(uuid,double precision,double precision,double precision,timestamp with time zone,boolean)'::regprocedure))>0 as publish_accepts_approximate,
 exists(select 1 from pg_constraint where conrelid='public.guard_live_locations'::regclass and conname='guard_live_locations_accuracy_meters_check' and pg_get_constraintdef(oid) like '%500%') as storage_accepts_approximate;
