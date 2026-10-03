(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.RosterSetup=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const validTime=value=>typeof value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(value);
  const minutes=value=>Number(value.slice(0,2))*60+Number(value.slice(3));
  function validate(shifts){
    if(!Array.isArray(shifts)||shifts.length<1||shifts.length>12)return 'Choose between 1 and 12 shifts.';
    if(shifts.length===1){
      const shift=shifts[0];
      if(!validTime(shift?.start_time)||!validTime(shift?.end_time))return 'Shift 1: enter valid start and end times.';
      return null;
    }
    for(let i=0;i<shifts.length;i++){
      const shift=shifts[i],next=shifts[(i+1)%shifts.length];
      if(!validTime(shift?.start_time)||!validTime(shift?.end_time))return `Shift ${i+1}: enter valid start and end times.`;
      if(shift.start_time===shift.end_time)return `Shift ${i+1}: start and end times must be different.`;
      if(i>0&&shift.start_time<=shifts[i-1].start_time)return 'List shifts from the earliest start time to the latest. Only the final shift can cross midnight.';
      if(shift.end_time!==next?.start_time)return 'Each shift must end when the next begins, and the final shift must end at the first shift’s start time. Cover 24 hours without gaps or overlaps.';
    }
    return null;
  }
  function clock(value){const m=minutes(value),h=Math.floor(m/60);return `${h%12||12}:${String(m%60).padStart(2,'0')} ${h<12?'AM':'PM'}`;}
  function periods(shifts){return shifts.map(s=>[s.start_time,s.end_time,`${clock(s.start_time)} – ${clock(s.end_time)}${s.end_time<s.start_time?' (next day)':''}`]);}
  function defaults(count){
    if(count===1)return [{start_time:'07:00',end_time:'19:00'}];
    const starts=count===2?['06:00','18:00']:count===3?['06:00','14:00','22:00']:Array.from({length:count},(_,i)=>{
      const m=Math.floor(i*1440/count);return `${String(Math.floor(m/60)).padStart(2,'0')}:${String(m%60).padStart(2,'0')}`;
    });
    return starts.map((start_time,i)=>({start_time,end_time:starts[(i+1)%count]}));
  }
  const signature=shifts=>shifts.map(s=>`${s.start_time}-${s.end_time}`).join(',');
  return Object.freeze({validate,periods,defaults,signature});
});
