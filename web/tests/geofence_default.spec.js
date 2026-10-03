const { test, expect } = require('@playwright/test');

async function openLocations(page) {
  await page.route(/^https:\/\//, route => route.fulfill({ body: '' }));
  await page.route('**/platform-configuration.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/leaflet.js', route => route.fulfill({ contentType: 'text/javascript', body: `
    const bounds = { pad() { return this; }, contains: ([lat, lng]) => lat >= 4.2 && lat <= 21.3 && lng >= 116.4 && lng <= 127 };
    const layer = extra => Object.assign({ addTo() { return this; }, remove() {}, bringToBack() {}, getBounds: () => bounds }, extra);
    window.drawnRadii = [];
    window.L = {
      latLngBounds: () => bounds, divIcon: () => ({}),
      map: () => ({ fitBounds() {}, on() {}, invalidateSize() {}, flyTo() {}, getZoom: () => 17 }),
      tileLayer: () => layer(), control: { scale: () => layer() },
      marker: ([lat, lng]) => layer({ bindTooltip() {}, on() {}, getLatLng: () => ({ lat, lng }), setLatLng() {} }),
      circle: (center, options) => { window.drawnRadii.push(options.radius); return layer(); }
    };
  ` }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({ contentType: 'text/javascript', body: `
    window.radiusRequests = [];
    window.rpcCalls = [];
    window.locationWrites = [];
    window.applyAdminRoleNavigation = () => {};
    const site = { label: 'Existing site', address: 'Manila, Philippines', latitude: 14.6, longitude: 120.98, radius: 137, active: true };
    const siteDoc = { id: 'existing-site', exists: true, data: () => ({ ...site }) };
    window.appSupabase = { rpc: name => {
      window.rpcCalls.push(name);
      return new Promise((resolve, reject) => window.radiusRequests.push({ resolve, reject }));
    } };
    window.firebase = {
      auth: () => ({ onAuthStateChanged: callback => setTimeout(() => callback({ uid: 'hr' }), 0), signOut: async () => {} }),
      firestore: () => ({ collection: table => ({
        get: async () => ({ forEach: callback => callback(siteDoc) }),
        doc: () => ({
          get: async () => table === 'users'
            ? { exists: true, data: () => ({ role: 'admin', firstName: 'HR', lastName: 'Tester' }) }
            : siteDoc,
          update: async data => { window.locationWrites.push({ operation: 'update', data }); }
        }),
        add: async data => { window.locationWrites.push({ operation: 'add', data }); }
      }) })
    };
  ` }));
  await page.goto('/admin/locations.html');
  await expect(page.locator('#loadingScreen')).toBeHidden();
  await expect(page.locator('#locationTable')).toContainText('137 m');
}

async function resolveRadius(page, index, data) {
  await page.evaluate(({ index, data }) => window.radiusRequests[index].resolve({ data, error: null }), { index, data });
}

test('Add waits for the stored radius and reads it again on every opening', async ({ page }) => {
  await openLocations(page);
  expect(await page.evaluate(() => window.rpcCalls)).toEqual([]);
  await page.getByRole('button', { name: 'Add Deployment Site', exact: true }).click();
  await expect(page.locator('#radius')).toHaveValue('');
  await expect(page.locator('#radiusDefaultStatus')).toContainText('Loading the default radius');
  await page.locator('#label').fill('New site');
  await page.evaluate(() => setPin(14.6, 120.98, 'Manila, Philippines'));
  await page.getByRole('button', { name: 'Save Deployment Site', exact: true }).click();
  await expect(page.locator('#formError')).toContainText('Please enter a valid radius');
  expect(await page.evaluate(() => window.locationWrites)).toEqual([]);
  expect(await page.evaluate(() => window.drawnRadii)).toEqual([]);
  await resolveRadius(page, 0, 350);
  await expect(page.locator('#radius')).toHaveValue('350');
  expect(await page.evaluate(() => window.drawnRadii.at(-1))).toBe(350);
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('button', { name: 'Add Deployment Site', exact: true }).click();
  await expect(page.locator('#radius')).toHaveValue('');
  await resolveRadius(page, 1, 700);
  await expect(page.locator('#radius')).toHaveValue('700');
  expect(await page.evaluate(() => window.rpcCalls)).toEqual(['default_geofence_radius', 'default_geofence_radius']);
  expect(await page.evaluate(() => window.locationWrites)).toEqual([]);
});

test('a delayed default never overwrites a manually entered radius', async ({ page }) => {
  await openLocations(page);
  await page.getByRole('button', { name: 'Add Deployment Site', exact: true }).click();
  await page.locator('#radius').fill('275');
  await page.evaluate(() => setPin(14.6, 120.98, 'Manila, Philippines'));
  await resolveRadius(page, 0, 350);
  await expect(page.locator('#radiusDefaultStatus')).toContainText('Default for new sites: 350 m');
  await expect(page.locator('#radius')).toHaveValue('275');
  expect(await page.evaluate(() => window.drawnRadii.at(-1))).toBe(275);
  expect(await page.evaluate(() => window.locationWrites)).toEqual([]);
});

test('responses from an earlier Add cannot change a new form or an existing site', async ({ page }) => {
  await openLocations(page);
  const add = page.getByRole('button', { name: 'Add Deployment Site', exact: true });
  await add.click();
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await add.click();
  await resolveRadius(page, 1, 675);
  await resolveRadius(page, 0, 100);
  await expect(page.locator('#radius')).toHaveValue('675');
  await expect(page.locator('#radiusDefaultStatus')).toContainText('675 m');
  await add.click();
  await page.getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(page.locator('#formTitle')).toHaveText('Edit Deployment Site');
  await expect(page.locator('#radius')).toHaveValue('137');
  await resolveRadius(page, 2, 900);
  await expect(page.locator('#radius')).toHaveValue('137');
  await expect(page.locator('#radiusDefaultStatus')).toBeEmpty();
  expect(await page.evaluate(() => window.rpcCalls.length)).toBe(3);
  expect(await page.evaluate(() => window.locationWrites)).toEqual([]);
});

for (const failure of ['rpc error', 'invalid value', 'network failure']) {
  test(`${failure} shows feedback and reopening Add retries without a stale fallback`, async ({ page }) => {
    await openLocations(page);
    const add = page.getByRole('button', { name: 'Add Deployment Site', exact: true });
    await add.click();
    await resolveRadius(page, 0, 350);
    await expect(page.locator('#radius')).toHaveValue('350');
    await add.click();
    await page.evaluate(failure => {
      const request = window.radiusRequests[1];
      if (failure === 'network failure') request.reject(new Error('Network unavailable'));
      else request.resolve({ data: failure === 'invalid value' ? null : 350, error: failure === 'rpc error' ? { message: 'Denied' } : null });
    }, failure);
    await expect(page.locator('#radiusDefaultStatus')).toContainText('Could not load the default radius');
    await expect(page.locator('#radius')).toHaveValue('');
    await page.locator('#radius').fill('225');
    await expect(page.locator('#radius')).toHaveValue('225');
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await add.click();
    await resolveRadius(page, 2, 500);
    await expect(page.locator('#radius')).toHaveValue('500');
    expect(await page.evaluate(() => window.locationWrites)).toEqual([]);
  });
}
