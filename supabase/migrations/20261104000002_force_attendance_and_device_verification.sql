-- =============================================================================
-- Migration: 20261104000002_force_attendance_and_device_verification.sql
-- Purpose:
--   1. Item #4: Dual-point proximity distance metrics (distance_from_post_meters,
--      dual_point_distance_meters) on public.attendance_sessions.
--   2. Item #5: Allow Time-In outside designated location subject to Operations
--      Head Force Attendance approval (force_attendance_requested,
--      force_attendance_reason, force_attendance_status, force_attendance_reviewed_by,
--      force_attendance_reviewed_at, force_attendance_review_note).
--   3. Items #6, #7, #20: Device ID / Hardware Verification & Live Face Capture
--      (registered_device_id, registered_device_info, registered_device_at on
--      public.profiles; device_id, device_info, device_verified, clock_in_face_photo
--      on public.attendance_sessions).
-- =============================================================================

-- 1. Extend public.profiles with Device Registration / Binding columns (#7, #20)
alter table public.profiles
  add column if not exists registered_device_id text,
  add column if not exists registered_device_info text,
  add column if not exists registered_device_at timestamptz;

-- 2. Extend public.attendance_sessions with Force Attendance, Proximity & Biometric/Device columns (#4, #5, #6, #7, #20)
alter table public.attendance_sessions
  add column if not exists force_attendance_requested boolean not null default false,
  add column if not exists force_attendance_reason text,
  add column if not exists force_attendance_status text check (force_attendance_status in ('pending', 'approved', 'rejected')),
  add column if not exists force_attendance_reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists force_attendance_reviewed_at timestamptz,
  add column if not exists force_attendance_review_note text,
  add column if not exists distance_from_post_meters double precision,
  add column if not exists dual_point_distance_meters double precision,
  add column if not exists device_id text,
  add column if not exists device_info text,
  add column if not exists device_verified boolean default true,
  add column if not exists clock_in_face_photo text;

create index if not exists idx_attendance_sessions_force_status
  on public.attendance_sessions (organization_id, force_attendance_status, clock_in_at desc)
  where force_attendance_requested = true;

-- 3. RPC: bind_or_verify_guard_device (#7, #20)
--    Registers a guard's cellular/mobile device ID on first use, or verifies that
--    subsequent logins/punches come from the registered device (Operations Head
--    can reset registered_device_id if the guard changes phones).
create or replace function public.bind_or_verify_guard_device(
  p_device_id text,
  p_device_info text default null,
  p_force_rebind boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_clean_id text := nullif(trim(coalesce(p_device_id, '')), '');
  v_clean_info text := nullif(trim(coalesce(p_device_info, '')), '');
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if v_clean_id is null then
    return jsonb_build_object(
      'verified', false,
      'status', 'missing_device_id',
      'message', 'Could not read device identifier.'
    );
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;

  if not found then
    raise exception 'Profile not found.' using errcode = '42501';
  end if;

  if v_profile.registered_device_id is null or trim(v_profile.registered_device_id) = '' or p_force_rebind then
    update public.profiles
    set registered_device_id = v_clean_id,
        registered_device_info = coalesce(v_clean_info, registered_device_info),
        registered_device_at = now()
    where id = v_uid;

    return jsonb_build_object(
      'verified', true,
      'status', 'bound',
      'registered_device_id', v_clean_id,
      'registered_device_info', v_clean_info
    );
  end if;

  if v_profile.registered_device_id = v_clean_id then
    if v_clean_info is not null and v_clean_info is distinct from v_profile.registered_device_info then
      update public.profiles
      set registered_device_info = v_clean_info
      where id = v_uid;
    end if;

    return jsonb_build_object(
      'verified', true,
      'status', 'matched',
      'registered_device_id', v_profile.registered_device_id,
      'registered_device_info', coalesce(v_clean_info, v_profile.registered_device_info)
    );
  end if;

  return jsonb_build_object(
    'verified', false,
    'status', 'mismatch',
    'registered_device_id', v_profile.registered_device_id,
    'registered_device_info', v_profile.registered_device_info,
    'current_device_id', v_clean_id,
    'current_device_info', v_clean_info,
    'message', 'Unrecognized device detected. This account is bound to ' || coalesce(v_profile.registered_device_info, v_profile.registered_device_id) || '.'
  );
end;
$$;

revoke all on function public.bind_or_verify_guard_device(text, text, boolean) from public, anon;
grant execute on function public.bind_or_verify_guard_device(text, text, boolean) to authenticated;

-- 4. RPC: reset_guard_registered_device (Operations Head utility to clear/reset a guard's bound phone)
create or replace function public.reset_guard_registered_device(
  p_guard_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
begin
  if not coalesce(public.is_admin(), false) and not coalesce(public.is_it_admin(), false) then
    raise exception 'Only Operations Head or Admin can reset a guard''s registered device.' using errcode = '42501';
  end if;

  update public.profiles
  set registered_device_id = null,
      registered_device_info = null,
      registered_device_at = null
  where id = p_guard_id
    and (organization_id = v_org or public.is_it_admin());

  return found;
end;
$$;

revoke all on function public.reset_guard_registered_device(uuid) from public, anon;
grant execute on function public.reset_guard_registered_device(uuid) to authenticated;

-- 5. RPC: attach_attendance_verification_metadata (#4, #6, #7, #20)
--    Attaches live face photo, device info, and dual-point proximity metrics to an attendance session.
create or replace function public.attach_attendance_verification_metadata(
  p_session_id uuid,
  p_device_id text default null,
  p_device_info text default null,
  p_face_photo text default null,
  p_distance_from_post_meters double precision default null
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid := public.current_organization_id();
  v_session public.attendance_sessions;
  v_profile public.profiles;
  v_verified boolean := true;
  v_dual_dist double precision := null;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select * into v_session
  from public.attendance_sessions
  where id = p_session_id
    and user_id = v_uid
    and organization_id = v_org
  for update;

  if not found then
    raise exception 'Attendance session not found.' using errcode = '42501';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid;

  if p_device_id is not null and trim(p_device_id) <> '' then
    if v_profile.registered_device_id is null or trim(v_profile.registered_device_id) = '' then
      update public.profiles
      set registered_device_id = trim(p_device_id),
          registered_device_info = coalesce(nullif(trim(p_device_info), ''), registered_device_info),
          registered_device_at = now()
      where id = v_uid;
      v_verified := true;
    else
      v_verified := (v_profile.registered_device_id = trim(p_device_id));
    end if;
  end if;

  if v_session.clock_in_latitude is not null and v_session.clock_in_longitude is not null
     and v_session.clock_out_latitude is not null and v_session.clock_out_longitude is not null then
    v_dual_dist := 6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(v_session.clock_in_latitude)) * cos(radians(v_session.clock_out_latitude)) *
      cos(radians(v_session.clock_out_longitude) - radians(v_session.clock_in_longitude)) +
      sin(radians(v_session.clock_in_latitude)) * sin(radians(v_session.clock_out_latitude))
    )));
  end if;

  update public.attendance_sessions
  set device_id = coalesce(nullif(trim(p_device_id), ''), device_id),
      device_info = coalesce(nullif(trim(p_device_info), ''), device_info),
      device_verified = v_verified,
      clock_in_face_photo = coalesce(nullif(trim(p_face_photo), ''), clock_in_face_photo),
      distance_from_post_meters = coalesce(p_distance_from_post_meters, distance_from_post_meters),
      dual_point_distance_meters = coalesce(v_dual_dist, dual_point_distance_meters),
      updated_at = now()
  where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

revoke all on function public.attach_attendance_verification_metadata(uuid, text, text, text, double precision) from public, anon;
grant execute on function public.attach_attendance_verification_metadata(uuid, text, text, text, double precision) to authenticated;

-- 6. RPC: request_force_attendance_clock_in (#4, #5, #6, #7, #20)
--    Allows a guard who is outside their designated post geofence (e.g., at a seminar,
--    roving assignment, or GPS boundary offset) to record Time-In subject to
--    Operations Head Force Attendance approval.
create or replace function public.request_force_attendance_clock_in(
  p_latitude double precision,
  p_longitude double precision,
  p_reason text,
  p_device_id text default null,
  p_device_info text default null,
  p_face_photo text default null
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_organization_id uuid := public.current_organization_id();
  v_duty record;
  v_result public.attendance_sessions;
  v_clean_reason text := trim(coalesce(p_reason, ''));
  v_dist_meters double precision;
  v_profile public.profiles;
  v_device_verified boolean := true;
  v_head record;
  v_guard_name text;
begin
  if not public.is_active_guard() and not public.is_active_duty_personnel() then
    raise exception 'Only active Guard accounts can request Force Attendance.' using errcode = '42501';
  end if;

  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Valid GPS coordinates are required to request Force Attendance.';
  end if;

  if char_length(v_clean_reason) < 5 then
    raise exception 'Please provide a reason of at least 5 characters (e.g., Seminar, Roving Duty, Client Errand).';
  end if;

  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_organization_id::text || ':' || auth.uid()::text, 0)
  );

  if exists (
    select 1 from public.attendance_sessions session
    where session.user_id = auth.uid()
      and session.organization_id = v_organization_id
      and session.status = 'open'
      and session.scheduled_end_at > v_now
  ) then
    raise exception 'Time Out of your open duty session before starting another one.';
  end if;

  select s.id as schedule_id, s.location_id, s.start_at, s.end_at,
    s.duty_days, l.label as location_label, l.latitude as post_lat, l.longitude as post_lng
  into v_duty
  from public.schedules s
  join public.locations l on l.id = s.location_id and l.active
    and l.organization_id = v_organization_id
  where s.user_id = auth.uid()
    and s.organization_id = v_organization_id
    and s.approval_status in ('approved', 'changed')
    and not s.marked_done
    and v_now >= s.start_at - interval '2 hours'
    and v_now < s.end_at
  order by s.start_at asc
  limit 1;

  if not found then
    raise exception 'No active duty schedule found for Force Attendance (allowed from 2 hours before shift start until shift end).';
  end if;

  v_dist_meters := 6371000 * acos(least(1.0, greatest(-1.0,
    cos(radians(v_duty.post_lat)) * cos(radians(p_latitude)) *
    cos(radians(p_longitude) - radians(v_duty.post_lng)) +
    sin(radians(v_duty.post_lat)) * sin(radians(p_latitude))
  )));

  select * into v_profile from public.profiles where id = auth.uid();
  if p_device_id is not null and trim(p_device_id) <> '' then
    if v_profile.registered_device_id is null or trim(v_profile.registered_device_id) = '' then
      update public.profiles
      set registered_device_id = trim(p_device_id),
          registered_device_info = coalesce(nullif(trim(p_device_info), ''), registered_device_info),
          registered_device_at = v_now
      where id = auth.uid();
      v_device_verified := true;
    else
      v_device_verified := (v_profile.registered_device_id = trim(p_device_id));
    end if;
  end if;

  update public.attendance_sessions
  set status = 'missed_timeout', updated_at = v_now
  where user_id = auth.uid()
    and organization_id = v_organization_id
    and status = 'open'
    and clock_out_at is null
    and scheduled_end_at <= v_now;

  insert into public.attendance_sessions (
    organization_id, schedule_id, user_id, location_id, location_label,
    duty_date, scheduled_start_at, scheduled_end_at, clock_in_at,
    clock_in_latitude, clock_in_longitude,
    force_attendance_requested, force_attendance_reason, force_attendance_status,
    distance_from_post_meters, device_id, device_info, device_verified, clock_in_face_photo
  ) values (
    v_organization_id, v_duty.schedule_id, auth.uid(), v_duty.location_id,
    v_duty.location_label, (v_duty.start_at at time zone 'Asia/Manila')::date,
    v_duty.start_at, v_duty.end_at, v_now, p_latitude, p_longitude,
    true, v_clean_reason, 'pending',
    round(v_dist_meters::numeric, 1)::double precision,
    nullif(trim(coalesce(p_device_id, '')), ''),
    nullif(trim(coalesce(p_device_info, '')), ''),
    v_device_verified,
    nullif(trim(coalesce(p_face_photo, '')), '')
  ) returning * into v_result;

  -- Notify Operations Head of Force Attendance request
  select coalesce(nullif(trim(concat_ws(' ', first_name, last_name)), ''), 'A guard')
  into v_guard_name
  from public.profiles where id = auth.uid();

  for v_head in
    select id from public.profiles
    where organization_id = v_organization_id and active and role = 'admin'
  loop
    begin
      perform public.insert_user_notification(
        v_head.id,
        v_organization_id,
        'system',
        'high',
        'Force Attendance Approval Needed',
        v_guard_name || ' clocked in outside ' || coalesce(v_duty.location_label, 'assigned post') ||
          ' (' || round(v_dist_meters)::text || 'm away). Reason: ' || v_clean_reason,
        'personnel',
        'attendance_session',
        v_result.id,
        jsonb_build_object('guard_id', auth.uid(), 'session_id', v_result.id, 'distance_m', round(v_dist_meters)),
        false,
        auth.uid(),
        'force-att:' || v_result.id::text
      );
    exception when others then
      null;
    end;
  end loop;

  return v_result;
end;
$$;

revoke all on function public.request_force_attendance_clock_in(double precision, double precision, text, text, text, text) from public, anon;
grant execute on function public.request_force_attendance_clock_in(double precision, double precision, text, text, text, text) to authenticated;

-- 7. RPC: request_force_attendance_clock_out (#5)
--    Allows a guard whose session was opened via Force Attendance (or who is still at a seminar/off-site location)
--    to record Time-Out outside the geofence, computing the dual-point distance between Time-In and Time-Out.
create or replace function public.request_force_attendance_clock_out(
  p_session_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_claim_overtime boolean default null
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_now timestamptz := clock_timestamp();
  v_session public.attendance_sessions;
  v_late boolean;
  v_dual_dist double precision := null;
begin
  if not coalesce(public.is_active_guard(), false) or v_org is null then
    raise exception 'Only active Guard accounts can record Time Out.' using errcode = '42501';
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Valid GPS coordinates are required for Time Out.';
  end if;

  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text || ':' || auth.uid()::text, 0));

  select * into v_session
  from public.attendance_sessions
  where id = p_session_id and user_id = auth.uid() and organization_id = v_org
  for update;

  if not found then
    raise exception 'Attendance record was not found.' using errcode = '42501';
  end if;

  if v_session.status <> 'open' or v_session.clock_out_at is not null then
    raise exception 'This duty session is already closed.';
  end if;

  v_late := v_now > v_session.scheduled_end_at;
  if v_late and p_claim_overtime is null then
    raise exception 'Your shift has ended. Tap Time Out again and choose whether you worked overtime.';
  end if;

  v_dual_dist := 6371000 * acos(least(1.0, greatest(-1.0,
    cos(radians(v_session.clock_in_latitude)) * cos(radians(p_latitude)) *
    cos(radians(p_longitude) - radians(v_session.clock_in_longitude)) +
    sin(radians(v_session.clock_in_latitude)) * sin(radians(p_latitude))
  )));

  update public.attendance_sessions
  set clock_out_at = case when v_late and p_claim_overtime is false then scheduled_end_at else v_now end,
      timeout_submitted_at = v_now,
      overtime_requested = v_late and coalesce(p_claim_overtime, false),
      clock_out_latitude = p_latitude,
      clock_out_longitude = p_longitude,
      clock_out_location_status = case when force_attendance_status = 'approved' then 'verified' else 'outside_post_pending' end,
      dual_point_distance_meters = round(v_dual_dist::numeric, 1)::double precision,
      force_attendance_requested = true,
      force_attendance_status = coalesce(force_attendance_status, 'pending'),
      status = 'closed',
      updated_at = v_now
  where id = v_session.id
  returning * into v_session;

  if v_session.force_attendance_status = 'approved' and not coalesce(v_session.overtime_requested, false) then
    perform public.complete_schedule(v_session.schedule_id);
  end if;

  return v_session;
end;
$$;

revoke all on function public.request_force_attendance_clock_out(uuid, double precision, double precision, boolean) from public, anon;
grant execute on function public.request_force_attendance_clock_out(uuid, double precision, double precision, boolean) to authenticated;

-- 8. RPC: decide_force_attendance (#5)
--    Operations Head approves or rejects a Force Attendance session.
create or replace function public.decide_force_attendance(
  p_session_id uuid,
  p_decision text,
  p_note text default null
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_session public.attendance_sessions;
  v_clean_decision text := lower(trim(coalesce(p_decision, '')));
  v_clean_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not coalesce(public.is_admin(), false) and not coalesce(public.is_it_admin(), false) then
    raise exception 'Only the Operations Head can approve or reject Force Attendance.' using errcode = '42501';
  end if;

  if v_clean_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected.';
  end if;

  select * into v_session
  from public.attendance_sessions
  where id = p_session_id
    and (organization_id = v_org or public.is_it_admin())
  for update;

  if not found then
    raise exception 'Attendance session not found.' using errcode = '42501';
  end if;

  update public.attendance_sessions
  set force_attendance_status = v_clean_decision,
      force_attendance_reviewed_by = auth.uid(),
      force_attendance_reviewed_at = now(),
      force_attendance_review_note = v_clean_note,
      clock_out_location_status = case
        when v_clean_decision = 'approved' and clock_out_at is not null then 'verified'
        when v_clean_decision = 'rejected' then 'rejected'
        else clock_out_location_status
      end,
      updated_at = now()
  where id = p_session_id
  returning * into v_session;

  if v_clean_decision = 'approved' and v_session.status = 'closed' and not coalesce(v_session.overtime_requested, false) then
    perform public.complete_schedule(v_session.schedule_id);
  end if;

  begin
    perform public.insert_user_notification(
      v_session.user_id,
      v_session.organization_id,
      'system',
      'normal',
      'Force Attendance ' || initcap(v_clean_decision),
      'Your Operations Head ' || v_clean_decision || ' your outside-location attendance for ' ||
        coalesce(v_session.location_label, 'your post') || ' on ' || v_session.duty_date::text ||
        case when v_clean_note is not null then ' (' || v_clean_note || ').' else '.' end,
      'system',
      'attendance_session',
      v_session.id,
      jsonb_build_object('session_id', v_session.id, 'decision', v_clean_decision),
      false,
      auth.uid(),
      'force-att-decision:' || v_session.id::text || ':' || v_clean_decision
    );
  exception when others then
    null;
  end;

  return v_session;
end;
$$;

revoke all on function public.decide_force_attendance(uuid, text, text) from public, anon;
grant execute on function public.decide_force_attendance(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
