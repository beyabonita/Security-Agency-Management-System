const fs=require('node:fs'),assert=require('node:assert/strict');
const {PGlite}=require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const model=require('../web/js/roster-setup.js');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
(async()=>{
 const db=new PGlite();let passed=0;
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql as $$select '${id(2)}'::uuid$$;
 create function public.is_admin() returns boolean language sql as $$select current_setting('test.admin')='true'$$;
 create function public.current_organization_is_active() returns boolean language sql as $$select current_setting('test.active')='true'$$;
 create function public.current_organization_id() returns uuid language sql as $$select current_setting('test.org')::uuid$$;
 create function public.test_now() returns timestamptz language sql stable as $$select current_setting('test.now')::timestamptz$$;
 create table public.organizations(id uuid primary key,active boolean);
 insert into public.organizations values('${id(1)}',true),('${id(99)}',true);
 create table public.profiles(id uuid primary key,organization_id uuid,active boolean,role text,first_name text,middle_initial text,last_name text,employment_category text);
 insert into public.profiles values('${id(2)}','${id(1)}',true,'admin','Head',null,null,null);
 ${Array.from({length:12},(_,i)=>`insert into public.profiles values('${id(i+3)}','${id(1)}',true,'user','Guard ${i+1}',null,null,'regular');`).join('\n')}
 insert into public.profiles values('${id(90)}','${id(99)}',true,'user','Other agency',null,null,'regular');
 create table public.locations(id uuid primary key,organization_id uuid,active boolean,label text,address text);
 insert into public.locations values('${id(80)}','${id(1)}',true,'Test post','Test address'),('${id(81)}','${id(99)}',true,'Foreign post',''),('${id(82)}','${id(1)}',false,'Inactive post','');
 create table public.schedules(id uuid primary key default gen_random_uuid(),organization_id uuid,user_id uuid,location_id uuid,location_label text,location_address text,
 guard_name text,start_at timestamptz,end_at timestamptz,duty_date date,dtr_period text,duty_category text,duty_days int,approval_status text,approved_by uuid,marked_done boolean not null default false,unique(user_id,start_at));
 select set_config('test.admin','true',false),set_config('test.active','true',false),set_config('test.org','${id(1)}',false),set_config('test.now','2026-09-12T05:00:00+08:00',false);`);
 // Exercise the actual schedule-writing function, not a mock. Only its clock is
 // frozen. Existing trigger behavior is covered by the repository SQL suites.
 const base=fs.readFileSync('supabase/migrations/20260905000000_dtr_schedule_periods.sql','utf8');
 await db.exec(base.slice(base.indexOf('create or replace function public.create_dtr_schedule('),base.indexOf('-- Count a worked DTR date once')).replaceAll('now()','public.test_now()'));
 await db.exec(fs.readFileSync('supabase/migrations/20260912000002_saved_shifting_setups.sql','utf8').replaceAll('now()','public.test_now()'));
 for(const file of ['20260912000003_manage_shifting_setups.sql','20260912000004_all_roster_setups_editable.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8').replaceAll('now()','public.test_now()'));
 await db.exec(fs.readFileSync('supabase/migrations/20260913000001_lock_used_roster_setups.sql','utf8').replaceAll('now()','public.test_now()'));
 const list=async()=>(await db.query('select * from list_shift_roster_setups()')).rows;
 let two=(await list())[0];
 const update=()=>db.query('select * from update_shift_roster_setup($1,$2,$3::jsonb,$4)',[two.id,'Renamed',JSON.stringify(model.defaults(2)),two.version]);
 const remove=()=>db.query('select remove_shift_roster_setup($1,$2)',[two.id,two.version]);
 const assign=()=>db.query('select * from assign_saved_shift_roster($1,$2,$3,$4::uuid[],$5)',[two.id,id(80),'2026-09-15',[id(3),id(4)],two.version]);
 async function check(name,fn){await fn();passed++;console.log('PASS '+name);}
 await check('unused initial setup is editable',async()=>{assert.equal(two.in_use,false);two=(await update()).rows[0];});
 await check('assignments preserve setup identity and lock both actions',async()=>{
  const rows=(await assign()).rows;assert.equal(rows.length,2);assert(rows.every(r=>r.roster_setup_id===two.id));
  await db.exec('set role authenticated');assert.equal((await list())[1].in_use,true);
  await assert.rejects(update(),/in use/);await assert.rejects(remove(),/in use/);await db.exec('reset role');
 });
 await check('cancelled duties unlock without removing history',async()=>{
  await db.exec("update schedules set approval_status='cancelled'");assert.equal((await list()).find(s=>s.id===two.id).in_use,false);
  two=(await update()).rows[0];assert.equal((await db.query('select count(*)::int n from schedules')).rows[0].n,2);
 });
 await check('ongoing overnight duty remains locked across midnight',async()=>{
  await db.exec("update schedules set approval_status='approved';select set_config('test.now','2026-09-16T01:00:00+08:00',false)");
  assert.equal((await list()).find(s=>s.id===two.id).in_use,true);await assert.rejects(remove(),/in use/);
 });
 await check('last shift ending releases lock',async()=>{
  await db.exec("select set_config('test.now','2026-09-16T06:00:00+08:00',false)");assert.equal((await list()).find(s=>s.id===two.id).in_use,false);
 });
 await check('legacy assignments without setup IDs also lock',async()=>{
  await db.exec("update schedules set roster_setup_id=null;select set_config('test.now','2026-09-15T12:00:00+08:00',false)");
  assert.equal((await list()).find(s=>s.id===two.id).in_use,true);await assert.rejects(update(),/in use/);
 });
 await check('completed assignments do not lock',async()=>{
  await db.exec('update schedules set marked_done=true');assert.equal((await list()).find(s=>s.id===two.id).in_use,false);
 });
 await check('other agency usage is isolated',async()=>{
  await db.query('update schedules set marked_done=false,organization_id=$1',[id(99)]);
  assert.equal((await list()).find(s=>s.id===two.id).in_use,false);
  await db.exec(`select set_config('test.org','${id(99)}',false)`);assert(!(await list()).some(s=>s.id===two.id));
  await assert.rejects(update(),/no longer available/);
  await db.exec(`select set_config('test.org','${id(1)}',false)`);
 });
 await check('unused setup can be removed while keeping history',async()=>{await remove();assert(!(await list()).some(s=>s.id===two.id));assert.equal((await db.query('select count(*)::int n from schedules')).rows[0].n,2);});
 await check('non-head cannot read usage or mutate setups',async()=>{
  await db.exec("select set_config('test.admin','false',false);set role authenticated");
  await assert.rejects(list(),e=>e.code==='42501');await assert.rejects(update(),e=>e.code==='42501');await assert.rejects(remove(),e=>e.code==='42501');
 });
 await db.close();console.log(passed+' roster locking database checks passed.');
})().catch(error=>{console.error(error);process.exit(1);});
