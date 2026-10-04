-- Real INSERT/UPDATE/DELETE under authenticated JWT subjects, not policy-text
-- assertions alone. All fixtures, notifications and attendance roll back.
begin;
set local storage.allow_delete_query='true';
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
update public.profiles set active=true,inspector_id=pg_temp.fixture_id('inspector') where id=pg_temp.fixture_id('guard');
insert into storage.objects(bucket_id,name,metadata)
select 'accomplishment-photos',pg_temp.fixture_id('guard')||'/'||lpad(n::text,32,'0')||'.jpg',
 '{"mimetype":"image/jpeg","size":200}'::jsonb from generate_series(1,5) n;
create function pg_temp.photo(n integer) returns text language sql stable as $$select pg_temp.fixture_id('guard')||'/'||lpad(n::text,32,'0')||'.jpg'$$;
create temp table photo_results(n integer generated always as identity,result text);
insert into photo_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.fixture_id('guard')::text,true);end$$;
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('unused'),'OK','Done','',pg_temp.photo(1),'photo.jpg')$$,'P0001',null,'Report cannot be submitted before Time In');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','Done','',null,'photo.jpg')$$,'P0001',null,'Photo is required');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'','Done','',pg_temp.photo(1),'photo.jpg')$$,'P0001',null,'Summary is required');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','','',pg_temp.photo(1),'photo.jpg')$$,'P0001',null,'Narrative is required');
insert into photo_results(result) select lives_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','Done','',pg_temp.photo(1),'photo.jpg')$$,'Guard can submit during an open duty');
insert into photo_results(result) select lives_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','Done','',pg_temp.photo(1),'photo.jpg')$$,'Retry returns the existing report');
insert into photo_results(result) select is((select count(*) from public.accomplishment_reports where photo_path=pg_temp.photo(1)),1::bigint,'Retry does not duplicate report');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'Changed','Done','',pg_temp.photo(1),'photo.jpg')$$,'P0001',null,'Already filed photo cannot be reassigned to changed content');
insert into photo_results(result) select lives_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('closed'),'Handover','Complete','',pg_temp.photo(2),'photo.jpg')$$,'Guard can submit after Time Out');
insert into photo_results(result) select lives_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'Update','Follow-up','',pg_temp.photo(3),'photo.jpg')$$,'Another report for the same duty preserves the earlier report');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','Done','')$$,'P0001',null,'Older text-only RPC cannot bypass photo requirement');
delete from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(1);
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(1)),1::bigint,'Filed photo cannot be deleted by Guard');
delete from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(4);
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(4)),0::bigint,'Unsubmitted photo can be discarded');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.fixture_id('foreign_guard')::text,true);end$$;
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(1)),0::bigint,'Unrelated Guard cannot read a filed photo');
insert into photo_results(result) select throws_ok($$select public.submit_accomplishment_report(pg_temp.fixture_id('open'),'OK','Done','',pg_temp.photo(5),'photo.jpg')$$,'42501',null,'Inactive foreign organization cannot submit');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.fixture_id('inspector')::text,true);end$$;
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(1)),1::bigint,'Assigned Inspector can read filed photo');
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(5)),0::bigint,'Inspector cannot read an unsubmitted photo');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.fixture_id('hr')::text,true);end$$;
insert into photo_results(result) select is((select count(*) from storage.objects where bucket_id='accomplishment-photos' and name=pg_temp.photo(1)),1::bigint,'Operations Head can read filed photo');
reset role;
insert into photo_results(result) select * from finish();
select result from photo_results order by n;
rollback;