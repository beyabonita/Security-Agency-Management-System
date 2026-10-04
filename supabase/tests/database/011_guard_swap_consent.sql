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

insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'Guard submits exchange');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/swap.pdf') where key='request';
insert into exchange_results(result) select is((select guard_response from public.shift_swap_requests where id=pg_temp.f('request')),'pending','Swap initially awaits Guard consent');
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'42501',null,'Requester cannot approve own swap');
reset role;
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),0::bigint,'Operations Head is not notified before consent');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'Operations Head cannot bypass Guard consent');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('other')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'42501',null,'Unrelated Guard cannot respond');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.shift_swap_requests where id=pg_temp.f('request')),1::bigint,'Target Guard can read invitation');
insert into exchange_results(result) select lives_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'Target Guard accepts');
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),false)$$,'P0001',null,'Response cannot execute twice');
reset role;
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('guard'),'Consent alone does not alter schedules');
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),1::bigint,'Operations Head notified after consent');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'Operations Head approves accepted swap');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('peer'),'Peer assigned original duty');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Requester assigned exchanged duty');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('target'),pg_temp.f('offered'),'Please exchange back',pg_temp.f('guard')||'/again.pdf','Letter.pdf')$$,'Second exchange can be requested');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/again.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),false)$$,'Target Guard declines');
insert into exchange_results(result) select is((select guard_response from public.shift_swap_requests where id=pg_temp.f('request')),'declined','Decline is recorded');
reset role;
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),0::bigint,'Declined request is not forwarded');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Decline leaves schedule unchanged');
-- Deployment detail resolution and map snapshot shape.
update public.locations set address='123 Main Street, Bacolod, Negros Occidental, Philippines' where id=pg_temp.f('site');
update public.profiles set assigned_location_id=pg_temp.f('site') where id=pg_temp.f('guard');
insert into exchange_results(result) select ok(private.guard_deployment_label(pg_temp.f('guard'),pg_temp.f('org'),now()) like '%123 Main Street%','Site resolver returns full saved address');
insert into exchange_results(result) select ok(public.live_guard_map_snapshot() ? 'server_now' and public.live_guard_map_snapshot() ? 'locations','Live map preserves snapshot contract');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.file_incident_report('other',repeat('A',104),'Test narrative',now(),null,null,10.67,122.95,null)$$,'Incident filing resolves the assigned home post without a client label');
reset role;
insert into exchange_results(result) select ok((select location_label like '%123 Main Street%' from public.incidents where user_id=pg_temp.f('guard') order by created_at desc limit 1),'New incident stores full deployment address');
update exchange_fixture set id=(select id from public.incidents where user_id=pg_temp.f('guard') order by created_at desc limit 1) where key='request';
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('other')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.incident_deployment_site(pg_temp.f('request'))$$,'42501',null,'Unrelated Guard cannot retrieve incident site');
reset role;
insert into exchange_results(result) select * from finish();
select result from exchange_results order by n;
rollback;
