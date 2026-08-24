-- Sentinel Link is operated for one beneficiary: TwentyTwenty Security Agency.
-- Deployment customers such as Jollibee are duty sites, not separate Sentinel
-- Link organizations. Preserve all historical records while consolidating the
-- former multi-client setup into the beneficiary workspace.

do $$
declare
  v_beneficiary_id uuid;
  v_legacy_id uuid;
begin
  select id
    into v_beneficiary_id
  from public.organizations
  where slug = 'twentytwenty-security-agency'
  limit 1;

  if v_beneficiary_id is null then
    select id
      into v_legacy_id
    from public.organizations
    where slug = 'legacy-default'
    order by created_at
    limit 1;

    if v_legacy_id is not null then
      update public.organizations
      set name = 'TwentyTwenty Security Agency',
          slug = 'twentytwenty-security-agency',
          active = true
      where id = v_legacy_id;
      v_beneficiary_id := v_legacy_id;
    else
      insert into public.organizations (name, slug, contact_name, contact_email, active)
      values ('TwentyTwenty Security Agency', 'twentytwenty-security-agency', '', '', true)
      returning id into v_beneficiary_id;
    end if;
  end if;

  -- The inspector-assignment lifecycle trigger correctly protects ordinary
  -- personnel changes. Temporarily suspend it only while every profile is
  -- being moved to the same beneficiary, then restore it immediately.
  alter table public.profiles disable trigger validate_profile_inspector_assignment;

  update public.profiles
  set organization_id = v_beneficiary_id
  where role <> 'it_admin'
    and organization_id is distinct from v_beneficiary_id;

  update public.profiles
  set organization_id = null
  where role = 'it_admin'
    and organization_id is not null;

  alter table public.profiles enable trigger validate_profile_inspector_assignment;

  update public.locations set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.schedules set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.attendance_punches set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.attendance_sessions set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.incidents set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.guard_assignment_history set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.shift_swap_requests set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;
  update public.accomplishment_reports set organization_id = v_beneficiary_id where organization_id is distinct from v_beneficiary_id;

  update public.organizations
  set active = false
  where id <> v_beneficiary_id
    and active;

  update public.organizations
  set name = 'TwentyTwenty Security Agency',
      active = true
  where id = v_beneficiary_id;
end $$;

-- There can be only one active beneficiary workspace. Historical organization
-- rows remain inactive so no records are discarded.
create unique index if not exists organizations_only_one_active_idx
  on public.organizations ((active))
  where active;

create or replace function public.beneficiary_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.organizations
  where slug = 'twentytwenty-security-agency'
    and active
  limit 1
$$;

grant execute on function public.beneficiary_organization_id() to authenticated;

-- IT Admin is responsible for platform maintenance and privileged access.
-- It must not be able to directly alter operational Guard/Inspector profiles.
drop policy if exists "it admin manages profiles" on public.profiles;
create policy "it admin manages platform profiles"
on public.profiles
for all
to authenticated
using (
  public.is_it_admin()
  and role in ('it_admin', 'admin')
)
with check (
  public.is_it_admin()
  and role in ('it_admin', 'admin')
);

-- Keep the beneficiary configuration visible to IT Admin, but remove the
-- previous browser-level ability to create or delete client organizations.
drop policy if exists "it admin manages organizations" on public.organizations;
create policy "it admin views beneficiary configuration"
on public.organizations
for select
to authenticated
using (public.is_it_admin());
