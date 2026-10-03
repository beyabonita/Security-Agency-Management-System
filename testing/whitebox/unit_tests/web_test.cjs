const {test}=require('node:test');
const assert=require('node:assert/strict');
const schedule=require('../../../web/js/schedule-period.js');
const contract=require('../../../web/js/contract-period.js');
const dtr=require('../../../web/js/dtr-report.js');
let serial=400;
function wb(module,method,scenario,input,expected,run){
  const id=`WB-${++serial}`;
  test(`${id} ${module}.${method}: ${scenario}`,async()=>{
    const meta={id,module,method,scenario,input,expected,framework:'node:test',source:'testing/whitebox/unit_tests/web_test.cjs'};
    try{const actual=await run();console.log('WB_EVIDENCE '+JSON.stringify({...meta,actual,at:new Date().toISOString()}));assert.deepEqual(actual,expected);}
    catch(e){console.log('WB_ERROR '+JSON.stringify({...meta,error:String(e)}));throw e;}
  });
}
for(const [day,start,end,expected] of [['2026-09-05','08:00','17:00',540],['2026-09-05','20:00','04:00',480],['2026-09-05','08:00','08:00',null],['2026-02-30','08:00','17:00',null],['2028-02-29','23:59','00:00',1],['2026-09-05','24:00','17:00',null],['2026-09-05','08:60','17:00',null],['2026-09-05','','17:00',null]]) wb('SchedulePeriod','calculate','shift duration and time validity',[day,start,end],expected,()=>schedule.calculate(day,start,end)?.durationMinutes??null);
for(const [date,expected] of [['2026-09-15','2026-09-15'],['2026-09-16','2026-09-30'],['2028-02-29','2028-02-29'],['2026-02-29',null],['2026-13-01',null],['',null]])wb('SchedulePeriod','dtrPeriodForDate','calendar and cutoff boundary',date,expected,()=>schedule.dtrPeriodForDate(date)?.endDate??null);
const entry=(period,start_time,end_time)=>({period,start_time,end_time});
for(const [entries,valid] of [[[],false],[null,false],[[entry('morning','08:00','12:00'),entry('afternoon','12:00','17:00')],true],[[entry('morning','08:00','12:00'),entry('afternoon','11:59','17:00')],false],[[entry('morning','08:00','12:00'),entry('morning','13:00','17:00')],false],[[entry('auto','08:00','12:00'),entry('afternoon','13:00','17:00')],false],[[entry('unknown','08:00','12:00')],false]]) wb('SchedulePeriod','buildDutyPlan','empty, overlap and duplicate periods',entries,valid,()=>!schedule.buildDutyPlan('2026-09-05',entries).error);
wb('SchedulePeriod','buildDutyPlan','sum periods excludes unpaid gap','08-12 + 13-17',480,()=>schedule.buildDutyPlan('2026-09-05',[entry('morning','08:00','12:00'),entry('afternoon','13:00','17:00')]).durationMinutes);
wb('SchedulePeriod','buildDutyPlan','null entry should return validation error',[null],true,()=>Boolean(schedule.buildDutyPlan('2026-09-05',[null]).error));
for(const [time,dir,expected] of [['12:00','IN','Afternoon IN'],['12:00','OUT','Morning OUT'],['12:01','OUT','Afternoon OUT'],['23:59','IN','Afternoon IN'],['24:00','IN',null],['08:00','BAD',null]])wb('SchedulePeriod','dtrColumnForTime','noon and invalid direction',[time,dir],expected,()=>schedule.dtrColumnForTime(time,dir,false)?.label??null);
for(const [start,end,valid] of [['2026-09-05','2026-09-05',true],['2026-09-06','2026-09-05',false],['2026-02-30','2026-03-01',false],[null,null,false],['1899-12-31','1900-01-01',false],['2028-02-29','2028-02-29',true]])wb('ContractPeriodJS','validate','ordered real dates',[start,end],valid,()=>contract.validate('contract',start,end)==='');
const guard={role:'user',employmentCategory:'contract',contractStartDate:'2026-09-05',contractEndDate:'2026-09-05'};
for(const [start,end,valid] of [['2026-09-05T00:00:00+08:00','2026-09-06T00:00:00+08:00',true],['2026-09-05T20:00:00+08:00','2026-09-06T04:00:00+08:00',false],['2026-09-04T23:59:59+08:00','2026-09-05T08:00:00+08:00',false],['2026-09-05T08:00:00+08:00','2026-09-05T08:00:00+08:00',false]])wb('ContractPeriodJS','dutyError','entire duty must fit contract',[start,end],valid,()=>contract.dutyError(guard,new Date(start),new Date(end))==='');
for(const [input,expected] of [[{},0],[{clock_in_at:'invalid',clock_out_at:'invalid'},0],[{clock_in_at:'2026-09-05T00:00Z',clock_out_at:'2026-09-05T08:00Z'},480],[{clock_in_at:'2026-09-05T00:00Z',clock_out_at:'2026-09-04T23:59Z'},0],[{clock_in_at:'2026-09-05T00:00Z',clock_out_at:'2026-09-05T00:00:59Z'},0]])wb('DtrReport','sessionMinutes','duration boundaries',input,expected,()=>dtr.sessionMinutes(input));
for(const [month,cutoff,expected] of [['2028-02','second','2028-02-29'],['2026-02','second','2026-02-28'],['2026-09','first','2026-09-15'],['2026-13','first',null],['bad','first',null],['2026-09','third',null]])wb('DtrReport','periodFromSelection','calendar selection',[month,cutoff],expected,()=>dtr.periodFromSelection(month,cutoff)?.endDate??null);
wb('DtrReport','buildReport','empty attendance creates zero totals',[],[0,0,15],()=>{const r=dtr.buildReport([],dtr.periodFromSelection('2026-09','first'));return [r.totalMinutes,r.completedDays,r.rows.length];});
wb('DtrReport','filterSessions','inclusive cutoff bounds',['2026-08-31','2026-09-01','2026-09-15','2026-09-16'],['2026-09-01','2026-09-15'],()=>dtr.filterSessions(['2026-08-31','2026-09-01','2026-09-15','2026-09-16'].map(duty_date=>({duty_date})),dtr.periodFromSelection('2026-09','first')).map(x=>x.duty_date));
