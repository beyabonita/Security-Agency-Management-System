const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const S = require('../js/schedule-period.js');

const daytime = S.calculate('2026-09-03', '08:00', '17:00');
assert.equal(daytime.startAt.toISOString(), '2026-09-03T00:00:00.000Z');
assert.equal(daytime.endDate, '2026-09-03');
assert.equal(daytime.overnight, false);
assert.equal(daytime.durationMinutes, 540);
assert.equal(S.formatDuration(daytime.durationMinutes), '9 hours');
const overnight = S.calculate('2026-09-15', '20:00', '05:00');
assert.equal(overnight.endDate, '2026-09-16');
assert.equal(overnight.overnight, true);
assert.equal(overnight.durationMinutes, 540);
assert.equal(S.calculate('2026-09-03', '08:00', '08:00'), null, 'Equal times are ambiguous, not an implicit 24-hour shift');
for (const [date, start, end] of [['', '08:00', '17:00'], ['2026-02-31', '08:00', '17:00'],
  ['2026-09-03', '25:00', '17:00'], ['2026-09-03', '8:00', '17:00'], ['2026-09-03', '08:00', '17:60']]) {
  assert.equal(S.calculate(date, start, end), null);
}
for (const [now, start, end, expected] of [
  ['2026-09-04T22:07:00+08:00', '08:00', '17:00', '2026-09-05'],
  ['2026-09-04T12:00:00+08:00', '08:00', '17:00', '2026-09-04'],
  ['2026-09-04T22:07:00+08:00', '20:00', '05:00', '2026-09-04'],
  ['2026-09-04T16:59:59+08:00', '08:00', '17:00', '2026-09-04'],
  ['2026-09-04T17:00:00+08:00', '08:00', '17:00', '2026-09-05'],
  ['2026-09-30T23:59:00+08:00', '08:00', '17:00', '2026-10-01'],
  ['2026-12-31T23:59:00+08:00', '08:00', '17:00', '2027-01-01'],
]) assert.equal(S.firstSchedulableDutyDate(new Date(now), start, end), expected);
assert.equal(S.firstSchedulableDutyDate('not-a-date', '08:00', '17:00'), '');

const morning = { period: 'morning', start_time: '08:00', end_time: '12:00', next_day: false };
const afternoon = { period: 'afternoon', start_time: '13:00', end_time: '17:00', next_day: false };
const overtime = { period: 'overtime', start_time: '17:00', end_time: '19:00', next_day: false };
const split = S.buildDutyPlan('2026-09-15', [afternoon, morning]);
assert.equal(split.error, null);
assert.deepEqual(split.periods.map(period => period.period), ['morning', 'afternoon']);
assert.equal(split.durationMinutes, 480, 'The 12–13 planned break is not counted');
assert.equal(split.cutoff.endDate, '2026-09-15');
assert.equal(S.buildDutyPlan('2026-09-15', [morning, afternoon, overtime]).durationMinutes, 600);
assert.equal(S.buildDutyPlan('2026-09-15', [afternoon]).durationMinutes, 240);
const nightPlan = S.buildDutyPlan('2026-09-15', [
  { period: 'auto', start_time: '20:00', end_time: '05:00' },
  { period: 'overtime', start_time: '05:00', end_time: '07:00', next_day: true },
]);
assert.equal(nightPlan.error, null);
assert.equal(nightPlan.durationMinutes, 660);
assert.equal(nightPlan.periods[1].startAt.toISOString(), '2026-09-15T21:00:00.000Z');
assert.equal(nightPlan.periods[1].dutyDate, '2026-09-15', 'Next-day overtime retains the original cutoff');
assert.equal(nightPlan.cutoff.cutoff, 'first');
for (const entries of [[], [morning, morning], [{ ...morning, end_time: '08:00' }],
  [{ ...morning, end_time: '14:00' }, afternoon],
  [morning, { period: 'auto', start_time: '15:00', end_time: '18:00' }],
  [{ period: 'invalid', start_time: '08:00', end_time: '12:00' }]]) {
  const result = S.buildDutyPlan('2026-09-15', entries);
  assert.ok(result.error, 'Invalid plans must be rejected');
  assert.deepEqual(result.periods, [], 'A rejected plan cannot leak partial periods');
}
assert.equal(S.firstDutyPlanDate('2026-09-04T11:59:59+08:00', [morning, afternoon]), '2026-09-04');
assert.equal(S.firstDutyPlanDate('2026-09-04T12:00:00+08:00', [morning, afternoon]), '2026-09-05');
assert.equal(S.firstDutyPlanDate('2026-09-04T12:00:00+08:00', [afternoon]), '2026-09-04');
assert.equal(S.dtrPeriodForDate('2026-09-15').label, 'Sep 1–15, 2026');
assert.equal(S.dtrPeriodForDate('2028-02-16').endDate, '2028-02-29');
assert.equal(S.dtrPeriodForDate('2026-02-31'), null);
assert.equal(S.dtrColumnForTime('12:00', 'OUT', false).label, 'Morning OUT');
assert.equal(S.dtrColumnForTime('12:00', 'IN', false).label, 'Afternoon IN');
assert.equal(S.dtrColumnForTime('12:30', 'OUT', false, 'morning').label, 'Morning OUT');
assert.equal(S.dtrPlacement('2026-09-15', '20:00', '05:00').timeOut.label, 'Morning OUT (next day)');
const otPlacement = S.dtrPlacement('2026-09-15', '05:00', '07:00', 'overtime', true);
assert.equal(otPlacement.timeIn.label, 'Overtime IN (next day)');
assert.equal(otPlacement.timeOut.label, 'Overtime OUT (next day)');
assert.equal(otPlacement.period.cutoff, 'first');

// Browser/device timezone must not move Philippine duty dates.
for (const timezone of ['UTC', 'America/Los_Angeles', 'Asia/Manila']) {
  const result = spawnSync(process.execPath, ['-e', `
    const assert = require('node:assert/strict');
    const p = require(${JSON.stringify(require.resolve('../js/schedule-period.js'))});
    assert.equal(p.calculate('2026-09-15','08:00','12:00').startAt.toISOString(),'2026-09-15T00:00:00.000Z');
    assert.equal(p.toLocalDateString(new Date('2026-09-15T16:00:00Z')),'2026-09-16');
    assert.equal(p.timeString(new Date('2026-09-15T16:00:00Z')),'00:00');
    assert.equal(p.firstDutyPlanDate('2026-09-15T04:00:00Z',[${JSON.stringify(morning)},${JSON.stringify(afternoon)}]),'2026-09-16');
  `], { env: { ...process.env, TZ: timezone }, encoding: 'utf8' });
  assert.equal(result.status, 0, `${timezone}: ${result.stderr}`);
}
console.log('Schedule period tests passed (split, continuous, OT, validation, cutoff and three timezones).');
