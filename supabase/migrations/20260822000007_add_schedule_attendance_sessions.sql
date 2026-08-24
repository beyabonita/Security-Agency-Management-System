-- Attendance is a schedule-linked duty session, not a calendar-day AM/PM grid.
-- This preserves a single duty across midnight and keeps the scheduled post
-- authoritative for both Time In and Time Out.
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  schedule_id uuid not null unique references public.schedules(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  location_id uuid references public.locations(id) on delete set null,
  location_label text not null default '',
  duty_date date not null,
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  clock_in_at timestamptz not null,
  clock_in_latitude double precision not null,
  clock_in_longitude double precision not null,
  clock_out_at timestamptz,
  clock_out_latitude double precision,
  clock_out_longitude double precision,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (scheduled_end_at > scheduled_start_at),
  check (clock_in_latitude between -90 and 90),
  check (clock_in_longitude between -180 and 180),
  check (clock_out_latitude is null or clock_out_latitude between -90 and 90),
  check (clock_out_longitude is null or clock_out_longitude between -180 and 180),
  check (clock_out_at is null or clock_out_at >= clock_in_at),
  check ((status = 'open' and clock_out_at is null) or (status = 'closed' and clock_out_at is not null))
);

create index if not exists attendance_sessions_user_duty_date_idx
  on public.attendance_sessions (organization_id, user_id, duty_date desc);
create index if not exists attendance_sessions_open_user_idx
  on public.attendance_sessions (organization_id, user_id, clock_in_at desc)
  where status = 'open';

alter table public.attendance_sessions enable row level security;
drop policy if exists "tenant attendance session visibility" on public.attendance_sessions;
create policy "tenant attendance session visibility"
on public.attendance_sessions
for select to authenticated
using (
  user_id = auth.uid()
  or public.is_it_admin()
  or (organization_id = public.current_organization_id() and public.is_staff())
);

alter publication supabase_realtime add table public.attendance_sessions;

-- Once a guard starts a duty, do not let a schedule edit detach the recorded
-- attendance from the shift, personnel member, or assigned post.
create or replace function public.prevent_started_schedule_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (
    new.user_id is distinct from old.user_id
    or new.location_id is distinct from old.location_id
    or new.start_at is distinct from old.start_at
    or new.end_at is distinct from old.end_at
  ) and exists (
    select 1
    from public.attendance_sessions session
    where session.schedule_id = old.id
      and session.clock_in_at is not null
  ) then
    raise exception 'A started duty cannot be changed. Create a corrected replacement schedule instead.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_started_schedule_mutation on public.schedules;
create trigger prevent_started_schedule_mutation
before update of user_id, location_id, start_at, end_at on public.schedules
for each row execute function public.prevent_started_schedule_mutation();

create or replace function public.record_attendance_event(
  p_action text,
  p_latitude double precision,
  p_longitude double precision
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_organization_id uuid;
  v_duty record;
  v_result public.attendance_sessions;
  v_duty_days integer;
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
      select 1
      from public.attendance_sessions session
      where session.user_id = auth.uid()
        and session.organization_id = v_organization_id
        and session.status = 'open'
    ) then
      raise exception 'Time Out of your open duty session before starting another one.';
    end if;

    select
      s.id as schedule_id,
      s.location_id,
      s.start_at,
      s.end_at,
      s.duty_days,
      l.label as location_label
    into v_duty
    from public.schedules s
    join public.locations l
      on l.id = s.location_id
      and l.active
      and l.organization_id = v_organization_id
    where s.user_id = auth.uid()
      and s.organization_id = v_organization_id
      and s.approval_status in ('approved', 'changed')
      and not s.marked_done
      and v_now >= s.start_at - interval '2 hours'
      and v_now <= s.end_at
      and 6371000 * acos(least(1.0, greatest(-1.0,
        cos(radians(l.latitude)) * cos(radians(p_latitude)) *
        cos(radians(p_longitude) - radians(l.longitude)) +
        sin(radians(l.latitude)) * sin(radians(p_latitude))
      ))) <= l.radius_meters
    order by s.start_at asc
    limit 1;

    if not found then
      raise exception 'Time In is allowed only at your scheduled post, from two hours before the shift until its scheduled end.';
    end if;

    insert into public.attendance_sessions (
      organization_id,
      schedule_id,
      user_id,
      location_id,
      location_label,
      duty_date,
      scheduled_start_at,
      scheduled_end_at,
      clock_in_at,
      clock_in_latitude,
      clock_in_longitude
    ) values (
      v_organization_id,
      v_duty.schedule_id,
      auth.uid(),
      v_duty.location_id,
      v_duty.location_label,
      (v_duty.start_at at time zone 'Asia/Manila')::date,
      v_duty.start_at,
      v_duty.end_at,
      v_now,
      p_latitude,
      p_longitude
    ) returning * into v_result;

    return v_result;
  end if;

  select
    session.id as session_id,
    session.schedule_id,
    s.location_id,
    s.start_at,
    s.end_at,
    s.duty_days,
    l.label as location_label
  into v_duty
  from public.attendance_sessions session
  join public.schedules s
    on s.id = session.schedule_id
    and s.organization_id = v_organization_id
  join public.locations l
    on l.id = session.location_id
    and l.organization_id = v_organization_id
  where session.user_id = auth.uid()
    and session.organization_id = v_organization_id
    and session.status = 'open'
    and session.clock_out_at is null
    and 6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(l.latitude)) * cos(radians(p_latitude)) *
      cos(radians(p_longitude) - radians(l.longitude)) +
      sin(radians(l.latitude)) * sin(radians(p_latitude))
    ))) <= l.radius_meters
  order by session.clock_in_at desc
  limit 1;

  if not found then
    raise exception 'Time Out is allowed only at the post of your open duty session.';
  end if;

  update public.attendance_sessions
  set clock_out_at = v_now,
      clock_out_latitude = p_latitude,
      clock_out_longitude = p_longitude,
      status = 'closed',
      updated_at = v_now
  where id = v_duty.session_id
    and status = 'open'
  returning * into v_result;
  if not found then
    raise exception 'This duty session was already closed.';
  end if;

  update public.schedules
  set marked_done = true,
      completed_at = v_now,
      completed_by = auth.uid()
  where id = v_duty.schedule_id
    and user_id = auth.uid()
    and organization_id = v_organization_id
    and not marked_done
  returning duty_days into v_duty_days;

  if found then
    update public.profiles
    set duty_days_total = duty_days_total + coalesce(v_duty_days, 1)
    where id = auth.uid()
      and organization_id = v_organization_id
      and role = 'user';
  end if;

  return v_result;
exception
  when unique_violation then
    raise exception 'An attendance session already exists for this scheduled duty.';
end;
$$;

-- Keep the legacy RPC callable while mobile and web clients are upgraded. Its
-- AM/PM label is now only a compatibility shadow; the session is authoritative.
create or replace function public.record_attendance_punch(
  p_punch_type text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_within_geofence boolean default false,
  p_location_label text default null
)
returns public.attendance_punches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text;
  v_session public.attendance_sessions;
  v_result public.attendance_punches;
begin
  -- Legacy client values remain intentionally untrusted. The session RPC
  -- resolves the tenant, scheduled post, and geofence on the server.
  perform p_within_geofence;
  perform p_location_label;

  if p_punch_type is null or p_punch_type not in ('AM In', 'AM Out', 'PM In', 'PM Out') then
    raise exception 'Invalid punch type.';
  end if;

  v_action := case
    when p_punch_type in ('AM In', 'PM In') then 'clock_in'
    else 'clock_out'
  end;

  select * into v_session
  from public.record_attendance_event(v_action, p_latitude, p_longitude);

  insert into public.attendance_punches (
    user_id,
    organization_id,
    punch_date,
    punch_type,
    punched_at,
    latitude,
    longitude,
    within_geofence,
    location_label
  ) values (
    v_session.user_id,
    v_session.organization_id,
    v_session.duty_date,
    p_punch_type,
    case when v_action = 'clock_in' then v_session.clock_in_at else v_session.clock_out_at end,
    case when v_action = 'clock_in' then v_session.clock_in_latitude else v_session.clock_out_latitude end,
    case when v_action = 'clock_in' then v_session.clock_in_longitude else v_session.clock_out_longitude end,
    true,
    v_session.location_label
  ) on conflict (user_id, punch_date, punch_type) do nothing
  returning * into v_result;

  if v_result.id is null then
    select * into v_result
    from public.attendance_punches
    where user_id = v_session.user_id
      and organization_id = v_session.organization_id
      and punch_date = v_session.duty_date
      and punch_type = p_punch_type;
  end if;

  return v_result;
end;
$$;

create or replace function public.complete_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_duty_days integer;
begin
  if not public.is_active_duty_personnel() then
    raise exception 'This account is not allowed to complete a duty.';
  end if;

  v_organization_id := public.current_organization_id();
  if not exists (
    select 1
    from public.attendance_sessions session
    where session.schedule_id = p_schedule_id
      and session.user_id = auth.uid()
      and session.organization_id = v_organization_id
      and session.status = 'closed'
  ) then
    raise exception 'Time Out is required before a duty can be completed.';
  end if;

  update public.schedules
  set marked_done = true,
      completed_at = coalesce(completed_at, now()),
      completed_by = coalesce(completed_by, auth.uid())
  where id = p_schedule_id
    and user_id = auth.uid()
    and organization_id = v_organization_id
    and not marked_done
  returning duty_days into v_duty_days;

  if found then
    update public.profiles
    set duty_days_total = duty_days_total + coalesce(v_duty_days, 1)
    where id = auth.uid()
      and organization_id = v_organization_id
      and role = 'user';
  end if;
end;
$$;

create or replace function public.evaluate_time_record(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns table(
  duty_days integer,
  completed_days integer,
  total_minutes integer,
  late_minutes integer,
  undertime_minutes integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Choose a valid date range.';
  end if;

  select p.organization_id
  into v_organization_id
  from public.profiles p
  where p.id = p_user_id
    and p.organization_id is not null
    and p.role in ('user', 'inspector');
  if v_organization_id is null then
    raise exception 'Personnel record was not found.';
  end if;

  if not public.is_it_admin() and not (
    public.is_admin() and v_organization_id = public.current_organization_id()
  ) then
    raise exception 'You cannot evaluate this personnel record.';
  end if;

  return query
  with duty as (
    select s.id, s.start_at, s.end_at
    from public.schedules s
    where s.user_id = p_user_id
      and s.organization_id = v_organization_id
      and (s.start_at at time zone 'Asia/Manila')::date between p_start_date and p_end_date
      and s.approval_status in ('approved', 'changed')
  )
  select
    count(*)::integer,
    count(*) filter (where session.clock_out_at is not null)::integer,
    coalesce(sum(case
      when session.clock_in_at is not null and session.clock_out_at is not null
      then greatest(0, floor(extract(epoch from (session.clock_out_at - session.clock_in_at)) / 60)::integer)
      else 0
    end), 0)::integer,
    coalesce(sum(case
      when session.clock_in_at is not null
      then greatest(0, floor(extract(epoch from (session.clock_in_at - duty.start_at)) / 60)::integer)
      else 0
    end), 0)::integer,
    coalesce(sum(case
      when session.clock_out_at is not null
      then greatest(0, floor(extract(epoch from (duty.end_at - session.clock_out_at)) / 60)::integer)
      else 0
    end), 0)::integer
  from duty
  left join public.attendance_sessions session
    on session.schedule_id = duty.id
    and session.organization_id = v_organization_id;
end;
$$;

grant select on public.attendance_sessions to authenticated;
grant execute on function public.record_attendance_event(text, double precision, double precision),
  public.record_attendance_punch(text, double precision, double precision, boolean, text),
  public.complete_schedule(uuid),
  public.evaluate_time_record(uuid, date, date)
to authenticated;
