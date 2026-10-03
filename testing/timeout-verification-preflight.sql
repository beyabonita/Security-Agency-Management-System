select version, name from supabase_migrations.schema_migrations where version >= '20260905000005' order by version;
select count(*) filter (where clock_out_at is null and scheduled_end_at < now()) as missing_timeouts,
  count(*) filter (where clock_out_at > scheduled_end_at) as late_timeouts
from public.attendance_sessions;
select t.tgname, pg_get_triggerdef(t.oid) as definition,
  pg_get_functiondef(t.tgfoid) as trigger_function
from pg_trigger t where not t.tgisinternal and t.tgrelid in ('public.attendance_sessions'::regclass,'public.schedules'::regclass,'public.profiles'::regclass);
