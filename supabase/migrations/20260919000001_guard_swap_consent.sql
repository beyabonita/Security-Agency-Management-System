alter table public.shift_swap_requests
  add column guard_response text check(guard_response in ('pending','approved','declined')),
  add column guard_responded_at timestamptz;
drop policy if exists "tenant swap request visibility" on public.shift_swap_requests;
create policy "tenant swap request visibility" on public.shift_swap_requests for select to authenticated
using (public.is_it_admin() or (organization_id=public.current_organization_id() and public.current_organization_is_active()
  and (requester_id=(select auth.uid()) or (target_guard_id=(select auth.uid()) and public.is_active_guard()) or public.is_admin())));
create or replace function public.submit_duty_exchange(p_schedule_id uuid,p_target_schedule_id uuid,p_reason text,p_letter_path text,p_letter_name text)
returns public.shift_swap_requests language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests; a public.schedules; b public.schedules;
  v_org uuid:=public.current_organization_id(); v_source_name text; v_target_name text;
begin
  if not coalesce(public.is_active_guard(),false) or v_org is null then raise exception 'Only an active Guard can submit a swap.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where letter_path=p_letter_path and requester_id=auth.uid() and organization_id=v_org;
  if found then
    if r.requested_schedule_id is distinct from p_schedule_id or r.target_schedule_id is distinct from p_target_schedule_id or r.reason is distinct from trim(p_reason) then raise exception 'This letter is already filed with another request.'; end if;
    return r;
  end if;
  if char_length(trim(coalesce(p_reason,''))) not between 5 and 1500 then raise exception 'Enter a reason between 5 and 1500 characters.'; end if;
  if char_length(trim(coalesce(p_letter_name,''))) not between 1 and 180 or p_letter_name ~ '[[:cntrl:]/\\]' then raise exception 'Choose a valid letter filename.'; end if;
  if p_letter_path is null or p_letter_path !~ ('^'||auth.uid()::text||'/[A-Za-z0-9-]+\.(pdf|jpg|png)$') or not exists(
    select 1 from storage.objects o where o.bucket_id='request-letters' and o.name=p_letter_path and (o.metadata->>'size')::bigint between 1 and 5242880
      and o.metadata->>'mimetype'=case when p_letter_path like '%.pdf' then 'application/pdf' when p_letter_path like '%.jpg' then 'image/jpeg' else 'image/png' end
  ) then raise exception 'Attach an owned PDF, JPG or PNG letter (up to 5 MB).'; end if;
  perform s.id from public.schedules s where s.organization_id=v_org and s.id in(p_schedule_id,p_target_schedule_id) order by s.id for update;
  select * into a from public.schedules where id=p_schedule_id and organization_id=v_org and user_id=auth.uid();
  if not found then raise exception 'Choose one of your own duty periods.' using errcode='42501'; end if;
  if not private.duty_exchange_eligible(a.id,p_target_schedule_id) then raise exception 'These duties are no longer available for exchange. Refresh and choose another duty.'; end if;
  select * into b from public.schedules where id=p_target_schedule_id;
  select coalesce(nullif(trim(concat_ws(' ',first_name,middle_initial,last_name)),''),username,'Guard') into v_source_name from public.profiles where id=a.user_id;
  select coalesce(nullif(trim(concat_ws(' ',first_name,middle_initial,last_name)),''),username,'Guard') into v_target_name from public.profiles where id=b.user_id;
  insert into public.shift_swap_requests(requester_id,requested_schedule_id,target_schedule_id,target_guard_id,reason,organization_id,request_type,letter_path,letter_name,status,guard_response,exchange_snapshot)
  values(auth.uid(),a.id,b.id,b.user_id,trim(p_reason),v_org,'swap',p_letter_path,trim(p_letter_name),'pending_admin','pending',
    jsonb_build_object('offered',private.duty_exchange_snapshot(a.id),'requested',private.duty_exchange_snapshot(b.id),'requester_name',v_source_name,'target_name',v_target_name)) returning * into r;
  return r;
end; $$;
create function public.respond_to_duty_swap(p_request_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests;
begin
  if not coalesce(public.is_active_guard(),false) or p_approve is null then raise exception 'Only an active Guard can respond.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where id=p_request_id and organization_id=public.current_organization_id()
    and target_guard_id=auth.uid() and target_schedule_id is not null for update;
  if not found then raise exception 'This swap request is not addressed to you.' using errcode='42501'; end if;
  if r.status<>'pending_admin' or r.guard_response is distinct from 'pending' then raise exception 'This request has already been answered.'; end if;
  if p_approve then
    perform s.id from public.schedules s where s.id in(r.requested_schedule_id,r.target_schedule_id) order by s.id for update;
    if private.duty_exchange_snapshot(r.requested_schedule_id) is distinct from r.exchange_snapshot->'offered'
      or private.duty_exchange_snapshot(r.target_schedule_id) is distinct from r.exchange_snapshot->'requested'
      or not private.duty_exchange_eligible(r.requested_schedule_id,r.target_schedule_id,r.id) then
      raise exception 'A duty has changed or is no longer available. Decline this request and ask for a new one.';
    end if;
  end if;
  update public.shift_swap_requests set guard_response=case when p_approve then 'approved' else 'declined' end,
    guard_responded_at=now(),status=case when p_approve then 'pending_admin' else 'rejected' end,updated_at=now() where id=r.id;
end; $$;
revoke all on function public.respond_to_duty_swap(uuid,boolean) from public,anon;
grant execute on function public.respond_to_duty_swap(uuid,boolean) to authenticated;
alter function public.decide_duty_request(uuid,boolean,text,uuid) rename to decide_consented_duty_request;
alter function public.decide_consented_duty_request(uuid,boolean,text,uuid) set schema private;
revoke all on function private.decide_consented_duty_request(uuid,boolean,text,uuid) from public,anon,authenticated;
create function public.decide_duty_request(p_request_id uuid,p_approve boolean,p_note text default '',p_replacement_guard_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests;
begin
  if not coalesce(public.is_admin(),false) then raise exception 'Only Operations Head can approve duty changes.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where id=p_request_id and organization_id=public.current_organization_id() for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.target_schedule_id is not null and r.guard_response is distinct from 'approved' then raise exception 'The selected Guard must approve this swap first.'; end if;
  perform private.decide_consented_duty_request(p_request_id,p_approve,p_note,p_replacement_guard_id);
end; $$;
revoke all on function public.decide_duty_request(uuid,boolean,text,uuid) from public,anon;
grant execute on function public.decide_duty_request(uuid,boolean,text,uuid) to authenticated;
create or replace function public.notify_shift_request_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient record; v_title text := case when new.request_type = 'absence' then 'Absence request' else 'Swap request' end;
begin
  if new.target_schedule_id is not null and new.guard_response='pending' then
    if tg_op='INSERT' or old.guard_response is distinct from new.guard_response then
      perform public.insert_user_notification(new.target_guard_id,new.organization_id,'shift_request','normal',
        'Shift swap request for your approval',coalesce(new.exchange_snapshot->>'requester_name','A Guard')||' wants to exchange duties with you. Approve or decline in Letter requests.',
        'shift_request','shift_swap_request',new.id,jsonb_build_object('status','pending_guard'),false,new.requester_id,
        'shift-request:'||new.id::text||':guard-consent',now()+interval '90 days');
      perform public.insert_user_notification(new.requester_id,new.organization_id,'shift_request','normal',
        'Awaiting the selected Guard','Your swap request must be accepted by the selected Guard before Operations Head review.',
        'shift_request','shift_swap_request',new.id,jsonb_build_object('status','pending_guard'),false,new.requester_id,
        'shift-request:'||new.id::text||':guard-waiting',now()+interval '90 days');
    end if;
    return new;
  end if;
  if new.guard_response='declined' and old.guard_response is distinct from new.guard_response then
    perform public.insert_user_notification(new.requester_id,new.organization_id,'shift_request','normal',
      'Shift swap declined',coalesce(new.exchange_snapshot->>'target_name','The selected Guard')||' declined the swap. Your duties remain unchanged.',
      'shift_request','shift_swap_request',new.id,jsonb_build_object('status','rejected'),false,new.target_guard_id,
      'shift-request:'||new.id::text||':guard-declined',now()+interval '90 days');
    return new;
  end if;
  if new.status = 'pending_admin' and (tg_op = 'INSERT' or old.status is distinct from new.status or old.guard_response is distinct from new.guard_response) then
    for v_recipient in select id from public.profiles where active and role = 'admin' and organization_id = new.organization_id loop
      perform public.insert_user_notification(v_recipient.id, new.organization_id, 'shift_request', 'high',
        v_title || ' awaiting approval', 'Review the Guard''s request and attached letter.',
        'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status,'request_type',new.request_type),
        false, new.requester_id, 'shift-request:' || new.id::text || ':admin', now() + interval '90 days');
    end loop;
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'normal',
      v_title || ' submitted', 'Your request was sent directly to Operational Head for approval.',
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.requester_id,
      'shift-request:' || new.id::text || ':direct-submitted', now() + interval '90 days');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('approved','rejected','cancelled') then
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'high',
      v_title || ' ' || new.status,
      left('Operational Head ' || new.status || ' your request.' || case when nullif(new.admin_note,'') is null then '' else ' ' || new.admin_note end, 1000),
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.admin_decision_by,
      'shift-request:' || new.id::text || ':decision:' || new.status, now() + interval '180 days');
    if new.status = 'approved' and new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
      perform public.insert_user_notification(new.target_guard_id, new.organization_id, 'schedule', 'high',
        'Duty assigned through an approved swap', 'Operational Head assigned you a duty. Check your schedule.',
        'schedule', 'shift_swap_request', new.id, jsonb_build_object('schedule_id',coalesce(new.replacement_schedule_id,new.requested_schedule_id)), false,
        new.admin_decision_by, 'shift-request:' || new.id::text || ':target-approved', now() + interval '180 days');
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists notify_shift_request_event on public.shift_swap_requests;
create trigger notify_shift_request_event after insert or update of status,guard_response on public.shift_swap_requests
for each row execute function public.notify_shift_request_event();
-- Existing unanswered exchanges must also obtain the selected Guard's consent.
update public.shift_swap_requests set guard_response='pending'
where target_schedule_id is not null and status in ('pending_admin','pending_inspector') and guard_response is null;
notify pgrst,'reload schema';