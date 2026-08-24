begin;

create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

select has_table('public', 'attendance_sessions', 'Attendance is stored as duty sessions');
select has_column('public', 'attendance_sessions', 'schedule_id', 'A duty session belongs to a schedule');
select has_table('public', 'guard_assignment_history', 'Guard assignment history is retained');
select has_table('public', 'accomplishment_reports', 'Accomplishment reports are retained');
select has_table('public', 'incidents', 'Incident reports are retained');

select ok(
  to_regprocedure('public.record_attendance_event(text,double precision,double precision)') is not null,
  'Attendance RPC exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_attendance_event(text,double precision,double precision)'::regprocedure,
    'EXECUTE'
  ),
  'Authenticated users can call the guarded attendance RPC'
);
select ok(
  to_regprocedure('public.submit_accomplishment_report(uuid,text,text,text)') is not null,
  'Accomplishment submission RPC exists'
);
select ok(
  to_regprocedure('public.file_incident_report(text,text,text,timestamp with time zone,text,integer,double precision,double precision,text)') is not null,
  'Incident filing RPC exists'
);
select ok(
  to_regprocedure('public.assign_guard_inspector(uuid,uuid)') is not null,
  'Guard Inspector assignment RPC exists'
);
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'validate_profile_inspector_assignment'
      and not tgisinternal
  ),
  'Inspector lifecycle trigger exists'
);
select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'incidents'
      and policyname = 'Authenticated users can mutate incidents'
  ),
  'Unsafe direct incident mutation policy is absent'
);

select * from finish();
rollback;
