const { expect, test } = require('@playwright/test');
const fs = require('node:fs/promises');
const path = require('node:path');

test('agency DTR downloads with the selected semi-monthly period', async ({ page }) => {
  await page.route('**/supabase-firebase-bridge.js', (route) => route.abort());
  page.on('pageerror', () => {});
  await page.goto('/admin/users.html', { waitUntil: 'domcontentloaded' });

  const downloadPromise = page.waitForEvent('download');
  await page.evaluate(async () => {
    const period = window.DtrReport.periodFromSelection('2026-09', 'first');
    await window.DtrReport.generatePdf({
      jsPDF: window.jspdf.jsPDF,
      period,
      account: { firstName: 'Pedro', middleInitial: 'D', lastName: 'Dela Cruz' },
      sessions: [
        {
          duty_date: '2026-09-03',
          scheduled_start_at: '2026-09-03T06:00:00+08:00',
          scheduled_end_at: '2026-09-03T18:00:00+08:00',
          clock_in_at: '2026-09-03T06:00:00+08:00',
          clock_out_at: '2026-09-03T19:00:00+08:00',
          timeout_verified_at:'2026-09-04T08:00:00+08:00',
          location_label: 'Main Detachment',
        },
        {
          duty_date: '2026-09-14',
          scheduled_start_at: '2026-09-14T22:00:00+08:00',
          scheduled_end_at: '2026-09-15T06:00:00+08:00',
          clock_in_at: '2026-09-14T22:00:00+08:00',
          clock_out_at: '2026-09-15T06:00:00+08:00',
          location_label: 'Main Detachment',
        },
        {
          duty_date: '2026-09-15', status:'missed_timeout',
          scheduled_start_at:'2026-09-15T14:00:00+08:00',
          scheduled_end_at:'2026-09-15T22:00:00+08:00',
          clock_in_at:'2026-09-15T14:03:00+08:00',
          location_label:'Main Detachment',
        },
      ],
      logoUrl: '../icons/sentinel-link-mark.png',
    });
  });
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe('DTR_Pedro_D_Dela_Cruz_2026-09-01_2026-09-15.pdf');

  const visualOutput = process.env.DTR_VISUAL_OUTPUT;
  const output = visualOutput || await download.path();
  if (visualOutput) {
    await fs.mkdir(path.dirname(visualOutput), { recursive: true });
    await download.saveAs(visualOutput);
  }
  const stat = await fs.stat(output);
  expect(stat.size).toBeGreaterThan(10_000);
});
