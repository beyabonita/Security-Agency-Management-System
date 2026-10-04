-- Migration: Guard Contract Renewal and History
-- Tracks contract renewals, start and expiration dates, and renewal audit logs

create table if not exists public.guard_contract_history (
  id uuid primary key default gen_random_uuid(),
  guard_id uuid not null references public.profiles(id) on delete cascade,
  contract_start_date date not null,
  contract_end_date date not null,
  contract_status text not null default 'Active',
  renewed_at timestamptz not null default now(),
  renewed_by uuid references public.profiles(id) on delete set null,
  remarks text not null default '' check (char_length(remarks) <= 1500)
);

create index if not exists guard_contract_history_guard_idx
  on public.guard_contract_history (guard_id, renewed_at desc);

alter table public.guard_contract_history enable row level security;

drop policy if exists "guard contract history visibility" on public.guard_contract_history;
create policy "guard contract history visibility" on public.guard_contract_history
  for select to authenticated
  using (guard_id = auth.uid() or public.is_staff());

drop policy if exists "guard contract history modify" on public.guard_contract_history;
create policy "guard contract history modify" on public.guard_contract_history
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());

grant select, insert, update on public.guard_contract_history to authenticated;
