-- Templates only: schedules and attendance already store independent snapshots.
alter table public.shift_roster_setups
  add column archived_at timestamptz,
  add column version integer not null default 1;

create function public.roster_setup_signature(p_shifts jsonb)
returns text language sql immutable set search_path='' as $$
  select string_agg((value->>'start_time')||'-'||(value->>'end_time'),',' order by ordinality)
  from jsonb_array_elements(p_shifts) with ordinality
$$;
revoke all on function public.roster_setup_signature(jsonb) from public,anon,authenticated;
alter table public.shift_roster_setups add column shift_signature text
  generated always as (public.roster_setup_signature(shifts)) stored;

-- Retain duplicate template records as archived; never delete duty history.
update public.shift_roster_setups set archived_at=now(),version=version+1
where shift_signature in ('06:00-18:00,18:00-06:00','06:00-14:00,14:00-22:00,22:00-06:00');
with duplicates as (
  select id,row_number() over(partition by organization_id,shift_signature order by created_at,id) as position
  from public.shift_roster_setups where archived_at is null
)
update public.shift_roster_setups s set archived_at=now(),version=version+1
from duplicates d where d.id=s.id and d.position>1;
drop index public.shift_roster_setups_agency_name;
create unique index shift_roster_setups_agency_name on public.shift_roster_setups(organization_id,lower(name)) where archived_at is null;
create unique index shift_roster_setups_agency_times on public.shift_roster_setups(organization_id,shift_signature) where archived_at is null;
alter policy "Operations Heads read agency shifting setups" on public.shift_roster_setups
using (archived_at is null and organization_id=public.current_organization_id()
  and public.is_admin() and public.current_organization_is_active());

create function public.check_saved_roster_values(p_name text,p_shifts jsonb)
returns void language plpgsql set search_path='' as $$
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then
    raise exception 'Enter a setup name of 1 to 80 characters.';
  end if;
  if not public.valid_roster_setup(p_shifts) then
    raise exception 'Use 2 to 12 shifts in start-time order, covering 24 hours without gaps or overlaps.';
  end if;
  if public.roster_setup_signature(p_shifts)='06:00-18:00,18:00-06:00' then
    raise exception 'These shift times already exist in 2 Shifts. Select that setup instead.';
  end if;
  if public.roster_setup_signature(p_shifts)='06:00-14:00,14:00-22:00,22:00-06:00' then
    raise exception 'These shift times already exist in 3 Shifts. Select that setup instead.';
  end if;
  if lower(btrim(p_name)) in ('2 shifts','3 shifts') then
    raise exception 'That name belongs to a standard setup. Choose a different name.';
  end if;
end $$;
revoke all on function public.check_saved_roster_values(text,jsonb) from public,anon,authenticated;

create or replace function public.save_shift_roster_setup(p_name text,p_shifts jsonb)
returns public.shift_roster_setups language plpgsql security definer set search_path='' as $$
declare result public.shift_roster_setups; v_org uuid:=public.current_organization_id();
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) or v_org is null then
    raise exception 'Only an active Operations Head can create shifting setups.' using errcode='42501';
  end if;
  perform public.check_saved_roster_values(p_name,p_shifts);
  insert into public.shift_roster_setups(organization_id,name,shifts,created_by)
    values(v_org,btrim(p_name),p_shifts,auth.uid()) on conflict do nothing returning * into result;
  if result.id is null then
    select * into result from public.shift_roster_setups where organization_id=v_org
      and lower(name)=lower(btrim(p_name)) and archived_at is null;
    if result.id is null or result.shift_signature is distinct from public.roster_setup_signature(p_shifts) then
      raise exception 'A setup with the same name or shift times already exists. Select or edit the existing setup.';
    end if;
  end if;
  return result;
end $$;

create function public.update_shift_roster_setup(p_setup_id uuid,p_name text,p_shifts jsonb,p_expected_version integer)
returns public.shift_roster_setups language plpgsql security definer set search_path='' as $$
declare result public.shift_roster_setups;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can edit shifting setups.' using errcode='42501';
  end if;
  select * into result from public.shift_roster_setups where id=p_setup_id
    and organization_id=public.current_organization_id() and archived_at is null for update;
  if not found then raise exception 'This setup is no longer available. Reload saved setups.'; end if;
  if result.version is distinct from p_expected_version then
    raise exception 'This setup changed in another session. Reload saved setups before editing.';
  end if;
  perform public.check_saved_roster_values(p_name,p_shifts);
  update public.shift_roster_setups set name=btrim(p_name),shifts=p_shifts,version=version+1
    where id=p_setup_id returning * into result;
  return result;
exception when unique_violation then
  raise exception 'A setup with the same name or shift times already exists. Choose different values.';
end $$;
revoke all on function public.update_shift_roster_setup(uuid,text,jsonb,integer) from public,anon;
grant execute on function public.update_shift_roster_setup(uuid,text,jsonb,integer) to authenticated;

create function public.remove_shift_roster_setup(p_setup_id uuid,p_expected_version integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare result public.shift_roster_setups;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can remove shifting setups.' using errcode='42501';
  end if;
  select * into result from public.shift_roster_setups where id=p_setup_id
    and organization_id=public.current_organization_id() for update;
  if not found then raise exception 'This setup is no longer available. Reload saved setups.'; end if;
  if result.archived_at is not null then return result.id; end if;
  if result.version is distinct from p_expected_version then
    raise exception 'This setup changed in another session. Reload saved setups before removing it.';
  end if;
  update public.shift_roster_setups set archived_at=now(),version=version+1 where id=p_setup_id;
  return p_setup_id;
end $$;
revoke all on function public.remove_shift_roster_setup(uuid,integer) from public,anon;
grant execute on function public.remove_shift_roster_setup(uuid,integer) to authenticated;

-- Require the previewed version when assigning an editable template.
drop function public.assign_saved_shift_roster(uuid,uuid,date,uuid[]);

create function public.assign_saved_shift_roster(p_setup_id uuid,p_location_id uuid,p_duty_date date,p_guard_ids uuid[],p_expected_version integer default null)
returns setof public.schedules language plpgsql security definer set search_path='' as $$
declare setup public.shift_roster_setups; i integer; v_key bigint; shift_end timestamptz;
  remaining integer[]:='{}'; selected_guards uuid[]:='{}'; s text; e text;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can assign a shift roster.' using errcode='42501';
  end if;
  select * into setup from public.shift_roster_setups
    where id=p_setup_id and organization_id=public.current_organization_id() and archived_at is null for share;
  if not found then raise exception 'This setup is no longer available. Reload saved setups.'; end if;
  if setup.version is distinct from p_expected_version then
    raise exception 'This setup changed. Reload saved setups and review the shift times before assigning.';
  end if;
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
revoke all on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[],integer) from public,anon;
grant execute on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[],integer) to authenticated;
notify pgrst,'reload schema';
