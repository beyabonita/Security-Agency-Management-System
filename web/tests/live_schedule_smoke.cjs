// Optional read-only deployed smoke test. Supply QA_HR_USERNAME and
// QA_HR_PASSWORD in the process environment; never store them in this file.
const { chromium } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const username = process.env.QA_HR_USERNAME;
  const password = process.env.QA_HR_PASSWORD;
  if (!username || !password) throw new Error('QA_HR_USERNAME and QA_HR_PASSWORD are required.');
  const base = process.env.QA_PORTAL_URL || 'https://security-agency-management-system-nu.vercel.app';
  const output = path.resolve(__dirname, '../../build/qa/schedule-fix');
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  try {
    await page.goto(`${base}/staff/login.html`);
    await page.locator('#username').fill(username);
    await page.locator('#password').fill(password);
    await page.locator('#loginBtn').click();
    await page.waitForURL('**/admin/dashboard.html', { timeout: 30000 });
    await page.goto(`${base}/admin/schedule.html`);
    await page.waitForFunction(() => window.appSupabase && typeof refreshSchedules === 'function');
    await page.locator('#loadingScreen').waitFor({ state: 'hidden' });
    await page.evaluate(() => refreshSchedules());
    const result = await page.evaluate(async () => {
      const { error } = await window.appSupabase.rpc('delete_unused_schedule', {
        // Nil UUID cannot match generated schedule IDs. No real row is targeted.
        p_schedule_id: '00000000-0000-0000-0000-000000000000',
      });
      return {
        loadFailed: schedulesLoadFailed,
        simpleForm: !document.querySelector('#dutyDays') && !document.querySelector('#dtrScheduleMap')
          && document.querySelector('label[for="startTime"]')?.textContent === 'Start time'
          && document.querySelector('label[for="endTime"]')?.textContent === 'End time',
        rows: schedules.length,
        protectedRows: schedules.filter(schedule => scheduleHistoryState(schedule).reason).length,
        deleteButtons: document.querySelectorAll('#scheduleTable .btn-schedule-del').length,
        missingRecordCode: error?.code,
        missingRecordDetails: error?.details,
      };
    });
    assert.equal(result.loadFailed, false, 'Authenticated embedded history query must load');
    assert.equal(result.simpleForm, true, 'Live schedule form uses the simplified date and time controls');
    assert.equal(result.deleteButtons, result.rows - result.protectedRows);
    assert.equal(result.missingRecordCode, 'P0002', 'Safe RPC must reject a nonexistent schedule');
    assert.equal(result.missingRecordDetails, 'SCHEDULE_NOT_FOUND');
    assert.deepEqual(pageErrors, [], 'No browser script errors');
    await page.screenshot({ path: path.join(output, 'live-schedule-desktop.png'), fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: path.join(output, 'live-schedule-mobile.png'), fullPage: true });
    const widths = await page.evaluate(() => ({
      page: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth,
    }));
    assert.ok(widths.page <= widths.viewport + 1, 'No page-level horizontal overflow on mobile');
    console.log(JSON.stringify({ checkedAt: new Date().toISOString(), url: `${base}/admin/schedule.html`, ...result, pageErrors, result: 'PASS' }, null, 2));
  } finally {
    // End only this test session; do not invalidate the user's other devices.
    await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
