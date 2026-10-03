select pg_get_functiondef('public.record_attendance_event_for_guard_internal(text,double precision,double precision)'::regprocedure) as definition,
 (select jsonb_object_agg(conname, pg_get_constraintdef(oid)) from pg_constraint
 where conrelid = 'public.attendance_sessions'::regclass and contype = 'c') as constraints;
