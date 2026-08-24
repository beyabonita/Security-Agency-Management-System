-- The policy below survived the tenant migration because its name differs
-- from the older policy names that were removed there. PostgreSQL combines
-- permissive policies with OR, so it allowed an HR account to delete an
-- incident from another organization when its UUID was known.
drop policy if exists "admin deletes incidents" on public.incidents;

-- Status changes go through this SECURITY DEFINER RPC. Restrict HR/Inspector
-- users to their own organization while preserving explicit platform-wide
-- access for the IT Admin role.
create or replace function public.update_incident_status(
  p_incident_id uuid,
  p_status text,
  p_status_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_rows integer;
begin
  if p_status not in ('open', 'acknowledged', 'resolved') then
    raise exception 'Invalid incident status.';
  end if;

  if public.is_it_admin() then
    update public.incidents
    set status = p_status,
        status_note = left(coalesce(p_status_note, ''), 500),
        updated_at = now(),
        updated_by = auth.uid()
    where id = p_incident_id;
  else
    if not public.is_staff() then
      raise exception 'You are not allowed to update this incident.';
    end if;

    v_organization_id := public.current_organization_id();
    if v_organization_id is null then
      raise exception 'This account is not assigned to an active organization.';
    end if;

    update public.incidents
    set status = p_status,
        status_note = left(coalesce(p_status_note, ''), 500),
        updated_at = now(),
        updated_by = auth.uid()
    where id = p_incident_id
      and organization_id = v_organization_id;
  end if;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'Incident not found or no longer accessible.';
  end if;
end;
$$;
