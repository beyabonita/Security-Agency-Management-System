-- Keep account/profile mutations behind the account Edge Functions and
-- guarded personnel RPCs. Direct profile writes can desynchronize Auth email,
-- metadata, role, device state, and the public profile row.
revoke insert, update, delete on public.profiles from authenticated;
drop policy if exists "it admin manages platform profiles" on public.profiles;

-- A schedule may reference personnel and a post only from its own tenant.
-- The profile half was already enforced; add the missing location half.
drop policy if exists "operations manages tenant schedules" on public.schedules;
create policy "operations manages tenant schedules"
on public.schedules
for all
to authenticated
using (
  public.is_admin()
  and organization_id = public.current_organization_id()
)
with check (
  public.is_admin()
  and organization_id = public.current_organization_id()
  and exists (
    select 1
    from public.profiles personnel
    where personnel.id = schedules.user_id
      and personnel.organization_id = schedules.organization_id
      and personnel.role in ('user', 'inspector')
  )
  and (
    schedules.location_id is null
    or exists (
      select 1
      from public.locations post
      where post.id = schedules.location_id
        and post.organization_id = schedules.organization_id
    )
  )
);

-- Serialize overlap checks per personnel member. Without a transaction-scoped
-- lock, two concurrent inserts can both pass an EXISTS check before either is
-- visible to the other transaction.
create or replace function public.prevent_overlapping_active_schedules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      new.organization_id::text || ':' || new.user_id::text,
      0
    )
  );

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
    raise exception 'This personnel member already has an overlapping active schedule.';
  end if;
  return new;
end;
$$;

-- Preserve at least one active platform administrator even if a privileged
-- caller bypasses the Edge Function and changes Auth from the dashboard.
create or replace function public.protect_last_active_it_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removes_active_it_admin boolean;
begin
  if tg_op = 'DELETE' then
    v_removes_active_it_admin := old.role = 'it_admin' and old.active;
  else
    v_removes_active_it_admin := old.role = 'it_admin'
      and old.active
      and (
        new.role is distinct from 'it_admin'::public.app_role
        or new.active is false
      );
  end if;

  if v_removes_active_it_admin then
    perform pg_advisory_xact_lock(20260822, 1501);
    if not exists (
      select 1
      from public.profiles other
      where other.id <> old.id
        and other.role = 'it_admin'
        and other.active
    ) then
      raise exception 'The last active IT Admin must remain active and keep the IT Admin role.';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists protect_last_active_it_admin_update on public.profiles;
create trigger protect_last_active_it_admin_update
before update of role, active on public.profiles
for each row execute function public.protect_last_active_it_admin();

drop trigger if exists protect_last_active_it_admin_delete on public.profiles;
create trigger protect_last_active_it_admin_delete
before delete on public.profiles
for each row execute function public.protect_last_active_it_admin();

-- Database-level uniqueness closes races that application-level EXISTS checks
-- alone cannot prevent.
create unique index if not exists attendance_sessions_one_open_per_user_idx
  on public.attendance_sessions (organization_id, user_id)
  where status = 'open';

create unique index if not exists guard_assignment_history_one_current_idx
  on public.guard_assignment_history (organization_id, guard_id)
  where ended_at is null;

create unique index if not exists shift_swap_requests_one_pending_schedule_idx
  on public.shift_swap_requests (organization_id, requested_schedule_id)
  where status in ('pending_inspector', 'pending_admin');

-- Match the filters and ordering used by account lists, Inspector queues,
-- incident history, assignment validation, and accomplishment review.
create index if not exists profiles_role_active_idx
  on public.profiles (role, active);
create index if not exists profiles_inspector_id_idx
  on public.profiles (inspector_id)
  where inspector_id is not null;
create index if not exists shift_swap_requests_inspector_queue_idx
  on public.shift_swap_requests (organization_id, inspector_id, status, created_at desc);
create index if not exists shift_swap_requests_admin_queue_idx
  on public.shift_swap_requests (organization_id, status, created_at desc);
create index if not exists incidents_tenant_created_idx
  on public.incidents (organization_id, created_at desc);
create index if not exists accomplishment_reports_guard_submitted_idx
  on public.accomplishment_reports (organization_id, guard_id, submitted_at desc);

-- Coordinates outside these ranges make distance calculations meaningless.
-- NOT VALID preserves any historical row for explicit review while enforcing
-- the rule for every new or changed deployment site.
alter table public.locations
  drop constraint if exists locations_latitude_valid,
  drop constraint if exists locations_longitude_valid;
alter table public.locations
  add constraint locations_latitude_valid
    check (latitude between -90 and 90) not valid,
  add constraint locations_longitude_valid
    check (longitude between -180 and 180) not valid;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Reset the
-- effective API surface, then explicitly grant only the functions intended for
-- browser/mobile callers. Trigger helpers remain private.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

grant execute on function
  public.current_role(),
  public.is_active_guard(),
  public.is_active_duty_personnel(),
  public.is_admin(),
  public.is_it_admin(),
  public.is_operations_head(),
  public.is_operations_staff(),
  public.is_staff(),
  public.current_organization_id(),
  public.current_organization_is_active(),
  public.is_same_organization(uuid),
  public.beneficiary_organization_id(),
  public.register_device(text),
  public.record_attendance_event(text, double precision, double precision),
  public.record_attendance_punch(text, double precision, double precision, boolean, text),
  public.complete_schedule(uuid),
  public.update_incident_status(uuid, text, text),
  public.assign_guard_location(uuid, uuid, text),
  public.assign_guard_inspector(uuid, uuid),
  public.set_personnel_active(uuid, boolean),
  public.request_shift_swap(uuid, uuid, timestamptz, timestamptz, text),
  public.review_shift_swap_by_inspector(uuid, boolean, text),
  public.decide_shift_swap_by_admin(uuid, boolean, text),
  public.evaluate_time_record(uuid, date, date),
  public.submit_accomplishment_report(uuid, text, text, text),
  public.review_accomplishment_report(uuid, text, text),
  public.file_incident_report(text, text, text, timestamptz, text, integer, double precision, double precision, text),
  public.update_platform_settings(text, integer, text, boolean),
  public.default_geofence_radius(),
  public.current_platform_announcement()
to authenticated;

grant execute on function public.current_platform_announcement() to anon;
