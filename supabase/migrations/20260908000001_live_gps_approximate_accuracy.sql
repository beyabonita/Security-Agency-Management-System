-- Keep approximate positions visible with their measured accuracy circle.
-- This only changes live map accuracy; attendance geofence checks are unchanged.
alter table public.guard_live_locations drop constraint guard_live_locations_accuracy_meters_check;
alter table public.guard_live_locations add constraint guard_live_locations_accuracy_meters_check
  check (accuracy_meters > 0 and accuracy_meters <= 500);
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
    or not(p_accuracy_meters>0 and p_accuracy_meters<=500)
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

