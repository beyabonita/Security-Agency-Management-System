const {test}=require('node:test'),assert=require('node:assert/strict');
const {classify,visible,createServerClock}=require('../js/live-tracking-model.js');
const now=Date.parse('2026-09-07T12:00:00Z');
const row={guard_name:'Ana <script>',location_label:'Main gate',latitude:14.6,longitude:120.98,
 accuracy_meters:10,captured_at:new Date(now-30000).toISOString(),received_at:new Date(now-20000).toISOString(),duty_end_at:new Date(now+3600000).toISOString()};
test('fresh fix is live',()=>assert.equal(classify(row,now).state,'live'));
test('server clock ages positions independently of device time and expires at actual duty end',()=>{
 let tick=100;const clock=createServerClock(()=>tick);assert.equal(clock.now(),null);
 clock.sync(new Date(now).toISOString());assert.equal(classify(row,clock.now()).state,'live');
 tick+=70000;assert.equal(classify(row,clock.now()).state,'stale');
 tick+=3600000;assert.equal(classify(row,clock.now()),null);
 assert.throws(()=>clock.sync('invalid'),/valid server time/);
});
test('old capture stays stale even if just received',()=>assert.equal(classify({...row,captured_at:new Date(now-120000).toISOString()},now).state,'stale'));
test('expired duty vanishes',()=>assert.equal(classify({...row,duty_end_at:new Date(now).toISOString()},now),null));
test('invalid and missing location data are hidden',()=>{
 for(const change of [{latitude:NaN},{longitude:181},{accuracy_meters:0},{accuracy_meters:501},{received_at:'invalid'},{captured_at:new Date(now+60000).toISOString()}])assert.equal(classify({...row,...change},now),null);
});
test('search is case insensitive and non-mutating',()=>{assert.equal(visible([row],'MAIN',now).length,1);assert.equal(visible([row],'missing',now).length,0);assert.equal(row.state,undefined);});
test('114 m fix stays visible and is explicitly approximate',()=>{
 const location=classify({...row,accuracy_meters:114},now);
 assert.equal(location.state,'live'); assert.equal(location.approximate,true);
 assert.equal(location.accuracy_meters,114);
 assert.equal(classify(row,now).approximate,false);
 assert.equal(classify({...row,accuracy_meters:500},now).approximate,true);
});
