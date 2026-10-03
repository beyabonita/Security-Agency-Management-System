const fs = require('node:fs');
const file = 'web/tests/schedule_lifecycle.spec.js';
let source = fs.readFileSync(file, 'utf8');
source = source.replace("if (name === 'create_dtr_schedule')", "if (name === 'create_shift_roster')");
source = source.replace("const plan = SchedulePeriod.buildDutyPlan(args.p_duty_date, args.p_periods);", `const times = args.p_shift_count === 2 ? [['06:00','18:00'],['18:00','06:00']] : [['06:00','14:00'],['14:00','22:00'],['22:00','06:00']];
          const plan = { periods: times.map(([start_time,end_time]) => SchedulePeriod.buildDutyPlan(args.p_duty_date,[{period:'auto',start_time,end_time}]).periods[0]) };`);
source = source.replace('user_id: args.p_user_id', 'user_id: args.p_guard_ids[index]');
source = source.replace("{ id: 'test-inspector', role: 'inspector', name: 'Inspector', active: true });", "{ id: 'test-inspector', role: 'inspector', name: 'Inspector', active: true },\n      { id: 'peer', role: 'user', name: 'Guard Two', active: true, employmentCategory: 'regular' },\n      { id: 'third', role: 'user', name: 'Guard Three', active: true, employmentCategory: 'regular' });");
source = source.replace(/^.*document.querySelector\('#guardUser'\).*\n/m, '').replace(/^.*document.querySelector\('#scheduleLocation'\).*\n/m, '');
source = source.replace('window.setDefaultScheduleDates();', 'window.renderShiftRoster();');
const start = source.indexOf('async function fillPersonnel');
const end = source.indexOf("test('attendance reports completion");
source = source.slice(0, start) + `async function showRows(page, rows) {
  await page.evaluate(async rows => { scheduleTest.rows = rows; await refreshSchedules(); }, rows);
}
const deleteButtons = page => page.locator('#scheduleTable [data-delete-schedule]');
async function fillRoster(page, date = '2099-01-01') {
  await page.locator('#rosterDate').fill(date);
  await page.locator('#rosterSite').selectOption('test-site');
  await page.locator('#rosterGuard0').selectOption('test-guard');
  await page.locator('#rosterGuard1').selectOption('peer');
}

test('roster is the only editor and explains the actual DTR and overtime rules', async ({ page }) => {
  await expect(page.getByText('Custom personnel duty plan')).toHaveCount(0);
  await expect(page.locator('#guardUser,#scheduleMode,#overtimeEnabled')).toHaveCount(0);
  await expect(page.getByRole('button', {name:'Create schedule', exact:true})).toHaveCount(0);
  await expect(page.getByRole('button', {name:'Assign all shifts', exact:true})).toBeVisible();
  await page.getByText('How does overtime work?', {exact:true}).click();
  await expect(page.locator('.roster-dtr-guide')).toContainText('Verifying attendance does not approve overtime pay.');
  await expect(page.locator('.roster-dtr-guide')).toContainText('stay blank for roster shifts');
  expect(await page.evaluate(() => typeof window.addSchedule)).toBe('undefined');
});

test('an overnight roster remains on the starting date and first DTR cutoff', async ({ page }) => {
  await fillRoster(page, '2099-01-15');
  await expect(page.locator('#rosterPreview')).toContainText('Jan 1–15, 2099');
  await expect(page.locator('#rosterPreview')).toContainText('Morning OUT (+1)');
  await page.locator('#saveRoster').click();
  await expect(page.getByText('2 shifts assigned successfully.', {exact:true})).toBeVisible();
  await expect(page.locator('#scheduleTable tr')).toHaveCount(2);
  const night = page.locator('#scheduleTable tr').filter({hasText:'Guard Two'});
  await expect(night.locator('.schedule-dtr-time')).toHaveText(['—','6:00 AM (+1)','6:00 PM','—','—','—']);
  await expect(night).toContainText('12 hours');
  expect(await page.evaluate(() => scheduleTest.created[0].map(row => row.duty_date))).toEqual(['2099-01-15','2099-01-15']);
  await page.locator('#scheduleCutoff').selectOption('second');
  await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
});

for (const kind of ['missing contract dates', 'outside contract dates', 'overnight contract end', 'inactive guard', 'expired shift']) {
  test(kind + ' prevents a roster request', async ({ page }) => {
    await fillRoster(page);
    await page.evaluate(kind => {
      if (kind === 'missing contract dates') guards[0].employmentCategory = 'contract';
      if (kind === 'outside contract dates') Object.assign(guards[0], {employmentCategory:'contract',contractStartDate:'2099-01-02',contractEndDate:'2099-01-31'});
      if (kind === 'overnight contract end') Object.assign(guards.find(g=>g.id==='peer'), {employmentCategory:'contract',contractStartDate:'2099-01-01',contractEndDate:'2099-01-01'});
      if (kind === 'inactive guard') guards[0].active = false;
    }, kind);
    if (kind === 'expired shift') {
      await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
      await page.locator('#rosterDate').fill('2026-09-04');
    }
    await page.locator('#saveRoster').click();
    await expect(page.locator('.sl-toast')).toBeVisible();
    expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='create_shift_roster'))).toEqual([]);
  });
}

test('a failed save prevents duplicate submission and preserves selected guards', async ({ page }) => {
  await fillRoster(page);
  await page.evaluate(() => { scheduleTest.pendingCreate=true; scheduleTest.createError={message:'Schedule conflict. Choose different Guards.'}; });
  await page.locator('#saveRoster').click();
  await expect(page.locator('#saveRoster')).toBeDisabled();
  await expect(page.locator('#rosterSetup')).toBeDisabled();
  await page.evaluate(() => { document.getElementById('saveRoster').dispatchEvent(new Event('click')); finishTestCreate(); });
  await expect(page.getByText('Schedule conflict. Choose different Guards.',{exact:true})).toBeVisible();
  await expect(page.locator('#saveRoster')).toBeEnabled();
  await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  await expect(page.locator('#rosterGuard1')).toHaveValue('peer');
  expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='create_shift_roster').length)).toBe(1);
});

test('an incomplete RPC response cannot report a saved roster', async ({ page }) => {
  await fillRoster(page); await page.evaluate(() => scheduleTest.malformedResult=true);
  await page.locator('#saveRoster').click();
  await expect(page.getByText('Could not confirm all assignments. Refresh the schedule before retrying.',{exact:true})).toBeVisible();
  await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
});

test('after the first shift ends the initial roster date moves to tomorrow', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  await page.reload();
  await expect(page.locator('#rosterDate')).toHaveValue('2026-09-05');
});

` + source.slice(end);
// The shared fixture now provides all three Guards.
source = source.replace(/    guards.push\(\{id:'peer'[\s\S]*?employmentCategory:'regular'\}\);\n/, '');
fs.writeFileSync(file, source);

const responsiveFile = 'web/tests/responsive_shells.spec.js';
let responsive = fs.readFileSync(responsiveFile,'utf8');
const first=responsive.indexOf("test('DTR duty editor supports"), last=responsive.indexOf("test('Guard DTR modals",first);
responsive=responsive.slice(0,first)+`test('roster DTR preview fits phone and desktop in light and dark themes', async ({ page }, testInfo) => {
  await openProtectedLayout(page, '/admin/schedule.html');
  await expect(page.locator('#scheduleMode')).toHaveCount(0);
  await page.locator('#rosterDate').fill('2099-09-15');
  await page.locator('#rosterSetup').selectOption('3');
  await expect(page.locator('#rosterPreview')).toContainText('Sep 1–15, 2099');
  await expect(page.locator('#rosterPreview')).toContainText('Morning OUT (+1)');
  await expect(page.locator('#rosterGuards select')).toHaveCount(3);
  for (const width of [390,1440]) {
    await page.setViewportSize({width,height:1000});
    for (const theme of ['light','dark']) {
      await page.evaluate(theme => sentinelTheme.set(theme), theme);
      await expect(page.locator('#rosterPreview')).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.screenshot({path:testInfo.outputPath('roster-'+width+'-'+theme+'.png'),fullPage:true});
    }
  }
});

`+responsive.slice(last);
fs.writeFileSync(responsiveFile,responsive);

const cssFile='web/admin/css/dtr-scheduling.css';
let css=fs.readFileSync(cssFile,'utf8');
css='/* Guard roster and DTR schedule history. */\n'+css.slice(css.indexOf('.schedule-list-filters {'));
css=css.replace(/^\.schedule-duty-editor input:disabled.*\n/m,'');
css=css.replace(/^    \.schedule-period-row.*\n/gm,'');
fs.writeFileSync(cssFile,css);
