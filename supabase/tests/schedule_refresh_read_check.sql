-- Read-only smoke check under an actual active Admin JWT subject. Return counts
-- only, never personnel names, credentials, attendance details or letter paths.
begin;
set local statement_timeout='15s';
do $$declare actor uuid; begin
  select p.id into actor from public.profiles p join public.organizations o on o.id=p.organization_id
    where p.role='admin' and p.active and o.active order by p.created_at limit 1;
  if actor is null then raise exception 'No active Admin available for read-only schedule verification.'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
end$$;
set local role authenticated;
select count(*) as readable_schedule_count,
  coalesce(sum((select count(*) from public.attendance_sessions a where a.schedule_id=s.id)),0) as attendance_links,
  coalesce(sum((select count(*) from public.accomplishment_reports a where a.schedule_id=s.id)),0) as accomplishment_links,
  coalesce(sum((select count(*) from public.shift_swap_requests r where r.requested_schedule_id=s.id)),0) as offered_request_links,
  coalesce(sum((select count(*) from public.shift_swap_requests r where r.target_schedule_id=s.id)),0) as target_request_links
from public.schedules s;
rollback;
