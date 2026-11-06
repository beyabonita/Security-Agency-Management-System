-- Update error notification for unrecognized or unauthorized devices (#7, #20)
-- Exact text: "We couldn't recognize this device. Please try again using your authorized device."

create or replace function public.bind_or_verify_guard_device(
  p_device_id text,
  p_device_info text default null,
  p_force_rebind boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_clean_id text := nullif(trim(coalesce(p_device_id, '')), '');
  v_clean_info text := nullif(trim(coalesce(p_device_info, '')), '');
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if v_clean_id is null then
    return jsonb_build_object(
      'verified', false,
      'status', 'missing_device_id',
      'message', 'Could not read device identifier.'
    );
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;

  if not found then
    raise exception 'Profile not found.' using errcode = '42501';
  end if;

  if v_profile.registered_device_id is null or trim(v_profile.registered_device_id) = '' or p_force_rebind then
    update public.profiles
    set registered_device_id = v_clean_id,
        registered_device_info = coalesce(v_clean_info, registered_device_info),
        registered_device_at = now()
    where id = v_uid;

    return jsonb_build_object(
      'verified', true,
      'status', 'bound',
      'registered_device_id', v_clean_id,
      'registered_device_info', v_clean_info
    );
  end if;

  if v_profile.registered_device_id = v_clean_id then
    if v_clean_info is not null and v_clean_info is distinct from v_profile.registered_device_info then
      update public.profiles
      set registered_device_info = v_clean_info
      where id = v_uid;
    end if;

    return jsonb_build_object(
      'verified', true,
      'status', 'matched',
      'registered_device_id', v_profile.registered_device_id,
      'registered_device_info', coalesce(v_clean_info, v_profile.registered_device_info)
    );
  end if;

  return jsonb_build_object(
    'verified', false,
    'status', 'mismatch',
    'registered_device_id', v_profile.registered_device_id,
    'registered_device_info', v_profile.registered_device_info,
    'current_device_id', v_clean_id,
    'current_device_info', v_clean_info,
    'message', 'We couldn''t recognize this device. Please try again using your authorized device.'
  );
end;
$$;

revoke all on function public.bind_or_verify_guard_device(text, text, boolean) from public, anon;
grant execute on function public.bind_or_verify_guard_device(text, text, boolean) to authenticated;

create or replace function public.register_device(p_device_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  v_organization_id uuid;
begin
  if not public.is_active_guard() then
    raise exception 'This account is not allowed to use the guard app.';
  end if;
  if p_device_id is null or char_length(trim(p_device_id)) not between 8 and 200 then
    raise exception 'Device registration is invalid. Please reinstall or contact your administrator.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;

  select * into p
  from public.profiles
  where id = auth.uid()
    and organization_id = v_organization_id;
  if not found then
    raise exception 'This account is not allowed to use the guard app.';
  end if;
  if p.device_locked and p.device_id is not null and p.device_id <> p_device_id then
    raise exception 'We couldn''t recognize this device. Please try again using your authorized device.';
  end if;
  if p.device_id is null or p.device_id = '' then
    update public.profiles
    set device_id = trim(p_device_id)
    where id = auth.uid()
      and organization_id = v_organization_id;
  end if;
end;
$$;

revoke all on function public.register_device(text) from public, anon;
grant execute on function public.register_device(text) to authenticated;

