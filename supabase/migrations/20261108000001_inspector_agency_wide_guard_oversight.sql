-- ============================================================================
-- Migration: 20261108000001_inspector_agency_wide_guard_oversight.sql
-- Description: Allow all active Field Inspectors agency-wide oversight across
-- all active guards, sites, shift schedules, incidents, and live GPS signals
-- without requiring manual 1-to-1 inspector assignment.
-- ============================================================================

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- 1. Personnel visibility: Active inspectors can view all personnel in their active agency
create or replace function private.can_view_personnel(p_user_id uuid, p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles actor
    left join public.organizations organization on organization.id = actor.organization_id
    where actor.id = (select auth.uid()) and actor.active
      and (
        actor.role = 'it_admin'
        or (organization.active and actor.organization_id = p_organization_id and (
          actor.id = p_user_id or actor.role in ('admin', 'inspector')
        ))
      )
  );
$$;

revoke all on function private.can_view_personnel(uuid, uuid) from public, anon;
grant execute on function private.can_view_personnel(uuid, uuid) to authenticated;

-- 2. Deployment site visibility: Active inspectors can view all agency deployment sites
create or replace function private.can_view_deployment_site(p_location_id uuid, p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_it_admin() or (
    p_organization_id = public.current_organization_id() and public.current_organization_is_active()
    and (
      public.is_admin()
      or public.is_staff()
      or exists (select 1 from public.profiles guard
        where guard.assigned_location_id = p_location_id and guard.organization_id = p_organization_id
          and private.can_view_personnel(guard.id, guard.organization_id))
      or exists (select 1 from public.schedules duty
        where duty.location_id = p_location_id and duty.organization_id = p_organization_id
          and private.can_view_personnel(duty.user_id, duty.organization_id))
      or exists (select 1 from public.guard_assignment_history history
        where history.location_id = p_location_id and history.organization_id = p_organization_id
          and private.can_view_personnel(history.guard_id, history.organization_id))
    )
  );
$$;

revoke all on function private.can_view_deployment_site(uuid, uuid) from public, anon;
grant execute on function private.can_view_deployment_site(uuid, uuid) to authenticated;

-- 3. Live guard locations: Active inspectors can view all live active guards agency-wide
create or replace function private.can_view_live_guard(p_guard uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles g
    join public.organizations o on o.id = g.organization_id and o.active
    join public.profiles viewer on viewer.id = auth.uid() and viewer.active
      and viewer.organization_id = g.organization_id
    where g.id = p_guard and g.active and g.role = 'user'
      and viewer.role in ('admin', 'inspector')
  );
$$;

revoke all on function private.can_view_live_guard(uuid) from public, anon;
grant execute on function private.can_view_live_guard(uuid) to authenticated;

-- 4. Broadcast live GPS signals to all active staff (Admins and Inspectors) in the agency
create or replace function private.signal_guard_location_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_guard uuid;
  viewer record;
begin
  v_guard := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  for viewer in
    select p.id
    from public.profiles g
    join public.organizations o on o.id = g.organization_id and o.active
    join public.profiles p on p.organization_id = g.organization_id and p.active
    where g.id = v_guard
      and p.role in ('admin', 'inspector')
  loop
    begin
      perform realtime.send('{}'::jsonb, 'location_changed', 'live-guards:' || viewer.id::text, true);
    exception when others then
    end;
  end loop;
  return null;
end;
$$;

revoke all on function private.signal_guard_location_change() from public, anon, authenticated;

-- 5. Broadcast profile updates (photos, names) to all active staff in the agency
create or replace function private.signal_guard_profile_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  viewer record;
begin
  for viewer in
    select p.id
    from public.profiles p
    where p.organization_id = new.organization_id
      and p.active
      and p.role in ('admin', 'inspector')
  loop
    begin
      perform realtime.send('{}'::jsonb, 'location_changed', 'live-guards:' || viewer.id::text, true);
    exception when others then
    end;
  end loop;
  return null;
end;
$$;

revoke all on function private.signal_guard_profile_change() from public, anon, authenticated;

notify pgrst, 'reload schema';
