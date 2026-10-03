-- Inspector assignment is an authorization boundary, not only a profile label.
-- Admin retains agency-wide operations; IT Admin retains its existing privileges.
-- Private SECURITY DEFINER predicates avoid profiles/schedules/locations RLS cycles.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.can_view_personnel(p_user_id uuid, p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles actor
    left join public.organizations organization on organization.id = actor.organization_id
    where actor.id = (select auth.uid()) and actor.active
      and (
        actor.role = 'it_admin'
        or (organization.active and actor.organization_id = p_organization_id and (
          actor.id = p_user_id or actor.role = 'admin'
          or (actor.role = 'inspector' and exists (
            select 1 from public.profiles guard
            where guard.id = p_user_id and guard.role = 'user'
              and guard.organization_id = actor.organization_id and guard.inspector_id = actor.id
          ))
        ))
      )
  );
$$;

create or replace function private.can_view_deployment_site(p_location_id uuid, p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_it_admin() or (
    p_organization_id = public.current_organization_id() and public.current_organization_is_active()
    and (
      public.is_admin()
      or exists (select 1 from public.profiles guard
        where guard.assigned_location_id = p_location_id and guard.organization_id = p_organization_id
          and private.can_view_personnel(guard.id, guard.organization_id))
      or exists (select 1 from public.schedules duty
        where duty.location_id = p_location_id and duty.organization_id = p_organization_id
          and private.can_view_personnel(duty.user_id, duty.organization_id))
      or exists (select 1 from public.guard_assignment_history history
        where history.location_id = p_location_id and history.organization_id = p_organization_id
          and private.can_view_personnel(history.guard_id, history.organization_id))
    )
  );
$$;

create or replace function private.can_view_incident_video(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.incidents incident
    where incident.video_path = p_path
      and private.can_view_personnel(incident.user_id, incident.organization_id));
$$;

create or replace function private.incident_video_is_unfiled(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.incidents incident where incident.video_path = p_path);
$$;

revoke all on function private.can_view_personnel(uuid,uuid),
  private.can_view_deployment_site(uuid,uuid), private.can_view_incident_video(text),
  private.incident_video_is_unfiled(text) from public, anon;
grant execute on function private.can_view_personnel(uuid,uuid),
  private.can_view_deployment_site(uuid,uuid), private.can_view_incident_video(text),
  private.incident_video_is_unfiled(text) to authenticated;

-- Replace broad staff SELECT policies. The restrictive companion also prevents
-- any older permissive policy from granting an Inspector broader reads/writes.
do $$
declare rule record;
begin
  for rule in select * from (values
    ('profiles','tenant profile visibility','id'),
    ('schedules','tenant schedule visibility','user_id'),
    ('attendance_punches','tenant attendance visibility','user_id'),
    ('attendance_sessions','tenant attendance session visibility','user_id'),
    ('incidents','tenant incident visibility','user_id'),
    ('guard_assignment_history','tenant assignment history visibility','guard_id'),
    ('accomplishment_reports','tenant accomplishment visibility','guard_id')
  ) as rules(table_name,policy_name,person_column)
  loop
    execute format('drop policy if exists %I on public.%I',rule.policy_name,rule.table_name);
    execute format('create policy %I on public.%I for select to authenticated using (private.can_view_personnel(%I,organization_id))',
      rule.policy_name,rule.table_name,rule.person_column);
    execute format('create policy "inspector assignment boundary" on public.%I as restrictive for all to authenticated using '
      || '(public.current_role() <> ''inspector'' or private.can_view_personnel(%I,organization_id)) '
      || 'with check (public.current_role() <> ''inspector'')',rule.table_name,rule.person_column);
    execute format('create policy "inspector cannot delete personnel operations" on public.%I as restrictive for delete to authenticated '
      || 'using (public.current_role() <> ''inspector'')',rule.table_name);
  end loop;
end;
$$;

drop policy if exists "tenant location visibility" on public.locations;
create policy "tenant location visibility" on public.locations for select to authenticated
using (private.can_view_deployment_site(id,organization_id));
create policy "inspector assignment boundary" on public.locations as restrictive for all to authenticated
using (public.current_role() <> 'inspector' or private.can_view_deployment_site(id,organization_id))
with check (public.current_role() <> 'inspector');
create policy "inspector cannot delete personnel operations" on public.locations as restrictive for delete to authenticated
using (public.current_role() <> 'inspector');

-- Absence/swap letters are private Guard-to-Admin correspondence. A legacy
-- inspector_id on the request does not grant access or approval authority.
drop policy if exists "tenant swap request visibility" on public.shift_swap_requests;
create policy "tenant swap request visibility" on public.shift_swap_requests for select to authenticated
using (public.is_it_admin() or (organization_id = public.current_organization_id()
  and public.current_organization_is_active() and (requester_id = (select auth.uid()) or public.is_admin())));
create policy "inspector requests are admin only" on public.shift_swap_requests as restrictive for all to authenticated
using (public.current_role() <> 'inspector') with check (public.current_role() <> 'inspector');

drop policy if exists "tenant incident staff reads video" on storage.objects;
create policy "tenant incident staff reads video" on storage.objects for select to authenticated
using (bucket_id = 'incident-videos' and (
  (public.is_active_duty_personnel() and (storage.foldername(name))[1] = (select auth.uid())::text)
  or public.is_it_admin() or private.can_view_incident_video(name)
));
create policy "inspector private media boundary" on storage.objects as restrictive for select to authenticated
using (public.current_role() <> 'inspector' or (bucket_id = 'incident-videos' and (
  (public.is_active_duty_personnel() and (storage.foldername(name))[1] = (select auth.uid())::text)
  or private.can_view_incident_video(name)
)));

-- Test global filing existence without RLS: a now-hidden report must never look
-- like an unfiled video that an old owner can delete.
drop policy if exists "active personnel remove own unfiled incident video" on storage.objects;
create policy "active personnel remove own unfiled incident video" on storage.objects for delete to authenticated
using (bucket_id = 'incident-videos' and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.incident_video_is_unfiled(name));

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
      or char_length(trim(incident.detailed_narrative)) < 10
      or (incident.video_path is not null and (incident.video_duration_seconds is null
        or incident.video_duration_seconds not between 1 and 15)) then
      raise exception 'The guard must file a timestamped incident report with remarks before it can be resolved.';
    end if;
  end if;
  update public.incidents set status = p_status, status_note = trim(coalesce(p_status_note,'')),
    updated_at = now(), updated_by = auth.uid() where id = incident.id;
end;
$$;
revoke all on function public.update_incident_status(uuid,text,text) from public,anon;
grant execute on function public.update_incident_status(uuid,text,text) to authenticated;

-- Existing notification payloads can contain Guard names, sites and remarks.
-- Recheck the CURRENT assignment on reads/acknowledgements, not creation alone.
create or replace function private.can_view_notification(
  p_recipient_id uuid, p_organization_id uuid, p_entity_type text, p_entity_id uuid, p_kind text
)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare actor public.profiles;
begin
  select * into actor from public.profiles where id = auth.uid() and active;
  if not found or actor.id <> p_recipient_id then return false; end if;
  if actor.role = 'it_admin' then return true; end if;
  if actor.organization_id is distinct from p_organization_id or not public.current_organization_is_active() then
    return false;
  end if;
  if actor.role <> 'inspector' then return true; end if;
  if p_entity_type in ('broadcast','platform_settings') and p_kind = 'system' then return true; end if;
  case p_entity_type
    when 'incident' then return exists (select 1 from public.incidents i where i.id = p_entity_id
      and i.organization_id = p_organization_id and private.can_view_personnel(i.user_id,i.organization_id));
    when 'profile' then return private.can_view_personnel(p_entity_id,p_organization_id);
    when 'schedule' then return exists (select 1 from public.schedules s where s.id = p_entity_id
      and s.organization_id = p_organization_id and private.can_view_personnel(s.user_id,s.organization_id));
    when 'assignment' then return exists (select 1 from public.guard_assignment_history h where h.id = p_entity_id
      and h.organization_id = p_organization_id and private.can_view_personnel(h.guard_id,h.organization_id));
    when 'accomplishment_report' then return exists (select 1 from public.accomplishment_reports r where r.id = p_entity_id
      and r.organization_id = p_organization_id and private.can_view_personnel(r.guard_id,r.organization_id));
    else return false;
  end case;
end;
$$;
revoke all on function private.can_view_notification(uuid,uuid,text,uuid,text) from public,anon;
grant execute on function private.can_view_notification(uuid,uuid,text,uuid,text) to authenticated;
drop policy if exists "users read their notifications" on public.user_notifications;
create policy "users read their notifications" on public.user_notifications for select to authenticated
using (recipient_id = (select auth.uid())
  and private.can_view_notification(recipient_id,organization_id,entity_type,entity_id,kind));

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.user_notifications set read_at = coalesce(read_at,now()) where id = p_notification_id
    and recipient_id = (select auth.uid())
    and private.can_view_notification(recipient_id,organization_id,entity_type,entity_id,kind);
  if not found then raise exception 'Notification was not found.'; end if;
end;
$$;
create or replace function public.acknowledge_notification(p_notification_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.user_notifications set read_at = coalesce(read_at,now()), acknowledged_at = coalesce(acknowledged_at,now())
  where id = p_notification_id and requires_ack
    and recipient_id = (select auth.uid())
    and private.can_view_notification(recipient_id,organization_id,entity_type,entity_id,kind);
  if not found then raise exception 'Acknowledgement-required notification was not found.'; end if;
end;
$$;
create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path = '' as $$
declare updated integer;
begin
  update public.user_notifications set read_at = now() where read_at is null and recipient_id = (select auth.uid())
    and private.can_view_notification(recipient_id,organization_id,entity_type,entity_id,kind);
  get diagnostics updated = row_count;
  return updated;
end;
$$;
revoke all on function public.mark_notification_read(uuid),public.acknowledge_notification(uuid),
  public.mark_all_notifications_read() from public,anon;
grant execute on function public.mark_notification_read(uuid),public.acknowledge_notification(uuid),
  public.mark_all_notifications_read() to authenticated;

create or replace function public.notify_incident_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient record; category text;
begin
  if tg_op = 'INSERT' then
    category := case new.category when 'crime' then 'Crime / theft' when 'fire' then 'Fire / hazard'
      when 'medical' then 'Medical emergency' when 'disturbance' then 'Disturbance' else 'Emergency' end;
    for recipient in select p.id from public.profiles p join public.organizations o on o.id = p.organization_id
      where p.active and o.active and p.organization_id = new.organization_id and (
        p.role = 'admin' or (p.role = 'inspector' and exists (select 1 from public.profiles guard
          where guard.id = new.user_id and guard.role = 'user' and guard.organization_id = new.organization_id
            and guard.inspector_id = p.id))
      )
    loop
      perform public.insert_user_notification(recipient.id,new.organization_id,'emergency','critical',
        'Emergency: ' || category,
        left(coalesce(nullif(new.guard_name,''),'Duty personnel') || ' reported an incident'
          || case when nullif(new.location_label,'') is null then '.' else ' at ' || new.location_label || '.' end
          || ' Immediate review is required.',1000),
        'emergency','incident',new.id,
        jsonb_build_object('category',new.category,'guard_name',new.guard_name,'location_label',new.location_label,'captured_at',new.captured_at),
        true,new.user_id,'incident:' || new.id::text || ':open',now() + interval '30 days');
    end loop;
  elsif new.status is distinct from old.status then
    perform public.insert_user_notification(new.user_id,new.organization_id,'incident_status',
      case when new.status = 'resolved' then 'normal' else 'high' end,
      case new.status when 'acknowledged' then 'Emergency alert acknowledged' when 'resolved' then 'Incident report resolved' else 'Incident report reopened' end,
      case new.status when 'acknowledged' then 'Your emergency alert is being reviewed by the operations team.'
        when 'resolved' then 'Your incident report was resolved.' || case when nullif(new.status_note,'') is null then '' else ' Note: ' || new.status_note end
        else 'Your incident report was reopened for further review.' end,
      'emergency','incident',new.id,jsonb_build_object('status',new.status),false,new.updated_by,
      'incident:' || new.id::text || ':status:' || new.status,now() + interval '90 days');
  end if;
  return new;
end;
$$;
revoke all on function public.notify_incident_event() from public,anon,authenticated;

-- Keep the existing Guard notification and add a separate Inspector inbox item.
-- A unique timestamp + transaction id permits legitimate reassignment cycles.
create or replace function public.notify_new_guard_inspector()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'user' and new.inspector_id is not null and (
    tg_op = 'INSERT' or new.inspector_id is distinct from old.inspector_id
  ) and exists (select 1 from public.profiles p join public.organizations o on o.id = p.organization_id
    where p.id = new.inspector_id and p.role = 'inspector' and p.active and o.active
      and p.organization_id = new.organization_id) then
    perform public.insert_user_notification(new.inspector_id,new.organization_id,'assignment','normal',
      'Guard assigned to you',
      coalesce(nullif(trim(concat_ws(' ',new.first_name,new.last_name)),''),nullif(new.username,''),'A Guard')
        || ' is now assigned to you. Review My Guards, duty schedules and incident reports.',
      'personnel','profile',new.id,jsonb_build_object('guard_id',new.id,'inspector_id',new.inspector_id),
      false,auth.uid(),'inspector-assignment:' || new.id::text || ':' || new.inspector_id::text || ':' || txid_current()::text,
      now() + interval '180 days');
  end if;
  return new;
end;
$$;
revoke all on function public.notify_new_guard_inspector() from public,anon,authenticated;
create trigger notify_new_guard_inspector after insert or update of inspector_id on public.profiles
for each row execute function public.notify_new_guard_inspector();

notify pgrst, 'reload schema';
