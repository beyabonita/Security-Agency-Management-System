// Public UI and download verification only. Does not sign in or install the APK.
const { chromium, expect } = require('@playwright/test');
const { PNG } = require('pngjs');
const jsQR = require('jsqr');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const output = path.resolve(__dirname, '../../build/qa/guard-app-modal/live');
const loginUrl = 'https://security-agency-management-system-nu.vercel.app/staff/login.html';
const expectedApk = path.resolve(__dirname, '../downloads/security-agency-management-system-guard.apk');
async function hash(file) {
  const digest = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) digest.update(chunk);
  return digest.digest('hex');
}

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
  const page = await context.newPage();
  const results = { startedAt: new Date().toISOString(), errors: [] };
  page.on('pageerror', error => results.errors.push(error.message));
  try {
    await page.goto(loginUrl);
    const qr = page.locator('.qr-frame');
    const target = await qr.getAttribute('href');
    const qrImage = PNG.sync.read(await page.locator('.qr-frame img').screenshot({ path: path.join(output, 'rendered-qr.png'), animations: 'disabled' }));
    expect(jsQR(new Uint8ClampedArray(qrImage.data), qrImage.width, qrImage.height)?.data).toBe(target);
    for (const [trigger, theme] of [['Open mobile setup', 'light'], ['Get app', 'dark']]) {
      await page.evaluate(theme => sentinelTheme.set(theme), theme);
      const link = page.getByRole('link', { name: trigger, exact: true });
      await link.click();
      const dialog = page.getByRole('dialog', { name: 'Install the Guard app', exact: true });
      await expect(dialog).toBeVisible();
      await expect(dialog.locator('#androidDownload')).toHaveAttribute('href', target);
      await expect(page).toHaveURL(loginUrl);
      await page.screenshot({ path: path.join(output, `modal-${theme}.png`), animations: 'disabled' });
      await page.keyboard.press('Escape');
      await expect(dialog).toHaveCount(0);
      await expect(link).toBeFocused();
    }
    const headers = await context.request.head(target);
    expect(headers.status()).toBe(200);
    expect(headers.headers()['content-disposition']).toContain('attachment;');
    expect(headers.headers()['content-type']).toContain('application/vnd.android.package-archive');
    const downloading = page.waitForEvent('download', { timeout: 30000 });
    await qr.click();
    const download = await downloading;
    let timer;
    const downloadResult = await Promise.race([
      download.failure().then(error => ({ error })),
      new Promise(resolve => { timer = setTimeout(() => resolve({ timeout: true }), 20000); }),
    ]);
    clearTimeout(timer);
    results.browserDownload = { url: download.url(), filename: download.suggestedFilename() };
    if (downloadResult.timeout) {
      await download.cancel();
      results.browserDownload.status = 'STARTED_BUT_NOT_COMPLETED';
      results.browserDownload.limitation = 'Automated Chromium did not finish the APK download within 20 seconds. No browser security settings were bypassed.';
    } else {
      expect(downloadResult.error).toBeNull();
      expect(await hash(await download.path())).toBe(await hash(expectedApk));
      results.browserDownload.status = 'PASS';
    }
    // Independently verify complete server bytes without installing/executing them.
    console.log('Verifying the full public APK response...');
    const response = await context.request.get(target, { timeout: 120000 });
    expect(response.status()).toBe(200);
    const bytes = await response.body();
    const checksum = crypto.createHash('sha256').update(bytes).digest('hex');
    expect(checksum).toBe(await hash(expectedApk));
    expect(bytes.length).toBe(fs.statSync(expectedApk).size);
    results.httpDownload = { status: 'PASS', bytes: bytes.length, sha256: checksum };
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await page.goto('https://security-agency-management-system-download.vercel.app/staff/app-download.html');
    await expect(page.getByRole('dialog', { name: 'Install the Guard app', exact: true })).toBeVisible();
    await expect(page).toHaveURL(/\/staff\/login\.html#guard-app-setup$/);
    expect(results.errors).toEqual([]);
    results.status = downloadResult.timeout ? 'PASS_WITH_DOWNLOAD_LIMITATION' : 'PASS';
  } catch (error) {
    results.status = 'FAIL'; results.error = error.message; process.exitCode = 1;
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
  } finally {
    results.completedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    console.log(JSON.stringify(results, null, 2));
    await browser.close();
  }
})();
