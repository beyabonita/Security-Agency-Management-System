const fs = require('node:fs');
const read = name => fs.readFileSync(`supabase/migrations/${name}.sql`, 'utf8');
let punch = read('20260908000000_attendance_shift_rollover');
punch = punch.slice(punch.indexOf('create or replace function public.record_attendance_event_for_guard_internal('));
punch = punch.replace('s.start_at, s.end_at, s.duty_days, l.label as location_label\n  into v_duty', 's.start_at, s.end_at, s.duty_days, session.scheduled_end_at, l.label as location_label\n  into v_duty');
punch = punch.replace('  update public.attendance_sessions\n  set clock_out_at = v_now', `  if v_now > v_duty.scheduled_end_at then
    raise exception 'This duty has ended. Ask your admin to verify the missing Time Out. You can still Time In for your next eligible duty.';
  end if;

  update public.attendance_sessions
  set clock_out_at = v_now`);
if (!punch.includes('session.scheduled_end_at, l.label')) throw Error('Could not add snapshot deadline');
let evaluation = read('20260905000005_correct_time_evaluation');
evaluation = evaluation.replaceAll('when a.clock_out_at is not null then', 'when a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null) then')
  .replaceAll('bool_and(a.clock_out_at is not null)', 'bool_and(a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null))')
  .replace('a.schedule_id = s.id and a.clock_out_at is not null', 'a.schedule_id = s.id and a.clock_out_at is not null and (a.clock_out_at <= a.scheduled_end_at or a.timeout_verified_at is not null)');
const policy = fs.readFileSync('testing/timeout-verification-schema.sql', 'utf8');
fs.writeFileSync('supabase/migrations/20260908000002_attendance_timeout_verification.sql', policy + '\n' + punch + '\n' + evaluation);
