-- Verify private video reads are tied to the incident's organization.
do $$
declare
  v_qual text;
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'incident staff reads video'
  ) then
    raise exception 'obsolete cross-tenant incident-video staff policy still exists';
  end if;

  select qual into v_qual
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname = 'tenant incident staff reads video';
  if v_qual is null
    or v_qual not like '%video_path%'
    or v_qual not like '%organization_id%'
    or v_qual not like '%current_organization_id%'
  then
    raise exception 'incident-video staff policy is missing an incident tenant check';
  end if;
end;
$$;
