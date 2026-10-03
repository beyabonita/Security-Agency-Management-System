-- Read-only status/clock diagnostics; no names or coordinates.
select clock_timestamp() as server_now,
  (select count(*) from public.attendance_sessions where status='open' and clock_out_at is null and scheduled_end_at>now()) as active_sessions,
  (select count(*) from public.attendance_sessions where status='open' and clock_out_at is null and scheduled_end_at<=now()) as ended_open_sessions,
  (select jsonb_agg(jsonb_build_object('session_open',s.status='open','has_timeout',s.clock_out_at is not null,
    'duty_end_at',s.scheduled_end_at,'captured_at',l.captured_at,'received_at',l.received_at,
    'guard_active',p.active,'agency_active',o.active,'approval',d.approval_status,'marked_done',d.marked_done))
   from public.guard_live_locations l join public.attendance_sessions s on s.id=l.session_id
   join public.profiles p on p.id=l.user_id join public.organizations o on o.id=p.organization_id
   join public.schedules d on d.id=s.schedule_id) as location_statuses;
