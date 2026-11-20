-- Calendar-based shift swap with Operations-Head-first approval,
-- target guard final confirmation, automatic schedule exchange (single day or entire month),
-- and notifications to requester and Operations Head on completion.

alter table public.shift_swap_requests
  add column if not exists swap_scope text not null default 'day';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'shift_swap_requests_swap_scope_check'
      and conrelid = 'public.shift_swap_requests'::regclass
  ) then
    alter table public.shift_swap_requests
      add constraint shift_swap_requests_swap_scope_check
      check (swap_scope in ('day', 'month'));
  end if;
end $$;

-- Restrict shift swap eligibility strictly to guards assigned to the same client (location_id).
create or replace function private.duty_exchange_eligible(
  p_source uuid, p_target uuid, p_ignore_request uuid default null
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.schedules a join public.schedules b
      on b.id = p_target
     and b.organization_id = a.organization_id
     and b.user_id <> a.user_id
     and b.location_id = a.location_id
    join public.profiles pa on pa.id = a.user_id and pa.organization_id = a.organization_id and pa.active and pa.role = 'user'
    join public.profiles pb on pb.id = b.user_id and pb.organization_id = b.organization_id and pb.active and pb.role = 'user'
    join public.locations la on la.id = a.location_id and la.organization_id = a.organization_id and la.active
    where a.id = p_source and a.id <> b.id
      and a.organization_id = public.current_organization_id()
      and a.approval_status in ('approved','changed') and b.approval_status in ('approved','changed')
      and a.end_at > now() and b.end_at > now()
      and not a.marked_done and not b.marked_done and a.completed_at is null and b.completed_at is null
      and not exists (select 1 from public.attendance_sessions s where s.schedule_id in (a.id,b.id))
      and not exists (select 1 from public.accomplishment_reports r where r.schedule_id in (a.id,b.id))
      and not exists (select 1 from public.shift_swap_requests r
        where (p_ignore_request is null or r.id <> p_ignore_request)
        and r.status in ('pending_admin','pending_inspector')
        and (r.requested_schedule_id in (a.id,b.id) or r.target_schedule_id in (a.id,b.id)))
      and not exists (select 1 from public.schedules other
        where other.organization_id = a.organization_id and other.id not in (a.id,b.id)
          and other.approval_status in ('approved','changed') and (
            (other.user_id = a.user_id and (
              (other.start_at < b.end_at and other.end_at > b.start_at)
              or (other.location_id = b.location_id and coalesce(other.duty_date, (other.start_at at time zone 'Asia/Manila')::date) = coalesce(b.duty_date, (b.start_at at time zone 'Asia/Manila')::date))
            ))
            or (other.user_id = b.user_id and (
              (other.start_at < a.end_at and other.end_at > a.start_at)
              or (other.location_id = a.location_id and coalesce(other.duty_date, (other.start_at at time zone 'Asia/Manila')::date) = coalesce(a.duty_date, (a.start_at at time zone 'Asia/Manila')::date))
            ))
          ))
  );
$$;

-- Only return swap options for guards assigned to the exact same client (location_id),
-- ordered so guards scheduled on the same date appear first.
create or replace function public.available_duty_swaps(p_schedule_id uuid)
returns table(
  id uuid,
  guard_name text,
  start_at timestamptz,
  end_at timestamptz,
  location_label text,
  duty_date date,
  dtr_period text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_anchor public.schedules;
begin
  if not coalesce(public.is_active_guard(), false) or v_org is null then
    raise exception 'Only an active Guard can view swap options.' using errcode = '42501';
  end if;

  select * into v_anchor
  from public.schedules s
  where s.id = p_schedule_id
    and s.user_id = auth.uid()
    and s.organization_id = v_org;

  if not found then
    raise exception 'Choose one of your own duty periods.' using errcode = '42501';
  end if;

  return query
  select
    s.id,
    coalesce(
      nullif(trim(concat_ws(' ', nullif(p.first_name, ''), nullif(p.middle_initial, ''), nullif(p.last_name, ''))), ''),
      p.username,
      'Guard'
    ) as guard_name,
    s.start_at,
    s.end_at,
    s.location_label,
    s.duty_date,
    s.dtr_period
  from public.schedules s
  join public.profiles p on p.id = s.user_id
  where s.organization_id = v_org
    and s.user_id <> auth.uid()
    and s.location_id = v_anchor.location_id
    and s.approval_status in ('approved', 'changed')
    and s.end_at > now()
    and private.duty_exchange_eligible(p_schedule_id, s.id)
  order by
    (coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date)
      = coalesce(v_anchor.duty_date, (v_anchor.start_at at time zone 'Asia/Manila')::date)) desc,
    s.start_at,
    s.id;
end;
$$;
revoke all on function public.available_duty_swaps(uuid) from public, anon;
grant execute on function public.available_duty_swaps(uuid) to authenticated;

-- Drop legacy 5-arg overload so PostgREST resolves uniquely with optional p_swap_scope.
drop function if exists public.submit_duty_exchange(uuid, uuid, text, text, text);

create or replace function public.submit_duty_exchange(
  p_schedule_id uuid,
  p_target_schedule_id uuid,
  p_reason text,
  p_letter_path text,
  p_letter_name text,
  p_swap_scope text default 'day'
)
returns public.shift_swap_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.shift_swap_requests;
  a public.schedules;
  b public.schedules;
  v_org uuid := public.current_organization_id();
  v_source_name text;
  v_target_name text;
  v_scope text := lower(trim(coalesce(nullif(p_swap_scope, ''), 'day')));
begin
  if not coalesce(public.is_active_guard(), false) or v_org is null then
    raise exception 'Only an active Guard can submit a swap.' using errcode = '42501';
  end if;
  if v_scope not in ('day', 'month') then
    raise exception 'Choose Single Day or Entire Month swap scope.';
  end if;

  select * into r
  from public.shift_swap_requests
  where letter_path = p_letter_path
    and requester_id = auth.uid()
    and organization_id = v_org;

  if found then
    if r.requested_schedule_id is distinct from p_schedule_id
       or r.target_schedule_id is distinct from p_target_schedule_id
       or r.reason is distinct from trim(p_reason)
       or r.swap_scope is distinct from v_scope then
      raise exception 'This letter is already filed with another request.';
    end if;
    return r;
  end if;

  if char_length(trim(coalesce(p_reason, ''))) not between 5 and 1500 then
    raise exception 'Enter a reason between 5 and 1500 characters.';
  end if;
  if char_length(trim(coalesce(p_letter_name, ''))) not between 1 and 180 or p_letter_name ~ '[[:cntrl:]/\\]' then
    raise exception 'Choose a valid letter filename.';
  end if;
  if p_letter_path is null
     or p_letter_path !~ ('^' || auth.uid()::text || '/[A-Za-z0-9-]+\.(pdf|jpg|png)$')
     or not exists (
       select 1
       from storage.objects o
       where o.bucket_id = 'request-letters'
         and o.name = p_letter_path
         and (o.metadata->>'size')::bigint between 1 and 5242880
         and o.metadata->>'mimetype' = case
           when p_letter_path like '%.pdf' then 'application/pdf'
           when p_letter_path like '%.jpg' then 'image/jpeg'
           else 'image/png'
         end
     ) then
    raise exception 'Attach an owned PDF, JPG or PNG letter (up to 5 MB).';
  end if;

  perform s.id
  from public.schedules s
  where s.organization_id = v_org
    and s.id in (p_schedule_id, p_target_schedule_id)
  order by s.id
  for update;

  select * into a
  from public.schedules
  where id = p_schedule_id
    and organization_id = v_org
    and user_id = auth.uid();

  if not found then
    raise exception 'Choose one of your own duty periods.' using errcode = '42501';
  end if;

  if not private.duty_exchange_eligible(a.id, p_target_schedule_id) then
    raise exception 'These duties are no longer available for exchange. Refresh and choose another duty.';
  end if;

  select * into b from public.schedules where id = p_target_schedule_id;

  select coalesce(nullif(trim(concat_ws(' ', nullif(first_name, ''), nullif(middle_initial, ''), nullif(last_name, ''))), ''), username, 'Guard')
    into v_source_name
  from public.profiles
  where id = a.user_id;

  select coalesce(nullif(trim(concat_ws(' ', nullif(first_name, ''), nullif(middle_initial, ''), nullif(last_name, ''))), ''), username, 'Guard')
    into v_target_name
  from public.profiles
  where id = b.user_id;

  insert into public.shift_swap_requests (
    requester_id,
    requested_schedule_id,
    target_schedule_id,
    target_guard_id,
    reason,
    organization_id,
    request_type,
    swap_scope,
    letter_path,
    letter_name,
    status,
    guard_response,
    exchange_snapshot
  ) values (
    auth.uid(),
    a.id,
    b.id,
    b.user_id,
    trim(p_reason),
    v_org,
    'swap',
    v_scope,
    p_letter_path,
    trim(p_letter_name),
    'pending_admin',
    'pending',
    jsonb_build_object(
      'offered', private.duty_exchange_snapshot(a.id),
      'requested', private.duty_exchange_snapshot(b.id),
      'requester_name', v_source_name,
      'target_name', v_target_name,
      'swap_scope', v_scope
    )
  )
  returning * into r;

  return r;
end;
$$;
revoke all on function public.submit_duty_exchange(uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.submit_duty_exchange(uuid, uuid, text, text, text, text) to authenticated;

-- Atomically swaps a single pair or all remaining eligible pairs in the calendar month.
create or replace function private.execute_duty_swap_exchange(
  p_request_id uuid,
  p_approver_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.shift_swap_requests;
  a public.schedules;
  b public.schedules;
  v_key bigint;
  v_a_category text;
  v_b_category text;
  v_a_name text;
  v_b_name text;
  v_anchor_date date;
  v_month_end date;
  v_pair record;
  v_swapped_count integer := 0;
begin
  select * into r from public.shift_swap_requests where id = p_request_id for update;
  if not found or r.target_schedule_id is null then
    raise exception 'Swap request not found.';
  end if;

  for v_key in
    select distinct pg_catalog.hashtextextended(r.organization_id::text || ':' || g::text, 0)
    from unnest(array[r.requester_id, r.target_guard_id]) g
    order by 1
  loop
    perform pg_catalog.pg_advisory_xact_lock(v_key);
  end loop;

  perform p.id
  from public.profiles p
  where p.id in (r.requester_id, r.target_guard_id)
  order by p.id
  for update;

  perform s.id
  from public.schedules s
  where s.id in (r.requested_schedule_id, r.target_schedule_id)
  order by s.id
  for update;

  select * into a from public.schedules where id = r.requested_schedule_id;
  select * into b from public.schedules where id = r.target_schedule_id;

  if private.duty_exchange_snapshot(a.id) is distinct from r.exchange_snapshot->'offered'
     or private.duty_exchange_snapshot(b.id) is distinct from r.exchange_snapshot->'requested'
     or not private.duty_exchange_eligible(a.id, b.id, r.id) then
    raise exception 'A duty has changed, ended, started attendance or conflicts with another duty. Decline this request and submit a new one.';
  end if;

  select employment_category,
         coalesce(nullif(trim(concat_ws(' ', nullif(first_name, ''), nullif(middle_initial, ''), nullif(last_name, ''))), ''), username, 'Guard')
    into v_a_category, v_a_name
  from public.profiles
  where id = a.user_id;

  select employment_category,
         coalesce(nullif(trim(concat_ws(' ', nullif(first_name, ''), nullif(middle_initial, ''), nullif(last_name, ''))), ''), username, 'Guard')
    into v_b_category, v_b_name
  from public.profiles
  where id = b.user_id;

  -- Swap the primary anchor pair first.
  update public.schedules set approval_status = 'draft' where id in (a.id, b.id);
  update public.schedules set user_id = b.user_id, guard_name = v_b_name, duty_category = v_b_category where id = a.id;
  update public.schedules set user_id = a.user_id, guard_name = v_a_name, duty_category = v_a_category where id = b.id;
  update public.schedules set approval_status = 'changed', approved_by = p_approver_id where id in (a.id, b.id);
  v_swapped_count := 1;

  -- For entire-month swaps, swap all remaining eligible co-scheduled days in that same calendar month.
  if coalesce(r.swap_scope, 'day') = 'month' then
    v_anchor_date := coalesce(a.duty_date, (a.start_at at time zone 'Asia/Manila')::date);
    v_month_end := (date_trunc('month', v_anchor_date::timestamp)::date + interval '1 month - 1 day')::date;

    for v_pair in
      select distinct on (day_key)
        sa.id as sa_id,
        sb.id as sb_id
      from (
        select s.*, coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) as day_key
        from public.schedules s
        where s.organization_id = r.organization_id
          and s.user_id = a.user_id
          and s.location_id = a.location_id
          and s.id <> a.id
          and s.approval_status in ('approved', 'changed')
          and s.end_at > now()
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) > v_anchor_date
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) <= v_month_end
      ) sa
      join (
        select s.*, coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) as day_key
        from public.schedules s
        where s.organization_id = r.organization_id
          and s.user_id = b.user_id
          and s.location_id = a.location_id
          and s.id <> b.id
          and s.approval_status in ('approved', 'changed')
          and s.end_at > now()
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) > v_anchor_date
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) <= v_month_end
      ) sb on sb.day_key = sa.day_key
      order by
        day_key,
        (sa.location_id = a.location_id and sb.location_id = b.location_id) desc,
        sa.start_at,
        sb.start_at
    loop
      perform s.id
      from public.schedules s
      where s.id in (v_pair.sa_id, v_pair.sb_id)
      order by s.id
      for update;

      if private.duty_exchange_eligible(v_pair.sa_id, v_pair.sb_id, r.id) then
        update public.schedules set approval_status = 'draft' where id in (v_pair.sa_id, v_pair.sb_id);
        update public.schedules set user_id = b.user_id, guard_name = v_b_name, duty_category = v_b_category where id = v_pair.sa_id;
        update public.schedules set user_id = a.user_id, guard_name = v_a_name, duty_category = v_a_category where id = v_pair.sb_id;
        update public.schedules set approval_status = 'changed', approved_by = p_approver_id where id in (v_pair.sa_id, v_pair.sb_id);
        v_swapped_count := v_swapped_count + 1;
      end if;
    end loop;
  end if;

  return v_swapped_count;
end;
$$;
revoke all on function private.execute_duty_swap_exchange(uuid, uuid) from public, anon, authenticated;

-- Operations Head approves swap first -> forwards to Chosen Guard for confirmation.
-- If Chosen Guard had already consented (legacy requests), executes immediately.
create or replace function public.decide_duty_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default '',
  p_replacement_guard_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.shift_swap_requests;
  v_swapped integer;
begin
  if not coalesce(public.is_admin(), false) or public.current_organization_id() is null then
    raise exception 'Only Operations Head can approve duty changes.' using errcode = '42501';
  end if;
  if p_approve is null or char_length(trim(coalesce(p_note, ''))) > 1500 then
    raise exception 'Choose a decision and keep the note within 1500 characters.';
  end if;
  if not p_approve and char_length(trim(coalesce(p_note, ''))) < 5 then
    raise exception 'Explain the rejection in at least 5 characters.';
  end if;

  select * into r
  from public.shift_swap_requests
  where id = p_request_id
    and organization_id = public.current_organization_id()
    and status = 'pending_admin'
  for update;

  if not found then
    raise exception 'This request is no longer awaiting Operations Head approval.';
  end if;

  if r.target_schedule_id is null then
    perform private.decide_legacy_duty_request(p_request_id, p_approve, p_note, p_replacement_guard_id);
    return;
  end if;

  if not p_approve then
    update public.shift_swap_requests
    set status = 'rejected',
        admin_decision_by = auth.uid(),
        admin_decision_at = now(),
        admin_note = trim(coalesce(p_note, '')),
        updated_at = now()
    where id = r.id;
    return;
  end if;

  if p_replacement_guard_id is not null and p_replacement_guard_id <> r.target_guard_id then
    raise exception 'Approve the selected exchange, or reject it. A different replacement cannot be substituted.';
  end if;

  -- If the target guard already approved earlier, finalize immediately.
  if r.guard_response = 'approved' then
    v_swapped := private.execute_duty_swap_exchange(r.id, auth.uid());
    update public.shift_swap_requests
    set status = 'approved',
        admin_decision_by = auth.uid(),
        admin_decision_at = now(),
        admin_note = trim(coalesce(p_note, '')),
        exchange_snapshot = coalesce(exchange_snapshot, '{}'::jsonb) || jsonb_build_object('swapped_count', v_swapped),
        updated_at = now()
    where id = r.id;
    return;
  end if;

  if r.admin_decision_at is not null then
    raise exception 'Already approved by Operations Head. Waiting for the selected Guard to confirm.';
  end if;

  if not private.duty_exchange_eligible(r.requested_schedule_id, r.target_schedule_id, r.id) then
    raise exception 'One of these duties has changed, started attendance, or conflicts with another schedule. Reject this request.';
  end if;

  -- Record Operations Head approval first and leave guard_response = 'pending' for the chosen guard.
  update public.shift_swap_requests
  set admin_decision_by = auth.uid(),
      admin_decision_at = now(),
      admin_note = trim(coalesce(p_note, '')),
      updated_at = now()
  where id = r.id;
end;
$$;
revoke all on function public.decide_duty_request(uuid, boolean, text, uuid) from public, anon;
grant execute on function public.decide_duty_request(uuid, boolean, text, uuid) to authenticated;

-- Chosen guard confirms or declines swap. Once approved by Operations Head and confirmed by Guard,
-- schedules are swapped automatically for that day or entire month.
create or replace function public.respond_to_duty_swap(
  p_request_id uuid,
  p_approve boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.shift_swap_requests;
  v_swapped integer;
begin
  if not coalesce(public.is_active_guard(), false) or p_approve is null then
    raise exception 'Only an active Guard can respond.' using errcode = '42501';
  end if;

  select * into r
  from public.shift_swap_requests
  where id = p_request_id
    and organization_id = public.current_organization_id()
    and target_guard_id = auth.uid()
    and target_schedule_id is not null
  for update;

  if not found then
    raise exception 'This swap request is not addressed to you.' using errcode = '42501';
  end if;

  if r.status <> 'pending_admin' or r.guard_response is distinct from 'pending' then
    raise exception 'This request has already been answered.';
  end if;

  if not p_approve then
    update public.shift_swap_requests
    set guard_response = 'declined',
        guard_responded_at = now(),
        status = 'rejected',
        updated_at = now()
    where id = r.id;
    return;
  end if;

  if r.admin_decision_at is not null then
    v_swapped := private.execute_duty_swap_exchange(r.id, coalesce(r.admin_decision_by, auth.uid()));
    update public.shift_swap_requests
    set guard_response = 'approved',
        guard_responded_at = now(),
        status = 'approved',
        exchange_snapshot = coalesce(exchange_snapshot, '{}'::jsonb) || jsonb_build_object('swapped_count', v_swapped),
        updated_at = now()
    where id = r.id;
  else
    -- Backward compatibility if an older unapproved request is answered directly.
    perform s.id from public.schedules s where s.id in (r.requested_schedule_id, r.target_schedule_id) order by s.id for update;
    if not private.duty_exchange_eligible(r.requested_schedule_id, r.target_schedule_id, r.id) then
      raise exception 'A duty has changed or is no longer available. Decline this request and ask for a new one.';
    end if;
    update public.shift_swap_requests
    set guard_response = 'approved',
        guard_responded_at = now(),
        status = 'pending_admin',
        updated_at = now()
    where id = r.id;
  end if;
end;
$$;
revoke all on function public.respond_to_duty_swap(uuid, boolean) from public, anon;
grant execute on function public.respond_to_duty_swap(uuid, boolean) to authenticated;

create or replace function public.notify_shift_request_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
  v_title text := case when new.request_type = 'absence' then 'Absence request' else 'Swap request' end;
  v_scope_word text := case when coalesce(new.swap_scope, 'day') = 'month' then 'monthly ' else '' end;
begin
  -- Guard-to-guard swap flow:
  -- 1. INSERT -> notify Operations Head & Requester
  -- 2. Operations Head approves (admin_decision_at set, guard_response='pending') -> notify Chosen Guard & Requester
  -- 3. Chosen Guard confirms (status='approved') -> notify Requester, Chosen Guard, & Operations Head
  -- 4. Guard declines -> notify Requester & Operations Head
  if new.target_schedule_id is not null then
    if tg_op = 'INSERT' and new.status = 'pending_admin' and new.admin_decision_at is null then
      for v_recipient in
        select id from public.profiles
        where active and role = 'admin' and organization_id = new.organization_id
      loop
        perform public.insert_user_notification(
          v_recipient.id, new.organization_id, 'shift_request', 'high',
          'Swap request awaiting approval',
          coalesce(new.exchange_snapshot->>'requester_name', 'A Guard') || ' requested a ' ||
            case when coalesce(new.swap_scope, 'day') = 'month' then 'full-month ' else '' end ||
            'shift swap with ' || coalesce(new.exchange_snapshot->>'target_name', 'another Guard') || '. Review in Duty requests.',
          'shift_request', 'shift_swap_request', new.id,
          jsonb_build_object('status', new.status, 'request_type', new.request_type, 'swap_scope', coalesce(new.swap_scope, 'day')),
          false, new.requester_id, 'shift-request:' || new.id::text || ':admin', now() + interval '90 days'
        );
      end loop;

      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request', 'normal',
        'Swap request submitted',
        'Your ' || v_scope_word || 'swap request was sent to Operations Head for approval.',
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', new.status, 'swap_scope', coalesce(new.swap_scope, 'day')),
        false, new.requester_id, 'shift-request:' || new.id::text || ':submitted', now() + interval '90 days'
      );
      return new;
    end if;

    if tg_op = 'UPDATE'
       and new.admin_decision_at is not null
       and old.admin_decision_at is null
       and new.status = 'pending_admin'
       and new.guard_response = 'pending' then
      perform public.insert_user_notification(
        new.target_guard_id, new.organization_id, 'shift_request', 'high',
        'Shift swap approved — Confirm swap',
        coalesce(new.exchange_snapshot->>'requester_name', 'A Guard') || ' wants to swap ' ||
          case when coalesce(new.swap_scope, 'day') = 'month' then 'monthly shifts' else 'a shift' end ||
          ' with you (approved by Operations Head). Open Absence & Shift Swap to confirm.',
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', 'awaiting_guard_confirmation', 'swap_scope', coalesce(new.swap_scope, 'day')),
        false, new.admin_decision_by, 'shift-request:' || new.id::text || ':guard-consent', now() + interval '90 days'
      );

      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request', 'normal',
        'Operations Head approved your swap',
        'Awaiting ' || coalesce(new.exchange_snapshot->>'target_name', 'the chosen Guard') || ' to confirm the swap.',
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', 'awaiting_guard_confirmation'),
        false, new.admin_decision_by, 'shift-request:' || new.id::text || ':admin-approved-wait-guard', now() + interval '90 days'
      );
      return new;
    end if;

    if tg_op = 'UPDATE'
       and new.guard_response = 'declined'
       and old.guard_response is distinct from new.guard_response then
      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request', 'high',
        'Shift swap declined',
        coalesce(new.exchange_snapshot->>'target_name', 'The chosen Guard') || ' declined the swap. Your duties remain unchanged.',
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', 'rejected'),
        false, new.target_guard_id, 'shift-request:' || new.id::text || ':guard-declined', now() + interval '90 days'
      );

      for v_recipient in
        select id from public.profiles
        where active and role = 'admin' and organization_id = new.organization_id
      loop
        perform public.insert_user_notification(
          v_recipient.id, new.organization_id, 'shift_request', 'normal',
          'Guard declined shift swap',
          coalesce(new.exchange_snapshot->>'target_name', 'The chosen Guard') || ' declined the shift swap requested by ' ||
            coalesce(new.exchange_snapshot->>'requester_name', 'the Guard') || '.',
          'shift_request', 'shift_swap_request', new.id,
          jsonb_build_object('status', 'rejected'),
          false, new.target_guard_id, 'shift-request:' || new.id::text || ':guard-declined:admin', now() + interval '90 days'
        );
      end loop;
      return new;
    end if;

    if tg_op = 'UPDATE' and new.status = 'approved' and old.status is distinct from 'approved' then
      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'schedule', 'high',
        'Shift swap confirmed & scheduled',
        coalesce(new.exchange_snapshot->>'target_name', 'Your swap partner') || ' confirmed the swap. Your ' ||
          v_scope_word || 'schedule has been updated automatically.',
        'schedule', 'shift_swap_request', new.id,
        jsonb_build_object('status', 'approved', 'swap_scope', coalesce(new.swap_scope, 'day')),
        false, new.target_guard_id, 'shift-request:' || new.id::text || ':approved:requester', now() + interval '180 days'
      );

      if new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
        perform public.insert_user_notification(
          new.target_guard_id, new.organization_id, 'schedule', 'high',
          'Shift swap confirmed & scheduled',
          'You confirmed the swap with ' || coalesce(new.exchange_snapshot->>'requester_name', 'your co-guard') ||
            '. Your ' || v_scope_word || 'schedule has been updated automatically.',
          'schedule', 'shift_swap_request', new.id,
          jsonb_build_object('status', 'approved', 'swap_scope', coalesce(new.swap_scope, 'day')),
          false, new.target_guard_id, 'shift-request:' || new.id::text || ':approved:target', now() + interval '180 days'
        );
      end if;

      for v_recipient in
        select id from public.profiles
        where active and role = 'admin' and organization_id = new.organization_id
      loop
        perform public.insert_user_notification(
          v_recipient.id, new.organization_id, 'schedule', 'high',
          'Guard confirmed shift swap',
          coalesce(new.exchange_snapshot->>'target_name', 'The chosen Guard') || ' confirmed the swap with ' ||
            coalesce(new.exchange_snapshot->>'requester_name', 'the requesting Guard') || '. Their ' ||
            v_scope_word || 'schedule was updated automatically.',
          'schedule', 'shift_swap_request', new.id,
          jsonb_build_object('status', 'approved', 'swap_scope', coalesce(new.swap_scope, 'day')),
          false, new.target_guard_id, 'shift-request:' || new.id::text || ':approved:admin', now() + interval '180 days'
        );
      end loop;
      return new;
    end if;

    if tg_op = 'UPDATE' and new.status in ('rejected', 'cancelled') and old.status is distinct from new.status then
      perform public.insert_user_notification(
        new.requester_id, new.organization_id, 'shift_request', 'high',
        v_title || ' ' || new.status,
        left('Operations Head ' || new.status || ' your request.' || case when nullif(new.admin_note, '') is null then '' else ' ' || new.admin_note end, 1000),
        'shift_request', 'shift_swap_request', new.id,
        jsonb_build_object('status', new.status),
        false, new.admin_decision_by, 'shift-request:' || new.id::text || ':decision:' || new.status, now() + interval '180 days'
      );
      return new;
    end if;

    return new;
  end if;

  -- Legacy / Absence / Single-guard replacement request notifications
  if new.status = 'pending_admin' and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    for v_recipient in select id from public.profiles where active and role = 'admin' and organization_id = new.organization_id loop
      perform public.insert_user_notification(v_recipient.id, new.organization_id, 'shift_request', 'high',
        v_title || ' awaiting approval', 'Review the Guard''s request and attached letter.',
        'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status', new.status, 'request_type', new.request_type),
        false, new.requester_id, 'shift-request:' || new.id::text || ':admin', now() + interval '90 days');
    end loop;
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'normal',
      v_title || ' submitted', 'Your request was sent directly to Operational Head for approval.',
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status', new.status), false, new.requester_id,
      'shift-request:' || new.id::text || ':direct-submitted', now() + interval '90 days');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('approved', 'rejected', 'cancelled') then
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'high',
      v_title || ' ' || new.status,
      left('Operational Head ' || new.status || ' your request.' || case when nullif(new.admin_note, '') is null then '' else ' ' || new.admin_note end, 1000),
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status', new.status), false, new.admin_decision_by,
      'shift-request:' || new.id::text || ':decision:' || new.status, now() + interval '180 days');
    if new.status = 'approved' and new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
      perform public.insert_user_notification(new.target_guard_id, new.organization_id, 'schedule', 'high',
        'Duty assigned through an approved swap', 'Operational Head assigned you a duty. Check your schedule.',
        'schedule', 'shift_swap_request', new.id, jsonb_build_object('schedule_id', coalesce(new.replacement_schedule_id, new.requested_schedule_id)), false,
        new.admin_decision_by, 'shift-request:' || new.id::text || ':target-approved', now() + interval '180 days');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists notify_shift_request_event on public.shift_swap_requests;
create trigger notify_shift_request_event
after insert or update of status, guard_response, admin_decision_at on public.shift_swap_requests
for each row execute function public.notify_shift_request_event();

notify pgrst, 'reload schema';
