-- Remove only the complete LOAD1000 batch from a TEST database.
-- Run as postgres. Refuses partial batches and newly linked operational data.
-- No FK or history-protection trigger is disabled.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
lock table public.locations,public.schedules,public.attendance_sessions,
  public.incidents,public.accomplishment_reports,public.user_notifications,
  public.shift_swap_requests,public.guard_assignment_history,public.profiles
  in share row exclusive mode;

create temporary table cleanup_ids on commit drop as
select n,('7e571000-1000-4000-8000-'||lpad(n::text,12,'0'))::uuid as id
from generate_series(1,1000) as g(n);

do $$
declare v_count integer;
begin
  select sum(c)::integer into v_count from (
    select count(*) c from public.locations where id in(select id from cleanup_ids where n<=100) and label like '[LOAD1000] Test post %'
    union all select count(*) from public.schedules where id in(select id from cleanup_ids where n between 101 and 300) and location_label like '[LOAD1000] Test post %'
      and location_id in(select id from cleanup_ids where n<=100)
    union all select count(*) from public.attendance_sessions where id in(select id from cleanup_ids where n between 301 and 500)
      and schedule_id in(select id from cleanup_ids where n between 101 and 300)
    union all select count(*) from public.incidents where id in(select id from cleanup_ids where n between 501 and 700) and incident_title like '[LOAD1000] Test incident %'
    union all select count(*) from public.accomplishment_reports where id in(select id from cleanup_ids where n between 701 and 800) and summary like '[LOAD1000] Synthetic completed duty report %'
    union all select count(*) from public.user_notifications where id in(select id from cleanup_ids where n between 801 and 1000) and metadata->>'test_batch'='LOAD1000'
  ) counts;
  if v_count<>1000 then raise exception 'Complete marked batch not found (matched % of 1000). Review manually; nothing removed.',v_count; end if;
  if exists(select 1 from public.shift_swap_requests where
      requested_schedule_id in(select id from cleanup_ids) or target_schedule_id in(select id from cleanup_ids))
    or exists(select 1 from public.guard_assignment_history where location_id in(select id from cleanup_ids))
    or exists(select 1 from public.profiles where assigned_location_id in(select id from cleanup_ids))
    or exists(select 1 from public.schedules where location_id in(select id from cleanup_ids) and id not in(select id from cleanup_ids))
    or exists(select 1 from public.attendance_sessions where (schedule_id in(select id from cleanup_ids) or location_id in(select id from cleanup_ids)) and id not in(select id from cleanup_ids))
    or exists(select 1 from public.accomplishment_reports where schedule_id in(select id from cleanup_ids) and id not in(select id from cleanup_ids))
    or exists(select 1 from public.user_notifications where entity_id in(select id from cleanup_ids) and id not in(select id from cleanup_ids)) then
    raise exception 'Additional data references the test batch. Cleanup refused; review the test database.';
  end if;
end $$;

delete from public.user_notifications where id in(select id from cleanup_ids where n between 801 and 1000);
delete from public.accomplishment_reports where id in(select id from cleanup_ids where n between 701 and 800);
delete from public.incidents where id in(select id from cleanup_ids where n between 501 and 700);
delete from public.attendance_sessions where id in(select id from cleanup_ids where n between 301 and 500);
-- Remove synthetic completion markers after removing synthetic history.
-- Updating these two columns does not invoke the schedule notification trigger.
update public.schedules set marked_done=false,completed_at=null
where id in(select id from cleanup_ids where n between 101 and 300);
delete from public.schedules where id in(select id from cleanup_ids where n between 101 and 300);
delete from public.locations where id in(select id from cleanup_ids where n between 1 and 100);
select 'Removed the 1,000-row LOAD1000 batch.' as result;
commit;
