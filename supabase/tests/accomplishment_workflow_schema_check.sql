-- Regression checks for accomplishment reports submitted and reviewed through
-- tenant-aware server functions instead of direct client table writes.
do $$
declare
  v_submit_definition text;
  v_review_definition text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'accomplishment_reports'
      and column_name = 'review_status'
  ) then
    raise exception 'accomplishment_reports.review_status is missing';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'accomplishment_reports'
      and cmd in ('INSERT', 'ALL')
  ) then
    raise exception 'accomplishment reports must not allow direct client inserts';
  end if;

  select pg_get_functiondef(
    'public.submit_accomplishment_report(uuid,text,text,text)'::regprocedure
  ) into v_submit_definition;
  if v_submit_definition not like '%public.is_active_guard()%'
    or v_submit_definition not like '%schedule.user_id = auth.uid()%'
    or v_submit_definition not like '%session.status = ''closed''%'
    or v_submit_definition not like '%organization_id = v_organization_id%'
  then
    raise exception 'accomplishment submission lacks guard, completed-session, or tenant validation';
  end if;

  select pg_get_functiondef(
    'public.review_accomplishment_report(uuid,text,text)'::regprocedure
  ) into v_review_definition;
  if v_review_definition not like '%public.is_admin()%'
    or v_review_definition not like '%organization_id = v_organization_id%'
    or v_review_definition not like '%reviewed_by = auth.uid()%'
  then
    raise exception 'accomplishment review lacks HR or tenant audit validation';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.submit_accomplishment_report(uuid,text,text,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated guards cannot submit accomplishment reports';
  end if;
end;
$$;
