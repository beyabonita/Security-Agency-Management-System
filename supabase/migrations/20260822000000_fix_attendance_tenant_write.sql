-- Every attendance record belongs to the caller's organization.  Migration
-- 20260821000012 made this column required but did not provide a value for
-- records created by record_attendance_punch.
alter table public.attendance_punches
  alter column organization_id set default public.current_organization_id();

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
  v_now timestamptz := now();
  v_date date := (now() at time zone 'Asia/Manila')::date;
  v_hour integer := extract(hour from now() at time zone 'Asia/Manila');
  v_organization_id uuid;
  v_location_label text;
  v_result public.attendance_punches;
begin
  -- Kept for RPC compatibility. The server determines the trusted label.
  perform p_location_label;

  if not public.is_active_duty_personnel() then
    raise exception 'This account is not allowed to record attendance.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;

  if p_punch_type not in ('AM In', 'AM Out', 'PM In', 'PM Out') then
    raise exception 'Invalid punch type.';
  end if;

  if (p_punch_type like 'AM %' and v_hour >= 12)
      or (p_punch_type like 'PM %' and v_hour < 12) then
    raise exception 'Punch type is not available at this time.';
  end if;

  if p_punch_type = 'AM Out' and not exists (
    select 1 from public.attendance_punches
    where user_id = auth.uid()
      and punch_date = v_date
      and punch_type = 'AM In'
  ) then
    raise exception 'Record AM In before AM Out.';
  end if;

  if p_punch_type = 'PM Out' and not exists (
    select 1 from public.attendance_punches
    where user_id = auth.uid()
      and punch_date = v_date
      and punch_type = 'PM In'
  ) then
    raise exception 'Record PM In before PM Out.';
  end if;

  if p_latitude is null or p_longitude is null or not p_within_geofence then
    raise exception 'You must be within the geofence of your scheduled duty location.';
  end if;

  select l.label
  into v_location_label
  from public.schedules s
  join public.locations l
    on l.id = s.location_id
    and l.active
    and l.organization_id = v_organization_id
  where s.user_id = auth.uid()
    and s.organization_id = v_organization_id
    and s.approval_status in ('approved', 'changed')
    and s.start_at <= v_now
    and s.end_at >= v_now
    and 6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(l.latitude)) * cos(radians(p_latitude)) *
      cos(radians(p_longitude) - radians(l.longitude)) +
      sin(radians(l.latitude)) * sin(radians(p_latitude))
    ))) <= l.radius_meters
  order by s.start_at desc
  limit 1;

  if v_location_label is null then
    raise exception 'You must be within the geofence of your scheduled duty location during its scheduled time.';
  end if;

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
    auth.uid(),
    v_organization_id,
    v_date,
    p_punch_type,
    v_now,
    p_latitude,
    p_longitude,
    true,
    v_location_label
  ) returning * into v_result;

  return v_result;
end;
$$;
