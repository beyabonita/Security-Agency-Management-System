-- Preserve real punches. An expired missing punch or an unverified late punch
-- contributes no worked hours until an agency Admin verifies its actual end.
alter table public.attendance_sessions
  add column timeout_verified_at timestamptz,
  add column timeout_verified_by uuid references public.profiles(id) on delete restrict,
  add column timeout_verification_reason text,
  add constraint attendance_timeout_verification_complete check (
    (timeout_verified_at is null and timeout_verified_by is null and timeout_verification_reason is null)
    or (timeout_verified_at is not null and timeout_verified_by is not null
      and timeout_verification_reason is not null
      and char_length(trim(timeout_verification_reason)) between 5 and 1500
      and status = 'closed' and clock_out_at is not null)
  );

create table public.attendance_timeout_reviews (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  session_id uuid not null references public.attendance_sessions(id) on delete restrict,
  guard_id uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_at timestamptz not null default now(),
  verified_clock_out_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 5 and 1500),
  before_record jsonb not null
);
create index attendance_timeout_reviews_session_idx on public.attendance_timeout_reviews(session_id, reviewed_at);
alter table public.attendance_timeout_reviews enable row level security;
create policy "agency admins read timeout reviews" on public.attendance_timeout_reviews
for select to authenticated using (
  public.is_admin() and public.current_organization_is_active()
  and organization_id = public.current_organization_id()
);
revoke all on public.attendance_timeout_reviews from public, anon, authenticated;
grant select on public.attendance_timeout_reviews to authenticated;

create function public.verify_attendance_timeout(
  p_session_id uuid, p_clock_out_at timestamptz, p_reason text,
  p_expected_updated_at timestamptz, p_request_id uuid
)
returns public.attendance_sessions
language plpgsql security definer set search_path = '' as $$
declare
  v_session public.attendance_sessions;
  v_review public.attendance_timeout_reviews;
  v_org uuid := public.current_organization_id();
  v_guard uuid;
  v_now timestamptz := clock_timestamp();
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if not coalesce(public.is_admin(), false) or v_org is null
    or not coalesce(public.current_organization_is_active(), false)
    or not exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin' and organization_id = v_org) then
    raise exception 'Only an active agency Admin can verify a missing Time Out.' using errcode = '42501';
  end if;
  if p_request_id is null or p_expected_updated_at is null then
    raise exception 'Reload the attendance record before verifying its Time Out.';
  end if;
  if char_length(v_reason) not between 5 and 1500 then
    raise exception 'Enter a verification reason between 5 and 1500 characters.';
  end if;
  select user_id into v_guard from public.attendance_sessions
    where id = p_session_id and organization_id = v_org;
  if not found then raise exception 'Attendance record was not found.' using errcode = '42501'; end if;
  -- Same lock and ordering as guard punches; correction and new Time In cannot race.
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text || ':' || v_guard::text, 0));
  select * into v_session from public.attendance_sessions
    where id = p_session_id and organization_id = v_org for update;
  select * into v_review from public.attendance_timeout_reviews where id = p_request_id;
  if found then
    if v_review.session_id <> p_session_id or v_review.reviewed_by <> auth.uid()
      or v_review.verified_clock_out_at is distinct from p_clock_out_at or v_review.reason <> v_reason then
      raise exception 'This review request was already used. Reload the attendance record.';
    end if;
    return v_session;
  end if;
  if v_session.updated_at is distinct from p_expected_updated_at then
    raise exception 'This attendance record changed. Reload it before reviewing.';
  end if;
  if v_session.scheduled_end_at >= v_now or v_session.timeout_verified_at is not null
    or not (v_session.clock_out_at is null or v_session.clock_out_at > v_session.scheduled_end_at) then
    raise exception 'Only an ended duty with a missing or unverified late Time Out can be reviewed.';
  end if;
  if p_clock_out_at is null or not isfinite(p_clock_out_at)
    or p_clock_out_at < v_session.clock_in_at or p_clock_out_at > v_now then
    raise exception 'Enter the verified actual Time Out between Time In and the current time.';
  end if;
  if exists (select 1 from public.attendance_sessions other
    where other.user_id = v_guard and other.organization_id = v_org and other.id <> p_session_id
      and other.clock_in_at < p_clock_out_at
      and coalesce(other.clock_out_at, other.scheduled_end_at) > v_session.clock_in_at) then
    raise exception 'The verified interval overlaps another duty. Check the actual Time Out.';
  end if;
  insert into public.attendance_timeout_reviews
    (id, organization_id, session_id, guard_id, reviewed_by, reviewed_at, verified_clock_out_at, reason, before_record)
  values (p_request_id, v_org, p_session_id, v_guard, auth.uid(), v_now, p_clock_out_at, v_reason, to_jsonb(v_session));
  update public.attendance_sessions set clock_out_at = p_clock_out_at,
    clock_out_latitude = null, clock_out_longitude = null, status = 'closed',
    timeout_verified_at = v_now, timeout_verified_by = auth.uid(),
    timeout_verification_reason = v_reason, updated_at = v_now
    where id = p_session_id returning * into v_session;

  -- Match normal duty completion, awarding a DTR date at most once. Previously
  -- completed historical schedules do not gain another day on verification.
  perform 1 from public.schedules where id = v_session.schedule_id for update;
  perform 1 from public.profiles where id = v_guard and organization_id = v_org for update;
  update public.schedules set marked_done = true, completed_at = coalesce(completed_at, v_now),
    completed_by = coalesce(completed_by, auth.uid())
    where id = v_session.schedule_id and organization_id = v_org and user_id = v_guard and not marked_done;
  if found and not exists (
    select 1 from public.attendance_sessions other
    join public.schedules done on done.id = other.schedule_id and done.organization_id = v_org and done.marked_done
    where other.user_id = v_guard and other.organization_id = v_org
      and other.duty_date = v_session.duty_date and other.status = 'closed'
      and other.id <> p_session_id
  ) then
    update public.profiles set duty_days_total = duty_days_total + 1
      where id = v_guard and organization_id = v_org and role = 'user';
  end if;
  return v_session;
end;
$$;
revoke all on function public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid) from public, anon;
grant execute on function public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid) to authenticated;

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
    s.start_at, s.end_at, s.duty_days, session.scheduled_end_at, l.label as location_label
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

  if v_now > v_duty.scheduled_end_at then
    raise exception 'This duty has ended. Ask your admin to verify the missing Time Out. You can still Time In for your next eligible duty.';
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

-- Evaluate the Guard's actual DTR attendance, not future schedule rows or
-- another Guard's reassigned duty. Preserve the existing RPC and permissions.
create or replace function public.evaluate_time_record(
  p_user_id uuid, p_start_date date, p_end_date date
)
returns table(duty_days integer, completed_days integer, total_minutes integer,
  late_minutes integer, undertime_minutes integer)
language plpgsql stable security definer set search_path = ''
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
  with recorded as (
    select a.*,
      case when a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null) then
        greatest(0, floor(extract(epoch from (a.clock_out_at - a.clock_in_at)) / 60))
        else 0 end as worked,
      greatest(0, floor(extract(epoch from (
        least(a.clock_in_at, a.scheduled_end_at) - a.scheduled_start_at
      )) / 60)) as late,
      case when a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null) then
        greatest(0, floor(extract(epoch from (
          a.scheduled_end_at - greatest(a.clock_out_at, a.scheduled_start_at)
        )) / 60)) else 0 end as shortfall
    from public.attendance_sessions a
    where a.user_id = p_user_id and a.organization_id = v_organization_id
      and a.duty_date between p_start_date and p_end_date
      and a.clock_in_at is not null
  ), attended_days as (
    select a.duty_date, bool_and(a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null)) as all_recorded_periods_closed
    from recorded a group by a.duty_date
  ), complete_days as (
    select d.duty_date from attended_days d
    where d.all_recorded_periods_closed
      and not exists (
        select 1 from public.schedules s
        where s.user_id = p_user_id and s.organization_id = v_organization_id
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) = d.duty_date
          and s.approval_status in ('approved', 'changed')
          and not exists (
            select 1 from recorded a where a.schedule_id = s.id and a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null)
          )
      )
  )
  select (select count(*)::integer from attended_days),
    (select count(*)::integer from complete_days),
    coalesce(sum(a.worked), 0)::integer,
    coalesce(sum(a.late), 0)::integer,
    coalesce(sum(a.shortfall), 0)::integer
  from recorded a;
end;
$$;

revoke all on function public.evaluate_time_record(uuid, date, date) from public, anon;
grant execute on function public.evaluate_time_record(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
