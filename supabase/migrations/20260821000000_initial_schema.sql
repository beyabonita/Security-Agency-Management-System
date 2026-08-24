-- Fresh Supabase schema for Security Time Tracker.
-- This migration intentionally imports no Firebase data.

create type public.app_role as enum ('admin', 'inspector', 'user');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  email text not null,
  first_name text not null default '',
  middle_initial text not null default '',
  last_name text not null default '',
  role public.app_role not null default 'user',
  active boolean not null default true,
  device_id text,
  device_locked boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  radius_meters double precision not null check (radius_meters > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  location_label text,
  location_address text,
  guard_name text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  marked_done boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (end_at > start_at)
);

create table public.attendance_punches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  punch_date date not null,
  punch_type text not null check (punch_type in ('AM In', 'AM Out', 'PM In', 'PM Out')),
  punched_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  within_geofence boolean not null,
  location_label text,
  created_at timestamptz not null default now(),
  unique (user_id, punch_date, punch_type)
);

create index schedules_user_start_at_idx on public.schedules (user_id, start_at desc);
create index attendance_punches_user_date_idx on public.attendance_punches (user_id, punch_date desc);

create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  guard_name text not null default '',
  guard_email text not null default '',
  category text not null check (category in ('crime', 'fire', 'medical', 'disturbance', 'other')),
  description text not null check (char_length(description) between 3 and 2000),
  photo_data text not null check (char_length(photo_data) between 1 and 750000),
  latitude double precision,
  longitude double precision,
  location_label text,
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolved')),
  status_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  updated_by uuid references public.profiles(id)
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, username, first_name, last_name)
  values (
    new.id,
    coalesce(new.email, ''),
    nullif(new.raw_user_meta_data ->> 'username', ''),
    coalesce(new.raw_user_meta_data ->> 'first_name', ''),
    coalesce(new.raw_user_meta_data ->> 'last_name', '')
  );
  return new;
end;
$$;

create or replace function public.set_incident_reporter()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  select trim(concat_ws(' ', first_name, nullif(middle_initial, ''), last_name)), email
  into new.guard_name, new.guard_email
  from public.profiles where id = new.user_id;
  if new.guard_name = '' then new.guard_name := 'Security Guard'; end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create trigger set_incident_reporter_before_insert
  before insert on public.incidents
  for each row execute procedure public.set_incident_reporter();

create or replace function public.current_role()
returns public.app_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_active_guard()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'user' and active
  )
$$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and active and role in ('admin', 'inspector')
  )
$$;

alter table public.profiles enable row level security;
alter table public.locations enable row level security;
alter table public.schedules enable row level security;
alter table public.attendance_punches enable row level security;
alter table public.incidents enable row level security;

create policy "read own profile or staff" on public.profiles for select
  to authenticated using (id = auth.uid() or public.is_staff());
create policy "staff manages profiles" on public.profiles for all
  to authenticated using (public.current_role() = 'admin')
  with check (public.current_role() = 'admin');

create policy "read assigned locations" on public.locations for select
  to authenticated using (
    public.is_staff() or exists (
      select 1 from public.schedules s
      where s.location_id = locations.id and s.user_id = auth.uid()
    )
  );
create policy "admin manages locations" on public.locations for all
  to authenticated using (public.current_role() = 'admin')
  with check (public.current_role() = 'admin');

create policy "read own schedules or staff" on public.schedules for select
  to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "admin manages schedules" on public.schedules for all
  to authenticated using (public.current_role() = 'admin')
  with check (public.current_role() = 'admin');

create policy "read own attendance or staff" on public.attendance_punches for select
  to authenticated using (user_id = auth.uid() or public.is_staff());

create policy "read own incidents or staff" on public.incidents for select
  to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "active guards create incidents" on public.incidents for insert
  to authenticated with check (user_id = auth.uid() and public.is_active_guard());
create policy "admins delete incidents" on public.incidents for delete
  to authenticated using (public.current_role() = 'admin');

create or replace function public.register_device(p_device_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  p public.profiles%rowtype;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found or p.role <> 'user' or not p.active then
    raise exception 'This account is not allowed to use the guard app.';
  end if;
  if p.device_locked and p.device_id is not null and p.device_id <> p_device_id then
    raise exception 'This account is registered to another device. Ask admin to reset device.';
  end if;
  if p.device_id is null or p.device_id = '' then
    update public.profiles set device_id = p_device_id where id = auth.uid();
  end if;
end;
$$;

create or replace function public.record_attendance_punch(
  p_punch_type text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_within_geofence boolean default false,
  p_location_label text default null
)
returns public.attendance_punches
language plpgsql
security definer set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_date date := (now() at time zone 'Asia/Manila')::date;
  v_day_start timestamptz := v_date::timestamp at time zone 'Asia/Manila';
  v_day_end timestamptz := (v_date + 1)::timestamp at time zone 'Asia/Manila';
  v_hour integer := extract(hour from now() at time zone 'Asia/Manila');
  v_result public.attendance_punches;
begin
  if not public.is_active_guard() then
    raise exception 'This account is not allowed to record attendance.';
  end if;
  if p_punch_type not in ('AM In', 'AM Out', 'PM In', 'PM Out') then
    raise exception 'Invalid punch type.';
  end if;
  if (p_punch_type like 'AM %' and v_hour >= 12) or
     (p_punch_type like 'PM %' and v_hour < 12) then
    raise exception 'Punch type is not available at this time.';
  end if;
  if p_punch_type = 'AM Out' and not exists (
    select 1 from public.attendance_punches
    where user_id = auth.uid() and punch_date = v_date and punch_type = 'AM In'
  ) then
    raise exception 'Record AM In before AM Out.';
  end if;
  if p_punch_type = 'PM Out' and not exists (
    select 1 from public.attendance_punches
    where user_id = auth.uid() and punch_date = v_date and punch_type = 'PM In'
  ) then
    raise exception 'Record PM In before PM Out.';
  end if;
  if p_latitude is null or p_longitude is null or not p_within_geofence then
    raise exception 'You must be within range of your assigned duty location to punch in.';
  end if;
  if not exists (
    select 1
    from public.schedules s
    join public.locations l on l.id = s.location_id and l.active
    where s.user_id = auth.uid()
      and s.start_at < v_day_end
      and s.end_at > v_day_start
      and 6371000 * acos(least(1.0, greatest(-1.0,
        cos(radians(l.latitude)) * cos(radians(p_latitude)) *
        cos(radians(p_longitude) - radians(l.longitude)) +
        sin(radians(l.latitude)) * sin(radians(p_latitude))
      ))) <= l.radius_meters
  ) then
    raise exception 'You must be within range of your assigned duty location to punch in.';
  end if;
  insert into public.attendance_punches (
    user_id, punch_date, punch_type, punched_at, latitude, longitude,
    within_geofence, location_label
  ) values (
    auth.uid(), v_date, p_punch_type, v_now, p_latitude, p_longitude,
    p_within_geofence, p_location_label
  ) returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.complete_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.schedules
  set marked_done = true, completed_at = now(), completed_by = auth.uid()
  where id = p_schedule_id
    and user_id = auth.uid()
    and not marked_done
    and end_at <= now()
    and public.is_active_guard();
  if not found then
    raise exception 'Schedule cannot be completed yet.';
  end if;
end;
$$;

create or replace function public.update_incident_status(
  p_incident_id uuid,
  p_status text,
  p_status_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_staff() or p_status not in ('open', 'acknowledged', 'resolved') then
    raise exception 'You are not allowed to update this incident.';
  end if;
  update public.incidents
  set status = p_status,
      status_note = left(coalesce(p_status_note, ''), 500),
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_incident_id;
  if not found then raise exception 'Incident not found.'; end if;
end;
$$;

grant usage on schema public to authenticated;
grant select on table public.profiles, public.locations, public.schedules,
  public.attendance_punches, public.incidents to authenticated;
grant insert, update, delete on table public.profiles, public.locations,
  public.schedules, public.incidents to authenticated;
grant execute on function public.register_device(text) to authenticated;
grant execute on function public.record_attendance_punch(text, double precision, double precision, boolean, text) to authenticated;
grant execute on function public.complete_schedule(uuid) to authenticated;
grant execute on function public.update_incident_status(uuid, text, text) to authenticated;

alter publication supabase_realtime add table public.profiles,
  public.locations, public.schedules, public.attendance_punches,
  public.incidents;

-- After this migration, create the first Auth user in the Supabase Dashboard,
-- then promote that user's matching profile in the SQL editor:
-- update public.profiles set role = 'admin' where email = 'admin@example.com';
