const { test, expect } = require('@playwright/test');
const { PNG } = require('pngjs');
const jsQR = require('jsqr');
const {apkUrl:APK}=require('./release_fixture.cjs');

test.beforeEach(async ({ page }) => {
  await page.route('**/*', route => new URL(route.request().url()).origin === 'http://127.0.0.1:4173'
    ? route.continue() : route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({ contentType: 'text/javascript', body: `
    window.firebase = { auth: () => ({ onAuthStateChanged() {}, signOut: async () => {} }), firestore: () => ({ collection: () => ({}) }) };
    window.appSupabase = { rpc: async () => ({ data: null, error: null }) };
  ` }));
});

for (const trigger of ['Open mobile setup', 'Get app']) {
  test(`${trigger} opens one modal without leaving or clearing login fields`, async ({ page }) => {
    await page.goto('/staff/login.html');
    await page.locator('#username').fill('draft-user');
    await page.locator('#password').fill('unsent-password');
    const link = page.getByRole('link', { name: trigger, exact: true });
    await link.click();
    const dialog = page.getByRole('dialog', { name: 'Install the Guard app', exact: true });
    await expect(dialog).toBeVisible();
    await expect(page).toHaveURL(/\/staff\/login\.html$/);
    await expect(dialog.locator('#androidDownload')).toHaveAttribute('href', APK);
    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect(link).toBeFocused();
    await expect(page.locator('#username')).toHaveValue('draft-user');
    await expect(page.locator('#password')).toHaveValue('unsent-password');
    await link.press('Enter');
    await expect(dialog).toHaveCount(1);
    await dialog.getByRole('button', { name: 'Done', exact: true }).click();
    await expect(dialog).toHaveCount(0);
  });
}

test('legacy setup link opens the same modal and closing clears only the setup hash', async ({ page }) => {
  await page.goto('/staff/app-download.html');
  await expect(page).toHaveURL(/\/staff\/login\.html#guard-app-setup$/);
  const dialog = page.getByRole('dialog', { name: 'Install the Guard app', exact: true });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(page).toHaveURL(/\/staff\/login\.html$/);
  await page.getByRole('link', { name: 'Get app', exact: true }).click();
  await expect(dialog).toBeVisible();
});

test('rendered desktop QR decodes to the APK, not a setup page', async ({ page }, info) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('/staff/login.html');
  const screenshot = await page.locator('.qr-frame img').screenshot({ path: info.outputPath('rendered-qr.png'), animations: 'disabled' });
  const png = PNG.sync.read(screenshot);
  const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
  expect(decoded?.data).toBe(APK);
});

for (const entry of ['QR link', 'modal button']) {
  test(`${entry} starts a browser download directly (isolated file fixture)`, async ({ page }) => {
    let requests = 0;
    await page.route(APK, route => {
      requests++;
      return route.fulfill({ contentType: 'application/vnd.android.package-archive',
        headers: { 'Content-Disposition': 'attachment; filename="guard-download-fixture.apk"' },
        body: Buffer.from('DOWNLOAD TEST FIXTURE — not an installable app'),
      });
    });
    await page.goto('/staff/login.html');
    if (entry === 'modal button') await page.getByRole('link', { name: 'Get app', exact: true }).click();
    const downloadEvent = page.waitForEvent('download');
    await page.locator(entry === 'QR link' ? '.qr-frame' : '#androidDownload').click();
    const download = await downloadEvent;
    expect(await download.failure()).toBeNull();
    expect(download.url()).toBe(APK);
    expect(requests).toBe(1);
    await expect(page).toHaveURL(/\/staff\/login\.html$/);
    if (entry === 'QR link') await expect(page.getByRole('dialog')).toHaveCount(0);
    else await expect(page.locator('.sl-guard-download-status')).toContainText('Check your browser');
  });
}

for (const theme of ['light', 'dark']) {
  for (const width of [1440, 740, 390, 320]) {
    test(`setup modal is contained and keyboard usable at ${width}px in ${theme} mode`, async ({ page }, info) => {
      await page.setViewportSize({ width, height: 844 });
      await page.goto('/staff/login.html');
      await page.evaluate(theme => sentinelTheme.set(theme), theme);
      await page.getByRole('link', { name: 'Get app', exact: true }).click();
      const dialog = page.getByRole('dialog', { name: 'Install the Guard app', exact: true });
      await expect(dialog).toBeVisible();
      await dialog.locator('summary').press('Enter');
      await expect(dialog.locator('details')).toHaveAttribute('open', '');
      expect(await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
      const box = await dialog.boundingBox();
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(width);
      await dialog.getByRole('button', { name: 'Done', exact: true }).focus();
      await page.keyboard.press('Tab');
      await expect(dialog.getByRole('button', { name: 'Close', exact: true })).toBeFocused();
      await page.screenshot({ path: info.outputPath('guard-setup.png'), animations: 'disabled' });
    });
  }
}
