-- Migration: Secure RPC for Operations Head / Admin to update extended personnel profile details and license credentials
create or replace function public.update_personnel_profile(
  p_user_id uuid,
  p_first_name text default null,
  p_middle_name text default null,
  p_middle_initial text default null,
  p_last_name text default null,
  p_mobile_number text default null,
  p_personnel_id text default null,
  p_date_of_birth date default null,
  p_gender text default null,
  p_civil_status text default null,
  p_complete_address text default null,
  p_date_hired date default null,
  p_employment_category text default null,
  p_contract_status text default null,
  p_contract_start_date date default null,
  p_contract_end_date date default null,
  p_license_security_url text default null,
  p_license_firearms_url text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_role text;
  v_org_id uuid;
begin
  if not (public.is_admin() or public.is_it_admin()) then
    raise exception 'Only Administrator or Operations Head can update personnel profiles.';
  end if;

  select role, organization_id into v_role, v_org_id
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'Personnel profile not found.';
  end if;

  if public.is_admin() and (v_org_id is distinct from public.current_organization_id() or v_role not in ('user', 'inspector')) then
    raise exception 'You can only update Guard or Inspector accounts within your organization.';
  end if;

  update public.profiles set
    first_name = coalesce(p_first_name, first_name),
    middle_name = coalesce(p_middle_name, middle_name),
    middle_initial = coalesce(p_middle_initial, middle_initial),
    last_name = coalesce(p_last_name, last_name),
    mobile_number = coalesce(p_mobile_number, mobile_number),
    personnel_id = coalesce(p_personnel_id, personnel_id),
    date_of_birth = coalesce(p_date_of_birth, date_of_birth),
    gender = coalesce(p_gender, gender),
    civil_status = coalesce(p_civil_status, civil_status),
    complete_address = coalesce(p_complete_address, complete_address),
    date_hired = coalesce(p_date_hired, date_hired),
    employment_category = coalesce(p_employment_category, employment_category),
    contract_status = coalesce(p_contract_status, contract_status),
    contract_start_date = coalesce(p_contract_start_date, contract_start_date),
    contract_end_date = coalesce(p_contract_end_date, contract_end_date),
    license_security_url = case when p_license_security_url is not null and p_license_security_url <> '' then p_license_security_url else license_security_url end,
    license_firearms_url = case when p_license_firearms_url is not null and p_license_firearms_url <> '' then p_license_firearms_url else license_firearms_url end
  where id = p_user_id;

  if coalesce(p_employment_category, '') = 'contract' and p_contract_start_date is not null and p_contract_end_date is not null then
    begin
      insert into public.guard_contract_history (
        guard_id,
        contract_start_date,
        contract_end_date,
        contract_status,
        renewed_at,
        renewed_by,
        remarks
      ) values (
        p_user_id,
        p_contract_start_date,
        p_contract_end_date,
        coalesce(p_contract_status, 'Active'),
        now(),
        auth.uid(),
        'Contract updated / renewed via personnel profile management'
      );
    exception when others then
      -- best effort history insert
    end;
  end if;
end $$;

grant execute on function public.update_personnel_profile to authenticated;
