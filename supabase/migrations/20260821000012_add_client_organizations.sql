-- Multi-client platform model: IT Admin onboards organizations; each organization's
-- HR / Operations Head manages only its own guards, inspectors, posts and reports.
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,80}$'),
  contact_name text not null default '',
  contact_email text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);

alter table public.profiles add column if not exists organization_id uuid references public.organizations(id) on delete set null;
alter table public.locations add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.schedules add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.attendance_punches add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.incidents add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.guard_assignment_history add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.shift_swap_requests add column if not exists organization_id uuid references public.organizations(id) on delete cascade;
alter table public.accomplishment_reports add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

-- Keep the existing installation together as one client without importing or moving data.
do $$
declare v_default_org uuid;
begin
  select id into v_default_org from public.organizations where slug='legacy-default';
  if v_default_org is null then
    insert into public.organizations(name,slug,contact_name,contact_email)
    values('Default Organization','legacy-default','','') returning id into v_default_org;
  end if;
  update public.profiles set organization_id=v_default_org where organization_id is null and role <> 'it_admin';
  update public.locations set organization_id=v_default_org where organization_id is null;
  update public.schedules set organization_id=v_default_org where organization_id is null;
  update public.attendance_punches set organization_id=v_default_org where organization_id is null;
  update public.incidents set organization_id=v_default_org where organization_id is null;
  update public.guard_assignment_history set organization_id=v_default_org where organization_id is null;
  update public.shift_swap_requests set organization_id=v_default_org where organization_id is null;
  update public.accomplishment_reports set organization_id=v_default_org where organization_id is null;
end $$;

alter table public.locations alter column organization_id set not null;
alter table public.schedules alter column organization_id set not null;
alter table public.attendance_punches alter column organization_id set not null;
alter table public.incidents alter column organization_id set not null;
alter table public.guard_assignment_history alter column organization_id set not null;
alter table public.shift_swap_requests alter column organization_id set not null;
alter table public.accomplishment_reports alter column organization_id set not null;

create or replace function public.current_organization_id() returns uuid language sql stable security definer set search_path=public as $$
  select organization_id from public.profiles where id=auth.uid() and active
$$;
create or replace function public.current_organization_is_active() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles p join public.organizations o on o.id=p.organization_id and o.active where p.id=auth.uid() and p.active)
$$;
create or replace function public.is_same_organization(p_organization_id uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.is_it_admin() or (p_organization_id is not null and p_organization_id=public.current_organization_id() and public.current_organization_is_active())
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role='admin') and public.current_organization_is_active()
$$;
create or replace function public.is_operations_head() returns boolean language sql stable security definer set search_path=public as $$ select public.is_admin() $$;
create or replace function public.is_operations_staff() returns boolean language sql stable security definer set search_path=public as $$ select public.is_admin() $$;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path=public as $$
  select public.is_it_admin() or (public.current_organization_is_active() and exists(select 1 from public.profiles where id=auth.uid() and active and role in ('admin','inspector')))
$$;
create or replace function public.is_active_guard() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role='user') and public.current_organization_is_active()
$$;
create or replace function public.is_active_duty_personnel() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role in ('user','inspector')) and public.current_organization_is_active()
$$;

alter table public.locations alter column organization_id set default public.current_organization_id();
alter table public.schedules alter column organization_id set default public.current_organization_id();
alter table public.incidents alter column organization_id set default public.current_organization_id();
alter table public.guard_assignment_history alter column organization_id set default public.current_organization_id();
alter table public.shift_swap_requests alter column organization_id set default public.current_organization_id();
alter table public.accomplishment_reports alter column organization_id set default public.current_organization_id();

create index if not exists profiles_organization_idx on public.profiles(organization_id);
create index if not exists locations_organization_idx on public.locations(organization_id);
create index if not exists schedules_organization_idx on public.schedules(organization_id);
create index if not exists incidents_organization_idx on public.incidents(organization_id);

alter table public.organizations enable row level security;
create policy "it admin manages organizations" on public.organizations for all to authenticated using (public.is_it_admin()) with check (public.is_it_admin());
create policy "organization members read own organization" on public.organizations for select to authenticated using (id=public.current_organization_id());

drop policy if exists "read own profile or staff" on public.profiles;
drop policy if exists "admin manages profiles" on public.profiles;
drop policy if exists "it admin manages profiles" on public.profiles;
create policy "tenant profile visibility" on public.profiles for select to authenticated using (
  id=auth.uid() or public.is_it_admin() or (organization_id=public.current_organization_id() and public.is_staff())
);
create policy "it admin manages profiles" on public.profiles for all to authenticated using (public.is_it_admin()) with check (public.is_it_admin());

drop policy if exists "read assigned locations" on public.locations;
drop policy if exists "admin manages locations" on public.locations;
drop policy if exists "operations manages locations" on public.locations;
create policy "tenant location visibility" on public.locations for select to authenticated using (
  public.is_it_admin() or (organization_id=public.current_organization_id() and (public.is_staff() or exists(select 1 from public.schedules s where s.location_id=locations.id and s.user_id=auth.uid())))
);
create policy "operations manages tenant locations" on public.locations for all to authenticated using (public.is_admin() and organization_id=public.current_organization_id()) with check (public.is_admin() and organization_id=public.current_organization_id());

drop policy if exists "read own schedules or staff" on public.schedules;
drop policy if exists "admin manages schedules" on public.schedules;
drop policy if exists "operations manages schedules" on public.schedules;
create policy "tenant schedule visibility" on public.schedules for select to authenticated using (
  public.is_it_admin() or user_id=auth.uid() or (organization_id=public.current_organization_id() and public.is_staff())
);
create policy "operations manages tenant schedules" on public.schedules for all to authenticated using (public.is_admin() and organization_id=public.current_organization_id()) with check (public.is_admin() and organization_id=public.current_organization_id() and exists(select 1 from public.profiles p where p.id=schedules.user_id and p.organization_id=schedules.organization_id));

drop policy if exists "read own attendance or staff" on public.attendance_punches;
create policy "tenant attendance visibility" on public.attendance_punches for select to authenticated using (
  public.is_it_admin() or user_id=auth.uid() or (organization_id=public.current_organization_id() and public.is_staff())
);

drop policy if exists "read own incidents or staff" on public.incidents;
drop policy if exists "active guards create incidents" on public.incidents;
drop policy if exists "admins delete incidents" on public.incidents;
drop policy if exists "operations delete incidents" on public.incidents;
create policy "tenant incident visibility" on public.incidents for select to authenticated using (
  public.is_it_admin() or user_id=auth.uid() or (organization_id=public.current_organization_id() and public.is_staff())
);
create policy "active tenant personnel create incidents" on public.incidents for insert to authenticated with check (user_id=auth.uid() and organization_id=public.current_organization_id() and public.is_active_duty_personnel());
create policy "operations delete tenant incidents" on public.incidents for delete to authenticated using (public.is_admin() and organization_id=public.current_organization_id());

drop policy if exists "assignment history visibility" on public.guard_assignment_history;
drop policy if exists "swap request visibility" on public.shift_swap_requests;
drop policy if exists "accomplishment visibility" on public.accomplishment_reports;
drop policy if exists "guard submits accomplishment" on public.accomplishment_reports;
create policy "tenant assignment history visibility" on public.guard_assignment_history for select to authenticated using (guard_id=auth.uid() or public.is_it_admin() or (organization_id=public.current_organization_id() and public.is_staff()));
create policy "tenant swap request visibility" on public.shift_swap_requests for select to authenticated using (requester_id=auth.uid() or inspector_id=auth.uid() or public.is_it_admin() or (organization_id=public.current_organization_id() and public.is_operations_staff()));
create policy "tenant accomplishment visibility" on public.accomplishment_reports for select to authenticated using (guard_id=auth.uid() or public.is_it_admin() or (organization_id=public.current_organization_id() and public.is_staff()));
create policy "guard submits tenant accomplishment" on public.accomplishment_reports for insert to authenticated with check (guard_id=auth.uid() and organization_id=public.current_organization_id() and public.is_active_guard());

create or replace function public.set_personnel_active(p_profile_id uuid,p_active boolean) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Only HR / Operations Head can update personnel status.'; end if;
  update public.profiles set active=p_active where id=p_profile_id and role in ('user','inspector') and organization_id=public.current_organization_id();
  if not found then raise exception 'Guard or Inspector account was not found in your organization.'; end if;
end $$;

create or replace function public.assign_guard_location(p_guard_id uuid,p_location_id uuid,p_remarks text default '') returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_operations_staff() then raise exception 'Only HR / Operations Head can manage deployments.'; end if;
  if not exists(select 1 from public.profiles where id=p_guard_id and role='user' and organization_id=public.current_organization_id()) then raise exception 'Guard not found in your organization.'; end if;
  if not exists(select 1 from public.locations where id=p_location_id and active and organization_id=public.current_organization_id()) then raise exception 'Active duty location not found in your organization.'; end if;
  update public.guard_assignment_history set ended_at=now() where guard_id=p_guard_id and ended_at is null and organization_id=public.current_organization_id();
  insert into public.guard_assignment_history(guard_id,location_id,assigned_by,remarks,organization_id) values(p_guard_id,p_location_id,auth.uid(),left(coalesce(p_remarks,''),1500),public.current_organization_id());
  update public.profiles set assigned_location_id=p_location_id where id=p_guard_id and organization_id=public.current_organization_id();
end $$;

create or replace function public.evaluate_time_record(p_user_id uuid,p_start_date date,p_end_date date) returns table(duty_days integer,completed_days integer,total_minutes integer,late_minutes integer,undertime_minutes integer) language plpgsql stable security definer set search_path=public as $$
begin
  if not (public.is_it_admin() or (public.is_admin() and exists(select 1 from public.profiles where id=p_user_id and organization_id=public.current_organization_id()))) then raise exception 'You cannot evaluate this personnel record.'; end if;
  return query with duty as(select id,start_at,end_at from public.schedules where user_id=p_user_id and start_at::date between p_start_date and p_end_date and approval_status in ('approved','changed')), punches as(select punch_date,min(punched_at) filter(where punch_type in('AM In','PM In')) first_in,max(punched_at) filter(where punch_type in('AM Out','PM Out')) last_out from public.attendance_punches where user_id=p_user_id and punch_date between p_start_date and p_end_date group by punch_date)
  select count(*)::integer,count(*) filter(where p.first_in is not null)::integer,coalesce(sum(greatest(0,extract(epoch from(p.last_out-p.first_in))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(p.first_in-d.start_at))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(d.end_at-p.last_out))/60)::integer),0)::integer from duty d left join punches p on p.punch_date=(d.start_at at time zone 'Asia/Manila')::date;
end $$;

grant select on public.organizations to authenticated;
grant execute on function public.current_organization_id(),public.set_personnel_active(uuid,boolean),public.assign_guard_location(uuid,uuid,text),public.evaluate_time_record(uuid,date,date) to authenticated;
