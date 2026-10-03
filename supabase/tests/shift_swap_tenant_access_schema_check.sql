-- Static checks for private request letters and direct Admin approval.
do $$
declare v_submit text; v_decide text; v_inspector text;
begin
  select pg_get_functiondef('public.submit_duty_request(uuid,text,text,text,text)'::regprocedure) into v_submit;
  if v_submit not like '%public.is_active_guard()%'
    or v_submit not like '%storage.objects%'
    or v_submit not like '%status%pending_admin%'
    or v_submit not like '%organization_id = v_org%' then
    raise exception 'submit_duty_request is missing Guard, letter, direct-approval, or tenant validation';
  end if;

  select pg_get_functiondef('public.decide_duty_request(uuid,boolean,text,uuid)'::regprocedure) into v_decide;
  if v_decide not like '%public.is_admin()%'
    or v_decide not like '%organization_id = public.current_organization_id()%'
    or v_decide not like '%attendance_sessions%'
    or v_decide not like '%overlapping duty%' then
    raise exception 'decide_duty_request is missing Admin, tenant, attendance, or overlap protection';
  end if;

  select pg_get_functiondef('public.review_shift_swap_by_inspector(uuid,boolean,text)'::regprocedure) into v_inspector;
  if v_inspector not like '%directly to Admin%' then
    raise exception 'Inspector review endpoint was not retired';
  end if;
  if has_function_privilege('authenticated',
    'public.review_shift_swap_by_inspector(uuid,boolean,text)'::regprocedure,'EXECUTE') then
    raise exception 'authenticated callers can still invoke retired Inspector review';
  end if;
  if not has_function_privilege('authenticated',
    'public.submit_duty_request(uuid,text,text,text,text)'::regprocedure,'EXECUTE') then
    raise exception 'authenticated Guards cannot invoke submit_duty_request';
  end if;
end;
$$;
