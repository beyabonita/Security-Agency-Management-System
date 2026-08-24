-- Keep every step of the shift-change workflow inside the caller's organization.
-- These RPCs are security definer functions, so tenant checks must be explicit.

create or replace function public.request_shift_swap(
  p_schedule_id uuid,
  p_target_guard_id uuid default null,
  p_requested_start_at timestamptz default null,
  p_requested_end_at timestamptz default null,
  p_reason text default ''
) returns public.shift_swap_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.shift_swap_requests;
  v_inspector uuid;
  v_organization_id uuid;
  v_schedule_start_at timestamptz;
  v_schedule_end_at timestamptz;
  v_effective_start_at timestamptz;
  v_effective_end_at timestamptz;
  v_destination_guard_id uuid;
begin
  if not public.is_active_guard() then
    raise exception 'Only active guards can request schedule changes.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if char_length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Provide a reason of at least 5 characters.';
  end if;

  if (p_requested_start_at is null) <> (p_requested_end_at is null) then
    raise exception 'Provide both requested start and end times, or leave both unchanged.';
  end if;
  if p_requested_start_at is not null
    and (p_requested_start_at <= now() or p_requested_end_at <= p_requested_start_at) then
    raise exception 'Requested duty times must be in the future and end after they start.';
  end if;

  select s.start_at, s.end_at
    into v_schedule_start_at, v_schedule_end_at
  from public.schedules s
  where s.id = p_schedule_id
    and s.user_id = auth.uid()
    and s.organization_id = v_organization_id
    and s.start_at > now()
    and s.approval_status = 'approved';
  if not found then
    raise exception 'Choose an upcoming approved duty schedule from your organization.';
  end if;

  if exists (
    select 1
    from public.shift_swap_requests sr
    where sr.requested_schedule_id = p_schedule_id
      and sr.organization_id = v_organization_id
      and sr.status in ('pending_inspector', 'pending_admin')
  ) then
    raise exception 'A shift-change request for this schedule is already awaiting review.';
  end if;

  if p_target_guard_id is not null then
    if p_target_guard_id = auth.uid() then
      raise exception 'Choose a different guard for a shift swap.';
    end if;
    if not exists (
      select 1
      from public.profiles p
      where p.id = p_target_guard_id
        and p.organization_id = v_organization_id
        and p.role = 'user'
        and p.active
    ) then
      raise exception 'The proposed guard is not an active guard in your organization.';
    end if;
  end if;

  v_effective_start_at := coalesce(p_requested_start_at, v_schedule_start_at);
  v_effective_end_at := coalesce(p_requested_end_at, v_schedule_end_at);
  v_destination_guard_id := coalesce(p_target_guard_id, auth.uid());
  if exists (
    select 1
    from public.schedules s
    where s.id <> p_schedule_id
      and s.user_id = v_destination_guard_id
      and s.organization_id = v_organization_id
      and s.approval_status in ('approved', 'changed')
      and s.start_at < v_effective_end_at
      and s.end_at > v_effective_start_at
  ) then
    raise exception 'The proposed guard already has an overlapping approved duty schedule.';
  end if;

  select p.inspector_id
    into v_inspector
  from public.profiles p
  where p.id = auth.uid()
    and p.organization_id = v_organization_id;
  if v_inspector is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_inspector
      and p.organization_id = v_organization_id
      and p.role = 'inspector'
      and p.active
  ) then
    raise exception 'No active Inspector is assigned in your organization.';
  end if;

  insert into public.shift_swap_requests (
    requester_id,
    requested_schedule_id,
    target_guard_id,
    requested_start_at,
    requested_end_at,
    reason,
    inspector_id,
    organization_id
  ) values (
    auth.uid(),
    p_schedule_id,
    p_target_guard_id,
    p_requested_start_at,
    p_requested_end_at,
    left(trim(coalesce(p_reason, '')), 1500),
    v_inspector,
    v_organization_id
  ) returning * into r;

  return r;
end;
$$;

create or replace function public.review_shift_swap_by_inspector(
  p_request_id uuid,
  p_approve boolean,
  p_note text default ''
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if public.current_role() is distinct from 'inspector'::public.app_role
    or not public.current_organization_is_active() then
    raise exception 'Only an active Inspector can review a shift-change request.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  update public.shift_swap_requests
  set status = case when p_approve then 'pending_admin' else 'rejected' end,
      inspector_decision_by = auth.uid(),
      inspector_decision_at = now(),
      inspector_note = left(trim(coalesce(p_note, '')), 1500),
      updated_at = now()
  where id = p_request_id
    and inspector_id = auth.uid()
    and organization_id = v_organization_id
    and status = 'pending_inspector';

  if not found then
    raise exception 'Request not available for review.';
  end if;
end;
$$;

create or replace function public.decide_shift_swap_by_admin(
  p_request_id uuid,
  p_approve boolean,
  p_note text default ''
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.shift_swap_requests%rowtype;
  v_organization_id uuid;
  v_schedule_start_at timestamptz;
  v_schedule_end_at timestamptz;
  v_effective_start_at timestamptz;
  v_effective_end_at timestamptz;
  v_destination_guard_id uuid;
begin
  if not public.is_operations_staff() then
    raise exception 'Only HR / Operations Head can finalize a schedule change.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  select * into r
  from public.shift_swap_requests
  where id = p_request_id
    and organization_id = v_organization_id
    and status = 'pending_admin'
  for update;
  if not found then
    raise exception 'Request is not awaiting final approval in your organization.';
  end if;

  if p_approve then
    select s.start_at, s.end_at
      into v_schedule_start_at, v_schedule_end_at
    from public.schedules s
    where s.id = r.requested_schedule_id
      and s.organization_id = v_organization_id
      and s.user_id = r.requester_id
    for update;
    if not found then
      raise exception 'The requested schedule is no longer available in your organization.';
    end if;

    v_destination_guard_id := coalesce(r.target_guard_id, r.requester_id);
    if not exists (
      select 1
      from public.profiles p
      where p.id = v_destination_guard_id
        and p.organization_id = v_organization_id
        and p.role = 'user'
        and p.active
    ) then
      raise exception 'The guard assigned to the requested schedule is no longer active in your organization.';
    end if;

    if (r.requested_start_at is null) <> (r.requested_end_at is null)
      or (r.requested_start_at is not null and r.requested_end_at <= r.requested_start_at) then
      raise exception 'The requested duty times are invalid.';
    end if;
    v_effective_start_at := coalesce(r.requested_start_at, v_schedule_start_at);
    v_effective_end_at := coalesce(r.requested_end_at, v_schedule_end_at);

    if exists (
      select 1
      from public.schedules s
      where s.id <> r.requested_schedule_id
        and s.user_id = v_destination_guard_id
        and s.organization_id = v_organization_id
        and s.approval_status in ('approved', 'changed')
        and s.start_at < v_effective_end_at
        and s.end_at > v_effective_start_at
    ) then
      raise exception 'The proposed guard has an overlapping approved duty schedule.';
    end if;

    update public.schedules
    set user_id = v_destination_guard_id,
        start_at = v_effective_start_at,
        end_at = v_effective_end_at,
        approval_status = 'changed',
        approved_by = auth.uid()
    where id = r.requested_schedule_id
      and organization_id = v_organization_id;
  end if;

  update public.shift_swap_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      admin_decision_by = auth.uid(),
      admin_decision_at = now(),
      admin_note = left(trim(coalesce(p_note, '')), 1500),
      updated_at = now()
  where id = p_request_id
    and organization_id = v_organization_id;
end;
$$;

grant execute on function public.request_shift_swap(uuid,uuid,timestamptz,timestamptz,text),
  public.review_shift_swap_by_inspector(uuid,boolean,text),
  public.decide_shift_swap_by_admin(uuid,boolean,text)
to authenticated;
