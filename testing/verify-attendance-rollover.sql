select
  exists(select 1 from supabase_migrations.schema_migrations
    where version='20260908000000' and name='attendance_shift_rollover') as migration_applied,
  position('session.scheduled_end_at > v_now' in pg_get_functiondef(
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure)) > 0 as active_shift_check,
  position('set status = ''missed_timeout''' in pg_get_functiondef(
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure)) > 0 as preserves_missing_timeout,
  position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure)) > 0 as punches_serialized,
  exists(select 1 from pg_constraint where conrelid='public.attendance_sessions'::regclass
    and conname='attendance_sessions_check2'
    and position('missed_timeout' in pg_get_constraintdef(oid)) > 0
    and position('clock_out_at IS NULL' in pg_get_constraintdef(oid)) > 0) as incomplete_record_constraint,
  not has_function_privilege('authenticated',
    'public.record_attendance_event_for_guard_internal(text,double precision,double precision)','execute') as internal_rpc_private,
  has_function_privilege('authenticated',
    'public.record_attendance_event(text,double precision,double precision)','execute') as guard_rpc_available;
