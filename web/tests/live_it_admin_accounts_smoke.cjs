const { chromium, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');

const baseUrl = 'https://security-agency-management-system-admin.vercel.app';
const output = path.resolve(__dirname, '../../build/qa/it-admin-accounts/live');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const evidence = { startedAt: new Date().toISOString(), browserErrors: [] };
  page.on('pageerror', (error) => evidence.browserErrors.push(error.message));

  try {
    const username = process.env.QA_IT_USERNAME;
    const password = process.env.QA_IT_PASSWORD;
    if (!username || !password) throw new Error('IT test credentials required');

    await page.goto(`${baseUrl}/system-access-7d92a4/login.html`);
    await page.locator('#username').fill(username);
    await page.locator('#password').fill(password);
    await page.locator('#login').click();
    await page.waitForURL('**/it-admin/dashboard.html', { timeout: 30000 });
    await page.goto(`${baseUrl}/it-admin/users.html`);

    const row = page.locator('#rows tr').filter({ hasText: username.toLowerCase() });
    await expect(row).toHaveCount(1);
    await expect(row.getByText('Current account', { exact: true })).toBeVisible();
    await expect(row.getByRole('button', { name: 'Edit', exact: true })).toHaveCount(0);
    await expect(row.getByRole('button', { name: /Disable|Enable/ })).toHaveCount(0);
    await expect(page.getByText('Reset device', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('columnheader', { name: 'Device', exact: true })).toHaveCount(0);
    await expect.poll(() => page.evaluate(() => typeof window.edgeFunctionErrors?.unwrap)).toBe('function');
    expect(evidence.browserErrors).toEqual([]);

    await page.locator('.it-card').filter({ hasText: 'Privileged accounts' }).screenshot({
      path: path.join(output, 'current-account-protected.png'),
      animations: 'disabled',
    });
    evidence.status = 'PASS';
    evidence.currentAccountProtected = true;
    evidence.resetDeviceRemoved = true;
    evidence.deviceColumnRemoved = true;
  } catch (error) {
    evidence.status = 'FAIL';
    evidence.error = error.message;
    await page.screenshot({ path: path.join(output, 'failure.png'), animations: 'disabled' }).catch(() => {});
    process.exitCode = 1;
  } finally {
    evidence.completedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    await page.evaluate(async () => window.appSupabase?.auth.signOut({ scope: 'local' })).catch(() => {});
    await browser.close();
  }
})();
