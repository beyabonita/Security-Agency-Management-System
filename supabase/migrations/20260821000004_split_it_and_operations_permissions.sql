-- Separate system administration from daily security-workforce operations.
-- The legacy `admin` role remains full-access while existing accounts are migrated.
create or replace function public.is_it_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and active and role in ('admin', 'it_admin')
  )
$$;

create or replace function public.is_operations_head() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and active and role in ('admin', 'operations_head')
  )
$$;

create or replace function public.is_operations_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_operations_head()
$$;

drop policy if exists "staff manages profiles" on public.profiles;
create policy "it admin manages profiles" on public.profiles for all
  to authenticated using (public.is_it_admin()) with check (public.is_it_admin());

drop policy if exists "admin manages locations" on public.locations;
create policy "operations manages locations" on public.locations for all
  to authenticated using (public.is_operations_head()) with check (public.is_operations_head());

drop policy if exists "admin manages schedules" on public.schedules;
create policy "operations manages schedules" on public.schedules for all
  to authenticated using (public.is_operations_head()) with check (public.is_operations_head());

drop policy if exists "admins delete incidents" on public.incidents;
create policy "operations delete incidents" on public.incidents for delete
  to authenticated using (public.is_operations_head());

