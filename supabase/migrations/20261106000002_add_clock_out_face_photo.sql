-- Migration: 20261106000002_add_clock_out_face_photo.sql
-- Description: Adds clock_out_face_photo column to public.attendance_sessions
-- and updates attach_attendance_verification_metadata to record Time Out face verification.

-- 1. Extend public.attendance_sessions with clock_out_face_photo
alter table public.attendance_sessions
  add column if not exists clock_out_face_photo text;

-- 2. Update attach_attendance_verification_metadata RPC
create or replace function public.attach_attendance_verification_metadata(
  p_session_id uuid,
  p_device_id text default null,
  p_device_info text default null,
  p_face_photo text default null,
  p_distance_from_post_meters double precision default null,
  p_clock_out_face_photo text default null
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
      clock_in_face_photo = case
        when p_face_photo is not null and v_session.clock_out_at is null
          then nullif(trim(p_face_photo), '')
        else clock_in_face_photo
      end,
      clock_out_face_photo = case
        when p_clock_out_face_photo is not null
          then nullif(trim(p_clock_out_face_photo), '')
        when p_face_photo is not null and v_session.clock_out_at is not null
          then nullif(trim(p_face_photo), '')
        else clock_out_face_photo
      end,
      distance_from_post_meters = coalesce(p_distance_from_post_meters, distance_from_post_meters),
      dual_point_distance_meters = coalesce(v_dual_dist, dual_point_distance_meters),
      updated_at = now()
  where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

revoke all on function public.attach_attendance_verification_metadata(uuid, text, text, text, double precision, text) from public, anon;
grant execute on function public.attach_attendance_verification_metadata(uuid, text, text, text, double precision, text) to authenticated;

