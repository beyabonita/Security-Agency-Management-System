-- A scheduled shift is the authoritative duty location for attendance.
-- Preserve existing records; prevent only new conflicting shifts.
create or replace function public.prevent_overlapping_active_schedules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.approval_status in ('approved', 'changed') and exists (
    select 1 from public.schedules existing
    where existing.user_id = new.user_id
      and existing.id <> coalesce(new.id, gen_random_uuid())
      and existing.approval_status in ('approved', 'changed')
      and existing.start_at < new.end_at and existing.end_at > new.start_at
  ) then
    raise exception 'This guard already has an overlapping active schedule.';
  end if;
  return new;
end $$;
drop trigger if exists prevent_overlapping_active_schedules on public.schedules;
create trigger prevent_overlapping_active_schedules
  before insert or update of user_id, start_at, end_at, approval_status on public.schedules
  for each row execute function public.prevent_overlapping_active_schedules();

create or replace function public.record_attendance_punch(
  p_punch_type text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_within_geofence boolean default false,
  p_location_label text default null
)
returns public.attendance_punches
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_date date := (now() at time zone 'Asia/Manila')::date;
  v_hour integer := extract(hour from now() at time zone 'Asia/Manila');
  v_location_label text;
  v_result public.attendance_punches;
begin
  if not public.is_active_guard() then raise exception 'This account is not allowed to record attendance.'; end if;
  if p_punch_type not in ('AM In', 'AM Out', 'PM In', 'PM Out') then raise exception 'Invalid punch type.'; end if;
  if (p_punch_type like 'AM %' and v_hour >= 12) or (p_punch_type like 'PM %' and v_hour < 12) then raise exception 'Punch type is not available at this time.'; end if;
  if p_punch_type = 'AM Out' and not exists (select 1 from public.attendance_punches where user_id=auth.uid() and punch_date=v_date and punch_type='AM In') then raise exception 'Record AM In before AM Out.'; end if;
  if p_punch_type = 'PM Out' and not exists (select 1 from public.attendance_punches where user_id=auth.uid() and punch_date=v_date and punch_type='PM In') then raise exception 'Record PM In before PM Out.'; end if;
  if p_latitude is null or p_longitude is null or not p_within_geofence then raise exception 'You must be within the geofence of your scheduled duty location.'; end if;

  select l.label into v_location_label
  from public.schedules s join public.locations l on l.id=s.location_id and l.active
  where s.user_id=auth.uid() and s.approval_status in ('approved','changed')
    and s.start_at <= v_now and s.end_at >= v_now
    and 6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(l.latitude)) * cos(radians(p_latitude)) * cos(radians(p_longitude)-radians(l.longitude)) +
      sin(radians(l.latitude)) * sin(radians(p_latitude))
    ))) <= l.radius_meters
  order by s.start_at desc limit 1;
  if v_location_label is null then raise exception 'You must be within the geofence of your scheduled duty location during its scheduled time.'; end if;

  insert into public.attendance_punches(user_id,punch_date,punch_type,punched_at,latitude,longitude,within_geofence,location_label)
  values(auth.uid(),v_date,p_punch_type,v_now,p_latitude,p_longitude,true,v_location_label)
  returning * into v_result;
  return v_result;
end $$;

create or replace function public.complete_schedule(p_schedule_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_duty_days integer;
begin
  update public.schedules
  set marked_done=true, completed_at=now(), completed_by=auth.uid()
  where id=p_schedule_id and user_id=auth.uid() and not marked_done
    and end_at<=now() and public.is_active_guard()
  returning duty_days into v_duty_days;
  if not found then raise exception 'Schedule cannot be completed yet.'; end if;
  update public.profiles set duty_days_total=duty_days_total+coalesce(v_duty_days,1) where id=auth.uid();
end $$;
