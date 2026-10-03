const { expect, test } = require('@playwright/test');
const manifest = require('../assets/fonts/material-symbols-rounded.json');

const pages = [
  '/staff/login.html', '/system-access-7d92a4/login.html',
  '/admin/dashboard.html', '/admin/users.html', '/admin/locations.html', '/admin/schedule.html',
  '/admin/incidents.html', '/admin/swaps.html', '/inspector/dashboard.html', '/inspector/users.html',
  '/inspector/locations.html', '/inspector/incidents.html', '/inspector/swaps.html',
  '/it-admin/dashboard.html', '/it-admin/users.html', '/it-admin/clients.html',
];

async function isolatePresentation(page) {
  // Test presentation without signing in or modifying production records.
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `window.firebase = { auth: () => ({ onAuthStateChanged() {}, signOut: async () => {} }),
      firestore: () => ({ collection: () => ({}) }) };`,
  }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  // Icons must still work when external Google Fonts access is unavailable.
  await page.route('https://fonts.googleapis.com/**', route => route.abort());
  await page.route('https://fonts.gstatic.com/**', route => route.abort());
}

async function loadIcons(page) {
  const loaded = await page.evaluate(async () => {
    const faces = await document.fonts.load('500 24px "Material Symbols Rounded"');
    return faces.map(face => ({ family: face.family, status: face.status }));
  });
  expect(loaded.length).toBeGreaterThan(0);
  expect(loaded.every(face => face.status === 'loaded')).toBe(true);
}

for (const theme of ['light', 'dark']) {
  test(`Google icons render on all ${pages.length} pages in ${theme} mode without an external font service`, async ({ page }, info) => {
    test.setTimeout(120000);
    await isolatePresentation(page);
    await page.setViewportSize({ width: theme === 'dark' ? 390 : 1440, height: 1000 });
    await page.addInitScript(value => localStorage.setItem('sentinel-link-theme', value), theme);
    for (const route of pages) {
      await page.goto(route, { waitUntil: 'load' });
      await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
      await loadIcons(page);
      const icons = page.locator('.material-symbols-rounded');
      expect(await icons.count(), route).toBeGreaterThan(0);
      const invalid = await icons.evaluateAll(elements => elements.filter(element => {
        const style = getComputedStyle(element);
        return !style.fontFamily.includes('Material Symbols Rounded') || !element.closest('[aria-hidden="true"]');
      }).map(element => element.textContent.trim()));
      expect(invalid, route + ' decorative icons must be styled and hidden from screen readers').toEqual([]);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route).toBe(true);
      await page.screenshot({ path: info.outputPath(route.replaceAll('/', '_') + '-' + theme + '.png'), fullPage: true });
    }
  });
}

test('all bundled icon names form single glyphs, including filled emergency alerts', async ({ page }) => {
  await isolatePresentation(page);
  await page.goto('/staff/login.html');
  await loadIcons(page);
  const measurements = await page.evaluate(names => {
    const container = document.createElement('div');
    container.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.append(container);
    const results = [];
    for (const filled of [false, true]) {
      for (const name of names) {
        const icon = document.createElement('span');
        icon.className = 'material-symbols-rounded' + (filled ? ' sl-icon-filled' : '');
        icon.style.fontSize = '24px';
        icon.textContent = name;
        container.append(icon);
        // Measure the text itself, not the fixed icon container: this proves
        // every included ligature renders a glyph instead of a clipped word.
        const range = document.createRange();
        range.selectNodeContents(icon);
        results.push({ name, filled, width: range.getBoundingClientRect().width });
      }
    }
    container.remove();
    return results;
  }, manifest.icons);
  for (const result of measurements) {
    expect(result.width, JSON.stringify(result)).toBeGreaterThan(8);
    expect(result.width, JSON.stringify(result)).toBeLessThanOrEqual(24.2);
  }
});

test('unavailable or still-loading icon fonts cannot stretch mobile navigation', async ({ page }) => {
  await isolatePresentation(page);
  await page.route('**/material-symbols-rounded.woff2', route => route.abort());
  await page.setViewportSize({ width: 390, height: 844 });
  for (const route of ['/admin/dashboard.html', '/inspector/dashboard.html', '/it-admin/clients.html', '/staff/login.html']) {
    await page.goto(route);
    await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route).toBe(true);
    await expect(page.locator('[data-theme-toggle]').first()).toHaveAccessibleName(/Switch to (dark|light) mode/);
  }
});

test('dialog, toast and modal close icons stay centered and accessible in dark mode', async ({ page }, info) => {
  await isolatePresentation(page);
  await page.goto('/admin/users.html');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.evaluate(() => window.sentinelTheme.set('dark'));
  await loadIcons(page);
  await page.evaluate(() => {
    appDialog.toast('Saved successfully.', { tone: 'success', duration: 30000 });
    appDialog.confirm('Review this action.', { title: 'Confirm action', icon: 'help' });
  });
  for (const selector of ['.sl-dialog-icon', '.sl-toast-icon']) {
    await expect(page.locator(selector)).toHaveCSS('display', 'grid');
    await expect(page.locator(selector)).toHaveCSS('place-items', 'center');
  }
  await expect(page.getByRole('button', { name: 'Close', exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath('google-dialog-toast-dark.png') });
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await page.evaluate(() => bootstrap.Modal.getOrCreateInstance(document.querySelector('#createGuardModal')).show());
  const close = page.locator('#createGuardModal .btn-close');
  await expect(close).toHaveCSS('filter', 'none');
  await expect(close).toHaveAccessibleName('Close');
  await page.screenshot({ path: info.outputPath('google-modal-close-dark.png') });
  await close.click();
  await expect(page.locator('#createGuardModal')).not.toBeVisible();
});
