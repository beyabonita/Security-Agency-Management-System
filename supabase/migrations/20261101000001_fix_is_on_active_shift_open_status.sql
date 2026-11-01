-- Fix public.is_on_active_shift() so clocked-in attendance sessions (status = 'open')
-- are recognized when guards file an Emergency Alert via public.file_incident_report().
-- In public.attendance_sessions, the active clocked-in status is 'open'
-- (constraint: status in ('open', 'closed', 'missed_timeout')).

create or replace function public.is_on_active_shift()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.attendance_sessions s
    where s.user_id = auth.uid()
      and s.organization_id = public.current_organization_id()
      and s.clock_in_at is not null
      and s.clock_out_at is null
      and s.status in ('open', 'clocked_in', 'active', 'pending_timeout', 'pending_review')
  );
$$;

revoke all on function public.is_on_active_shift() from public, anon;
grant execute on function public.is_on_active_shift() to authenticated;
comment on function public.is_on_active_shift() is
  'Returns true when the authenticated user has an open, unfinished attendance session (clocked-in, not yet clocked-out).';

notify pgrst, 'reload schema';
