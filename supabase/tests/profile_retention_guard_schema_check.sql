-- Verify Auth cascades cannot silently erase historical operational data.
do $$
declare
  v_definition text;
begin
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.profiles'::regclass
      and t.tgname = 'prevent_historical_profile_deletion'
      and not t.tgisinternal
  ) then
    raise exception 'profiles must have the historical deletion guard trigger';
  end if;

  select pg_get_functiondef('public.prevent_historical_profile_deletion()'::regprocedure)
    into v_definition;
  if v_definition not like '%attendance_punches%'
    or v_definition not like '%incidents%'
    or v_definition not like '%shift_swap_requests%'
    or v_definition not like '%Disable the account instead.%'
  then
    raise exception 'profile deletion guard is missing historical-record protection';
  end if;
end;
$$;
