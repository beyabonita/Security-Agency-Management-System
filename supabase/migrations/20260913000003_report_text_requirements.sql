-- Accomplishment reports require text, without minimum sentence lengths.
-- Emergency remarks may be omitted. Keep existing maximum lengths.
alter table public.accomplishment_reports
  drop constraint accomplishment_reports_summary_check,
  drop constraint accomplishment_reports_detailed_narrative_check,
  add constraint accomplishment_reports_summary_check check (char_length(btrim(summary)) between 1 and 1500),
  add constraint accomplishment_reports_detailed_narrative_check check (char_length(btrim(detailed_narrative)) between 1 and 5000);
alter table public.incidents
  drop constraint incidents_description_check,
  add constraint incidents_description_check check (char_length(description) <= 2000);

create or replace function public.submit_accomplishment_report(
  p_schedule_id uuid,
  p_summary text,
  p_detailed_narrative text,
  p_issues_encountered text default ''
)
returns public.accomplishment_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_report public.accomplishment_reports;
begin
  if not public.is_active_guard() then
    raise exception 'Only an active Guard can submit an accomplishment report.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if char_length(trim(coalesce(p_summary, ''))) not between 1 and 1500 then
    raise exception 'Enter a duty summary of up to 1,500 characters.';
  end if;
  if char_length(trim(coalesce(p_detailed_narrative, ''))) not between 1 and 5000 then
    raise exception 'Enter a detailed narrative of up to 5,000 characters.';
  end if;
  if char_length(trim(coalesce(p_issues_encountered, ''))) > 1500 then
    raise exception 'Issues encountered cannot exceed 1,500 characters.';
  end if;

  if exists (
    select 1
    from public.accomplishment_reports report
    where report.schedule_id = p_schedule_id
  ) then
    raise exception 'An accomplishment report was already submitted for this duty.';
  end if;

  if not exists (
    select 1
    from public.schedules schedule
    join public.attendance_sessions session
      on session.schedule_id = schedule.id
      and session.organization_id = schedule.organization_id
      and session.user_id = auth.uid()
      and session.status = 'closed'
      and session.clock_out_at is not null
    where schedule.id = p_schedule_id
      and schedule.user_id = auth.uid()
      and schedule.organization_id = v_organization_id
      and schedule.marked_done
  ) then
    raise exception 'Complete Time Out for this duty before submitting its accomplishment report.';
  end if;

  insert into public.accomplishment_reports (
    schedule_id,
    guard_id,
    organization_id,
    summary,
    detailed_narrative,
    issues_encountered,
    review_status
  ) values (
    p_schedule_id,
    auth.uid(),
    v_organization_id,
    trim(p_summary),
    trim(p_detailed_narrative),
    trim(coalesce(p_issues_encountered, '')),
    'submitted'
  ) returning * into v_report;

  return v_report;
end;
$$;


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
  if char_length(trim(coalesce(p_guard_remarks, ''))) > 2000 then
    raise exception 'Incident remarks cannot exceed 2,000 characters.';
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
create or replace function public.update_incident_status(
  p_incident_id uuid, p_status text, p_status_note text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare incident public.incidents;
begin
  -- Check authorization before returning report-specific validation details.
  if not public.is_staff() then
    raise exception 'You are not allowed to update this incident.' using errcode = '42501';
  end if;
  select * into incident from public.incidents i where i.id = p_incident_id
    and private.can_view_personnel(i.user_id,i.organization_id) for update;
  if not found then
    raise exception 'Incident not found or no longer accessible.' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('open','acknowledged','resolved') then
    raise exception 'Invalid incident status.';
  end if;
  if char_length(trim(coalesce(p_status_note,''))) > 500 then
    raise exception 'Incident status note cannot exceed 500 characters.';
  end if;
  if p_status = 'resolved' then
    if char_length(trim(coalesce(p_status_note,''))) < 5 then
      raise exception 'Add a resolution note of at least 5 characters before closing an incident.';
    end if;
    if incident.filed_at is null or incident.captured_at is null
      or (incident.video_path is not null and (incident.video_duration_seconds is null
        or incident.video_duration_seconds not between 1 and 15)) then
      raise exception 'The guard must file a timestamped incident report before it can be resolved.';
    end if;
  end if;
  update public.incidents set status = p_status, status_note = trim(coalesce(p_status_note,'')),
    updated_at = now(), updated_by = auth.uid() where id = incident.id;
end;
$$;
revoke all on function public.update_incident_status(uuid,text,text) from public,anon;
grant execute on function public.update_incident_status(uuid,text,text) to authenticated;


notify pgrst, 'reload schema';
