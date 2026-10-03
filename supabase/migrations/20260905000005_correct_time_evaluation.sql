-- Evaluate the Guard's actual DTR attendance, not future schedule rows or
-- another Guard's reassigned duty. Preserve the existing RPC and permissions.
create or replace function public.evaluate_time_record(
  p_user_id uuid, p_start_date date, p_end_date date
)
returns table(duty_days integer, completed_days integer, total_minutes integer,
  late_minutes integer, undertime_minutes integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_organization_id uuid;
begin
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Choose a valid date range.';
  end if;
  select p.organization_id into v_organization_id from public.profiles p
  where p.id = p_user_id and p.organization_id is not null and p.role in ('user', 'inspector');
  if v_organization_id is null then raise exception 'Personnel record was not found.'; end if;
  if not public.is_it_admin() and not (
    public.is_admin() and v_organization_id = public.current_organization_id()
  ) then
    raise exception 'You cannot evaluate this personnel record.';
  end if;

  return query
  with recorded as (
    select a.*,
      case when a.clock_out_at is not null then
        greatest(0, floor(extract(epoch from (a.clock_out_at - a.clock_in_at)) / 60))
        else 0 end as worked,
      greatest(0, floor(extract(epoch from (
        least(a.clock_in_at, a.scheduled_end_at) - a.scheduled_start_at
      )) / 60)) as late,
      case when a.clock_out_at is not null then
        greatest(0, floor(extract(epoch from (
          a.scheduled_end_at - greatest(a.clock_out_at, a.scheduled_start_at)
        )) / 60)) else 0 end as shortfall
    from public.attendance_sessions a
    where a.user_id = p_user_id and a.organization_id = v_organization_id
      and a.duty_date between p_start_date and p_end_date
      and a.clock_in_at is not null
  ), attended_days as (
    select a.duty_date, bool_and(a.clock_out_at is not null) as all_recorded_periods_closed
    from recorded a group by a.duty_date
  ), complete_days as (
    select d.duty_date from attended_days d
    where d.all_recorded_periods_closed
      and not exists (
        select 1 from public.schedules s
        where s.user_id = p_user_id and s.organization_id = v_organization_id
          and coalesce(s.duty_date, (s.start_at at time zone 'Asia/Manila')::date) = d.duty_date
          and s.approval_status in ('approved', 'changed')
          and not exists (
            select 1 from recorded a where a.schedule_id = s.id and a.clock_out_at is not null
          )
      )
  )
  select (select count(*)::integer from attended_days),
    (select count(*)::integer from complete_days),
    coalesce(sum(a.worked), 0)::integer,
    coalesce(sum(a.late), 0)::integer,
    coalesce(sum(a.shortfall), 0)::integer
  from recorded a;
end;
$$;

revoke all on function public.evaluate_time_record(uuid, date, date) from public, anon;
grant execute on function public.evaluate_time_record(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
