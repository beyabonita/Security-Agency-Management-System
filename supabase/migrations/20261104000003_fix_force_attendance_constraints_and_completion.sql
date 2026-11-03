-- =============================================================================
-- Migration: 20261104000003_fix_force_attendance_constraints_and_completion.sql
-- Purpose:
--   Fixes two SQL constraint/completion edge cases found during the audit of
--   20261104000002_force_attendance_and_device_verification.sql:
--   1. public.attendance_sessions.clock_out_location_status has a CHECK constraint:
--      check (clock_out_location_status in ('verified','unavailable','outside_post','operational_release')).
--      Using 'outside_post_pending' or 'rejected' in request_force_attendance_clock_out /
--      decide_force_attendance would raise a 23514 check_violation error. Updated to
--      use 'outside_post' (and 'verified' when approved).
--   2. public.complete_schedule(p_schedule_id) checks `user_id = auth.uid()`, so calling
--      it from decide_force_attendance when the Operations Head (admin) is logged in
--      would raise an exception because `auth.uid()` is the admin, not the guard.
--      Updated decide_force_attendance to mark the guard's schedule done and increment
--      duty_days_total directly under the guard's user_id.
-- =============================================================================

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
  if not coalesce(public.is_active_guard(), false) and not coalesce(public.is_active_duty_personnel(), false) then
    raise exception 'Only active Guard accounts can record Time Out.' using errcode = '42501';
  end if;

  if v_org is null then
    raise exception 'This account is not assigned to an active organization.';
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
      clock_out_location_status = case when force_attendance_status = 'approved' then 'verified' else 'outside_post' end,
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
  v_now timestamptz := now();
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
      force_attendance_reviewed_at = v_now,
      force_attendance_review_note = v_clean_note,
      clock_out_location_status = case
        when v_clean_decision = 'approved' and clock_out_at is not null then 'verified'
        when v_clean_decision = 'rejected' and clock_out_at is not null then 'outside_post'
        else clock_out_location_status
      end,
      updated_at = v_now
  where id = p_session_id
  returning * into v_session;

  -- Complete the guard's schedule directly using v_session.user_id (since auth.uid() is the admin)
  if v_clean_decision = 'approved' and v_session.status = 'closed' and not coalesce(v_session.overtime_requested, false) then
    perform 1 from public.schedules where id = v_session.schedule_id for update;
    perform 1 from public.profiles where id = v_session.user_id and organization_id = v_session.organization_id for update;

    update public.schedules
    set marked_done = true,
        completed_at = coalesce(completed_at, v_now),
        completed_by = coalesce(completed_by, auth.uid())
    where id = v_session.schedule_id
      and organization_id = v_session.organization_id
      and user_id = v_session.user_id
      and not marked_done;

    if found and not exists (
      select 1 from public.attendance_sessions other
      join public.schedules done on done.id = other.schedule_id
        and done.organization_id = v_session.organization_id
        and done.marked_done
      where other.user_id = v_session.user_id
        and other.organization_id = v_session.organization_id
        and other.duty_date = v_session.duty_date
        and other.status = 'closed'
        and other.id <> v_session.id
    ) then
      update public.profiles
      set duty_days_total = duty_days_total + 1
      where id = v_session.user_id
        and organization_id = v_session.organization_id
        and role = 'user';
    end if;
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
