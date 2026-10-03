-- Include authorized on-duty guards before their first fix. Null coordinates
-- mean waiting for GPS; clients must never place those guards at a default point.
create or replace function public.list_live_guard_locations()
returns table(user_id uuid,session_id uuid,guard_name text,location_label text,
  latitude double precision,longitude double precision,accuracy_meters double precision,
  captured_at timestamptz,received_at timestamptz,duty_end_at timestamptz)
language sql stable security definer set search_path='' as $$
  select s.user_id,s.id,trim(concat_ws(' ',p.first_name,p.last_name)),s.location_label,
    l.latitude,l.longitude,l.accuracy_meters,l.captured_at,l.received_at,s.scheduled_end_at
  from public.attendance_sessions s
  join public.profiles p on p.id=s.user_id and p.organization_id=s.organization_id
  join public.schedules d on d.id=s.schedule_id and d.user_id=s.user_id
    and d.organization_id=p.organization_id
  left join public.guard_live_locations l on l.session_id=s.id and l.user_id=s.user_id
    and l.received_at>now()-interval '24 hours'
  where private.can_view_live_guard(s.user_id)
    and s.status='open' and s.clock_out_at is null
    and s.clock_in_at<=now() and s.scheduled_end_at>now()
    and d.approval_status in('approved','changed') and not d.marked_done
  order by p.last_name,p.first_name,s.user_id;
$$;
revoke all on function public.list_live_guard_locations() from public,anon;
grant execute on function public.list_live_guard_locations() to authenticated;

-- Reuse private, supervisor-scoped invalidations for duty changes too, so a
-- Time In appears even before GPS is acquired and Time Out removes it promptly.
create trigger signal_guard_duty_location_change
after insert or update of status,clock_out_at,scheduled_end_at or delete
on public.attendance_sessions
for each row execute function private.signal_guard_location_change();
