-- An Inspector cannot leave the active tenant role while guards still point to
-- that Inspector. HR must explicitly reassign or clear those guards first.

create or replace function public.validate_profile_inspector_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE'
    and old.role = 'inspector'
    and (
      new.role is distinct from old.role
      or new.organization_id is distinct from old.organization_id
      or new.active is distinct from old.active
    )
    and (
      new.role <> 'inspector'
      or new.organization_id is distinct from old.organization_id
      or new.active is false
    )
    and exists (
      select 1
      from public.profiles guard
      where guard.inspector_id = old.id
    )
  then
    raise exception 'Reassign or clear all Guard Inspector assignments before disabling, moving, or changing this Inspector.';
  end if;

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
before insert or update of inspector_id, organization_id, role, active on public.profiles
for each row execute function public.validate_profile_inspector_assignment();
