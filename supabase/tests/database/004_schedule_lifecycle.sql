-- Real INSERT/UPDATE/DELETE under authenticated JWT subjects, not policy-text
-- assertions alone. All fixtures, notifications and attendance roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

create temp table schedule_fixture (key text primary key, id uuid not null default gen_random_uuid());
insert into schedule_fixture(key) values
  ('hr'), ('guard'), ('inspector'), ('it'), ('foreign_guard'), ('foreign_org'),
  ('site'), ('other_site'), ('foreign_site'), ('unused'), ('unused_direct'),
  ('open'), ('closed'), ('report'), ('change'), ('completed'), ('new'), ('foreign_schedule');
insert into schedule_fixture(key, id) values ('org', public.beneficiary_organization_id());
create function pg_temp.fixture_id(p_key text) returns uuid language sql stable as
  $$ select id from pg_temp.schedule_fixture where key = p_key $$;

insert into public.organizations(id, name, slug, active)
values (pg_temp.fixture_id('foreign_org'), 'Schedule regression fixture',
        'schedule-test-' || pg_temp.fixture_id('foreign_org')::text, false);

insert into auth.users(id, email, raw_user_meta_data)
select id, 'schedule-test-' || id::text || '@example.invalid', '{}'::jsonb
from schedule_fixture where key in ('hr', 'guard', 'inspector', 'it', 'foreign_guard');
update public.profiles p
set organization_id = case when f.key = 'it' then null
                          when f.key = 'foreign_guard' then pg_temp.fixture_id('foreign_org')
                          else pg_temp.fixture_id('org') end,
    role = case f.key when 'hr' then 'admin'::public.app_role
                      when 'inspector' then 'inspector'::public.app_role
                      when 'it' then 'it_admin'::public.app_role
                      else 'user'::public.app_role end
from schedule_fixture f where p.id = f.id;

insert into public.locations(id, organization_id, label, latitude, longitude, radius_meters)
select id, case when key = 'foreign_site' then pg_temp.fixture_id('foreign_org') else pg_temp.fixture_id('org') end,
       'Schedule regression ' || key, 10.67, 122.95, 100
from schedule_fixture where key in ('site', 'other_site', 'foreign_site');

insert into public.schedules(id, organization_id, user_id, location_id, start_at, end_at, marked_done)
select id, case when key = 'foreign_schedule' then pg_temp.fixture_id('foreign_org') else pg_temp.fixture_id('org') end,
       case when key = 'foreign_schedule' then pg_temp.fixture_id('foreign_guard') else pg_temp.fixture_id('guard') end,
       case when key = 'foreign_schedule' then pg_temp.fixture_id('foreign_site') else pg_temp.fixture_id('site') end,
       '2098-01-01 00:00+08'::timestamptz + row_number() over (order by key) * interval '1 day',
       '2098-01-01 08:00+08'::timestamptz + row_number() over (order by key) * interval '1 day',
       key = 'completed'
from schedule_fixture where key in ('unused', 'unused_direct', 'open', 'closed', 'report', 'change', 'completed', 'foreign_schedule');

insert into public.attendance_sessions(organization_id, schedule_id, user_id, location_id,
  duty_date, scheduled_start_at, scheduled_end_at, clock_in_at, clock_in_latitude, clock_in_longitude, clock_out_at, status)
select s.organization_id, s.id, s.user_id, s.location_id, (s.start_at at time zone 'Asia/Manila')::date,
       s.start_at, s.end_at, s.start_at, 10.67, 122.95,
       case when f.key = 'closed' then s.end_at else null end,
       case when f.key = 'closed' then 'closed' else 'open' end
from public.schedules s join schedule_fixture f on f.id = s.id where f.key in ('open', 'closed');
insert into public.accomplishment_reports(organization_id, schedule_id, guard_id, summary, detailed_narrative)
values (pg_temp.fixture_id('org'), pg_temp.fixture_id('report'), pg_temp.fixture_id('guard'),
        'Regression duty completed', 'Regression fixture narrative, rolled back after testing.');
insert into public.shift_swap_requests(organization_id, requested_schedule_id, requester_id, inspector_id, reason)
values (pg_temp.fixture_id('org'), pg_temp.fixture_id('change'), pg_temp.fixture_id('guard'), pg_temp.fixture_id('inspector'),
        'Regression shift request, rolled back after testing.');

create temp table schedule_test_results(n integer generated always as identity, result text);
insert into schedule_test_results(result) select no_plan();
-- pgTAP's temporary counters and fixture tables must stay accessible while
-- testing the actual authenticated role instead of the database owner.
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.fixture_id('hr')::text, true); end $$;

insert into schedule_test_results(result) select lives_ok(
  $$ select id from public.locations where id = pg_temp.fixture_id('site') $$,
  'HR can read deployment sites without recursive policies');
insert into schedule_test_results(result) select lives_ok(
  $$ insert into public.schedules(id, user_id, location_id, start_at, end_at)
     values (pg_temp.fixture_id('new'), pg_temp.fixture_id('guard'), pg_temp.fixture_id('site'),
             '2099-01-01 08:00+08', '2099-01-01 17:00+08') returning * $$,
  'HR can create a schedule with RETURNING and default organization under RLS');
insert into schedule_test_results(result) select is(
  (select count(*) from public.schedules where id = pg_temp.fixture_id('new')), 1::bigint,
  'Created schedule is visible to HR');
insert into schedule_test_results(result) select lives_ok(
  $$ update public.schedules set location_id = pg_temp.fixture_id('other_site')
     where id = pg_temp.fixture_id('unused') returning * $$,
  'HR can update an unused schedule without recursive policies');
insert into schedule_test_results(result) select throws_ok(
  $$ insert into public.schedules(user_id, location_id, start_at, end_at)
     values (pg_temp.fixture_id('guard'), pg_temp.fixture_id('foreign_site'), '2099-02-01 08:00+08', '2099-02-01 17:00+08') $$,
  '42501', null, 'Cross-organization deployment-site insertion is denied');
insert into schedule_test_results(result) select throws_ok(
  $$ insert into public.schedules(user_id, location_id, start_at, end_at)
     values (pg_temp.fixture_id('foreign_guard'), pg_temp.fixture_id('site'), '2099-02-01 08:00+08', '2099-02-01 17:00+08') $$,
  '42501', null, 'Cross-organization personnel insertion is denied');
insert into schedule_test_results(result) select throws_ok(
  $$ insert into public.schedules(user_id, location_id, start_at, end_at)
     values (pg_temp.fixture_id('hr'), pg_temp.fixture_id('site'), '2099-02-01 08:00+08', '2099-02-01 17:00+08') $$,
  '42501', null, 'HR accounts cannot be assigned as duty personnel');
insert into schedule_test_results(result) select throws_ok(
  $$ update public.schedules set location_id = pg_temp.fixture_id('foreign_site') where id = pg_temp.fixture_id('unused') $$,
  '42501', null, 'Cross-organization schedule updates remain denied');

do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.fixture_id('guard')::text, true); end $$;
insert into schedule_test_results(result) select is(
  (select count(*) from public.locations where id = pg_temp.fixture_id('site')), 1::bigint,
  'Guard can still read a scheduled geofence');
insert into schedule_test_results(result) select is(
  (select count(*) from public.locations where id = pg_temp.fixture_id('foreign_site')), 0::bigint,
  'Guard cannot read another organization geofence');
insert into schedule_test_results(result) select throws_ok(
  $$ insert into public.schedules(user_id, location_id, start_at, end_at)
     values (pg_temp.fixture_id('guard'), pg_temp.fixture_id('site'), '2099-03-01 08:00+08', '2099-03-01 17:00+08') $$,
  '42501', null, 'Guard cannot create a schedule');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('unused')) $$,
  '42501', 'Only Admin can delete unused duty schedules.', 'Guard cannot delete schedules through RPC');

do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.fixture_id('inspector')::text, true); end $$;
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('unused')) $$,
  '42501', 'Only Admin can delete unused duty schedules.', 'Inspector cannot delete schedules through RPC');
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.fixture_id('it')::text, true); end $$;
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('unused')) $$,
  '42501', 'Only Admin can delete unused duty schedules.', 'IT Admin cannot bypass the operations-role boundary');

do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.fixture_id('hr')::text, true); end $$;
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('foreign_schedule')) $$,
  'P0002', 'Schedule not found or no longer available. Refresh the schedule list.', 'HR cannot delete another organization schedule');
insert into schedule_test_results(result) select lives_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('unused')) $$, 'HR can delete an unused schedule');
insert into schedule_test_results(result) select is(
  (select count(*) from public.schedules where id = pg_temp.fixture_id('unused')), 0::bigint,
  'Unused schedule is actually deleted');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('unused')) $$,
  'P0002', 'Schedule not found or no longer available. Refresh the schedule list.', 'Repeated deletion reports missing record instead of false success');
insert into schedule_test_results(result) select lives_ok(
  $$ delete from public.schedules where id = pg_temp.fixture_id('unused_direct') returning id $$,
  'Direct RLS deletion still permits unused schedules');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('open')) $$,
  'P0001', 'This schedule has recorded attendance and must be kept for the guard''s DTR.', 'Open attendance blocks deletion with a clear message');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('closed')) $$,
  'P0001', 'This schedule has recorded attendance and must be kept for the guard''s DTR.', 'Closed attendance blocks deletion with a clear message');
insert into schedule_test_results(result) select throws_ok(
  $$ delete from public.schedules where id = pg_temp.fixture_id('closed') $$,
  'P0001', 'This schedule has recorded attendance and must be kept for the guard''s DTR.', 'Direct deletion cannot bypass attendance protection');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('report')) $$,
  'P0001', 'This schedule has an accomplishment report and must be kept for historical records.', 'Accomplishment report cannot be silently cascaded away');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('change')) $$,
  'P0001', 'This schedule has a shift-change request and must be kept for approval history.', 'Shift approval history cannot be silently cascaded away');
insert into schedule_test_results(result) select throws_ok(
  $$ select public.delete_unused_schedule(pg_temp.fixture_id('completed')) $$,
  'P0001', 'Completed duty schedules must be kept for historical records.', 'Completed legacy duty remains protected even without a session');
insert into schedule_test_results(result) select is(
  (select count(*) from public.attendance_sessions where user_id = pg_temp.fixture_id('guard')), 2::bigint,
  'Both open and closed DTR sessions remain intact');
insert into schedule_test_results(result) select is(
  (select count(*) from public.accomplishment_reports where schedule_id = pg_temp.fixture_id('report')), 1::bigint,
  'Accomplishment report remains intact');
insert into schedule_test_results(result) select is(
  (select count(*) from public.shift_swap_requests where requested_schedule_id = pg_temp.fixture_id('change')), 1::bigint,
  'Shift request remains intact');

reset role;
insert into schedule_test_results(result) select ok(
  not has_function_privilege('anon', to_regprocedure('public.delete_unused_schedule(uuid)'), 'EXECUTE'),
  'Anonymous clients cannot call schedule deletion');
insert into schedule_test_results(result) select ok(
  not has_function_privilege('authenticated', to_regprocedure('public.prevent_schedule_history_deletion()'), 'EXECUTE'),
  'Deletion trigger cannot be invoked as a public RPC');
insert into schedule_test_results(result) select ok(
  not has_function_privilege('anon', to_regprocedure('private.has_schedule_at_location(uuid)'), 'EXECUTE'),
  'Location membership helper is not anonymously executable');
insert into schedule_test_results(result) select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=public']
     from pg_proc p where p.oid = to_regprocedure('private.has_schedule_at_location(uuid)')),
  'Membership lookup bypasses recursive RLS with a pinned definer search_path');
insert into schedule_test_results(result) select ok(
  (select confdeltype = 'r' from pg_constraint where conname = 'attendance_sessions_schedule_id_fkey'
   and conrelid = 'public.attendance_sessions'::regclass),
  'Attendance foreign key retains RESTRICT instead of CASCADE');

insert into schedule_test_results(result) select * from finish();
select result from schedule_test_results order by n;
rollback;
