-- Regression checks for server-side attendance location validation.
do $$
declare
  v_legacy_definition text;
  v_legacy_core_definition text;
  v_event_definition text;
  v_event_core_definition text;
begin
  select pg_get_functiondef(
    'public.record_attendance_punch(text,double precision,double precision,boolean,text)'::regprocedure
  ) into v_legacy_definition;

  if v_legacy_definition not like '%public.is_active_guard()%'
    or v_legacy_definition not like '%record_attendance_punch_for_guard_internal%'
  then
    raise exception 'legacy attendance RPC is not Guard-only';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_punch_for_guard_internal(text,double precision,double precision,boolean,text)'::regprocedure
  ) into v_legacy_core_definition;
  if v_legacy_core_definition not like '%perform p_within_geofence%'
    or v_legacy_core_definition like '%or not p_within_geofence%'
  then
    raise exception 'private legacy attendance implementation must not trust the client geofence flag';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure
  ) into v_event_definition;
  if v_event_definition not like '%public.is_active_guard()%'
    or v_event_definition not like '%record_attendance_event_for_guard_internal%'
  then
    raise exception 'record_attendance_event is not Guard-only';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure
  ) into v_event_core_definition;
  if v_event_core_definition not like '%p_latitude not between -90 and 90%'
    or v_event_core_definition not like '%p_longitude not between -180 and 180%'
    or v_event_core_definition not like '%organization_id = v_organization_id%'
  then
    raise exception 'private Guard attendance implementation is missing coordinate or tenant validation';
  end if;
end;
$$;
