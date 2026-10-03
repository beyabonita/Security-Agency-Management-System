-- Exchange two existing duty periods without exposing other Guards' private
-- profiles, attendance or letters. Existing installed apps retain coverage requests.
alter table public.shift_swap_requests
  add column target_schedule_id uuid references public.schedules(id) on delete restrict,
  add column exchange_snapshot jsonb;
alter table public.shift_swap_requests add constraint duty_exchange_has_snapshot
  check (target_schedule_id is null or (request_type = 'swap'
    and target_schedule_id <> requested_schedule_id and target_guard_id is not null
    and exchange_snapshot is not null));
create index shift_request_target_pending_idx on public.shift_swap_requests(target_schedule_id)
  where status in ('pending_admin','pending_inspector');

create or replace function private.duty_exchange_eligible(
  p_source uuid, p_target uuid, p_ignore_request uuid default null
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.schedules a join public.schedules b
      on b.id = p_target and b.organization_id = a.organization_id and b.user_id <> a.user_id
    join public.profiles pa on pa.id = a.user_id and pa.organization_id = a.organization_id and pa.active and pa.role = 'user'
    join public.profiles pb on pb.id = b.user_id and pb.organization_id = b.organization_id and pb.active and pb.role = 'user'
    join public.locations la on la.id = a.location_id and la.organization_id = a.organization_id and la.active
    join public.locations lb on lb.id = b.location_id and lb.organization_id = b.organization_id and lb.active
    where a.id = p_source and a.id <> b.id
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
            (other.user_id = a.user_id and other.start_at < b.end_at and other.end_at > b.start_at)
            or (other.user_id = b.user_id and other.start_at < a.end_at and other.end_at > a.start_at)))
  );
$$;
revoke all on function private.duty_exchange_eligible(uuid,uuid,uuid) from public,anon,authenticated;

-- Minimal immutable duty details used for review and detecting changed offers.
create or replace function private.duty_exchange_snapshot(p_schedule uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',s.id,'user_id',s.user_id,'start_at',s.start_at,'end_at',s.end_at,
    'location_id',s.location_id,'location_label',s.location_label,'duty_date',s.duty_date,'dtr_period',s.dtr_period)
  from public.schedules s where s.id = p_schedule;
$$;
revoke all on function private.duty_exchange_snapshot(uuid) from public,anon,authenticated;

create or replace function public.available_duty_swaps(p_schedule_id uuid)
returns table(id uuid, guard_name text, start_at timestamptz, end_at timestamptz,
  location_label text, duty_date date, dtr_period text)
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.current_organization_id();
begin
  if not public.is_active_guard() or v_org is null then
    raise exception 'Only an active Guard can view swap options.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.schedules s where s.id = p_schedule_id
      and s.user_id = auth.uid() and s.organization_id = v_org) then
    raise exception 'Choose one of your own duty periods.' using errcode = '42501';
  end if;
  return query select s.id,
    coalesce(nullif(trim(concat_ws(' ',nullif(p.first_name,''),nullif(p.middle_initial,''),nullif(p.last_name,''))),''),p.username,'Guard'),
    s.start_at,s.end_at,s.location_label,s.duty_date,s.dtr_period
    from public.schedules s join public.profiles p on p.id = s.user_id
    where s.organization_id = v_org and s.user_id <> auth.uid()
      and s.approval_status in ('approved','changed') and s.end_at > now()
      and private.duty_exchange_eligible(p_schedule_id,s.id)
    order by s.start_at,s.id;
end;
$$;
revoke all on function public.available_duty_swaps(uuid) from public,anon;
grant execute on function public.available_duty_swaps(uuid) to authenticated;

-- Include the target duty in pending-request exclusivity, even for old apps
-- submitting an absence or coverage request against an offered swap period.
create or replace function private.protect_pending_duty_exchange()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status not in ('pending_admin','pending_inspector') then return new; end if;
  perform s.id from public.schedules s where s.id in (new.requested_schedule_id,new.target_schedule_id)
    order by s.id for update;
  if exists (select 1 from public.shift_swap_requests r where r.id <> new.id
    and r.organization_id = new.organization_id and r.status in ('pending_admin','pending_inspector')
    and (r.requested_schedule_id in (new.requested_schedule_id,new.target_schedule_id)
      or r.target_schedule_id in (new.requested_schedule_id,new.target_schedule_id))) then
    raise exception 'One of these duties already has a request awaiting Admin approval.';
  end if;
  return new;
end;
$$;
revoke all on function private.protect_pending_duty_exchange() from public,anon,authenticated;
create trigger protect_pending_duty_exchange before insert or update of requested_schedule_id,target_schedule_id,status
  on public.shift_swap_requests for each row execute function private.protect_pending_duty_exchange();

create or replace function public.submit_duty_exchange(p_schedule_id uuid,p_target_schedule_id uuid,
  p_reason text,p_letter_path text,p_letter_name text)
returns public.shift_swap_requests language plpgsql security definer set search_path = '' as $$
declare r public.shift_swap_requests; a public.schedules; b public.schedules;
  v_org uuid := public.current_organization_id(); v_source_name text; v_target_name text;
begin
  if not public.is_active_guard() or v_org is null then
    raise exception 'Only an active Guard can submit a swap.' using errcode = '42501';
  end if;
  select * into r from public.shift_swap_requests where letter_path = p_letter_path
    and requester_id = auth.uid() and organization_id = v_org;
  if found then
    if r.requested_schedule_id is distinct from p_schedule_id or r.target_schedule_id is distinct from p_target_schedule_id
      or r.reason is distinct from trim(p_reason) then
      raise exception 'This letter is already filed with another request. Refresh your requests.';
    end if;
    return r;
  end if;
  perform s.id from public.schedules s where s.organization_id = v_org
    and s.id in (p_schedule_id,p_target_schedule_id) order by s.id for update;
  select * into a from public.schedules where id = p_schedule_id and organization_id = v_org and user_id = auth.uid();
  if not found then raise exception 'Choose one of your own duty periods.' using errcode = '42501'; end if;
  if not private.duty_exchange_eligible(a.id,p_target_schedule_id) then
    raise exception 'These duties are no longer available for exchange. Refresh and choose another duty.';
  end if;
  select * into b from public.schedules where id = p_target_schedule_id;
  select coalesce(nullif(trim(concat_ws(' ',nullif(first_name,''),nullif(middle_initial,''),nullif(last_name,''))),''),username,'Guard')
    into v_source_name from public.profiles where id = a.user_id;
  select coalesce(nullif(trim(concat_ws(' ',nullif(first_name,''),nullif(middle_initial,''),nullif(last_name,''))),''),username,'Guard')
    into v_target_name from public.profiles where id = b.user_id;
  -- Reuse attachment ownership, MIME/size, reason and idempotent upload checks.
  r := public.submit_duty_request(a.id,'swap',p_reason,p_letter_path,p_letter_name);
  update public.shift_swap_requests set target_schedule_id = b.id, target_guard_id = b.user_id,
    exchange_snapshot = jsonb_build_object('offered',private.duty_exchange_snapshot(a.id),
      'requested',private.duty_exchange_snapshot(b.id),'requester_name',v_source_name,'target_name',v_target_name)
    where id = r.id returning * into r;
  return r;
end;
$$;
revoke all on function public.submit_duty_exchange(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.submit_duty_exchange(uuid,uuid,text,text,text) to authenticated;

-- Preserve the proven absence/legacy coverage path behind a private boundary.
alter function public.decide_duty_request(uuid,boolean,text,uuid) rename to decide_legacy_duty_request;
alter function public.decide_legacy_duty_request(uuid,boolean,text,uuid) set schema private;
revoke all on function private.decide_legacy_duty_request(uuid,boolean,text,uuid) from public,anon,authenticated;

create or replace function public.decide_duty_request(p_request_id uuid,p_approve boolean,
  p_note text default '',p_replacement_guard_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shift_swap_requests; a public.schedules; b public.schedules;
  v_key bigint; v_a_category text; v_b_category text;
begin
  if not public.is_admin() or public.current_organization_id() is null then
    raise exception 'Only Admin can decide duty requests.' using errcode = '42501';
  end if;
  if p_approve is null or char_length(trim(coalesce(p_note,''))) > 1500 then
    raise exception 'Choose a decision and keep the note within 1500 characters.';
  end if;
  if not p_approve and char_length(trim(coalesce(p_note,''))) < 5 then
    raise exception 'Explain the rejection in at least 5 characters.';
  end if;
  select * into r from public.shift_swap_requests where id = p_request_id
    and organization_id = public.current_organization_id() and status = 'pending_admin' for update;
  if not found then raise exception 'This request is no longer awaiting Admin approval.'; end if;
  if r.target_schedule_id is null then
    perform private.decide_legacy_duty_request(p_request_id,p_approve,p_note,p_replacement_guard_id);
    return;
  end if;
  if p_approve then
    if p_replacement_guard_id is not null and p_replacement_guard_id <> r.target_guard_id then
      raise exception 'Approve the selected exchange, or reject it. A different replacement cannot be substituted.';
    end if;
    -- Use the same locks as scheduling, in deterministic order for both Guards.
    for v_key in select distinct pg_catalog.hashtextextended(r.organization_id::text || ':' || g::text,0)
      from unnest(array[r.requester_id,r.target_guard_id]) g order by 1 loop
      perform pg_catalog.pg_advisory_xact_lock(v_key);
    end loop;
    perform p.id from public.profiles p where p.id in (r.requester_id,r.target_guard_id) order by p.id for update;
    perform s.id from public.schedules s where s.id in (r.requested_schedule_id,r.target_schedule_id) order by s.id for update;
    select * into a from public.schedules where id = r.requested_schedule_id;
    select * into b from public.schedules where id = r.target_schedule_id;
    if private.duty_exchange_snapshot(a.id) is distinct from r.exchange_snapshot->'offered'
      or private.duty_exchange_snapshot(b.id) is distinct from r.exchange_snapshot->'requested'
      or not private.duty_exchange_eligible(a.id,b.id,r.id) then
      raise exception 'A duty has changed, ended, started attendance or conflicts with another duty. Reject this request and ask the Guard to submit again.';
    end if;
    select employment_category into v_a_category from public.profiles where id = a.user_id;
    select employment_category into v_b_category from public.profiles where id = b.user_id;
    -- Temporarily draft both locked rows inside this transaction so same-time
    -- exchanges do not hit an intermediate overlap. No draft notification is
    -- emitted; existing overlap/history triggers still validate the final rows.
    update public.schedules set approval_status = 'draft' where id in (a.id,b.id);
    update public.schedules set user_id = b.user_id, duty_category = v_b_category where id = a.id;
    update public.schedules set user_id = a.user_id, duty_category = v_a_category where id = b.id;
    update public.schedules set approval_status = 'changed', approved_by = auth.uid() where id in (a.id,b.id);
  end if;
  update public.shift_swap_requests set status = case when p_approve then 'approved' else 'rejected' end,
    admin_decision_by = auth.uid(),admin_decision_at = now(),admin_note = trim(coalesce(p_note,'')),updated_at = now()
    where id = r.id;
end;
$$;
revoke all on function public.decide_duty_request(uuid,boolean,text,uuid) from public,anon;
grant execute on function public.decide_duty_request(uuid,boolean,text,uuid) to authenticated;
create or replace function public.decide_shift_swap_by_admin(p_request_id uuid,p_approve boolean,p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin perform public.decide_duty_request(p_request_id,p_approve,p_note); end;
$$;
