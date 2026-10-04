(function(root) {
  'use strict';
  function classify(row, now=Date.now()) {
    const captured=Date.parse(row.captured_at), received=Date.parse(row.received_at), end=Date.parse(row.duty_end_at);
    if (!Number.isFinite(end) || end<=now) return null;
    if ([row.latitude,row.longitude,row.accuracy_meters,row.captured_at,row.received_at].every(value=>value===null)) {
      return {...row,approximate:false,ageSeconds:null,state:'waiting'};
    }
    if (!Number.isFinite(row.latitude) || !Number.isFinite(row.longitude) ||
        Math.abs(row.latitude)>90 || Math.abs(row.longitude)>180 ||
        !Number.isFinite(row.accuracy_meters) || row.accuracy_meters<=0 || row.accuracy_meters>500 ||
        !Number.isFinite(captured) || !Number.isFinite(received) || !Number.isFinite(end) ||
        captured>now+5000 || received>now+5000 || end<=now) return null;
    const age=Math.max(0, now-Math.min(captured,received));
    return {...row, approximate:row.accuracy_meters>100, ageSeconds:Math.floor(age/1000), state:age<=90000?'live':'stale'};
  }
  function visible(rows, search='', now=Date.now()) {
    const query=search.trim().toLowerCase();
    return rows.map(row=>classify(row,now)).filter(Boolean)
      .filter(row=>`${row.guard_name} ${row.location_label} ${row.mobile_number||''} ${row.contact_number||''}`.toLowerCase().includes(query));
  }
  // Advance from the server snapshot with a monotonic clock, independent of
  // device timezone, manual clock changes, or network time corrections.
  function createServerClock(monotonic=()=>performance.now()) {
    let serverAt=null,tickAt=0;
    return {
      sync(value){
        const parsed=Date.parse(value);
        if(!Number.isFinite(parsed))throw new Error('The location snapshot has no valid server time.');
        serverAt=parsed;tickAt=monotonic();
      },
      now(){return serverAt===null?null:serverAt+Math.max(0,monotonic()-tickAt);},
    };
  }
  const api={classify,visible,createServerClock};
  if(typeof module==='object') module.exports=api;
  else root.LiveTrackingModel=api;
})(typeof window==='undefined'?globalThis:window);
