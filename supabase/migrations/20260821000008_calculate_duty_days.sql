-- Initialise cumulative duty days from already completed schedules.
update public.profiles profile
set duty_days_total = greatest(
  profile.duty_days_total,
  coalesce((
    select sum(schedule.duty_days)::integer
    from public.schedules schedule
    where schedule.user_id=profile.id and schedule.marked_done
  ), 0)
)
where profile.role='user';

create or replace function public.evaluate_time_record(p_user_id uuid,p_start_date date,p_end_date date)
returns table(duty_days integer,completed_days integer,total_minutes integer,late_minutes integer,undertime_minutes integer)
language sql stable security definer set search_path = public as $$
 with duty as(select id,start_at,end_at,duty_days from public.schedules where user_id=p_user_id and start_at::date between p_start_date and p_end_date and approval_status in ('approved','changed')),
 punches as(select punch_date,min(punched_at) filter(where punch_type in('AM In','PM In')) first_in,max(punched_at) filter(where punch_type in('AM Out','PM Out')) last_out from public.attendance_punches where user_id=p_user_id and punch_date between p_start_date and p_end_date group by punch_date)
 select coalesce(sum(d.duty_days),0)::integer,count(*) filter(where p.first_in is not null)::integer,coalesce(sum(greatest(0,extract(epoch from(p.last_out-p.first_in))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(p.first_in-d.start_at))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(d.end_at-p.last_out))/60)::integer),0)::integer from duty d left join punches p on p.punch_date=(d.start_at at time zone 'Asia/Manila')::date
$$;
