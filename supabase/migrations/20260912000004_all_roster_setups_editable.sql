-- The starting 2/3-shift rosters are ordinary agency templates, seeded once.
-- Removing a template never causes it to reappear when the portal reloads.
create or replace function public.check_saved_roster_values(p_name text,p_shifts jsonb)
returns void language plpgsql set search_path='' as $$
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then
    raise exception 'Enter a setup name of 1 to 80 characters.';
  end if;
  if not public.valid_roster_setup(p_shifts) then
    raise exception 'Use 2 to 12 shifts in start-time order, covering 24 hours without gaps or overlaps.';
  end if;
end $$;

insert into public.shift_roster_setups(organization_id,name,shifts)
select o.id,initial.name,initial.shifts from public.organizations o cross join (values
  ('2 Shifts','[{"start_time":"06:00","end_time":"18:00"},{"start_time":"18:00","end_time":"06:00"}]'::jsonb),
  ('3 Shifts','[{"start_time":"06:00","end_time":"14:00"},{"start_time":"14:00","end_time":"22:00"},{"start_time":"22:00","end_time":"06:00"}]'::jsonb)
) initial(name,shifts) on conflict do nothing;

create function public.seed_initial_roster_setups()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.shift_roster_setups(organization_id,name,shifts) values
    (new.id,'2 Shifts','[{"start_time":"06:00","end_time":"18:00"},{"start_time":"18:00","end_time":"06:00"}]'::jsonb),
    (new.id,'3 Shifts','[{"start_time":"06:00","end_time":"14:00"},{"start_time":"14:00","end_time":"22:00"},{"start_time":"22:00","end_time":"06:00"}]'::jsonb);
  return new;
end $$;
revoke all on function public.seed_initial_roster_setups() from public,anon,authenticated;
create trigger seed_initial_roster_setups after insert on public.organizations
  for each row execute function public.seed_initial_roster_setups();

-- Cached portal versions must not assign hard-coded times after the Head edits
-- or removes the corresponding template. The current portal uses versioned IDs.
create or replace function public.create_shift_roster(p_location_id uuid,p_duty_date date,
  p_shift_count integer,p_guard_ids uuid[])
returns setof public.schedules language plpgsql security definer set search_path='' as $$
begin
  raise exception 'Refresh the scheduling page and select a saved shifting setup before assigning.';
end $$;
notify pgrst,'reload schema';
