// Read-only diagnostic. Intercept configuration writes before exercising Save.
const { chromium, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../build/qa/platform-controls/diagnostic');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, colorScheme: 'dark' });
  const page = await context.newPage();
  const evidence = { startedAt: new Date().toISOString(), browserErrors: [], interceptedSaves: 0 };
  page.on('pageerror', error => evidence.browserErrors.push(error.message));
  await page.route('**/rest/v1/rpc/update_platform_settings', route => {
    evidence.interceptedSaves++;
    return route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ message: 'Diagnostic: save intercepted; no live settings changed.' }) });
  });
  try {
    if (!process.env.QA_IT_USERNAME || !process.env.QA_IT_PASSWORD) throw Error('IT test credentials required');
    await page.goto('https://security-agency-management-system-admin.vercel.app/system-access-7d92a4/login.html');
    await page.locator('#username').fill(process.env.QA_IT_USERNAME);
    await page.locator('#password').fill(process.env.QA_IT_PASSWORD);
    await page.locator('#login').click();
    await page.waitForURL('**/it-admin/dashboard.html', { timeout: 30000 });
    await page.goto('https://security-agency-management-system-admin.vercel.app/it-admin/clients.html');
    await expect(page.locator('#platformSettingsFeedback')).toContainText('Last saved');
    const readSettings = () => page.evaluate(async () => {
      const result = await appSupabase.from('platform_settings').select('support_email,default_geofence_radius,portal_announcement,portal_announcement_enabled,updated_at').eq('singleton', true).maybeSingle();
      if (result.error) throw Error(result.error.message);
      return result.data;
    });
    evidence.before = await readSettings();
    evidence.handlerTypes = await page.evaluate(() => ({
      globalHandler: typeof window.savePlatformSettings,
      formNamedProperty: typeof document.getElementById('platformSettingsForm').savePlatformSettings,
      formNamedPropertyTag: document.getElementById('platformSettingsForm').savePlatformSettings?.tagName,
    }));
    await page.locator('#platformSettingsForm').screenshot({ path: path.join(output, 'before-save.png'), animations: 'disabled' });
    await page.locator('#savePlatformSettings').click();
    await page.waitForTimeout(1200);
    evidence.feedback = await page.locator('#platformSettingsFeedback').innerText();
    evidence.after = await readSettings();
    expect(evidence.after).toEqual(evidence.before);
    await page.locator('#platformSettingsForm').screenshot({ path: path.join(output, 'after-save.png'), animations: 'disabled' });
    evidence.status = 'DIAGNOSTIC COMPLETE — live values unchanged';
  } catch (error) {
    evidence.status = 'DIAGNOSTIC ERROR';
    evidence.error = error.message;
    process.exitCode = 1;
  } finally {
    evidence.completedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
    await browser.close();
  }
})();
