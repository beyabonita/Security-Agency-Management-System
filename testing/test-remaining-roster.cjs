const fs=require('node:fs'),assert=require('node:assert/strict');
const {PGlite}=require('C:/Temp/sams-live-tracking-tools/node_modules/@electric-sql/pglite');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
(async()=>{
 const db=new PGlite();let passed=0;
 await db.exec(`create role anon;create role authenticated;
 create function public.is_admin() returns boolean language sql as $$ select current_setting('test.admin')='true' $$;
 create function public.current_organization_is_active() returns boolean language sql as $$select true$$;
 create function public.current_organization_id() returns uuid language sql as $$select '${id(1)}'::uuid$$;
 create function public.test_now() returns timestamptz language sql stable as $$select current_setting('test.now')::timestamptz$$;
 create table public.profiles(id uuid primary key,organization_id uuid,active boolean,role text);
 insert into public.profiles values ('${id(2)}','${id(1)}',true,'user'),('${id(3)}','${id(1)}',true,'user'),('${id(4)}','${id(1)}',true,'user'),('${id(5)}','${id(9)}',true,'user');
 create table public.schedules(user_id uuid, duty_date date,start_at timestamptz,end_at timestamptz, unique(user_id,duty_date));
 create function public.create_dtr_schedule(g uuid,l uuid,d date,periods jsonb) returns setof public.schedules language plpgsql as $$
 declare s time:=(periods->0->>'start_time')::time;e time:=(periods->0->>'end_time')::time;
 begin
 return query insert into public.schedules values(g,d,(d+s) at time zone 'Asia/Manila',((d+case when e<=s then 1 else 0 end)+e) at time zone 'Asia/Manila') returning *;
 end $$;
 select set_config('test.admin','true',false);`);
 // Clock substitution only, inside an isolated database. The roster function
 // and all its validations execute unchanged; create_dtr_schedule is a fixture.
 await db.exec(fs.readFileSync('supabase/migrations/20260912000001_assign_remaining_roster_shifts.sql','utf8').replaceAll('now()','public.test_now()'));
 const call=(count,guards,day='2026-09-12')=>`select * from public.create_shift_roster('${id(8)}','${day}',${count},array[${guards.map(g=>g===null?'null':`'${id(g)}'::uuid`).join(',')}]::uuid[])`;
 async function check(name,fn){await db.exec('truncate public.schedules');await fn();passed++;console.log('PASS '+name);}
 async function time(t){await db.query("select set_config('test.now',$1,false)",['2026-09-12T'+t+'+08:00']);}
 await check('two shifts before first end both assigned',async()=>{await time('17:59:59');assert.equal((await db.query(call(2,[2,3]))).rows.length,2);});
 await check('exactly 6 PM keeps tonight and skips ended morning',async()=>{await time('18:00:00');const rows=(await db.query(call(2,[null,3]))).rows;assert.equal(rows.length,1);assert.equal(rows[0].start_at.toISOString(),'2026-09-12T10:00:00.000Z');assert.equal(rows[0].end_at.toISOString(),'2026-09-12T22:00:00.000Z');});
 await check('three shifts exactly 2 PM save afternoon and night',async()=>{await time('14:00:00');assert.equal((await db.query(call(3,[null,3,4]))).rows.length,2);});
 await check('three shifts exactly 10 PM still save night',async()=>{await time('22:00:00');assert.equal((await db.query(call(3,[null,null,4]))).rows.length,1);});
 await check('future roster still requires every guard',async()=>{await assert.rejects(db.query(call(3,[null,3,4],'2026-09-13')));assert.equal((await db.query(call(3,[2,3,4],'2026-09-13'))).rows.length,3);});
 await check('past date cannot be backdated',async()=>{await assert.rejects(db.query(call(2,[2,3],'2026-09-11')));});
 await check('remaining guard required and duplicate guards rejected',async()=>{await time('14:00:00');await assert.rejects(db.query(call(3,[null,3,null])));await assert.rejects(db.query(call(3,[null,3,3])));});
 await check('foreign-agency guard rejected',async()=>{await assert.rejects(db.query(call(3,[null,3,5])));});
 await check('ended guard does not create a historical schedule',async()=>{await time('23:00:00');const rows=(await db.query(call(2,[2,3]))).rows;assert.deepEqual(rows.map(r=>r.user_id),[id(3)]);});
 await check('conflicting later slot rolls back earlier slot',async()=>{await time('12:00:00');await db.exec(`insert into schedules values('${id(3)}','2026-09-12',now(),now())`);await assert.rejects(db.query(call(2,[2,3])));assert.equal((await db.query('select count(*)::int n from schedules')).rows[0].n,1);});
 await check('non-head cannot create roster',async()=>{await db.exec("select set_config('test.admin','false',false)");await assert.rejects(db.query(call(2,[2,3])),e=>e.code==='42501');});
 await db.close();console.log(`${passed} isolated database checks passed.`);
})().catch(error=>{console.error(error);process.exit(1);});
