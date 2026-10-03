-- Restore the required application workspace after a clean test reset.
-- Does not create accounts, schedules or attendance and does not change passwords.
begin;
lock table public.organizations in share row exclusive mode;
do $$
begin
  if exists (select 1 from public.organizations
      where active and slug<>'twentytwenty-security-agency') then
    raise exception 'Another active workspace exists; inspect its configuration before restoring the beneficiary.';
  end if;
end $$;
insert into public.organizations(name,slug,contact_name,contact_email,active)
values ('TwentyTwenty Security Agency','twentytwenty-security-agency','','',true)
on conflict (slug) do update set active=true;
commit;
select id,name,slug,active from public.organizations
where slug='twentytwenty-security-agency';
