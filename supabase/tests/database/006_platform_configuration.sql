-- Actual RPC calls under client roles. Fixtures, settings, audit records and
-- generated notifications are all reverted at the end of this transaction.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

create temp table platform_fixture(key text primary key, id uuid not null default gen_random_uuid());
insert into platform_fixture(key) values ('it'), ('other_it'), ('disabled_it'), ('hr'), ('guard');
create function pg_temp.platform_id(p_key text) returns uuid language sql stable as
  $$ select id from pg_temp.platform_fixture where key = p_key $$;

insert into auth.users(id, email, raw_user_meta_data)
select id, 'platform-test-' || id::text || '@example.invalid', '{}'::jsonb from platform_fixture;
update public.profiles p
set role = case f.key when 'hr' then 'admin'::public.app_role
                      when 'guard' then 'user'::public.app_role
                      else 'it_admin'::public.app_role end,
    active = f.key <> 'disabled_it',
    organization_id = case when f.key in ('hr', 'guard') then public.beneficiary_organization_id() else null end
from platform_fixture f where p.id = f.id;

update public.platform_settings
set support_email = 'initial@example.invalid', default_geofence_radius = 100,
    portal_announcement = '', portal_announcement_enabled = false,
    updated_at = '2000-01-01 00:00:00+00', updated_by = pg_temp.platform_id('other_it')
where singleton;
create temp table platform_baseline as
select to_jsonb(s) as settings,
       (select count(*) from public.platform_settings_audit) as audit_count
from public.platform_settings s where singleton;

-- Count UPDATE trigger executions independently of transaction-stable now().
create temp table platform_updates(id integer);
create function pg_temp.record_platform_update() returns trigger language plpgsql as $$
begin
  insert into pg_temp.platform_updates values (1);
  return new;
end;
$$;
create trigger platform_test_update after update on public.platform_settings
for each row execute function pg_temp.record_platform_update();

create temp table platform_results(n integer generated always as identity, result text);
insert into platform_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated, anon;
grant all on all sequences in schema pg_temp to authenticated, anon;

insert into platform_results(result) select ok(
  (select relrowsecurity from pg_class where oid = 'public.platform_settings'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.platform_settings_audit'::regclass),
  'Settings and audit keep row-level security');
insert into platform_results(result) select ok(
  has_function_privilege('authenticated', 'public.update_platform_settings(text,integer,text,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.update_platform_settings(text,integer,text,boolean)', 'EXECUTE'),
  'Only authenticated clients can reach the guarded save RPC');
insert into platform_results(result) select ok(
  has_function_privilege('anon', 'public.current_platform_support_email()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.current_platform_support_email()', 'EXECUTE'),
  'The support address is intentionally readable before and after login');
insert into platform_results(result) select ok(
  (select prorettype = 'text'::regtype and prosecdef and proconfig @> array['search_path=public']
   from pg_proc where oid = 'public.current_platform_support_email()'::regprocedure),
  'Public support getter returns only text with a pinned definer search path');
insert into platform_results(result) select ok(
  not has_table_privilege('authenticated', 'public.platform_settings', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.platform_settings_audit', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon', 'public.platform_settings', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon', 'public.platform_settings_audit', 'SELECT,INSERT,UPDATE,DELETE'),
  'Public support access does not grant table reads or client writes');

set local role anon;
insert into platform_results(result) select is(public.current_platform_support_email(), 'initial@example.invalid',
  'Anonymous login pages can retrieve the configured support address');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('blocked@example.invalid', 150, '', false) $$,
  '42501', null, 'Anonymous callers cannot save settings');
insert into platform_results(result) select throws_ok(
  $$ select * from public.platform_settings $$, '42501', null, 'Anonymous callers cannot read the settings row');
insert into platform_results(result) select throws_ok(
  $$ select * from public.platform_settings_audit $$, '42501', null, 'Anonymous callers cannot read audit history');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('hr')::text, true); end $$;
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('blocked@example.invalid', 150, '', false) $$,
  'P0001', 'Only IT Admin can change platform settings.', 'HR cannot save platform settings');
insert into platform_results(result) select is((select count(*) from public.platform_settings), 0::bigint,
  'HR cannot read the protected settings row');
insert into platform_results(result) select is((select count(*) from public.platform_settings_audit), 0::bigint,
  'HR cannot read platform audit history');
insert into platform_results(result) select is(public.current_platform_support_email(), 'initial@example.invalid',
  'Authenticated portal users can read the support address');
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('guard')::text, true); end $$;
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('blocked@example.invalid', 150, '', false) $$,
  'P0001', 'Only IT Admin can change platform settings.', 'Guard cannot save platform settings');
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('disabled_it')::text, true); end $$;
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('blocked@example.invalid', 150, '', false) $$,
  'P0001', 'Only IT Admin can change platform settings.', 'Disabled IT Admin cannot save platform settings');

do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('it')::text, true); end $$;
insert into platform_results(result) select is((select count(*) from public.platform_settings), 1::bigint,
  'Active IT Admin can load configuration');
insert into platform_results(result) select throws_ok(
  $$ update public.platform_settings set support_email = 'blocked@example.invalid' where singleton $$,
  '42501', null, 'IT Admin still cannot bypass validation using a direct table update');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('bad-email', 100, '', false) $$,
  'P0001', 'Enter a valid support email address.', 'Malformed support email is rejected');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', null, '', false) $$,
  'P0001', 'Default geofence radius must be between 25 and 1,000 meters.', 'Missing radius has a clear validation error');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 24, '', false) $$,
  'P0001', 'Default geofence radius must be between 25 and 1,000 meters.', 'Radius below 25 meters is rejected');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 1001, '', false) $$,
  'P0001', 'Default geofence radius must be between 25 and 1,000 meters.', 'Radius above 1,000 meters is rejected');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 100, '', null) $$,
  'P0001', 'Choose whether to publish the portal announcement.', 'Missing publication choice has a clear validation error');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 100, '   ', true) $$,
  'P0001', 'Published announcements must be at least 3 characters.', 'Blank published announcements are rejected');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 100, ' A ', true) $$,
  'P0001', 'Published announcements must be at least 3 characters.', 'One-character announcement is rejected before notification insertion');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 100, ' AB ', true) $$,
  'P0001', 'Published announcements must be at least 3 characters.', 'Two-character announcement is rejected before notification insertion');
insert into platform_results(result) select throws_ok(
  $$ select public.update_platform_settings('', 100, repeat('x', 241), true) $$,
  'P0001', 'Portal announcement must be 240 characters or fewer.', 'Oversized announcement is rejected');
insert into platform_results(result) select is(
  (select to_jsonb(s) from public.platform_settings s where singleton), (select settings from platform_baseline),
  'Rejected saves leave every setting and saved timestamp unchanged');

insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings(' INITIAL@EXAMPLE.INVALID ', 100, '   ', false) $$,
  'An unchanged save succeeds after normalizing form text');
insert into platform_results(result) select is(
  (select to_jsonb(s) from public.platform_settings s where singleton), (select settings from platform_baseline),
  'Unchanged save preserves the complete row, including saved time and editor');
insert into platform_results(result) select is((select count(*) from platform_updates), 0::bigint,
  'Unchanged save does not execute UPDATE triggers');
insert into platform_results(result) select is(
  (select count(*) from public.platform_settings_audit), (select audit_count from platform_baseline),
  'Invalid and unchanged saves do not add audit records');

insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings(' HELP@EXAMPLE.INVALID ', 250, ' Planned maintenance ', true) $$,
  'Active IT Admin can save and publish a valid configuration');
insert into platform_results(result) select results_eq(
  $$ select support_email, default_geofence_radius, portal_announcement, portal_announcement_enabled, updated_by
     from public.platform_settings where singleton $$,
  $$ values ('help@example.invalid'::text, 250, 'Planned maintenance'::text, true, pg_temp.platform_id('it')) $$,
  'Changed configuration persists normalized values and editor');
insert into platform_results(result) select is(public.default_geofence_radius(), 250,
  'The geofence default getter exposes the saved radius');
insert into platform_results(result) select is(public.current_platform_support_email(), 'help@example.invalid',
  'The support getter exposes the saved address');
insert into platform_results(result) select is(public.current_platform_announcement(), 'Planned maintenance',
  'The announcement getter exposes the published notice');
insert into platform_results(result) select is(
  (select count(*) from public.platform_settings_audit), (select audit_count + 1 from platform_baseline),
  'A changed save records exactly one audit entry');
insert into platform_results(result) select results_eq(
  $$ select changed_fields, settings from public.platform_settings_audit where changed_by = pg_temp.platform_id('it') $$,
  $$ values (array['support_email', 'default_geofence_radius', 'portal_announcement', 'portal_announcement_enabled']::text[],
     '{"support_email":"help@example.invalid","default_geofence_radius":250,"portal_announcement":"Planned maintenance","portal_announcement_enabled":true}'::jsonb) $$,
  'Audit entry contains exactly the changed fields and resulting configuration');

reset role;
insert into platform_results(result) select is(
  (select count(*) from public.user_notifications where recipient_id = pg_temp.platform_id('guard')
   and created_by = pg_temp.platform_id('it') and entity_type = 'platform_settings' and message = 'Planned maintenance'),
  1::bigint, 'Publishing delivers one notification to an active recipient');
create temp table platform_published as
select to_jsonb(s) as settings, (select count(*) from public.user_notifications) as notification_count
from public.platform_settings s where singleton;
grant select on platform_published to authenticated;
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('other_it')::text, true); end $$;
insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings('help@example.invalid', 250, 'Planned maintenance', true) $$,
  'Another IT Admin can submit identical published settings safely');
insert into platform_results(result) select is(
  (select to_jsonb(s) from public.platform_settings s where singleton), (select settings from platform_published),
  'Repeated save does not replace the original editor or timestamp');
insert into platform_results(result) select is((select count(*) from platform_updates), 1::bigint,
  'Only the changed save has executed UPDATE triggers');
insert into platform_results(result) select is(
  (select count(*) from public.platform_settings_audit), (select audit_count + 1 from platform_baseline),
  'Repeated published save adds no audit record');
reset role;
insert into platform_results(result) select is(
  (select count(*) from public.user_notifications), (select notification_count from platform_published),
  'Repeated save creates no additional notifications');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.platform_id('it')::text, true); end $$;
insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings('', 25, 'AB', false) $$,
  'An unpublished short draft and the minimum geofence radius are accepted');
insert into platform_results(result) select is(public.current_platform_announcement(), null::text,
  'Disabling publication hides the announcement');
insert into platform_results(result) select is(public.current_platform_support_email(), null::text,
  'A cleared support address returns null for consumers to hide the link');
insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings('', 1000, 'ABC', true) $$,
  'Three-character publication and maximum geofence radius are accepted');
insert into platform_results(result) select lives_ok(
  $$ select public.update_platform_settings('', 1000, repeat('x', 240), true) $$,
  'The 240-character announcement limit is accepted by settings and notification validation');

reset role;
insert into platform_results(result) select * from finish();
select result from platform_results order by n;
rollback;
