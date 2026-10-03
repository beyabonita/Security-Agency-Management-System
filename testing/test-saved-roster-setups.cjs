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
 guard_name text,start_at timestamptz,end_at timestamptz,duty_date date,dtr_period text,duty_category text,duty_days int,approval_status text,approved_by uuid,unique(user_id,start_at));
 select set_config('test.admin','true',false),set_config('test.active','true',false),set_config('test.org','${id(1)}',false),set_config('test.now','2026-09-12T05:00:00+08:00',false);`);
 // Exercise the actual schedule-writing function, not a mock. Only its clock is
 // frozen. Existing trigger behavior is covered by the repository SQL suites.
 const base=fs.readFileSync('supabase/migrations/20260905000000_dtr_schedule_periods.sql','utf8');
 await db.exec(base.slice(base.indexOf('create or replace function public.create_dtr_schedule('),base.indexOf('-- Count a worked DTR date once')).replaceAll('now()','public.test_now()'));
 await db.exec(fs.readFileSync('supabase/migrations/20260912000002_saved_shifting_setups.sql','utf8').replaceAll('now()','public.test_now()'));
 const save=async(name,shifts)=> (await db.query('select * from public.save_shift_roster_setup($1,$2::jsonb)',[name,JSON.stringify(shifts)])).rows[0];
 const assign=async(setup,guards=[3,4,5,6],day='2026-09-15',site=80)=>(await db.query('select * from public.assign_saved_shift_roster($1,$2,$3,$4::uuid[])',[setup,id(site),day,guards.map(g=>g===null?null:id(g))])).rows;
 async function check(name,fn){await db.exec('truncate public.schedules');await fn();passed++;console.log('PASS '+name);}
 const four=model.defaults(4);let saved;
 await check('save reusable four-shift setup with agency and creator',async()=>{saved=await save('Four shifts',four);assert.equal(saved.organization_id,id(1));assert.equal(saved.created_by,id(2));assert.deepEqual(saved.shifts,four);});
 await check('identical retry returns the same setup; duplicate name cannot overwrite',async()=>{assert.equal((await save(' FOUR SHIFTS ',four)).id,saved.id);await assert.rejects(save('Four shifts',model.defaults(3)),/already uses that name/);});
 await check('JS and SQL agree on valid coverage for 2 through 12 shifts',async()=>{for(let n=2;n<=12;n++){const shifts=model.defaults(n);assert.equal(model.validate(shifts),null);assert.equal((await db.query('select public.valid_roster_setup($1::jsonb) valid',[JSON.stringify(shifts)])).rows[0].valid,true);}});
 await check('reject gaps overlaps unsorted equal invalid or missing times and counts',async()=>{
   const invalid=[null,[],[four[0]],Array(13).fill(four[0]),{},[{start_time:'06:00',end_time:'06:00'},{start_time:'06:00',end_time:'06:00'}],
    [{start_time:'06:00',end_time:'17:00'},{start_time:'18:00',end_time:'06:00'}],
    [{start_time:'18:00',end_time:'06:00'},{start_time:'06:00',end_time:'18:00'}],
    [{start_time:'06:00',end_time:'20:00'},{start_time:'18:00',end_time:'06:00'}],
    [{start_time:'24:00',end_time:'18:00'},{start_time:'18:00',end_time:'24:00'}],
    [{end_time:'18:00'},{start_time:'18:00',end_time:'06:00'}]];
   for(const shifts of invalid){assert.ok(model.validate(shifts));await assert.rejects(save('Invalid setup',shifts));}
   await assert.rejects(save(' ',four));await assert.rejects(save('a'.repeat(81),four));
 });
 await check('assign actual schedule snapshots and preserve overnight duty date',async()=>{
   const rows=await assign(saved.id);assert.equal(rows.length,4);
   assert.equal(rows[0].start_at.toISOString(),'2026-09-14T16:00:00.000Z');
   assert.equal(rows[3].end_at.toISOString(),'2026-09-15T16:00:00.000Z');
   for(const row of rows){assert.equal(row.duty_date.toISOString().slice(0,10),'2026-09-15');assert.equal(row.dtr_period,'auto');assert.equal(row.end_at-row.start_at,6*3600000);}
 });
 await check('changed 7 AM boundary works and saving another setup preserves history',async()=>{
   const custom=await save('Seven to seven',[{start_time:'07:00',end_time:'19:00'},{start_time:'19:00',end_time:'07:00'}]);
   const before=await assign(custom.id,[3,4]);await save('Different rotation',model.defaults(3));
   const after=(await db.query('select * from schedules order by start_at')).rows;
   assert.deepEqual(after,before);assert.equal(after[1].end_at.toISOString(),'2026-09-15T23:00:00.000Z');
 });
 await check('today skips ended slots at exact boundary',async()=>{
   await db.exec("select set_config('test.now','2026-09-12T12:00:00+08:00',false)");
   const rows=await assign(saved.id,[null,null,5,6],'2026-09-12');assert.equal(rows.length,2);assert.deepEqual(rows.map(r=>r.user_id),[id(5),id(6)]);
 });
 await check('future date still requires all Guards; past date rejected',async()=>{await assert.rejects(assign(saved.id,[null,null,5,6]));await assert.rejects(assign(saved.id,[3,4,5,6],'2026-09-11'));});
 await check('reject duplicate remaining Guards, wrong array and foreign Guards',async()=>{await assert.rejects(assign(saved.id,[3,4,5,5]));await assert.rejects(assign(saved.id,[3,4]));await assert.rejects(assign(saved.id,[3,4,5,90]));});
 await check('existing schedule writer still rejects foreign and inactive sites',async()=>{await assert.rejects(assign(saved.id,[3,4,5,6],'2026-09-15',81));await assert.rejects(assign(saved.id,[3,4,5,6],'2026-09-15',82));});
 await check('conflict on final slot rolls back earlier assignments',async()=>{
   await db.query('insert into schedules(user_id,start_at) values($1,$2)',[id(6),'2026-09-15T18:00:00+08:00']);
   await assert.rejects(assign(saved.id));assert.equal((await db.query('select count(*)::int n from schedules')).rows[0].n,1);
 });
 await check('agency Head cannot read or assign another agency setup',async()=>{
   await db.exec(`select set_config('test.org','${id(99)}',false);set role authenticated;`);
   assert.equal((await db.query('select * from shift_roster_setups')).rows.length,0);await assert.rejects(assign(saved.id));
   await db.exec(`reset role;select set_config('test.org','${id(1)}',false);`);
 });
 await check('Guard cannot read create or assign setups; direct writes denied',async()=>{
   await db.exec("select set_config('test.admin','false',false);set role authenticated;");
   assert.equal((await db.query('select * from shift_roster_setups')).rows.length,0);
   await assert.rejects(save('Guard setup',four),e=>e.code==='42501');await assert.rejects(assign(saved.id),e=>e.code==='42501');
   await assert.rejects(db.query('delete from shift_roster_setups'),e=>e.code==='42501');
   await db.exec("reset role;select set_config('test.admin','true',false);");
 });
 await check('authenticated Head can read saved setups but cannot directly alter them',async()=>{
   await db.exec('set role authenticated');assert.ok((await db.query('select * from shift_roster_setups')).rows.length>0);
   assert.equal((await save('Head-created setup',four)).organization_id,id(1));
   assert.equal((await assign(saved.id)).length,4);
   await assert.rejects(db.query("update shift_roster_setups set name='Changed'"),e=>e.code==='42501');await db.exec('reset role');
 });
 await check('inactive agency cannot read save or assign setups',async()=>{
   await db.exec("select set_config('test.active','false',false);set role authenticated;");
   assert.equal((await db.query('select * from shift_roster_setups')).rows.length,0);await assert.rejects(save('Inactive setup',four),e=>e.code==='42501');await assert.rejects(assign(saved.id),e=>e.code==='42501');
   await db.exec('reset role');
 });
 await db.close();console.log(`${passed} saved-setup database checks passed.`);
})().catch(error=>{console.error(error);process.exit(1);});
