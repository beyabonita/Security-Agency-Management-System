-- Keep assigned rosters locked until their current/upcoming duties finish.
alter table public.schedules add column roster_setup_id uuid references public.shift_roster_setups(id);
create index schedules_roster_setup_id on public.schedules(roster_setup_id) where roster_setup_id is not null;

create index schedules_roster_usage on public.schedules(organization_id,end_at)
  where not marked_done and approval_status in ('approved','changed','pending');

-- Earlier schedules stored times only. Match their complete slot timestamps,
-- including overnight duration. Ambiguous legacy slots protect every matching setup.
create function public.roster_setup_in_use(p_setup public.shift_roster_setups)
returns boolean language sql stable set search_path='' as $$
  select exists (
    select 1 from public.schedules s
    where s.organization_id=p_setup.organization_id
      and s.approval_status in ('approved','changed','pending')
      and not s.marked_done and s.end_at>now()
      and (s.roster_setup_id=p_setup.id or (s.roster_setup_id is null and s.dtr_period='auto'
        and exists (select 1 from jsonb_array_elements(p_setup.shifts) slot
          where s.start_at=((s.duty_date+(slot->>'start_time')::time) at time zone 'Asia/Manila')
            and s.end_at=(((s.duty_date+case when (slot->>'end_time')::time<(slot->>'start_time')::time then 1 else 0 end)
              +(slot->>'end_time')::time) at time zone 'Asia/Manila'))))
  )
$$;
revoke all on function public.roster_setup_in_use(public.shift_roster_setups) from public,anon,authenticated;

create function public.list_shift_roster_setups()
returns table(id uuid,name text,shifts jsonb,version integer,in_use boolean)
language plpgsql security definer set search_path='' as $$
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can view shifting setups.' using errcode='42501';
  end if;
  return query select r.id,r.name,r.shifts,r.version,public.roster_setup_in_use(r)
    from public.shift_roster_setups r where r.organization_id=public.current_organization_id()
      and r.archived_at is null order by r.name;
end $$;
revoke all on function public.list_shift_roster_setups() from public,anon;
grant execute on function public.list_shift_roster_setups() to authenticated;

create or replace function public.update_shift_roster_setup(p_setup_id uuid,p_name text,p_shifts jsonb,p_expected_version integer)
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
  if public.roster_setup_in_use(result) then
    raise exception 'This shifting setup is in use. Edit or remove it after its current and upcoming duties finish.';
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

create or replace function public.remove_shift_roster_setup(p_setup_id uuid,p_expected_version integer)
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
  if public.roster_setup_in_use(result) then
    raise exception 'This shifting setup is in use. Edit or remove it after its current and upcoming duties finish.';
  end if;
  update public.shift_roster_setups set archived_at=now(),version=version+1 where id=p_setup_id;
  return p_setup_id;
end $$;
revoke all on function public.remove_shift_roster_setup(uuid,integer) from public,anon;
grant execute on function public.remove_shift_roster_setup(uuid,integer) to authenticated;

-- Require the previewed version when assigning an editable template.


create or replace function public.assign_saved_shift_roster(p_setup_id uuid,p_location_id uuid,p_duty_date date,p_guard_ids uuid[],p_expected_version integer default null)
returns setof public.schedules language plpgsql security definer set search_path='' as $$
declare setup public.shift_roster_setups; i integer; v_key bigint; shift_end timestamptz;
  created public.schedules; remaining integer[]:='{}'; selected_guards uuid[]:='{}'; s text; e text;
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
    for created in select * from public.create_dtr_schedule(p_guard_ids[i],p_location_id,p_duty_date,
      jsonb_build_array(jsonb_build_object('period','auto','start_time',setup.shifts->(i-1)->>'start_time',
        'end_time',setup.shifts->(i-1)->>'end_time','next_day',false))) loop
      update public.schedules set roster_setup_id=p_setup_id where id=created.id returning * into created;
      return next created;
    end loop;
  end loop;
end $$;
revoke all on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[],integer) from public,anon;
grant execute on function public.assign_saved_shift_roster(uuid,uuid,date,uuid[],integer) to authenticated;
notify pgrst,'reload schema';
