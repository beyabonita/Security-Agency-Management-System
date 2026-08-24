-- Separate universal-system administration from daily HR/Operations work.
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role='admin')
$$;
create or replace function public.is_it_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role='it_admin')
$$;
create or replace function public.is_operations_head() returns boolean language sql stable security definer set search_path = public as $$ select public.is_admin() $$;
create or replace function public.is_operations_staff() returns boolean language sql stable security definer set search_path = public as $$ select public.is_admin() $$;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role in ('admin','it_admin','inspector'))
$$;

drop policy if exists "admin manages profiles" on public.profiles;
create policy "it admin manages profiles" on public.profiles for all to authenticated using (public.is_it_admin()) with check (public.is_it_admin());

create or replace function public.set_personnel_active(p_profile_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only HR / Operations Head can update personnel status.'; end if;
  update public.profiles set active=p_active where id=p_profile_id and role in ('user','inspector');
  if not found then raise exception 'Only Guard or Inspector accounts can be updated here.'; end if;
end $$;
grant execute on function public.set_personnel_active(uuid,boolean) to authenticated;
