-- Run after `supabase db reset` or `supabase db push` against a disposable
-- database. This is a schema-level regression check for the tenant write fix.
begin;

do $$
declare
  v_default text;
  v_function text;
begin
  select pg_get_expr(d.adbin, d.adrelid)
  into v_default
  from pg_attrdef d
  join pg_attribute a
    on a.attrelid = d.adrelid
    and a.attnum = d.adnum
  where d.adrelid = 'public.attendance_punches'::regclass
    and a.attname = 'organization_id';

  if v_default is null or position('current_organization_id' in v_default) = 0 then
    raise exception 'attendance_punches.organization_id must default to current_organization_id()';
  end if;

  select pg_get_functiondef(
    'public.record_attendance_punch(text,double precision,double precision,boolean,text)'::regprocedure
  ) into v_function;

  if position('v_session.organization_id' in v_function) = 0
      or position('organization_id' in v_function) = 0 then
    raise exception 'record_attendance_punch must write the session organization explicitly';
  end if;
end;
$$;

rollback;
