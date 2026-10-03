-- Behavior tests under real JWT subjects. All fixtures roll back, including notifications.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
create temp table request_fixture(key text primary key, id uuid not null default gen_random_uuid());
insert into request_fixture(key) values ('hr'),('guard'),('cover'),('inspector'),('site'),('absence'),('swap'),('busy'),('incident'),('request');
insert into request_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.request_fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data) select id,'request-test-'||id::text||'@example.invalid','{}'::jsonb
from request_fixture where key in ('hr','guard','cover','inspector');
update public.profiles p set role=case f.key when 'hr' then 'admin'::public.app_role when 'inspector' then 'inspector'::public.app_role else 'user'::public.app_role end,
  active=true, organization_id=pg_temp.f('org') from request_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
values(pg_temp.f('site'),pg_temp.f('org'),'Request test site',10.67,122.95,100);
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at)
select id,pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'2098-01-01 08:00+08'::timestamptz+row_number() over(order by key)*interval '1 day',
 '2098-01-01 17:00+08'::timestamptz+row_number() over(order by key)*interval '1 day'
from request_fixture where key in ('absence','swap');
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at)
select pg_temp.f('busy'),organization_id,pg_temp.f('cover'),location_id,start_at,end_at from public.schedules where id=pg_temp.f('swap');
-- Metadata fixtures only: no physical Storage objects are created or deleted by this SQL test.
insert into storage.objects(bucket_id,name,metadata) values
('request-letters',pg_temp.f('guard')||'/absence.pdf','{"mimetype":"application/pdf","size":30}'),
('request-letters',pg_temp.f('guard')||'/swap.pdf','{"mimetype":"application/pdf","size":30}'),
('request-letters',pg_temp.f('guard')||'/other.pdf','{"mimetype":"application/pdf","size":30}'),
('request-letters',pg_temp.f('guard')||'/large.pdf','{"mimetype":"application/pdf","size":6000000}'),
('request-letters',pg_temp.f('guard')||'/wrong.pdf','{"mimetype":"text/html","size":30}'),
('request-letters',pg_temp.f('cover')||'/foreign.pdf','{"mimetype":"application/pdf","size":30}');
insert into public.incidents(id,user_id,organization_id,category,description,photo_data) values(pg_temp.f('incident'),pg_temp.f('guard'),pg_temp.f('org'),'other','Isolated regression fixture','AAAA');
create temp table request_results(n integer generated always as identity, result text);
insert into request_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated,service_role;
grant all on all sequences in schema pg_temp to authenticated,service_role;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into request_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Test reason',null,'Letter.pdf')$$,'P0001',null,'Missing letter is rejected');
insert into request_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Test reason',pg_temp.f('cover')||'/foreign.pdf','Letter.pdf')$$,'P0001',null,'Another Guard letter cannot be used');
insert into request_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Test reason',pg_temp.f('guard')||'/large.pdf','Letter.pdf')$$,'P0001',null,'Oversized letter is rejected');
insert into request_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Test reason',pg_temp.f('guard')||'/wrong.pdf','Letter.pdf')$$,'P0001',null,'HTML masquerading as PDF metadata is rejected');
insert into request_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Family appointment',pg_temp.f('guard')||'/absence.pdf','Letter.pdf')$$,'Guard submits letter without an assigned Inspector');
update request_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/absence.pdf') where key='request';
insert into request_results(result) select is((select status from public.shift_swap_requests where id=pg_temp.f('request')),'pending_admin','Request goes directly to HR');
insert into request_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Family appointment',pg_temp.f('guard')||'/absence.pdf','Letter.pdf')$$,'Retry after a lost response is idempotent');
insert into request_results(result) select throws_ok($$select public.submit_duty_request(pg_temp.f('absence'),'absence','Another reason',pg_temp.f('guard')||'/other.pdf','Letter.pdf')$$,'P0001',null,'Duplicate pending request is blocked');
insert into request_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'42501',null,'Guard cannot approve');
insert into request_results(result) select throws_ok($$select public.manage_incident_deletion(pg_temp.f('incident'),pg_temp.f('hr'),false)$$,'42501',null,'Client cannot forge a deletion actor');
insert into request_results(result) select throws_ok($$delete from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/absence.pdf'$$,'42501',null,'Direct Storage catalogue deletion is blocked');
insert into request_results(result) select is((select count(*) from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/absence.pdf'),1::bigint,'A submitted letter cannot be removed by its Guard');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('inspector')::text,true);end$$;
insert into request_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'42501',null,'Inspector cannot approve');
insert into request_results(result) select is((select count(*) from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/absence.pdf'),0::bigint,'Inspector cannot read private HR letters');
insert into request_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request')),0::bigint,'No Inspector review notification');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('hr')::text,true);end$$;
insert into request_results(result) select is((select count(*) from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/absence.pdf'),1::bigint,'HR can read the submitted letter');
insert into request_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request')),1::bigint,'HR receives a direct approval notification');
insert into request_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true,'Approved absence')$$,'HR approves absence');
insert into request_results(result) select is((select approval_status from public.schedules where id=pg_temp.f('absence')),'cancelled','Absence cancels, rather than deletes, the duty');
insert into request_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'A decided request cannot be processed twice');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into request_results(result) select lives_ok($$select public.submit_duty_request(pg_temp.f('swap'),'swap','Please arrange coverage',pg_temp.f('guard')||'/swap.pdf','Swap.pdf')$$,'Guard submits swap letter');
update request_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/swap.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('hr')::text,true);end$$;
insert into request_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'Swap requires a replacement Guard');
insert into request_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true,'',pg_temp.f('cover'))$$,'P0001',null,'Overlapping replacement duty is rejected');
update public.schedules set approval_status='cancelled' where id=pg_temp.f('busy');
insert into request_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true,'Coverage approved',pg_temp.f('cover'))$$,'HR approves an available replacement');
insert into request_results(result) select is((select user_id from public.schedules where id=(select replacement_schedule_id from public.shift_swap_requests where id=pg_temp.f('request'))),pg_temp.f('cover'),'Approved coverage creates the replacement Guard assignment');
reset role;
insert into request_results(result) select throws_ok($$insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
select organization_id,id,pg_temp.f('guard'),location_id,'2098-01-02',start_at,end_at,start_at,10.67,122.95 from public.schedules where id=pg_temp.f('absence')$$,'P0001',null,'Stale Time In cannot enter an approved absence');
insert into request_results(result) select throws_ok($$insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
select organization_id,id,pg_temp.f('guard'),location_id,'2098-01-03',start_at,end_at,start_at,10.67,122.95 from public.schedules where id=pg_temp.f('swap')$$,'P0001',null,'Stale Time In cannot enter another Guard assignment');
set local role service_role;
insert into request_results(result) select throws_ok($$select public.manage_incident_deletion(pg_temp.f('incident'),pg_temp.f('guard'),false)$$,'42501',null,'Deletion independently verifies the active HR role');
insert into request_results(result) select lives_ok($$select public.manage_incident_deletion(pg_temp.f('incident'),pg_temp.f('hr'),false)$$,'HR deletion starts cleanup');
insert into request_results(result) select lives_ok($$select public.manage_incident_deletion(pg_temp.f('incident'),pg_temp.f('hr'),true)$$,'Photo-only incident deletion completes');
insert into request_results(result) select lives_ok($$select public.manage_incident_deletion(pg_temp.f('incident'),pg_temp.f('hr'),true)$$,'Repeated deletion is idempotent');
reset role;
insert into request_results(result) select is((select count(*) from public.incidents where id=pg_temp.f('incident')),0::bigint,'Report and database photo are removed');
insert into request_results(result) select is((select count(*) from public.incident_deletion_audit where incident_id=pg_temp.f('incident')),1::bigint,'A small deletion audit is retained without media');
insert into request_results(result) select * from finish();
select result from request_results order by n;
rollback;
