const fs = require('node:fs');
const source = fs.readFileSync('supabase/migrations/20260907000000_live_guard_locations.sql','utf8');
let fn = source.slice(source.indexOf('create or replace function public.publish_guard_location('), source.indexOf('create or replace function public.stop_guard_location('));
if (!fn.includes('p_accuracy_meters<=100')) throw Error('Unexpected GPS function');
fn = fn.replace('p_accuracy_meters<=100','p_accuracy_meters<=500');
const sql = `-- Keep approximate positions visible with their measured accuracy circle.
-- This only changes live map accuracy; attendance geofence checks are unchanged.
alter table public.guard_live_locations drop constraint guard_live_locations_accuracy_meters_check;
alter table public.guard_live_locations add constraint guard_live_locations_accuracy_meters_check
  check (accuracy_meters > 0 and accuracy_meters <= 500);
${fn}`;
fs.writeFileSync('supabase/migrations/20260908000001_live_gps_approximate_accuracy.sql',sql);
fs.writeFileSync('testing/apply-live-gps-accuracy.sql',`begin;
set local lock_timeout='10s'; set local statement_timeout='60s';
${sql}
insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260908000001','live_gps_approximate_accuracy',array[$migration$${sql}$migration$]);
notify pgrst,'reload schema';
commit;
select version from supabase_migrations.schema_migrations where version='20260908000001';
`);
