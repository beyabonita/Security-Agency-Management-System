-- Migration: Guard self-service profile customization, shared profile_photo_url,
-- emergency_contact, storage bucket policies, and realtime live-map invalidation.

-- 1. Extend public.profiles with shared profile photo URL and emergency contact
alter table public.profiles
  add column if not exists profile_photo_url text,
  add column if not exists emergency_contact text;

-- 2. Provision public-read storage bucket for profile photos (writes restricted to service_role Edge Function)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  true,
  2097152,
  array['image/jpeg', 'image/png']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg', 'image/png'];

drop policy if exists "Public can view profile photos" on storage.objects;
create policy "Public can view profile photos"
  on storage.objects
  for select
  to public
  using (bucket_id = 'profile-photos');

-- 3. Secure self-service RPC: Guard can update ONLY their own contact number, complete address, and emergency contact
create or replace function public.update_own_guard_profile(
  p_mobile_number text default null,
  p_complete_address text default null,
  p_emergency_contact text default null,
  p_strict_payload jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_mobile text;
  v_address text;
  v_emergency text;
  v_key text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  -- Reject any attempt to pass locked profile fields
  if p_strict_payload is not null and jsonb_typeof(p_strict_payload) = 'object' then
    for v_key in select jsonb_object_keys(p_strict_payload)
    loop
      if v_key not in ('mobile_number', 'mobileNumber', 'complete_address', 'completeAddress', 'emergency_contact', 'emergencyContact') then
        raise exception 'Field "%" is read-only and can only be modified by the Operations Head.', v_key using errcode = '42501';
      end if;
    end loop;
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;

  if not found or not v_profile.active then
    raise exception 'Active profile not found.' using errcode = '42501';
  end if;

  if v_profile.role <> 'user' then
    raise exception 'Self-service guard profile updates are only available to Guard accounts.' using errcode = '42501';
  end if;

  -- Normalize & validate Philippine mobile number (09XXXXXXXXX or +639XXXXXXXXX)
  if p_mobile_number is null then
    v_mobile := v_profile.mobile_number;
  else
    v_mobile := regexp_replace(trim(p_mobile_number), '[\s\-()]', '', 'g');
    if v_mobile = '' then
      v_mobile := null;
    else
      if v_mobile ~ '^\+639[0-9]{9}$' then
        v_mobile := '0' || substring(v_mobile from 4);
      elsif v_mobile ~ '^639[0-9]{9}$' then
        v_mobile := '0' || substring(v_mobile from 3);
      end if;
      if v_mobile !~ '^09[0-9]{9}$' then
        raise exception 'Enter a valid 11-digit mobile number starting with 09.' using errcode = '22023';
      end if;

      if exists (
        select 1 from public.profiles
        where mobile_number = v_mobile
          and id <> v_uid
      ) then
        raise exception 'This mobile number is already registered to another personnel record.' using errcode = '23505';
      end if;
    end if;
  end if;

  if p_complete_address is null then
    v_address := v_profile.complete_address;
  else
    v_address := nullif(trim(p_complete_address), '');
    if v_address is not null and char_length(v_address) > 500 then
      raise exception 'Complete address must be 500 characters or fewer.' using errcode = '22023';
    end if;
  end if;

  if p_emergency_contact is null then
    v_emergency := v_profile.emergency_contact;
  else
    v_emergency := nullif(trim(p_emergency_contact), '');
    if v_emergency is not null and char_length(v_emergency) > 300 then
      raise exception 'Emergency contact must be 300 characters or fewer.' using errcode = '22023';
    end if;
  end if;

  update public.profiles set
    mobile_number = v_mobile,
    complete_address = v_address,
    emergency_contact = v_emergency
  where id = v_uid;

  return jsonb_build_object(
    'id', v_uid,
    'mobile_number', v_mobile,
    'complete_address', v_address,
    'emergency_contact', v_emergency,
    'profile_photo_url', v_profile.profile_photo_url
  );
end $$;

revoke all on function public.update_own_guard_profile(text, text, text, jsonb) from public, anon;
grant execute on function public.update_own_guard_profile(text, text, text, jsonb) to authenticated;

-- 4. Read-only details RPC for Guard mobile app (resolves assigned post & inspector names safely)
create or replace function public.get_own_guard_profile_details()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_post_label text;
  v_post_address text;
  v_inspector_name text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid;

  if not found then
    raise exception 'Profile not found.' using errcode = 'P0002';
  end if;

  if v_profile.assigned_location_id is not null then
    select l.label, l.address into v_post_label, v_post_address
    from public.locations l
    where l.id = v_profile.assigned_location_id;
  end if;

  if v_post_label is null then
    select coalesce(nullif(l.label, ''), s.location_label), coalesce(nullif(l.address, ''), s.location_address)
      into v_post_label, v_post_address
    from public.schedules s
    left join public.locations l on l.id = s.location_id
    where s.user_id = v_uid
      and s.approval_status in ('approved', 'changed')
      and not coalesce(s.marked_done, false)
    order by s.start_at desc
    limit 1;
  end if;

  if v_profile.inspector_id is not null then
    select nullif(trim(concat_ws(' ', i.first_name, i.last_name)), '')
      into v_inspector_name
    from public.profiles i
    where i.id = v_profile.inspector_id;
  end if;

  return jsonb_build_object(
    'id', v_profile.id,
    'first_name', v_profile.first_name,
    'middle_name', v_profile.middle_name,
    'middle_initial', v_profile.middle_initial,
    'last_name', v_profile.last_name,
    'personnel_id', v_profile.personnel_id,
    'email', v_profile.email,
    'mobile_number', v_profile.mobile_number,
    'complete_address', v_profile.complete_address,
    'emergency_contact', v_profile.emergency_contact,
    'profile_photo_url', v_profile.profile_photo_url,
    'date_hired', v_profile.date_hired,
    'employment_category', v_profile.employment_category,
    'contract_status', v_profile.contract_status,
    'contract_start_date', v_profile.contract_start_date,
    'contract_end_date', v_profile.contract_end_date,
    'assigned_location_id', v_profile.assigned_location_id,
    'assigned_post_label', coalesce(v_post_label, 'Unassigned'),
    'assigned_post_address', v_post_address,
    'inspector_id', v_profile.inspector_id,
    'inspector_name', coalesce(v_inspector_name, 'Unassigned')
  );
end $$;

revoke all on function public.get_own_guard_profile_details() from public, anon;
grant execute on function public.get_own_guard_profile_details() to authenticated;

-- 5. Extend Operations Head update_personnel_profile RPC (drop old 18-arg signature first to avoid PostgREST overload ambiguity)
drop function if exists public.update_personnel_profile(
  uuid, text, text, text, text, text, text, date, text, text, text, date, text, text, date, date, text, text
);

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
  p_license_firearms_url text default null,
  p_emergency_contact text default null,
  p_profile_photo_url text default null,
  p_clear_profile_photo boolean default false
) returns void language plpgsql security definer set search_path = public as $$
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
    removed_at = null,
    active = coalesce(active, true),
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
    emergency_contact = case when p_emergency_contact is not null then nullif(trim(p_emergency_contact), '') else emergency_contact end,
    date_hired = coalesce(p_date_hired, date_hired),
    employment_category = coalesce(p_employment_category, employment_category),
    contract_status = coalesce(p_contract_status, contract_status),
    contract_start_date = coalesce(p_contract_start_date, contract_start_date),
    contract_end_date = coalesce(p_contract_end_date, contract_end_date),
    license_security_url = case when p_license_security_url is not null and p_license_security_url <> '' then p_license_security_url else license_security_url end,
    license_firearms_url = case when p_license_firearms_url is not null and p_license_firearms_url <> '' then p_license_firearms_url else license_firearms_url end,
    profile_photo_url = case
      when coalesce(p_clear_profile_photo, false) then null
      when p_profile_photo_url is not null and p_profile_photo_url <> '' then p_profile_photo_url
      else profile_photo_url
    end
  where id = p_user_id;

  begin
    update auth.users set banned_until = null where id = p_user_id;
  exception when others then
    null;
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
      null;
    end;
  end if;
end $$;

grant execute on function public.update_personnel_profile to authenticated;

-- 6. Include shared profile_photo_url and personal contact details in Live Guard Map snapshot
create or replace function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('server_now', now(), 'locations', coalesce((
    select jsonb_agg(to_jsonb(g) || jsonb_build_object(
      'location_label', concat_ws(' · ', coalesce(nullif(l.label, ''), g.location_label), nullif(l.address, '')),
      'client_name', coalesce(nullif(l.label, ''), g.location_label),
      'location_address', nullif(l.address, ''),
      'mobile_number', p.mobile_number,
      'profile_photo_url', p.profile_photo_url,
      'complete_address', p.complete_address,
      'emergency_contact', p.emergency_contact,
      'first_name', p.first_name,
      'last_name', p.last_name
    ))
    from public.list_live_guard_locations() g
    join public.profiles p on p.id = g.user_id
    join public.attendance_sessions a on a.id = g.session_id
    left join public.schedules s on s.id = a.schedule_id
    left join public.locations l on l.id = s.location_id and l.organization_id = s.organization_id
  ), '[]'::jsonb));
$$;

revoke all on function public.live_guard_map_snapshot() from public, anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;

-- 7. Signal live-guard viewers immediately whenever a guard's profile photo or personal info changes
create or replace function private.signal_guard_profile_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  viewer record;
begin
  if new.role <> 'user' then
    return new;
  end if;

  for viewer in
    select p.id
    from public.organizations o
    join public.profiles p on p.organization_id = o.id and p.active
    where o.id = new.organization_id
      and o.active
      and (p.role = 'admin' or (p.role = 'inspector' and p.id = new.inspector_id))
  loop
    begin
      perform realtime.send('{}'::jsonb, 'location_changed', 'live-guards:' || viewer.id::text, true);
    exception when others then
      null;
    end;
  end loop;

  return new;
end $$;

revoke all on function private.signal_guard_profile_change() from public, anon, authenticated;

drop trigger if exists signal_guard_profile_change on public.profiles;
create trigger signal_guard_profile_change
  after update of profile_photo_url, mobile_number, complete_address, emergency_contact, first_name, last_name
  on public.profiles
  for each row
  execute function private.signal_guard_profile_change();

notify pgrst, 'reload schema';

