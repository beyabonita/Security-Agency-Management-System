const fs = require('fs');
const dtr = require('../web/js/dtr-report.js');
const base = {id:'a',schedule_id:'schedule',user_id:'guard',duty_date:'2026-09-13',location_label:'Saint Francis',scheduled_start_at:'2026-09-13T06:00:00+08:00',scheduled_end_at:'2026-09-13T18:00:00+08:00',clock_in_at:'2026-09-13T06:00:00+08:00',clock_out_at:'2026-09-13T19:00:00+08:00',status:'closed'};
const cases = [
 {name:'verified overtime',sessions:[{...base,timeout_verified_at:'2026-09-14T08:00:00+08:00'}]},
 {name:'unverified three minutes',sessions:[{...base,clock_out_at:'2026-09-13T18:03:00+08:00'}]},
 {name:'missing timeout',sessions:[{...base,clock_out_at:null,status:'missed_timeout'}]},
 {name:'overnight cutoff and multiple sessions',sessions:[{...base,id:'night',duty_date:'2026-09-15',scheduled_start_at:'2026-09-15T18:00:00+08:00',scheduled_end_at:'2026-09-16T06:00:00+08:00',clock_in_at:'2026-09-15T18:00:00+08:00',clock_out_at:'2026-09-16T06:00:00+08:00'},{...base,clock_out_at:'2026-09-13T12:00:00+08:00'},{...base,id:'second',scheduled_start_at:'2026-09-13T14:00:00+08:00',scheduled_end_at:'2026-09-13T18:00:00+08:00',clock_in_at:'2026-09-13T14:00:00+08:00',clock_out_at:'2026-09-13T18:00:00+08:00'}]},
 {name:'empty cutoff',sessions:[]},
];
for(const c of cases){ const r = dtr.buildReport(c.sessions,dtr.periodFromSelection('2026-09','first')); c.expected={rows:r.shiftRows.map(s=>[s.day,s.assignedShift,s.actualIn,s.actualOut,s.overtimeHours,s.workedHours]),totalMinutes:r.totalMinutes,overtimeMinutes:r.totalOvertimeMinutes,completedDays:r.completedDays,detachment:r.detachment}; }
fs.writeFileSync('testing/guard-dtr-parity.json',JSON.stringify(cases,null,2));
