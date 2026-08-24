-- HR / Operations owns day-to-day guard-to-Inspector assignments. Keep those
-- links tenant safe so shift-change notifications never cross organizations.

create or replace function public.validate_profile_inspector_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.inspector_id is not null then
    if new.role <> 'user' then
      raise exception 'Only Guard accounts can have an assigned Inspector.';
    end if;
    if new.organization_id is null or not exists (
      select 1
      from public.profiles inspector
      where inspector.id = new.inspector_id
        and inspector.organization_id = new.organization_id
        and inspector.role = 'inspector'
        and inspector.active
    ) then
      raise exception 'Assigned Inspector must be active and belong to the same organization.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists validate_profile_inspector_assignment on public.profiles;
create trigger validate_profile_inspector_assignment
before insert or update of inspector_id, organization_id, role on public.profiles
for each row execute function public.validate_profile_inspector_assignment();

create or replace function public.assign_guard_inspector(
  p_guard_id uuid,
  p_inspector_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only HR / Operations Head can assign an Inspector.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if p_inspector_id is not null and not exists (
    select 1
    from public.profiles inspector
    where inspector.id = p_inspector_id
      and inspector.organization_id = v_organization_id
      and inspector.role = 'inspector'
      and inspector.active
  ) then
    raise exception 'Choose an active Inspector from your organization.';
  end if;

  update public.profiles
  set inspector_id = p_inspector_id
  where id = p_guard_id
    and organization_id = v_organization_id
    and role = 'user';
  if not found then
    raise exception 'Guard was not found in your organization.';
  end if;
end;
$$;

grant execute on function public.assign_guard_inspector(uuid, uuid) to authenticated;
