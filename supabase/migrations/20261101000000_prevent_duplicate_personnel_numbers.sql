-- Migration: Prevent duplicate registration of mobile numbers and Personnel IDs across personnel records

create or replace function public.enforce_unique_personnel_identifiers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mobile text;
  v_pid text;
begin
  v_mobile := nullif(btrim(coalesce(new.mobile_number, '')), '');
  v_pid := nullif(btrim(coalesce(new.personnel_id, '')), '');

  new.mobile_number := v_mobile;
  new.personnel_id := v_pid;

  if v_mobile is not null and (
    tg_op = 'INSERT' or v_mobile is distinct from nullif(btrim(coalesce(old.mobile_number, '')), '')
  ) then
    if exists (
      select 1
      from public.profiles p
      where p.mobile_number = v_mobile
        and p.id is distinct from new.id
    ) then
      raise exception 'This mobile number is already registered to another personnel record.'
        using errcode = '23505';
    end if;
  end if;

  if v_pid is not null and (
    tg_op = 'INSERT' or upper(v_pid) is distinct from upper(nullif(btrim(coalesce(old.personnel_id, '')), ''))
  ) then
    if exists (
      select 1
      from public.profiles p
      where p.personnel_id is not null
        and btrim(p.personnel_id) <> ''
        and upper(btrim(p.personnel_id)) = upper(v_pid)
        and p.id is distinct from new.id
    ) then
      raise exception 'This Personnel ID is already registered to another personnel record.'
        using errcode = '23505';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_unique_personnel_identifiers on public.profiles;
create trigger trg_enforce_unique_personnel_identifiers
  before insert or update of mobile_number, personnel_id
  on public.profiles
  for each row
  execute function public.enforce_unique_personnel_identifiers();

-- Add partial unique indexes when existing data has no legacy duplicates
do $$
begin
  if not exists (
    select 1
    from public.profiles
    where mobile_number is not null and btrim(mobile_number) <> ''
    group by btrim(mobile_number)
    having count(*) > 1
  ) then
    execute 'create unique index if not exists profiles_mobile_number_unique_idx on public.profiles (mobile_number) where mobile_number is not null and btrim(mobile_number) <> ''''';
  end if;

  if not exists (
    select 1
    from public.profiles
    where personnel_id is not null and btrim(personnel_id) <> ''
    group by upper(btrim(personnel_id))
    having count(*) > 1
  ) then
    execute 'create unique index if not exists profiles_personnel_id_unique_idx on public.profiles (upper(btrim(personnel_id))) where personnel_id is not null and btrim(personnel_id) <> ''''';
  end if;
end $$;

-- Update update_personnel_profile RPC to explicitly validate uniqueness before updating
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
  v_mobile text;
  v_pid text;
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

  v_mobile := nullif(btrim(coalesce(p_mobile_number, '')), '');
  v_pid := nullif(btrim(coalesce(p_personnel_id, '')), '');

  if v_mobile is not null and exists (
    select 1 from public.profiles p
    where p.mobile_number = v_mobile
      and p.id <> p_user_id
  ) then
    raise exception 'This mobile number is already registered to another personnel record.'
      using errcode = '23505';
  end if;

  if v_pid is not null and exists (
    select 1 from public.profiles p
    where p.personnel_id is not null
      and btrim(p.personnel_id) <> ''
      and upper(btrim(p.personnel_id)) = upper(v_pid)
      and p.id <> p_user_id
  ) then
    raise exception 'This Personnel ID is already registered to another personnel record.'
      using errcode = '23505';
  end if;

  -- Restore account active state, clear any historical removal flag, and update profile
  update public.profiles set
    removed_at = null,
    active = coalesce(active, true),
    first_name = coalesce(p_first_name, first_name),
    middle_name = coalesce(p_middle_name, middle_name),
    middle_initial = coalesce(p_middle_initial, middle_initial),
    last_name = coalesce(p_last_name, last_name),
    mobile_number = case when p_mobile_number is not null then v_mobile else mobile_number end,
    personnel_id = coalesce(v_pid, personnel_id),
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

  -- Ensure any auth ban is lifted if this account was previously marked removed
  begin
    update auth.users set banned_until = null where id = p_user_id;
  exception when others then
    -- best effort auth unban
  end;

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
notify pgrst, 'reload schema';

