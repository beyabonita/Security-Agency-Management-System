const assert = require('node:assert/strict');
const {test} = require('node:test');
const ui = require('../web/js/contract-period.js');
test('Contract UI validates required, reverse, real dates and inclusive same-day contracts', () => {
  assert.ok(ui.validate('contract', '', ''));
  assert.ok(ui.validate('contract', '2026-02-30', '2026-03-05'));
  assert.ok(ui.validate('contract', '2026-09-06', '2026-09-05'));
  assert.equal(ui.validate('contract', '2028-02-29', '2028-02-29'), '');
  assert.equal(ui.validate('regular', '', ''), '');
});
test('Scheduling must fit entire period including overnight end', () => {
  const guard = {role:'user', employmentCategory:'contract', contractStartDate:'2026-09-05', contractEndDate:'2026-09-05'};
  const check = (s,e) => ui.dutyError(guard,new Date(s),new Date(e));
  assert.equal(check('2026-09-05T00:00:00+08:00','2026-09-06T00:00:00+08:00'), '');
  assert.ok(check('2026-09-05T20:00:00+08:00','2026-09-06T04:00:00+08:00'));
  assert.ok(check('2026-09-04T23:59:59+08:00','2026-09-05T08:00:00+08:00'));
  assert.equal(ui.label(guard,new Date('2026-09-05T16:00:00Z')), '2026-09-05 – 2026-09-05 · Expired');
});
test('Edge validation matches UI and does not invent legacy dates', async () => {
  const {contractPeriod} = await import('../supabase/functions/_shared/contract-period.ts');
  for (const [s,e] of [['',''],['2026-02-30','2026-03-05'],['2026-09-06','2026-09-05'],['2028-02-29','2028-02-29']]) {
    assert.equal(contractPeriod('contract',s,e).error || '', ui.validate('contract',s,e));
  }
  assert.deepEqual(contractPeriod('contract',null,null,true), {start:null,end:null});
  assert.ok(contractPeriod('contract',null,null).error);
  assert.deepEqual(contractPeriod('regular','2026-01-01','2026-12-31'), {start:null,end:null});
});
