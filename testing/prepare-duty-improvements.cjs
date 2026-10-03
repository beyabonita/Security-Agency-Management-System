const fs = require('node:fs');
const read = name => fs.readFileSync('supabase/migrations/'+name+'.sql','utf8').replaceAll('\r\n','\n');
let punch=read('20260908000002_attendance_timeout_verification');
punch=punch.slice(punch.indexOf('create or replace function public.record_attendance_event_for_guard_internal('),punch.indexOf('-- Evaluate the Guard'));
punch=punch.replace("if p_latitude is null or p_longitude is null then", "if p_action = 'clock_in' and (p_latitude is null or p_longitude is null) then");
const outStart=punch.indexOf('  select session.id as session_id');
const geoStart=punch.indexOf('    and 6371000 * acos',outStart);
const geoEnd=punch.indexOf('  order by session.clock_in_at',geoStart);
if(geoStart<0||geoEnd<0)throw Error('Missing clock-out geofence block');
punch=punch.slice(0,geoStart)+punch.slice(geoEnd);
punch=punch.replace('s.start_at, s.end_at, s.duty_days, session.scheduled_end_at, l.label as location_label', 's.start_at, s.end_at, s.duty_days, session.scheduled_end_at, l.label as location_label,\n    l.latitude as post_latitude, l.longitude as post_longitude, l.radius_meters');
punch=punch.replace('Time Out is allowed only at the post of your open duty session.', 'No open duty was found. Refresh your attendance.');
punch=punch.replace("clock_out_longitude = p_longitude, status = 'closed', updated_at = v_now", `clock_out_longitude = p_longitude,
      clock_out_location_status = case
        when p_latitude is null or p_longitude is null then 'unavailable'
        when 6371000 * acos(least(1.0,greatest(-1.0,
          cos(radians(v_duty.post_latitude))*cos(radians(p_latitude))*cos(radians(p_longitude)-radians(v_duty.post_longitude))+
          sin(radians(v_duty.post_latitude))*sin(radians(p_latitude))))) <= v_duty.radius_meters then 'verified'
        else 'outside_post' end,
      status = 'closed', updated_at = v_now`);
// Reject malformed partial/NaN coordinates; null/null is an honest unavailable fix.
punch=punch.replace("  if p_latitude not between", "  if (p_latitude is null) <> (p_longitude is null) then raise exception 'Provide both coordinates or neither.'; end if;\n  if p_latitude not between");
let submit=read('20260904000001_guard_request_letters');
submit=submit.slice(submit.indexOf('create or replace function public.submit_duty_request('),submit.indexOf('-- Old app versions'));
submit=submit.replace("if not found or s.end_at <= now() or s.approval_status not in ('approved','changed')\n    or s.marked_done or s.completed_at is not null then", "if not found or s.approval_status not in ('approved','changed')\n    or (s.end_at <= now() and s.duty_date <> (now() at time zone 'Asia/Manila')::date) then");
submit=submit.replace(/  if exists \(select 1 from public\.attendance_sessions where schedule_id = s\.id\) then[\s\S]*?  end if;\n/,'');
submit=submit.replace('Choose an active upcoming or ongoing duty.', 'Choose a duty scheduled today, an ongoing overnight duty, or a future duty.');
fs.writeFileSync('supabase/migrations/20260911000000_gps_timeout_and_same_day_requests.sql',`-- Actual punches are preserved; an unavailable GPS fix is explicitly recorded.
alter table public.attendance_sessions add column clock_out_location_status text
  check (clock_out_location_status in ('verified','unavailable','outside_post','operational_release'));
${punch}\n${submit}\n`);
