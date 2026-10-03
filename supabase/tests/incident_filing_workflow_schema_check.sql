-- Regression checks for incident filing, closure, and unfiled-upload cleanup.
do $$
declare
  v_filing_definition text;
  v_status_definition text;
  v_delete_policy text;
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'incidents'
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ) then
    raise exception 'incidents must not allow direct client writes';
  end if;

  select pg_get_functiondef(
    'public.file_incident_report(text,text,text,timestamptz,text,integer,double precision,double precision,text)'::regprocedure
  ) into v_filing_definition;
  if v_filing_definition not like '%public.is_active_duty_personnel()%'
    or v_filing_definition not like '%organization_id,%'
    or v_filing_definition not like '%auth.uid()%'
    or v_filing_definition not like '%p_video_duration_seconds not between 1 and 15%'
    or v_filing_definition not like '%p_captured_at%'
  then
    raise exception 'incident filing must validate personnel, tenant, capture time, and video duration';
  end if;

  select pg_get_functiondef(
    'public.update_incident_status(uuid,text,text)'::regprocedure
  ) into v_status_definition;
  if v_status_definition not like '%p_status = ''resolved''%'
    or v_status_definition not like '%incident.filed_at is null%'
    or v_status_definition not like '%incident.captured_at is null%'
  then
    raise exception 'incident closure must require a timestamped filed report';
  end if;

  select qual into v_delete_policy
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname = 'active personnel remove own unfiled incident video';
  v_delete_policy := lower(v_delete_policy);
  if v_delete_policy is null
    or v_delete_policy not like '%not (exists%'
    or v_delete_policy not like '%incident.video_path%'
  then
    raise exception 'unfiled incident uploads need a guarded cleanup policy';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.file_incident_report(text,text,text,timestamptz,text,integer,double precision,double precision,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated duty personnel cannot file incidents';
  end if;
end;
$$;
