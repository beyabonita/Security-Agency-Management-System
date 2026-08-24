-- Fail closed for objects created by future migrations. Client-facing tables
-- and RPCs must opt in with an explicit GRANT in the same migration, while the
-- service role retains the access required by trusted Edge Functions.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  grant execute on functions to service_role;

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  grant all on tables to service_role;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  grant all on sequences to service_role;
