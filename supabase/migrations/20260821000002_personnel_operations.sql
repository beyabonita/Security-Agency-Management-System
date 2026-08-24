-- Personnel, approval, deployment history, reporting and time evaluation.
alter table public.profiles
  add column if not exists employment_category text not null default 'regular' check (employment_category in ('regular', 'contract')),
  add column if not exists inspector_id uuid references public.profiles(id) on delete set null,
  add column if not exists assigned_location_id uuid references public.locations(id) on delete set null,
  add column if not exists duty_days_total integer not null default 0 check (duty_days_total >= 0);
alter table public.schedules
  add column if not exists duty_category text check (duty_category in ('regular', 'contract')),
  add column if not exists approval_status text not null default 'approved' check (approval_status in ('draft', 'approved', 'cancelled', 'changed')),
  add column if not exists approved_by uuid references public.profiles(id),
  add column if not exists duty_days integer not null default 1 check (duty_days > 0);
alter table public.incidents
  add column if not exists incident_title text not null default 'Emergency incident',
  add column if not exists detailed_narrative text not null default '',
  add column if not exists immediate_action text not null default '',
  add column if not exists video_path text,
  add column if not exists video_duration_seconds integer check (video_duration_seconds is null or video_duration_seconds between 1 and 15),
  add column if not exists captured_at timestamptz,
  add column if not exists filed_at timestamptz;

create table if not exists public.guard_assignment_history (
  id uuid primary key default gen_random_uuid(), guard_id uuid not null references public.profiles(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null, assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(), ended_at timestamptz, remarks text not null default '' check (char_length(remarks) <= 1500)
);
create table if not exists public.shift_swap_requests (
  id uuid primary key default gen_random_uuid(), requester_id uuid not null references public.profiles(id) on delete cascade,
  requested_schedule_id uuid not null references public.schedules(id) on delete cascade, target_guard_id uuid references public.profiles(id) on delete set null,
  requested_start_at timestamptz, requested_end_at timestamptz, reason text not null check (char_length(reason) between 5 and 1500),
  status text not null default 'pending_inspector' check (status in ('pending_inspector', 'pending_admin', 'approved', 'rejected', 'cancelled')),
  inspector_id uuid references public.profiles(id), inspector_decision_by uuid references public.profiles(id), inspector_decision_at timestamptz, inspector_note text,
  admin_decision_by uuid references public.profiles(id), admin_decision_at timestamptz, admin_note text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.accomplishment_reports (
  id uuid primary key default gen_random_uuid(), schedule_id uuid not null unique references public.schedules(id) on delete cascade,
  guard_id uuid not null references public.profiles(id) on delete cascade, summary text not null check (char_length(summary) between 10 and 1500),
  detailed_narrative text not null check (char_length(detailed_narrative) between 20 and 5000), issues_encountered text not null default '',
  submitted_at timestamptz not null default now(), reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, review_note text
);
create index if not exists guard_assignment_history_guard_idx on public.guard_assignment_history (guard_id, assigned_at desc);
create index if not exists shift_swap_requests_status_idx on public.shift_swap_requests (status, created_at desc);

create or replace function public.is_operations_staff() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role in ('admin', 'it_admin', 'operations_head'))
$$;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role in ('admin', 'it_admin', 'operations_head', 'inspector'))
$$;
create or replace function public.assign_guard_location(p_guard_id uuid, p_location_id uuid, p_remarks text default '') returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operations_staff() then raise exception 'Only IT Admin or Operations Head can manage deployments.'; end if;
  if not exists (select 1 from public.profiles where id=p_guard_id and role='user') then raise exception 'Guard not found.'; end if;
  if not exists (select 1 from public.locations where id=p_location_id and active) then raise exception 'Active duty location not found.'; end if;
  update public.guard_assignment_history set ended_at=now() where guard_id=p_guard_id and ended_at is null;
  insert into public.guard_assignment_history(guard_id,location_id,assigned_by,remarks) values(p_guard_id,p_location_id,auth.uid(),left(coalesce(p_remarks,''),1500));
  update public.profiles set assigned_location_id=p_location_id where id=p_guard_id;
end $$;
create or replace function public.request_shift_swap(p_schedule_id uuid,p_target_guard_id uuid default null,p_requested_start_at timestamptz default null,p_requested_end_at timestamptz default null,p_reason text default '') returns public.shift_swap_requests language plpgsql security definer set search_path=public as $$
declare r public.shift_swap_requests; v_inspector uuid;
begin
  if not public.is_active_guard() then raise exception 'Only active guards can request schedule changes.'; end if;
  if not exists(select 1 from public.schedules where id=p_schedule_id and user_id=auth.uid() and start_at>now() and approval_status='approved') then raise exception 'Choose an upcoming approved duty schedule.'; end if;
  select inspector_id into v_inspector from public.profiles where id=auth.uid(); if v_inspector is null then raise exception 'No Inspector assigned.'; end if;
  insert into public.shift_swap_requests(requester_id,requested_schedule_id,target_guard_id,requested_start_at,requested_end_at,reason,inspector_id) values(auth.uid(),p_schedule_id,p_target_guard_id,p_requested_start_at,p_requested_end_at,left(p_reason,1500),v_inspector) returning * into r; return r;
end $$;
create or replace function public.review_shift_swap_by_inspector(p_request_id uuid,p_approve boolean,p_note text default '') returns void language plpgsql security definer set search_path=public as $$
begin
 update public.shift_swap_requests set status=case when p_approve then 'pending_admin' else 'rejected' end,inspector_decision_by=auth.uid(),inspector_decision_at=now(),inspector_note=left(coalesce(p_note,''),1500),updated_at=now()
 where id=p_request_id and inspector_id=auth.uid() and status='pending_inspector' and public.current_role()='inspector'; if not found then raise exception 'Request not available for review.'; end if;
end $$;
create or replace function public.decide_shift_swap_by_admin(p_request_id uuid,p_approve boolean,p_note text default '') returns void language plpgsql security definer set search_path=public as $$
declare r public.shift_swap_requests%rowtype;
begin
 if not public.is_operations_staff() then raise exception 'Only IT Admin or Operations Head can finalize a schedule change.'; end if;
 select * into r from public.shift_swap_requests where id=p_request_id and status='pending_admin' for update; if not found then raise exception 'Request is not awaiting final approval.'; end if;
 if p_approve then update public.schedules set user_id=coalesce(r.target_guard_id,user_id),start_at=coalesce(r.requested_start_at,start_at),end_at=coalesce(r.requested_end_at,end_at),approval_status='changed',approved_by=auth.uid() where id=r.requested_schedule_id; end if;
 update public.shift_swap_requests set status=case when p_approve then 'approved' else 'rejected' end,admin_decision_by=auth.uid(),admin_decision_at=now(),admin_note=left(coalesce(p_note,''),1500),updated_at=now() where id=p_request_id;
end $$;
create or replace function public.evaluate_time_record(p_user_id uuid,p_start_date date,p_end_date date) returns table(duty_days integer,completed_days integer,total_minutes integer,late_minutes integer,undertime_minutes integer) language sql stable security definer set search_path=public as $$
 with duty as(select id,start_at,end_at from public.schedules where user_id=p_user_id and start_at::date between p_start_date and p_end_date and approval_status in ('approved','changed')), punches as(select punch_date,min(punched_at) filter(where punch_type in('AM In','PM In')) first_in,max(punched_at) filter(where punch_type in('AM Out','PM Out')) last_out from public.attendance_punches where user_id=p_user_id and punch_date between p_start_date and p_end_date group by punch_date)
 select count(*)::integer,count(*) filter(where p.first_in is not null)::integer,coalesce(sum(greatest(0,extract(epoch from(p.last_out-p.first_in))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(p.first_in-d.start_at))/60)::integer),0)::integer,coalesce(sum(greatest(0,extract(epoch from(d.end_at-p.last_out))/60)::integer),0)::integer from duty d left join punches p on p.punch_date=(d.start_at at time zone 'Asia/Manila')::date
$$;

alter table public.guard_assignment_history enable row level security;
alter table public.shift_swap_requests enable row level security;
alter table public.accomplishment_reports enable row level security;
create policy "assignment history visibility" on public.guard_assignment_history for select to authenticated using (guard_id=auth.uid() or public.is_staff());
create policy "swap request visibility" on public.shift_swap_requests for select to authenticated using(requester_id=auth.uid() or inspector_id=auth.uid() or public.is_operations_staff());
create policy "accomplishment visibility" on public.accomplishment_reports for select to authenticated using(guard_id=auth.uid() or public.is_staff());
create policy "guard submits accomplishment" on public.accomplishment_reports for insert to authenticated with check(guard_id=auth.uid() and public.is_active_guard());
grant select on public.guard_assignment_history,public.shift_swap_requests,public.accomplishment_reports to authenticated;
grant execute on function public.assign_guard_location(uuid,uuid,text),public.request_shift_swap(uuid,uuid,timestamptz,timestamptz,text),public.review_shift_swap_by_inspector(uuid,boolean,text),public.decide_shift_swap_by_admin(uuid,boolean,text),public.evaluate_time_record(uuid,date,date) to authenticated;
alter publication supabase_realtime add table public.guard_assignment_history,public.shift_swap_requests,public.accomplishment_reports;
