-- Align server-side messages with the simplified three-role model.
create or replace function public.assign_guard_location(p_guard_id uuid, p_location_id uuid, p_remarks text default '') returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operations_staff() then raise exception 'Only an Admin can manage Home Posts.'; end if;
  if not exists (select 1 from public.profiles where id=p_guard_id and role='user') then raise exception 'Guard not found.'; end if;
  if not exists (select 1 from public.locations where id=p_location_id and active) then raise exception 'Active duty location not found.'; end if;
  update public.guard_assignment_history set ended_at=now() where guard_id=p_guard_id and ended_at is null;
  insert into public.guard_assignment_history(guard_id,location_id,assigned_by,remarks) values(p_guard_id,p_location_id,auth.uid(),left(coalesce(p_remarks,''),1500));
  update public.profiles set assigned_location_id=p_location_id where id=p_guard_id;
end $$;

create or replace function public.decide_shift_swap_by_admin(p_request_id uuid,p_approve boolean,p_note text default '') returns void language plpgsql security definer set search_path=public as $$
declare r public.shift_swap_requests%rowtype;
begin
 if not public.is_operations_staff() then raise exception 'Only an Admin can finalize a schedule change.'; end if;
 select * into r from public.shift_swap_requests where id=p_request_id and status='pending_admin' for update; if not found then raise exception 'Request is not awaiting final approval.'; end if;
 if p_approve then update public.schedules set user_id=coalesce(r.target_guard_id,user_id),start_at=coalesce(r.requested_start_at,start_at),end_at=coalesce(r.requested_end_at,end_at),approval_status='changed',approved_by=auth.uid() where id=r.requested_schedule_id; end if;
 update public.shift_swap_requests set status=case when p_approve then 'approved' else 'rejected' end,admin_decision_by=auth.uid(),admin_decision_at=now(),admin_note=left(coalesce(p_note,''),1500),updated_at=now() where id=p_request_id;
end $$;
