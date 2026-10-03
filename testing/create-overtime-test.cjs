const fs=require('fs');
const original=fs.readFileSync('testing/test-strict-timeout.cjs','utf8');
const prefix=original.slice(0,original.indexOf("  await db.exec(`insert into locations values"));
const tail=String.raw`
  const notifications=read('20260823000001_add_realtime_notifications');
  await db.exec(notifications.slice(0,notifications.indexOf('create or replace function public.mark_notification_read(')));
  await db.exec(read('20260913000004_guard_overtime_timeout_choice'));
  const actor=async n=>db.exec('reset role;select set_config(\'request.jwt.claim.sub\',\''+id(n)+'\',false);set role authenticated;');
  async function setup(end="now()-interval '2 hours'") {
    await db.exec('reset role;truncate user_notifications,attendance_timeout_reviews,attendance_sessions,schedules cascade;');
    await db.exec("insert into schedules(id,organization_id,user_id,location_id,approval_status,start_at,end_at,duty_date) values('"+id(20)+"','"+id(100)+"','"+id(1)+"','"+id(10)+"','approved',("+end+")-interval '12 hours',"+end+",current_date);");
    await db.exec("insert into attendance_sessions(id,organization_id,schedule_id,user_id,location_id,location_label,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,status) select '"+id(30)+"',organization_id,id,user_id,location_id,'Gate',duty_date,start_at,end_at,start_at,'open' from schedules;");
    await actor(1);
  }
  const timeout=(choice,lat=14.6,lon=120.98,session=id(30))=>db.query('select * from record_guard_timeout($1,$2,$3,$4)',[session,lat,lon,choice]);
  const adminRead=async sql=>{await db.exec('reset role');const r=await db.query(sql);await actor(1);return r.rows;};
  await setup();
  for(const [label,choice,lat,lon,pattern] of [
    ['missing choice',null,14.6,120.98,/choose whether/],
    ['missing GPS',true,null,null,/current location/],
    ['outside original post',true,14.8,120.98,/geofence/],
    ['NaN GPS',false,NaN,120.98,/invalid/],
  ]) await check(label+' cannot submit',()=>assert.rejects(timeout(choice,lat,lon),pattern));
  await check('overtime records actual submission and queues only own active Operations Head',async()=>{
    const row=(await timeout(true)).rows[0];
    assert.equal(row.overtime_requested,true);assert.equal(row.timeout_verified_at,null);assert.equal(row.clock_out_at,row.timeout_submitted_at);
    assert.equal(Math.floor((new Date(row.clock_out_at)-new Date(row.scheduled_end_at))/60000),120);
    const notes=await adminRead('select * from user_notifications');assert.equal(notes.length,1);assert.equal(notes[0].recipient_id,id(4));
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,false);
  });
  await check('retry preserves first Time Out and creates no duplicate alert',async()=>{
    const first=(await timeout(true)).rows[0];const again=(await timeout(true)).rows[0];assert.equal(first.clock_out_at,again.clock_out_at);
    assert.equal((await adminRead('select * from user_notifications')).length,1);
    await assert.rejects(timeout(false),/different overtime choice/);
  });
  await check('only Operations Head approval finalizes overtime and notifies guard',async()=>{
    const row=(await timeout(true)).rows[0];
    const review=()=>db.query('select * from verify_attendance_timeout($1,$2,$3,$4,$5)',[row.id,row.clock_out_at,'Confirmed relief guard arrived late.',row.updated_at,id(70)]);
    await assert.rejects(review(),/Only an active agency Admin/);
    await actor(4);const approved=(await review()).rows[0];assert.ok(approved.timeout_verified_at);
    assert.equal(approved.timeout_submitted_at,row.timeout_submitted_at);
    await actor(1);
    const notes=await adminRead('select * from user_notifications');assert.equal(notes.length,2);assert.ok(notes.some(n=>n.recipient_id===id(1)));
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,true);
  });
  await setup("now()-interval '3 minutes'");
  await check('no overtime uses scheduled end without approval and preserves actual submission',async()=>{
    const row=(await timeout(false)).rows[0];assert.equal(row.clock_out_at,row.scheduled_end_at);assert.equal(row.overtime_requested,false);assert.equal(row.timeout_verified_at,null);
    assert.ok(new Date(row.timeout_submitted_at)>new Date(row.clock_out_at));
    assert.equal((new Date(row.clock_out_at)-new Date(row.clock_in_at))/3600000,12);
    assert.equal((await adminRead('select * from user_notifications')).length,0);
    assert.equal((await adminRead('select marked_done from schedules'))[0].marked_done,true);
  });
  await setup("now()+interval '1 hour'");
  await check('early ordinary Time Out uses actual time, with no overtime question required',async()=>{
    await assert.rejects(timeout(true),/only after/);
    const row=(await timeout(null)).rows[0];assert.equal(row.clock_out_at,row.timeout_submitted_at);assert.equal(row.overtime_requested,false);
    assert.ok(new Date(row.clock_out_at)<new Date(row.scheduled_end_at));
  });
  await setup();
  await check('other guard and Inspector cannot submit this guard Time Out',async()=>{
    await actor(5);await assert.rejects(timeout(true),/not found/);
    await actor(3);await assert.rejects(timeout(true),/Only active Guard/);
    await actor(1);
  });
  await check('rolled over missing duty requires review rather than a new punch',async()=>{
    await db.exec("reset role;update attendance_sessions set status='missed_timeout';");await actor(1);
    await assert.rejects(timeout(false),/no longer open/);
  });
  await db.close(); console.log(passed+' overtime-choice database checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});
`;
fs.writeFileSync('testing/test-overtime-choice.cjs',prefix+tail);
