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