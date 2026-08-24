-- Regression checks for tenant-safe, acknowledgement-capable notifications.
do $$
declare
  v_incident_definition text;
  v_broadcast_definition text;
begin
  if not exists (
    select 1 from pg_class
    where oid = 'public.user_notifications'::regclass
      and relrowsecurity
  ) then
    raise exception 'Notification inbox must have RLS enabled';
  end if;

  if not has_table_privilege('authenticated', 'public.user_notifications', 'SELECT')
    or has_table_privilege('authenticated', 'public.user_notifications', 'INSERT')
    or has_table_privilege('authenticated', 'public.user_notifications', 'UPDATE')
    or has_table_privilege('authenticated', 'public.user_notifications', 'DELETE')
  then
    raise exception 'Authenticated notification table privileges are unsafe';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'user_notifications'
      and policyname = 'users read their notifications'
      and cmd = 'SELECT'
      and qual like '%recipient_id = ( SELECT auth.uid() AS uid)%'
  ) then
    raise exception 'Recipient-only notification read policy is missing';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.insert_user_notification(uuid,uuid,text,text,text,text,text,text,uuid,jsonb,boolean,uuid,text,timestamptz)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Clients can invoke the private notification insertion primitive';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.notify_incident_event()'::regprocedure,
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.notify_schedule_event()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'A notification trigger helper is client executable';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.acknowledge_notification(uuid)'::regprocedure,
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.acknowledge_notification(uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Notification acknowledgement RPC privileges are incorrect';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.incidents'::regclass
      and tgname = 'notify_incident_event'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.schedules'::regclass
      and tgname = 'notify_schedule_event'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.shift_swap_requests'::regclass
      and tgname = 'notify_shift_request_event'
      and not tgisinternal
  ) then
    raise exception 'One or more operational notification triggers are missing';
  end if;

  select pg_get_functiondef('public.notify_incident_event()'::regprocedure)
  into v_incident_definition;
  if v_incident_definition not like '%profile.role = ANY (ARRAY[''admin''::app_role, ''inspector''::app_role])%'
    or v_incident_definition like '%profile.role = ''it_admin''%'
    or v_incident_definition not like '%''critical''%'
  then
    raise exception 'Emergency notification routing is not Operations/Inspector-only and critical';
  end if;

  select pg_get_functiondef(
    'public.send_broadcast_notification(text,text,text,text,boolean)'::regprocedure
  ) into v_broadcast_definition;
  if v_broadcast_definition not like '%v_sender.role <> ALL (ARRAY[''it_admin''::app_role, ''admin''::app_role])%'
    or v_broadcast_definition not like '%profile.organization_id = v_organization_id%'
  then
    raise exception 'Broadcast notification authorization or tenant scope is missing';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_notifications'
  ) then
    raise exception 'Notification inbox is not in the realtime publication';
  end if;
end;
$$;
