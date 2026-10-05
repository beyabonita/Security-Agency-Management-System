-- Migration: Create purge_personnel_account function and purge Inspector T. Base
create or replace function public.purge_personnel_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role text;
  v_email text;
  v_fallback_admin uuid;
begin
  -- Caller must be postgres superuser, service_role, or authenticated admin
  if current_user not in ('postgres', 'supabase_admin')
     and coalesce(auth.role(), '') <> 'service_role'
     and not (public.is_admin() or public.is_it_admin() or public.is_operations_head()) then
    raise exception 'Only administrators can permanently purge personnel accounts.' using errcode = '42501';
  end if;

  if auth.uid() is not null and auth.uid() = p_user_id then
    raise exception 'You cannot delete your own account.' using errcode = '42501';
  end if;

  select role, email into v_role, v_email from public.profiles where id = p_user_id;
  if not found then
    delete from auth.users where id = p_user_id;
    return jsonb_build_object('ok', true, 'message', 'Profile already removed, auth cleaned up.');
  end if;

  -- Pick an active fallback admin to inherit any non-nullable audit fields if needed
  select id into v_fallback_admin from public.profiles
  where role in ('admin', 'it_admin') and active and id <> p_user_id
  order by created_at asc limit 1;

  -- 1. Unassign any guards assigned to this inspector
  update public.profiles set inspector_id = null where inspector_id = p_user_id;

  -- 2. Shift swap requests referencing this user
  if to_regclass('public.shift_swap_requests') is not null then
    delete from public.shift_swap_requests
    where requester_id = p_user_id
       or target_guard_id = p_user_id
       or inspector_id = p_user_id
       or inspector_decision_by = p_user_id
       or admin_decision_by = p_user_id;
  end if;

  -- 3. Incident reviews & updates
  if to_regclass('public.incidents') is not null then
    update public.incidents set updated_by = v_fallback_admin where updated_by = p_user_id;
    delete from public.incidents where user_id = p_user_id;
  end if;

  -- 4. Schedules & attendance sessions
  if to_regclass('public.schedules') is not null then
    update public.schedules set completed_by = null where completed_by = p_user_id;
    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='schedules' and column_name='approved_by') then
      execute 'update public.schedules set approved_by = null where approved_by = $1' using p_user_id;
    end if;
    delete from public.schedules where user_id = p_user_id;
  end if;

  if to_regclass('public.attendance_punches') is not null then
    delete from public.attendance_punches where user_id = p_user_id;
  end if;

  if to_regclass('public.attendance_timeout_reviews') is not null then
    delete from public.attendance_timeout_reviews where guard_id = p_user_id or reviewed_by = p_user_id;
  end if;

  if to_regclass('public.attendance_sessions') is not null then
    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='attendance_sessions' and column_name='timeout_verified_by') then
      execute 'update public.attendance_sessions set timeout_verified_by = null where timeout_verified_by = $1' using p_user_id;
    end if;
    delete from public.attendance_sessions where user_id = p_user_id;
  end if;

  -- 5. Guard assignment history
  if to_regclass('public.guard_assignment_history') is not null then
    delete from public.guard_assignment_history where guard_id = p_user_id;
    if v_fallback_admin is not null then
      update public.guard_assignment_history set assigned_by = v_fallback_admin where assigned_by = p_user_id;
    else
      delete from public.guard_assignment_history where assigned_by = p_user_id;
    end if;
  end if;

  -- 6. Accomplishment reports
  if to_regclass('public.accomplishment_reports') is not null then
    delete from public.accomplishment_reports where guard_id = p_user_id;
    update public.accomplishment_reports set reviewed_by = null where reviewed_by = p_user_id;
  end if;

  -- 7. Live locations & notifications & contract history
  if to_regclass('public.guard_live_locations') is not null then
    delete from public.guard_live_locations where user_id = p_user_id;
  end if;

  if to_regclass('public.user_notifications') is not null then
    delete from public.user_notifications where recipient_id = p_user_id or created_by = p_user_id;
  end if;

  if to_regclass('public.guard_contract_history') is not null then
    delete from public.guard_contract_history where guard_id = p_user_id;
    update public.guard_contract_history set renewed_by = null where renewed_by = p_user_id;
  end if;

  if to_regclass('public.account_presence') is not null then
    execute 'delete from public.account_presence where user_id = $1' using p_user_id;
  end if;

  -- 8. Shift roster setups
  if to_regclass('public.shift_roster_setups') is not null then
    update public.shift_roster_setups set created_by = null where created_by = p_user_id;
  end if;

  -- 9. Incident deletion audit
  if to_regclass('public.incident_deletion_audit') is not null then
    if v_fallback_admin is not null then
      update public.incident_deletion_audit set deleted_by = v_fallback_admin where deleted_by = p_user_id;
    else
      delete from public.incident_deletion_audit where deleted_by = p_user_id;
    end if;
  end if;

  -- 10. Client organizations
  if to_regclass('public.client_organizations') is not null then
    update public.client_organizations set created_by = null where created_by = p_user_id;
  end if;

  -- 11. Delete the profile
  delete from public.profiles where id = p_user_id;

  -- 12. Delete from auth.users
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('ok', true, 'purged_email', v_email, 'purged_id', p_user_id);
end;
$$;

revoke all on function public.purge_personnel_account(uuid) from public, anon;
grant execute on function public.purge_personnel_account(uuid) to authenticated;

-- Immediately purge Inspector T. Base if present in the database
do $$
declare
  v_inspector_id uuid;
begin
  select id into v_inspector_id from public.profiles where lower(email) = 'inspector1@gmail.com';
  if v_inspector_id is not null then
    perform public.purge_personnel_account(v_inspector_id);
  end if;
  -- Also ensure auth user is cleaned up if profile was detached
  delete from auth.users where lower(email) = 'inspector1@gmail.com';
end $$;
