const assert = require('node:assert/strict');
const fs = require('node:fs');
const { PGlite } = require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const read = name => fs.readFileSync(`supabase/migrations/${name}.sql`, 'utf8');
(async () => {
  const db = new PGlite();
  let passed = 0;
  async function check(name, run) { await run(); console.log('PASS ' + name); passed++; }
  await db.exec(`
    create schema auth; create role authenticated; create role anon;
    create table organizations(id uuid primary key);
    create table profiles(id uuid primary key, organization_id uuid, active boolean, role text);
    create table locations(id uuid primary key, organization_id uuid, label text, active boolean,
      latitude double precision, longitude double precision, radius_meters integer);
    create table schedules(id uuid primary key, organization_id uuid, user_id uuid, location_id uuid,
      approval_status text, marked_done boolean default false, start_at timestamptz, end_at timestamptz, duty_days integer default 1);
    create function auth.uid() returns uuid language sql stable as $$select current_setting('request.jwt.claim.sub')::uuid$$;
    create function public.current_organization_id() returns uuid language sql stable as $$select organization_id from profiles where id=auth.uid()$$;
    create function public.is_active_guard() returns boolean language sql stable as $$select coalesce((select active and role='user' from profiles where id=auth.uid()),false)$$;
    create function public.is_active_duty_personnel() returns boolean language sql stable as $$select public.is_active_guard()$$;
    create function public.complete_schedule(p_id uuid) returns void language sql as $$update schedules set marked_done=true where id=p_id$$;
    insert into organizations values('${id(100)}'),('${id(200)}');
    insert into profiles values('${id(1)}','${id(100)}',true,'user'),('${id(2)}','${id(200)}',true,'user'),('${id(3)}','${id(100)}',true,'inspector');
    insert into locations values('${id(10)}','${id(100)}','Gate',true,14.6,120.98,100);
    select set_config('request.jwt.claim.sub','${id(1)}',false);
  `);
  const table = read('20260822000007_add_schedule_attendance_sessions');
  await db.exec(table.slice(0, table.indexOf('alter table public.attendance_sessions enable row level security;')));
  let baseline = read('20260905000000_dtr_schedule_periods');
  baseline = baseline.slice(baseline.indexOf('create or replace function public.record_attendance_event_for_guard_internal('));
  await db.exec(baseline.slice(0, baseline.indexOf('\n$$;') + 4));
  let wrapper = read('20260823000000_disable_inspector_attendance');
  wrapper = wrapper.slice(wrapper.indexOf('create function public.record_attendance_event('), wrapper.indexOf('create function public.record_attendance_punch('));
  await db.exec(wrapper);
  await db.exec(`
    insert into schedules(id,organization_id,user_id,location_id,approval_status,start_at,end_at) values
      ('${id(20)}','${id(100)}','${id(1)}','${id(10)}','approved',now()-interval '12 hours',now()-interval '4 hours'),
      ('${id(21)}','${id(100)}','${id(1)}','${id(10)}','approved',now()-interval '1 minute',now()+interval '8 hours');
    insert into attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
    select organization_id,id,user_id,location_id,current_date,start_at,end_at,start_at,14.6,120.98 from schedules where id='${id(20)}';
  `);
  const punch = (action, lat=14.6, lon=120.98) => db.query(`select * from public.record_attendance_event('${action}',${lat},${lon})`);
  const old = async () => (await db.query(`select * from attendance_sessions where schedule_id='${id(20)}'`)).rows[0];
  await check('reproduces original next-shift rejection', () => assert.rejects(punch('clock_in'), /Time Out of your open duty/));
  await db.exec(read('20260908000000_attendance_shift_rollover'));
  await check('internal function remains unavailable to app roles', async () => {
    assert.equal((await db.query("select has_function_privilege('authenticated','public.record_attendance_event_for_guard_internal(text,double precision,double precision)','execute') as allowed")).rows[0].allowed, false);
  });
  await check('wrong-post punch cannot expire existing attendance', async () => {
    await assert.rejects(punch('clock_in',0,0), /scheduled post/);
    assert.equal((await old()).status, 'open');
  });
  await check('foreign guard cannot roll over another guard attendance', async () => {
    await db.exec(`select set_config('request.jwt.claim.sub','${id(2)}',false)`);
    await assert.rejects(punch('clock_in'), /scheduled post/);
    assert.equal((await old()).status, 'open');
    await db.exec(`select set_config('request.jwt.claim.sub','${id(1)}',false)`);
  });
  await check('next Time In archives ended session without inventing a punch', async () => {
    // FROM invokes the composite-returning function once, unlike SELECT (fn()).*.
    const row = (await db.query("select * from public.record_attendance_event('clock_in',14.6,120.98)")).rows[0];
    assert.equal(row.schedule_id,id(21));
    assert.equal(row.status,'open');
    assert.equal((await old()).status,'missed_timeout');
    assert.equal((await old()).clock_out_at,null);
    assert.equal((await db.query(`select marked_done from schedules where id='${id(20)}'`)).rows[0].marked_done,false);
  });
  await check('ongoing shift and duplicate taps still block another Time In', () => assert.rejects(punch('clock_in'), /Time Out of your open duty/));
  await check('Time Out completes only the new session', async () => {
    const row = (await db.query("select * from public.record_attendance_event('clock_out',14.6,120.98)")).rows[0];
    assert.equal(row.schedule_id,id(21)); assert.equal(row.status,'closed');
    assert.equal((await old()).clock_out_at,null);
    await assert.rejects(punch('clock_out'), /open duty session/);
  });
  await check('missing timeout cannot carry fabricated checkout timestamp', () => assert.rejects(
    db.exec(`update attendance_sessions set clock_out_at=now() where schedule_id='${id(20)}'`), /attendance_sessions_check2/));
  await check('late Time Out still works before rollover', async () => {
    await db.exec(`update attendance_sessions set status='open' where schedule_id='${id(20)}'`);
    const row = (await db.query("select * from public.record_attendance_event('clock_out',14.6,120.98)")).rows[0];
    assert.equal(row.schedule_id,id(20)); assert.equal(row.status,'closed');
  });
  await check('inspector role remains forbidden from punching', async () => {
    await db.exec(`select set_config('request.jwt.claim.sub','${id(3)}',false)`);
    await assert.rejects(punch('clock_in'), /Only active Guard/);
  });
  await db.close();
  console.log(`${passed} attendance database checks passed.`);
})().catch(error => { console.error(error); process.exitCode=1; });
