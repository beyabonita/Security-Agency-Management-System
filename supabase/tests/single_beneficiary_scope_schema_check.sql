begin;

create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

select ok(
  to_regprocedure('public.beneficiary_organization_id()') is not null,
  'Canonical beneficiary organization function exists'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'organizations'
      and indexname = 'organizations_only_one_active_idx'
  ),
  'Only one active beneficiary organization can exist'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'it admin manages platform profiles'
  ),
  'Direct IT Admin profile-write policy is removed in favor of the guarded Edge Function'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'locations'
      and policyname = 'operations manages tenant locations'
  ),
  'HR / Operations retains deployment-site management'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'organizations'
      and policyname = 'it admin manages organizations'
  ),
  'Browser-level multi-client management policy is removed'
);

select is(
  (select name from public.organizations where id = public.beneficiary_organization_id()),
  'TwentyTwenty Security Agency',
  'Canonical beneficiary is TwentyTwenty Security Agency'
);

select ok(
  to_regclass('public.platform_settings') is not null,
  'Protected platform settings table exists'
);

select ok(
  to_regprocedure('public.update_platform_settings(text,integer,text,boolean)') is not null,
  'IT Admin platform settings RPC exists'
);

select ok(
  to_regprocedure('public.default_geofence_radius()') is not null,
  'Default geofence settings function exists'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_settings'
      and policyname = 'it admin reads platform settings'
  ),
  'Platform settings are readable only through the IT Admin policy'
);

select * from finish();
rollback;
