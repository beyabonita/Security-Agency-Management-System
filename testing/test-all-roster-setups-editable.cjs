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
 for(const file of ['20260912000003_manage_shifting_setups.sql','20260912000004_all_roster_setups_editable.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8').replaceAll('now()','public.test_now()'));
 const save=async(name,shifts)=>(await db.query('select * from public.save_shift_roster_setup($1,$2::jsonb)',[name,JSON.stringify(shifts)])).rows[0];
 const update=async(item,name,shifts,version=item.version)=>(await db.query('select * from public.update_shift_roster_setup($1,$2,$3::jsonb,$4)',[item.id,name,JSON.stringify(shifts),version])).rows[0];
 const remove=async(item)=>(await db.query('select public.remove_shift_roster_setup($1,$2) id',[item.id,item.version])).rows[0].id;
 const assign=async(item,guards=[3,4],version=item.version)=>(await db.query('select * from public.assign_saved_shift_roster($1,$2,$3,$4::uuid[],$5)',[item.id,id(80),'2026-09-15',guards.map(id),version])).rows;
 const active=async()=>(await db.query('select * from shift_roster_setups where organization_id=$1 and archived_at is null order by name',[id(1)])).rows;
 const seven=[{start_time:'07:00',end_time:'19:00'},{start_time:'19:00',end_time:'07:00'}];
 async function check(name,fn){await db.exec('truncate public.schedules');await fn();passed++;console.log('PASS '+name);}
 let two,three;
 await check('both starting setups are ordinary persisted agency records',async()=>{
   [two,three]=await active();assert.equal(two.name,'2 Shifts');assert.equal(three.name,'3 Shifts');
   assert.deepEqual(two.shifts,model.defaults(2));assert.deepEqual(three.shifts,model.defaults(3));
   assert.equal((await db.query('select count(*)::int n from shift_roster_setups where organization_id=$1',[id(99)])).rows[0].n,2);
 });
 await check('Head can edit 2 Shifts and future assignments use the changed times',async()=>{
   const before=await assign(two);await db.exec('set role authenticated');two=await update(two,'2 Shifts',seven);await db.exec('reset role');
   assert.equal(two.version,2);assert.deepEqual((await db.query('select * from schedules order by start_at')).rows,before);
   await db.exec('truncate schedules');const rows=await assign(two);assert.equal(rows[1].end_at.toISOString(),'2026-09-15T23:00:00.000Z');
 });
 await check('Head can edit 3 Shifts including its name and number of shifts',async()=>{
   await db.exec('set role authenticated');three=await update(three,'Four rotations',model.defaults(4));await db.exec('reset role');
   assert.equal(three.version,2);assert.equal((await assign(three,[3,4,5,6])).length,4);
 });
 await check('duplicates still rejected against any active saved name or times',async()=>{
   await assert.rejects(save('Copy of two',seven),/already exists/);await assert.rejects(save('2 Shifts',model.defaults(3)),/already exists/);
   await assert.rejects(update(two,'Copy',model.defaults(4)),/already exists/);
 });
 await check('older previews and legacy hard-coded assignment cannot bypass edited times',async()=>{
   await assert.rejects(assign(two,[3,4],1),/Reload saved setups/);
   await assert.rejects(db.query('select * from public.create_shift_roster($1,$2,$3,$4::uuid[])',[id(80),'2026-09-15',2,[id(3),id(4)]]),/Refresh the scheduling page/);
 });
 await check('another agency cannot edit or remove the starting setups',async()=>{
   await db.exec(`select set_config('test.org','${id(99)}',false);set role authenticated;`);
   await assert.rejects(update(two,'Other agency',seven),/no longer available/);await assert.rejects(remove(three),/no longer available/);
   await db.exec(`reset role;select set_config('test.org','${id(1)}',false);`);
 });
 await check('removing both is allowed and keeps schedules intact',async()=>{
   const before=await assign(two);await db.exec('set role authenticated');await remove(two);await remove(three);
   assert.equal((await active()).length,0);await db.exec('reset role');
   assert.deepEqual((await db.query('select * from schedules order by start_at')).rows,before);
   await assert.rejects(assign(two),/no longer available/);
 });
 await check('reads and agency updates do not recreate removed defaults',async()=>{
   for(let i=0;i<3;i++)assert.equal((await active()).length,0);
   await db.query('update organizations set active=true where id=$1',[id(1)]);assert.equal((await active()).length,0);
 });
 await check('Head can explicitly recreate a removed initial name and pattern',async()=>{
   await db.exec('set role authenticated');const recreated=await save('2 Shifts',model.defaults(2));await db.exec('reset role');
   assert.notEqual(recreated.id,two.id);assert.equal(recreated.name,'2 Shifts');assert.equal((await active()).length,1);
 });
 await check('new agencies get starting setups once via the insert trigger',async()=>{
   await db.query('insert into organizations(id,active) values($1,true)',[id(98)]);
   assert.equal((await db.query('select count(*)::int n from shift_roster_setups where organization_id=$1',[id(98)])).rows[0].n,2);
 });
 await check('non-head cannot edit or remove initial setups',async()=>{
   const current=(await active())[0];await db.exec("select set_config('test.admin','false',false);set role authenticated;");
   await assert.rejects(update(current,'No',seven),e=>e.code==='42501');await assert.rejects(remove(current),e=>e.code==='42501');await db.exec('reset role');
 });
 await db.close();console.log(`${passed} editable initial-setup database checks passed.`);
})().catch(error=>{console.error(error);process.exit(1);});
