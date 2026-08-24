-- Do not let an Auth-user deletion silently cascade away operational history.
-- Empty, newly created accounts can still be removed during provisioning rollback.
create or replace function public.prevent_historical_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.schedules where user_id = old.id or completed_by = old.id)
    or exists (select 1 from public.attendance_punches where user_id = old.id)
    or exists (select 1 from public.incidents where user_id = old.id or updated_by = old.id)
    or exists (select 1 from public.guard_assignment_history where guard_id = old.id or assigned_by = old.id)
    or exists (
      select 1
      from public.shift_swap_requests
      where requester_id = old.id
        or target_guard_id = old.id
        or inspector_id = old.id
        or inspector_decision_by = old.id
        or admin_decision_by = old.id
    )
    or exists (select 1 from public.accomplishment_reports where guard_id = old.id or reviewed_by = old.id)
  then
    raise exception 'Account deletion is blocked because this account has operational history. Disable the account instead.';
  end if;
  return old;
end;
$$;

drop trigger if exists prevent_historical_profile_deletion on public.profiles;
create trigger prevent_historical_profile_deletion
before delete on public.profiles
for each row execute function public.prevent_historical_profile_deletion();
