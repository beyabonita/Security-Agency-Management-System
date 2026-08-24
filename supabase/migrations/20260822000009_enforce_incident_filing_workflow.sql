-- Emergency reports are filed atomically after capture. The server derives the
-- guard and organization, records the filing time, and blocks direct writes.

drop policy if exists "active tenant personnel create incidents" on public.incidents;
drop policy if exists "active guards create incidents" on public.incidents;
drop policy if exists "operations delete tenant incidents" on public.incidents;
drop policy if exists "admins delete incidents" on public.incidents;
revoke insert, update, delete on public.incidents from authenticated;

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
  if not public.is_active_duty_personnel() then
    raise exception 'Only active duty personnel can file an emergency alert.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if p_category not in ('crime', 'fire', 'medical', 'disturbance', 'other') then
    raise exception 'Choose a valid incident category.';
  end if;
  if char_length(coalesce(p_photo_data, '')) not between 100 and 750000
    or p_photo_data !~ '^[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'A valid incident photo is required.';
  end if;
  if char_length(trim(coalesce(p_guard_remarks, ''))) not between 10 and 2000 then
    raise exception 'Guard remarks must contain 10 to 2,000 characters before filing an alert.';
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
    trim(p_guard_remarks),
    trim(p_guard_remarks),
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

-- A video that fails to file must be removable by the uploading duty user. A
-- referenced video cannot be deleted through the client, preserving evidence.
drop policy if exists "active personnel remove own unfiled incident video" on storage.objects;
create policy "active personnel remove own unfiled incident video"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'incident-videos'
  and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = auth.uid()::text
  and not exists (
    select 1
    from public.incidents incident
    where incident.video_path = storage.objects.name
  )
);

create or replace function public.update_incident_status(
  p_incident_id uuid,
  p_status text,
  p_status_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_rows integer;
begin
  if p_status not in ('open', 'acknowledged', 'resolved') then
    raise exception 'Invalid incident status.';
  end if;
  if char_length(trim(coalesce(p_status_note, ''))) > 500 then
    raise exception 'Incident status note cannot exceed 500 characters.';
  end if;
  if p_status = 'resolved'
    and char_length(trim(coalesce(p_status_note, ''))) < 5 then
    raise exception 'Add a resolution note of at least 5 characters before closing an incident.';
  end if;

  if public.is_it_admin() then
    if p_status = 'resolved' and not exists (
      select 1
      from public.incidents incident
      where incident.id = p_incident_id
        and incident.filed_at is not null
        and incident.captured_at is not null
        and char_length(trim(incident.detailed_narrative)) >= 10
        and (incident.video_path is null or incident.video_duration_seconds between 1 and 15)
    ) then
      raise exception 'The guard must file a timestamped incident report with remarks before it can be resolved.';
    end if;

    update public.incidents
    set status = p_status,
        status_note = trim(coalesce(p_status_note, '')),
        updated_at = now(),
        updated_by = auth.uid()
    where id = p_incident_id;
  else
    if not public.is_staff() then
      raise exception 'You are not allowed to update this incident.';
    end if;

    v_organization_id := public.current_organization_id();
    if v_organization_id is null then
      raise exception 'This account is not assigned to an active organization.';
    end if;

    if p_status = 'resolved' and not exists (
      select 1
      from public.incidents incident
      where incident.id = p_incident_id
        and incident.organization_id = v_organization_id
        and incident.filed_at is not null
        and incident.captured_at is not null
        and char_length(trim(incident.detailed_narrative)) >= 10
        and (incident.video_path is null or incident.video_duration_seconds between 1 and 15)
    ) then
      raise exception 'The guard must file a timestamped incident report with remarks before it can be resolved.';
    end if;

    update public.incidents
    set status = p_status,
        status_note = trim(coalesce(p_status_note, '')),
        updated_at = now(),
        updated_by = auth.uid()
    where id = p_incident_id
      and organization_id = v_organization_id;
  end if;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'Incident not found or no longer accessible.';
  end if;
end;
$$;

grant execute on function public.file_incident_report(
  text, text, text, timestamptz, text, integer, double precision, double precision, text
), public.update_incident_status(uuid, text, text)
to authenticated;
