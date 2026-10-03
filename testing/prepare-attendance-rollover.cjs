const fs = require('node:fs');
const source = fs.readFileSync('supabase/migrations/20260905000000_dtr_schedule_periods.sql', 'utf8');
let body = source.slice(source.indexOf('create or replace function public.record_attendance_event_for_guard_internal('));
body = body.slice(0, body.indexOf('\n$$;') + 4);
function replace(before, after) {
  if (!body.includes(before)) throw new Error('Missing source: ' + before);
  body = body.replace(before, after);
}
replace("  if p_action = 'clock_in' then", `  -- Serialize punches and schedule changes for the same guard. A rollover and
  -- a late Time Out must never race to modify the previous session.
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_organization_id::text || ':' || auth.uid()::text, 0)
  );

  if p_action = 'clock_in' then`);
replace("        and session.status = 'open'", "        and session.status = 'open' and session.scheduled_end_at > v_now");
replace('and v_now <= s.end_at', 'and v_now < s.end_at');
replace('    insert into public.attendance_sessions (', `    -- Preserve missing punches as incomplete records. Never manufacture a Time
    -- Out, completed schedule, or paid hours. A failed new punch rolls this back.
    update public.attendance_sessions
    set status = 'missed_timeout', updated_at = v_now
    where user_id = auth.uid() and organization_id = v_organization_id
      and status = 'open' and clock_out_at is null and scheduled_end_at <= v_now;

    insert into public.attendance_sessions (`);
const migration = `-- An ended duty with a missing Time Out must not block the next shift.
alter table public.attendance_sessions
  drop constraint attendance_sessions_status_check,
  drop constraint attendance_sessions_check2,
  add constraint attendance_sessions_status_check
    check (status in ('open', 'closed', 'missed_timeout')),
  add constraint attendance_sessions_check2 check (
    (status in ('open', 'missed_timeout') and clock_out_at is null)
    or (status = 'closed' and clock_out_at is not null)
  );

${body}

revoke all on function public.record_attendance_event_for_guard_internal(
  text, double precision, double precision
) from public, anon, authenticated;
`;
fs.writeFileSync('supabase/migrations/20260908000000_attendance_shift_rollover.sql', migration);
