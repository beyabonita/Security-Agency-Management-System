-- Private request letters; new requests go straight to HR / Operations.
alter table public.shift_swap_requests
  add column request_type text not null default 'swap' check (request_type in ('swap', 'absence')),
  add column letter_path text,
  add column letter_name text;
create unique index shift_request_letter_unique on public.shift_swap_requests(letter_path) where letter_path is not null;
alter table public.shift_swap_requests alter column status set default 'pending_admin';

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('request-letters', 'request-letters', false, 5242880, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

-- No UPDATE policy: a letter cannot be replaced after HR reviews it.
create policy "guards upload private request letters" on storage.objects for insert to authenticated
with check (bucket_id = 'request-letters' and public.is_active_guard()
  and public.current_organization_id() is not null
  and name ~ ('^' || auth.uid()::text || '/[A-Za-z0-9-]+\.(pdf|jpg|png)$'));
create policy "owners and HR read request letters" on storage.objects for select to authenticated
using (bucket_id = 'request-letters' and (
  (public.is_active_guard() and (storage.foldername(name))[1] = auth.uid()::text)
  or (public.is_admin() and exists (select 1 from public.shift_swap_requests r
    where r.letter_path = storage.objects.name and r.organization_id = public.current_organization_id()))
));
create policy "guards remove only unsubmitted letters" on storage.objects for delete to authenticated
using (bucket_id = 'request-letters' and public.is_active_guard()
  and (storage.foldername(name))[1] = auth.uid()::text
  and not exists (select 1 from public.shift_swap_requests r where r.letter_path = storage.objects.name));

create or replace function public.submit_duty_request(
  p_schedule_id uuid, p_request_type text, p_reason text, p_letter_path text, p_letter_name text
) returns public.shift_swap_requests
language plpgsql security definer set search_path = public as $$
declare
  r public.shift_swap_requests;
  s public.schedules;
  v_org uuid := public.current_organization_id();
begin
  if not public.is_active_guard() or v_org is null then
    raise exception 'Only an active Guard can submit a duty request.' using errcode = '42501';
  end if;
  if p_request_type is null or p_request_type not in ('swap','absence') then
    raise exception 'Choose Swap or Absence.';
  end if;
  if char_length(trim(coalesce(p_reason,''))) not between 5 and 1500 then
    raise exception 'Enter a reason between 5 and 1500 characters.';
  end if;
  if char_length(trim(coalesce(p_letter_name,''))) not between 1 and 180
    or p_letter_name ~ '[[:cntrl:]/\\]' then
    raise exception 'Choose a letter with a valid filename (maximum 180 characters).';
  end if;
  -- Idempotent retry after a lost response. Do not create duplicate letters or approvals.
  select * into r from public.shift_swap_requests
    where letter_path = p_letter_path and requester_id = auth.uid() and organization_id = v_org;
  if found then
    if r.requested_schedule_id <> p_schedule_id or r.request_type <> p_request_type
      or r.reason <> trim(p_reason) then
      raise exception 'This letter is already filed with another request. Refresh your requests.';
    end if;
    return r;
  end if;
  select * into s from public.schedules where id = p_schedule_id and user_id = auth.uid()
    and organization_id = v_org for update;
  if not found or s.end_at <= now() or s.approval_status not in ('approved','changed')
    or s.marked_done or s.completed_at is not null then
    raise exception 'Choose an active upcoming or ongoing duty.';
  end if;
  if exists (select 1 from public.attendance_sessions where schedule_id = s.id) then
    raise exception 'This duty already has attendance. Contact HR for a correction.';
  end if;
  if exists (select 1 from public.shift_swap_requests where requested_schedule_id = s.id
    and status in ('pending_admin','pending_inspector')) then
    raise exception 'This duty already has a request awaiting HR approval.';
  end if;
  if p_letter_path is null or p_letter_path !~ ('^' || auth.uid()::text || '/[A-Za-z0-9-]+\.(pdf|jpg|png)$')
    or not exists (select 1 from storage.objects o where o.bucket_id = 'request-letters' and o.name = p_letter_path
      and (o.metadata->>'size')::bigint between 1 and 5242880
      and o.metadata->>'mimetype' = case when p_letter_path like '%.pdf' then 'application/pdf'
        when p_letter_path like '%.jpg' then 'image/jpeg' else 'image/png' end) then
    raise exception 'Attach a PDF, JPG or PNG letter (up to 5 MB) before submitting.';
  end if;
  insert into public.shift_swap_requests(requester_id, requested_schedule_id, reason,
    organization_id, request_type, letter_path, letter_name, status)
  values(auth.uid(), s.id, trim(p_reason), v_org, p_request_type, p_letter_path, trim(p_letter_name), 'pending_admin')
  returning * into r;
  return r;
end;
$$;

-- Old app versions must update rather than bypass the required attachment.
create or replace function public.request_shift_swap(p_schedule_id uuid, p_target_guard_id uuid default null,
  p_requested_start_at timestamptz default null, p_requested_end_at timestamptz default null, p_reason text default '')
returns public.shift_swap_requests language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Update the Guard app to submit a Swap or Absence request with a letter directly to HR.';
end;
$$;

create or replace function public.review_shift_swap_by_inspector(p_request_id uuid, p_approve boolean, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Duty requests now go directly to HR / Operations for approval.' using errcode = '42501';
end;
$$;

create or replace function public.decide_duty_request(p_request_id uuid, p_approve boolean,
  p_note text default '', p_replacement_guard_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r public.shift_swap_requests;
  s public.schedules;
  v_guard uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_category text;
begin
  if not public.is_admin() or public.current_organization_id() is null then
    raise exception 'Only HR / Operations can decide duty requests.' using errcode = '42501';
  end if;
  if p_approve is null or char_length(trim(coalesce(p_note,''))) > 1500 then
    raise exception 'Choose a decision and keep the note within 1500 characters.';
  end if;
  if not p_approve and char_length(trim(coalesce(p_note,''))) < 5 then
    raise exception 'Explain the rejection in at least 5 characters.';
  end if;
  select * into r from public.shift_swap_requests where id = p_request_id
    and organization_id = public.current_organization_id() and status = 'pending_admin' for update;
  if not found then raise exception 'This request is no longer awaiting HR approval.'; end if;
  if p_approve then
    select * into s from public.schedules where id = r.requested_schedule_id
      and organization_id = r.organization_id and user_id = r.requester_id for update;
    if not found or s.end_at <= now() or s.approval_status not in ('approved','changed')
      or s.marked_done or s.completed_at is not null then
      raise exception 'This duty has changed or ended. Reject the request and ask the Guard to submit again.';
    end if;
    if exists (select 1 from public.attendance_sessions where schedule_id = s.id)
      or exists (select 1 from public.accomplishment_reports where schedule_id = s.id) then
      raise exception 'This duty has attendance or a report and cannot be changed by a request.';
    end if;
    if r.request_type = 'absence' then
      -- Keep the schedule and request as the approved-absence audit trail. No duty hours are invented.
      update public.schedules set approval_status = 'cancelled', approved_by = auth.uid() where id = s.id;
    else
      v_guard := coalesce(p_replacement_guard_id, r.target_guard_id);
      -- Existing date-change requests remain reviewable. New letter requests require HR to select coverage.
      if v_guard is null and r.letter_path is null and r.requested_start_at is not null then v_guard := r.requester_id; end if;
      if v_guard is null or (r.letter_path is not null and v_guard = r.requester_id) then
        raise exception 'Choose a different Guard to cover this duty before approving the swap.';
      end if;
      select employment_category into v_category from public.profiles where id = v_guard and active and role = 'user'
        and organization_id = r.organization_id for update;
      if not found then raise exception 'The replacement Guard must be active in your agency.'; end if;
      v_start := coalesce(r.requested_start_at, s.start_at);
      v_end := coalesce(r.requested_end_at, s.end_at);
      if v_end <= v_start or v_end <= now() then raise exception 'The requested duty period is invalid.'; end if;
      if exists (select 1 from public.schedules where user_id = v_guard and id <> s.id
        and organization_id = r.organization_id and approval_status in ('approved','changed')
        and start_at < v_end and end_at > v_start) then
        raise exception 'The replacement Guard already has an overlapping duty.';
      end if;
      update public.schedules set user_id = v_guard, start_at = v_start, end_at = v_end,
        duty_category = v_category, approval_status = 'changed', approved_by = auth.uid() where id = s.id;
    end if;
  end if;
  update public.shift_swap_requests set status = case when p_approve then 'approved' else 'rejected' end,
    target_guard_id = case when p_approve and r.request_type = 'swap' then v_guard else target_guard_id end,
    admin_decision_by = auth.uid(), admin_decision_at = now(), admin_note = trim(coalesce(p_note,'')), updated_at = now()
  where id = r.id;
end;
$$;

create or replace function public.decide_shift_swap_by_admin(p_request_id uuid, p_approve boolean, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin perform public.decide_duty_request(p_request_id, p_approve, p_note); end;
$$;

create or replace function public.notify_shift_request_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient record; v_title text := case when new.request_type = 'absence' then 'Absence request' else 'Swap request' end;
begin
  if new.status = 'pending_admin' and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    for v_recipient in select id from public.profiles where active and role = 'admin' and organization_id = new.organization_id loop
      perform public.insert_user_notification(v_recipient.id, new.organization_id, 'shift_request', 'high',
        v_title || ' awaiting approval', 'Review the Guard''s request and attached letter.',
        'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status,'request_type',new.request_type),
        false, new.requester_id, 'shift-request:' || new.id::text || ':admin', now() + interval '90 days');
    end loop;
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'normal',
      v_title || ' submitted', 'Your request was sent directly to HR / Operations for approval.',
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.requester_id,
      'shift-request:' || new.id::text || ':direct-submitted', now() + interval '90 days');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('approved','rejected','cancelled') then
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'high',
      v_title || ' ' || new.status,
      left('HR / Operations ' || new.status || ' your request.' || case when nullif(new.admin_note,'') is null then '' else ' ' || new.admin_note end, 1000),
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.admin_decision_by,
      'shift-request:' || new.id::text || ':decision:' || new.status, now() + interval '180 days');
    if new.status = 'approved' and new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
      perform public.insert_user_notification(new.target_guard_id, new.organization_id, 'schedule', 'high',
        'Duty assigned through an approved swap', 'HR assigned you a duty. Check your schedule.',
        'schedule', 'shift_swap_request', new.id, jsonb_build_object('schedule_id',new.requested_schedule_id), false,
        new.admin_decision_by, 'shift-request:' || new.id::text || ':target-approved', now() + interval '180 days');
    end if;
  end if;
  return new;
end;
$$;

-- Preserve existing requests while removing the extra approval step.
update public.shift_swap_requests set status = 'pending_admin', updated_at = now() where status = 'pending_inspector';
delete from public.user_notifications notification
using public.shift_swap_requests request
where notification.entity_type = 'shift_swap_request'
  and notification.entity_id = request.id
  and request.status = 'pending_admin'
  and notification.dedupe_key in (
    'shift-request:' || request.id::text || ':inspector',
    'shift-request:' || request.id::text || ':submitted'
  );

-- Serialize Time In with request approval. A stale attendance selection cannot
-- clock into a duty that HR has just cancelled or assigned to another Guard.
create or replace function public.check_session_schedule_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare s public.schedules;
begin
  select * into s from public.schedules where id = new.schedule_id for update;
  if not found or s.organization_id <> new.organization_id or s.user_id <> new.user_id
    or s.approval_status not in ('approved','changed') then
    raise exception 'Your duty assignment has changed. Refresh your schedule before Time In.';
  end if;
  return new;
end;
$$;
revoke all on function public.check_session_schedule_before_insert() from public, anon, authenticated;
create trigger check_session_schedule_before_insert before insert on public.attendance_sessions
for each row execute function public.check_session_schedule_before_insert();
revoke all on function public.submit_duty_request(uuid,text,text,text,text),
  public.decide_duty_request(uuid,boolean,text,uuid) from public, anon;
grant execute on function public.submit_duty_request(uuid,text,text,text,text),
  public.decide_duty_request(uuid,boolean,text,uuid) to authenticated;
revoke all on function public.review_shift_swap_by_inspector(uuid,boolean,text) from public, anon, authenticated;
notify pgrst, 'reload schema';
