const assert = require('node:assert/strict');
const fs = require('node:fs');
const { PGlite } = require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const read = name => fs.readFileSync(`supabase/migrations/${name}.sql`, 'utf8');
(async () => {
  const db = new PGlite(); let passed = 0;
  const check = async (name, run) => { await run(); console.log('PASS ' + name); passed++; };
  await db.exec(`
    create schema auth; create role authenticated; create role anon;
    create table organizations(id uuid primary key, active boolean default true);
    create table profiles(id uuid primary key, organization_id uuid, active boolean, role text, duty_days_total integer default 0);
    create table locations(id uuid primary key, organization_id uuid, label text, active boolean, latitude double precision, longitude double precision, radius_meters integer);
    create table schedules(id uuid primary key, organization_id uuid, user_id uuid, location_id uuid, approval_status text,
      marked_done boolean default false, start_at timestamptz, end_at timestamptz, duty_days integer default 1,
      duty_date date, completed_at timestamptz, completed_by uuid);
    create function auth.uid() returns uuid language sql stable as $$select current_setting('request.jwt.claim.sub')::uuid$$;
    create function public.current_organization_id() returns uuid language sql stable security definer as $$select organization_id from public.profiles where id=auth.uid()$$;
    create function public.current_organization_is_active() returns boolean language sql stable security definer as $$select active from public.organizations where id=public.current_organization_id()$$;
    create function public.is_admin() returns boolean language sql stable security definer as $$select coalesce((select active and role='admin' from public.profiles where id=auth.uid()),false)$$;
    create function public.is_it_admin() returns boolean language sql stable security definer as $$select coalesce((select active and role='it_admin' from public.profiles where id=auth.uid()),false)$$;
    create function public.is_active_guard() returns boolean language sql stable security definer as $$select coalesce((select active and role='user' from public.profiles where id=auth.uid()),false)$$;
    create function public.is_active_duty_personnel() returns boolean language sql stable security definer as $$select public.is_active_guard()$$;
    insert into organizations(id) values('${id(100)}'),('${id(200)}');
    insert into profiles(id,organization_id,active,role) values
      ('${id(1)}','${id(100)}',true,'user'),('${id(2)}','${id(200)}',true,'admin'),
      ('${id(3)}','${id(100)}',true,'inspector'),('${id(4)}','${id(100)}',true,'admin'),
      ('${id(5)}','${id(100)}',true,'user'),('${id(6)}','${id(100)}',false,'admin');
    insert into locations values('${id(10)}','${id(100)}','Gate',true,14.6,120.98,100);
    select set_config('request.jwt.claim.sub','${id(1)}',false);
  `);
  const table = read('20260822000007_add_schedule_attendance_sessions');
  await db.exec(table.slice(0, table.indexOf('alter table public.attendance_sessions enable row level security;')));
  const periods = read('20260905000000_dtr_schedule_periods');
  const complete = periods.slice(periods.indexOf('create or replace function public.complete_schedule('));
  await db.exec(complete.slice(0, complete.indexOf('\n$$;') + 4));
  await db.exec(read('20260908000000_attendance_shift_rollover'));
  const wrapper = read('20260823000000_disable_inspector_attendance');
  await db.exec(wrapper.slice(wrapper.indexOf('create function public.record_attendance_event('), wrapper.indexOf('create function public.record_attendance_punch(')));
  await db.exec(read('20260908000002_attendance_timeout_verification'));

  const gps = read('20260911000000_gps_timeout_and_same_day_requests');
  await db.exec(gps.slice(0,gps.indexOf('create or replace function public.submit_duty_request(')));
  await db.exec(read('20260913000002_require_timeout_at_duty_post'));

  await db.exec("alter table profiles add column first_name text default 'Test', add column last_name text default 'Guard';");
  const notifications=read('20260823000001_add_realtime_notifications');
  await db.exec(notifications.slice(0,notifications.indexOf('create or replace function public.mark_notification_read(')));
  await db.exec(read('20260913000004_guard_overtime_timeout_choice'));
  const actor=async n=>db.exec('reset role;select set_config(\'request.jwt.claim.sub\',\''+id(n)+'\',false);set role authenticated;');
  async function setup(end="now()-interval '2 hours'") {
    await db.exec('reset role;truncate user_notifications,attendance_timeout_reviews,attendance_sessions,schedules cascade;');
    await db.exec("insert into schedules(id,organization_id,user_id,location_id,approval_status,start_at,end_at,duty_date) values('"+id(20)+"','"+id(100)+"','"+id(1)+"','"+id(10)+"','approved',("+end+")-interval '12 hours',"+end+",current_date);");
    await db.exec("insert into attendance_sessions(id,organization_id,schedule_id,user_id,location_id,location_label,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude,status) select '"+id(30)+"',organization_id,id,user_id,location_id,'Gate',duty_date,start_at,end_at,start_at,14.6,120.98,'open' from schedules;");
    await actor(1);
  }
  const timeout=(choice,lat=14.6,lon=120.98,session=id(30))=>db.query('select to_jsonb(record_guard_timeout($1,$2,$3,$4)) as record',[session,lat,lon,choice]).then(r=>({rows:r.rows.map(x=>x.record)}));
  const adminRead=async sql=>{await db.exec('reset role');const r=await db.query(sql);await actor(1);return r.rows;};
  await setup();
  for(const [label,choice,lat,lon,pattern] of [
    ['missing choice',null,14.6,120.98,/choose whether/],
    ['missing GPS',true,null,null,/current location/],
    ['outside original post',true,14.8,120.98,/geofence/],
    ['NaN GPS',false,NaN,120.98,/invalid/],
  ]) await check(label+' cannot submit',()=>assert.rejects(timeout(choice,lat,lon),pattern));
  await check('overtime records actual submission and queues only own active Operations Head',async()=>{
    const row=(await timeout(true)).rows[0];
    assert.equal(row.overtime_requested,true);assert.equal(row.timeout_verified_at,null);assert.equal(row.clock_out_at,row.timeout_submitted_at);
    assert.equal(Math.floor((new Date(row.clock_out_at)-new Date(row.scheduled_end_at))/60000),120);
    const notes=await adminRead('select * from user_notifications');assert.equal(notes.length,1);assert.equal(notes[0].recipient_id,id(4));
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,false);
  });
  await check('retry preserves first Time Out and creates no duplicate alert',async()=>{
    const first=(await timeout(true)).rows[0];const again=(await timeout(true)).rows[0];assert.equal(first.clock_out_at,again.clock_out_at);
    assert.equal((await adminRead('select * from user_notifications')).length,1);
    await assert.rejects(timeout(false),/different overtime choice/);
  });
  await check('only Operations Head approval finalizes overtime and notifies guard',async()=>{
    const row=(await timeout(true)).rows[0];
    const review=()=>db.query('select to_jsonb(verify_attendance_timeout($1,$2,$3,$4,$5)) as record',[row.id,row.clock_out_at,'Confirmed relief guard arrived late.',row.updated_at,id(70)]).then(r=>({rows:r.rows.map(x=>x.record)}));
    await assert.rejects(review(),/Only an active agency Admin/);
    await actor(4);const approved=(await review()).rows[0];assert.ok(approved.timeout_verified_at);
    assert.equal(approved.timeout_submitted_at,row.timeout_submitted_at);
    await actor(1);
    const notes=await adminRead('select * from user_notifications');assert.equal(notes.length,2);assert.ok(notes.some(n=>n.recipient_id===id(1)));
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,true);
  });
  await setup("now()-interval '3 minutes'");
  await check('no overtime uses scheduled end without approval and preserves actual submission',async()=>{
    const row=(await timeout(false)).rows[0];assert.equal(row.clock_out_at,row.scheduled_end_at);assert.equal(row.overtime_requested,false);assert.equal(row.timeout_verified_at,null);
    assert.ok(new Date(row.timeout_submitted_at)>new Date(row.clock_out_at));
    assert.equal((new Date(row.clock_out_at)-new Date(row.clock_in_at))/3600000,12);
    assert.equal((await adminRead('select * from user_notifications')).length,0);
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,true);
  });
  await setup("now()+interval '1 hour'");
  await check('early ordinary Time Out uses actual time, with no overtime question required',async()=>{
    await assert.rejects(timeout(true),/only after/);
    const row=(await timeout(null)).rows[0];assert.equal(row.clock_out_at,row.timeout_submitted_at);assert.equal(row.overtime_requested,false);
    assert.ok(new Date(row.clock_out_at)<new Date(row.scheduled_end_at));
  });
  await setup();
  await check('other guard and Inspector cannot submit this guard Time Out',async()=>{
    await actor(5);await assert.rejects(timeout(true),/not found/);
    await actor(3);await assert.rejects(timeout(true),/Only active Guard/);
    await actor(1);
  });
  await check('rolled over missing duty requires review rather than a new punch',async()=>{
    await db.exec("reset role;update attendance_sessions set status='missed_timeout';");await actor(1);
    await assert.rejects(timeout(false),/no longer open/);
  });
  await db.close(); console.log(passed+' overtime-choice database checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});


