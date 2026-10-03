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
  await db.exec(`insert into locations values('${id(11)}','${id(100)}','Other post',true,14.7,121.1,100);
    insert into schedules(id,organization_id,user_id,location_id,approval_status,start_at,end_at,duty_date)
    values('${id(20)}','${id(100)}','${id(1)}','${id(10)}','approved',now()-interval '1 hour',now()+interval '1 hour',current_date),
    ('${id(21)}','${id(100)}','${id(1)}','${id(11)}','approved',now(),now()+interval '2 hours',current_date);`);
  const punch=(action,lat,lon)=>db.query('select * from record_attendance_event($1,$2,$3)',[action,lat,lon]);
  const current=async()=>(await db.query('select * from attendance_sessions where schedule_id=$1',[id(20)])).rows[0];
  await db.exec('set role authenticated');
  await check('Time In at assigned post remains available',async()=>{
    const row=(await punch('clock_in',14.6,120.98)).rows[0];assert.equal(row.status,'open');
  });
  for (const [label,lat,lon,pattern] of [
    ['missing GPS',null,null,/current location/],['partial GPS',14.6,null,/current location/],
    ['outside original post',14.61,120.98,/geofence/],['different assigned post',14.7,121.1,/geofence/],
    ['invalid latitude',91,120.98,/invalid/],['NaN',NaN,120.98,/invalid/]]) {
    await check(label+' cannot close attendance',async()=>{
      await assert.rejects(punch('clock_out',lat,lon),pattern);
      await db.exec('reset role');assert.equal((await current()).clock_out_at,null);
      assert.equal((await db.query('select marked_done from schedules where id=$1',[id(20)])).rows[0].marked_done,false);
      await db.exec('set role authenticated');
    });
  }
  await check('verified original-post Time Out closes attendance',async()=>{
    const row=(await punch('clock_out',14.6,120.98)).rows[0];assert.equal(row.status,'closed');assert.equal(row.clock_out_location_status,'verified');
  });
  await check('duplicate Time Out is rejected',()=>assert.rejects(punch('clock_out',14.6,120.98),/No open duty/));
  await db.exec('reset role');
  await db.exec(`update attendance_sessions set status='open',clock_out_at=null,scheduled_end_at=now()-interval '1 minute';set role authenticated;`);
  await check('ended missing Time Out still needs Operations Head verification',()=>assert.rejects(punch('clock_out',14.6,120.98),/verify the missing/));
  await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id(3)}',false);set role authenticated;`);
  await check('Inspector cannot punch',()=>assert.rejects(punch('clock_out',14.6,120.98),/Only active Guard/));
  await db.close();console.log(passed+' strict Time Out database checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});
