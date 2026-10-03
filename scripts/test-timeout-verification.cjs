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
  await db.exec(`
    create unique index one_open on attendance_sessions(organization_id,user_id) where status='open';
    insert into schedules(id,organization_id,user_id,location_id,approval_status,start_at,end_at,duty_date) values
      ('${id(20)}','${id(100)}','${id(1)}','${id(10)}','approved',now()-interval '12 hours',now()-interval '4 hours',current_date),
      ('${id(21)}','${id(100)}','${id(1)}','${id(10)}','approved',now()-interval '1 hour',now()+interval '7 hours',current_date),
      ('${id(22)}','${id(100)}','${id(5)}','${id(10)}','approved',now()-interval '30 hours',now()-interval '22 hours',current_date-1);
    insert into attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
      select organization_id,id,user_id,location_id,duty_date,start_at,end_at,start_at,14.6,120.98 from schedules where id in ('${id(20)}','${id(22)}');
    update attendance_sessions set status='closed',clock_out_at=clock_in_at+interval '24 hours' where schedule_id='${id(22)}';
  `);
  const actor = n => db.query("select set_config('request.jwt.claim.sub',$1,false)", [id(n)]);
  const row = async n => (await db.query('select * from attendance_sessions where schedule_id=$1', [id(n)])).rows[0];
  const punch = action => db.query('select * from public.record_attendance_event($1,14.6,120.98)', [action]);
  let original = await row(20); let request = 300;
  const verify = (session, end = session.scheduled_end_at, note = 'Confirmed actual end with guard and duty log', rid = id(request++), expected = session.updated_at) =>
    db.query('select * from public.verify_attendance_timeout($1,$2,$3,$4,$5)', [session.id,end,note,expected,rid]);
  await check('forgotten next-day Time Out is rejected without inventing a punch', async () => {
    await assert.rejects(punch('clock_out'), /admin to verify/i); assert.equal((await row(20)).clock_out_at,null);
  });
  await check('next duty remains available and preserves the missing record', async () => {
    await punch('clock_in'); assert.equal((await row(20)).status,'missed_timeout'); assert.equal((await row(20)).clock_out_at,null);
    original = await row(20);
  });
  for (const n of [1,2,3,6]) await check('non-authorized actor ' + n + ' cannot verify', async () => {
    await actor(n); await assert.rejects(verify(original), /Only an active agency Admin|not found/);
  });
  await actor(4);
  await check('unverified historical 24-hour timeout is excluded from evaluation', async () => {
    const result = (await db.query('select * from evaluate_time_record($1,current_date-2,current_date)',[id(5)])).rows[0];
    assert.equal(result.total_minutes,0); assert.equal(result.completed_days,0);
  });
  await check('verification validates evidence, future times and Time In bound', async () => {
    await assert.rejects(verify(original,original.scheduled_end_at,'no'), /reason/);
    await assert.rejects(verify(original,'infinity'), /actual Time Out/);
    await assert.rejects(verify(original,new Date(Date.now()+3600000).toISOString()), /actual Time Out/);
    await assert.rejects(verify(original,new Date(new Date(original.clock_in_at)-1000).toISOString()), /actual Time Out/);
  });
  await check('verification rejects ongoing duty and overlapping interval', async () => {
    await assert.rejects(verify(await row(21)), /Only an ended duty/);
    await assert.rejects(verify(original,new Date().toISOString()), /overlaps/);
  });
  await check('stale admin form cannot overwrite changed attendance', async () => {
    await assert.rejects(verify(original,original.scheduled_end_at,undefined,undefined,'2000-01-01T00:00:00Z'), /record changed/);
  });
  await check('admin verification saves actual end and immutable audit without invented GPS', async () => {
    const result = (await verify(original,original.scheduled_end_at,undefined,id(400))).rows[0];
    assert.equal(result.status,'closed'); assert.ok(result.timeout_verified_at); assert.equal(result.timeout_verified_by,id(4));
    assert.equal(result.clock_out_latitude,null);
    const audit = (await db.query('select * from attendance_timeout_reviews where session_id=$1',[original.id])).rows[0];
    assert.equal(audit.before_record.clock_out_at,null); assert.equal(audit.before_record.status,'missed_timeout');
    assert.equal((await db.query('select duty_days_total from profiles where id=$1',[id(1)])).rows[0].duty_days_total,1);
  });
  await check('retry is idempotent and a second reviewer cannot overwrite verification', async () => {
    await db.exec('set role authenticated');
    await verify(original,original.scheduled_end_at,undefined,id(400));
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int as n from attendance_timeout_reviews')).rows[0].n,1);
    await assert.rejects(verify(await row(20)), /Only an ended duty/);
  });
  await check('historical late punch original is preserved while verified hours replace inflation', async () => {
    const late = await row(22); await verify(late);
    const result = (await db.query('select * from evaluate_time_record($1,current_date-2,current_date)',[id(5)])).rows[0];
    assert.equal(result.total_minutes,480); assert.equal(result.completed_days,1);
    const audit = (await db.query('select before_record from attendance_timeout_reviews where session_id=$1',[late.id])).rows[0];
    assert.equal(new Date(audit.before_record.clock_out_at)-new Date(audit.before_record.clock_in_at),24*3600000);
  });
  await check('on-time guard checkout still works and does not credit same day twice', async () => {
    await actor(1); const current = (await punch('clock_out')).rows[0]; assert.equal(current.status,'closed');
    assert.equal((await db.query('select duty_days_total from profiles where id=$1',[id(1)])).rows[0].duty_days_total,1);
  });
  await check('audit history is read-only and scoped to agency admins', async () => {
    await actor(3); await db.exec('set role authenticated');
    assert.equal((await db.query('select * from attendance_timeout_reviews')).rows.length,0);
    await assert.rejects(db.exec('delete from attendance_timeout_reviews'), /permission denied/); await db.exec('reset role');
    await actor(2); await db.exec('set role authenticated'); assert.equal((await db.query('select * from attendance_timeout_reviews')).rows.length,0); await db.exec('reset role');
    await actor(4); await db.exec('set role authenticated'); assert.equal((await db.query('select * from attendance_timeout_reviews')).rows.length,2); await db.exec('reset role');
  });
  await check('anonymous users cannot execute verification', async () => {
    const saved = await row(20); await db.exec('set role anon');
    await assert.rejects(verify(saved), /permission denied/); await db.exec('reset role');
  });
  await check('inactive agency cannot verify attendance', async () => {
    await db.exec('update organizations set active=false'); await assert.rejects(verify(await row(20)),/Only an active agency Admin/);
  });
  await db.close(); console.log(`${passed} timeout verification database checks passed.`);
})().catch(error => { console.error(error); process.exit(1); });
