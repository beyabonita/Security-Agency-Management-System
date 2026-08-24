-- Inspector accounts review Guard operations but do not record personal
-- attendance. Keep the mature schedule/geofence implementation private and
-- expose it only through a Guard-authorized wrapper.
alter function public.record_attendance_event(
  text,
  double precision,
  double precision
) rename to record_attendance_event_for_guard_internal;

revoke all on function public.record_attendance_event_for_guard_internal(
  text,
  double precision,
  double precision
) from public, anon, authenticated;

alter function public.record_attendance_punch(
  text,
  double precision,
  double precision,
  boolean,
  text
) rename to record_attendance_punch_for_guard_internal;

revoke all on function public.record_attendance_punch_for_guard_internal(
  text,
  double precision,
  double precision,
  boolean,
  text
) from public, anon, authenticated;

create function public.record_attendance_event(
  p_action text,
  p_latitude double precision,
  p_longitude double precision
)
returns public.attendance_sessions
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_guard() then
    raise exception using
      errcode = '42501',
      message = 'Only active Guard accounts can record Time In or Time Out.';
  end if;

  return public.record_attendance_event_for_guard_internal(
    p_action,
    p_latitude,
    p_longitude
  );
end;
$$;

revoke all on function public.record_attendance_event(
  text,
  double precision,
  double precision
) from public, anon;
grant execute on function public.record_attendance_event(
  text,
  double precision,
  double precision
) to authenticated;

comment on function public.record_attendance_event(
  text,
  double precision,
  double precision
) is 'Records schedule-linked geofenced attendance for active Guard accounts only.';

create function public.record_attendance_punch(
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
begin
  if not public.is_active_guard() then
    raise exception using
      errcode = '42501',
      message = 'Only active Guard accounts can record Time In or Time Out.';
  end if;

  return public.record_attendance_punch_for_guard_internal(
    p_punch_type,
    p_latitude,
    p_longitude,
    p_within_geofence,
    p_location_label
  );
end;
$$;

revoke all on function public.record_attendance_punch(
  text,
  double precision,
  double precision,
  boolean,
  text
) from public, anon;
grant execute on function public.record_attendance_punch(
  text,
  double precision,
  double precision,
  boolean,
  text
) to authenticated;

comment on function public.record_attendance_punch(
  text,
  double precision,
  double precision,
  boolean,
  text
) is 'Legacy Guard-only compatibility wrapper for schedule-linked attendance.';
