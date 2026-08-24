-- Regression checks for schedule-linked, overnight-safe attendance sessions.
do $$
declare
  v_event_definition text;
  v_event_core_definition text;
  v_legacy_definition text;
  v_legacy_core_definition text;
  v_evaluation_definition text;
begin
  if to_regclass('public.attendance_sessions') is null then
    raise exception 'attendance_sessions table is missing';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'attendance_sessions'
      and column_name in ('organization_id', 'schedule_id', 'duty_date', 'clock_in_at', 'clock_out_at')
    group by table_schema, table_name
    having count(*) = 5
  ) then
    raise exception 'attendance_sessions is missing required session columns';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.attendance_sessions'::regclass) then
    raise exception 'attendance_sessions must have RLS enabled';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure
  ) into v_event_definition;
  if v_event_definition not like '%public.is_active_guard()%'
    or v_event_definition not like '%record_attendance_event_for_guard_internal%'
  then
    raise exception 'record_attendance_event is not restricted to active Guards';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure
  ) into v_event_core_definition;
  if v_event_core_definition not like '%s.start_at - interval ''2 hours''%'
    or v_event_core_definition not like '%session.status = ''open''%'
    or v_event_core_definition not like '%v_duty.start_at at time zone ''Asia/Manila''%'
    or v_event_core_definition not like '%l.radius_meters%'
  then
    raise exception 'private Guard attendance implementation is missing schedule, overnight, or geofence validation';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_punch(text,double precision,double precision,boolean,text)'::regprocedure
  ) into v_legacy_definition;
  if v_legacy_definition not like '%public.is_active_guard()%'
    or v_legacy_definition not like '%record_attendance_punch_for_guard_internal%'
  then
    raise exception 'legacy attendance RPC is not restricted to active Guards';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_punch_for_guard_internal(text,double precision,double precision,boolean,text)'::regprocedure
  ) into v_legacy_core_definition;
  if v_legacy_core_definition not like '%perform p_within_geofence%'
    or v_legacy_core_definition not like '%public.record_attendance_event%'
  then
    raise exception 'private legacy attendance implementation must ignore client geofence data and delegate to sessions';
  end if;

  select pg_get_functiondef(
    'public.evaluate_time_record(uuid,date,date)'::regprocedure
  ) into v_evaluation_definition;
  if v_evaluation_definition not like '%public.attendance_sessions%'
    or v_evaluation_definition not like '%session.schedule_id = duty.id%'
    or v_evaluation_definition like '%attendance_punches%'
  then
    raise exception 'DTR evaluation must use schedule-linked attendance sessions only';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated Guards cannot call the guarded attendance RPC';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated clients can bypass the Guard-only attendance wrapper';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_attendance_punch_for_guard_internal(text,double precision,double precision,boolean,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated clients can bypass the Guard-only legacy attendance wrapper';
  end if;
end;
$$;
