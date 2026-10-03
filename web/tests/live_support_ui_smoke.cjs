// Read-only public-page smoke: no login, configuration writes, or email delivery.
const { chromium, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../build/qa/support-ui/live');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const results = { startedAt: new Date().toISOString(), checks: [] };
  for (const [name, url] of [
    ['staff', 'https://security-agency-management-system-nu.vercel.app/staff/login.html'],
    ['it', 'https://security-agency-management-system-admin.vercel.app/system-access-7d92a4/login.html'],
  ]) {
    const context = await browser.newContext({ viewport: { width: 1366, height: 768 } });
    const page = await context.newPage();
    const result = { page: name, errors: [] };
    page.on('pageerror', error => result.errors.push(error.message));
    try {
      await page.goto(url);
      const trigger = page.locator('[data-platform-support] a');
      await expect(trigger).toBeVisible();
      const address = await trigger.getAttribute('data-support-email');
      expect(address).toBeTruthy();
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => sentinelTheme.set(theme), theme);
        const notice = page.locator('[data-platform-announcement]');
        if (await notice.count()) {
          await expect.poll(async () => {
            const a = await page.locator('[data-theme-toggle]').boundingBox();
            const b = await notice.boundingBox();
            return a.y + a.height <= b.y;
          }).toBe(true);
        }
        await page.screenshot({ path: path.join(output, `${name}-${theme}-login.png`), fullPage: true, animations: 'disabled' });
        await trigger.click();
        const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
        await expect(dialog).toBeVisible();
        await expect(dialog.getByLabel('Support email', { exact: true })).toHaveValue(address);
        await expect(dialog.getByRole('link', { name: 'Open email app' })).toHaveAttribute('href', 'mailto:' + encodeURIComponent(address).replace('%40', '@'));
        await page.screenshot({ path: path.join(output, `${name}-${theme}-support.png`), animations: 'disabled' });
        await page.keyboard.press('Escape');
        await expect(dialog).toHaveCount(0);
        await expect(trigger).toBeFocused();
        await expect(page).toHaveURL(url);
      }
      expect(result.errors).toEqual([]);
      result.status = 'PASS';
    } catch (error) {
      result.status = 'FAIL'; result.error = error.message; process.exitCode = 1;
      await page.screenshot({ path: path.join(output, `${name}-failure.png`) }).catch(() => {});
    }
    results.checks.push(result);
    await context.close();
  }
  results.completedAt = new Date().toISOString();
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
  console.log(JSON.stringify(results, null, 2));
  await browser.close();
})();
