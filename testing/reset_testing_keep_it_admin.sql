-- CLEAN TEST RESET — DESTRUCTIVE WHEN EXECUTED.
-- Run the WHOLE file in the Supabase SQL Editor as postgres.
-- Preserves ALL profiles whose role is it_admin and their auth.users records,
-- passwords, identities, MFA configuration and sessions. Removes all other users.
-- Removes organizations, sites, schedules, attendance/DTR, live GPS, incidents,
-- requests, reports, notifications, saved shifting setups and application audit history.
-- Shifting setups are cleared too; create new setups before assigning a roster.
-- Resets platform settings to defaults. Keeps schema, functions, policies,
-- migrations and empty Storage buckets so the application still works.
-- Recreates the required active TwentyTwenty beneficiary workspace as system
-- configuration; account creation depends on this row even on a clean database.
--
-- BEFORE RUNNING:
-- 1. Keep a backup you can restore. Stop testing/uploads during this reset.
-- 2. Empty uploaded files in Supabase Storage (including request-letters and
--    incident-videos) using the Dashboard/Storage API. Keep the buckets.
--    Do NOT DELETE FROM storage.objects: that does not delete stored files.
-- 3. Run this entire script. It COMMITs the reset on success. Any failed check
--    aborts the transaction; run ROLLBACK if your SQL session stays aborted.
-- This file is intentionally outside migrations and is never auto-deployed.

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

create temporary table reset_target_tables (name text primary key) on commit drop;
insert into reset_target_tables values
 ('user_notifications'), ('guard_live_locations'), ('attendance_timeout_reviews'),
 ('incident_deletion_audit'), ('platform_settings_audit'), ('shift_swap_requests'),
 ('accomplishment_reports'), ('attendance_sessions'), ('attendance_punches'),
 ('guard_assignment_history'), ('incidents'), ('schedules'), ('locations'),
 ('shift_roster_setups'), ('profiles'), ('organizations'), ('platform_settings');

-- Account activity is a reviewed, optional table: its migration may not have
-- been deployed yet. Never skip unknown tables or required existing tables.
insert into reset_target_tables(name)
select 'account_presence_sessions'
where to_regclass('public.account_presence_sessions') is not null;

-- Refuse an unfamiliar schema rather than silently leave new business tables.
do $$
declare unknown_tables text; t record;
begin
  select string_agg(c.relname, ', ' order by c.relname) into unknown_tables
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p')
    and not exists (select 1 from reset_target_tables x where x.name=c.relname)
    and not exists (select 1 from pg_depend d where d.classid='pg_class'::regclass
      and d.objid=c.oid and d.deptype='e');
  if unknown_tables is not null then
    raise exception 'Reset stopped: review additional public tables first: %', unknown_tables;
  end if;
  for t in select name from reset_target_tables order by name loop
    if to_regclass(format('public.%I',t.name)) is null then
      raise exception 'Reset stopped: expected table public.% is missing.',t.name;
    end if;
    execute format('lock table public.%I in access exclusive mode',t.name);
  end loop;
  lock table auth.users in share row exclusive mode;
  if not exists (select 1 from public.profiles p join auth.users u on u.id=p.id
                 where p.role::text='it_admin' and p.active) then
    raise exception 'Reset stopped: no active IT Admin with an Auth account exists.';
  end if;
  if exists (select 1 from storage.objects) then
    raise exception 'Reset stopped: uploaded files remain. Empty Storage files through the Dashboard or Storage API, keep the buckets, then rerun. No data was cleared.';
  end if;
end $$;

create temporary table reset_keep_admins on commit drop as
  select p.id, to_jsonb(p) as profile_before
  from public.profiles p where p.role::text='it_admin';

-- Disable only application triggers inside this transaction to prevent normal
-- history protections/notifications from interfering with a deliberate reset.
-- Foreign keys remain enforced. Restore every trigger's original state below.
create temporary table reset_trigger_states on commit drop as
  select c.relname as table_name,t.tgname,t.tgenabled
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  join reset_target_tables x on x.name=c.relname
  where n.nspname='public' and not t.tgisinternal;
do $$
declare t record;
begin
  for t in select * from reset_trigger_states loop
    execute format('alter table public.%I disable trigger %I',t.table_name,t.tgname);
  end loop;
end $$;

-- Remove session history when installed. Auth sessions for IT Admins remain intact.
do $$
begin
  if to_regclass('public.account_presence_sessions') is not null then
    execute 'delete from public.account_presence_sessions';
  end if;
end $$;

delete from public.user_notifications;
delete from public.guard_live_locations;
delete from public.attendance_timeout_reviews;
delete from public.incident_deletion_audit;
delete from public.platform_settings_audit;
delete from public.shift_swap_requests;
delete from public.accomplishment_reports;
delete from public.attendance_sessions;
delete from public.attendance_punches;
delete from public.guard_assignment_history;
delete from public.incidents;
delete from public.schedules;
-- Schedules may reference setups, so delete them first.
delete from public.shift_roster_setups;

-- Remove links to entities being deleted, including unusual old IT Admin links.
-- IT Admin credentials, role, active status and personal details stay untouched.
update public.profiles set inspector_id=null, assigned_location_id=null,
  organization_id=null
where inspector_id is not null or assigned_location_id is not null or organization_id is not null;
delete from public.locations;
delete from public.organizations;
insert into public.organizations(name,slug,contact_name,contact_email,active)
values ('TwentyTwenty Security Agency','twentytwenty-security-agency','','',true);
delete from public.platform_settings;
insert into public.platform_settings(singleton) values (true);

delete from public.profiles p
where not exists (select 1 from reset_keep_admins k where k.id=p.id);
-- Auth cascades remove identities/sessions belonging to deleted users.
-- IT Admin Auth rows are never updated or deleted.
delete from auth.users u
where not exists (select 1 from reset_keep_admins k where k.id=u.id);

do $$
declare t record; remaining bigint;
begin
  for t in select name from reset_target_tables
           where name not in ('profiles','platform_settings','organizations') loop
    execute format('select count(*) from public.%I',t.name) into remaining;
    if remaining<>0 then raise exception 'Reset incomplete: public.% is not empty.',t.name; end if;
  end loop;
  if (select count(*) from public.organizations)<>1 or not exists
      (select 1 from public.organizations where slug='twentytwenty-security-agency' and active) then
    raise exception 'Reset incomplete: required active beneficiary workspace is missing.';
  end if;
  if exists (select 1 from auth.users u where not exists
      (select 1 from reset_keep_admins k where k.id=u.id))
    or exists (select 1 from public.profiles p where p.role::text<>'it_admin') then
    raise exception 'Reset incomplete: non-IT Admin accounts remain.';
  end if;
  if exists (select 1 from reset_keep_admins k
      left join public.profiles p on p.id=k.id left join auth.users u on u.id=k.id
      where p.id is null or u.id is null
        or (to_jsonb(p)-array['inspector_id','assigned_location_id','organization_id'])
           is distinct from (k.profile_before-array['inspector_id','assigned_location_id','organization_id'])) then
    raise exception 'Reset stopped: IT Admin preservation check failed.';
  end if;
  for t in select * from reset_trigger_states loop
    execute format('alter table public.%I %s trigger %I',t.table_name,
      case t.tgenabled when 'D' then 'disable' when 'A' then 'enable always'
        when 'R' then 'enable replica' else 'enable' end,t.tgname);
  end loop;
end $$;

commit;

-- Successful result: only your preserved IT Admin accounts are listed.
select p.id, p.username, p.role, p.active,
       'Reset complete: IT Admin preserved; test records cleared.' as result
from public.profiles p where p.role::text='it_admin' order by p.username;
