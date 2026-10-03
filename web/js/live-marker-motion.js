(function(root,factory) {
  'use strict';
  const api=factory(root);
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.LiveMarkerMotion=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(root) {
  'use strict';
  const defaultDuration=2000, maxAnimatedDistance=1000;
  function point(value) {
    if(!value)return null;
    const lat=Array.isArray(value)?value[0]:value.lat;
    const lng=Array.isArray(value)?value[1]:value.lng;
    return Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180?[lat,lng]:null;
  }
  function longitudeDelta(from,to) { return ((to-from+540)%360)-180; }
  function distance(from,to) {
    const radians=Math.PI/180;
    const dLat=(to[0]-from[0])*radians,dLng=longitudeDelta(from[1],to[1])*radians;
    const a=Math.sin(dLat/2)**2+Math.cos(from[0]*radians)*Math.cos(to[0]*radians)*Math.sin(dLng/2)**2;
    return 6371000*2*Math.asin(Math.sqrt(Math.min(1,Math.max(0,a))));
  }
  function same(a,b) { return a&&b&&a[0]===b[0]&&a[1]===b[1]; }
  function create(options) {
    const {marker,circle}=options;
    if(!marker||typeof marker.getLatLng!=='function'||typeof marker.setLatLng!=='function') {
      throw new TypeError('A marker with getLatLng and setLatLng is required.');
    }
    const requestFrame=options.requestFrame||root.requestAnimationFrame?.bind(root);
    const cancelFrame=options.cancelFrame||root.cancelAnimationFrame?.bind(root);
    const now=options.now||(()=>root.performance?.now()??Date.now());
    const reducedMotion=options.reducedMotion??(()=>root.matchMedia?.('(prefers-reduced-motion: reduce)').matches===true);
    let frame=null,generation=0,target=null;
    function write(value) {
      marker.setLatLng(value);
      circle?.setLatLng(value);
    }
    function stop({finish=false}={}) {
      generation++;
      if(frame!==null)cancelFrame?.(frame);
      frame=null;
      if(finish&&target)write(target);
      target=null;
    }
    function moveTo(value,{duration=defaultDuration}={}) {
      const next=point(value);
      if(!next)return false;
      const immediate=typeof reducedMotion==='function'?reducedMotion():reducedMotion;
      // Repeated refreshes of the same fix must not restart an in-flight movement.
      if(same(target,next)&&frame!==null&&!immediate)return true;
      stop();
      const from=point(marker.getLatLng());
      target=next;
      const milliseconds=Number.isFinite(duration)?duration:defaultDuration;
      // A large correction should appear at its reported position, without inventing a route.
      if(!from||same(from,next)||immediate||!requestFrame||milliseconds<=0||distance(from,next)>maxAnimatedDistance) {
        write(next);target=null;return true;
      }
      const startedAt=now(),revision=generation,dLng=longitudeDelta(from[1],next[1]);
      function animate() {
        if(revision!==generation)return;
        frame=null;
        const progress=Math.min(1,Math.max(0,(now()-startedAt)/milliseconds));
        if(progress>=1) {
          write(next);target=null;return;
        }
        const lng=((from[1]+dLng*progress+540)%360)-180;
        write([from[0]+(next[0]-from[0])*progress,lng]);
        frame=requestFrame(animate);
      }
      frame=requestFrame(animate);
      return true;
    }
    return {moveTo,stop};
  }
  return {create};
});
