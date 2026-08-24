-- Finalize tenant boundaries for legacy security definer helpers.

create or replace function public.prevent_overlapping_active_schedules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.approval_status in ('approved', 'changed') and exists (
    select 1
    from public.schedules existing
    where existing.user_id = new.user_id
      and existing.organization_id = new.organization_id
      and existing.id <> coalesce(new.id, gen_random_uuid())
      and existing.approval_status in ('approved', 'changed')
      and existing.start_at < new.end_at
      and existing.end_at > new.start_at
  ) then
    raise exception 'This guard already has an overlapping active schedule.';
  end if;
  return new;
end;
$$;

create or replace function public.register_device(p_device_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  v_organization_id uuid;
begin
  if not public.is_active_guard() then
    raise exception 'This account is not allowed to use the guard app.';
  end if;
  if p_device_id is null or char_length(trim(p_device_id)) not between 8 and 200 then
    raise exception 'Device registration is invalid. Please reinstall or contact your administrator.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;

  select * into p
  from public.profiles
  where id = auth.uid()
    and organization_id = v_organization_id;
  if not found then
    raise exception 'This account is not allowed to use the guard app.';
  end if;
  if p.device_locked and p.device_id is not null and p.device_id <> p_device_id then
    raise exception 'This account is registered to another device. Ask admin to reset device.';
  end if;
  if p.device_id is null or p.device_id = '' then
    update public.profiles
    set device_id = trim(p_device_id)
    where id = auth.uid()
      and organization_id = v_organization_id;
  end if;
end;
$$;

create or replace function public.complete_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_duty_days integer;
  v_organization_id uuid;
begin
  if not public.is_active_duty_personnel() then
    raise exception 'This account is not allowed to complete a duty schedule.';
  end if;
  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'This account is not assigned to an active organization.';
  end if;

  update public.schedules
  set marked_done = true,
      completed_at = now(),
      completed_by = auth.uid()
  where id = p_schedule_id
    and user_id = auth.uid()
    and organization_id = v_organization_id
    and not marked_done
    and end_at <= now()
  returning duty_days into v_duty_days;
  if not found then
    raise exception 'Schedule cannot be completed yet.';
  end if;

  update public.profiles
  set duty_days_total = duty_days_total + coalesce(v_duty_days, 1)
  where id = auth.uid()
    and organization_id = v_organization_id
    and role = 'user';
end;
$$;

create or replace function public.evaluate_time_record(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns table(
  duty_days integer,
  completed_days integer,
  total_minutes integer,
  late_minutes integer,
  undertime_minutes integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Choose a valid date range.';
  end if;

  select p.organization_id
  into v_organization_id
  from public.profiles p
  where p.id = p_user_id
    and p.organization_id is not null
    and p.role in ('user', 'inspector');
  if v_organization_id is null then
    raise exception 'Personnel record was not found.';
  end if;

  if not public.is_it_admin() and not (
    public.is_admin() and v_organization_id = public.current_organization_id()
  ) then
    raise exception 'You cannot evaluate this personnel record.';
  end if;

  return query
  with duty as (
    select s.id, s.start_at, s.end_at
    from public.schedules s
    where s.user_id = p_user_id
      and s.organization_id = v_organization_id
      and (s.start_at at time zone 'Asia/Manila')::date between p_start_date and p_end_date
      and s.approval_status in ('approved', 'changed')
  ), punches as (
    select a.punch_date,
      min(a.punched_at) filter (where a.punch_type in ('AM In', 'PM In')) first_in,
      max(a.punched_at) filter (where a.punch_type in ('AM Out', 'PM Out')) last_out
    from public.attendance_punches a
    where a.user_id = p_user_id
      and a.organization_id = v_organization_id
      and a.punch_date between p_start_date and p_end_date
    group by a.punch_date
  )
  select
    count(*)::integer,
    count(*) filter (where p.first_in is not null)::integer,
    coalesce(sum(greatest(0, extract(epoch from (p.last_out - p.first_in)) / 60)::integer), 0)::integer,
    coalesce(sum(greatest(0, extract(epoch from (p.first_in - d.start_at)) / 60)::integer), 0)::integer,
    coalesce(sum(greatest(0, extract(epoch from (d.end_at - p.last_out)) / 60)::integer), 0)::integer
  from duty d
  left join punches p
    on p.punch_date = (d.start_at at time zone 'Asia/Manila')::date;
end;
$$;

grant execute on function public.register_device(text),
  public.complete_schedule(uuid),
  public.evaluate_time_record(uuid, date, date)
to authenticated;
