-- Update incidents table check constraint and update_incident_status function
-- to support 'under_investigation' and 'escalated' statuses alongside 'open', 'acknowledged', and 'resolved'.

alter table public.incidents
  drop constraint if exists incidents_status_check;

alter table public.incidents
  add constraint incidents_status_check check (status in ('open', 'under_investigation', 'escalated', 'acknowledged', 'resolved'));

create or replace function public.update_incident_status(
  p_incident_id uuid, p_status text, p_status_note text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  incident public.incidents;
  v_reviewer_name text;
  v_reviewer_role text;
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
  if p_status is null or p_status not in ('open','under_investigation','escalated','acknowledged','resolved') then
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
  -- Snapshot the authenticated reviewer; clients cannot supply another identity.
  select coalesce(nullif(btrim(concat_ws(' ', p.first_name, nullif(p.middle_initial, ''), p.last_name)), ''),
      nullif(p.username, ''), 'Reviewer'), p.role::text
    into v_reviewer_name, v_reviewer_role
    from public.profiles p where p.id = auth.uid();
  if not found then
    raise exception 'Reviewer profile not found.' using errcode = '42501';
  end if;
  -- An identical retry is a no-op, while a different reviewer is recorded.
  if incident.status = p_status
    and coalesce(incident.status_note, '') = trim(coalesce(p_status_note, ''))
    and incident.updated_by = auth.uid() then
    return;
  end if;
  update public.incidents set review_history = review_history || jsonb_build_array(jsonb_build_object(
      'reviewer_id', auth.uid(), 'reviewer_name', v_reviewer_name,
      'reviewer_role', v_reviewer_role, 'status', p_status,
      'note', trim(coalesce(p_status_note, '')), 'reviewed_at', now()
    )), status = p_status, status_note = trim(coalesce(p_status_note,'')),
    updated_at = now(), updated_by = auth.uid() where id = incident.id;
end;
$$;

revoke all on function public.update_incident_status(uuid,text,text) from public,anon;
grant execute on function public.update_incident_status(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
