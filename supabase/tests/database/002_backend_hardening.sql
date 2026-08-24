begin;

create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(22);

select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'INSERT'),
  'Authenticated clients cannot directly insert profiles'
);
select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'UPDATE'),
  'Authenticated clients cannot directly update profiles'
);
select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'DELETE'),
  'Authenticated clients cannot directly delete profiles'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'No direct profile-mutation RLS policy remains'
);
select ok(
  (
    select with_check like '%post.organization_id = schedules.organization_id%'
      and with_check like '%personnel.organization_id = schedules.organization_id%'
    from pg_policies
    where schemaname = 'public'
      and tablename = 'schedules'
      and policyname = 'operations manages tenant schedules'
  ),
  'Schedule writes validate personnel and post tenant ownership'
);
select ok(
  pg_get_functiondef('public.prevent_overlapping_active_schedules()'::regprocedure)
    like '%pg_advisory_xact_lock%',
  'Schedule overlap validation serializes concurrent writes'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'protect_last_active_it_admin_update'
      and not tgisinternal
  ),
  'IT Admin update protection trigger exists'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'protect_last_active_it_admin_delete'
      and not tgisinternal
  ),
  'IT Admin deletion protection trigger exists'
);
select has_index(
  'public',
  'attendance_sessions',
  'attendance_sessions_one_open_per_user_idx',
  'Only one attendance session can remain open per user'
);
select has_index(
  'public',
  'guard_assignment_history',
  'guard_assignment_history_one_current_idx',
  'Only one current home-post assignment can remain per guard'
);
select has_index(
  'public',
  'shift_swap_requests',
  'shift_swap_requests_one_pending_schedule_idx',
  'Only one pending shift request can exist per schedule'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ),
  'Anonymous callers cannot execute attendance'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.prevent_historical_profile_deletion()'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated callers cannot execute private trigger helpers'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated clients retain access to the guarded attendance RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated clients cannot bypass the Guard-only attendance wrapper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_attendance_punch_for_guard_internal(text,double precision,double precision,boolean,text)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated clients cannot bypass the Guard-only legacy attendance wrapper'
);
select ok(
  has_function_privilege(
    'anon',
    'public.current_platform_announcement()'::regprocedure,
    'EXECUTE'
  ),
  'The public portal announcement remains anonymously readable'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.locations'::regclass
      and conname = 'locations_latitude_valid'
      and contype = 'c'
  ),
  'Deployment-site latitude is database validated'
);
select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and not coalesce(procedure.proconfig, '{}'::text[])
        @> array['search_path=public']::text[]
      and not coalesce(procedure.proconfig, '{}'::text[])
        @> array['search_path=public, storage']::text[]
  ),
  'Every SECURITY DEFINER function pins its search_path'
);
select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and procedure.oid <>
        'public.current_platform_announcement()'::regprocedure
      and has_function_privilege('anon', procedure.oid, 'EXECUTE')
  ),
  'No private SECURITY DEFINER function is executable by anonymous callers'
);
select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname in ('public', 'storage')
      and (
        (qual like '%auth.uid()%' and qual not like '%SELECT auth.uid() AS uid%')
        or (
          with_check like '%auth.uid()%'
          and with_check not like '%SELECT auth.uid() AS uid%'
        )
      )
  ),
  'RLS policies initialize auth.uid once per statement'
);
select ok(
  not exists (
    select schemaname, tablename, roles
    from pg_policies
    where schemaname in ('public', 'storage')
      and cmd in ('SELECT', 'ALL')
    group by schemaname, tablename, roles
    having count(*) > 1
  ),
  'Tables have no overlapping permissive read policies for the same roles'
);

select * from finish();
rollback;
