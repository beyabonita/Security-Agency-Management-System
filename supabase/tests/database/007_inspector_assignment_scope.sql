-- Real RLS/RPC behavior under separate JWT subjects. Every fixture rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
create temp table inspector_fixture(key text primary key, id uuid not null default gen_random_uuid());
insert into inspector_fixture(key) values
 ('admin'),('inspector'),('other_inspector'),('it'),('guard'),('other_guard'),('foreign_guard'),('foreign_org'),
 ('site'),('other_site'),('home_only'),('unassigned_site'),('foreign_site'),
 ('shift'),('other_shift'),('own_shift'),('foreign_shift'),('incident'),('other_incident'),('foreign_incident'),('old_notification');
insert into inspector_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$ select id from pg_temp.inspector_fixture where key=k $$;
insert into public.organizations(id,name,slug,active)
values(pg_temp.f('foreign_org'),'Inspector scope fixture','inspector-scope-' || pg_temp.f('foreign_org')::text,false);
insert into auth.users(id,email,raw_user_meta_data)
select id,'inspector-test-' || id::text || '@example.invalid','{}'::jsonb from inspector_fixture
where key in ('admin','inspector','other_inspector','it','guard','other_guard','foreign_guard');
update public.profiles p set active=true,
 role=case f.key when 'admin' then 'admin'::public.app_role when 'it' then 'it_admin'::public.app_role
   when 'inspector' then 'inspector'::public.app_role when 'other_inspector' then 'inspector'::public.app_role else 'user'::public.app_role end,
 organization_id=case f.key when 'it' then null when 'foreign_guard' then pg_temp.f('foreign_org') else pg_temp.f('org') end
from inspector_fixture f where p.id=f.id;
update public.profiles set inspector_id=pg_temp.f('inspector') where id=pg_temp.f('guard');
update public.profiles set inspector_id=pg_temp.f('other_inspector') where id=pg_temp.f('other_guard');
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
select id,case key when 'foreign_site' then pg_temp.f('foreign_org') else pg_temp.f('org') end,
 'Inspector fixture ' || key,10.67,122.95,100 from inspector_fixture
where key in ('site','other_site','home_only','unassigned_site','foreign_site');
update public.profiles set assigned_location_id=pg_temp.f('home_only') where id=pg_temp.f('guard');
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at)
select id,case key when 'foreign_shift' then pg_temp.f('foreign_org') else pg_temp.f('org') end,
 case key when 'other_shift' then pg_temp.f('other_guard') when 'own_shift' then pg_temp.f('inspector')
   when 'foreign_shift' then pg_temp.f('foreign_guard') else pg_temp.f('guard') end,
 case key when 'other_shift' then pg_temp.f('other_site') when 'foreign_shift' then pg_temp.f('foreign_site') else pg_temp.f('site') end,
 '2098-01-01 08:00+08','2098-01-01 17:00+08' from inspector_fixture where key in ('shift','other_shift','own_shift','foreign_shift');
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,
 scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude,clock_out_at,status)
select organization_id,id,user_id,location_id,'2098-01-01',start_at,end_at,start_at,10.67,122.95,end_at,'closed'
from public.schedules where id in (pg_temp.f('shift'),pg_temp.f('other_shift'),pg_temp.f('foreign_shift'));
insert into public.attendance_punches(organization_id,user_id,punch_date,punch_type,within_geofence)
select organization_id,user_id,'2098-01-01','AM In',true from public.schedules
where id in (pg_temp.f('shift'),pg_temp.f('other_shift'),pg_temp.f('foreign_shift'));
insert into public.guard_assignment_history(organization_id,guard_id,location_id,assigned_by,remarks)
select organization_id,user_id,location_id,pg_temp.f('admin'),'Scope fixture' from public.schedules
where id in (pg_temp.f('shift'),pg_temp.f('other_shift'));
insert into public.accomplishment_reports(organization_id,guard_id,schedule_id,summary,detailed_narrative)
select organization_id,user_id,id,'Scope test completed duty','Detailed scope regression fixture; not a real duty report.'
from public.schedules where id in (pg_temp.f('shift'),pg_temp.f('other_shift'));
insert into public.incidents(id,organization_id,user_id,category,description,photo_data,
 detailed_narrative,captured_at,filed_at,video_path,video_duration_seconds)
select id,case key when 'foreign_incident' then pg_temp.f('foreign_org') else pg_temp.f('org') end,
 case key when 'other_incident' then pg_temp.f('other_guard') when 'foreign_incident' then pg_temp.f('foreign_guard') else pg_temp.f('guard') end,
 'other','Regression incident','AAAA','Regression incident narrative with captured evidence.',now(),now(),
 case key when 'other_incident' then pg_temp.f('other_guard') when 'foreign_incident' then pg_temp.f('foreign_guard') else pg_temp.f('guard') end || '/scope.webm',15
from inspector_fixture where key in ('incident','other_incident','foreign_incident');
-- SQL metadata fixtures only, not actual uploaded files; rolled back afterward.
insert into storage.objects(bucket_id,name,metadata)
select 'incident-videos',video_path,'{"mimetype":"video/webm","size":123}'::jsonb
from public.incidents where id in (pg_temp.f('incident'),pg_temp.f('other_incident'),pg_temp.f('foreign_incident'));
insert into storage.objects(bucket_id,name,metadata)
values('request-letters',pg_temp.f('guard') || '/scope.pdf','{"mimetype":"application/pdf","size":123}');
insert into public.shift_swap_requests(organization_id,requester_id,requested_schedule_id,inspector_id,reason,letter_path,letter_name)
values(pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('shift'),pg_temp.f('inspector'),
 'Private absence fixture',pg_temp.f('guard') || '/scope.pdf','Scope.pdf');
-- Simulate an agency-wide notification produced by the old implementation.
insert into public.user_notifications(id,recipient_id,organization_id,kind,priority,title,message,
 action_key,entity_type,entity_id,requires_ack)
values(pg_temp.f('old_notification'),pg_temp.f('inspector'),pg_temp.f('org'),'emergency','critical',
 'Legacy emergency','This notification belongs to an unassigned Guard.','emergency','incident',pg_temp.f('other_incident'),true);
-- Deliberately add an unsafe permissive legacy policy to prove the restrictive
-- boundary cannot be defeated by a leftover is_staff SELECT policy.
create policy "test legacy staff visibility" on public.profiles for select to authenticated using(public.is_staff());
create policy "test legacy schedule visibility" on public.schedules for select to authenticated using(public.is_staff());
create policy "test legacy media visibility" on storage.objects for select to authenticated using(public.is_staff());
create temp table inspector_results(n integer generated always as identity,result text);
insert into inspector_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.f('inspector')::text,true); end $$;
insert into inspector_results(result) select is((select count(*) from public.profiles where id=pg_temp.f('guard')),1::bigint,'Assigned Guard is visible');
insert into inspector_results(result) select is((select count(*) from public.profiles where id in(pg_temp.f('other_guard'),pg_temp.f('foreign_guard'),pg_temp.f('admin'),pg_temp.f('other_inspector'))),0::bigint,'Unassigned and cross-agency profiles stay hidden despite legacy staff policy');
insert into inspector_results(result) select is((select count(*) from public.profiles where id=pg_temp.f('inspector')),1::bigint,'Inspector sees own profile');
insert into inspector_results(result) select is((select count(*) from public.schedules where id in(pg_temp.f('shift'),pg_temp.f('own_shift'))),2::bigint,'Assigned Guard and own Inspector schedules are readable');
insert into inspector_results(result) select is((select count(*) from public.schedules where id in(pg_temp.f('other_shift'),pg_temp.f('foreign_shift'))),0::bigint,'Unassigned and foreign duty schedules stay hidden');
insert into inspector_results(result) select is((select count(*) from public.attendance_sessions where user_id=pg_temp.f('guard')),1::bigint,'Assigned Guard DTR session is readable');
insert into inspector_results(result) select is((select count(*) from public.attendance_sessions where user_id in(pg_temp.f('other_guard'),pg_temp.f('foreign_guard'))),0::bigint,'Other DTR sessions are hidden');
insert into inspector_results(result) select is((select count(*) from public.attendance_punches where user_id in(pg_temp.f('guard'),pg_temp.f('other_guard'),pg_temp.f('foreign_guard'))),1::bigint,'Legacy attendance rows follow assignment scope');
insert into inspector_results(result) select is((select count(*) from public.locations where id in(pg_temp.f('site'),pg_temp.f('home_only'))),2::bigint,'Assigned Guard scheduled and home posts are readable without RLS recursion');
insert into inspector_results(result) select is((select count(*) from public.locations where id in(pg_temp.f('other_site'),pg_temp.f('unassigned_site'),pg_temp.f('foreign_site'))),0::bigint,'Other deployment sites are hidden');
insert into inspector_results(result) select is((select count(*) from public.guard_assignment_history where guard_id in(pg_temp.f('guard'),pg_temp.f('other_guard'))),1::bigint,'Assignment history follows current supervisor');
insert into inspector_results(result) select is((select count(*) from public.accomplishment_reports where guard_id in(pg_temp.f('guard'),pg_temp.f('other_guard'))),1::bigint,'Only assigned Guard accomplishments are readable');
insert into inspector_results(result) select is((select count(*) from public.incidents where id in(pg_temp.f('incident'),pg_temp.f('other_incident'),pg_temp.f('foreign_incident'))),1::bigint,'Only assigned Guard incidents are readable');
insert into inspector_results(result) select is((select count(*) from storage.objects where name in(pg_temp.f('guard')||'/scope.webm',pg_temp.f('other_guard')||'/scope.webm',pg_temp.f('foreign_guard')||'/scope.webm')),1::bigint,'Only assigned Guard evidence video is readable despite legacy media policy');
insert into inspector_results(result) select is((select count(*) from storage.objects where bucket_id='request-letters' and name=pg_temp.f('guard')||'/scope.pdf'),0::bigint,'Private absence letter is never visible to Inspector');
insert into inspector_results(result) select is((select count(*) from public.shift_swap_requests where requester_id=pg_temp.f('guard')),0::bigint,'Request details remain between Guard and Admin');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where entity_type='profile' and entity_id=pg_temp.f('guard')),1::bigint,'New assignment notifies Inspector');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where kind='emergency' and entity_id=pg_temp.f('incident')),1::bigint,'Assigned Inspector receives new emergency');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where id=pg_temp.f('old_notification')),0::bigint,'Old unassigned-Guard notification body is hidden');
insert into inspector_results(result) select throws_ok($$select public.acknowledge_notification(pg_temp.f('old_notification'))$$,'P0001',null,'Cannot acknowledge hidden legacy alert');
insert into inspector_results(result) select throws_ok($$select public.mark_notification_read(pg_temp.f('old_notification'))$$,'P0001',null,'Cannot mark hidden alert read');
insert into inspector_results(result) select lives_ok($$select public.update_incident_status(pg_temp.f('incident'),'acknowledged','Inspector responding')$$,'Assigned Inspector can acknowledge incident');
insert into inspector_results(result) select lives_ok($$select public.update_incident_status(pg_temp.f('incident'),'resolved','Verified incident is resolved')$$,'Assigned Inspector can resolve properly filed incident');
insert into inspector_results(result) select throws_ok($$select public.update_incident_status(pg_temp.f('other_incident'),'acknowledged','Out of scope')$$,'42501',null,'Inspector cannot use status RPC to bypass assignment');
insert into inspector_results(result) select throws_ok($$select public.update_incident_status(pg_temp.f('foreign_incident'),'resolved','Out of scope')$$,'42501',null,'Foreign incident status RPC is denied');
insert into inspector_results(result) select throws_ok($$select public.assign_guard_inspector(pg_temp.f('other_guard'),pg_temp.f('inspector'))$$,'P0001',null,'Inspector cannot assign themselves more Guards');
insert into inspector_results(result) select throws_ok($$select public.record_attendance_event('in',10.67,122.95)$$,'42501',null,'Inspector Time In remains forbidden');
insert into inspector_results(result) select throws_ok($$select public.record_attendance_event('out',10.67,122.95)$$,'42501',null,'Inspector Time Out remains forbidden');
insert into inspector_results(result) select throws_ok($$select public.review_shift_swap_by_inspector(gen_random_uuid(),true,'Approved')$$,'42501',null,'Inspector cannot approve letters through legacy RPC');
insert into inspector_results(result) select lives_ok($$select public.mark_all_notifications_read()$$,'Bulk read succeeds on visible notifications');
reset role;
insert into inspector_results(result) select ok((select read_at is null from public.user_notifications where id=pg_temp.f('old_notification')),'Bulk read did not mutate hidden legacy notification');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('incident') and kind='emergency' and recipient_id=pg_temp.f('other_inspector')),0::bigint,'Unassigned Inspector was not sent new emergency at all');
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true); end $$;
insert into inspector_results(result) select is((select count(*) from public.incidents where id in(pg_temp.f('incident'),pg_temp.f('other_incident'))),2::bigint,'Admin retains agency-wide incident access');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where kind='emergency' and entity_id in(pg_temp.f('incident'),pg_temp.f('other_incident'))),2::bigint,'Admin receives emergencies from all agency Guards');
insert into inspector_results(result) select lives_ok($$select public.assign_guard_inspector(pg_temp.f('guard'),pg_temp.f('other_inspector'))$$,'Admin can reassign Guard');
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.f('inspector')::text,true); end $$;
insert into inspector_results(result) select is((select count(*) from public.incidents where id=pg_temp.f('incident')),0::bigint,'Reassignment immediately removes old Inspector incident access');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('incident')),0::bigint,'Reassignment immediately hides persisted emergency payload');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('guard')),0::bigint,'Old assignment notification no longer reveals reassigned Guard');
insert into inspector_results(result) select is((select count(*) from storage.objects where name=pg_temp.f('guard')||'/scope.webm'),0::bigint,'Reassignment removes evidence video read access');
insert into inspector_results(result) select throws_ok($$select public.update_incident_status(pg_temp.f('incident'),'open','No longer assigned')$$,'42501',null,'Old Inspector cannot reopen after reassignment');
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.f('other_inspector')::text,true); end $$;
insert into inspector_results(result) select is((select count(*) from public.incidents where id=pg_temp.f('incident')),1::bigint,'New Inspector can review assigned Guard historical reports');
insert into inspector_results(result) select is((select count(*) from public.user_notifications where entity_type='profile' and entity_id=pg_temp.f('guard')),1::bigint,'New Inspector receives assignment notification');
do $$ begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true); end $$;
insert into inspector_results(result) select is((select count(*) from public.incidents where id=pg_temp.f('incident')),1::bigint,'Guard keeps own report access after reassignment');
insert into inspector_results(result) select ok(exists(select 1 from public.user_notifications where entity_type='profile' and entity_id=pg_temp.f('guard') and title='Inspector assignment updated'),'Guard retains Inspector reassignment notification');
reset role;
insert into inspector_results(result) select * from finish();
select result from inspector_results order by n;
rollback;
