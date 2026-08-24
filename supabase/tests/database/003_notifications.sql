begin;

create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

select has_table('public', 'user_notifications', 'Notification inbox exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_notifications'::regclass),
  'Notification inbox has RLS enabled'
);
select ok(
  has_table_privilege('authenticated', 'public.user_notifications', 'SELECT')
    and not has_table_privilege('authenticated', 'public.user_notifications', 'INSERT')
    and not has_table_privilege('authenticated', 'public.user_notifications', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.user_notifications', 'DELETE'),
  'Clients can only select notification rows'
);
select policies_are(
  'public',
  'user_notifications',
  array['users read their notifications'],
  'Only the recipient-read policy exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.insert_user_notification(uuid,uuid,text,text,text,text,text,text,uuid,jsonb,boolean,uuid,text,timestamptz)'::regprocedure,
    'EXECUTE'
  ),
  'Private notification insertion cannot be called by clients'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.notify_incident_event()'::regprocedure,
    'EXECUTE'
  ) and not has_function_privilege(
    'anon',
    'public.notify_schedule_event()'::regprocedure,
    'EXECUTE'
  ),
  'Notification trigger helpers cannot be invoked by clients'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.mark_notification_read(uuid)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated users can mark their notification read through the RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.acknowledge_notification(uuid)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated users can acknowledge their critical notification'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.acknowledge_notification(uuid)'::regprocedure,
    'EXECUTE'
  ),
  'Anonymous users cannot acknowledge notifications'
);
select has_trigger(
  'public', 'incidents', 'notify_incident_event',
  'Incidents generate routed emergency notifications'
);
select has_trigger(
  'public', 'schedules', 'notify_schedule_event',
  'Schedule changes generate Guard notifications'
);
select has_trigger(
  'public', 'shift_swap_requests', 'notify_shift_request_event',
  'Shift workflow changes generate routed notifications'
);
select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_notifications'
  ),
  'Notification inbox is published through Supabase Realtime'
);

select * from finish();
rollback;
