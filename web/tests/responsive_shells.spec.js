const { expect, test } = require('@playwright/test');

const protectedPages = [
  '/admin/dashboard.html',
  '/admin/users.html',
  '/admin/locations.html',
  '/admin/schedule.html',
  '/admin/incidents.html',
  '/admin/swaps.html',
  '/inspector/dashboard.html',
  '/inspector/users.html',
  '/inspector/locations.html',
  '/inspector/incidents.html',
  '/inspector/swaps.html',
  '/it-admin/dashboard.html',
  '/it-admin/users.html',
  '/it-admin/clients.html',
];

async function openProtectedLayout(page, path) {
  await page.goto(path, { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
}

test.beforeEach(async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.route('**/supabase-firebase-bridge.js', (route) => route.abort());
  page.on('pageerror', () => {});
});

test('all protected pages stay contained on a phone viewport', async ({ page }) => {
  for (const path of protectedPages) {
    await openProtectedLayout(page, path);
    const dimensions = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      page: document.documentElement.scrollWidth,
    }));
    expect(dimensions.page, `${path} should not create page-level horizontal scrolling`)
      .toBeLessThanOrEqual(dimensions.viewport + 1);
  }
});

test('HR navigation opens and closes as a mobile drawer', async ({ page }) => {
  await openProtectedLayout(page, '/admin/dashboard.html');
  const toggle = page.locator('#axMenuToggle');
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(page.locator('.ax-sidebar')).toHaveClass(/ax-open/);
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(page.locator('.ax-sidebar')).not.toHaveClass(/ax-open/);
});

test('Inspector navigation exposes a compact mobile menu', async ({ page }) => {
  await openProtectedLayout(page, '/inspector/dashboard.html');
  const toggle = page.locator('#ixMenuToggle');
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(page.locator('#ixTopnav')).toHaveClass(/ix-open/);
  await expect(page.locator('.ix-topnav-links')).toBeVisible();
});

test('Inspector portal has no personal attendance controls', async ({ page }) => {
  await openProtectedLayout(page, '/inspector/dashboard.html');
  await expect(page.locator('a[href="attendance.html"]')).toHaveCount(0);
  await expect(page.getByText('My Time In / Out', { exact: true })).toHaveCount(0);

  const removedPage = await page.goto('/inspector/attendance.html');
  expect(removedPage?.status()).toBe(404);
});

test('HR Personnel keeps DTR available for Guards only', async ({ page }) => {
  await openProtectedLayout(page, '/admin/users.html');

  await expect(page.locator('.ax-nav a[href="users.html"]')).toHaveText(/Personnel/);
  await expect(page.locator('[aria-labelledby="guardPersonnelHeading"] th').filter({ hasText: 'DTR' })).toHaveCount(1);
  await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] th').filter({ hasText: 'DTR' })).toHaveCount(0);
  await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] thead')).toContainText('Personnel');
  await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] thead')).toContainText('Device');
});

test('IT Admin navigation opens as a mobile drawer', async ({ page }) => {
  await openProtectedLayout(page, '/it-admin/clients.html');
  const toggle = page.locator('[data-it-nav-toggle]');
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(page.locator('#itSidebar')).toHaveClass(/ax-open/);
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
});

test('every staff role shell uses the shared agency mark', async ({ page }) => {
  for (const [path, selector] of [
    ['/admin/dashboard.html', '.ax-brand'],
    ['/inspector/dashboard.html', '.ix-shell-brand'],
    ['/it-admin/dashboard.html', '.ax-brand'],
  ]) {
    await openProtectedLayout(page, path);
    const background = await page.locator(selector).evaluate(
      (element) => getComputedStyle(element, '::before').backgroundImage,
    );
    expect(background, `${path} should render the shared agency mark`)
      .toContain('sentinel-link-mark.png');
  }
});

test('HR create-personnel modal keeps its actions visible on a phone', async ({ page }) => {
  await openProtectedLayout(page, '/admin/users.html');
  await page.locator('#createGuardModal').evaluate((modal) => {
    modal.style.display = 'block';
    modal.classList.add('show');
  });

  const modal = page.locator('#createGuardModal .modal-content');
  const footer = page.locator('#createGuardModal .modal-footer');
  await expect(modal).toBeVisible();
  await expect(footer).toBeVisible();
  const metrics = await footer.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return { top: bounds.top, bottom: bounds.bottom, viewport: window.innerHeight };
  });
  expect(metrics.top).toBeGreaterThanOrEqual(0);
  expect(metrics.bottom).toBeLessThanOrEqual(metrics.viewport + 1);
  await expect(page.locator('#createGuardBtn')).toHaveText('Create Guard');
});

test('an open personnel action menu stays above action triggers in later rows', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await openProtectedLayout(page, '/admin/users.html');
  await page.locator('#guardTableBody').evaluate((body) => {
    const row = (id) => `<tr>
      <td>Personnel ${id}</td><td>Regular</td><td>1</td><td>Active</td>
      <td>Site</td><td>Unassigned</td>
      <td><div class="personnel-actions">
        <button type="button" class="personnel-actions-trigger">Actions</button>
        <div class="personnel-actions-menu" id="personnel-actions-${id}">
          <button type="button" class="action-btn">Edit</button>
          <button type="button" class="action-btn">Disable</button>
          <button type="button" class="action-btn">Set Home Post</button>
          <button type="button" class="action-btn">History</button>
          <button type="button" class="action-btn">Set Inspector</button>
          <button type="button" class="action-btn">Reports</button>
        </div>
      </div></td><td>DTR</td><td>Device</td>
    </tr>`;
    body.innerHTML = row('first') + row('second');
  });

  const firstActions = page.locator('.personnel-actions').first();
  const firstMenu = page.locator('#personnel-actions-first');
  const secondTrigger = page.locator('.personnel-actions-trigger').nth(1);
  await firstActions.hover();
  await expect(firstMenu).toBeVisible();

  const secondTriggerBounds = await secondTrigger.boundingBox();
  expect(secondTriggerBounds).not.toBeNull();
  const topMenuId = await page.evaluate(({ x, y }) => {
    return document.elementFromPoint(x, y)?.closest('.personnel-actions-menu')?.id || null;
  }, {
    x: secondTriggerBounds.x + secondTriggerBounds.width / 2,
    y: secondTriggerBounds.y + secondTriggerBounds.height / 2,
  });
  expect(topMenuId).toBe('personnel-actions-first');
});

test('deployment-site search, location permission, and cached edit stay reliable', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.unroute('**/supabase-firebase-bridge.js');
  await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.firebase = {
        auth: () => ({ onAuthStateChanged: () => {}, signOut: async () => {} }),
        firestore: () => ({ collection: () => ({}) })
      };
      window.appSupabase = { rpc: async () => ({ data: 100, error: null }) };
      window.testToastMessages = [];
      window.appDialog = { toast: (message) => window.testToastMessages.push(message) };
    `,
  }));

  let requestedSearchUrl = null;
  await page.route('https://nominatim.openstreetmap.org/search?**', (route) => {
    requestedSearchUrl = new URL(route.request().url());
    return route.fulfill({
      contentType: 'application/json',
      json: [
        {
          name: 'Silay',
          display_name: 'Silay, Negros Occidental, Philippines',
          lat: '10.7994126',
          lon: '122.9756149',
          boundingbox: ['10.75', '10.85', '122.92', '123.03'],
          address: { city: 'Silay', country: 'Philippines', country_code: 'ph' },
        },
        {
          name: 'Foreign result',
          display_name: 'Foreign result, Japan',
          lat: '35.6762',
          lon: '139.6503',
          boundingbox: ['35.6', '35.7', '139.6', '139.7'],
          address: { country: 'Japan', country_code: 'jp' },
        },
      ],
    });
  });

  await page.goto('/admin/locations.html', { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.waitForFunction(() => window.L && typeof window.initMap === 'function');
  await page.locator('#locationForm').evaluate((form) => { form.style.display = 'block'; });
  await page.evaluate(() => window.initMap());
  await expect(page.locator('.sl-location-marker')).toHaveCount(0);

  await page.locator('#addressSearch').fill('Silay');
  await page.locator('#addressSearchButton').click();
  await expect(page.locator('.address-suggestion')).toHaveCount(1);
  await expect(page.locator('.address-suggestion')).toContainText('Silay');

  expect(requestedSearchUrl).not.toBeNull();
  expect(requestedSearchUrl.searchParams.get('countrycodes')).toBe('ph');
  expect(requestedSearchUrl.searchParams.get('bounded')).toBe('1');
  expect(requestedSearchUrl.searchParams.get('viewbox')).toBe('116.4,21.3,127.0,4.2');

  await page.locator('.address-suggestion').click();
  await expect(page.locator('#selectedAddressDisplay')).toContainText('Silay');
  await expect(page.locator('.sl-location-marker')).toHaveCount(1);
  await expect(page.locator('#lat')).toHaveValue('10.7994126');
  await expect(page.locator('#lng')).toHaveValue('122.9756149');

  await page.evaluate(() => {
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (_success, failure) => { window.rejectTestGeolocation = failure; },
      },
    });
  });
  await page.locator('#useCurrentLocationButton').click();
  await page.evaluate(() => window.rejectTestGeolocation({ code: 1 }));
  await expect(page.locator('#addressSearchStatus')).toContainText('selected address was kept');
  await expect(page.locator('#address')).toHaveValue('Silay, Negros Occidental, Philippines');
  expect(await page.evaluate(() => window.testToastMessages)).toEqual([]);

  await page.locator('#useCurrentLocationButton').click();
  await page.evaluate(() => {
    const rejectStaleRequest = window.rejectTestGeolocation;
    window.cancelCurrentLocationRequest();
    window.setAddressSearchStatus('');
    rejectStaleRequest({ code: 1 });
  });
  await expect(page.locator('#addressSearchStatus')).toHaveText('');
  expect(await page.evaluate(() => window.testToastMessages)).toEqual([]);

  await page.evaluate(async () => {
    locationRecords.set('cached-site', {
      label: 'Jollibee Silay',
      address: 'Silay, Negros Occidental, Philippines',
      latitude: 10.7994126,
      longitude: 122.9756149,
      radius: 120,
      active: true,
    });
    await editLocation('cached-site', document.createElement('button'));
  });
  await expect(page.locator('#editId')).toHaveValue('cached-site');
  await expect(page.locator('#label')).toHaveValue('Jollibee Silay');
  await expect(page.locator('#radius')).toHaveValue('120');
});
