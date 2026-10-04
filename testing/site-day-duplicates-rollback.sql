begin;
set local lock_timeout='5s';
-- Retain historical duplicates; prevent new assignments and second Time Ins.
create function private.enforce_one_guard_duty_per_site_day()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_day date := coalesce(new.duty_date,(new.start_at at time zone 'Asia/Manila')::date);
begin
  if new.approval_status not in ('approved','changed') then return new; end if;
  -- Existing duplicate rows must still permit Time Out/completion and review.
  if tg_op='UPDATE' and old.approval_status in ('approved','changed')
    and new.organization_id is not distinct from old.organization_id
    and new.user_id is not distinct from old.user_id
    and new.location_id is not distinct from old.location_id
    and v_day is not distinct from coalesce(old.duty_date,(old.start_at at time zone 'Asia/Manila')::date)
    and new.start_at is not distinct from old.start_at and new.end_at is not distinct from old.end_at
  then return new; end if;
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(new.organization_id::text||':'||new.user_id::text,0));
  if exists(select 1 from public.schedules s where s.id<>new.id
    and s.organization_id=new.organization_id and s.user_id=new.user_id
    and s.location_id=new.location_id and s.approval_status in ('approved','changed')
    and coalesce(s.duty_date,(s.start_at at time zone 'Asia/Manila')::date)=v_day)
  then raise exception 'Already assigned on this day at this deployment site. Choose another Guard.'; end if;
  return new;
end;
$$;
revoke all on function private.enforce_one_guard_duty_per_site_day() from public,anon,authenticated;
create trigger enforce_one_guard_duty_per_site_day
before insert or update of organization_id,user_id,location_id,start_at,end_at,duty_date,approval_status on public.schedules
for each row execute function private.enforce_one_guard_duty_per_site_day();

create function private.prevent_second_site_day_time_in()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_day date;
begin
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(new.organization_id::text||':'||new.user_id::text,0));
  select coalesce(s.duty_date,(s.start_at at time zone 'Asia/Manila')::date) into v_day
    from public.schedules s where s.id=new.schedule_id;
  if exists(select 1 from public.attendance_sessions a where a.organization_id=new.organization_id
    and a.user_id=new.user_id and a.location_id=new.location_id and a.duty_date=v_day)
  then raise exception 'Already assigned on this day. Time In has already been recorded at this deployment site.'; end if;
  return new;
end;
$$;
revoke all on function private.prevent_second_site_day_time_in() from public,anon,authenticated;
-- Run before the schedule snapshot/uniqueness checks for a clear duplicate message.
create trigger a_prevent_second_site_day_time_in before insert on public.attendance_sessions
for each row execute function private.prevent_second_site_day_time_in();

create or replace function public.record_attendance_event(
  p_action text,p_latitude double precision,p_longitude double precision
) returns public.attendance_sessions language plpgsql security definer set search_path='' as $$
begin
  if not public.is_active_guard() then
    raise exception 'Only active Guard accounts can record Time In or Time Out.' using errcode='42501';
  end if;
  if p_action='clock_in' then
    perform pg_advisory_xact_lock(pg_catalog.hashtextextended(public.current_organization_id()::text||':'||auth.uid()::text,0));
    if exists(select 1 from public.attendance_sessions a where a.user_id=auth.uid()
      and a.organization_id=public.current_organization_id() and a.status='open' and a.scheduled_end_at>now())
    then raise exception 'Already assigned on this day. Time In has already been recorded. Complete Time Out for your current duty.'; end if;
  end if;
  return public.record_attendance_event_for_guard_internal(p_action,p_latitude,p_longitude);
end;
$$;
revoke all on function public.record_attendance_event(text,double precision,double precision) from public,anon;
grant execute on function public.record_attendance_event(text,double precision,double precision) to authenticated;
notify pgrst,'reload schema';
-- All fixtures, including the temporary legacy-row setup, roll back.

set local lock_timeout='5s';
set local statement_timeout='30s';
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
create temp table fixture(key text primary key,id uuid default gen_random_uuid());
insert into fixture(key) values ('admin'),('guard'),('peer'),('site'),('other_site'),('legacy1'),('legacy2'),('future'),('draft');
insert into fixture values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@example.invalid','{}' from fixture where key in ('admin','guard','peer');
update public.profiles p set active=true,organization_id=pg_temp.f('org'),role=case when p.id=pg_temp.f('admin') then 'admin'::public.app_role else 'user'::public.app_role end where id in (pg_temp.f('admin'),pg_temp.f('guard'),pg_temp.f('peer'));
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters) select id,pg_temp.f('org'),'Duplicate duty fixture',10.67,122.95,100 from fixture where key in ('site','other_site');
-- Reproduce pre-migration back-to-back duplicates without deleting history.
alter table public.schedules disable trigger enforce_one_guard_duty_per_site_day;
insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at,duty_date)
values (pg_temp.f('legacy1'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),now()-interval '2 hours',now()-interval '10 minutes',(now() at time zone 'Asia/Manila')::date),
 (pg_temp.f('legacy2'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),now()-interval '10 minutes',now()+interval '2 hours',(now() at time zone 'Asia/Manila')::date);
alter table public.schedules enable trigger enforce_one_guard_duty_per_site_day;
create temp table results(n int generated always as identity,result text);
insert into results(result) select no_plan();
insert into results(result) select lives_ok($$insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at,duty_date) values(pg_temp.f('future'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'2099-01-01 06:00+08','2099-01-01 18:00+08','2099-01-01')$$,'First duty assignment is allowed');
create function pg_temp.assign_at(site text,day date) returns void language plpgsql as $$begin insert into public.schedules(organization_id,user_id,location_id,start_at,end_at,duty_date) values(pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f(site),(day+time '18:00') at time zone 'Asia/Manila',((day+1)+time '06:00') at time zone 'Asia/Manila',day);end$$;
insert into results(result) select throws_ok($$select pg_temp.assign_at('site','2099-01-01')$$,'P0001','Already assigned on this day at this deployment site. Choose another Guard.','Back-to-back same-site duty rejected');
insert into results(result) select lives_ok($$select pg_temp.assign_at('other_site','2099-01-01')$$,'Nonoverlapping different-site duty remains allowed');
insert into results(result) select lives_ok($$select pg_temp.assign_at('site','2099-01-02')$$,'Next duty date remains allowed including overnight hours');
insert into results(result) select throws_ok($$update public.schedules set location_id=pg_temp.f('site') where user_id=pg_temp.f('guard') and location_id=pg_temp.f('other_site')$$,'P0001',null,'Reassignment cannot introduce same-site duplicate');
insert into results(result) select lives_ok($$insert into public.schedules(id,organization_id,user_id,location_id,start_at,end_at,duty_date,approval_status) values(pg_temp.f('draft'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'2099-01-01 18:00+08','2099-01-02 06:00+08','2099-01-01','draft')$$,'Draft does not reserve another active duty');
insert into results(result) select throws_ok($$update public.schedules set approval_status='approved' where id=pg_temp.f('draft')$$,'P0001',null,'Approving duplicate draft rejected');
create function pg_temp.punch(k text) returns void language plpgsql as $$begin insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude) select organization_id,id,user_id,location_id,duty_date,start_at,end_at,start_at,10.67,122.95 from public.schedules where id=pg_temp.f(k);end$$;
insert into results(result) select lives_ok($$select pg_temp.punch('legacy1')$$,'First historical duty Time In succeeds');
insert into results(result) select lives_ok($$update public.attendance_sessions set clock_out_at=scheduled_end_at,status='closed' where schedule_id=pg_temp.f('legacy1');update public.schedules set marked_done=true where id=pg_temp.f('legacy1')$$,'Existing duplicate can finish normally');
insert into results(result) select throws_ok($$select pg_temp.punch('legacy2')$$,'P0001','Already assigned on this day. Time In has already been recorded at this deployment site.','Second Time In after closed duty rejected');
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into results(result) select throws_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'P0001','Already assigned on this day. Time In has already been recorded at this deployment site.','Real Guard Time In RPC rejects existing duplicate schedule');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into results(result) select throws_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'42501','Only active Guard accounts can record Time In or Time Out.','Operations Head cannot clock in as Guard');
insert into results(result) select throws_ok($$select public.create_dtr_schedule(pg_temp.f('peer'),pg_temp.f('site'),'2099-02-01','[{"period":"morning","start_time":"06:00","end_time":"12:00"},{"period":"afternoon","start_time":"12:00","end_time":"18:00"}]')$$,'P0001','Already assigned on this day at this deployment site. Choose another Guard.','Multiple-period RPC cannot bypass day rule');
insert into results(result) select is((select count(*) from public.schedules where user_id=pg_temp.f('peer')),0::bigint,'Failed multi-period assignment rolls back every shift');
reset role;
insert into fixture(key) values('setup');
insert into public.shift_roster_setups(id,organization_id,name,shifts,created_by) values(pg_temp.f('setup'),pg_temp.f('org'),'Duplicate fixture '||pg_temp.f('setup'),'[{"start_time":"06:00","end_time":"18:00"},{"start_time":"18:00","end_time":"06:00"}]',pg_temp.f('admin')) on conflict do nothing;
update fixture set id=(select id from public.shift_roster_setups where organization_id=pg_temp.f('org') and shift_signature='06:00-18:00,18:00-06:00' and archived_at is null) where key='setup';
set local role authenticated;
insert into results(result) select throws_ok($$select public.assign_saved_shift_roster(pg_temp.f('setup'),pg_temp.f('site'),'2099-01-01',array[pg_temp.f('peer'),pg_temp.f('guard')],(select version from public.shift_roster_setups where id=pg_temp.f('setup')))$$,'P0001','Already assigned on this day at this deployment site. Choose another Guard.','Roster RPC rejects nonoverlapping duplicate in its second slot');
insert into results(result) select is((select count(*) from public.schedules where user_id=pg_temp.f('peer')),0::bigint,'Roster failure rolls back first Guard assignment too');
reset role;
update public.attendance_sessions set status='missed_timeout',clock_out_at=null where schedule_id=pg_temp.f('legacy1');
insert into results(result) select throws_ok($$select pg_temp.punch('legacy2')$$,'P0001','Already assigned on this day. Time In has already been recorded at this deployment site.','Missed Time Out does not permit duplicate Time In');
insert into results(result) select lives_ok($$select pg_temp.punch('future')$$,'Time In on a later duty date remains allowed');
insert into public.schedules(organization_id,user_id,location_id,start_at,end_at,duty_date) values(pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site'),now()-interval '30 minutes',now()+interval '1 hour',(now() at time zone 'Asia/Manila')::date);
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into results(result) select lives_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'Guard can Time In for an unstarted assignment');
insert into results(result) select throws_ok($$select public.record_attendance_event('clock_in',10.67,122.95)$$,'P0001','Already assigned on this day. Time In has already been recorded. Complete Time Out for your current duty.','Repeated Time In for ongoing duty gives clear message');
reset role;
insert into results(result) select * from finish();
select result from results order by n;
rollback;
