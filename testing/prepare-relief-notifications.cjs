const fs=require('node:fs');
let source=fs.readFileSync('supabase/migrations/20260904000001_guard_request_letters.sql','utf8');
source=source.slice(source.indexOf('create or replace function public.notify_shift_request_event()'),source.indexOf('-- Preserve existing requests'));
source=source.replaceAll('HR / Operations','Operational Head').replaceAll('HR assigned','Operational Head assigned')
 .replace("jsonb_build_object('schedule_id',new.requested_schedule_id)","jsonb_build_object('schedule_id',coalesce(new.replacement_schedule_id,new.requested_schedule_id))");
const file='supabase/migrations/20260911000001_duty_relief_and_shift_rosters.sql';
let migration=fs.readFileSync(file,'utf8');
if(migration.includes('create or replace function public.notify_shift_request_event()'))throw Error('Notification change already added');
fs.writeFileSync(file,migration+'\n'+source);
