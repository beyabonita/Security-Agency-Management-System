-- Preserve real punches. An expired missing punch or an unverified late punch
-- contributes no worked hours until an agency Admin verifies its actual end.
alter table public.attendance_sessions
  add column timeout_verified_at timestamptz,
  add column timeout_verified_by uuid references public.profiles(id) on delete restrict,
  add column timeout_verification_reason text,
  add constraint attendance_timeout_verification_complete check (
    (timeout_verified_at is null and timeout_verified_by is null and timeout_verification_reason is null)
    or (timeout_verified_at is not null and timeout_verified_by is not null
      and timeout_verification_reason is not null
      and char_length(trim(timeout_verification_reason)) between 5 and 1500
      and status = 'closed' and clock_out_at is not null)
  );

create table public.attendance_timeout_reviews (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  session_id uuid not null references public.attendance_sessions(id) on delete restrict,
  guard_id uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_at timestamptz not null default now(),
  verified_clock_out_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 5 and 1500),
  before_record jsonb not null
);
create index attendance_timeout_reviews_session_idx on public.attendance_timeout_reviews(session_id, reviewed_at);
alter table public.attendance_timeout_reviews enable row level security;
create policy "agency admins read timeout reviews" on public.attendance_timeout_reviews
for select to authenticated using (
  public.is_admin() and public.current_organization_is_active()
  and organization_id = public.current_organization_id()
);
revoke all on public.attendance_timeout_reviews from public, anon, authenticated;
grant select on public.attendance_timeout_reviews to authenticated;

create function public.verify_attendance_timeout(
  p_session_id uuid, p_clock_out_at timestamptz, p_reason text,
  p_expected_updated_at timestamptz, p_request_id uuid
)
returns public.attendance_sessions
language plpgsql security definer set search_path = '' as $$
declare
  v_session public.attendance_sessions;
  v_review public.attendance_timeout_reviews;
  v_org uuid := public.current_organization_id();
  v_guard uuid;
  v_now timestamptz := clock_timestamp();
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if not coalesce(public.is_admin(), false) or v_org is null
    or not coalesce(public.current_organization_is_active(), false)
    or not exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin' and organization_id = v_org) then
    raise exception 'Only an active agency Admin can verify a missing Time Out.' using errcode = '42501';
  end if;
  if p_request_id is null or p_expected_updated_at is null then
    raise exception 'Reload the attendance record before verifying its Time Out.';
  end if;
  if char_length(v_reason) not between 5 and 1500 then
    raise exception 'Enter a verification reason between 5 and 1500 characters.';
  end if;
  select user_id into v_guard from public.attendance_sessions
    where id = p_session_id and organization_id = v_org;
  if not found then raise exception 'Attendance record was not found.' using errcode = '42501'; end if;
  -- Same lock and ordering as guard punches; correction and new Time In cannot race.
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text || ':' || v_guard::text, 0));
  select * into v_session from public.attendance_sessions
    where id = p_session_id and organization_id = v_org for update;
  select * into v_review from public.attendance_timeout_reviews where id = p_request_id;
  if found then
    if v_review.session_id <> p_session_id or v_review.reviewed_by <> auth.uid()
      or v_review.verified_clock_out_at is distinct from p_clock_out_at or v_review.reason <> v_reason then
      raise exception 'This review request was already used. Reload the attendance record.';
    end if;
    return v_session;
  end if;
  if v_session.updated_at is distinct from p_expected_updated_at then
    raise exception 'This attendance record changed. Reload it before reviewing.';
  end if;
  if v_session.scheduled_end_at >= v_now or v_session.timeout_verified_at is not null
    or not (v_session.clock_out_at is null or v_session.clock_out_at > v_session.scheduled_end_at) then
    raise exception 'Only an ended duty with a missing or unverified late Time Out can be reviewed.';
  end if;
  if p_clock_out_at is null or not isfinite(p_clock_out_at)
    or p_clock_out_at < v_session.clock_in_at or p_clock_out_at > v_now then
    raise exception 'Enter the verified actual Time Out between Time In and the current time.';
  end if;
  if exists (select 1 from public.attendance_sessions other
    where other.user_id = v_guard and other.organization_id = v_org and other.id <> p_session_id
      and other.clock_in_at < p_clock_out_at
      and coalesce(other.clock_out_at, other.scheduled_end_at) > v_session.clock_in_at) then
    raise exception 'The verified interval overlaps another duty. Check the actual Time Out.';
  end if;
  insert into public.attendance_timeout_reviews
    (id, organization_id, session_id, guard_id, reviewed_by, reviewed_at, verified_clock_out_at, reason, before_record)
  values (p_request_id, v_org, p_session_id, v_guard, auth.uid(), v_now, p_clock_out_at, v_reason, to_jsonb(v_session));
  update public.attendance_sessions set clock_out_at = p_clock_out_at,
    clock_out_latitude = null, clock_out_longitude = null, status = 'closed',
    timeout_verified_at = v_now, timeout_verified_by = auth.uid(),
    timeout_verification_reason = v_reason, updated_at = v_now
    where id = p_session_id returning * into v_session;

  -- Match normal duty completion, awarding a DTR date at most once. Previously
  -- completed historical schedules do not gain another day on verification.
  perform 1 from public.schedules where id = v_session.schedule_id for update;
  perform 1 from public.profiles where id = v_guard and organization_id = v_org for update;
  update public.schedules set marked_done = true, completed_at = coalesce(completed_at, v_now),
    completed_by = coalesce(completed_by, auth.uid())
    where id = v_session.schedule_id and organization_id = v_org and user_id = v_guard and not marked_done;
  if found and not exists (
    select 1 from public.attendance_sessions other
    join public.schedules done on done.id = other.schedule_id and done.organization_id = v_org and done.marked_done
    where other.user_id = v_guard and other.organization_id = v_org
      and other.duty_date = v_session.duty_date and other.status = 'closed'
      and other.id <> p_session_id
  ) then
    update public.profiles set duty_days_total = duty_days_total + 1
      where id = v_guard and organization_id = v_org and role = 'user';
  end if;
  return v_session;
end;
$$;
revoke all on function public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid) from public, anon;
grant execute on function public.verify_attendance_timeout(uuid,timestamptz,text,timestamptz,uuid) to authenticated;
