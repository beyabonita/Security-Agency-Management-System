-- Regression checks for Inspector lifecycle protection.
do $$
declare
  v_function_definition text;
  v_trigger_definition text;
begin
  select pg_get_functiondef(
    'public.validate_profile_inspector_assignment()'::regprocedure
  ) into v_function_definition;
  if v_function_definition not like '%old.role = ''inspector''%'
    or v_function_definition not like '%new.active is false%'
    or v_function_definition not like '%Reassign or clear all Guard Inspector assignments%'
  then
    raise exception 'Inspector lifecycle validation is incomplete';
  end if;

  select pg_get_triggerdef(trigger.oid)
  from pg_trigger trigger
  where trigger.tgrelid = 'public.profiles'::regclass
    and trigger.tgname = 'validate_profile_inspector_assignment'
    and not trigger.tgisinternal
  into v_trigger_definition;
  if v_trigger_definition is null
    or v_trigger_definition not like '%UPDATE OF inspector_id, organization_id, role, active%'
  then
    raise exception 'Inspector lifecycle trigger must also validate active status';
  end if;
end;
$$;
