-- Regression checks for tenant-safe Inspector assignment.
do $$
declare
  v_function_definition text;
  v_trigger_definition text;
begin
  select pg_get_functiondef(
    'public.assign_guard_inspector(uuid,uuid)'::regprocedure
  ) into v_function_definition;
  if v_function_definition not like '%public.is_admin()%'
    or v_function_definition not like '%inspector.organization_id = v_organization_id%'
    or v_function_definition not like '%role = ''inspector''%'
    or v_function_definition not like '%role = ''user''%'
  then
    raise exception 'Inspector assignment lacks HR, tenant, or role validation';
  end if;

  select pg_get_functiondef(
    'public.validate_profile_inspector_assignment()'::regprocedure
  ) into v_trigger_definition;
  if v_trigger_definition not like '%new.organization_id%'
    or v_trigger_definition not like '%inspector.role = ''inspector''%'
  then
    raise exception 'Inspector assignment trigger lacks same-organization validation';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.profiles'::regclass
      and trigger.tgname = 'validate_profile_inspector_assignment'
      and not trigger.tgisinternal
  ) then
    raise exception 'Inspector assignment validation trigger is missing';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.assign_guard_inspector(uuid,uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'HR cannot call Inspector assignment function';
  end if;
end;
$$;
