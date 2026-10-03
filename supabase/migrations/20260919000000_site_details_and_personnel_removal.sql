alter table public.profiles add column if not exists removed_at timestamptz;
create or replace function private.guard_deployment_label(p_guard uuid,p_org uuid,p_at timestamptz)
returns text language sql stable security definer set search_path='' as $$
  select coalesce(
    (select concat_ws(' · ',coalesce(nullif(l.label,''),nullif(s.location_label,'')),nullif(l.address,''))
     from public.schedules s left join public.locations l on l.id=s.location_id and l.organization_id=p_org
     where s.user_id=p_guard and s.organization_id=p_org and s.approval_status in ('approved','changed')
       and (p_at between s.start_at and s.end_at or exists(select 1 from public.attendance_sessions a where a.schedule_id=s.id and a.clock_in_at<=p_at and coalesce(a.clock_out_at,now())>=p_at))
     order by s.start_at desc limit 1),
    (select concat_ws(' · ',l.label,nullif(l.address,'')) from public.profiles p join public.locations l on l.id=p.assigned_location_id and l.organization_id=p_org where p.id=p_guard and p.organization_id=p_org)
  );
$$;
revoke all on function private.guard_deployment_label(uuid,uuid,timestamptz) from public,anon,authenticated;
create or replace function private.attach_incident_deployment_site()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.location_label:=coalesce(private.guard_deployment_label(new.user_id,new.organization_id,coalesce(new.captured_at,new.created_at,now())),nullif(trim(new.location_label),''));
  return new;
end; $$;
revoke all on function private.attach_incident_deployment_site() from public,anon,authenticated;
create trigger attach_incident_deployment_site before insert on public.incidents for each row execute function private.attach_incident_deployment_site();
create or replace function public.incident_deployment_site(p_incident_id uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare i public.incidents;
begin
  select * into i from public.incidents where id=p_incident_id;
  if not found or not private.can_view_personnel(i.user_id,i.organization_id) then
    raise exception 'This incident is not available to you.' using errcode='42501';
  end if;
  return coalesce(nullif(i.location_label,''),private.guard_deployment_label(i.user_id,i.organization_id,coalesce(i.captured_at,i.created_at)),'No assigned deployment site');
end; $$;
revoke all on function public.incident_deployment_site(uuid) from public,anon;
grant execute on function public.incident_deployment_site(uuid) to authenticated;
create or replace function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('server_now',now(),'locations',coalesce((
    select jsonb_agg(to_jsonb(g)||jsonb_build_object('location_label',concat_ws(' · ',coalesce(nullif(l.label,''),g.location_label),nullif(l.address,''))))
    from public.list_live_guard_locations() g
    join public.attendance_sessions a on a.id=g.session_id
    left join public.schedules s on s.id=a.schedule_id
    left join public.locations l on l.id=s.location_id and l.organization_id=s.organization_id
  ),'[]'::jsonb));
$$;
revoke all on function public.live_guard_map_snapshot() from public,anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;
notify pgrst,'reload schema';