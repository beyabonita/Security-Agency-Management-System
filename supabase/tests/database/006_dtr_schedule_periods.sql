-- Authenticated behavior tests for atomic DTR plans. All rows and notifications roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
create temp table dtr_fixture(key text primary key, id uuid not null default gen_random_uuid());
insert into dtr_fixture(key) values ('admin'),('guard'),('inspector'),('it'),('inactive_guard'),('inactive_admin'),('foreign_guard'),('foreign_org'),('site'),('inactive_site'),('foreign_site');
insert into dtr_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.df(k text) returns uuid language sql stable as $$select id from pg_temp.dtr_fixture where key=k$$;
insert into public.organizations(id,name,slug,active) values(pg_temp.df('foreign_org'),'DTR rollback test','dtr-test-'||pg_temp.df('foreign_org'),false);
insert into auth.users(id,email,raw_user_meta_data)
select id,'dtr-test-'||id||'@example.invalid','{}'::jsonb from dtr_fixture
where key in ('admin','guard','inspector','it','inactive_guard','inactive_admin','foreign_guard');
update public.profiles p set organization_id=case when f.key='it' then null when f.key='foreign_guard' then pg_temp.df('foreign_org') else pg_temp.df('org') end,
 role=case when f.key in ('admin','inactive_admin') then 'admin'::public.app_role when f.key='inspector' then 'inspector'::public.app_role when f.key='it' then 'it_admin'::public.app_role else 'user'::public.app_role end,
 active=f.key not in ('inactive_guard','inactive_admin'), duty_days_total=0
from dtr_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters,active)
select id,case when key='foreign_site' then pg_temp.df('foreign_org') else pg_temp.df('org') end,
 'DTR rollback site',10.67,122.95,100,key<>'inactive_site'
from dtr_fixture where key in ('site','inactive_site','foreign_site');
create temp table dtr_created as select * from public.schedules where false;
create temp table dtr_results(n integer generated always as identity,result text);
insert into dtr_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.df('admin')::text,true); end $$;

insert into dtr_results(result) select lives_ok($q$
insert into dtr_created select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-15',
 '[{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"13:00","end_time":"17:00"},{"period":"overtime","start_time":"01:00","end_time":"03:00","next_day":true}]')
$q$,'Admin atomically creates Morning Afternoon and next-day OT');
insert into dtr_results(result) select is((select count(*) from dtr_created),3::bigint,'RPC returns all three created rows');
insert into dtr_results(result) select is((select count(distinct duty_date) from dtr_created),1::bigint,'Three periods retain one DTR anchor');
insert into dtr_results(result) select is((select start_at from dtr_created where dtr_period='morning'),'2099-01-15 00:00Z'::timestamptz,'Morning is interpreted in Asia/Manila');
insert into dtr_results(result) select is((select start_at from dtr_created where dtr_period='overtime'),'2099-01-15 17:00Z'::timestamptz,'Next-day OT starts on Jan 16 in Manila');
insert into dtr_results(result) select is((select duty_date from dtr_created where dtr_period='overtime'),'2099-01-15'::date,'OT belongs to first cutoff despite next-day timestamp');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-15','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$q$,
 'P0001','This personnel member already has an overlapping active schedule.','Duplicate create cannot save overlapping periods');
insert into dtr_results(result) select is((select count(*) from public.schedules where user_id=pg_temp.df('guard')),3::bigint,'Duplicate request did not add rows');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"12:00","end_time":"12:00"}]')$q$,
 'P0001','Start time and End time must be different.','Invalid second period rejects whole request');
insert into dtr_results(result) select is((select count(*) from public.schedules where user_id=pg_temp.df('guard') and duty_date='2099-01-02'),0::bigint,'First period rolled back after second period failed');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"morning","start_time":"08:00","end_time":"14:00"},{"period":"afternoon","start_time":"13:00","end_time":"17:00"}]')$q$,
 'P0001','This personnel member already has an overlapping active schedule.','Overlapping periods within one request are rejected');
insert into dtr_results(result) select is((select count(*) from public.schedules where user_id=pg_temp.df('guard') and duty_date='2099-01-02'),0::bigint,'Internal overlap rolls back the first insert too');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"morning","start_time":"13:00","end_time":"17:00"}]')$q$,
 'P0001','A DTR period may be added only once per request.','Duplicate labels are rejected');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"13:00","end_time":"17:00"}]')$q$,
 'P0001','Use Continuous duty or separate Morning/Afternoon periods, not both.','Continuous and split modes cannot be mixed');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[]')$q$,'P0001','Choose between one and three duty periods.','Empty plan is rejected');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','{}')$q$,'P0001','Provide the enabled duty periods as an array.','Wrong JSON container is rejected');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"25:00","end_time":"08:00"}]')$q$,'P0001','Enter each duty time in HH:mm format.','Invalid time is rejected before cast');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"12:00","next_day":"true"}]')$q$,'P0001','Each duty period needs a period, Start time, End time, and valid next-day choice.','Next-day flag must be boolean');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2000-01-01','[{"period":"auto","start_time":"08:00","end_time":"12:00"}]')$q$,'P0001','Choose today or a future duty date.','Past duty date is rejected');

insert into dtr_results(result) select lives_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-31','[{"period":"auto","start_time":"20:00","end_time":"05:00"}]')$q$,'Continuous overnight is accepted across month boundary');
insert into dtr_results(result) select is((select end_at from public.schedules where user_id=pg_temp.df('guard') and duty_date='2099-01-31'),'2099-01-31 21:00Z'::timestamptz,'Overnight ends on Feb 1 in Manila');
insert into dtr_results(result) select lives_ok($q$select * from public.create_dtr_schedule(pg_temp.df('inspector'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'Inspector retains one continuous assignment');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('inspector'),pg_temp.df('site'),'2099-01-03','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$q$,'P0001','An Inspector has one duty period and does not use Guard DTR columns.','Inspector cannot be assigned split Guard DTR periods');

insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('inactive_guard'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'P0001','Choose active personnel from your agency.','Inactive guard cannot receive a plan');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('admin'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'P0001','Choose active personnel from your agency.','Admin cannot be assigned Guard duty');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('foreign_guard'),pg_temp.df('site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'P0001','Choose active personnel from your agency.','Foreign guard is rejected');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('foreign_site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'P0001','Choose an active deployment site from your agency.','Foreign site is rejected');
insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('inactive_site'),'2099-01-02','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'P0001','Choose an active deployment site from your agency.','Inactive site is rejected');
do $$ declare r record; begin for r in select key,id from dtr_fixture where key in ('guard','inspector','it','inactive_admin') loop
 perform set_config('request.jwt.claim.sub',r.id::text,true);
 insert into dtr_results(result) select throws_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-03','[{"period":"auto","start_time":"08:00","end_time":"17:00"}]')$q$,'42501','Only an active Admin can create duty schedules.',r.key||' cannot create duty plans');
end loop; end $$;

reset role;
-- Session insertion snapshots schedule-owned period and DTR date, not caller metadata.
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,dtr_period,scheduled_start_at,scheduled_end_at,clock_in_at,clock_out_at,status,clock_in_latitude,clock_in_longitude)
select organization_id,id,user_id,location_id,'2000-01-01','auto',start_at,end_at,
 case dtr_period when 'morning' then start_at+interval '5 minutes' when 'afternoon' then start_at-interval '5 minutes' else start_at+interval '2 minutes' end,
 case dtr_period when 'morning' then end_at+interval '10 minutes' when 'afternoon' then end_at-interval '10 minutes' else end_at+interval '2 minutes' end,
 'closed',10.67,122.95 from dtr_created;
insert into dtr_results(result) select is((select count(*) from public.attendance_sessions where user_id=pg_temp.df('guard') and duty_date='2099-01-15' and dtr_period in ('morning','afternoon','overtime')),3::bigint,'Attendance copies authoritative DTR metadata');
insert into dtr_results(result) select throws_ok($q$update public.schedules set dtr_period='auto' where id=(select id from dtr_created where dtr_period='morning')$q$,'P0001','A started duty cannot be changed. Create a corrected replacement schedule instead.','Started DTR columns are immutable');
insert into dtr_results(result) select throws_ok($q$update public.schedules set duty_date='2099-01-16' where id=(select id from dtr_created where dtr_period='morning')$q$,'P0001','A started duty cannot be changed. Create a corrected replacement schedule instead.','Started DTR row cannot move cutoff');
set local role authenticated;
do $$ declare r record; begin perform set_config('request.jwt.claim.sub',pg_temp.df('guard')::text,true);
 for r in select id from dtr_created order by start_at loop perform public.complete_schedule(r.id); end loop;
end $$;
insert into dtr_results(result) select is((select duty_days_total from public.profiles where id=pg_temp.df('guard')),1,'Three completions credit one cumulative duty day');
insert into dtr_results(result) select lives_ok($q$select public.complete_schedule(id) from dtr_created$q$,'Retrying completion is safe');
insert into dtr_results(result) select is((select duty_days_total from public.profiles where id=pg_temp.df('guard')),1,'Completion retry does not award another day');
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.df('admin')::text,true); end $$;
insert into dtr_results(result) select is((select duty_days from public.evaluate_time_record(pg_temp.df('guard'),'2099-01-01','2099-01-15')),1,'Evaluation counts one DTR duty date');
insert into dtr_results(result) select is((select completed_days from public.evaluate_time_record(pg_temp.df('guard'),'2099-01-01','2099-01-15')),1,'Evaluation counts the completed DTR date once');
insert into dtr_results(result) select is((select total_minutes from public.evaluate_time_record(pg_temp.df('guard'),'2099-01-01','2099-01-15')),600,'Evaluation sums actual period minutes');
insert into dtr_results(result) select is((select late_minutes from public.evaluate_time_record(pg_temp.df('guard'),'2099-01-01','2099-01-15')),7,'Evaluation sums actual late minutes');
insert into dtr_results(result) select is((select undertime_minutes from public.evaluate_time_record(pg_temp.df('guard'),'2099-01-01','2099-01-15')),10,'Evaluation sums actual undertime minutes');
insert into dtr_results(result) select throws_ok($q$select public.delete_unused_schedule((select id from dtr_created where dtr_period='morning'))$q$,'P0001','This schedule has recorded attendance and must be kept for the guard''s DTR.','Split period attendance retains deletion protection');
insert into dtr_results(result) select lives_ok($q$select public.delete_unused_schedule(id) from public.schedules where user_id=pg_temp.df('guard') and duty_date='2099-01-31'$q$,'Unused continuous period remains deletable');
insert into dtr_results(result) select lives_ok($q$select * from public.create_dtr_schedule(pg_temp.df('guard'),pg_temp.df('site'),'2099-01-31','[{"period":"auto","start_time":"20:00","end_time":"05:00"}]')$q$,'Deleted unused period can be recreated unchanged');
reset role;
insert into dtr_results(result) select ok(not has_function_privilege('anon',to_regprocedure('public.create_dtr_schedule(uuid,uuid,date,jsonb)'),'EXECUTE'),'Anonymous caller cannot invoke create RPC');
insert into dtr_results(result) select * from finish();
select result from dtr_results order by n;
rollback;
