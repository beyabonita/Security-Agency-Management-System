-- Accomplishment reports are evidence of a completed, closed duty session.
-- Keep the guard identity, tenant, and review audit trail server controlled.

alter table public.accomplishment_reports
  add column if not exists review_status text;

update public.accomplishment_reports
set review_status = case
  when reviewed_at is null then 'submitted'
  else 'reviewed'
end
where review_status is null;

alter table public.accomplishment_reports
  alter column review_status set default 'submitted',
  alter column review_status set not null;

alter table public.accomplishment_reports
  drop constraint if exists accomplishment_reports_review_status_check;

alter table public.accomplishment_reports
  add constraint accomplishment_reports_review_status_check
  check (review_status in ('submitted', 'reviewed', 'needs_follow_up'));

-- Direct table writes let a caller forge the guard, schedule, or tenant. The
-- SECURITY DEFINER functions below derive all three from the authenticated user.
drop policy if exists "guard submits tenant accomplishment" on public.accomplishment_reports;
drop policy if exists "guard submits accomplishment" on public.accomplishment_reports;
revoke insert, update, delete on public.accomplishment_reports from authenticated;

create or replace function public.submit_accomplishment_report(
  p_schedule_id uuid,
  p_summary text,
  p_detailed_narrative text,
  p_issues_encountered text default ''
)
returns public.accomplishment_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_report public.accomplishment_reports;
begin
  if not public.is_active_guard() then
    raise exception 'Only an active Guard can submit an accomplishment report.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if char_length(trim(coalesce(p_summary, ''))) not between 10 and 1500 then
    raise exception 'Duty summary must contain 10 to 1,500 characters.';
  end if;
  if char_length(trim(coalesce(p_detailed_narrative, ''))) not between 20 and 5000 then
    raise exception 'Detailed narrative must contain 20 to 5,000 characters.';
  end if;
  if char_length(trim(coalesce(p_issues_encountered, ''))) > 1500 then
    raise exception 'Issues encountered cannot exceed 1,500 characters.';
  end if;

  if exists (
    select 1
    from public.accomplishment_reports report
    where report.schedule_id = p_schedule_id
  ) then
    raise exception 'An accomplishment report was already submitted for this duty.';
  end if;

  if not exists (
    select 1
    from public.schedules schedule
    join public.attendance_sessions session
      on session.schedule_id = schedule.id
      and session.organization_id = schedule.organization_id
      and session.user_id = auth.uid()
      and session.status = 'closed'
      and session.clock_out_at is not null
    where schedule.id = p_schedule_id
      and schedule.user_id = auth.uid()
      and schedule.organization_id = v_organization_id
      and schedule.marked_done
  ) then
    raise exception 'Complete Time Out for this duty before submitting its accomplishment report.';
  end if;

  insert into public.accomplishment_reports (
    schedule_id,
    guard_id,
    organization_id,
    summary,
    detailed_narrative,
    issues_encountered,
    review_status
  ) values (
    p_schedule_id,
    auth.uid(),
    v_organization_id,
    trim(p_summary),
    trim(p_detailed_narrative),
    trim(coalesce(p_issues_encountered, '')),
    'submitted'
  ) returning * into v_report;

  return v_report;
end;
$$;

create or replace function public.review_accomplishment_report(
  p_report_id uuid,
  p_review_status text,
  p_review_note text default ''
)
returns public.accomplishment_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_report public.accomplishment_reports;
begin
  if not public.is_admin() then
    raise exception 'Only HR / Operations Head can review accomplishment reports.';
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null then
    raise exception 'Your organization could not be determined.';
  end if;

  if p_review_status not in ('reviewed', 'needs_follow_up') then
    raise exception 'Choose Reviewed or Needs follow-up.';
  end if;
  if char_length(trim(coalesce(p_review_note, ''))) > 1500 then
    raise exception 'Review note cannot exceed 1,500 characters.';
  end if;
  if p_review_status = 'needs_follow_up'
    and char_length(trim(coalesce(p_review_note, ''))) < 5 then
    raise exception 'Add a follow-up note of at least 5 characters.';
  end if;

  update public.accomplishment_reports
  set review_status = p_review_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = trim(coalesce(p_review_note, ''))
  where id = p_report_id
    and organization_id = v_organization_id
  returning * into v_report;

  if not found then
    raise exception 'Accomplishment report was not found in your organization.';
  end if;

  return v_report;
end;
$$;

grant execute on function public.submit_accomplishment_report(uuid, text, text, text),
  public.review_accomplishment_report(uuid, text, text)
to authenticated;
