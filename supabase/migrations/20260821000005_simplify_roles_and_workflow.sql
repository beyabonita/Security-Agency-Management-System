-- Keep the system simple: one Admin manages the complete operation.
-- Existing IT Admin and HR/Operations Head accounts become Admin accounts.
update public.profiles set role = 'admin' where role in ('it_admin', 'operations_head');

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin')
$$;
create or replace function public.is_it_admin() returns boolean language sql stable security definer set search_path = public as $$ select public.is_admin() $$;
create or replace function public.is_operations_head() returns boolean language sql stable security definer set search_path = public as $$ select public.is_admin() $$;
create or replace function public.is_operations_staff() returns boolean language sql stable security definer set search_path = public as $$ select public.is_admin() $$;

drop policy if exists "it admin manages profiles" on public.profiles;
create policy "admin manages profiles" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "operations manages locations" on public.locations;
create policy "admin manages locations" on public.locations for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "operations manages schedules" on public.schedules;
create policy "admin manages schedules" on public.schedules for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "operations delete incidents" on public.incidents;
create policy "admin deletes incidents" on public.incidents for delete to authenticated using (public.is_admin());
