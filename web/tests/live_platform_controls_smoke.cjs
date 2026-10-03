// Exercise a real unchanged save. The RPC's no-op path preserves settings,
// timestamps, audit history and notifications. Block any changed payload.
const { chromium, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../build/qa/platform-controls/live');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, colorScheme: 'dark' });
  const page = await context.newPage();
  const evidence = { startedAt: new Date().toISOString(), browserErrors: [], saves: 0 };
  page.on('pageerror', error => evidence.browserErrors.push(error.message));
  let expectedPayload;
  await page.route('**/rest/v1/rpc/update_platform_settings', route => {
    const payload = route.request().postDataJSON();
    try { expect(payload).toEqual(expectedPayload); }
    catch (_) { evidence.blockedChangedPayload = true; return route.abort(); }
    evidence.saves++;
    return route.continue();
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
    const snapshot = () => page.evaluate(async () => {
      const [settings, audit] = await Promise.all([
        appSupabase.from('platform_settings').select('*').eq('singleton', true).maybeSingle(),
        appSupabase.from('platform_settings_audit').select('id', { count: 'exact', head: true }),
      ]);
      if (settings.error || audit.error) throw Error(settings.error?.message || audit.error.message);
      return { settings: settings.data, auditCount: audit.count };
    });
    const before = await snapshot();
    expectedPayload = {
      p_support_email: before.settings.support_email,
      p_default_geofence_radius: before.settings.default_geofence_radius,
      p_portal_announcement: before.settings.portal_announcement,
      p_portal_announcement_enabled: before.settings.portal_announcement_enabled,
    };
    await page.locator('#savePlatformSettings').click();
    await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
    await expect(page.locator('#savePlatformSettings')).toBeEnabled();
    await page.locator('#platformSettingsForm').screenshot({ path: path.join(output, 'configuration-save.png'), animations: 'disabled' });
    expect(await snapshot()).toEqual(before);
    await page.reload();
    await expect(page.locator('#platformSettingsFeedback')).toContainText('Last saved');
    expect(await snapshot()).toEqual(before);
    expect(evidence.saves).toBe(1);
    expect(evidence.browserErrors).toEqual([]);
    evidence.status = 'PASS';
    evidence.settingsUnchanged = true;
    evidence.auditUnchanged = true;
    evidence.savedTimestampPreserved = before.settings.updated_at;
  } catch (error) {
    evidence.status = 'FAIL';
    evidence.error = error.message;
    await page.screenshot({ path: path.join(output, 'failure.png'), animations: 'disabled' }).catch(() => {});
    process.exitCode = 1;
  } finally {
    evidence.completedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
    await browser.close();
  }
})();
