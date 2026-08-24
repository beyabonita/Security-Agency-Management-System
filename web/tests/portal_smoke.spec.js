const { expect, test } = require('@playwright/test');

function collectFatalClientErrors(page) {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  return errors;
}

test('staff sign-in renders and initializes the official Supabase client', async ({ page }) => {
  const errors = collectFatalClientErrors(page);
  await page.goto('/staff/login.html');

  await expect(page).toHaveTitle(/Sentinel Link — Staff Sign In/i);
  await expect(page.getByRole('heading', { name: 'Sentinel Link' })).toBeVisible();
  await expect(page.locator('#username')).toBeVisible();
  await expect(page.locator('#password')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible();
  await page.getByRole('button', { name: 'Show' }).click();
  await expect(page.locator('#password')).toHaveAttribute('type', 'text');
  await page.getByRole('button', { name: 'Hide' }).click();
  await expect(page.locator('#password')).toHaveAttribute('type', 'password');
  await expect.poll(() => page.evaluate(
    () => typeof window.appSupabase?.auth?.signInWithPassword,
  )).toBe('function');

  expect(errors.filter((message) => /could not load the official Supabase client|firebase is not defined/i.test(message))).toEqual([]);
});

test('staff sign-in remains contained on a phone viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/staff/login.html');

  const card = await page.locator('.login-panel').boundingBox();
  expect(card).not.toBeNull();
  expect(card.x).toBeGreaterThanOrEqual(0);
  expect(card.x + card.width).toBeLessThanOrEqual(390);
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible();
});

test('staff sign-in routes every phone through mobile app setup', async ({ page, request }) => {
  await page.goto('/staff/login.html');

  const qr = page.getByRole('img', { name: /QR code for opening Sentinel Link mobile app download options/i });
  await expect(qr).toBeVisible();
  await expect(qr).toHaveAttribute('src', './guard-app-qr.png');

  const setup = page.getByRole('link', { name: 'Open mobile setup' });
  await expect(setup).toHaveAttribute('href', './app-download.html');
  await expect(page.getByRole('link', { name: 'Get app' })).toHaveAttribute('href', './app-download.html');

  const qrResponse = await request.get('/staff/guard-app-qr.png');
  expect(qrResponse.ok()).toBeTruthy();
  expect(qrResponse.headers()['content-type']).toContain('image/png');
});

test('mobile setup offers the verified Android app only', async ({ page }) => {
  await page.goto('/staff/app-download.html');

  await expect(page).toHaveTitle(/Sentinel Link — Android Guard App/i);
  await expect(page.getByRole('heading', { name: 'Install Sentinel Link' })).toBeVisible();
  const androidDownload = page.getByRole('link', { name: 'Download for Android' });
  await expect(androidDownload).toHaveAttribute(
    'href',
    '../downloads/sentinel-link-guard.apk?v=1.0.1',
  );
  await expect(androidDownload).toHaveAttribute('download', 'Sentinel-Link-Guard-v1.0.1.apk');
  await expect(page.locator('body')).not.toContainText(/iOS|iPhone|iPad|TestFlight/);
});

test('mobile setup blocks the APK on unsupported phones', async ({ browser }) => {
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  await page.goto('/staff/app-download.html');

  await expect(page.locator('html')).toHaveAttribute('data-platform', 'unsupported');
  await expect(page.locator('#deviceMessage')).toContainText('supports Android devices only');
  await expect(page.locator('#androidDownload')).not.toHaveAttribute('href');
  await expect(page.locator('#androidDownload')).toHaveAttribute('aria-disabled', 'true');
  await expect(page.locator('body')).not.toContainText(/iOS|iPhone|iPad|TestFlight/);
  await context.close();
});

test('mobile setup stays contained on an Android phone', async ({ browser }) => {
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 Chrome/140.0.0.0 Mobile Safari/537.36',
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  await page.goto('/staff/app-download.html');

  await expect(page.locator('html')).toHaveAttribute('data-platform', 'android');
  await expect(page.locator('#androidCard')).toHaveClass(/is-detected/);
  await expect(page.locator('#deviceMessage')).toContainText('Android detected');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  await context.close();
});

test('IT Admin access page renders separately', async ({ page }) => {
  const errors = collectFatalClientErrors(page);
  await page.goto('/system-access-7d92a4/login.html');

  await expect(page).toHaveTitle(/Sentinel Link — System Access/i);
  await expect(page.getByRole('heading', { name: 'System Control' })).toBeVisible();
  await expect(page.getByRole('button', { name: /Continue to system control/i })).toBeVisible();
  await expect.poll(() => page.evaluate(
    () => typeof window.appSupabase?.auth?.signInWithPassword,
  )).toBe('function');

  expect(errors.filter((message) => /could not load the official Supabase client|firebase is not defined/i.test(message))).toEqual([]);
});

test('IT Admin access uses a compact card on a phone viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/system-access-7d92a4/login.html');

  await expect(page.locator('.system-login-brand')).toBeHidden();
  await expect(page.locator('.system-mobile-mark')).toBeVisible();
  const card = await page.locator('.system-login-card').boundingBox();
  expect(card).not.toBeNull();
  expect(card.x).toBeGreaterThanOrEqual(0);
  expect(card.x + card.width).toBeLessThanOrEqual(390);
});

test('IT Admin access keeps the compact brand mark through tablet widths', async ({ page }) => {
  await page.setViewportSize({ width: 820, height: 900 });
  await page.goto('/system-access-7d92a4/login.html');

  await expect(page.locator('.system-login-brand')).toBeHidden();
  await expect(page.locator('.system-mobile-mark')).toBeVisible();
  await expect(page.locator('.system-mobile-mark img')).toHaveAttribute(
    'src',
    '../icons/sentinel-link-mark.png',
  );
});

test('shared action buttons expose and restore an animated busy state', async ({ page }) => {
  await page.goto('/staff/login.html');
  await expect.poll(() => page.evaluate(() => typeof window.appDialog?.runBusy)).toBe('function');

  await page.evaluate(() => {
    window.appDialog.setBusy(document.getElementById('loginBtn'), true, {
      label: 'Creating account…',
    });
  });
  const button = page.locator('#loginBtn');
  await expect(button).toBeDisabled();
  await expect(button).toHaveAttribute('aria-busy', 'true');
  await expect(button).toHaveClass(/sl-button-busy/);
  await expect(button).toHaveText('Creating account…');
  await expect.poll(() => button.evaluate((element) =>
    getComputedStyle(element, '::before').animationName)).toContain('sl-spin');

  await page.evaluate(() => window.appDialog.setBusy(document.getElementById('loginBtn'), false));
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveAttribute('aria-busy', 'true');
  await expect(button).toHaveText('Sign in');

  await page.evaluate(() => window.appDialog.toast('Guard account created.', { tone: 'success' }));
  await expect(page.locator('.sl-toast[data-tone="success"]')).toContainText('Guard account created.');
});
