-- Rollback-only behavioral tests. No real Guard's duties or uploaded files are changed.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
create temp table exchange_fixture(key text primary key,id uuid not null default gen_random_uuid());
insert into exchange_fixture(key) values ('admin'),('guard'),('peer'),('other'),('inspector'),('site'),('site2'),
 ('offered'),('target'),('conflict'),('request'),('ended'),('draft'),('absent'),('started'),('foreign_org');
insert into exchange_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.exchange_fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data)
 select id,'exchange-test-'||id::text||'@example.invalid','{}'::jsonb
 from exchange_fixture where key in ('admin','guard','peer','other','inspector');
update public.profiles p set role=case f.key when 'admin' then 'admin'::public.app_role
 when 'inspector' then 'inspector'::public.app_role else 'user'::public.app_role end,
 active=true,organization_id=pg_temp.f('org'),first_name='Exchange',last_name=f.key,
 employment_category=case when f.key='peer' then 'contract' else 'regular' end,
 contract_start_date=case when f.key='peer' then date '2000-01-01' end,
 contract_end_date=case when f.key='peer' then date '2099-12-31' end
 from exchange_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
 values(pg_temp.f('site'),pg_temp.f('org'),'Exchange Site A',10.67,122.95,100),
 (pg_temp.f('site2'),pg_temp.f('org'),'Exchange Site B',10.68,122.96,100);
-- Same-time different-post exchange exercises intermediate-overlap handling.
insert into public.schedules(id,organization_id,user_id,location_id,location_label,start_at,end_at,duty_date,dtr_period)
 values(pg_temp.f('offered'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'Exchange Site A','2098-01-01 08:00+08','2098-01-01 12:00+08','2098-01-01','morning'),
 (pg_temp.f('target'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-01 08:00+08','2098-01-01 12:00+08','2098-01-01','morning'),
 (pg_temp.f('absent'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'Exchange Site A','2098-01-02 08:00+08','2098-01-02 12:00+08','2098-01-02','morning'),
 (pg_temp.f('draft'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-03 08:00+08','2098-01-03 12:00+08','2098-01-03','morning'),
 (pg_temp.f('started'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-04 08:00+08','2098-01-04 12:00+08','2098-01-04','morning'),
 (pg_temp.f('ended'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B',now()-interval '6 hours',now()-interval '2 hours',current_date,'morning');
update public.schedules set approval_status='draft' where id=pg_temp.f('draft');
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
 select organization_id,id,user_id,location_id,duty_date,start_at,end_at,start_at,10.68,122.96 from public.schedules where id=pg_temp.f('started');
insert into storage.objects(bucket_id,name,metadata)
 select 'request-letters',pg_temp.f('guard')||'/'||n||'.pdf','{"mimetype":"application/pdf","size":30}'::jsonb
 from unnest(array['swap','absence','again','stale','started','reject']) n;
insert into storage.objects(bucket_id,name,metadata) values
 ('request-letters',pg_temp.f('peer')||'/absence.pdf','{"mimetype":"application/pdf","size":30}');
create temp table exchange_results(n integer generated always as identity,result text);
insert into exchange_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.schedules where user_id=pg_temp.f('peer')),0::bigint,'Guard cannot directly read peer schedules');
insert into exchange_results(result) select is((select count(*) from public.available_duty_swaps(pg_temp.f('offered')) where id in (select id from exchange_fixture)),1::bigint,'Picker lists the eligible peer duty only');
insert into exchange_results(result) select is((select guard_name from public.available_duty_swaps(pg_temp.f('offered')) where id=pg_temp.f('target')),'Exchange peer','Picker supplies a Guard name, not an email or private profile');
insert into exchange_results(result) select throws_ok($$select public.available_duty_swaps(pg_temp.f('target'))$$,'42501',null,'Cannot enumerate using another Guard source');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('offered'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'P0001',null,'Self exchange is rejected');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('started'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'P0001',null,'Recorded attendance cannot be offered');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',null,'Letter.pdf')$$,'P0001',null,'An exchange requires a real uploaded letter');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',pg_temp.f('peer')||'/absence.pdf','Letter.pdf')$$,'P0001',null,'Another Guard letter is rejected');
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'Guard requests a reciprocal exchange');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/swap.pdf') where key='request';
insert into exchange_results(result) select is((select status from public.shift_swap_requests where id=pg_temp.f('request')),'pending_admin','Exchange awaits Admin approval');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('guard'),'Submitting does not reassign a duty');
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'Lost-response retry is idempotent');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('draft'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'P0001',null,'Retry cannot change the target');
insert into exchange_results(result) select is((select count(*) from public.available_duty_swaps(pg_temp.f('absent')) where id in (select id from exchange_fixture)),0::bigint,'Pending target is unavailable for another exchange');
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'42501',null,'Guard cannot approve an exchange');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('target'),'absence','Need absence',pg_temp.f('peer')||'/absence.pdf','Letter.pdf')$$,'P0001',null,'Legacy app cannot file absence against a pending exchange target');
insert into exchange_results(result) select is((select count(*) from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/swap.pdf'),0::bigint,'Target Guard cannot read the private letter');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('inspector')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.available_duty_swaps(pg_temp.f('offered'))$$,'42501',null,'Inspector cannot use the Guard picker');
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'42501',null,'Inspector cannot approve the exchange');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true,'',pg_temp.f('other'))$$,'P0001',null,'Admin cannot substitute an unrelated replacement');
insert into exchange_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true,'Exchange approved')$$,'Admin exchanges two simultaneous duties atomically');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('peer'),'Peer takes requester duty');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Requester takes peer duty');
insert into exchange_results(result) select is((select duty_category from public.schedules where id=pg_temp.f('offered')),'contract','Receiving Guard duty category is preserved');
insert into exchange_results(result) select is((select location_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('site'),'Original post/geofence stays with the duty');
insert into exchange_results(result) select is((select dtr_period from public.schedules where id=pg_temp.f('target')),'morning','DTR column mapping is preserved');
insert into exchange_results(result) select is((select duty_date::text from public.schedules where id=pg_temp.f('target')),'2098-01-01','DTR date is preserved');
insert into exchange_results(result) select is((select count(*) from public.schedules where id in (pg_temp.f('offered'),pg_temp.f('target')) and approval_status='changed'),2::bigint,'Both final duties are approved changed, never left draft');
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'A decision cannot execute twice');
reset role;
insert into exchange_results(result) select is((select count(distinct recipient_id) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id in (pg_temp.f('guard'),pg_temp.f('peer'))),2::bigint,'Both Guards receive decision notifications');
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id in (pg_temp.f('offered'),pg_temp.f('target')) and title='Duty schedule cancelled'),0::bigint,'Exchange does not create false cancellation notifications');

-- Cross-tenant peer candidates must never be disclosed, even without RLS.
update public.profiles set organization_id=null where id=pg_temp.f('peer');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.available_duty_swaps(pg_temp.f('target')) where id in (select id from exchange_fixture)),0::bigint,'Guard outside the agency is excluded');
reset role;
update public.profiles set organization_id=pg_temp.f('org') where id=pg_temp.f('peer');

-- Stale snapshot is rejected without partially changing either duty.
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('target'),pg_temp.f('offered'),'Exchange back',pg_temp.f('guard')||'/stale.pdf','Letter.pdf')$$,'A decided exchange can be requested again');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/stale.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
update public.schedules set end_at=end_at+interval '10 minutes' where id=pg_temp.f('offered');
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'Changed offered details require a fresh request');
insert into exchange_results(result) select is((select status from public.shift_swap_requests where id=pg_temp.f('request')),'pending_admin','Failed approval preserves request for review');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Failed approval leaves requester assigned');
insert into exchange_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),false,'Duty details have changed')$$,'Admin can reject a stale request');

-- Validate overlap in both receiving directions; source and target themselves
-- are excluded because they exchange owners together.
reset role;
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at)
 values(pg_temp.f('conflict'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'2098-01-02 09:00+08','2098-01-02 11:00+08');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.available_duty_swaps(pg_temp.f('absent')) where id=pg_temp.f('offered')),0::bigint,'Picker excludes a duty that would overlap after exchange');
insert into exchange_results(result) select throws_ok($$select public.submit_duty_exchange(pg_temp.f('absent'),pg_temp.f('offered'),'Exchange with conflict',pg_temp.f('guard')||'/again.pdf','Letter.pdf')$$,'P0001',null,'Server rejects an overlapping receiving duty');
insert into exchange_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('absent'),'absence','Need an absence',pg_temp.f('guard')||'/absence.pdf','Letter.pdf')$$,'Absence still works through the existing RPC');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/absence.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'Admin still approves an absence');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.schedules where id=pg_temp.f('absent') and approval_status in ('approved','changed')),0::bigint,'Approved absence is absent from the active My Schedule query');
insert into exchange_results(result) select is((select count(*) from public.shift_swap_requests where id=pg_temp.f('request') and status='approved'),1::bigint,'Approved absence remains in request history');
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('target'),pg_temp.f('offered'),'Another exchange',pg_temp.f('guard')||'/again.pdf','Letter.pdf')$$,'Create an exchange for authority revalidation');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/again.pdf') where key='request';
reset role;
insert into public.organizations(id,name,slug,active)
 values(pg_temp.f('foreign_org'),'Exchange foreign fixture','exchange-foreign-'||pg_temp.f('foreign_org')::text,false);
-- Simulate a privileged historical workspace move after submission. No real
-- organization, Guard or duty is changed; every ID belongs to this fixture.
update public.profiles set organization_id=pg_temp.f('foreign_org') where id in (pg_temp.f('guard'),pg_temp.f('peer'));
update public.locations set organization_id=pg_temp.f('foreign_org') where id in (pg_temp.f('site'),pg_temp.f('site2'));
update public.schedules set organization_id=pg_temp.f('foreign_org') where id in (pg_temp.f('target'),pg_temp.f('offered'));
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'An old request cannot authorize an exchange in a different agency');
insert into exchange_results(result) select is((select status from public.shift_swap_requests where id=pg_temp.f('request')),'pending_admin','Unauthorized moved exchange remains undecided');
reset role;
insert into exchange_results(result) select * from finish();
select result from exchange_results order by n;
rollback;
