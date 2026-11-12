-- Migration: Purge duplicate test accounts for Trix E. Aguilar (trixx@gmail.com, trix@gmail.com)
do $$
declare
  r record;
begin
  for r in (
    select id, email from public.profiles
    where lower(email) in ('trixx@gmail.com', 'trix@gmail.com')
       or personnel_id in ('SEC-2026-098', 'SEC-2026-095')
  ) loop
    perform public.purge_personnel_account(r.id);
  end loop;

  -- Also ensure auth users are cleaned up if profiles were detached
  delete from auth.users where lower(email) in ('trixx@gmail.com', 'trix@gmail.com');
end $$;
