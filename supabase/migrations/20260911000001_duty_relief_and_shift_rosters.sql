-- Relief never reassigns a schedule that already contains another guard's work.
alter table public.shift_swap_requests add column replacement_schedule_id uuid
  references public.schedules(id) on delete restrict;

create function public.decide_duty_relief(p_request_id uuid, p_approve boolean,
  p_note text default '', p_replacement_guard_id uuid default null,
  p_actual_end_at timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.shift_swap_requests; s public.schedules; a public.attendance_sessions;
  replacement public.profiles; new_schedule uuid; v_start timestamptz;
  v_now timestamptz := now(); v_key bigint; v_note text := trim(coalesce(p_note,''));
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operational Head can decide duty requests.' using errcode='42501';
  end if;
  if p_approve is null or char_length(v_note)>1500 or (not p_approve and char_length(v_note)<5) then
    raise exception 'Choose a decision. Rejections require 5–1500 characters.';
  end if;
  select * into r from public.shift_swap_requests where id=p_request_id
    and organization_id=public.current_organization_id() and status='pending_admin' for update;
  if not found or r.target_schedule_id is not null then raise exception 'This relief request is no longer awaiting a decision.'; end if;
  if p_approve then
    for v_key in select distinct pg_catalog.hashtextextended(r.organization_id::text||':'||g::text,0)
      from unnest(array[r.requester_id,p_replacement_guard_id]) g where g is not null order by 1 loop
      perform pg_catalog.pg_advisory_xact_lock(v_key);
    end loop;
    select * into s from public.schedules where id=r.requested_schedule_id
      and organization_id=r.organization_id and user_id=r.requester_id for update;
    if not found or s.approval_status not in ('approved','changed') then
      raise exception 'The duty assignment changed. Reload the request.';
    end if;
    select * into a from public.attendance_sessions where schedule_id=s.id
      and user_id=r.requester_id and organization_id=r.organization_id for update;
    if a.id is not null and a.clock_out_at is null then
      if p_actual_end_at is null or not isfinite(p_actual_end_at)
        or p_actual_end_at<a.clock_in_at or p_actual_end_at>least(v_now,a.scheduled_end_at)
        or char_length(v_note)<5 then
        raise exception 'Confirm the actual Time Out with the Guard and enter a note. Use a time between Time In and the earlier of now or scheduled end.';
      end if;
      insert into public.attendance_timeout_reviews(id,organization_id,session_id,guard_id,reviewed_by,
        verified_clock_out_at,reason,before_record)
      values(gen_random_uuid(),r.organization_id,a.id,a.user_id,auth.uid(),p_actual_end_at,v_note,to_jsonb(a));
      update public.attendance_sessions set clock_out_at=p_actual_end_at,status='closed',
        clock_out_location_status='operational_release',timeout_verified_at=v_now,
        timeout_verified_by=auth.uid(),timeout_verification_reason=v_note,updated_at=v_now where id=a.id;
      -- Count a worked date once, matching normal Time Out completion.
      if not s.marked_done and not exists(select 1 from public.attendance_sessions other
        join public.schedules done on done.id=other.schedule_id and done.marked_done
        where other.user_id=a.user_id and other.organization_id=r.organization_id
          and other.duty_date=a.duty_date and other.status='closed' and other.id<>a.id) then
        update public.profiles set duty_days_total=duty_days_total+1 where id=a.user_id;
      end if;
      update public.schedules set marked_done=true,completed_at=coalesce(completed_at,v_now),completed_by=auth.uid() where id=s.id;
    end if;
    if r.request_type='swap' then
      if p_replacement_guard_id is null or p_replacement_guard_id=r.requester_id then
        raise exception 'Select a different active Guard for the remaining duty.';
      end if;
      select * into replacement from public.profiles where id=p_replacement_guard_id
        and organization_id=r.organization_id and active and role='user' for share;
      if not found then raise exception 'Choose an active Guard in your agency.'; end if;
      v_start:=greatest(s.start_at,v_now);
      if v_start>=s.end_at then raise exception 'This duty has ended; there is no remaining period to cover.'; end if;
      if exists(select 1 from public.schedules other where other.user_id=replacement.id
        and other.organization_id=r.organization_id and other.approval_status in ('approved','changed')
        and other.start_at<s.end_at and other.end_at>v_start) then
        raise exception 'The replacement Guard already has an overlapping duty.';
      end if;
      insert into public.schedules(organization_id,user_id,location_id,location_label,location_address,
        guard_name,start_at,end_at,duty_date,dtr_period,duty_category,duty_days,approval_status,approved_by)
      values(r.organization_id,replacement.id,s.location_id,s.location_label,s.location_address,
        trim(concat_ws(' ',replacement.first_name,replacement.middle_initial,replacement.last_name)),
        v_start,s.end_at,s.duty_date,s.dtr_period,replacement.employment_category,1,'approved',auth.uid())
      returning id into new_schedule;
    end if;
    update public.schedules set approval_status='cancelled',approved_by=auth.uid() where id=s.id;
  end if;
  update public.shift_swap_requests set status=case when p_approve then 'approved' else 'rejected' end,
    target_guard_id=case when p_approve and r.request_type='swap' then p_replacement_guard_id else target_guard_id end,
    replacement_schedule_id=new_schedule,admin_decision_by=auth.uid(),admin_decision_at=v_now,
    admin_note=v_note,updated_at=v_now where id=r.id;
end;
$$;
revoke all on function public.decide_duty_relief(uuid,boolean,text,uuid,timestamptz) from public,anon;
grant execute on function public.decide_duty_relief(uuid,boolean,text,uuid,timestamptz) to authenticated;
create or replace function private.decide_legacy_duty_request(p_request_id uuid,p_approve boolean,
  p_note text default '',p_replacement_guard_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin perform public.decide_duty_relief(p_request_id,p_approve,p_note,p_replacement_guard_id); end;
$$;

-- Save every guard in a 24-hour roster atomically. A failed slot rolls back all slots.
create function public.create_shift_roster(p_location_id uuid,p_duty_date date,
  p_shift_count integer,p_guard_ids uuid[])
returns setof public.schedules language plpgsql security definer set search_path='' as $$
declare i integer; starts text[]; ends text[]; v_key bigint;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operational Head can assign a shift roster.' using errcode='42501';
  end if;
  if p_shift_count is null or p_shift_count not in (2,3) or cardinality(p_guard_ids) is distinct from p_shift_count
    or (select count(distinct g) from unnest(p_guard_ids) g)<>p_shift_count then
    raise exception 'Choose a different Guard for each of the 2 or 3 shifts.';
  end if;
  for v_key in select distinct pg_catalog.hashtextextended(public.current_organization_id()::text||':'||g::text,0)
    from unnest(p_guard_ids) g order by 1 loop perform pg_catalog.pg_advisory_xact_lock(v_key); end loop;
  if exists(select 1 from unnest(p_guard_ids) g where not exists(select 1 from public.profiles p
    where p.id=g and p.organization_id=public.current_organization_id() and p.active and p.role='user')) then
    raise exception 'All assigned Guards must be active in your agency.';
  end if;
  starts:=case when p_shift_count=2 then array['06:00','18:00'] else array['06:00','14:00','22:00'] end;
  ends:=case when p_shift_count=2 then array['18:00','06:00'] else array['14:00','22:00','06:00'] end;
  for i in 1..p_shift_count loop
    return query select * from public.create_dtr_schedule(p_guard_ids[i],p_location_id,p_duty_date,
      jsonb_build_array(jsonb_build_object('period','auto','start_time',starts[i],'end_time',ends[i],'next_day',false)));
  end loop;
end;
$$;
revoke all on function public.create_shift_roster(uuid,date,integer,uuid[]) from public,anon;
grant execute on function public.create_shift_roster(uuid,date,integer,uuid[]) to authenticated;
notify pgrst,'reload schema';

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

