-- Schedule writes read locations to validate tenant ownership. The locations
-- SELECT policy must not expand schedules' RLS again (SQLSTATE 42P17).
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.has_schedule_at_location(p_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.schedules s
    where s.location_id = p_location_id
      and s.user_id = (select auth.uid())
      and s.organization_id = public.current_organization_id()
  );
$$;

revoke all on function private.has_schedule_at_location(uuid) from public, anon;
grant execute on function private.has_schedule_at_location(uuid) to authenticated;

drop policy if exists "tenant location visibility" on public.locations;
create policy "tenant location visibility"
on public.locations
for select to authenticated
using (
  public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and (public.is_staff() or private.has_schedule_at_location(id))
  )
);

-- Never cascade a schedule deletion into duty reports or approval history.
-- Keep the attendance FK intact as the final concurrency/integrity safeguard.
create or replace function public.prevent_schedule_history_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.attendance_sessions where schedule_id = old.id) then
    raise exception 'This schedule has recorded attendance and must be kept for the guard''s DTR.'
      using detail = 'SCHEDULE_ATTENDANCE_HISTORY';
  end if;
  if old.marked_done or old.completed_at is not null then
    raise exception 'Completed duty schedules must be kept for historical records.'
      using detail = 'SCHEDULE_COMPLETED_HISTORY';
  end if;
  if exists (select 1 from public.accomplishment_reports where schedule_id = old.id) then
    raise exception 'This schedule has an accomplishment report and must be kept for historical records.'
      using detail = 'SCHEDULE_REPORT_HISTORY';
  end if;
  if exists (select 1 from public.shift_swap_requests where requested_schedule_id = old.id) then
    raise exception 'This schedule has a shift-change request and must be kept for approval history.'
      using detail = 'SCHEDULE_CHANGE_HISTORY';
  end if;
  return old;
end;
$$;

revoke all on function public.prevent_schedule_history_deletion() from public, anon, authenticated;
drop trigger if exists prevent_schedule_history_deletion on public.schedules;
create trigger prevent_schedule_history_deletion
before delete on public.schedules
for each row execute function public.prevent_schedule_history_deletion();

create or replace function public.delete_unused_schedule(p_schedule_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only HR / Operations can delete unused duty schedules.'
      using errcode = '42501';
  end if;

  -- Lock before checking/removing. Attendance's FK also locks this parent row,
  -- so a concurrent Time In cannot silently lose its schedule or DTR.
  select id into v_schedule_id
  from public.schedules
  where id = p_schedule_id
    and organization_id = public.current_organization_id()
  for update;

  if not found then
    raise exception 'Schedule not found or no longer available. Refresh the schedule list.'
      using errcode = 'P0002', detail = 'SCHEDULE_NOT_FOUND';
  end if;

  delete from public.schedules where id = v_schedule_id;
  return v_schedule_id;
exception when foreign_key_violation then
  raise exception 'This schedule has linked duty records and must be kept for historical records.'
    using detail = 'SCHEDULE_LINKED_HISTORY';
end;
$$;

revoke all on function public.delete_unused_schedule(uuid) from public, anon;
grant execute on function public.delete_unused_schedule(uuid) to authenticated;

notify pgrst, 'reload schema';
