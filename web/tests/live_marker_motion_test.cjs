const {test}=require('node:test');
const assert=require('node:assert/strict');
const {create}=require('../js/live-marker-motion.js');

function fixture(initial=[14.6,120.98],options={}) {
  let time=0,id=0;
  const frames=new Map(),cancelled=[];
  function layer() {
    return {
      position:[...initial],writes:[],
      getLatLng() { return {lat:this.position[0],lng:this.position[1]}; },
      setLatLng(value) { this.position=[...value];this.writes.push([...value]);return this; }
    };
  }
  const marker=layer(),circle=layer();
  const motion=create({marker,circle,now:()=>time,
    requestFrame:fn=>{frames.set(++id,fn);return id;},
    cancelFrame:frame=>{cancelled.push(frames.get(frame));frames.delete(frame);},
    reducedMotion:false,...options});
  function advance(milliseconds) {
    time+=milliseconds;
    const pending=[...frames.values()];frames.clear();
    pending.forEach(fn=>fn(time));
  }
  return {motion,marker,circle,advance,frames,cancelled};
}
function close(actual,expected) { assert.ok(Math.abs(actual-expected)<1e-9,`${actual} differs from ${expected}`); }

test('marker and accuracy circle move together between reported positions, then hold',()=>{
  const f=fixture();
  f.motion.moveTo([14.602,120.982]);
  assert.deepEqual(f.marker.position,[14.6,120.98]);
  f.advance(1000);
  close(f.marker.position[0],14.601);close(f.marker.position[1],120.981);
  assert.deepEqual(f.circle.position,f.marker.position);
  f.advance(1000);
  assert.deepEqual(f.marker.position,[14.602,120.982]);
  assert.equal(f.frames.size,0);
  f.advance(30000);
  assert.deepEqual(f.marker.position,[14.602,120.982]);
});

test('new fixes retarget from the currently displayed point without snapping',()=>{
  const f=fixture();f.motion.moveTo([14.604,120.984]);f.advance(500);
  const displayed=[...f.marker.position];
  f.motion.moveTo([14.6,120.982]);
  assert.deepEqual(f.marker.position,displayed);assert.equal(f.frames.size,1);
  f.advance(1000);
  close(f.marker.position[0],(displayed[0]+14.6)/2);
  close(f.marker.position[1],(displayed[1]+120.982)/2);
  f.advance(1000);assert.deepEqual(f.marker.position,[14.6,120.982]);
});

test('duplicate updates do not restart movement',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982]);f.advance(1000);
  f.motion.moveTo([14.602,120.982]);f.advance(1000);
  assert.deepEqual(f.marker.position,[14.602,120.982]);assert.equal(f.frames.size,0);
});

test('stop cancels movement and ignores an already queued callback after removal',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982]);f.advance(500);
  const displayed=[...f.marker.position];
  f.motion.stop();assert.equal(f.frames.size,0);
  f.cancelled.at(-1)();f.advance(3000);
  assert.deepEqual(f.marker.position,displayed);assert.deepEqual(f.circle.position,displayed);
});

test('stop with finish applies the last real fix immediately',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982]);f.advance(500);
  f.motion.stop({finish:true});
  assert.deepEqual(f.marker.position,[14.602,120.982]);
  assert.deepEqual(f.circle.position,f.marker.position);assert.equal(f.frames.size,0);
});

test('reduced motion honors a live preference change',()=>{
  let reduced=false;
  const f=fixture(undefined,{reducedMotion:()=>reduced});
  f.motion.moveTo([14.602,120.982]);f.advance(500);reduced=true;
  f.motion.moveTo([14.602,120.982]);
  assert.deepEqual(f.marker.position,[14.602,120.982]);assert.equal(f.frames.size,0);
  const immediate=fixture(undefined,{reducedMotion:true});
  immediate.motion.moveTo([14.602,120.982]);assert.equal(immediate.frames.size,0);
  assert.deepEqual(immediate.marker.position,[14.602,120.982]);
});

test('a correction farther than 1 km is applied without drawing a travel path',()=>{
  const f=fixture();f.motion.moveTo([14.7,121.08]);
  assert.deepEqual(f.marker.position,[14.7,121.08]);
  assert.deepEqual(f.circle.position,f.marker.position);assert.equal(f.frames.size,0);
});

test('a small move across the antimeridian takes the short direction',()=>{
  const f=fixture([0,179.999]);f.motion.moveTo([0,-179.999]);f.advance(1000);
  close(Math.abs(f.marker.position[1]),180);f.advance(1000);
  assert.deepEqual(f.marker.position,[0,-179.999]);
});

test('invalid coordinates are ignored without interrupting valid movement',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982]);
  for(const value of [null,[],[NaN,120],[91,120],[14.6,181],['14.6',120]]) {
    assert.equal(f.motion.moveTo(value),false);
  }
  assert.equal(f.frames.size,1);f.advance(2000);
  assert.deepEqual(f.marker.position,[14.602,120.982]);
});

test('custom duration and a delayed animation frame finish exactly at the GPS fix',()=>{
  const f=fixture();f.motion.moveTo({lat:14.602,lng:120.982},{duration:4000});
  f.advance(1000);close(f.marker.position[0],14.6005);
  f.advance(10000);assert.deepEqual(f.marker.position,[14.602,120.982]);
  assert.equal(f.frames.size,0);
});

test('zero duration applies immediately and unchanged positions allocate no frames',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982],{duration:0});
  assert.deepEqual(f.marker.position,[14.602,120.982]);assert.equal(f.frames.size,0);
  f.motion.moveTo([14.602,120.982]);assert.equal(f.frames.size,0);
});

test('an old cancelled callback cannot interfere with a replacement animation',()=>{
  const f=fixture();f.motion.moveTo([14.602,120.982]);f.advance(500);
  f.motion.moveTo([14.601,120.981]);
  const writes=f.marker.writes.length;f.cancelled.at(-1)();
  assert.equal(f.marker.writes.length,writes);assert.equal(f.frames.size,1);
  f.advance(2000);assert.deepEqual(f.marker.position,[14.601,120.981]);
});
