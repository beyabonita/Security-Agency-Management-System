-- Explicit guard choice for late Time Out. Preserve submission time separately
-- from the DTR end when the guard declares no overtime.
alter table public.attendance_sessions
  add column timeout_submitted_at timestamptz,
  add column overtime_requested boolean;

create function public.record_guard_timeout(
  p_session_id uuid, p_latitude double precision, p_longitude double precision,
  p_claim_overtime boolean default null
) returns public.attendance_sessions
language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid := public.current_organization_id();
  v_now timestamptz;
  v_session public.attendance_sessions;
  v_post public.locations;
  v_late boolean;
begin
  if not coalesce(public.is_active_guard(),false) or v_org is null
    or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only active Guard accounts can record Time Out.' using errcode='42501';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'A current location is required to record attendance.';
  end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'Location coordinates are invalid.';
  end if;
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text || ':' || auth.uid()::text,0));
  select * into v_session from public.attendance_sessions
    where id=p_session_id and user_id=auth.uid() and organization_id=v_org for update;
  if not found then raise exception 'Attendance record was not found.' using errcode='42501'; end if;
  -- Retrying the same request must not close a different session or change its choice.
  if v_session.timeout_submitted_at is not null then
    if v_session.overtime_requested is distinct from coalesce(p_claim_overtime,false) then
      raise exception 'This Time Out was already submitted with a different overtime choice. Refresh your attendance.';
    end if;
    return v_session;
  end if;
  if v_session.status <> 'open' or v_session.clock_out_at is not null then
    raise exception 'This duty is no longer open. Ask your Operations Head to review a missing Time Out.';
  end if;
  if exists(select 1 from public.attendance_sessions other
    where other.user_id=auth.uid() and other.organization_id=v_org and other.id<>v_session.id
      and other.clock_in_at>=v_session.clock_in_at) then
    raise exception 'A newer duty has started. Ask your Operations Head to review the earlier Time Out.';
  end if;
  select * into v_post from public.locations where id=v_session.location_id and organization_id=v_org;
  if not found or v_post.latitude is null or v_post.longitude is null
    or v_post.radius_meters is null or v_post.radius_meters<=0 then
    raise exception 'The duty post location is unavailable. Ask your Operations Head to check it.';
  end if;
  if 6371000 * acos(least(1.0,greatest(-1.0,
    cos(radians(v_post.latitude))*cos(radians(p_latitude))*cos(radians(p_longitude)-radians(v_post.longitude))+
    sin(radians(v_post.latitude))*sin(radians(p_latitude))))) > v_post.radius_meters then
    raise exception 'Time Out is allowed only within the geofence of the post where you timed in.';
  end if;
  v_now := clock_timestamp();
  v_late := v_now > v_session.scheduled_end_at;
  if v_late and p_claim_overtime is null then
    raise exception 'Your shift has ended. Tap Time Out again and choose whether you worked overtime.';
  end if;
  if not v_late and p_claim_overtime is true then
    raise exception 'Overtime can be requested only after the scheduled shift end.';
  end if;
  if v_now < v_session.clock_in_at or (v_late and p_claim_overtime is false and v_session.scheduled_end_at < v_session.clock_in_at) then
    raise exception 'The Time Out would be earlier than Time In. Ask your Operations Head to review it.';
  end if;
  update public.attendance_sessions set
    clock_out_at=case when v_late and p_claim_overtime is false then scheduled_end_at else v_now end,
    timeout_submitted_at=v_now, overtime_requested=v_late and coalesce(p_claim_overtime,false),
    clock_out_latitude=p_latitude,clock_out_longitude=p_longitude,clock_out_location_status='verified',
    status='closed',updated_at=v_now
    where id=v_session.id returning * into v_session;
  if not v_session.overtime_requested then perform public.complete_schedule(v_session.schedule_id); end if;
  return v_session;
end;
$$;
revoke all on function public.record_guard_timeout(uuid,double precision,double precision,boolean) from public,anon;
grant execute on function public.record_guard_timeout(uuid,double precision,double precision,boolean) to authenticated;

create function public.notify_overtime_timeout() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_head record; v_guard_name text;
begin
  if new.overtime_requested is true and old.timeout_submitted_at is null and new.timeout_submitted_at is not null then
    select coalesce(nullif(trim(concat_ws(' ', first_name, last_name)),''),'A guard') into v_guard_name
      from public.profiles where id=new.user_id;
    for v_head in select id from public.profiles where organization_id=new.organization_id and active and role='admin' loop
      perform public.insert_user_notification(v_head.id,new.organization_id,'system','normal',
        'Overtime Time Out awaiting approval',
        v_guard_name || ' submitted an overtime Time Out for duty ' || new.duty_date::text || ' at ' || coalesce(nullif(new.location_label,''),'the assigned post') || '. Review it in Personnel > View DTR.',
        'personnel','attendance_session',new.id,jsonb_build_object('guard_id',new.user_id,'session_id',new.id),false,new.user_id,'overtime-timeout:'||new.id::text);
    end loop;
  elsif new.overtime_requested is true and old.timeout_verified_at is null and new.timeout_verified_at is not null then
    perform public.insert_user_notification(new.user_id,new.organization_id,'system','normal','Overtime Time Out reviewed',
      'Your Operations Head reviewed your Time Out for duty ' || new.duty_date::text || '. Your DTR now shows the verified time and hours.',
      'system','attendance_session',new.id,jsonb_build_object('session_id',new.id),false,new.timeout_verified_by,'overtime-reviewed:'||new.id::text);
  end if;
  return new;
end;
$$;
revoke all on function public.notify_overtime_timeout() from public,anon,authenticated;
create trigger attendance_overtime_timeout_notification after update on public.attendance_sessions
  for each row execute function public.notify_overtime_timeout();
notify pgrst,'reload schema';
