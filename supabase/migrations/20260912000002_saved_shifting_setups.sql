-- Reusable agency-owned 24-hour rosters. Assignment snapshots times through
-- create_dtr_schedule; a saved setup never rewrites attendance or old schedules.
create function public.valid_roster_setup(p_shifts jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare i integer; n integer; s text; e text; previous_start text;
begin
  if jsonb_typeof(p_shifts) is distinct from 'array' then return false; end if;
  n:=jsonb_array_length(p_shifts);
  if n not between 2 and 12 then return false; end if;
  for i in 0..n-1 loop
    s:=p_shifts->i->>'start_time'; e:=p_shifts->i->>'end_time';
    if jsonb_typeof(p_shifts->i) is distinct from 'object'
      or jsonb_typeof(p_shifts->i->'start_time') is distinct from 'string'
      or jsonb_typeof(p_shifts->i->'end_time') is distinct from 'string'
      or s !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or e !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or s=e or (i>0 and s<=previous_start)
      or e is distinct from (p_shifts->((i+1)%n)->>'start_time') then return false; end if;
    previous_start:=s;
  end loop;
  return true;
end $$;
revoke all on function public.valid_roster_setup(jsonb) from public,anon,authenticated;

create table public.shift_roster_setups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (name=btrim(name) and char_length(name) between 1 and 80),
  shifts jsonb not null check (public.valid_roster_setup(shifts)),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index shift_roster_setups_agency_name on public.shift_roster_setups(organization_id,lower(name));
alter table public.shift_roster_setups enable row level security;
revoke all on public.shift_roster_setups from public,anon,authenticated;
grant select on public.shift_roster_setups to authenticated;
create policy "Operations Heads read agency shifting setups" on public.shift_roster_setups
  for select to authenticated using (
    organization_id=public.current_organization_id() and public.is_admin()
    and public.current_organization_is_active());

create function public.save_shift_roster_setup(p_name text,p_shifts jsonb)
returns public.shift_roster_setups language plpgsql security definer set search_path='' as $$
declare result public.shift_roster_setups; v_org uuid:=public.current_organization_id();
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) or v_org is null then
    raise exception 'Only an active Operations Head can create shifting setups.' using errcode='42501';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then
    raise exception 'Enter a setup name of 1 to 80 characters.';
  end if;
  if not public.valid_roster_setup(p_shifts) then
    raise exception 'Use 2 to 12 shifts in start-time order, covering 24 hours without gaps or overlaps. The final shift ends at the first shift start time.';
  end if;
  insert into public.shift_roster_setups(organization_id,name,shifts,created_by)
    values(v_org,btrim(p_name),p_shifts,auth.uid()) on conflict do nothing returning * into result;
  if result.id is null then
    select * into result from public.shift_roster_setups where organization_id=v_org and lower(name)=lower(btrim(p_name));
    -- Retrying an identical save after a network failure is safe.
    if result.shifts is distinct from p_shifts then
      raise exception 'A shifting setup already uses that name. Choose another name.';
    end if;
  end if;
  return result;
end $$;
revoke all on function public.save_shift_roster_setup(text,jsonb) from public,anon;
grant execute on function public.save_shift_roster_setup(text,jsonb) to authenticated;

create function public.assign_saved_shift_roster(p_setup_id uuid,p_location_id uuid,p_duty_date date,p_guard_ids uuid[])
returns setof public.schedules language plpgsql security definer set search_path='' as $$
declare setup public.shift_roster_setups; i integer; v_key bigint; shift_end timestamptz;
  remaining integer[]:='{}'; selected_guards uuid[]:='{}'; s text; e text;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can assign a shift roster.' using errcode='42501';
  end if;
  select * into setup from public.shift_roster_setups
    where id=p_setup_id and organization_id=public.current_organization_id() for share;
  if not found then raise exception 'Choose a saved shifting setup from your agency.'; end if;
  if p_duty_date is null or not isfinite(p_duty_date) or p_duty_date<(now() at time zone 'Asia/Manila')::date then
    raise exception 'Choose today or a future schedule date.';
  end if;
  if cardinality(p_guard_ids) is distinct from jsonb_array_length(setup.shifts)
    or array_ndims(p_guard_ids) is distinct from 1 or array_lower(p_guard_ids,1) is distinct from 1 then
    raise exception 'Choose a different Guard for each remaining shift.';
  end if;
  for i in 1..jsonb_array_length(setup.shifts) loop
    s:=setup.shifts->(i-1)->>'start_time'; e:=setup.shifts->(i-1)->>'end_time';
    shift_end:=((p_duty_date+case when e::time<s::time then 1 else 0 end)+e::time) at time zone 'Asia/Manila';
    if shift_end<=now() then continue; end if;
    remaining:=array_append(remaining,i);
    selected_guards:=array_append(selected_guards,p_guard_ids[i]);
  end loop;
  if cardinality(remaining)=0 then raise exception 'No ongoing or upcoming shifts remain on this date.'; end if;
  if (select count(distinct g) from unnest(selected_guards) g)<>cardinality(remaining) then
    raise exception 'Choose a different Guard for each remaining shift.';
  end if;
  for v_key in select distinct pg_catalog.hashtextextended(public.current_organization_id()::text||':'||g::text,0)
    from unnest(selected_guards) g order by 1 loop perform pg_catalog.pg_advisory_xact_lock(v_key); end loop;
  if exists(select 1 from unnest(selected_guards) g where not exists(select 1 from public.profiles p
    where p.id=g and p.organization_id=public.current_organization_id() and p.active and p.role='user')) then
    raise exception 'All assigned Guards must be active in your agency.';
  end if;
  foreach i in array remaining loop
    return query select * from public.create_dtr_schedule(p_guard_ids[i],p_location_id,p_duty_date,
      jsonb_build_array(jsonb_build_object('period','auto','start_time',setup.shifts->(i-1)->>'start_time',
        'end_time',setup.shifts->(i-1)->>'end_time','next_day',false)));
  end loop;
end $$;
revoke all on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[]) from public,anon;
grant execute on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[]) to authenticated;
notify pgrst,'reload schema';
