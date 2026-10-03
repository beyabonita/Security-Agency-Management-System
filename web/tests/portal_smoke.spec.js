const { expect, test } = require('@playwright/test');
const {apkUrl,apkFileName,qrSource}=require('./release_fixture.cjs');

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

  await expect(page).toHaveTitle(/Twenty-Twenty Security Agency — Staff Sign In/i);
  await expect(page.getByRole('heading', { name: 'Twenty-Twenty Security Agency' })).toBeVisible();
  await expect(page.locator('.brand-intro')).toHaveText('Security Agency Management System');
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

test('local legacy login paths redirect to the correct access pages', async ({ page }) => {
  await page.goto('/admin/login.html', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveURL(/\/staff\/login\.html$/);

  await page.goto('/inspector/login.html', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveURL(/\/staff\/login\.html$/);

  await page.goto('/it-admin/login.html', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveURL(/\/system-access-7d92a4\/login\.html$/);
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

test('portal colour mode is available before sign-in and persists between access pages', async ({ page }) => {
  await page.goto('/staff/login.html');
  await expect.poll(() => page.evaluate(() => typeof window.sentinelTheme?.set)).toBe('function');

  await page.evaluate(() => window.sentinelTheme.set('light'));
  const toggle = page.locator('[data-theme-toggle]');
  await expect(toggle).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await toggle.click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

  await page.goto('/system-access-7d92a4/login.html');
  await expect.poll(() => page.evaluate(() => window.sentinelTheme?.get())).toBe('dark');
  await expect(page.locator('[data-theme-toggle]')).toBeVisible();
});

test('login pages use the agency-office background and keep dark fields legible', async ({ page, request }) => {
  const imageResponse = await request.get('/assets/twentytwenty-agency-office.jpg');
  expect(imageResponse.ok()).toBeTruthy();
  expect(imageResponse.headers()['content-type']).toContain('image/jpeg');

  await page.goto('/staff/login.html');
  await page.evaluate(() => window.sentinelTheme.set('dark'));
  // Inputs animate between theme surfaces. Poll the settled state rather than
  // sampling a first animation frame on a slower browser.
  await expect.poll(() => page.evaluate(
    () => getComputedStyle(document.querySelector('#username')).backgroundColor,
  )).not.toBe('rgb(255, 255, 255)');
  const staffStyles = await page.evaluate(() => {
    const background = getComputedStyle(document.querySelector('.access-background'));
    const panel = getComputedStyle(document.querySelector('.login-panel'));
    const input = getComputedStyle(document.querySelector('#username'));
    return {
      backgroundImage: background.backgroundImage,
      panelBackground: panel.backgroundColor,
      inputBackground: input.backgroundColor,
      inputColor: input.color,
    };
  });
  expect(staffStyles.backgroundImage).toContain('twentytwenty-agency-office.jpg');
  expect(staffStyles.panelBackground).not.toBe('rgb(255, 253, 253)');
  expect(staffStyles.inputBackground).not.toBe('rgb(255, 255, 255)');
  expect(staffStyles.inputColor).toBe('rgb(255, 244, 245)');

  await page.goto('/system-access-7d92a4/login.html');
  await expect.poll(() => page.evaluate(
    () => getComputedStyle(document.querySelector('#username')).backgroundColor,
  )).not.toBe('rgb(250, 245, 245)');
  const itStyles = await page.evaluate(() => {
    const pageSurface = getComputedStyle(document.querySelector('.ax-login-wrap'));
    const brandSurface = getComputedStyle(document.querySelector('.system-login-brand'));
    const input = getComputedStyle(document.querySelector('#username'));
    return {
      backgroundImage: pageSurface.backgroundImage,
      brandBackgroundImage: brandSurface.backgroundImage,
      inputBackground: input.backgroundColor,
      inputColor: input.color,
    };
  });
  expect(itStyles.backgroundImage).toContain('twentytwenty-agency-office.jpg');
  expect(itStyles.brandBackgroundImage).toContain('twentytwenty-agency-office.jpg');
  expect(itStyles.inputBackground).not.toBe('rgb(250, 245, 245)');
  expect(itStyles.inputColor).toBe('rgb(248, 236, 238)');
});

test('staff sign-in offers a setup modal and a direct APK QR code', async ({ page, request }) => {
  await page.goto('/staff/login.html');

  const qr = page.getByRole('img', { name: 'Scan to download the Android Guard app APK directly' });
  await expect(qr).toBeVisible();
  await expect(qr).toHaveAttribute('src', qrSource);
  await expect(page.locator('.qr-frame')).toHaveAttribute('href', apkUrl);

  const setup = page.getByRole('link', { name: 'Open mobile setup' });
  await expect(setup).toHaveAttribute('href', './app-download.html');
  await expect(page.getByRole('link', { name: 'Get app' })).toHaveAttribute('href', './app-download.html');
  await setup.click();
  await expect(page.getByRole('dialog', { name: 'Install the Guard app', exact: true })).toBeVisible();
  await expect(page).toHaveURL(/\/staff\/login\.html$/);

  const qrResponse = await request.get('/staff/guard-app-qr.png');
  expect(qrResponse.ok()).toBeTruthy();
  expect(qrResponse.headers()['content-type']).toContain('image/png');
});

test('old mobile setup URL opens the Android modal on staff sign-in', async ({ page }) => {
  await page.goto('/staff/app-download.html');

  await expect(page).toHaveURL(/\/staff\/login\.html#guard-app-setup$/);
  await expect(page.getByRole('heading', { name: 'Install the Guard app' })).toBeVisible();
  const androidDownload = page.getByRole('link', { name: 'Download for Android' });
  await expect(androidDownload).toHaveAttribute(
    'href',
    apkUrl,
  );
  await expect(androidDownload).toHaveAttribute('download', apkFileName);
  await expect(page.locator('body')).not.toContainText(/iOS|iPhone|iPad|TestFlight/);
});

test('mobile setup blocks the APK on unsupported phones', async ({ browser }) => {
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  await page.goto('/staff/app-download.html');

  await expect(page.locator('.sl-guard-app')).toHaveAttribute('data-platform', 'unsupported');
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

  await expect(page.locator('.sl-guard-app')).toHaveAttribute('data-platform', 'android');
  await expect(page.locator('#deviceMessage')).toContainText('Android detected');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  await context.close();
});

test('IT Admin access page renders separately', async ({ page }) => {
  const errors = collectFatalClientErrors(page);
  await page.goto('/system-access-7d92a4/login.html');

  await expect(page).toHaveTitle(/Twenty-Twenty Security Agency — System Access/i);
  await expect(page.getByRole('heading', { name: 'Security Agency Management System' })).toBeVisible();
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
  await expect(button).toHaveAccessibleName('Sign in');
  await expect(button.locator('.material-symbols-rounded')).toHaveText('arrow_forward');

  await page.evaluate(() => window.appDialog.toast('Guard account created.', { tone: 'success' }));
  await expect(page.locator('.sl-toast[data-tone="success"]')).toContainText('Guard account created.');
});
