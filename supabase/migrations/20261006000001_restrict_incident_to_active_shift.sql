-- Restrict incident filing to guards and inspectors who are currently clocked-in
-- (have an active attendance session that has not been clocked out yet).
-- This prevents off-duty personnel from filing incident reports.

-- Helper function: true when the calling guard/inspector has a live, unfinished attendance session.
create or replace function public.is_on_active_shift()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.attendance_sessions s
    where s.user_id = auth.uid()
      and s.organization_id = public.current_organization_id()
      and s.clock_in_at is not null
      and s.clock_out_at is null
      and s.status in ('clocked_in', 'active', 'pending_timeout', 'pending_review')
  );
$$;

revoke all on function public.is_on_active_shift() from public, anon;
grant execute on function public.is_on_active_shift() to authenticated;
comment on function public.is_on_active_shift() is
  'Returns true when the authenticated user has an active, unfinished attendance session (clocked-in, not yet clocked-out).';

-- Replace file_incident_report guard: require an active shift, not just an active account.
create or replace function public.file_incident_report(
  p_category text,
  p_photo_data text,
  p_guard_remarks text,
  p_captured_at timestamptz,
  p_video_path text default null,
  p_video_duration_seconds integer default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_location_label text default null
)
returns public.incidents
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_now timestamptz := now();
  v_organization_id uuid;
  v_guard_name text;
  v_guard_email text;
  v_incident public.incidents;
begin
  -- Must be an active guard/inspector account.
  if not public.is_active_duty_personnel() then
    raise exception 'Only active duty personnel can file an emergency alert.';
  end if;

  -- Must be currently clocked-in on an active shift.
  if not public.is_on_active_shift() then
    raise exception 'You must be clocked-in on an active shift to file an incident report.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if p_category not in ('crime', 'fire', 'medical', 'disturbance', 'other') then
    raise exception 'Choose a valid incident category.';
  end if;
  if p_photo_data is null and p_video_path is null then
    raise exception 'Capture a photo or record a video before filing the alert.';
  end if;
  if p_photo_data is not null and (
    char_length(p_photo_data) not between 100 and 750000
    or p_photo_data !~ '^[A-Za-z0-9+/]+={0,2}$'
  ) then
    raise exception 'The incident photo is invalid. Retake it before filing.';
  end if;
  if coalesce(p_guard_remarks, '') !~ '[^[:space:]]'
    or char_length(trim(p_guard_remarks)) > 2000 then
    raise exception 'Enter an incident narrative of up to 2,000 characters.';
  end if;
  if p_captured_at is null
    or p_captured_at < v_now - interval '10 minutes'
    or p_captured_at > v_now + interval '1 minute' then
    raise exception 'The capture timestamp is invalid or too old. Capture the incident again before filing.';
  end if;

  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'Provide both GPS coordinates or leave both empty.';
  end if;
  if p_latitude is not null
    and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    raise exception 'Incident GPS coordinates are invalid.';
  end if;

  if p_video_path is null then
    if p_video_duration_seconds is not null then
      raise exception 'Video duration cannot be supplied without a video.';
    end if;
  else
    if char_length(p_video_path) > 500
      or p_video_path !~ ('^' || auth.uid()::text || '/[A-Za-z0-9._-]+$') then
      raise exception 'Incident video path is invalid.';
    end if;
    if p_video_duration_seconds is null
      or p_video_duration_seconds not between 1 and 15 then
      raise exception 'Incident video must be 15 seconds or less.';
    end if;
    if not exists (
      select 1
      from storage.objects object
      where object.bucket_id = 'incident-videos'
        and object.name = p_video_path
    ) then
      raise exception 'The captured incident video was not found.';
    end if;
  end if;

  select
    coalesce(
      nullif(trim(concat_ws(' ', profile.first_name, nullif(profile.middle_initial, ''), profile.last_name)), ''),
      nullif(profile.username, ''),
      'Duty personnel'
    ),
    coalesce(profile.email, '')
  into v_guard_name, v_guard_email
  from public.profiles profile
  where profile.id = auth.uid()
    and profile.organization_id = v_organization_id;
  if not found then
    raise exception 'Your personnel record was not found in this organization.';
  end if;

  insert into public.incidents (
    user_id,
    organization_id,
    guard_name,
    guard_email,
    category,
    incident_title,
    description,
    detailed_narrative,
    immediate_action,
    photo_data,
    captured_at,
    filed_at,
    video_path,
    video_duration_seconds,
    latitude,
    longitude,
    location_label,
    status
  ) values (
    auth.uid(),
    v_organization_id,
    v_guard_name,
    v_guard_email,
    p_category,
    case p_category
      when 'crime' then 'Crime / theft emergency alert'
      when 'fire' then 'Fire / hazard emergency alert'
      when 'medical' then 'Medical emergency alert'
      when 'disturbance' then 'Disturbance emergency alert'
      else 'Emergency incident alert'
    end,
    trim(coalesce(p_guard_remarks, '')),
    trim(coalesce(p_guard_remarks, '')),
    'Emergency alert filed through Sentinel Link.',
    p_photo_data,
    p_captured_at,
    v_now,
    p_video_path,
    p_video_duration_seconds,
    p_latitude,
    p_longitude,
    nullif(left(trim(coalesce(p_location_label, '')), 250), ''),
    'open'
  ) returning * into v_incident;

  return v_incident;
end;
$$;

-- Tighten the RLS insert policy to also require an active shift.
drop policy if exists "active tenant personnel create incidents" on public.incidents;
create policy "active tenant personnel create incidents"
  on public.incidents
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and organization_id = public.current_organization_id()
    and public.is_active_duty_personnel()
    and public.is_on_active_shift()
  );

notify pgrst, 'reload schema';
