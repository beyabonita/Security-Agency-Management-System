-- Add archived_at timestamp column to incidents table and add archive_incident_report RPC function
alter table public.incidents add column if not exists archived_at timestamptz;

create or replace function public.archive_incident_report(
  p_incident_id uuid,
  p_archive boolean default true
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_incident public.incidents;
begin
  if not public.is_admin() then
    raise exception 'Only Operations Head can archive incident reports.' using errcode = '42501';
  end if;
  select * into v_incident from public.incidents i
    where i.id = p_incident_id
      and i.organization_id = public.current_organization_id()
    for update;
  if not found then
    raise exception 'Incident report not found or not accessible.' using errcode = 'P0002';
  end if;

  update public.incidents
  set archived_at = case when p_archive then now() else null end,
      updated_at = now(),
      updated_by = auth.uid()
  where id = v_incident.id;
end;
$$;

grant execute on function public.archive_incident_report(uuid, boolean) to authenticated;
notify pgrst, 'reload schema';
