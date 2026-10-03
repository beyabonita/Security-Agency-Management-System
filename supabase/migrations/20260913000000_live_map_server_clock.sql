-- Return the authorized snapshot and its clock together, including empty lists.
-- A viewer's incorrect device clock must not hide freshly received GPS fixes.
create function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('server_now',now(),'locations',coalesce(
    (select jsonb_agg(to_jsonb(location)) from public.list_live_guard_locations() location),'[]'::jsonb));
$$;
revoke all on function public.live_guard_map_snapshot() from public,anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;
notify pgrst,'reload schema';
