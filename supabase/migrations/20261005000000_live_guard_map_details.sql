create or replace function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('server_now',now(),'locations',coalesce((
    select jsonb_agg(to_jsonb(g)||jsonb_build_object(
      'location_label',concat_ws(' · ',coalesce(nullif(l.label,''),g.location_label),nullif(l.address,'')),
      'client_name',coalesce(nullif(l.label,''),g.location_label),
      'location_address',nullif(l.address,''),
      'mobile_number',p.mobile_number))
    from public.list_live_guard_locations() g
    join public.profiles p on p.id=g.user_id
    join public.attendance_sessions a on a.id=g.session_id
    left join public.schedules s on s.id=a.schedule_id
    left join public.locations l on l.id=s.location_id and l.organization_id=s.organization_id
  ),'[]'::jsonb));
$$;
revoke all on function public.live_guard_map_snapshot() from public,anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;
notify pgrst,'reload schema';
