-- Sentinel Link notification inbox and realtime delivery.
-- Operational alerts remain inside the beneficiary organization. IT Admin can
-- send platform notices, but is not made part of day-to-day emergency routing.

create table public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  kind text not null check (kind in (
    'emergency', 'incident_status', 'schedule', 'assignment', 'shift_request',
    'accomplishment', 'account', 'system'
  )),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'critical')),
  title text not null check (char_length(trim(title)) between 3 and 120),
  message text not null check (char_length(trim(message)) between 3 and 1000),
  action_key text check (action_key is null or action_key in (
    'emergency', 'schedule', 'personnel', 'shift_request', 'accomplishment', 'system'
  )),
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  requires_ack boolean not null default false,
  read_at timestamptz,
  acknowledged_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  expires_at timestamptz,
  dedupe_key text,
  check (priority <> 'critical' or requires_ack),
  check (acknowledged_at is null or requires_ack),
  check (expires_at is null or expires_at > created_at)
);

create index user_notifications_recipient_created_idx
  on public.user_notifications (recipient_id, created_at desc);
create index user_notifications_recipient_unread_idx
  on public.user_notifications (recipient_id, created_at desc)
  where read_at is null;
create index user_notifications_recipient_unacknowledged_idx
  on public.user_notifications (recipient_id, created_at desc)
  where requires_ack and acknowledged_at is null;
create unique index user_notifications_recipient_dedupe_idx
  on public.user_notifications (recipient_id, dedupe_key)
  where dedupe_key is not null;

alter table public.user_notifications enable row level security;

create policy "users read their notifications"
on public.user_notifications
for select
to authenticated
using (recipient_id = (select auth.uid()));

revoke all on public.user_notifications from anon, authenticated;
grant select on public.user_notifications to authenticated;

-- This primitive is trigger-only. Client callers use the constrained broadcast
-- and acknowledgement functions below.
create or replace function public.insert_user_notification(
  p_recipient_id uuid,
  p_organization_id uuid,
  p_kind text,
  p_priority text,
  p_title text,
  p_message text,
  p_action_key text default null,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_requires_ack boolean default false,
  p_created_by uuid default null,
  p_dedupe_key text default null,
  p_expires_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = p_recipient_id
      and profile.active
      and (p_organization_id is null or profile.organization_id = p_organization_id)
  ) then
    return;
  end if;

  insert into public.user_notifications (
    recipient_id, organization_id, kind, priority, title, message,
    action_key, entity_type, entity_id, metadata, requires_ack,
    created_by, dedupe_key, expires_at
  ) values (
    p_recipient_id,
    p_organization_id,
    p_kind,
    p_priority,
    left(trim(p_title), 120),
    left(trim(p_message), 1000),
    p_action_key,
    nullif(left(trim(coalesce(p_entity_type, '')), 80), ''),
    p_entity_id,
    coalesce(p_metadata, '{}'::jsonb),
    p_requires_ack or p_priority = 'critical',
    p_created_by,
    nullif(left(trim(coalesce(p_dedupe_key, '')), 240), ''),
    p_expires_at
  )
  on conflict (recipient_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

revoke all on function public.insert_user_notification(
  uuid, uuid, text, text, text, text, text, text, uuid, jsonb,
  boolean, uuid, text, timestamptz
) from public, anon, authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_id = auth.uid();
  if not found then
    raise exception 'Notification was not found.';
  end if;
end;
$$;

create or replace function public.acknowledge_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notifications
  set read_at = coalesce(read_at, now()),
      acknowledged_at = coalesce(acknowledged_at, now())
  where id = p_notification_id
    and recipient_id = auth.uid()
    and requires_ack;
  if not found then
    raise exception 'Acknowledgement-required notification was not found.';
  end if;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  update public.user_notifications
  set read_at = now()
  where recipient_id = auth.uid()
    and read_at is null;
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

-- HR / Operations can notify its own field personnel. IT Admin can publish a
-- platform maintenance notice. No role can address arbitrary user IDs.
create or replace function public.send_broadcast_notification(
  p_audience text,
  p_title text,
  p_message text,
  p_priority text default 'normal',
  p_requires_ack boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender public.profiles%rowtype;
  v_recipient record;
  v_count integer := 0;
  v_organization_id uuid;
  v_title text := trim(coalesce(p_title, ''));
  v_message text := trim(coalesce(p_message, ''));
begin
  select * into v_sender
  from public.profiles
  where id = auth.uid() and active;
  if not found or v_sender.role not in ('it_admin', 'admin') then
    raise exception 'Only IT Admin or HR / Operations Head can send notices.';
  end if;
  if char_length(v_title) not between 3 and 120 then
    raise exception 'Notification title must contain 3 to 120 characters.';
  end if;
  if char_length(v_message) not between 5 and 1000 then
    raise exception 'Notification message must contain 5 to 1,000 characters.';
  end if;
  if p_priority not in ('low', 'normal', 'high', 'critical') then
    raise exception 'Choose a valid notification priority.';
  end if;

  if v_sender.role = 'it_admin' then
    if p_audience not in ('platform_admins', 'operations_heads', 'all') then
      raise exception 'Choose Platform admins, HR / Operations Heads, or Everyone.';
    end if;
    for v_recipient in
      select profile.id, profile.organization_id
      from public.profiles profile
      where profile.active
        and profile.id <> auth.uid()
        and (
          (p_audience = 'platform_admins' and profile.role = 'it_admin')
          or (p_audience = 'operations_heads' and profile.role = 'admin')
          or p_audience = 'all'
        )
    loop
      perform public.insert_user_notification(
        v_recipient.id, v_recipient.organization_id, 'system', p_priority,
        v_title, v_message, 'system', 'broadcast', null,
        jsonb_build_object('audience', p_audience, 'sender_role', 'it_admin'),
        p_requires_ack, auth.uid(), null, now() + interval '90 days'
      );
      v_count := v_count + 1;
    end loop;
  else
    v_organization_id := public.current_organization_id();
    if v_organization_id is null or not public.current_organization_is_active() then
      raise exception 'Your beneficiary workspace is not active.';
    end if;
    if p_audience not in ('guards', 'inspectors', 'field', 'organization') then
      raise exception 'Choose Guards, Inspectors, Field personnel, or Entire organization.';
    end if;
    for v_recipient in
      select profile.id
      from public.profiles profile
      where profile.active
        and profile.organization_id = v_organization_id
        and profile.id <> auth.uid()
        and (
          (p_audience = 'guards' and profile.role = 'user')
          or (p_audience = 'inspectors' and profile.role = 'inspector')
          or (p_audience = 'field' and profile.role in ('user', 'inspector'))
          or p_audience = 'organization'
        )
    loop
      perform public.insert_user_notification(
        v_recipient.id, v_organization_id, 'system', p_priority,
        v_title, v_message, 'system', 'broadcast', null,
        jsonb_build_object('audience', p_audience, 'sender_role', 'admin'),
        p_requires_ack, auth.uid(), null, now() + interval '90 days'
      );
      v_count := v_count + 1;
    end loop;
  end if;

  return v_count;
end;
$$;

grant execute on function public.mark_notification_read(uuid),
  public.acknowledge_notification(uuid),
  public.mark_all_notifications_read(),
  public.send_broadcast_notification(text, text, text, text, boolean)
to authenticated;

create or replace function public.notify_incident_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
  v_category text;
begin
  if tg_op = 'INSERT' then
    v_category := case new.category
      when 'crime' then 'Crime / theft'
      when 'fire' then 'Fire / hazard'
      when 'medical' then 'Medical emergency'
      when 'disturbance' then 'Disturbance'
      else 'Emergency'
    end;
    for v_recipient in
      select profile.id
      from public.profiles profile
      where profile.active
        and profile.organization_id = new.organization_id
        and profile.role in ('admin', 'inspector')
    loop
      perform public.insert_user_notification(
        v_recipient.id,
        new.organization_id,
        'emergency',
        'critical',
        'Emergency: ' || v_category,
        left(coalesce(nullif(new.guard_name, ''), 'Duty personnel') ||
          ' reported an incident' ||
          case when nullif(new.location_label, '') is null then '.' else ' at ' || new.location_label || '.' end ||
          ' Immediate review is required.', 1000),
        'emergency',
        'incident',
        new.id,
        jsonb_build_object(
          'category', new.category,
          'guard_name', new.guard_name,
          'location_label', new.location_label,
          'captured_at', new.captured_at
        ),
        true,
        new.user_id,
        'incident:' || new.id::text || ':open',
        now() + interval '30 days'
      );
    end loop;
  elsif new.status is distinct from old.status then
    perform public.insert_user_notification(
      new.user_id,
      new.organization_id,
      'incident_status',
      case when new.status = 'resolved' then 'normal' else 'high' end,
      case new.status
        when 'acknowledged' then 'Emergency alert acknowledged'
        when 'resolved' then 'Incident report resolved'
        else 'Incident report reopened'
      end,
      case new.status
        when 'acknowledged' then 'Your emergency alert is being reviewed by the operations team.'
        when 'resolved' then 'Your incident report was resolved.' || case when nullif(new.status_note, '') is null then '' else ' Note: ' || new.status_note end
        else 'Your incident report was reopened for further review.'
      end,
      'emergency',
      'incident',
      new.id,
      jsonb_build_object('status', new.status),
      false,
      new.updated_by,
      'incident:' || new.id::text || ':status:' || new.status,
      now() + interval '90 days'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_incident_event on public.incidents;
create trigger notify_incident_event
after insert or update of status on public.incidents
for each row execute function public.notify_incident_event();

create or replace function public.notify_schedule_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message text;
  v_dedupe text;
begin
  if tg_op = 'UPDATE' and new.user_id is distinct from old.user_id then
    perform public.insert_user_notification(
      old.user_id, old.organization_id, 'schedule', 'high',
      'Duty schedule reassigned',
      'A duty previously assigned to you was reassigned. Review your current schedule.',
      'schedule', 'schedule', old.id, '{}'::jsonb, false, auth.uid(),
      'schedule:' || old.id::text || ':removed:' || old.user_id::text,
      now() + interval '90 days'
    );
  end if;

  if new.approval_status not in ('approved', 'changed', 'cancelled') then
    return new;
  end if;
  if tg_op = 'UPDATE' and not (
    new.user_id is distinct from old.user_id
    or new.location_id is distinct from old.location_id
    or new.location_label is distinct from old.location_label
    or new.start_at is distinct from old.start_at
    or new.end_at is distinct from old.end_at
    or new.approval_status is distinct from old.approval_status
  ) then
    return new;
  end if;

  v_message := case when new.approval_status = 'cancelled'
    then 'Your duty at ' || coalesce(nullif(new.location_label, ''), 'the assigned post') || ' was cancelled.'
    else 'Duty at ' || coalesce(nullif(new.location_label, ''), 'your assigned post') ||
      ' starts ' || to_char(new.start_at at time zone 'Asia/Manila', 'Mon DD, YYYY at HH12:MI AM') ||
      ' and ends ' || to_char(new.end_at at time zone 'Asia/Manila', 'Mon DD, YYYY at HH12:MI AM') || '.'
  end;
  v_dedupe := 'schedule:' || new.id::text || ':' || md5(concat_ws('|',
    new.user_id::text, coalesce(new.location_id::text, ''), coalesce(new.location_label, ''),
    new.start_at::text, new.end_at::text, new.approval_status
  ));

  perform public.insert_user_notification(
    new.user_id, new.organization_id, 'schedule',
    case when new.approval_status = 'cancelled' then 'high' else 'normal' end,
    case
      when new.approval_status = 'cancelled' then 'Duty schedule cancelled'
      when tg_op = 'INSERT' then 'New duty schedule'
      else 'Duty schedule updated'
    end,
    v_message,
    'schedule', 'schedule', new.id,
    jsonb_build_object('start_at', new.start_at, 'end_at', new.end_at, 'status', new.approval_status),
    false, auth.uid(), v_dedupe, new.end_at + interval '30 days'
  );
  return new;
end;
$$;

drop trigger if exists notify_schedule_event on public.schedules;
create trigger notify_schedule_event
after insert or update of user_id, location_id, location_label, start_at, end_at, approval_status
on public.schedules
for each row execute function public.notify_schedule_event();

create or replace function public.notify_assignment_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_location_label text;
begin
  select location.label into v_location_label
  from public.locations location
  where location.id = new.location_id;

  perform public.insert_user_notification(
    new.guard_id, new.organization_id, 'assignment', 'high',
    'Deployment post updated',
    'Your home post is now ' || coalesce(v_location_label, 'unassigned') || '.' ||
      case when nullif(trim(new.remarks), '') is null then '' else ' Remarks: ' || trim(new.remarks) end,
    'personnel', 'assignment', new.id,
    jsonb_build_object('location_id', new.location_id, 'location_label', v_location_label),
    false, new.assigned_by, 'assignment:' || new.id::text, now() + interval '180 days'
  );
  return new;
end;
$$;

drop trigger if exists notify_assignment_event on public.guard_assignment_history;
create trigger notify_assignment_event
after insert on public.guard_assignment_history
for each row execute function public.notify_assignment_event();

create or replace function public.notify_profile_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspector_name text;
begin
  if new.role <> 'user' or not new.active then
    return new;
  end if;

  if new.active is distinct from old.active and new.active then
    perform public.insert_user_notification(
      new.id, new.organization_id, 'account', 'high', 'Account reactivated',
      'Your Guard account is active again. You can resume using Sentinel Link.',
      'personnel', 'profile', new.id, '{}'::jsonb, false, auth.uid(),
      'profile:' || new.id::text || ':reactivated:' || extract(epoch from now())::bigint::text,
      now() + interval '90 days'
    );
  end if;

  if new.employment_category is distinct from old.employment_category then
    perform public.insert_user_notification(
      new.id, new.organization_id, 'account', 'normal', 'Duty category updated',
      'Your duty category is now ' || initcap(new.employment_category) || '.',
      'personnel', 'profile', new.id,
      jsonb_build_object('employment_category', new.employment_category), false, auth.uid(),
      'profile:' || new.id::text || ':category:' || new.employment_category,
      now() + interval '180 days'
    );
  end if;

  if new.inspector_id is distinct from old.inspector_id then
    select coalesce(
      nullif(trim(concat_ws(' ', inspector.first_name, inspector.last_name)), ''),
      nullif(inspector.username, ''),
      'an Inspector'
    ) into v_inspector_name
    from public.profiles inspector
    where inspector.id = new.inspector_id;
    perform public.insert_user_notification(
      new.id, new.organization_id, 'assignment', 'normal', 'Inspector assignment updated',
      case when new.inspector_id is null
        then 'You currently have no assigned Inspector. Contact HR / Operations if this is unexpected.'
        else v_inspector_name || ' is now your assigned Inspector.'
      end,
      'personnel', 'profile', new.id,
      jsonb_build_object('inspector_id', new.inspector_id, 'inspector_name', v_inspector_name),
      false, auth.uid(),
      'profile:' || new.id::text || ':inspector:' || coalesce(new.inspector_id::text, 'none') || ':' || extract(epoch from now())::bigint::text,
      now() + interval '180 days'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_profile_event on public.profiles;
create trigger notify_profile_event
after update of active, employment_category, inspector_id on public.profiles
for each row execute function public.notify_profile_event();

create or replace function public.notify_shift_request_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
begin
  if tg_op = 'INSERT' then
    perform public.insert_user_notification(
      new.inspector_id, new.organization_id, 'shift_request', 'high',
      'Shift-change request needs review',
      'A Guard submitted a shift-change request. Review it before HR / Operations approval.',
      'shift_request', 'shift_swap_request', new.id,
      jsonb_build_object('requester_id', new.requester_id, 'status', new.status),
      false, new.requester_id, 'shift-request:' || new.id::text || ':inspector',
      now() + interval '90 days'
    );
    perform public.insert_user_notification(
      new.requester_id, new.organization_id, 'shift_request', 'normal',
      'Shift-change request submitted',
      'Your request was sent to your Inspector for review.',
      'shift_request', 'shift_swap_request', new.id,
      jsonb_build_object('status', new.status), false, new.requester_id,
      'shift-request:' || new.id::text || ':submitted', now() + interval '90 days'
    );
  elsif new.status is distinct from old.status then
    if new.status = 'pending_admin' then
      for v_recipient in
        select profile.id
        from public.profiles profile
        where profile.active
          and profile.organization_id = new.organization_id
          and profile.role = 'admin'
      loop
        perform public.insert_user_notification(
          v_recipient.id, new.organization_id, 'shift_request', 'high',
          'Shift change awaiting approval',
          'An Inspector-approved shift change needs final HR / Operations review.',
          'shift_request', 'shift_swap_request', new.id,
          jsonb_build_object('requester_id', new.requester_id, 'status', new.status),
          false, new.inspector_decision_by,
          'shift-request:' || new.id::text || ':admin', now() + interval '90 days'
        );
      end loop;
      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request', 'normal',
        'Inspector approved your request',
        'Your shift-change request is awaiting final HR / Operations approval.',
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', new.status), false, new.inspector_decision_by,
        'shift-request:' || new.id::text || ':pending-admin', now() + interval '90 days'
      );
    elsif new.status in ('approved', 'rejected', 'cancelled') then
      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request',
        case when new.status = 'approved' then 'high' else 'normal' end,
        case new.status
          when 'approved' then 'Shift change approved'
          when 'rejected' then 'Shift change not approved'
          else 'Shift-change request cancelled'
        end,
        case new.status
          when 'approved' then 'Your approved schedule has been updated. Review your duty schedule.'
          when 'rejected' then 'Your shift-change request was not approved.' || case when nullif(new.admin_note, '') is null then '' else ' Note: ' || new.admin_note end
          else 'Your shift-change request was cancelled.'
        end,
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', new.status), false, new.admin_decision_by,
        'shift-request:' || new.id::text || ':decision:' || new.status,
        now() + interval '180 days'
      );
      if new.status = 'approved' and new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
        perform public.insert_user_notification(
          new.target_guard_id, new.organization_id, 'schedule', 'high',
          'Duty assigned through shift change',
          'An approved shift change assigned a duty to you. Review your schedule now.',
          'schedule', 'shift_swap_request', new.id,
          jsonb_build_object('status', new.status, 'schedule_id', new.requested_schedule_id),
          false, new.admin_decision_by,
          'shift-request:' || new.id::text || ':target-approved', now() + interval '180 days'
        );
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists notify_shift_request_event on public.shift_swap_requests;
create trigger notify_shift_request_event
after insert or update of status on public.shift_swap_requests
for each row execute function public.notify_shift_request_event();

create or replace function public.notify_accomplishment_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
begin
  if tg_op = 'INSERT' then
    for v_recipient in
      select profile.id
      from public.profiles profile
      where profile.active
        and profile.organization_id = new.organization_id
        and profile.role = 'admin'
    loop
      perform public.insert_user_notification(
        v_recipient.id, new.organization_id, 'accomplishment', 'normal',
        'New accomplishment report',
        'A Guard submitted an accomplishment report for review.',
        'accomplishment', 'accomplishment_report', new.id,
        jsonb_build_object('guard_id', new.guard_id, 'review_status', new.review_status),
        false, new.guard_id, 'accomplishment:' || new.id::text || ':submitted',
        now() + interval '180 days'
      );
    end loop;
  elsif new.review_status is distinct from old.review_status then
    perform public.insert_user_notification(
      new.guard_id, new.organization_id, 'accomplishment',
      case when new.review_status = 'needs_follow_up' then 'high' else 'normal' end,
      case when new.review_status = 'needs_follow_up'
        then 'Accomplishment report needs follow-up'
        else 'Accomplishment report reviewed'
      end,
      case when new.review_status = 'needs_follow_up'
        then 'HR / Operations requested follow-up.' || case when nullif(new.review_note, '') is null then '' else ' Note: ' || new.review_note end
        else 'HR / Operations reviewed your accomplishment report.'
      end,
      'accomplishment', 'accomplishment_report', new.id,
      jsonb_build_object('review_status', new.review_status), false, new.reviewed_by,
      'accomplishment:' || new.id::text || ':review:' || new.review_status,
      now() + interval '180 days'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_accomplishment_event on public.accomplishment_reports;
create trigger notify_accomplishment_event
after insert or update of review_status on public.accomplishment_reports
for each row execute function public.notify_accomplishment_event();

create or replace function public.notify_platform_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
begin
  if new.portal_announcement_enabled
    and nullif(trim(new.portal_announcement), '') is not null
    and (
      new.portal_announcement_enabled is distinct from old.portal_announcement_enabled
      or new.portal_announcement is distinct from old.portal_announcement
    ) then
    for v_recipient in
      select profile.id, profile.organization_id
      from public.profiles profile
      where profile.active and profile.id <> coalesce(new.updated_by, gen_random_uuid())
    loop
      perform public.insert_user_notification(
        v_recipient.id, v_recipient.organization_id, 'system', 'normal',
        'Platform announcement', new.portal_announcement,
        'system', 'platform_settings', null,
        jsonb_build_object('published_at', new.updated_at), false, new.updated_by,
        'platform-announcement:' || md5(new.portal_announcement || new.updated_at::text),
        now() + interval '30 days'
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists notify_platform_announcement on public.platform_settings;
create trigger notify_platform_announcement
after update of portal_announcement, portal_announcement_enabled on public.platform_settings
for each row execute function public.notify_platform_announcement();

alter publication supabase_realtime add table public.user_notifications;

