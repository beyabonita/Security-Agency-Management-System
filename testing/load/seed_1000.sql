-- Sentinel Link: exactly 1,000 synthetic business rows, not 1,000 per table.
-- Run the ENTIRE file in the Supabase SQL Editor as postgres on a TEST copy.
-- Requires the repository migrations through 20260905000005.
-- Edit guard_ids below: existing active REGULAR test guards in ONE active agency.
-- Does not create Auth users, fake audit records, or change existing profiles.
-- Repeat runs abort; use cleanup_1000.sql before reseeding.
-- Mix: 100 locations + 200 schedules + 200 attendance sessions + 200 incidents
--      + 100 accomplishment reports + 200 notifications = 1,000 rows.
-- Stable UUID namespace and labels identify this batch. Do not reuse them.
-- Notification triggers alone are suspended transactionally while seeding;
-- all validation, FK, overlap and contract triggers continue to execute.
-- Successful COMMIT persists the rows for UI checks. Replace COMMIT with
-- ROLLBACK at the end if you want only a disposable SQL trial.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local timezone = 'Asia/Manila';

create temporary table load_config on commit drop as
select
  array['a39a3788-2972-4843-8d21-d0f257b186a6'::uuid] as guard_ids, -- e.g. ARRAY['your-test-guard-uuid'::uuid]
  (current_date - 1) as last_duty_date;

-- Reserved UUID family: 7e571000-1000-4000-8000-000000000001 ... 001000.
create temporary table load_ids on commit drop as
select n, ('7e571000-1000-4000-8000-' || lpad(n::text,12,'0'))::uuid as id
from generate_series(1,1000) as g(n);

do $$
declare v_ids uuid[]; v_count integer; v_org uuid;
begin
  select guard_ids into v_ids from load_config;
  if cardinality(v_ids) = 0 or array_position(v_ids,null) is not null then
    raise exception 'Set load_config.guard_ids to existing regular test-guard UUIDs first.';
  end if;
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) as t(x)) then
    raise exception 'Test-guard UUIDs must be distinct.';
  end if;
  select count(*), min(p.organization_id::text)::uuid into v_count,v_org
  from public.profiles p join public.organizations o on o.id=p.organization_id
  where p.id=any(v_ids) and p.active and p.role='user'
    and p.employment_category='regular' and o.active;
  if v_count <> cardinality(v_ids) or
    (select count(distinct organization_id) from public.profiles where id=any(v_ids)) <> 1 then
    raise exception 'Use only active regular test guards belonging to one active agency.';
  end if;
  if (select last_duty_date from load_config) >= current_date then
    raise exception 'Use a last_duty_date before today for closed attendance.';
  end if;
  if exists (
    select id from public.locations where id in(select id from load_ids)
    union all select id from public.schedules where id in(select id from load_ids)
    union all select id from public.attendance_sessions where id in(select id from load_ids)
    union all select id from public.incidents where id in(select id from load_ids)
    union all select id from public.accomplishment_reports where id in(select id from load_ids)
    union all select id from public.user_notifications where id in(select id from load_ids)
  ) then raise exception 'This batch already exists or its UUIDs collide. No rows were changed.'; end if;
  if (select count(*) from pg_trigger where
    (tgrelid,tgname) in (('public.schedules'::regclass,'notify_schedule_event'),
      ('public.incidents'::regclass,'notify_incident_event'),
      ('public.accomplishment_reports'::regclass,'notify_accomplishment_event'))
    and tgenabled='O') <> 3 then
    raise exception 'Expected three normally enabled notification triggers; check migration state.';
  end if;
end $$;

-- Locks prevent concurrent writes during the short trigger-state change.
alter table public.schedules disable trigger notify_schedule_event;
alter table public.incidents disable trigger notify_incident_event;
alter table public.accomplishment_reports disable trigger notify_accomplishment_event;

create temporary table load_plan on commit drop as
select n,
  c.guard_ids[1+((n-1)%cardinality(c.guard_ids))] as guard_id,
  c.last_duty_date-((n-1)/cardinality(c.guard_ids)) as duty_date,
  1+((n-1)%100) as location_n
from load_config c cross join generate_series(1,200) as g(n);

insert into public.locations(id,organization_id,label,address,latitude,longitude,radius_meters,active)
select i.id,p.organization_id,'[LOAD1000] Test post '||i.n,
  'Synthetic test address '||i.n,14.5995+(i.n%10)*0.001,120.9842+(i.n/10)*0.001,100,true
from load_ids i cross join load_config c join public.profiles p on p.id=c.guard_ids[1]
where i.n between 1 and 100;

insert into public.schedules(id,organization_id,user_id,location_id,location_label,
  location_address,guard_name,start_at,end_at,duty_date,dtr_period,duty_category,approval_status,duty_days)
select i.id,p.organization_id,p.id,l.id,l.label,l.address,
  concat_ws(' ',p.first_name,p.last_name),
  (x.duty_date+time '08:00') at time zone 'Asia/Manila',
  (x.duty_date+time '16:00') at time zone 'Asia/Manila',
  x.duty_date,'auto','regular','approved',1
from load_plan x join load_ids i on i.n=100+x.n
join public.profiles p on p.id=x.guard_id
join load_ids li on li.n=x.location_n join public.locations l on l.id=li.id;

insert into public.attendance_sessions(id,organization_id,schedule_id,user_id,
  location_id,location_label,duty_date,scheduled_start_at,scheduled_end_at,
  clock_in_at,clock_out_at,clock_in_latitude,clock_in_longitude,
  clock_out_latitude,clock_out_longitude,status,dtr_period,created_at,updated_at)
select ai.id,s.organization_id,s.id,s.user_id,l.id,l.label,s.duty_date,s.start_at,s.end_at,
  s.start_at+case when x.n%5=0 then interval '10 minutes' else interval '0' end,
  s.end_at-case when x.n%7=0 then interval '15 minutes' else interval '0' end,
  l.latitude,l.longitude,l.latitude,l.longitude,'closed','auto',s.start_at,s.end_at
from load_plan x join load_ids si on si.n=100+x.n join public.schedules s on s.id=si.id
join load_ids ai on ai.n=300+x.n join public.locations l on l.id=s.location_id;

update public.schedules s set marked_done=true,completed_at=s.end_at
where s.id in(select id from load_ids where n between 101 and 300);

insert into public.incidents(id,organization_id,user_id,category,description,photo_data,
  incident_title,detailed_narrative,immediate_action,latitude,longitude,location_label,
  status,captured_at,filed_at,created_at)
select ii.id,s.organization_id,s.user_id,
  (array['crime','fire','medical','disturbance','other'])[1+(x.n%5)],
  '[LOAD1000] Synthetic incident '||x.n||'. Test data only.',
  -- Valid tiny PNG placeholder; deliberately not a realistic photo payload.
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8WQAAAAASUVORK5CYII=',
  '[LOAD1000] Test incident '||x.n,
  'Synthetic narrative for data-volume checks. This event did not occur.',
  'Test entry only. No real emergency response.',l.latitude,l.longitude,l.label,
  (array['open','acknowledged','resolved'])[1+(x.n%3)],
  s.start_at+interval '1 hour',s.start_at+interval '61 minutes',s.start_at+interval '61 minutes'
from load_plan x join load_ids si on si.n=100+x.n join public.schedules s on s.id=si.id
join load_ids ii on ii.n=500+x.n join public.locations l on l.id=s.location_id;

insert into public.accomplishment_reports(id,organization_id,schedule_id,guard_id,
  summary,detailed_narrative,issues_encountered,submitted_at,review_status)
select ri.id,s.organization_id,s.id,s.user_id,
  '[LOAD1000] Synthetic completed duty report '||x.n,
  'Synthetic accomplishment narrative for volume testing. Patrol and handover data are invented.',
  'Test data only.',s.end_at+interval '5 minutes','submitted'
from load_plan x join load_ids si on si.n=100+x.n join public.schedules s on s.id=si.id
join load_ids ri on ri.n=700+x.n where x.n<=100;

insert into public.user_notifications(id,recipient_id,organization_id,kind,priority,title,
  message,action_key,entity_type,entity_id,metadata,dedupe_key)
select ni.id,s.user_id,s.organization_id,'schedule','low',
  '[LOAD1000] Synthetic notification',
  'Test data only: review the synthetic duty schedule. No action is required.',
  'schedule','schedule',s.id,jsonb_build_object('test_batch','LOAD1000'),
  'LOAD1000:'||x.n
from load_plan x join load_ids si on si.n=100+x.n join public.schedules s on s.id=si.id
join load_ids ni on ni.n=800+x.n;

alter table public.schedules enable trigger notify_schedule_event;
alter table public.incidents enable trigger notify_incident_event;
alter table public.accomplishment_reports enable trigger notify_accomplishment_event;

create temporary table load_counts on commit drop as
select 'locations' as table_name,count(*) as rows_inserted from public.locations where id in(select id from load_ids)
union all select 'schedules',count(*) from public.schedules where id in(select id from load_ids)
union all select 'attendance_sessions',count(*) from public.attendance_sessions where id in(select id from load_ids)
union all select 'incidents',count(*) from public.incidents where id in(select id from load_ids)
union all select 'accomplishment_reports',count(*) from public.accomplishment_reports where id in(select id from load_ids)
union all select 'user_notifications',count(*) from public.user_notifications where id in(select id from load_ids);
do $$ begin
  if (select sum(rows_inserted) from load_counts) <> 1000 then
    raise exception 'Expected exactly 1,000 test rows; entire transaction rolled back.';
  end if;
end $$;
select * from load_counts union all select 'TOTAL',sum(rows_inserted) from load_counts;
commit;
