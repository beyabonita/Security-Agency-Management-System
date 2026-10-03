const { expect, test } = require('@playwright/test');

const pages = [
  '/staff/login.html', '/system-access-7d92a4/login.html',
  '/admin/dashboard.html', '/admin/users.html', '/admin/locations.html',
  '/admin/schedule.html', '/admin/incidents.html', '/admin/swaps.html',
  '/inspector/dashboard.html', '/inspector/users.html', '/inspector/locations.html',
  '/inspector/incidents.html', '/inspector/swaps.html',
  '/it-admin/dashboard.html', '/it-admin/users.html', '/it-admin/clients.html',
];

// Presentation tests deliberately isolate live authentication/data; no production
// records are created, updated or removed. Existing integration tests cover data.
async function prepare(page) {
  await page.addInitScript(() => {
    if (!localStorage.getItem('sentinel-link-theme')) localStorage.setItem('sentinel-link-theme', 'dark');
  });
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `window.firebase = { auth: () => ({ onAuthStateChanged() {}, signOut: async () => {} }),
      firestore: () => ({ collection: () => ({}) }) };`,
  }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
}

async function appearance(locator) {
  return locator.evaluate(el => {
    const rgb = value => (value.match(/[\d.]+/g) || []).map(Number);
    const luminance = value => {
      const c = rgb(value).slice(0, 3).map(n => n / 255).map(n => n <= .04045 ? n / 12.92 : ((n + .055) / 1.055) ** 2.4);
      return .2126*c[0] + .7152*c[1] + .0722*c[2];
    };
    const style = getComputedStyle(el);
    let bg = el;
    while (bg.parentElement && (rgb(getComputedStyle(bg).backgroundColor)[3] ?? 1) < .8) bg = bg.parentElement;
    const background = getComputedStyle(bg).backgroundColor;
    const foreground = style.color;
    const a = luminance(foreground), b = luminance(background);
    return { background, foreground, luminance: b, contrast: (Math.max(a,b)+.05)/(Math.min(a,b)+.05) };
  });
}

for (const width of [1440, 390]) {
  test(`all role pages use readable dark surfaces at ${width}px`, async ({ page }, info) => {
    test.setTimeout(120000);
    await prepare(page);
    await page.setViewportSize({ width, height: width > 500 ? 1000 : 844 });
    for (const path of pages) {
      await page.goto(path, { waitUntil: 'networkidle' });
      await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
      await expect(page.locator('html'), path).toHaveAttribute('data-theme', 'dark');
      await expect(page.locator('[data-theme-toggle]').first(), path).toBeVisible();
      const selectors = [
        '.ax-panel', '.ix-panel', '.it-card', '.glass-card', '.form-panel',
        '.personnel-table-heading h2', '.it-card h2', '.ax-page-title', '.ix-page-title',
        '.form-control', '.form-select', '.it-settings-form input:not([type="checkbox"])',
        '.it-settings-form textarea', '.user-table th', '.it-table th',
        '.login-heading h2', '.system-login-card h2',
        '.download-hero p', '.download-brand small', '.build-seal span', '.build-seal strong',
        '.platform-copy p', '.platform-footnote', '.install-steps p', '.download-footer',
        '.login-heading > p',
      ];
      for (const selector of selectors) {
        for (const item of await page.locator(selector).all()) {
          if (!await item.isVisible()) continue;
          const colors = await appearance(item);
          expect(colors.luminance, path + ' ' + selector + ' dark background').toBeLessThan(.15);
          expect(colors.contrast, path + ' ' + selector + ' readable foreground').toBeGreaterThanOrEqual(4.5);
        }
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth), path + ' horizontal overflow')
        .toBeLessThanOrEqual(width + 1);
      await page.screenshot({ path: info.outputPath(path.replaceAll('/', '_') + '-dark.png'), fullPage: true });
    }
  });
}

test('dark mode survives navigation and switches back to light without stale colours', async ({ page }) => {
  await prepare(page);
  await page.goto('/admin/schedule.html');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.getByRole('button', { name: 'Switch to light mode', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  for (const card of await page.locator('.schedule-form-card').all()) {
    expect((await appearance(card)).luminance).toBeGreaterThan(.8);
  }
  await page.goto('/it-admin/clients.html');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  expect((await appearance(page.locator('.it-card').first())).luminance).toBeGreaterThan(.8);
  await page.getByRole('button', { name: 'Switch to dark mode', exact: true }).click();
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  expect((await appearance(page.locator('.it-card').first())).luminance).toBeLessThan(.15);
  expect(await page.evaluate(() => localStorage.getItem('sentinel-link-theme'))).toBe('dark');
});

test('HR create-account modal, read-only fields, and custom confirmations follow dark mode', async ({ page }, info) => {
  await prepare(page);
  await page.goto('/admin/users.html');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.evaluate(() => bootstrap.Modal.getOrCreateInstance(document.querySelector('#createGuardModal')).show());
  const modal = page.locator('#createGuardModal');
  await expect(modal).toBeVisible();
  for (const selector of ['.modal-content', '.modal-title', '.form-control', '.form-select']) {
    for (const item of await modal.locator(selector).all()) {
      if (!await item.isVisible()) continue;
      const colors = await appearance(item);
      expect(colors.luminance, selector).toBeLessThan(.15);
      expect(colors.contrast, selector).toBeGreaterThanOrEqual(4.5);
    }
  }
  await page.screenshot({ path: info.outputPath('hr-create-account-dark.png') });
  await page.evaluate(() => bootstrap.Modal.getInstance(document.querySelector('#createGuardModal')).hide());
  await expect(modal).not.toBeVisible();
  await page.evaluate(() => { appDialog.form({
    title: 'Edit personnel', message: 'Review the account details.',
    fields: [{ name: 'name', label: 'Name', value: 'QA preview' }]
  }); });
  const dialog = page.locator('.sl-dialog');
  await expect(dialog).toBeVisible();
  for (const selector of ['.sl-dialog-title', '.sl-dialog-field label', 'input', '.sl-dialog-btn:not(.sl-dialog-btn-primary)']) {
    const colors = await appearance(dialog.locator(selector).first());
    expect(colors.luminance).toBeLessThan(.15);
    expect(colors.contrast).toBeGreaterThanOrEqual(4.5);
  }
  await page.screenshot({ path: info.outputPath('hr-edit-dialog-dark.png') });
  await page.keyboard.press('Escape');
});

test('toasts and form feedback preserve legible semantic colours', async ({ page }, info) => {
  await prepare(page);
  await page.goto('/it-admin/clients.html');
  await page.evaluate(() => {
    appDialog.toast('Configuration could not be saved.', { tone: 'danger', duration: 30000 });
    appDialog.toast('Configuration saved.', { tone: 'success', duration: 30000 });
  });
  await expect(page.locator('.sl-toast')).toHaveCount(2);
  for (const toast of await page.locator('.sl-toast').all()) {
    const colors = await appearance(toast);
    expect(colors.luminance).toBeLessThan(.15);
    expect(colors.contrast).toBeGreaterThanOrEqual(4.5);
    expect((await appearance(toast.locator('.sl-toast-icon'))).contrast).toBeGreaterThanOrEqual(4.5);
  }
  await page.screenshot({ path: info.outputPath('it-admin-feedback-dark.png'), fullPage: true });
});

test('personnel rows, hover menus and status badges follow the active theme', async ({ page }, info) => {
  await prepare(page);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('/admin/users.html');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.evaluate(() => {
    document.querySelector('#guardTableBody').innerHTML = renderGuardRow('qa-guard', {
      firstName: 'QA', lastName: 'Guard', username: 'qa.guard', active: true, employmentCategory: 'regular'
    }, {});
    document.querySelector('#inspectorTableBody').innerHTML = renderInspectorRow('qa-inspector', {
      firstName: 'QA', lastName: 'Inspector', username: 'qa.inspector', active: false
    });
  });
  await page.locator('#guardTableBody .personnel-actions-trigger').hover();
  await expect(page.locator('#guardTableBody .personnel-actions-menu')).toBeVisible();
  for (const selector of ['.user-name', '.user-email', '.badge-active', '.badge-disabled', '.personnel-actions-trigger',
    '#guardTableBody .personnel-actions-menu .action-btn', '.btn-dtr']) {
    for (const item of await page.locator(selector).all()) {
      if (!await item.isVisible()) continue;
      expect((await appearance(item)).contrast, selector).toBeGreaterThanOrEqual(4.5);
    }
  }
  await page.screenshot({ path: info.outputPath('personnel-actions-dark.png'), fullPage: true });
});
