-- A contract is an inclusive range of Philippine calendar dates. Legacy unset
-- contracts remain readable; an Admin must configure them before new duty.
alter table public.profiles
  add column contract_start_date date,
  add column contract_end_date date,
  add constraint profiles_contract_period_check check (
    (contract_start_date is null and contract_end_date is null) or
    (role = 'user' and employment_category = 'contract'
      and contract_start_date is not null and contract_end_date is not null
      and contract_start_date >= date '1900-01-01'
      and contract_end_date <= date '9998-12-31'
      and contract_end_date >= contract_start_date)
  );

create or replace function private.contract_allows_duty(
  p_guard uuid, p_start timestamptz, p_end timestamptz
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = p_guard and (
    p.role <> 'user' or p.employment_category = 'regular' or (
      p.contract_start_date is not null and p.contract_end_date is not null
      and p_start >= (p.contract_start_date::timestamp at time zone 'Asia/Manila')
      and p_end <= ((p.contract_end_date + 1)::timestamp at time zone 'Asia/Manila')
      and p_end > p_start
    )
  ));
$$;
revoke all on function private.contract_allows_duty(uuid,timestamptz,timestamptz) from public, anon, authenticated;

create or replace function private.enforce_schedule_contract()
returns trigger language plpgsql security definer set search_path = '' as $$
declare p public.profiles%rowtype;
begin
  if new.approval_status not in ('approved','changed') then return new; end if;
  -- Serialize with category/period edits. Historical completion/cancellation
  -- updates never rewrite the original category or invalidate a time record.
  select * into p from public.profiles where id = new.user_id for share;
  if p.role = 'user' and p.employment_category = 'contract' and (
    p.contract_start_date is null or p.contract_end_date is null or
    new.start_at < (p.contract_start_date::timestamp at time zone 'Asia/Manila') or
    new.end_at > ((p.contract_end_date + 1)::timestamp at time zone 'Asia/Manila')) then
    raise exception 'Duty must start and finish within the Guard contract dates. Set or renew the contract in Personnel.';
  end if;
  new.duty_category := case when p.role = 'user' then p.employment_category else null end;
  return new;
end;
$$;
create trigger enforce_schedule_contract_insert before insert on public.schedules
for each row execute function private.enforce_schedule_contract();
create trigger enforce_schedule_contract_update
before update of user_id,start_at,end_at,approval_status on public.schedules
for each row
when (old.user_id is distinct from new.user_id or old.start_at is distinct from new.start_at
  or old.end_at is distinct from new.end_at or old.approval_status is distinct from new.approval_status)
execute function private.enforce_schedule_contract();

create or replace function private.enforce_clock_in_contract()
returns trigger language plpgsql security definer set search_path = '' as $$
declare p public.profiles%rowtype; s public.schedules%rowtype;
begin
  select * into p from public.profiles where id = new.user_id for share;
  if p.role = 'user' and p.employment_category = 'contract' then
    select * into s from public.schedules where id = new.schedule_id;
    if p.contract_start_date is null or p.contract_end_date is null or
      s.start_at < (p.contract_start_date::timestamp at time zone 'Asia/Manila') or
      s.end_at > ((p.contract_end_date + 1)::timestamp at time zone 'Asia/Manila') or
      (now() at time zone 'Asia/Manila')::date not between p.contract_start_date and p.contract_end_date then
      raise exception 'Time In is unavailable outside your contract period. Ask Admin to set or renew your contract dates.';
    end if;
  end if;
  return new;
end;
$$;
-- INSERT only: always allow the existing validated clock-out flow to finish
-- an already-open duty, including after contract expiry or a category edit.
create trigger enforce_clock_in_contract before insert on public.attendance_sessions
for each row execute function private.enforce_clock_in_contract();
revoke all on function private.enforce_schedule_contract(),private.enforce_clock_in_contract() from public,anon,authenticated;

-- Profile DML remains service-only (20260822000015). No new client write grant.

-- Recheck agency authority at approval as well as submission. A moved personnel
-- pair must not make an old request authorize changes in a different workspace.
create or replace function private.duty_exchange_eligible(
  p_source uuid, p_target uuid, p_ignore_request uuid default null
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.schedules a join public.schedules b
      on b.id = p_target and b.organization_id = a.organization_id and b.user_id <> a.user_id
    join public.profiles pa on pa.id = a.user_id and pa.organization_id = a.organization_id and pa.active and pa.role = 'user'
    join public.profiles pb on pb.id = b.user_id and pb.organization_id = b.organization_id and pb.active and pb.role = 'user'
    join public.locations la on la.id = a.location_id and la.organization_id = a.organization_id and la.active
    join public.locations lb on lb.id = b.location_id and lb.organization_id = b.organization_id and lb.active
    where a.id = p_source and a.id <> b.id
      and a.organization_id = public.current_organization_id()
      and private.contract_allows_duty(a.user_id,b.start_at,b.end_at)
      and private.contract_allows_duty(b.user_id,a.start_at,a.end_at)
      and a.approval_status in ('approved','changed') and b.approval_status in ('approved','changed')
      and a.end_at > now() and b.end_at > now()
      and not a.marked_done and not b.marked_done and a.completed_at is null and b.completed_at is null
      and not exists (select 1 from public.attendance_sessions s where s.schedule_id in (a.id,b.id))
      and not exists (select 1 from public.accomplishment_reports r where r.schedule_id in (a.id,b.id))
      and not exists (select 1 from public.shift_swap_requests r
        where (p_ignore_request is null or r.id <> p_ignore_request)
        and r.status in ('pending_admin','pending_inspector')
        and (r.requested_schedule_id in (a.id,b.id) or r.target_schedule_id in (a.id,b.id)))
      and not exists (select 1 from public.schedules other
        where other.organization_id = a.organization_id and other.id not in (a.id,b.id)
          and other.approval_status in ('approved','changed') and (
            (other.user_id = a.user_id and other.start_at < b.end_at and other.end_at > b.start_at)
            or (other.user_id = b.user_id and other.start_at < a.end_at and other.end_at > a.start_at)))
  );
$$;
