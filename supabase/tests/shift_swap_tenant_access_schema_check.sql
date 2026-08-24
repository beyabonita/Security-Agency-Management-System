-- Static regression checks for the tenant-sensitive security definer RPCs.
do $$
declare
  v_request_definition text;
  v_review_definition text;
  v_decision_definition text;
begin
  select pg_get_functiondef('public.request_shift_swap(uuid,uuid,timestamptz,timestamptz,text)'::regprocedure)
    into v_request_definition;
  if v_request_definition not like '%organization_id = v_organization_id%'
    or v_request_definition not like '%A shift-change request for this schedule is already awaiting review.%' then
    raise exception 'request_shift_swap is missing its tenant or duplicate-request guard';
  end if;

  select pg_get_functiondef('public.review_shift_swap_by_inspector(uuid,boolean,text)'::regprocedure)
    into v_review_definition;
  if v_review_definition not like '%organization_id = v_organization_id%'
    or v_review_definition not like '%inspector_id = auth.uid()%'
  then
    raise exception 'review_shift_swap_by_inspector is missing its tenant or inspector guard';
  end if;

  select pg_get_functiondef('public.decide_shift_swap_by_admin(uuid,boolean,text)'::regprocedure)
    into v_decision_definition;
  if v_decision_definition not like '%organization_id = v_organization_id%'
    or v_decision_definition not like '%Only HR / Operations Head can finalize a schedule change.%'
  then
    raise exception 'decide_shift_swap_by_admin is missing its tenant or role guard';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.request_shift_swap(uuid,uuid,timestamptz,timestamptz,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'authenticated users cannot request a shift change';
  end if;
end;
$$;
