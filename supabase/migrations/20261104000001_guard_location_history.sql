-- Item #15: Store and retrieve guard location history (breadcrumb trail).

create table if not exists public.guard_location_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision not null check (accuracy_meters > 0 and accuracy_meters <= 2500),
  captured_at timestamptz not null,
  received_at timestamptz not null default now()
);

create index if not exists idx_guard_location_history_user_captured
  on public.guard_location_history (user_id, captured_at desc);

create index if not exists idx_guard_location_history_session_captured
  on public.guard_location_history (session_id, captured_at asc);

alter table public.guard_location_history enable row level security;
revoke all on public.guard_location_history from public, anon, authenticated;
grant select on public.guard_location_history to authenticated;

drop policy if exists "authorized guard location history viewers" on public.guard_location_history;
create policy "authorized guard location history viewers" on public.guard_location_history
for select to authenticated using (
  private.can_view_live_guard(user_id)
);

create or replace function private.record_guard_location_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.guard_location_history h
    where h.user_id = new.user_id
      and h.session_id = new.session_id
      and h.captured_at = new.captured_at
  ) then
    insert into public.guard_location_history (
      user_id,
      session_id,
      latitude,
      longitude,
      accuracy_meters,
      captured_at,
      received_at
    ) values (
      new.user_id,
      new.session_id,
      new.latitude,
      new.longitude,
      new.accuracy_meters,
      new.captured_at,
      new.received_at
    );
  end if;
  return new;
end;
$$;

revoke all on function private.record_guard_location_history() from public, anon, authenticated;

drop trigger if exists trg_record_guard_location_history on public.guard_live_locations;
create trigger trg_record_guard_location_history
after insert or update on public.guard_live_locations
for each row execute function private.record_guard_location_history();

-- Backfill any currently active guard_live_locations rows into guard_location_history
insert into public.guard_location_history (
  user_id,
  session_id,
  latitude,
  longitude,
  accuracy_meters,
  captured_at,
  received_at
)
select
  l.user_id,
  l.session_id,
  l.latitude,
  l.longitude,
  l.accuracy_meters,
  l.captured_at,
  l.received_at
from public.guard_live_locations l
where not exists (
  select 1
  from public.guard_location_history h
  where h.user_id = l.user_id
    and h.session_id = l.session_id
    and h.captured_at = l.captured_at
);

create or replace function public.get_guard_location_history(
  p_user_id uuid,
  p_limit integer default 100
)
returns table (
  id uuid,
  user_id uuid,
  session_id uuid,
  location_label text,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  captured_at timestamptz,
  received_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    h.id,
    h.user_id,
    h.session_id,
    coalesce(s.location_label, 'Assigned Post') as location_label,
    h.latitude,
    h.longitude,
    h.accuracy_meters,
    h.captured_at,
    h.received_at
  from public.guard_location_history h
  left join public.attendance_sessions s on s.id = h.session_id
  where h.user_id = p_user_id
    and private.can_view_live_guard(h.user_id)
  order by h.captured_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

revoke all on function public.get_guard_location_history(uuid, integer) from public, anon;
grant execute on function public.get_guard_location_history(uuid, integer) to authenticated;

notify pgrst, 'reload schema';

