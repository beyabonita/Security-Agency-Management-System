-- Migration: Guard Archiving restricted to accounts without an active contract
create or replace function public.archive_personnel_account(
  p_user_id uuid,
  p_archive boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_profile public.profiles;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  if not (public.is_admin() or public.is_it_admin()) then
    raise exception 'Only Administrator or Operations Head can archive personnel accounts.' using errcode = '42501';
  end if;

  select * into v_profile from public.profiles
    where id = p_user_id
      and (organization_id = public.current_organization_id() or public.is_it_admin())
    for update;

  if not found then
    raise exception 'Personnel profile not found or not accessible.' using errcode = 'P0002';
  end if;

  if p_archive then
    -- Verify guard does not have an active contract
    if v_profile.employment_category = 'contract'
       and v_profile.contract_start_date is not null
       and v_profile.contract_end_date is not null
       and v_today between v_profile.contract_start_date and v_profile.contract_end_date
       and coalesce(v_profile.contract_status, 'Active') = 'Active' then
      raise exception 'Cannot archive guard because they have an Active Contract valid until % (PHT). End or expire their contract dates first.', v_profile.contract_end_date using errcode = '42501';
    end if;

    update public.profiles set
      removed_at = now(),
      active = false,
      assigned_location_id = null
    where id = v_profile.id;

    return jsonb_build_object('ok', true, 'message', 'Personnel account archived successfully.');
  else
    update public.profiles set
      removed_at = null,
      active = true
    where id = v_profile.id;

    return jsonb_build_object('ok', true, 'message', 'Personnel account unarchived successfully.');
  end if;
end $$;

grant execute on function public.archive_personnel_account(uuid, boolean) to authenticated;
notify pgrst, 'reload schema';
