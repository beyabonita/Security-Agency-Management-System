-- Run after `supabase db reset` or `supabase db push` against a disposable
-- database. This prevents the permissive legacy delete policy from returning
-- and ensures staff status updates remain tenant scoped.
begin;

do $$
declare
  v_function text;
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'incidents'
      and policyname = 'admin deletes incidents'
  ) then
    raise exception 'legacy cross-tenant incident delete policy still exists';
  end if;

  select pg_get_functiondef(
    'public.update_incident_status(uuid,text,text)'::regprocedure
  ) into v_function;

  if position('organization_id = v_organization_id' in v_function) = 0
      or position('public.is_it_admin()' in v_function) = 0 then
    raise exception 'incident status updates must be tenant scoped with an explicit IT Admin branch';
  end if;
end;
$$;

rollback;
