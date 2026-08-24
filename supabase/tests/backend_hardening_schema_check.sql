-- Regression checks for the final API/RPC privilege boundary and concurrency
-- invariants introduced by the backend hardening pass.
do $$
declare
  v_overlap_definition text;
  v_schedule_check text;
begin
  if has_table_privilege('authenticated', 'public.profiles', 'INSERT')
    or has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
    or has_table_privilege('authenticated', 'public.profiles', 'DELETE')
  then
    raise exception 'Authenticated clients must not mutate profiles directly';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'A direct profile mutation policy remains exposed';
  end if;

  select with_check
  into v_schedule_check
  from pg_policies
  where schemaname = 'public'
    and tablename = 'schedules'
    and policyname = 'operations manages tenant schedules';
  if v_schedule_check not like '%post.organization_id = schedules.organization_id%'
    or v_schedule_check not like '%personnel.organization_id = schedules.organization_id%'
  then
    raise exception 'Schedule writes do not validate personnel and post tenant ownership';
  end if;

  select pg_get_functiondef(
    'public.prevent_overlapping_active_schedules()'::regprocedure
  ) into v_overlap_definition;
  if v_overlap_definition not like '%pg_advisory_xact_lock%'
    or v_overlap_definition not like '%existing.organization_id = new.organization_id%'
  then
    raise exception 'Schedule overlap validation is not concurrency and tenant safe';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'protect_last_active_it_admin_update'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'protect_last_active_it_admin_delete'
      and not tgisinternal
  ) then
    raise exception 'Last-active-IT-Admin protection triggers are missing';
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'attendance_sessions'
      and indexname = 'attendance_sessions_one_open_per_user_idx'
  ) then
    raise exception 'Open attendance sessions are not protected by a unique index';
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'shift_swap_requests'
      and indexname = 'shift_swap_requests_one_pending_schedule_idx'
  ) then
    raise exception 'Pending schedule-change requests are not protected by a unique index';
  end if;

  if has_function_privilege(
    'anon',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Anonymous callers can execute the attendance RPC';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.prevent_historical_profile_deletion()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Authenticated callers can directly invoke a private trigger helper';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Authenticated callers can bypass the Guard-only attendance wrapper';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_attendance_punch_for_guard_internal(text,double precision,double precision,boolean,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Authenticated callers can bypass the Guard-only legacy attendance wrapper';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ) or not has_function_privilege(
    'anon',
    'public.current_platform_announcement()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'The explicit public RPC allow-list is incomplete';
  end if;

  if exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and not coalesce(procedure.proconfig, '{}'::text[])
        @> array['search_path=public']::text[]
      and not coalesce(procedure.proconfig, '{}'::text[])
        @> array['search_path=public, storage']::text[]
  ) then
    raise exception 'A SECURITY DEFINER function is missing an explicit search_path';
  end if;

  if exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and procedure.oid <>
        'public.current_platform_announcement()'::regprocedure
      and has_function_privilege('anon', procedure.oid, 'EXECUTE')
  ) then
    raise exception 'A private SECURITY DEFINER function is executable by anonymous callers';
  end if;

  if exists (
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
  ) then
    raise exception 'An RLS policy evaluates auth.uid once per row';
  end if;
end;
$$;
