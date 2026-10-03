-- LOCAL CHANGE ONLY: apply only after the owner authorizes testing/deployment.
-- One duty date is one DTR row. A row can contain a continuous duty, or separate
-- Morning/Afternoon periods, plus optional Overtime. Each period remains an
-- independent schedule-linked attendance session; no attendance is invented.

alter table public.schedules
  add column if not exists dtr_period text not null default 'auto'
    check (dtr_period in ('auto', 'morning', 'afternoon', 'overtime')),
  add column if not exists duty_date date;

alter table public.attendance_sessions
  add column if not exists dtr_period text not null default 'auto'
    check (dtr_period in ('auto', 'morning', 'afternoon', 'overtime'));

comment on column public.schedules.duty_date is
  'DTR row date in Asia/Manila. Null legacy rows use the local scheduled start date.';
comment on column public.schedules.dtr_period is
  'Explicit DTR column pair, or auto for a continuous/legacy shift. Inspector schedules use auto.';
comment on column public.attendance_sessions.dtr_period is
  'DTR column mapping snapshotted from the approved schedule at Time In.';

create index if not exists schedules_user_dtr_date_idx
  on public.schedules (organization_id, user_id, duty_date)
  where duty_date is not null;

-- A legacy schedule-change request supplies start/end timestamps, not a DTR
-- date. Move its explicit anchor by the same number of days, retaining an
-- overnight period's next-day offset. Existing rows remain unmodified.
create or replace function public.align_changed_schedule_duty_date()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if old.duty_date is not null
    and new.duty_date is not distinct from old.duty_date
    and new.start_at is distinct from old.start_at then
    new.duty_date := old.duty_date
      + ((new.start_at at time zone 'Asia/Manila')::date
        - (old.start_at at time zone 'Asia/Manila')::date);
  end if;
  return new;
end;
$$;

create trigger align_changed_schedule_duty_date
before update of start_at, duty_date on public.schedules
for each row execute function public.align_changed_schedule_duty_date();

-- Once Time In exists, neither the period's times nor its DTR row/columns may
-- be reassigned. Keep the existing attendance-history protections.
create or replace function public.prevent_started_schedule_mutation()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if (
    new.user_id is distinct from old.user_id
    or new.location_id is distinct from old.location_id
    or new.start_at is distinct from old.start_at
    or new.end_at is distinct from old.end_at
    or new.dtr_period is distinct from old.dtr_period
    or new.duty_date is distinct from old.duty_date
  ) and exists (
    select 1 from public.attendance_sessions session
    where session.schedule_id = old.id and session.clock_in_at is not null
  ) then
    raise exception 'A started duty cannot be changed. Create a corrected replacement schedule instead.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_started_schedule_mutation on public.schedules;
create trigger prevent_started_schedule_mutation
before update of user_id, location_id, start_at, end_at, dtr_period, duty_date on public.schedules
for each row execute function public.prevent_started_schedule_mutation();

-- Extend the existing race protection for approval/reassignment. The locked
-- schedule is authoritative, not metadata supplied by a mobile/browser client.
create or replace function public.check_session_schedule_before_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare s public.schedules;
begin
  select * into s from public.schedules where id = new.schedule_id for update;
  if not found
    or s.organization_id is distinct from new.organization_id
    or s.user_id is distinct from new.user_id
    or s.location_id is distinct from new.location_id
    or s.start_at is distinct from new.scheduled_start_at
    or s.end_at is distinct from new.scheduled_end_at
    or s.marked_done
    or s.approval_status not in ('approved', 'changed') then
    raise exception 'Your duty assignment has changed. Refresh your schedule before Time In.';
  end if;
  -- The caller selected these post/time snapshots before acquiring this lock.
  -- Reject a concurrent change instead of applying a geofence decision made
  -- against the previous assignment to a new one. DTR metadata itself is
  -- deliberately copied only after locking the authoritative schedule.
  new.duty_date := coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date);
  new.dtr_period := s.dtr_period;
  return new;
end;
$$;

-- Atomically validate and create every enabled period. A rejected period rolls
-- the entire request back, including schedule notifications. Existing overlap
-- triggers still execute and share this per-person transaction advisory lock.
create or replace function public.create_dtr_schedule(
  p_user_id uuid,
  p_location_id uuid,
  p_duty_date date,
  p_periods jsonb
)
returns setof public.schedules
language plpgsql security definer set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_personnel public.profiles;
  v_post public.locations;
  v_period jsonb;
  v_label text;
  v_labels text[] := array[]::text[];
  v_start_time time;
  v_end_time time;
  v_start_date date;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_next_day boolean;
  v_rows uuid[] := array[]::uuid[];
  v_created public.schedules;
begin
  if not public.is_admin() or v_org is null then
    raise exception 'Only an active Admin can create duty schedules.' using errcode = '42501';
  end if;
  if p_user_id is null or p_location_id is null then
    raise exception 'Choose personnel and a deployment site.';
  end if;
  if p_duty_date is null or not isfinite(p_duty_date)
    or p_duty_date < (now() at time zone 'Asia/Manila')::date then
    raise exception 'Choose today or a future duty date.';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'Provide the enabled duty periods as an array.';
  end if;
  if jsonb_array_length(p_periods) not between 1 and 3 then
    raise exception 'Choose between one and three duty periods.';
  end if;

  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_org::text || ':' || p_user_id::text, 0)
  );
  perform 1 from public.organizations where id = v_org and active for share;
  if not found then
    raise exception 'Your agency is not active.' using errcode = '42501';
  end if;
  select * into v_personnel from public.profiles
    where id = p_user_id and organization_id = v_org
      and active and role in ('user', 'inspector') for share;
  if not found then
    raise exception 'Choose active personnel from your agency.';
  end if;
  select * into v_post from public.locations
    where id = p_location_id and organization_id = v_org and active for share;
  if not found then
    raise exception 'Choose an active deployment site from your agency.';
  end if;

  for v_period in select value from jsonb_array_elements(p_periods) loop
    if jsonb_typeof(v_period) is distinct from 'object'
      or jsonb_typeof(v_period->'period') is distinct from 'string'
      or jsonb_typeof(v_period->'start_time') is distinct from 'string'
      or jsonb_typeof(v_period->'end_time') is distinct from 'string'
      or (v_period ? 'next_day' and jsonb_typeof(v_period->'next_day') is distinct from 'boolean') then
      raise exception 'Each duty period needs a period, Start time, End time, and valid next-day choice.';
    end if;
    v_label := v_period->>'period';
    if v_label not in ('auto', 'morning', 'afternoon', 'overtime') then
      raise exception 'Choose Continuous duty, Morning, Afternoon, or Overtime.';
    end if;
    if v_label = any(v_labels) then
      raise exception 'A DTR period may be added only once per request.';
    end if;
    v_labels := array_append(v_labels, v_label);
    if 'auto' = any(v_labels) and ('morning' = any(v_labels) or 'afternoon' = any(v_labels)) then
      raise exception 'Use Continuous duty or separate Morning/Afternoon periods, not both.';
    end if;
    if (v_period->>'start_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or (v_period->>'end_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'Enter each duty time in HH:mm format.';
    end if;
    v_start_time := (v_period->>'start_time')::time;
    v_end_time := (v_period->>'end_time')::time;
    v_next_day := coalesce((v_period->>'next_day')::boolean, false);
    if v_start_time = v_end_time then
      raise exception 'Start time and End time must be different.';
    end if;
    if v_personnel.role = 'inspector' and (
      jsonb_array_length(p_periods) <> 1 or v_label <> 'auto' or v_next_day
    ) then
      raise exception 'An Inspector has one duty period and does not use Guard DTR columns.';
    end if;
    v_start_date := p_duty_date + case when v_next_day then 1 else 0 end;
    v_start_at := (v_start_date + v_start_time) at time zone 'Asia/Manila';
    v_end_at := ((v_start_date + case when v_end_time < v_start_time then 1 else 0 end)
      + v_end_time) at time zone 'Asia/Manila';
    if v_end_at <= now() then
      raise exception 'The % period has already ended. Choose a current or future duty period.', v_label;
    end if;

    insert into public.schedules (
      organization_id, user_id, location_id, location_label, location_address,
      guard_name, start_at, end_at, duty_date, dtr_period, duty_category,
      duty_days, approval_status, approved_by
    ) values (
      v_org, v_personnel.id, v_post.id, v_post.label, v_post.address,
      trim(concat_ws(' ', nullif(trim(v_personnel.first_name), ''),
        nullif(trim(v_personnel.middle_initial), ''), nullif(trim(v_personnel.last_name), ''))),
      v_start_at, v_end_at, p_duty_date, v_label,
      case when v_personnel.role = 'user' then v_personnel.employment_category else null end,
      1, 'approved', auth.uid()
    ) returning * into v_created;
    v_rows := array_append(v_rows, v_created.id);
  end loop;

  return query select s.* from public.schedules s
    where s.id = any(v_rows) and s.organization_id = v_org
    order by s.start_at, s.end_at;
end;
$$;

-- Count a worked DTR date once, not once per Morning/Afternoon/Overtime period.
-- Do not rewrite historical totals. Both current and legacy clock-out callers
-- use this same completion path; retries cannot award another day.
create or replace function public.complete_schedule(p_schedule_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_organization_id uuid;
  v_duty_date date;
begin
  if not public.is_active_duty_personnel() then
    raise exception 'This account is not allowed to complete a duty.';
  end if;
  v_organization_id := public.current_organization_id();
  select session.duty_date into v_duty_date
  from public.attendance_sessions session
  where session.schedule_id = p_schedule_id and session.user_id = auth.uid()
    and session.organization_id = v_organization_id and session.status = 'closed';
  if not found then
    raise exception 'Time Out is required before a duty can be completed.';
  end if;

  perform 1 from public.schedules where id = p_schedule_id
    and user_id = auth.uid() and organization_id = v_organization_id for update;
  perform 1 from public.profiles where id = auth.uid()
    and organization_id = v_organization_id for update;

  update public.schedules
  set marked_done = true, completed_at = coalesce(completed_at, now()),
      completed_by = coalesce(completed_by, auth.uid())
  where id = p_schedule_id and user_id = auth.uid()
    and organization_id = v_organization_id and not marked_done;

  if found and not exists (
    select 1 from public.attendance_sessions other
    join public.schedules completed on completed.id = other.schedule_id
      and completed.organization_id = v_organization_id and completed.marked_done
    where other.user_id = auth.uid() and other.organization_id = v_organization_id
      and other.duty_date = v_duty_date and other.status = 'closed'
      and other.schedule_id <> p_schedule_id
  ) then
    update public.profiles set duty_days_total = duty_days_total + 1
    where id = auth.uid() and organization_id = v_organization_id and role = 'user';
  end if;
end;
$$;

-- Preserve the existing time window, role wrapper, location validation and
-- geofence calculations. Only completion accounting is delegated to the
-- shared one-DTR-date completion function above.
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

  if p_action = 'clock_in' then
    if exists (
      select 1 from public.attendance_sessions session
      where session.user_id = auth.uid() and session.organization_id = v_organization_id
        and session.status = 'open'
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
      and v_now >= s.start_at - interval '2 hours' and v_now <= s.end_at
      and 6371000 * acos(least(1.0, greatest(-1.0,
        cos(radians(l.latitude)) * cos(radians(p_latitude)) *
        cos(radians(p_longitude) - radians(l.longitude)) +
        sin(radians(l.latitude)) * sin(radians(p_latitude))
      ))) <= l.radius_meters
    order by s.start_at asc limit 1;
    if not found then
      raise exception 'Time In is allowed only at your scheduled post, from two hours before the shift until its scheduled end.';
    end if;

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

-- Totals still use actual session timestamps. Morning/Afternoon breaks are
-- excluded naturally because they are separate sessions; days use the DTR
-- anchor, including next-day overtime belonging to the preceding duty date.
create or replace function public.evaluate_time_record(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns table(duty_days integer, completed_days integer, total_minutes integer,
  late_minutes integer, undertime_minutes integer)
language plpgsql stable security definer set search_path = public
as $$
declare v_organization_id uuid;
begin
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Choose a valid date range.';
  end if;
  select p.organization_id into v_organization_id from public.profiles p
  where p.id = p_user_id and p.organization_id is not null and p.role in ('user', 'inspector');
  if v_organization_id is null then raise exception 'Personnel record was not found.'; end if;
  if not public.is_it_admin() and not (
    public.is_admin() and v_organization_id = public.current_organization_id()
  ) then
    raise exception 'You cannot evaluate this personnel record.';
  end if;

  return query
  with duty as (
    select s.id, s.start_at, s.end_at,
      coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) as dtr_date
    from public.schedules s
    where s.user_id = p_user_id and s.organization_id = v_organization_id
      and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date)
        between p_start_date and p_end_date
      and s.approval_status in ('approved', 'changed')
  )
  select count(distinct duty.dtr_date)::integer,
    count(distinct duty.dtr_date) filter (where session.clock_out_at is not null)::integer,
    coalesce(sum(case
      when session.clock_in_at is not null and session.clock_out_at is not null
      then greatest(0, floor(extract(epoch from (session.clock_out_at - session.clock_in_at)) / 60)::integer)
      else 0 end), 0)::integer,
    coalesce(sum(case
      when session.clock_in_at is not null
      then greatest(0, floor(extract(epoch from (session.clock_in_at - duty.start_at)) / 60)::integer)
      else 0 end), 0)::integer,
    coalesce(sum(case
      when session.clock_out_at is not null
      then greatest(0, floor(extract(epoch from (duty.end_at - session.clock_out_at)) / 60)::integer)
      else 0 end), 0)::integer
  from duty left join public.attendance_sessions session
    on session.schedule_id = duty.id and session.organization_id = v_organization_id;
end;
$$;

revoke all on function public.align_changed_schedule_duty_date(),
  public.prevent_started_schedule_mutation(),
  public.check_session_schedule_before_insert(),
  public.record_attendance_event_for_guard_internal(text, double precision, double precision)
from public, anon, authenticated;
revoke all on function public.create_dtr_schedule(uuid, uuid, date, jsonb) from public, anon;
grant execute on function public.create_dtr_schedule(uuid, uuid, date, jsonb) to authenticated;

notify pgrst, 'reload schema';
