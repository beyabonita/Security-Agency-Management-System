// Verify existing, already-read notices only; no production records are changed.
const { chromium, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../build/qa/notification-view/live');
const base = 'https://security-agency-management-system-nu.vercel.app';

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, colorScheme: 'dark' });
  const page = await context.newPage();
  const errors = [];
  const blockedWrites = [];
  const results = { startedAt: new Date().toISOString(), status: 'RUNNING' };
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/rest/v1/rpc/*', route => {
    const rpc = new URL(route.request().url()).pathname.split('/').pop();
    if (['mark_notification_read', 'acknowledge_notification', 'mark_all_notifications_read', 'send_broadcast_notification'].includes(rpc)) {
      blockedWrites.push(rpc);
      return route.abort();
    }
    return route.continue();
  });
  try {
    if (!process.env.QA_INSPECTOR_USERNAME || !process.env.QA_INSPECTOR_PASSWORD) throw Error('QA Inspector credentials required');
    await page.goto(base + '/staff/login.html', { waitUntil: 'load' });
    await page.locator('#username').fill(process.env.QA_INSPECTOR_USERNAME);
    await page.locator('#password').fill(process.env.QA_INSPECTOR_PASSWORD);
    await page.locator('#loginBtn').click();
    await page.waitForURL('**/inspector/dashboard.html', { timeout: 30000 });
    await page.locator('.sl-notification-bell').click();
    const notices = page.locator('.sl-notification-item[data-read="true"]').filter({
      has: page.locator('.sl-notification-item-icon', { hasText: /^campaign$/ }),
    });
    await expect(notices.first()).toBeVisible();
    const count = Math.min(await notices.count(), 2);
    const originalUrl = page.url();
    for (let index = 0; index < count; index++) {
      if (index === 1) await page.setViewportSize({ width: 390, height: 844 });
      const notice = notices.nth(index);
      const title = await notice.locator('.sl-notification-item-title').innerText();
      const message = await notice.locator('.sl-notification-item-message').innerText();
      await notice.getByRole('button', { name: 'View', exact: true }).click();
      const dialog = page.getByRole('dialog');
      await expect(dialog).toBeVisible();
      await expect(dialog.locator('.sl-dialog-title')).toHaveText(title);
      await expect(dialog.locator('.sl-notification-detail-message')).toHaveText(message);
      await expect(dialog.locator('.sl-notification-detail-status')).toHaveText('Read');
      await expect(page.locator('.sl-notification-drawer')).toBeHidden();
      await expect(dialog.getByRole('button', { name: /Open/ })).toHaveCount(0);
      await expect(dialog).toHaveCSS('opacity', '1');
      await expect(page.locator('.sl-dialog-backdrop')).toHaveCSS('opacity', '1');
      await page.screenshot({ path: path.join(output, `notification-view-${index === 0 ? 'desktop' : 'mobile'}.png`), animations: 'disabled' });
      await dialog.getByRole('button', { name: 'Done', exact: true }).click();
      await expect(page.locator('.sl-notification-drawer')).toBeVisible();
      await expect(page).toHaveURL(originalUrl);
    }
    expect(blockedWrites).toEqual([]);
    expect(errors).toEqual([]);
    results.status = 'PASS';
    results.noticesViewed = count;
  } catch (error) {
    results.status = 'FAIL';
    results.error = error.message;
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    process.exitCode = 1;
  } finally {
    results.completedAt = new Date().toISOString();
    results.browserErrors = errors;
    results.blockedWrites = blockedWrites;
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    console.log(JSON.stringify(results, null, 2));
    await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
    await browser.close();
  }
})();
