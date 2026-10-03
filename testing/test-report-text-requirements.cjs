const fs=require('fs'),assert=require('assert/strict');
const {PGlite}=require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
(async()=>{
 const db=new PGlite();let count=0;const check=async(name,fn)=>{await fn();count++;console.log('PASS '+name)};
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;create schema storage;
 create function auth.uid() returns uuid language sql as $$select current_setting('test.actor')::uuid$$;
 create function public.current_organization_id() returns uuid language sql as $$select '${id(100)}'::uuid$$;
 create function public.is_active_guard() returns boolean language sql as $$select auth.uid()='${id(1)}'::uuid$$;
 create function public.is_active_duty_personnel() returns boolean language sql as $$select public.is_active_guard()$$;
 create function public.is_staff() returns boolean language sql as $$select auth.uid()='${id(2)}'::uuid$$;
 create function private.can_view_personnel(p_user uuid,p_org uuid) returns boolean language sql as $$select public.is_staff() and p_org=public.current_organization_id()$$;
 create table profiles(id uuid primary key,organization_id uuid,first_name text,middle_initial text,last_name text,username text,email text);
 insert into profiles values('${id(1)}','${id(100)}','Test',null,'Guard','test',null);
 create table schedules(id uuid primary key,user_id uuid,organization_id uuid,marked_done boolean);
 insert into schedules values('${id(10)}','${id(1)}','${id(100)}',true),('${id(11)}','${id(1)}','${id(100)}',false);
 create table attendance_sessions(schedule_id uuid,user_id uuid,organization_id uuid,status text,clock_out_at timestamptz);
 insert into attendance_sessions values('${id(10)}','${id(1)}','${id(100)}','closed',now());
 create table accomplishment_reports(id uuid default gen_random_uuid(),schedule_id uuid unique,guard_id uuid,organization_id uuid,
 summary text not null check(char_length(summary) between 10 and 1500),
 detailed_narrative text not null check(char_length(detailed_narrative) between 20 and 5000),issues_encountered text,review_status text);
 create table storage.objects(bucket_id text,name text);
 create table incidents(id uuid default gen_random_uuid(),user_id uuid,organization_id uuid,guard_name text,guard_email text,
 category text,incident_title text,description text not null check(char_length(description) between 3 and 2000),
 detailed_narrative text not null,immediate_action text,photo_data text not null check(char_length(photo_data) between 1 and 750000),captured_at timestamptz,filed_at timestamptz,
 video_path text,video_duration_seconds int,latitude double precision,longitude double precision,location_label text,
 status text,status_note text,updated_at timestamptz,updated_by uuid);
 select set_config('test.actor','${id(1)}',false);`);
 await db.exec(fs.readFileSync('supabase/migrations/20260913000003_report_text_requirements.sql','utf8'));
 await db.exec(`alter table profiles add column role text default 'guard';
 insert into profiles values('${id(2)}','${id(100)}','Alex',null,'Head','head',null,'admin'),
 ('${id(3)}','${id(100)}','Sam',null,'Inspector','inspector',null,'inspector');
 create or replace function public.is_staff() returns boolean language sql as $$select auth.uid() in ('${id(2)}'::uuid,'${id(3)}'::uuid)$$;`);
 const report=(summary,narrative,schedule=id(10))=>db.query('select * from submit_accomplishment_report($1,$2,$3)',[schedule,summary,narrative]);
 const incident=(remarks,photo='A'.repeat(104),captured=new Date().toISOString())=>db.query('select * from file_incident_report($1,$2,$3,$4)', ['other',photo,remarks,captured]);
 const legacy=(await incident('')).rows[0];
 await db.query('update incidents set updated_by=$1,updated_at=now(),status=$2,status_note=$3 where id=$4',[id(2),'acknowledged','Earlier review',legacy.id]);
 await db.exec(fs.readFileSync('supabase/migrations/20260914000000_incident_narrative_and_review_history.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20260914000001_incident_photo_or_video.sql','utf8'));
 const videoPath=id(1)+'/evidence.mp4';
 await db.query('insert into storage.objects values($1,$2)', ['incident-videos',videoPath]);
 const videoReport=(path=videoPath,duration=5,photo=null,captured=new Date().toISOString(),remarks='Help')=>db.query('select * from file_incident_report($1,$2,$3,$4,$5,$6)', ['other',photo,remarks,captured,path,duration]);
 await check('video alone, photo alone, and legacy combined evidence are accepted',async()=>{
  const video=(await videoReport()).rows[0];assert.equal(video.photo_data,null);assert.equal(video.video_path,videoPath);
  assert.equal((await incident('Help')).rows[0].video_path,null);
  assert.equal((await videoReport(videoPath,5,'A'.repeat(104))).rows[0].video_path,videoPath);
 });
 await check('video reports require owned uploaded evidence, valid duration, fresh capture and narrative',async()=>{
  await assert.rejects(videoReport(null,null),/photo or record a video/);
  await assert.rejects(videoReport(id(2)+'/evidence.mp4'),/path is invalid/);
  await assert.rejects(videoReport(id(1)+'/missing.mp4'),/not found/);
  await assert.rejects(videoReport(videoPath,16),/15 seconds/);
  await assert.rejects(videoReport(videoPath,null),/15 seconds/);
  await assert.rejects(videoReport(null,5,'A'.repeat(104)),/without a video/);
  await assert.rejects(videoReport(videoPath,5,null,'2000-01-01T00:00:00Z'),/timestamp/);
  await assert.rejects(videoReport(videoPath,5,null,undefined,''),/narrative/);
 });
 await check('short accomplishment summary and narrative are accepted',async()=>{
  const row=(await report('OK','Done')).rows[0];assert.equal(row.summary,'OK');assert.equal(row.detailed_narrative,'Done');
 });
 await db.exec('truncate accomplishment_reports');
 await check('empty required accomplishment fields still need text',async()=>{
  await assert.rejects(report(' ','Done'),/duty summary/);await assert.rejects(report('OK',''),/narrative/);
 });
 await check('existing maximum lengths remain enforced',async()=>{
  await assert.rejects(report('A'.repeat(1501),'Done'),/1,500/);await assert.rejects(report('OK','A'.repeat(5001)),/5,000/);
  await assert.rejects(incident('A'.repeat(2001)),/2,000/);
 });
 await check('unfinished duty cannot submit accomplishment',()=>assert.rejects(report('OK','Done',id(11)),/Time Out/));
 let blank;
 await check('blank, whitespace and null narratives are rejected; short text is accepted',async()=>{
  for(const text of ['', '   ', '\n\t\r', null]) await assert.rejects(incident(text),/incident narrative/);
  const row=(await incident('OK')).rows[0];assert.equal(row.description,'OK');assert.equal(row.detailed_narrative,'OK');blank=row;
 });
 await check('an attached photo and capture timestamp must remain valid',async()=>{
  await assert.rejects(incident('Help',''),/photo/);await assert.rejects(incident('Help',undefined,'2000-01-01T00:00:00Z'),/timestamp/);
 });
 blank=legacy;
 await db.exec(`select set_config('test.actor','${id(2)}',false);`);
 await check('existing latest reviewer is retained without inventing earlier history',async()=>{
  const row=(await db.query('select * from incidents where id=$1',[legacy.id])).rows[0];
  assert.equal(row.description,'');assert.equal(row.review_history.length,1);
  assert.equal(row.review_history[0].reviewer_name,'Alex Head');assert.equal(row.review_history[0].legacy,true);
 });
 await check('Inspector acknowledgement and Operations Head notes keep separate authenticated identities',async()=>{
  await db.exec(`select set_config('test.actor','${id(3)}',false);`);
  await db.query('select update_incident_status($1,$2,$3)',[legacy.id,'acknowledged','Responding']);
  await db.query('select update_incident_status($1,$2,$3)',[legacy.id,'acknowledged','Responding']);
  let row=(await db.query('select * from incidents where id=$1',[legacy.id])).rows[0];
  assert.equal(row.review_history.length,2);assert.equal(row.review_history[1].reviewer_id,id(3));
  assert.equal(row.review_history[1].reviewer_name,'Sam Inspector');assert.equal(row.review_history[1].reviewer_role,'inspector');
  await db.exec(`update profiles set first_name='Changed' where id='${id(3)}'; select set_config('test.actor','${id(2)}',false);`);
  await db.query('select update_incident_status($1,$2,$3)',[legacy.id,'acknowledged','Assisting Inspector']);
  row=(await db.query('select * from incidents where id=$1',[legacy.id])).rows[0];
  assert.equal(row.review_history.length,3);assert.equal(row.review_history[1].reviewer_name,'Sam Inspector');
  assert.equal(row.review_history[2].reviewer_role,'admin');assert.equal(row.review_history[2].note,'Assisting Inspector');
 });
 await check('out-of-scope report cannot be acknowledged or gain a review',async()=>{
  await db.query('update incidents set organization_id=$1 where id=$2',[id(999),legacy.id]);
  await assert.rejects(db.query('select update_incident_status($1,$2,$3)',[legacy.id,'acknowledged','Bypass']),/not found|accessible/);
  await db.query('update incidents set organization_id=$1 where id=$2',[id(100),legacy.id]);
 });
 await check('staff can resolve a timestamped alert without guard remarks',async()=>{
  await db.query('select update_incident_status($1,$2,$3)',[blank.id,'resolved','Checked and resolved']);
  assert.equal((await db.query('select status from incidents where id=$1',[blank.id])).rows[0].status,'resolved');
 });
 await check('resolution notes and filed evidence remain required',async()=>{
  await assert.rejects(db.query('select update_incident_status($1,$2,$3)',[blank.id,'resolved','']),/resolution note/);
  await db.query('update incidents set filed_at=null where id=$1',[blank.id]);
  await assert.rejects(db.query('select update_incident_status($1,$2,$3)',[blank.id,'resolved','Checked and resolved']),/timestamped/);
 });
 await check('staff cannot file as a guard',async()=>{
  await assert.rejects(report('OK','Done'),/active Guard/);await assert.rejects(incident(''),/active duty personnel/);
 });
 await db.exec(`select set_config('test.actor','${id(1)}',false);`);
 await check('guard cannot resolve incidents',()=>assert.rejects(db.query('select update_incident_status($1,$2,$3)',[blank.id,'resolved','Checked and resolved']),/not allowed/));
 await db.close();console.log(count+' report text database checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});
