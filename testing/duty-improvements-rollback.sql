begin;
set local lock_timeout='5s';
set local statement_timeout='90s';


create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
create temp table relief_fixture(key text primary key,id uuid not null default gen_random_uuid());
insert into relief_fixture(key) values('head'),('guard'),('peer'),('third'),('inspector'),('site'),('duty'),('later'),('request');
insert into relief_fixture(key,id) values('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.relief_fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data) select id,'relief-test-'||id::text||'@example.invalid','{}'::jsonb
  from relief_fixture where key in ('head','guard','peer','third','inspector');
update public.profiles p set role=case f.key when 'head' then 'admin'::public.app_role
  when 'inspector' then 'inspector'::public.app_role else 'user'::public.app_role end,
  active=true,organization_id=pg_temp.f('org'),first_name='Relief',last_name=f.key,employment_category='regular'
  from relief_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
  values(pg_temp.f('site'),pg_temp.f('org'),'Relief fixture',10.67,122.95,100);
insert into public.schedules(id,organization_id,user_id,location_id,location_label,start_at,end_at,duty_date,dtr_period)
  values(pg_temp.f('duty'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'Relief fixture',now()-interval '1 hour',now()+interval '2 hours',(now() at time zone 'Asia/Manila')::date,'auto');
insert into storage.objects(bucket_id,name,metadata) select 'request-letters',pg_temp.f('guard')||'/'||n||'.pdf',
  '{"mimetype":"application/pdf","size":30}'::jsonb from unnest(array['relief','absence']) n;
create temp table relief_results(n integer generated always as identity,result text);
insert into relief_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into relief_results(result) select throws_ok($$select public.record_attendance_event('clock_in',null,null)$$,'P0001',null,'Time In still requires GPS');
insert into relief_results(result) select lives_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'Guard times in at assigned post');
insert into relief_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('duty'),'swap','Feeling unwell and need relief',pg_temp.f('guard')||'/relief.pdf','Relief.pdf')$$,'Timed-in Guard can request a replacement');
update relief_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/relief.pdf') where key='request';
insert into relief_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('duty'),'absence','Feeling unwell',pg_temp.f('guard')||'/absence.pdf','Absence.pdf')$$,'P0001',null,'Duplicate pending requests are prevented');
insert into relief_results(result) select throws_ok($$select public.decide_duty_relief(pg_temp.f('request'),true,'Approved',pg_temp.f('peer'))$$,'42501',null,'Guard cannot approve their own request');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('head')::text,true);end$$;
insert into relief_results(result) select throws_ok($$select public.decide_duty_relief(pg_temp.f('request'),true,'Approved',pg_temp.f('peer'))$$,'P0001',null,'Open attendance requires a confirmed actual Time Out');
insert into relief_results(result) select lives_ok($$select public.decide_duty_relief(pg_temp.f('request'),true,'Confirmed with Guard at duty post',pg_temp.f('peer'),now())$$,'Operational Head confirms actual end and assigns relief');
insert into relief_results(result) select is((select user_id from public.schedules where id=pg_temp.f('duty')),pg_temp.f('guard'),'Original schedule and work retain original Guard');
insert into relief_results(result) select is((select status from public.attendance_sessions where schedule_id=pg_temp.f('duty')),'closed','Original duty is closed');
insert into relief_results(result) select is((select count(*) from public.attendance_timeout_reviews where guard_id=pg_temp.f('guard')),1::bigint,'Verified release has an audit record');
insert into relief_results(result) select is((select user_id from public.schedules where id=(select replacement_schedule_id from public.shift_swap_requests where id=pg_temp.f('request'))),pg_temp.f('peer'),'Replacement receives a separate schedule');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into relief_results(result) select lives_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'Replacement records own Time In');
insert into relief_results(result) select lives_ok($$select public.record_attendance_event('clock_out',null,null)$$,'Time Out succeeds without GPS');
insert into relief_results(result) select is((select clock_out_location_status from public.attendance_sessions where user_id=pg_temp.f('peer')),'unavailable','Missing GPS is explicit, not fabricated');
insert into relief_results(result) select throws_ok($$select public.create_shift_roster(pg_temp.f('site'),date '2098-02-01',2,array[pg_temp.f('guard'),pg_temp.f('peer')])$$,'42501',null,'Guard cannot create a roster');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('head')::text,true);end$$;
insert into relief_results(result) select is((select count(*) from public.create_shift_roster(pg_temp.f('site'),date '2098-02-01',2,array[pg_temp.f('guard'),pg_temp.f('peer')])),2::bigint,'Two shifts are saved together');
insert into relief_results(result) select is((select end_at from public.schedules where user_id=pg_temp.f('peer') and duty_date='2098-02-01'),'2098-02-02 06:00+08'::timestamptz,'Overnight shift ends on next calendar day');
insert into relief_results(result) select is((select count(*) from public.create_shift_roster(pg_temp.f('site'),date '2098-02-02',3,array[pg_temp.f('guard'),pg_temp.f('peer'),pg_temp.f('third')])),3::bigint,'Three shifts are saved together');
insert into relief_results(result) select throws_ok($$select public.create_shift_roster(pg_temp.f('site'),date '2098-02-03',2,array[pg_temp.f('guard'),pg_temp.f('guard')])$$,'P0001',null,'Duplicate Guard selection rejected');
insert into relief_results(result) select throws_ok($$select public.create_shift_roster(pg_temp.f('site'),date '2098-02-03',2,array[pg_temp.f('guard'),pg_temp.f('inspector')])$$,'P0001',null,'Inspector excluded from Guard roster');
-- Conflict in slot 2 must roll back slot 1, including notifications.
insert into relief_results(result) select lives_ok($$select public.create_dtr_schedule(pg_temp.f('peer'),pg_temp.f('site'),date '2098-02-04','[{"period":"auto","start_time":"18:00","end_time":"06:00"}]'::jsonb)$$,'Prepare a conflicting second shift');
insert into relief_results(result) select throws_ok($$select public.create_shift_roster(pg_temp.f('site'),date '2098-02-04',2,array[pg_temp.f('guard'),pg_temp.f('peer')])$$,'P0001',null,'Conflicting roster is rejected atomically');
insert into relief_results(result) select is((select count(*) from public.schedules where duty_date='2098-02-04' and user_id=pg_temp.f('guard')),0::bigint,'Failed roster leaves no partial first shift');
reset role;
insert into public.schedules(id,organization_id,user_id,location_id,location_label,start_at,end_at,duty_date,dtr_period)
  values(pg_temp.f('later'),pg_temp.f('org'),pg_temp.f('third'),pg_temp.f('site'),'Relief fixture',now()-interval '1 hour',now()+interval '2 hours',(now() at time zone 'Asia/Manila')::date,'auto');
insert into storage.objects(bucket_id,name,metadata) values('request-letters',pg_temp.f('third')||'/absence.pdf','{"mimetype":"application/pdf","size":30}'::jsonb);
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('third')::text,true);end$$;
insert into relief_results(result) select lives_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'Another Guard begins duty');
insert into relief_results(result) select lives_ok($$select public.record_attendance_event('clock_out',11.67,123.95)$$,'Time Out outside geofence is recorded');
insert into relief_results(result) select is((select clock_out_location_status from public.attendance_sessions where user_id=pg_temp.f('third')),'outside_post','Outside-post location is flagged');
insert into relief_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('later'),'absence','Unwell and cannot complete remaining duty',pg_temp.f('third')||'/absence.pdf','Absence.pdf')$$,'Today remains requestable after Time Out');
update relief_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('third')||'/absence.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('head')::text,true);end$$;
insert into relief_results(result) select lives_ok($$select public.decide_duty_relief(pg_temp.f('request'),true,'Partial absence approved')$$,'Partial absence preserves closed attendance');
insert into relief_results(result) select is((select count(*) from public.attendance_sessions where user_id=pg_temp.f('third') and clock_out_at is not null),1::bigint,'Partial absence does not erase actual work');
reset role;
insert into relief_results(result) select * from finish();
select result from relief_results order by n;
rollback;
