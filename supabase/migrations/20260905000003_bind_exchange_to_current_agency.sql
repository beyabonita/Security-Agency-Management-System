-- Recheck agency authority at approval as well as submission. A moved personnel
-- pair must not make an old request authorize changes in a different workspace.
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
            (other.user_id = a.user_id and other.start_at < b.end_at and other.end_at > b.start_at)
            or (other.user_id = b.user_id and other.start_at < a.end_at and other.end_at > a.start_at)))
  );
$$;
