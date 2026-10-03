-- A roster date is not over when its first shift ends. Create only remaining
-- slots, keeping original shift times and all historical attendance untouched.
create or replace function public.create_shift_roster(p_location_id uuid,p_duty_date date,
  p_shift_count integer,p_guard_ids uuid[])
returns setof public.schedules language plpgsql security definer set search_path='' as $$
declare i integer; starts text[]; ends text[]; v_key bigint;
  remaining integer[]:='{}'; selected_guards uuid[]:='{}'; shift_end timestamptz;
begin
  if not coalesce(public.is_admin(),false) or not coalesce(public.current_organization_is_active(),false) then
    raise exception 'Only an active Operations Head can assign a shift roster.' using errcode='42501';
  end if;
  if p_duty_date is null or not isfinite(p_duty_date) or p_duty_date<(now() at time zone 'Asia/Manila')::date then
    raise exception 'Choose today or a future schedule date.';
  end if;
  if p_shift_count is null or p_shift_count not in (2,3)
    or cardinality(p_guard_ids) is distinct from p_shift_count
    or array_ndims(p_guard_ids) is distinct from 1 or array_lower(p_guard_ids,1) is distinct from 1 then
    raise exception 'Choose a different Guard for each remaining shift.';
  end if;
  starts:=case when p_shift_count=2 then array['06:00','18:00'] else array['06:00','14:00','22:00'] end;
  ends:=case when p_shift_count=2 then array['18:00','06:00'] else array['14:00','22:00','06:00'] end;
  for i in 1..p_shift_count loop
    shift_end:=((p_duty_date+case when ends[i]::time<=starts[i]::time then 1 else 0 end)+ends[i]::time) at time zone 'Asia/Manila';
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
      jsonb_build_array(jsonb_build_object('period','auto','start_time',starts[i],'end_time',ends[i],'next_day',false)));
  end loop;
end;
$$;
revoke all on function public.create_shift_roster(uuid,date,integer,uuid[]) from public,anon;
grant execute on function public.create_shift_roster(uuid,date,integer,uuid[]) to authenticated;
notify pgrst,'reload schema';
