-- An ended duty with a missing Time Out must not block the next shift.
alter table public.attendance_sessions
  drop constraint attendance_sessions_status_check,
  drop constraint attendance_sessions_check2,
  add constraint attendance_sessions_status_check
    check (status in ('open', 'closed', 'missed_timeout')),
  add constraint attendance_sessions_check2 check (
    (status in ('open', 'missed_timeout') and clock_out_at is null)
    or (status = 'closed' and clock_out_at is not null)
  );

create or replace function public.record_attendance_event_for_guard_internal(
  p_action text,
  p_latitude double precision,
  p_longitude double precision
)
returns public.attendance_sessions
language plpgsql security definer set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_organization_id uuid;
  v_duty record;
  v_result public.attendance_sessions;
begin
  if p_action is null or p_action not in ('clock_in', 'clock_out') then
    raise exception 'Choose either Time In or Time Out.';
  end if;
  if not public.is_active_duty_personnel() then
    raise exception 'This account is not allowed to record attendance.';
  end if;
  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'A current location is required to record attendance.';
  end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'Location coordinates are invalid.';
  end if;

  -- Serialize punches and schedule changes for the same guard. A rollover and
  -- a late Time Out must never race to modify the previous session.
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_organization_id::text || ':' || auth.uid()::text, 0)
  );

  if p_action = 'clock_in' then
    if exists (
      select 1 from public.attendance_sessions session
      where session.user_id = auth.uid() and session.organization_id = v_organization_id
        and session.status = 'open' and session.scheduled_end_at > v_now
    ) then
      raise exception 'Time Out of your open duty session before starting another one.';
    end if;
    select s.id as schedule_id, s.location_id, s.start_at, s.end_at,
      s.duty_days, l.label as location_label
    into v_duty
    from public.schedules s
    join public.locations l on l.id = s.location_id and l.active
      and l.organization_id = v_organization_id
    where s.user_id = auth.uid() and s.organization_id = v_organization_id
      and s.approval_status in ('approved', 'changed') and not s.marked_done
      and v_now >= s.start_at - interval '2 hours' and v_now < s.end_at
      and 6371000 * acos(least(1.0, greatest(-1.0,
        cos(radians(l.latitude)) * cos(radians(p_latitude)) *
        cos(radians(p_longitude) - radians(l.longitude)) +
        sin(radians(l.latitude)) * sin(radians(p_latitude))
      ))) <= l.radius_meters
    order by s.start_at asc limit 1;
    if not found then
      raise exception 'Time In is allowed only at your scheduled post, from two hours before the shift until its scheduled end.';
    end if;

    -- Preserve missing punches as incomplete records. Never manufacture a Time
    -- Out, completed schedule, or paid hours. A failed new punch rolls this back.
    update public.attendance_sessions
    set status = 'missed_timeout', updated_at = v_now
    where user_id = auth.uid() and organization_id = v_organization_id
      and status = 'open' and clock_out_at is null and scheduled_end_at <= v_now;

    insert into public.attendance_sessions (
      organization_id, schedule_id, user_id, location_id, location_label,
      duty_date, scheduled_start_at, scheduled_end_at, clock_in_at,
      clock_in_latitude, clock_in_longitude
    ) values (
      v_organization_id, v_duty.schedule_id, auth.uid(), v_duty.location_id,
      v_duty.location_label, (v_duty.start_at at time zone 'Asia/Manila')::date,
      v_duty.start_at, v_duty.end_at, v_now, p_latitude, p_longitude
    ) returning * into v_result;
    return v_result;
  end if;

  select session.id as session_id, session.schedule_id, s.location_id,
    s.start_at, s.end_at, s.duty_days, l.label as location_label
  into v_duty
  from public.attendance_sessions session
  join public.schedules s on s.id = session.schedule_id
    and s.organization_id = v_organization_id
  join public.locations l on l.id = session.location_id
    and l.organization_id = v_organization_id
  where session.user_id = auth.uid() and session.organization_id = v_organization_id
    and session.status = 'open' and session.clock_out_at is null
    and 6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(l.latitude)) * cos(radians(p_latitude)) *
      cos(radians(p_longitude) - radians(l.longitude)) +
      sin(radians(l.latitude)) * sin(radians(p_latitude))
    ))) <= l.radius_meters
  order by session.clock_in_at desc limit 1;
  if not found then
    raise exception 'Time Out is allowed only at the post of your open duty session.';
  end if;

  update public.attendance_sessions
  set clock_out_at = v_now, clock_out_latitude = p_latitude,
      clock_out_longitude = p_longitude, status = 'closed', updated_at = v_now
  where id = v_duty.session_id and status = 'open'
  returning * into v_result;
  if not found then raise exception 'This duty session was already closed.'; end if;

  perform public.complete_schedule(v_duty.schedule_id);
  return v_result;
exception
  when unique_violation then
    raise exception 'An attendance session already exists for this scheduled duty.';
end;
$$;

revoke all on function public.record_attendance_event_for_guard_internal(
  text, double precision, double precision
) from public, anon, authenticated;
