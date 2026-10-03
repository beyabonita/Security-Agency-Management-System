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
 const save=async(name,shifts)=>(await db.query('select * from public.save_shift_roster_setup($1,$2::jsonb)',[name,JSON.stringify(shifts)])).rows[0];
 const four=model.defaults(4),seven=[{start_time:'07:00',end_time:'19:00'},{start_time:'19:00',end_time:'07:00'}];
 await save('2 Shifts',model.defaults(2));await save('3 Shifts',model.defaults(3));
 const original=await save('Four original',four);await save('Copy',four.map(s=>({...s,ignored:'extra'})));
 await db.exec(`select set_config('test.org','${id(99)}',false)`);await save('Other agency four',four);
 await db.exec(`select set_config('test.org','${id(1)}',false)`);
 await db.exec(fs.readFileSync('supabase/migrations/20260912000003_manage_shifting_setups.sql','utf8').replaceAll('now()','public.test_now()'));
 const update=async(item,name,shifts,version=item.version)=>(await db.query('select * from public.update_shift_roster_setup($1,$2,$3::jsonb,$4)',[item.id,name,JSON.stringify(shifts),version])).rows[0];
 const remove=async(item,version=item.version)=>(await db.query('select public.remove_shift_roster_setup($1,$2) id',[item.id,version])).rows[0].id;
 const assign=async(item,guards=[3,4,5,6],version=item.version)=>(await db.query('select * from public.assign_saved_shift_roster($1,$2,$3,$4::uuid[],$5)',[item.id,id(80),'2026-09-15',guards.map(id),version])).rows;
 async function check(name,fn){await db.exec('truncate public.schedules');await fn();passed++;console.log('PASS '+name);}
 let saved;
 await check('migration archives built-in and same-time duplicates within each agency',async()=>{
   const rows=(await db.query('select * from shift_roster_setups')).rows;
   assert.equal(rows.filter(r=>r.archived_at).length,3);
   assert.equal(rows.filter(r=>!r.archived_at&&r.organization_id===id(99)).length,1);
   saved=rows.find(r=>!r.archived_at&&r.organization_id===id(1));assert.deepEqual(saved.shifts.map(s=>({start_time:s.start_time,end_time:s.end_time})),four);
   await db.exec('set role authenticated');assert.equal((await db.query('select * from shift_roster_setups')).rows.length,1);await db.exec('reset role');
 });
 await check('built-in times and names cannot be duplicated',async()=>{
   await assert.rejects(save('Alias for standard two',model.defaults(2)),/already exist in 2 Shifts/);
   await assert.rejects(save('Alias for standard three',model.defaults(3)),/already exist in 3 Shifts/);
   await assert.rejects(save(' 2 SHIFTS ',seven),/standard setup/);
 });
 await check('different name and ignored JSON keys cannot bypass duplicate times',async()=>{
   await assert.rejects(save('Another four',four),/already exists/);
   await assert.rejects(save('Extra metadata',four.map(s=>({...s,label:'new'}))),/already exists/);
   assert.equal((await save(saved.name,saved.shifts)).id,saved.id);
 });
 await check('edit changes name and times, preserves existing schedule snapshots',async()=>{
   const before=await assign(saved);saved=await update(saved,'Seven to seven',seven);
   assert.equal(saved.version,2);assert.deepEqual(saved.shifts,seven);
   assert.deepEqual((await db.query('select * from schedules order by start_at')).rows,before);
 });
 await check('future assignments use edited times and preserve overnight DTR date',async()=>{
   const rows=await assign(saved,[3,4]);assert.equal(rows.length,2);assert.equal(rows[1].end_at.toISOString(),'2026-09-15T23:00:00.000Z');
   assert.equal(rows[1].duty_date.toISOString().slice(0,10),'2026-09-15');
 });
 await check('stale edit remove and assignment require reloading the preview',async()=>{
   await assert.rejects(update(saved,'Stale',seven,1),/another session/);
   await assert.rejects(remove(saved,1),/another session/);
   await assert.rejects(assign(saved,[3,4],1),/Reload saved setups/);
   await assert.rejects(assign(saved,[3,4],null),/Reload saved setups/);
 });
 let other;
 await check('editing rejects invalid coverage and duplicate names or times',async()=>{
   other=await save('Four new',four);
   await assert.rejects(update(saved,'Invalid',[{start_time:'07:00',end_time:'18:00'},{start_time:'19:00',end_time:'07:00'}]),/without gaps/);
   await assert.rejects(update(saved,'Same times as other',four),/already exists/);
   await assert.rejects(update(saved,'Four new',seven),/already exists/);
   await assert.rejects(update(saved,'Standard copy',model.defaults(2)),/already exist/);
 });
 await check('remove hides the template and blocks assignment, preserving schedule history',async()=>{
   const before=await assign(saved,[3,4]);assert.equal(await remove(saved),saved.id);
   assert.deepEqual((await db.query('select * from schedules order by start_at')).rows,before);
   await assert.rejects(assign(saved,[3,4]),/no longer available/);await assert.rejects(update(saved,'Unavailable',seven),/no longer available/);
   assert.equal(await remove(saved),saved.id);
   await db.exec('set role authenticated');assert.equal((await db.query('select * from shift_roster_setups where id=$1',[saved.id])).rows.length,0);await db.exec('reset role');
   const replacement=await save('Seven to seven',seven);assert.notEqual(replacement.id,saved.id);
 });
 await check('another agency cannot edit or remove a setup',async()=>{
   await db.exec(`select set_config('test.org','${id(99)}',false);set role authenticated;`);
   await assert.rejects(update(other,'Foreign',seven),/no longer available/);await assert.rejects(remove(other),/no longer available/);
   await db.exec(`reset role;select set_config('test.org','${id(1)}',false);`);
 });
 await check('Guard and inactive agency cannot edit or remove setups',async()=>{
   for(const key of ['test.admin','test.active']){
     await db.query('select set_config($1,$2,false)',[key,'false']);await db.exec('set role authenticated');
     await assert.rejects(update(other,'Denied',seven),e=>e.code==='42501');await assert.rejects(remove(other),e=>e.code==='42501');
     await db.exec('reset role');await db.query('select set_config($1,$2,false)',[key,'true']);
   }
 });
 await check('authenticated Head can edit/remove; anonymous callers cannot execute',async()=>{
   await db.exec('set role authenticated');other=await update(other,'Renamed four',four);await remove(other);await db.exec('reset role;set role anon;');
   await assert.rejects(remove(other),e=>e.code==='42501');await assert.rejects(update(other,'No',four),e=>e.code==='42501');await db.exec('reset role');
 });
 await db.close();console.log(`${passed} setup management database checks passed.`);
})().catch(error=>{console.error(error);process.exit(1);});
