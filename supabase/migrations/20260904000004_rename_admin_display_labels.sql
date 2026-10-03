-- Keep the stable role key (`admin`) while presenting that agency role simply as
-- "Admin" in user-facing database errors and generated notifications.
do $$
declare
  v_function record;
  v_definition text;
  v_updated_definition text;
  v_updated_count integer := 0;
begin
  for v_function in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        pg_get_functiondef(p.oid) like '%HR / Operations%'
        or pg_get_functiondef(p.oid) like '%Operations Head%'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_updated_definition := replace(v_definition, 'HR / Operations Heads', 'Admins');
    v_updated_definition := replace(v_updated_definition, 'HR / Operations Head', 'Admin');
    v_updated_definition := replace(v_updated_definition, 'HR / Operations', 'Admin');
    v_updated_definition := replace(v_updated_definition, 'Operations Head', 'Admin');

    if v_updated_definition is distinct from v_definition then
      execute v_updated_definition;
      v_updated_count := v_updated_count + 1;
    end if;
  end loop;

  if v_updated_count <> 12 then
    raise exception 'Expected to update 12 user-facing database functions, updated %', v_updated_count;
  end if;
end
$$;
