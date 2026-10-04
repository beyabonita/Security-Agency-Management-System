begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
-- Legacy accounts can remain unset until Operations Head adds their number.
alter table public.profiles add column mobile_number text
  constraint profiles_mobile_number_format check (mobile_number is null or mobile_number ~ '^09[0-9]{9}$');

create or replace function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('server_now',now(),'locations',coalesce((
    select jsonb_agg(to_jsonb(g)||jsonb_build_object(
      'location_label',concat_ws(' · ',coalesce(nullif(l.label,''),g.location_label),nullif(l.address,'')),
      'mobile_number',p.mobile_number))
    from public.list_live_guard_locations() g
    join public.profiles p on p.id=g.user_id
    join public.attendance_sessions a on a.id=g.session_id
    left join public.schedules s on s.id=a.schedule_id
    left join public.locations l on l.id=s.location_id and l.organization_id=s.organization_id
  ),'[]'::jsonb));
$$;
revoke all on function public.live_guard_map_snapshot() from public,anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;
notify pgrst,'reload schema';

-- Real RLS/RPC behavior under separate JWT subjects. Every fixture rolls back.

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
 now()-interval '1 hour',now()+interval '7 hours' from inspector_fixture where key in ('shift','other_shift','own_shift','foreign_shift');
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
select organization_id,id,user_id,location_id,(start_at at time zone 'Asia/Manila')::date,start_at,end_at,start_at,10.67,122.95 from public.schedules where id in(pg_temp.f('shift'),pg_temp.f('other_shift'),pg_temp.f('foreign_shift'));
create temp table mobile_results(n integer generated always as identity,result text);
insert into mobile_results(result) select no_plan();
insert into mobile_results(result) select lives_ok($$update public.profiles set mobile_number='09123456789' where id=pg_temp.f('guard')$$,'Valid Philippine mobile number is stored');
insert into mobile_results(result) select throws_ok($$update public.profiles set mobile_number='0912345678' where id=pg_temp.f('guard')$$,'23514',null,'Short number rejected by database');
insert into mobile_results(result) select throws_ok($$update public.profiles set mobile_number='091234567890' where id=pg_temp.f('guard')$$,'23514',null,'Long number rejected by database');
insert into mobile_results(result) select throws_ok($$update public.profiles set mobile_number='08123456789' where id=pg_temp.f('guard')$$,'23514',null,'Non-mobile prefix rejected by database');
insert into mobile_results(result) select throws_ok($$update public.profiles set mobile_number='0912345678x' where id=pg_temp.f('guard')$$,'23514',null,'Nondigits rejected by database');
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('inspector')::text,true);end$$;
insert into mobile_results(result) select is((select r->>'mobile_number' from jsonb_array_elements(public.live_guard_map_snapshot()->'locations') r where r->>'user_id'=pg_temp.f('guard')::text),'09123456789','Assigned Inspector sees guard mobile on map');
insert into mobile_results(result) select is((select count(*) from jsonb_array_elements(public.live_guard_map_snapshot()->'locations') r where r->>'user_id'=pg_temp.f('other_guard')::text),0::bigint,'Inspector cannot see another inspectors guard');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('other_inspector')::text,true);end$$;
insert into mobile_results(result) select is((select count(*) from jsonb_array_elements(public.live_guard_map_snapshot()->'locations') r where r->>'user_id'=pg_temp.f('guard')::text),0::bigint,'Unassigned Inspector cannot read guard number');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into mobile_results(result) select is((select r->>'mobile_number' from jsonb_array_elements(public.live_guard_map_snapshot()->'locations') r where r->>'user_id'=pg_temp.f('guard')::text),'09123456789','Operations Head sees guard mobile on map');
insert into mobile_results(result) select ok((select (r->>'mobile_number') is null from jsonb_array_elements(public.live_guard_map_snapshot()->'locations') r where r->>'user_id'=pg_temp.f('other_guard')::text),'Legacy number remains null');
reset role;
insert into mobile_results(result) select * from finish();
select result from mobile_results order by n;
rollback;