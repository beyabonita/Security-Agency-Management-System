// Execute the real migration on an isolated PostgreSQL engine (PGlite).
// Minimal prerequisite schema; does not certify all existing Supabase migrations.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {PGlite}=require(process.env.PGLITE_MODULE||'C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
(async()=>{
 const db=new PGlite(); let passed=0;
 const check=(name,fn)=>fn().then(()=>{passed++;console.log('PASS '+name);});
 await db.exec(`create schema auth; create schema private; create schema realtime; create role authenticated; create role anon;
 create table realtime.messages(topic text,payload jsonb); alter table realtime.messages enable row level security;
 grant usage on schema realtime to authenticated;grant select on realtime.messages to authenticated;
 create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic',true) $$;
 create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as $$ insert into realtime.messages values(topic,payload) $$;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to authenticated,anon;
 create table public.organizations(id uuid primary key,active boolean);
 create table public.profiles(id uuid primary key,organization_id uuid,active boolean,role text,inspector_id uuid,first_name text,last_name text);
 create table public.schedules(id uuid primary key,user_id uuid,organization_id uuid,approval_status text,marked_done boolean);
 create table public.attendance_sessions(id uuid primary key,user_id uuid,organization_id uuid,schedule_id uuid,status text,
   clock_in_at timestamptz,clock_out_at timestamptz,scheduled_end_at timestamptz,location_label text);
 grant select on public.attendance_sessions,public.schedules,public.profiles,public.organizations to authenticated;
 insert into public.organizations values('${id(100)}',true),('${id(200)}',true);
 insert into public.profiles values
 ('${id(1)}','${id(100)}',true,'user','${id(3)}','Guard','One'),
 ('${id(2)}','${id(100)}',true,'admin',null,'Admin','One'),
 ('${id(3)}','${id(100)}',true,'inspector',null,'Assigned','Inspector'),
 ('${id(4)}','${id(100)}',true,'inspector',null,'Other','Inspector'),
 ('${id(5)}','${id(200)}',true,'admin',null,'Foreign','Admin'),
 ('${id(6)}','${id(100)}',true,'it_admin',null,'IT','Admin');
 insert into public.schedules values('${id(10)}','${id(1)}','${id(100)}','approved',false);
 insert into public.attendance_sessions values('${id(11)}','${id(1)}','${id(100)}','${id(10)}','open',now()-interval '1 hour',null,now()+interval '1 hour','Main gate');`);
 await db.exec(fs.readFileSync(path.resolve(__dirname,'../supabase/migrations/20260907000000_live_guard_locations.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.resolve(__dirname,'../supabase/migrations/20260908000001_live_gps_approximate_accuracy.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.resolve(__dirname,'../supabase/migrations/20260912000000_live_tracking_waiting_guards.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.resolve(__dirname,'../supabase/migrations/20260913000000_live_map_server_clock.sql'),'utf8'));
 async function as(n,sql){await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id(n)}',false); set role authenticated;`);return db.query(sql);}
 async function root(sql){await db.exec('reset role');return db.exec(sql);}
 const publish=(extra={})=>`select public.publish_guard_location('${extra.session||id(11)}',${extra.lat||'14.6'},120.98,${extra.accuracy||'20'},${extra.time||"clock_timestamp()-interval '1 second'"},${extra.mock||'false'})`;
 async function denied(n,sql,code){await assert.rejects(as(n,sql),e=>e.code===code);}
 await check('on-duty guard without GPS is listed only to authorized supervisors',async()=>{
   for(const viewer of [2,3]) {
     const rows=(await as(viewer,'select * from public.list_live_guard_locations()')).rows;
     assert.equal(rows.length,1);assert.equal(rows[0].latitude,null);assert.equal(rows[0].captured_at,null);
   }
   for(const viewer of [1,4,5,6]) assert.equal((await as(viewer,'select * from public.list_live_guard_locations()')).rows.length,0);
 });
 await check('guard publishes an on-duty fix',async()=>{await as(1,publish());});
 await check('map snapshot includes server clock and keeps the same supervisor access boundaries',async()=>{
   for(const viewer of [2,3]){
     const snapshot=(await as(viewer,'select public.live_guard_map_snapshot() snapshot')).rows[0].snapshot;
     assert.equal(snapshot.locations.length,1);assert.ok(Number.isFinite(Date.parse(snapshot.server_now)));
     assert.ok(Date.parse(snapshot.server_now)>=Date.parse(snapshot.locations[0].received_at));
   }
   for(const viewer of [1,4,5,6]){
     const snapshot=(await as(viewer,'select public.live_guard_map_snapshot() snapshot')).rows[0].snapshot;
     assert.deepEqual(snapshot.locations,[]);assert.ok(Number.isFinite(Date.parse(snapshot.server_now)));
   }
 });
 await check('broadcast signals target only supervisors and contain no coordinates',async()=>{
   await db.exec('reset role');const sent=(await db.query('select * from realtime.messages order by topic')).rows;
   assert.deepEqual(sent.map(r=>r.topic),['live-guards:'+id(2),'live-guards:'+id(3)]);
   assert.ok(sent.every(r=>Object.keys(r.payload).length===0));
 });
 await check('private signal topic authorization rejects foreign topic',async()=>{
   await db.exec(`select set_config('realtime.topic','live-guards:${id(2)}',false)`);
   assert.equal((await as(5,'select * from realtime.messages')).rows.length,0);
 });
 await check('admin sees position',async()=>assert.equal((await as(2,'select * from public.list_live_guard_locations()')).rows.length,1));
 await check('assigned inspector sees position',async()=>assert.equal((await as(3,'select * from public.list_live_guard_locations()')).rows.length,1));
 for(const n of [1,4,5,6]) await check(`role/scope ${n} cannot read list or table`,async()=>{
   assert.equal((await as(n,'select * from public.list_live_guard_locations()')).rows.length,0);
   assert.equal((await as(n,'select * from public.guard_live_locations')).rows.length,0);
 });
 await check('foreign user cannot publish another session',()=>denied(5,publish(),'42501'));
 await check('direct location writes denied',()=>denied(1,"delete from public.guard_live_locations",'42501'));
 for(const [name,extra]of [['mock',{mock:'true'}],['missing mock flag',{mock:'null'}],['stale',{time:"now()-interval '2 minutes'"}],['future',{time:"now()+interval '1 minute'"}],['NaN',{lat:"'NaN'::float8"}],['infinite',{lat:"'Infinity'::float8"}],['bad coordinates',{lat:'91'}],['weak accuracy',{accuracy:'501'}],['null accuracy',{accuracy:'null'}]])
   await check('reject '+name,()=>denied(1,publish(extra),'22023'));
 await check('114 m live fix is accepted and visible to the assigned inspector',async()=>{
   await as(1,publish({accuracy:'114',time:'clock_timestamp()'}));
   assert.equal((await as(3,'select * from public.list_live_guard_locations()')).rows[0].accuracy_meters,114);
 });
 await check('older valid update does not replace latest fix',async()=>{
   const before=(await as(2,'select captured_at from public.list_live_guard_locations()')).rows[0].captured_at;
   await as(1,publish({time:"now()-interval '15 seconds'"}));
   assert.deepEqual((await as(2,'select captured_at from public.list_live_guard_locations()')).rows[0].captured_at,before);
 });
 await check('assignment revocation removes inspector access',async()=>{
   await root(`update public.profiles set inspector_id=null where id='${id(1)}'`);
   assert.equal((await as(3,'select * from public.list_live_guard_locations()')).rows.length,0);
 });
 await check('disabled guard cannot publish or be viewed',async()=>{
   await root(`update public.profiles set active=false where id='${id(1)}'`);
   await denied(1,publish(),'42501');assert.equal((await as(2,'select * from public.list_live_guard_locations()')).rows.length,0);
   await root(`update public.profiles set active=true where id='${id(1)}'`);
 });
 await check('agency move does not expose previous duty to new admin',async()=>{
   await root(`update public.profiles set organization_id='${id(200)}' where id='${id(1)}'`);
   assert.equal((await as(5,'select * from public.list_live_guard_locations()')).rows.length,0);
   assert.equal((await as(5,'select * from public.guard_live_locations')).rows.length,0);
   await root(`update public.profiles set organization_id='${id(100)}' where id='${id(1)}'`);
 });
 await check('stop deletes position and leaves an on-duty waiting entry',async()=>{await as(1,`select public.stop_guard_location('${id(11)}')`);const rows=(await as(2,'select * from public.list_live_guard_locations()')).rows;assert.equal(rows.length,1);assert.equal(rows[0].latitude,null);});
 await check('expired duty denies publishing and hides marker',async()=>{
   await as(1,publish());await root(`update public.attendance_sessions set scheduled_end_at=now()-interval '1 second'`);
   await denied(1,publish(),'42501');assert.equal((await as(2,'select * from public.list_live_guard_locations()')).rows.length,0);
   await root("update public.attendance_sessions set scheduled_end_at=now()+interval '1 hour'");
 });
 await check('clock-out trigger clears stored fix and prevents new writes',async()=>{
   await root("update public.attendance_sessions set status='closed',clock_out_at=now()");
   await denied(1,publish(),'42501');await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from public.guard_live_locations')).rows[0].n,0);
 });
 await check('anonymous RPC denied',async()=>{await db.exec('reset role;set role anon');await assert.rejects(db.query('select * from public.list_live_guard_locations()'),e=>e.code==='42501');});
 await check('anonymous map snapshot denied',async()=>{await assert.rejects(db.query('select public.live_guard_map_snapshot()'),e=>e.code==='42501');});
 await db.close();console.log(`${passed} database checks passed. Local isolated PostgreSQL; no hosted connection.`);
})().catch(e=>{console.error(e);process.exit(1);});
