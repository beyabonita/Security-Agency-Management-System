const assert = require('node:assert/strict');
const DtrReport = require('../js/dtr-report.js');
const SchedulePeriod = require('../js/schedule-period.js');

// Check all five roster slots across cutoff and month-end boundaries.
for (const dutyDate of ['2026-09-15', '2026-09-30']) {
  for (const [start, end, inColumn, outColumn, hours] of [
    ['06:00','18:00','morningIn','afternoonOut','12:00'],
    ['18:00','06:00','afternoonIn','morningOut','12:00'],
    ['06:00','14:00','morningIn','afternoonOut','8:00'],
    ['14:00','22:00','afternoonIn','afternoonOut','8:00'],
    ['22:00','06:00','afternoonIn','morningOut','8:00'],
  ]) {
    const shift = SchedulePeriod.calculate(dutyDate, start, end);
    const mapping = SchedulePeriod.dtrPlacement(dutyDate, start, end);
    const session = {duty_date:dutyDate,dtr_period:'auto',scheduled_start_at:shift.startAt,
      scheduled_end_at:shift.endAt,clock_in_at:shift.startAt,clock_out_at:shift.endAt};
    const selection = DtrReport.selectionFromDate(dutyDate);
    const rosterReport = DtrReport.buildReport([session], DtrReport.periodFromSelection(selection.month, selection.cutoff));
    const row = rosterReport.rows.find(row => row.dutyDate === dutyDate);
    assert.equal(mapping.timeIn.section.toLowerCase()+'In',inColumn);
    assert.equal(mapping.timeOut.section.toLowerCase()+'Out',outColumn);
    assert.equal(row[inColumn],DtrReport.formatTime(shift.startAt));
    assert.equal(row[outColumn],DtrReport.formatTime(shift.endAt)+(shift.overnight?' (next day)':''));
    assert.equal(row.totalHours,hours);
    assert.equal(row.overtimeIn,''); assert.equal(row.overtimeOut,'');
    assert.equal(rosterReport.completedDays,1);
    const pending = DtrReport.buildReport([{...session,clock_in_at:null,clock_out_at:null}], rosterReport.period);
    assert.equal(pending.totalMinutes,0);
    assert.equal(pending.rows.find(row=>row.dutyDate===dutyDate)[inColumn],'');
  }
}

const firstCutoff = DtrReport.periodFromSelection('2026-09', 'first');
assert.equal(firstCutoff.startDate, '2026-09-01');
assert.equal(firstCutoff.endDate, '2026-09-15');

const secondCutoff = DtrReport.periodFromSelection('2026-02', 'second');
assert.equal(secondCutoff.startDate, '2026-02-16');
assert.equal(secondCutoff.endDate, '2026-02-28');
assert.equal(DtrReport.periodFromSelection('2028-02', 'second').endDate, '2028-02-29');
assert.equal(DtrReport.periodFromSelection('not-a-month', 'first'), null);

const sessions = [
  {
    duty_date: '2026-09-03',
    clock_in_at: '2026-09-03T08:00:00+08:00',
    clock_out_at: '2026-09-03T17:00:00+08:00',
    location_label: 'Main Detachment',
  },
  {
    duty_date: '2026-09-14',
    clock_in_at: '2026-09-14T20:00:00+08:00',
    clock_out_at: '2026-09-15T05:00:00+08:00',
    location_label: 'Main Detachment',
  },
  {
    duty_date: '2026-09-17',
    clock_in_at: '2026-09-17T08:00:00+08:00',
    clock_out_at: null,
    location_label: 'Other Site',
  },
  {
    duty_date: '2026-09-05',
    scheduled_start_at: '2026-09-05T08:00:00+08:00',
    scheduled_end_at: '2026-09-05T17:00:00+08:00',
    clock_in_at: '2026-09-05T12:05:00+08:00',
    clock_out_at: '2026-09-05T17:30:00+08:00',
    timeout_verified_at: '2026-09-06T08:00:00+08:00',
    location_label: 'Main Detachment',
  },
];

assert.deepEqual(DtrReport.defaultSelection(sessions), { month: '2026-09', cutoff: 'second' });
assert.equal(DtrReport.filterSessions(sessions, firstCutoff).length, 3);

const report = DtrReport.buildReport(sessions, firstCutoff);
assert.equal(report.rows.length, 15, 'The first cutoff should contain days 1 through 15');
assert.equal(report.completedDays, 3);
assert.equal(report.totalMinutes, 1405);
assert.equal(report.detachment, 'Main Detachment');

const dayShift = report.rows.find((row) => row.day === '3');
assert.match(dayShift.morningIn, /8:00\s*AM/i);
assert.match(dayShift.afternoonOut, /5:00\s*PM/i);
assert.equal(dayShift.totalHours, '9:00');

const nightShift = report.rows.find((row) => row.day === '14');
assert.match(nightShift.afternoonIn, /8:00\s*PM/i);
assert.match(nightShift.morningOut, /5:00\s*AM/i);
assert.match(nightShift.morningOut, /\(next day\)/, 'Overnight Time Out should be identified as next day');
assert.equal(nightShift.totalHours, '9:00');
assert.equal(nightShift.overtimeIn, '', 'Overtime must not be fabricated without separate punches');

const lateDayShift = report.rows.find((row) => row.day === '5');
assert.match(lateDayShift.morningIn, /12:05\s*PM/i, 'The actual punch time should be retained');
assert.equal(lateDayShift.afternoonIn, '', 'A late punch must not move out of its scheduled DTR column');

const blankReport = DtrReport.buildReport([], secondCutoff, 'Assigned Post');
assert.equal(blankReport.rows.length, 13);
assert.equal(blankReport.detachment, 'Assigned Post');
assert.equal(blankReport.totalMinutes, 0);

const preview = DtrReport.renderPreview({
  sessions,
  period: firstCutoff,
  account: { firstName: 'Pedro', middleInitial: 'D', lastName: 'Dela Cruz' },
  detachment: 'Fallback Post',
  logoUrl: '../icons/sentinel-link-mark.png',
});
assert.match(preview, /TWENTY TWENTY SECURITY AGENCY, INC\./);
assert.match(preview, /DAILY TIME RECORD/);
assert.match(preview, /Pedro D\. Dela Cruz/);
assert.match(preview, /Main Detachment/);
assert.match(preview, /Sep 1, 2026 - Sep 15, 2026/);
assert.equal((preview.match(/<tbody>[\s\S]*?<\/tbody>/)?.[0].match(/<tr>/g) || []).length, 15);
assert.match(preview, /\(next day\)/, 'The HTML preview should preserve overnight punch notation');
assert.match(preview, /NO\. OF DAYS/);
assert.match(preview, /TOTAL WORKED HOURS/);

const escapedPreview = DtrReport.renderPreview({
  sessions: [{
    duty_date: '2026-09-03',
    clock_in_at: '2026-09-03T08:00:00+08:00',
    clock_out_at: '2026-09-03T17:00:00+08:00',
    location_label: '<script>alert("site")</script>',
  }],
  period: firstCutoff,
  account: { firstName: '<img src=x onerror=alert(1)>', lastName: 'Guard' },
  logoUrl: 'logo.png" onerror="alert(2)',
});
assert.doesNotMatch(escapedPreview, /<script>/);
assert.doesNotMatch(escapedPreview, /<img src=x onerror=/);
assert.doesNotMatch(escapedPreview, /src="logo\.png" onerror=/);
assert.match(escapedPreview, /&lt;script&gt;/);
assert.match(escapedPreview, /&lt;img src=x onerror=alert\(1\)&gt;/);

console.log('DTR report tests passed.');

// Explicit DTR periods retain their column even when real punches cross noon.
const explicitSessions = [
  { duty_date: '2026-09-15', dtr_period: 'morning', scheduled_start_at: '2026-09-15T08:00:00+08:00', scheduled_end_at: '2026-09-15T12:00:00+08:00', clock_in_at: '2026-09-15T08:05:00+08:00', clock_out_at: '2026-09-15T12:10:00+08:00' },
  { duty_date: '2026-09-15', dtr_period: 'afternoon', scheduled_start_at: '2026-09-15T13:00:00+08:00', scheduled_end_at: '2026-09-15T17:00:00+08:00', clock_in_at: '2026-09-15T12:55:00+08:00', clock_out_at: '2026-09-15T16:50:00+08:00' },
  { duty_date: '2026-09-15', dtr_period: 'overtime', scheduled_start_at: '2026-09-16T01:00:00+08:00', scheduled_end_at: '2026-09-16T03:00:00+08:00', clock_in_at: '2026-09-16T01:02:00+08:00', clock_out_at: '2026-09-16T03:02:00+08:00' },
];
explicitSessions.forEach(session => { session.timeout_verified_at = '2026-09-17T00:00:00Z'; });
const explicitReport = DtrReport.buildReport(explicitSessions, firstCutoff);
const explicitRow = explicitReport.rows[14];
assert.equal(explicitReport.completedDays, 1, 'Three completed periods count as one duty date');
assert.equal(explicitReport.totalMinutes, 600, 'Only actual closed session intervals count; break is excluded');
assert.equal(explicitRow.totalHours, '10:00');
assert.match(explicitRow.morningIn, /8:05\s*AM/);
assert.match(explicitRow.morningOut, /12:10\s*PM/);
assert.match(explicitRow.afternoonIn, /12:55\s*PM/);
assert.match(explicitRow.afternoonOut, /4:50\s*PM/);
assert.match(explicitRow.overtimeIn, /1:02\s*AM \(next day\)/);
assert.match(explicitRow.overtimeOut, /3:02\s*AM \(next day\)/);
assert.equal(DtrReport.buildReport(explicitSessions, DtrReport.periodFromSelection('2026-09', 'second')).sessions.length, 0);
const repeated = DtrReport.buildReport([explicitSessions[0], { ...explicitSessions[0], clock_in_at: '2026-09-15T09:00:00+08:00', clock_out_at: null }], firstCutoff).rows[14];
assert.match(repeated.morningIn, /8:05\s*AM\n9:00\s*AM/, 'Repeated actual punches remain visible');
const noon = DtrReport.buildReport([{ duty_date: '2026-09-15', clock_in_at: '2026-09-15T08:00:00+08:00', clock_out_at: '2026-09-15T12:00:00+08:00' }], firstCutoff).rows[14];
assert.match(noon.morningOut, /12:00\s*PM/);
assert.equal(noon.afternoonOut, '');
const noPunches = DtrReport.buildReport([{ duty_date: '2026-09-15', dtr_period: 'overtime', scheduled_start_at: '2026-09-15T17:00:00+08:00', scheduled_end_at: '2026-09-15T19:00:00+08:00' }], firstCutoff).rows[14];
assert.equal(noPunches.overtimeIn, ''); assert.equal(noPunches.overtimeOut, ''); assert.equal(noPunches.totalMinutes, 0);
const repeatedPreview = DtrReport.renderPreview({ sessions: [explicitSessions[0], { ...explicitSessions[0], clock_in_at: '2026-09-15T09:00:00+08:00', clock_out_at: null }], period: firstCutoff });
assert.match(repeatedPreview, /<td>8:05\s*AM<\/td>/);
assert.match(repeatedPreview, /<td>9:00\s*AM<\/td>/);
assert.equal((repeatedPreview.match(/<tbody>[\s\S]*?<\/tbody>/)[0].match(/<tr>/g)||[]).length,16);
console.log('Explicit-period actual DTR tests passed.');

const forgotten = {
  duty_date: '2026-09-08', status: 'open', dtr_period: 'auto',
  scheduled_start_at: '2026-09-08T08:00:00+08:00', scheduled_end_at: '2026-09-08T20:00:00+08:00',
  clock_in_at: '2026-09-08T08:00:00+08:00', clock_out_at: null,
};
assert.equal(DtrReport.needsTimeoutReview(forgotten, new Date('2026-09-08T10:00:00+08:00')), false);
assert.equal(DtrReport.needsTimeoutReview(forgotten, new Date('2026-09-09T08:00:00+08:00')), true);
const missing = DtrReport.buildReport([{...forgotten, status:'missed_timeout'}],firstCutoff);
assert.equal(missing.totalMinutes,0); assert.equal(missing.completedDays,0);
assert.equal(missing.rows[7].afternoonOut,'');
assert.match(missing.reviewNotes[0].status,/Missing Time Out/);
const late = {...forgotten, status:'closed', clock_out_at:'2026-09-09T08:00:00+08:00'};
const unverified = DtrReport.buildReport([late],firstCutoff);
assert.equal(unverified.totalMinutes,0); assert.equal(unverified.completedDays,0);
assert.match(unverified.rows[7].afternoonOut,/8:00\s*AM \(next day\)/);
assert.match(unverified.reviewNotes[0].status,/awaiting Operations Head verification/);
const verified = {...late, clock_out_at:'2026-09-08T20:00:00+08:00', timeout_verified_at:'2026-09-09T09:00:00+08:00'};
assert.equal(DtrReport.buildReport([verified],firstCutoff).totalMinutes,720);
assert.equal(DtrReport.buildReport([verified,{...forgotten,status:'missed_timeout'}],firstCutoff).completedDays,0);
const genuineOvernight = {...forgotten, duty_date:'2026-09-08', scheduled_start_at:'2026-09-08T20:00:00+08:00', scheduled_end_at:'2026-09-09T08:00:00+08:00', clock_in_at:'2026-09-08T20:00:00+08:00',clock_out_at:'2026-09-09T08:00:00+08:00'};
assert.equal(DtrReport.needsTimeoutReview(genuineOvernight),false);
assert.equal(DtrReport.sessionMinutes(genuineOvernight),720);
assert.match(DtrReport.renderPreview({sessions:[late],period:firstCutoff}),/hours excluded/);
console.log('Missing and late Time Out verification tests passed.');

assert.match(preview,/Assigned shift \/ Site/);
assert.match(preview,/Actual<br>Time In/);
assert.match(preview,/Worked<br>Hours/);
assert.doesNotMatch(preview,/<th[^>]*>(Morning|Afternoon|Overtime)</);
const shiftReport=DtrReport.buildReport([genuineOvernight,verified,{...forgotten,status:'missed_timeout'}],firstCutoff);
const shiftRows=shiftReport.shiftRows.filter(r=>r.dutyDate==='2026-09-08');
assert.equal(shiftRows.length,3,'Distinct sessions on the same day must not be merged');
assert.match(shiftRows[0].actualIn,/8:00\s*AM/);
assert.equal(shiftRows.filter(r=>r.status==='Verified').length,1);
assert.equal(shiftRows.filter(r=>r.status.includes('Missing Time Out'))[0].workedHours,'');
assert.equal(shiftRows.find(r=>r.actualOut.includes('(next day)')).workedHours,'12:00');
const archivedOvertime=DtrReport.buildReport([{...genuineOvernight,dtr_period:'overtime'}],firstCutoff);
assert.match(archivedOvertime.shiftRows.find(r=>r.actualIn).assignedShift,/Overtime assignment/);
console.log('Shift-format DTR rows preserve actual punches, multiple sessions, legacy overtime, and pending verification.');

// Overtime follows the assigned end, including late starts and overnight duty.
const overtimeBase={duty_date:'2026-09-08',dtr_period:'auto',status:'closed',
  scheduled_start_at:'2026-09-08T06:00:00+08:00',scheduled_end_at:'2026-09-08T18:00:00+08:00',
  clock_in_at:'2026-09-08T06:00:00+08:00',clock_out_at:'2026-09-08T19:00:00+08:00',
  timeout_verified_at:'2026-09-09T08:00:00+08:00'};
for(const [change,expected] of [
  [{},60],
  [{clock_out_at:'2026-09-08T18:00:00+08:00'},0],
  [{clock_out_at:'2026-09-08T17:45:00+08:00'},0],
  [{clock_out_at:'2026-09-08T18:03:00+08:00'},3],
  [{clock_in_at:'2026-09-08T07:00:00+08:00'},60],
  [{clock_in_at:'2026-09-08T18:30:00+08:00'},30],
  [{clock_in_at:'2026-09-08T05:00:00+08:00',clock_out_at:'2026-09-08T18:00:00+08:00'},0],
  [{clock_in_at:'2026-09-08T20:00:00+08:00'},0],
  [{timeout_verified_at:null},null],
  [{clock_out_at:null},null],
  [{clock_in_at:null},null],
  [{scheduled_end_at:null},null],
  [{scheduled_end_at:'invalid'},null],
]) assert.equal(DtrReport.sessionOvertimeMinutes({...overtimeBase,...change}),expected,JSON.stringify(change));
const overtimeReport=DtrReport.buildReport([overtimeBase],firstCutoff);
const overtimeRow=overtimeReport.shiftRows.find(row=>row.actualIn);
assert.equal(overtimeRow.overtimeHours,'1:00');
assert.equal(overtimeRow.workedHours,'13:00');
assert.equal(overtimeReport.totalOvertimeMinutes,60);
assert.equal(overtimeReport.totalMinutes,780,'Overtime must not be added twice');
const overnightOT={...overtimeBase,duty_date:'2026-09-15',scheduled_start_at:'2026-09-15T22:00:00+08:00',
  scheduled_end_at:'2026-09-16T06:00:00+08:00',clock_in_at:'2026-09-15T22:00:00+08:00',
  clock_out_at:'2026-09-16T08:00:00+08:00',timeout_verified_at:'2026-09-16T09:00:00+08:00'};
const overnightOTReport=DtrReport.buildReport([overnightOT],firstCutoff);
assert.equal(overnightOTReport.totalOvertimeMinutes,120);
assert.equal(overnightOTReport.shiftRows.at(-1).workedHours,'10:00');
assert.match(overnightOTReport.shiftRows.at(-1).actualOut,/\(next day\)/);
const incompleteOT=DtrReport.buildReport([{...overtimeBase,timeout_verified_at:null}],firstCutoff);
assert.equal(incompleteOT.totalOvertimeMinutes,0);assert.equal(incompleteOT.totalMinutes,0);
assert.equal(incompleteOT.shiftRows.find(row=>row.actualIn).overtimeHours,'');
const otPreview=DtrReport.renderPreview({sessions:[overtimeBase],period:firstCutoff});
assert(otPreview.indexOf('Total Overtime<br>Hours')<otPreview.indexOf('Total Worked<br>Hours'));
assert.match(otPreview,/TOTAL OVERTIME HOURS/);
assert.match(otPreview,/already included in Total Worked Hours/);
console.log('Automatic overtime tests passed: scheduled end, verification, minute precision, midnight, and no double counting.');

const sixColumnPreview=DtrReport.renderPreview({sessions:[],period:firstCutoff});
assert.equal((sixColumnPreview.match(/scope="col"/g)||[]).length,6);
assert.doesNotMatch(sixColumnPreview,/<th[^>]*>Status<\/th>/);
assert.equal((sixColumnPreview.match(/<td/g)||[]).length,15*5);
console.log('DTR preview has six aligned columns without Status.');
