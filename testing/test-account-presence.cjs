const fs=require('node:fs'),assert=require('node:assert/strict');
const {PGlite}=require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
(async()=>{
 const db=new PGlite();let count=0;
 const check=async(name,fn)=>{await fn();console.log('PASS '+name);count++;};
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('session_id',current_setting('test.session',true))$$;
 create table profiles(id uuid primary key,first_name text,middle_initial text,last_name text,username text,role text,active boolean);
 create table auth.sessions(id uuid primary key,user_id uuid,created_at timestamptz default now(),not_after timestamptz);
 insert into profiles values
 ('${id(1)}','IT',null,'Admin','it','it_admin',true),('${id(2)}','Ops',null,'Head','ops','admin',true),
 ('${id(3)}','Test',null,'Inspector','inspector','inspector',true),('${id(4)}','Test',null,'Guard','guard','user',true),
 ('${id(5)}','Disabled',null,'Guard','disabled','user',false);`);
 await db.exec("alter table profiles add email text; update profiles set email=username||'@gmail.com';");
 await db.exec(fs.readFileSync('supabase/migrations/20260914000002_account_presence.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20260914000003_account_email_identity.sql','utf8'));
 await check('email uniqueness is case insensitive without rewriting existing profiles',async()=>{
  await assert.rejects(()=>db.query('insert into profiles(id,email) values($1,$2)',[id(9),'IT@GMAIL.COM']),/duplicate key/);
  assert.equal((await db.query('select email from profiles where id=$1',[id(1)])).rows[0].email,'it@gmail.com');
 });
 const actor=async(user,session)=>db.exec(`select set_config('test.actor','${id(user)}',false),set_config('test.session','${id(session)}',false)`);
 const session=async(user,n)=>db.query('insert into auth.sessions(id,user_id) values($1,$2)',[id(n),id(user)]);
 const touch=()=>db.query('select touch_account_presence($1)',['web']);
 const activity=async(args=['','','',0,0])=>{await actor(1,101);return (await db.query('select it_account_activity($1,$2,$3,$4,$5) as result',args)).rows[0].result;};
 await session(1,101);await actor(1,101);await touch();
 await check('all four roles appear and enabled accounts are offline without contact',async()=>{
  const data=await activity();assert.equal(data.accounts.total,5);
  assert.deepEqual(new Set(data.accounts.rows.map(r=>r.role)),new Set(['it_admin','admin','inspector','user']));
  assert.equal(data.accounts.rows.find(r=>r.id===id(2)).online,false);
 });
 await check('sign-in records history and heartbeat marks the Operations Head online',async()=>{
  await session(2,102);await actor(2,102);await touch();
  const data=await activity();assert.equal(data.accounts.rows.find(r=>r.id===id(2)).online,true);
  const log=data.history.rows.find(r=>r.session_id===id(102));assert.equal(log.name,'Ops Head');assert.equal(log.status,'Online');
 });
 await check('repeated heartbeats and tabs do not duplicate login history',async()=>{
  await actor(2,102);await touch();await touch();assert.equal((await activity()).history.total,2);
 });
 await check('sign-out ends presence immediately and a stale JWT cannot restore it',async()=>{
  await db.query('delete from auth.sessions where id=$1',[id(102)]);
  const data=await activity();assert.equal(data.accounts.rows.find(r=>r.id===id(2)).online,false);
  const log=data.history.rows.find(r=>r.session_id===id(102));assert.ok(log.signed_out_at);assert.equal(log.status,'Session ended');
  await actor(2,102);await assert.rejects(touch(),/no longer active/);
 });
 await check('another connected session keeps the account online until it also ends',async()=>{
  await session(2,103);await session(2,104);await actor(2,103);await touch();await actor(2,104);await touch();
  await db.query('delete from auth.sessions where id=$1',[id(103)]);
  assert.equal((await activity()).accounts.rows.find(r=>r.id===id(2)).online,true);
  await db.query('delete from auth.sessions where id=$1',[id(104)]);
  assert.equal((await activity()).accounts.rows.find(r=>r.id===id(2)).online,false);
 });
 await check('lost contact expires after 90 seconds; reconnect reuses the same session',async()=>{
  await session(3,105);await actor(3,105);await touch();
  await db.query("update account_presence_sessions set last_seen_at=now()-interval '91 seconds' where session_id=$1",[id(105)]);
  let data=await activity();assert.equal(data.accounts.rows.find(r=>r.id===id(3)).online,false);
  assert.equal(data.history.rows.find(r=>r.session_id===id(105)).signed_out_at,null);
  await actor(3,105);await touch();data=await activity();assert.equal(data.accounts.rows.find(r=>r.id===id(3)).online,true);
  assert.equal(data.history.rows.filter(r=>r.session_id===id(105)).length,1);
 });
 await check('expired and disabled sessions cannot claim online',async()=>{
  await session(4,106);await actor(4,106);await touch();
  await db.query("update auth.sessions set not_after=now()-interval '1 second' where id=$1",[id(106)]);
  await assert.rejects(touch(),/no longer active/);
  assert.equal((await activity()).accounts.rows.find(r=>r.id===id(4)).online,false);
  await session(5,107);await actor(5,107);await assert.rejects(touch(),/no longer active/);
 });
 await check('only authenticated active IT Admin can read activity and other users cannot write directly',async()=>{
  await actor(3,105);await assert.rejects(db.query('select it_account_activity()'),/IT Admin/);
  await db.exec('set role authenticated');
  await assert.rejects(db.query('select * from account_presence_sessions'),/permission denied/);
  await assert.rejects(db.query('update account_presence_sessions set last_seen_at=now()'),/permission denied/);
  await db.exec('reset role');
  await actor(1,999);await assert.rejects(db.query('select it_account_activity()'),/IT Admin/);
 });
 await check('role, search and online filters use server results and support empty pages',async()=>{
  const data=await activity(['Inspector','inspector','online',0,0]);assert.equal(data.accounts.total,1);
  assert.equal(data.accounts.rows[0].role,'inspector');
  assert.equal((await activity(['','user','online',0,0])).accounts.total,0);
  assert.equal((await activity(['','','',1,1])).accounts.rows.length,0);
 });
 await db.close();console.log(count+' account presence database checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});
