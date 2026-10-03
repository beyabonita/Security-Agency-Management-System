begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
-- Local implementation. Do not push to the hosted project before deployment approval.
-- One latest fix per guard; no movement-history table.
create table public.guard_live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision not null check (accuracy_meters > 0 and accuracy_meters <= 100),
  captured_at timestamptz not null,
  received_at timestamptz not null default now()
);
alter table public.guard_live_locations enable row level security;
revoke all on public.guard_live_locations from public,anon,authenticated;
grant select on public.guard_live_locations to authenticated;

create or replace function private.can_view_live_guard(p_guard uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.profiles g
    join public.organizations o on o.id=g.organization_id and o.active
    join public.profiles viewer on viewer.id=auth.uid() and viewer.active
      and viewer.organization_id=g.organization_id
    where g.id=p_guard and g.active and g.role='user'
      and (viewer.role='admin' or (viewer.role='inspector' and g.inspector_id=viewer.id))
  );
$$;
revoke all on function private.can_view_live_guard(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.can_view_live_guard(uuid) to authenticated;

create policy "authorized live location viewers" on public.guard_live_locations
for select to authenticated using (
  private.can_view_live_guard(user_id)
  and exists(select 1 from public.attendance_sessions s
    join public.profiles g on g.id=s.user_id and g.organization_id=s.organization_id
    join public.schedules d on d.id=s.schedule_id and d.user_id=s.user_id and d.organization_id=s.organization_id
    where s.id=session_id and s.user_id=guard_live_locations.user_id
    and s.status='open' and s.clock_out_at is null and s.scheduled_end_at > now()
    and d.approval_status in('approved','changed') and not d.marked_done)
);

create or replace function public.publish_guard_location(
  p_session_id uuid,p_latitude double precision,p_longitude double precision,
  p_accuracy_meters double precision,p_captured_at timestamptz,p_is_mocked boolean
) returns void language plpgsql security definer set search_path='' as $$
declare s public.attendance_sessions; v_now timestamptz:=clock_timestamp();
begin
  if auth.uid() is null then raise exception 'Sign in to share your duty location.' using errcode='42501'; end if;
  -- Share lock serializes clock-out/deletion against publication.
  select * into s from public.attendance_sessions where id=p_session_id and user_id=auth.uid() for update;
  if not found or s.status<>'open' or s.clock_out_at is not null
    or s.clock_in_at>v_now or s.scheduled_end_at<=v_now
    or not exists(select 1 from public.profiles p join public.organizations o on o.id=p.organization_id
      where p.id=auth.uid() and p.active and p.role='user' and o.active and p.organization_id=s.organization_id)
    or not exists(select 1 from public.schedules d where d.id=s.schedule_id and d.user_id=s.user_id
      and d.organization_id=s.organization_id and d.approval_status in('approved','changed') and not d.marked_done) then
    raise exception 'Location sharing requires your active, clocked-in duty.' using errcode='42501';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null or p_captured_at is null
    or p_is_mocked is distinct from false
    or not(p_latitude between -90 and 90) or not(p_longitude between -180 and 180)
    or not(p_accuracy_meters>0 and p_accuracy_meters<=100)
    or p_captured_at < v_now-interval '45 seconds' or p_captured_at>v_now+interval '5 seconds'
    or p_captured_at<s.clock_in_at then
    raise exception 'A fresh, accurate, non-mock GPS fix is required.' using errcode='22023';
  end if;
  insert into public.guard_live_locations(user_id,session_id,latitude,longitude,accuracy_meters,captured_at,received_at)
  values(auth.uid(),s.id,p_latitude,p_longitude,p_accuracy_meters,p_captured_at,v_now)
  on conflict(user_id) do update set session_id=excluded.session_id,latitude=excluded.latitude,
    longitude=excluded.longitude,accuracy_meters=excluded.accuracy_meters,
    captured_at=excluded.captured_at,received_at=excluded.received_at
  where excluded.captured_at>guard_live_locations.captured_at;
end $$;
revoke all on function public.publish_guard_location(uuid,double precision,double precision,double precision,timestamptz,boolean) from public,anon;
grant execute on function public.publish_guard_location(uuid,double precision,double precision,double precision,timestamptz,boolean) to authenticated;

create or replace function public.stop_guard_location(p_session_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.attendance_sessions where id=p_session_id and user_id=auth.uid() for update;
  delete from public.guard_live_locations where user_id=auth.uid() and session_id=p_session_id;
end $$;
revoke all on function public.stop_guard_location(uuid) from public,anon;
grant execute on function public.stop_guard_location(uuid) to authenticated;

create or replace function public.list_live_guard_locations()
returns table(user_id uuid,session_id uuid,guard_name text,location_label text,
  latitude double precision,longitude double precision,accuracy_meters double precision,
  captured_at timestamptz,received_at timestamptz,duty_end_at timestamptz)
language sql stable security definer set search_path='' as $$
  select l.user_id,l.session_id,trim(concat_ws(' ',p.first_name,p.last_name)),s.location_label,
    l.latitude,l.longitude,l.accuracy_meters,l.captured_at,l.received_at,s.scheduled_end_at
  from public.guard_live_locations l join public.profiles p on p.id=l.user_id
  join public.attendance_sessions s on s.id=l.session_id and s.user_id=l.user_id
  join public.schedules d on d.id=s.schedule_id and d.user_id=s.user_id and d.organization_id=p.organization_id
  where private.can_view_live_guard(l.user_id) and s.organization_id=p.organization_id
    and s.status='open' and s.clock_out_at is null and s.scheduled_end_at>now()
    and d.approval_status in('approved','changed') and not d.marked_done
    and l.received_at>now()-interval '24 hours'
  order by p.last_name,p.first_name,l.user_id;
$$;
revoke all on function public.list_live_guard_locations() from public,anon;
grant execute on function public.list_live_guard_locations() to authenticated;

create or replace function private.clear_closed_guard_location()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status<>'open' or new.clock_out_at is not null then
    delete from public.guard_live_locations where session_id=new.id;
  end if;
  return new;
end $$;
revoke all on function private.clear_closed_guard_location() from public,anon,authenticated;
create trigger clear_closed_guard_location after update of status,clock_out_at on public.attendance_sessions
for each row execute function private.clear_closed_guard_location();

-- Private, per-viewer invalidations carry no coordinates or guard identifiers.
-- Do not publish the location table: Postgres DELETE events do not apply RLS.
create policy "receive own live location signals" on realtime.messages
for select to authenticated using (
  realtime.topic()='live-guards:'||(select auth.uid())::text
  and exists(select 1 from public.profiles p join public.organizations o on o.id=p.organization_id
    where p.id=(select auth.uid()) and p.active and p.role in('admin','inspector') and o.active)
);

create or replace function private.signal_guard_location_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_guard uuid; viewer record;
begin
  v_guard:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  for viewer in
    select p.id from public.profiles g
    join public.organizations o on o.id=g.organization_id and o.active
    join public.profiles p on p.organization_id=g.organization_id and p.active
    where g.id=v_guard and (p.role='admin' or (p.role='inspector' and p.id=g.inspector_id))
  loop
    perform realtime.send('{}'::jsonb,'location_changed','live-guards:'||viewer.id::text,true);
  end loop;
  return null;
end $$;
revoke all on function private.signal_guard_location_change() from public,anon,authenticated;
create trigger signal_guard_location_change after insert or update or delete on public.guard_live_locations
for each row execute function private.signal_guard_location_change();

insert into supabase_migrations.schema_migrations(version,name,statements) values ('20260907000000','live_guard_locations',ARRAY[$migration$-- Local implementation. Do not push to the hosted project before deployment approval.
-- One latest fix per guard; no movement-history table.
create table public.guard_live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision not null check (accuracy_meters > 0 and accuracy_meters <= 100),
  captured_at timestamptz not null,
  received_at timestamptz not null default now()
);
alter table public.guard_live_locations enable row level security;
revoke all on public.guard_live_locations from public,anon,authenticated;
grant select on public.guard_live_locations to authenticated;

create or replace function private.can_view_live_guard(p_guard uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.profiles g
    join public.organizations o on o.id=g.organization_id and o.active
    join public.profiles viewer on viewer.id=auth.uid() and viewer.active
      and viewer.organization_id=g.organization_id
    where g.id=p_guard and g.active and g.role='user'
      and (viewer.role='admin' or (viewer.role='inspector' and g.inspector_id=viewer.id))
  );
$$;
revoke all on function private.can_view_live_guard(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.can_view_live_guard(uuid) to authenticated;

create policy "authorized live location viewers" on public.guard_live_locations
for select to authenticated using (
  private.can_view_live_guard(user_id)
  and exists(select 1 from public.attendance_sessions s
    join public.profiles g on g.id=s.user_id and g.organization_id=s.organization_id
    join public.schedules d on d.id=s.schedule_id and d.user_id=s.user_id and d.organization_id=s.organization_id
    where s.id=session_id and s.user_id=guard_live_locations.user_id
    and s.status='open' and s.clock_out_at is null and s.scheduled_end_at > now()
    and d.approval_status in('approved','changed') and not d.marked_done)
);

create or replace function public.publish_guard_location(
  p_session_id uuid,p_latitude double precision,p_longitude double precision,
  p_accuracy_meters double precision,p_captured_at timestamptz,p_is_mocked boolean
) returns void language plpgsql security definer set search_path='' as $$
declare s public.attendance_sessions; v_now timestamptz:=clock_timestamp();
begin
  if auth.uid() is null then raise exception 'Sign in to share your duty location.' using errcode='42501'; end if;
  -- Share lock serializes clock-out/deletion against publication.
  select * into s from public.attendance_sessions where id=p_session_id and user_id=auth.uid() for update;
  if not found or s.status<>'open' or s.clock_out_at is not null
    or s.clock_in_at>v_now or s.scheduled_end_at<=v_now
    or not exists(select 1 from public.profiles p join public.organizations o on o.id=p.organization_id
      where p.id=auth.uid() and p.active and p.role='user' and o.active and p.organization_id=s.organization_id)
    or not exists(select 1 from public.schedules d where d.id=s.schedule_id and d.user_id=s.user_id
      and d.organization_id=s.organization_id and d.approval_status in('approved','changed') and not d.marked_done) then
    raise exception 'Location sharing requires your active, clocked-in duty.' using errcode='42501';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null or p_captured_at is null
    or p_is_mocked is distinct from false
    or not(p_latitude between -90 and 90) or not(p_longitude between -180 and 180)
    or not(p_accuracy_meters>0 and p_accuracy_meters<=100)
    or p_captured_at < v_now-interval '45 seconds' or p_captured_at>v_now+interval '5 seconds'
    or p_captured_at<s.clock_in_at then
    raise exception 'A fresh, accurate, non-mock GPS fix is required.' using errcode='22023';
  end if;
  insert into public.guard_live_locations(user_id,session_id,latitude,longitude,accuracy_meters,captured_at,received_at)
  values(auth.uid(),s.id,p_latitude,p_longitude,p_accuracy_meters,p_captured_at,v_now)
  on conflict(user_id) do update set session_id=excluded.session_id,latitude=excluded.latitude,
    longitude=excluded.longitude,accuracy_meters=excluded.accuracy_meters,
    captured_at=excluded.captured_at,received_at=excluded.received_at
  where excluded.captured_at>guard_live_locations.captured_at;
end $$;
revoke all on function public.publish_guard_location(uuid,double precision,double precision,double precision,timestamptz,boolean) from public,anon;
grant execute on function public.publish_guard_location(uuid,double precision,double precision,double precision,timestamptz,boolean) to authenticated;

create or replace function public.stop_guard_location(p_session_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.attendance_sessions where id=p_session_id and user_id=auth.uid() for update;
  delete from public.guard_live_locations where user_id=auth.uid() and session_id=p_session_id;
end $$;
revoke all on function public.stop_guard_location(uuid) from public,anon;
grant execute on function public.stop_guard_location(uuid) to authenticated;

create or replace function public.list_live_guard_locations()
returns table(user_id uuid,session_id uuid,guard_name text,location_label text,
  latitude double precision,longitude double precision,accuracy_meters double precision,
  captured_at timestamptz,received_at timestamptz,duty_end_at timestamptz)
language sql stable security definer set search_path='' as $$
  select l.user_id,l.session_id,trim(concat_ws(' ',p.first_name,p.last_name)),s.location_label,
    l.latitude,l.longitude,l.accuracy_meters,l.captured_at,l.received_at,s.scheduled_end_at
  from public.guard_live_locations l join public.profiles p on p.id=l.user_id
  join public.attendance_sessions s on s.id=l.session_id and s.user_id=l.user_id
  join public.schedules d on d.id=s.schedule_id and d.user_id=s.user_id and d.organization_id=p.organization_id
  where private.can_view_live_guard(l.user_id) and s.organization_id=p.organization_id
    and s.status='open' and s.clock_out_at is null and s.scheduled_end_at>now()
    and d.approval_status in('approved','changed') and not d.marked_done
    and l.received_at>now()-interval '24 hours'
  order by p.last_name,p.first_name,l.user_id;
$$;
revoke all on function public.list_live_guard_locations() from public,anon;
grant execute on function public.list_live_guard_locations() to authenticated;

create or replace function private.clear_closed_guard_location()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status<>'open' or new.clock_out_at is not null then
    delete from public.guard_live_locations where session_id=new.id;
  end if;
  return new;
end $$;
revoke all on function private.clear_closed_guard_location() from public,anon,authenticated;
create trigger clear_closed_guard_location after update of status,clock_out_at on public.attendance_sessions
for each row execute function private.clear_closed_guard_location();

-- Private, per-viewer invalidations carry no coordinates or guard identifiers.
-- Do not publish the location table: Postgres DELETE events do not apply RLS.
create policy "receive own live location signals" on realtime.messages
for select to authenticated using (
  realtime.topic()='live-guards:'||(select auth.uid())::text
  and exists(select 1 from public.profiles p join public.organizations o on o.id=p.organization_id
    where p.id=(select auth.uid()) and p.active and p.role in('admin','inspector') and o.active)
);

create or replace function private.signal_guard_location_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_guard uuid; viewer record;
begin
  v_guard:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  for viewer in
    select p.id from public.profiles g
    join public.organizations o on o.id=g.organization_id and o.active
    join public.profiles p on p.organization_id=g.organization_id and p.active
    where g.id=v_guard and (p.role='admin' or (p.role='inspector' and p.id=g.inspector_id))
  loop
    perform realtime.send('{}'::jsonb,'location_changed','live-guards:'||viewer.id::text,true);
  end loop;
  return null;
end $$;
revoke all on function private.signal_guard_location_change() from public,anon,authenticated;
create trigger signal_guard_location_change after insert or update or delete on public.guard_live_locations
for each row execute function private.signal_guard_location_change();
$migration$]);
notify pgrst, 'reload schema';
commit;
