-- Static regression checks for the legacy RPCs that execute with elevated rights.
do $$
declare
  v_device_definition text;
  v_complete_definition text;
  v_evaluate_definition text;
  v_trigger_definition text;
begin
  select pg_get_functiondef('public.register_device(text)'::regprocedure) into v_device_definition;
  if v_device_definition not like '%public.is_active_guard()%'
    or v_device_definition not like '%organization_id = v_organization_id%'
  then
    raise exception 'register_device is missing active-organization validation';
  end if;

  select pg_get_functiondef('public.complete_schedule(uuid)'::regprocedure) into v_complete_definition;
  if v_complete_definition not like '%organization_id = v_organization_id%'
    or v_complete_definition not like '%public.is_active_duty_personnel()%'
  then
    raise exception 'complete_schedule is missing tenant validation';
  end if;

  select pg_get_functiondef('public.evaluate_time_record(uuid,date,date)'::regprocedure) into v_evaluate_definition;
  if v_evaluate_definition not like '%s.organization_id = v_organization_id%'
    or v_evaluate_definition not like '%session.organization_id = v_organization_id%'
  then
    raise exception 'evaluate_time_record is missing tenant filters';
  end if;

  select pg_get_functiondef('public.prevent_overlapping_active_schedules()'::regprocedure) into v_trigger_definition;
  if v_trigger_definition not like '%existing.organization_id = new.organization_id%' then
    raise exception 'schedule overlap guard is missing its tenant filter';
  end if;
end;
$$;
