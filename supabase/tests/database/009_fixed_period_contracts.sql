begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
create temp table contract_fixture(key text primary key,id uuid not null default gen_random_uuid());
insert into contract_fixture(key) values ('admin'),('guard'),('regular'),('legacy'),('site'),('open');
insert into contract_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.contract_fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data)
select id,'contract-test-'||id||'@example.invalid','{}'::jsonb from contract_fixture where key in ('admin','guard','regular','legacy');
update public.profiles p set role=case when f.key='admin' then 'admin'::public.app_role else 'user'::public.app_role end,
 organization_id=pg_temp.f('org'),active=true,
 employment_category=case when f.key in ('guard','legacy') then 'contract' else 'regular' end,
 contract_start_date=case when f.key='guard' then date '2099-01-01' end,
 contract_end_date=case when f.key='guard' then date '2099-01-02' end
from contract_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
values(pg_temp.f('site'),pg_temp.f('org'),'Contract rollback site',10.67,122.95,100);
create temp table contract_results(n integer generated always as identity,result text);
insert into contract_results(result) select no_plan();
insert into contract_results(result) select ok(private.contract_allows_duty(pg_temp.f('guard'),'2099-01-01 00:00+08','2099-01-03 00:00+08'),'Start and inclusive end boundaries are allowed');
insert into contract_results(result) select ok(not private.contract_allows_duty(pg_temp.f('guard'),'2098-12-31 23:59+08','2099-01-01 08:00+08'),'A minute before contract starts is rejected');
insert into contract_results(result) select ok(not private.contract_allows_duty(pg_temp.f('guard'),'2099-01-02 20:00+08','2099-01-03 04:00+08'),'Overnight duty cannot run beyond inclusive end date');
insert into contract_results(result) select ok(private.contract_allows_duty(pg_temp.f('regular'),'2100-01-01 08:00+08','2100-01-01 17:00+08'),'Regular has no contract limit');
insert into contract_results(result) select ok(not private.contract_allows_duty(pg_temp.f('legacy'),'2099-01-01 08:00+08','2099-01-01 17:00+08'),'Legacy missing dates fail closed');
insert into contract_results(result) select throws_ok($$update public.profiles set contract_end_date='2098-01-01' where id=pg_temp.f('guard')$$,'23514',null,'Reversed contract dates rejected');
insert into contract_results(result) select throws_ok($$update public.profiles set contract_end_date=null where id=pg_temp.f('guard')$$,'23514',null,'Partial contract dates rejected');
insert into contract_results(result) select throws_ok($$update public.profiles set employment_category='regular' where id=pg_temp.f('guard')$$,'23514',null,'Changing to Regular must clear contract dates');
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into contract_results(result) select lives_ok($$select public.create_dtr_schedule(pg_temp.f('guard'),pg_temp.f('site'),'2099-01-01','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$$,'Admin schedules Contract guard within period');
insert into contract_results(result) select throws_ok($$select public.create_dtr_schedule(pg_temp.f('guard'),pg_temp.f('site'),'2099-01-03','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$$,'P0001',null,'RPC rejects out-of-contract duty');
insert into contract_results(result) select throws_ok($$select public.create_dtr_schedule(pg_temp.f('legacy'),pg_temp.f('site'),'2099-01-01','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$$,'P0001',null,'RPC rejects contract without dates');
insert into contract_results(result) select lives_ok($$select public.create_dtr_schedule(pg_temp.f('regular'),pg_temp.f('site'),'2099-01-03','[{"period":"morning","start_time":"08:00","end_time":"12:00"}]')$$,'Regular future schedule remains available');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into contract_results(result) select throws_ok($$update public.profiles set contract_end_date='2100-01-01' where id=pg_temp.f('guard')$$,'42501',null,'Guard cannot extend own contract');
reset role;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
-- Exchange picker checks both receiving contract windows, not only the source.
insert into contract_results(result) select ok(not private.duty_exchange_eligible(
 (select id from public.schedules where user_id=pg_temp.f('guard')),
 (select id from public.schedules where user_id=pg_temp.f('regular'))),'Reciprocal exchange outside recipient contract is excluded');
update public.profiles set contract_end_date='2099-01-03' where id=pg_temp.f('guard');
insert into contract_results(result) select ok(private.duty_exchange_eligible(
 (select id from public.schedules where user_id=pg_temp.f('guard')),
 (select id from public.schedules where user_id=pg_temp.f('regular'))),'Renewing contract enables eligible exchange');
-- A date change does not delete or rewrite an already-created duty.
update public.profiles set contract_start_date='2000-01-01',contract_end_date='2000-12-31' where id=pg_temp.f('guard');
insert into contract_results(result) select is((select count(*) from public.schedules where user_id=pg_temp.f('guard')),1::bigint,'Schedule history survives contract expiry');
insert into contract_results(result) select throws_ok($$
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
select organization_id,id,user_id,location_id,duty_date,start_at,end_at,now(),10.67,122.95 from public.schedules where user_id=pg_temp.f('guard')
$$,'P0001',null,'Expired contract cannot start an existing future duty');
update public.profiles set contract_start_date='2000-01-01',contract_end_date='2099-12-31' where id=pg_temp.f('guard');
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at,duty_date,dtr_period)
values(pg_temp.f('open'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),now()-interval '1 hour',now()+interval '1 hour',(now() at time zone 'Asia/Manila')::date,'auto');
insert into contract_results(result) select lives_ok($$
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
select organization_id,id,user_id,location_id,duty_date,start_at,end_at,now()-interval '10 minutes',10.67,122.95 from public.schedules where id=pg_temp.f('open')
$$,'Current contract allows attendance');
update public.profiles set contract_end_date='2000-12-31' where id=pg_temp.f('guard');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into contract_results(result) select lives_ok($$select public.record_attendance_event('clock_out',10.67,122.95)$$,'An open duty can clock out after contract expiry');
reset role;
insert into contract_results(result) select is((select status from public.attendance_sessions where schedule_id=pg_temp.f('open')),'closed','Expired-contract Time Out is actually persisted');
insert into contract_results(result) select * from finish();
select result from contract_results order by n;
rollback;
