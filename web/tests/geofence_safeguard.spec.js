const { test, expect } = require('@playwright/test');

async function openLocationsWithGuards(page, guards = []) {
  await page.route(/^https:\/\//, route => route.fulfill({ body: '' }));
  await page.route('**/platform-configuration.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/leaflet.js', route => route.fulfill({ contentType: 'text/javascript', body: `
    const bounds = { pad() { return this; }, contains: ([lat, lng]) => lat >= 4.2 && lat <= 21.3 && lng >= 116.4 && lng <= 127 };
    let markerDraggable = true;
    const layer = extra => Object.assign({
      addTo() { return this; },
      remove() {},
      bringToBack() {},
      getBounds: () => bounds
    }, extra);
    window.markerDraggingEnabled = true;
    window.L = {
      latLngBounds: () => bounds,
      divIcon: () => ({}),
      map: () => ({
        fitBounds() {},
        on(event, handler) { window.mapClickHandler = handler; },
        invalidateSize() {},
        flyTo() {},
        getZoom: () => 17
      }),
      tileLayer: () => layer(),
      control: { scale: () => layer() },
      marker: ([lat, lng], opts) => {
        window.markerDraggingEnabled = opts?.draggable !== false;
        return layer({
          bindTooltip() {},
          on() {},
          getLatLng: () => ({ lat, lng }),
          setLatLng() {},
          dragging: {
            enable: () => { window.markerDraggingEnabled = true; },
            disable: () => { window.markerDraggingEnabled = false; }
          }
        });
      },
      circle: () => layer()
    };
  ` }));

  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({ contentType: 'text/javascript', body: `
    window.locationUpdates = [];
    window.applyAdminRoleNavigation = () => {};
    const site = { label: 'Secured Facility', address: 'Makati, Metro Manila', latitude: 14.55, longitude: 121.02, radius: 150, active: true };
    const siteDoc = { id: 'secured-facility-id', exists: true, data: () => ({ ...site }) };
    const guardDocs = ${JSON.stringify(guards)}.map((g, idx) => ({
      id: g.id || ('guard-' + idx),
      exists: true,
      data: () => ({ role: 'user', ...g })
    }));

    window.appSupabase = { rpc: async () => ({ data: 100, error: null }) };
    window.firebase = {
      auth: () => ({ onAuthStateChanged: callback => setTimeout(() => callback({ uid: 'admin-user' }), 0), signOut: async () => {} }),
      firestore: () => ({ collection: table => ({
        get: async () => ({
          forEach: callback => {
            if (table === 'locations') callback(siteDoc);
            else if (table === 'users') {
              callback({ id: 'admin-user', exists: true, data: () => ({ role: 'admin', firstName: 'Admin', lastName: 'Ops' }) });
              guardDocs.forEach(g => callback(g));
            }
          }
        }),
        doc: id => ({
          get: async () => table === 'users'
            ? { exists: true, data: () => ({ role: 'admin', firstName: 'Admin', lastName: 'Ops' }) }
            : siteDoc,
          update: async data => { window.locationUpdates.push({ id, data }); }
        }),
        add: async data => { window.locationUpdates.push({ id: 'new', data }); }
      }) })
    };
  ` }));

  await page.goto('/admin/locations.html');
  await expect(page.locator('#loadingScreen')).toBeHidden();
}

test('locks geofence coordinates and radius with alert banner when guards are deployed', async ({ page }) => {
  await openLocationsWithGuards(page, [
    { firstName: 'Juan', lastName: 'Dela Cruz', assignedLocationId: 'secured-facility-id', active: true },
    { firstName: 'Pedro', lastName: 'Santos', assignedLocationId: 'secured-facility-id', active: true }
  ]);

  // Check table displays locked deployed badge
  const table = page.locator('#locationTable');
  await expect(table).toContainText('2 Deployed');

  // Click Edit
  await page.getByRole('button', { name: 'Edit', exact: true }).click();

  // Safeguard banner must appear with guard chips and warning
  const banner = page.locator('#geofenceSafeguardBanner');
  await expect(banner).toBeVisible();
  await expect(banner).toContainText('Geofence Safeguard: Editing Locked');
  await expect(banner).toContainText('2 deployed security guards');
  await expect(banner).toContainText('Juan Dela Cruz');
  await expect(banner).toContainText('Pedro Santos');
  await expect(banner).toContainText('View Deployed Guards');
  await expect(banner).toContainText('Reassign in Personnel');

  // Radius and address inputs must be disabled/locked
  await expect(page.locator('#radius')).toBeDisabled();
  await expect(page.locator('#addressSearch')).toBeDisabled();
  await expect(page.locator('#addressSearchButton')).toBeDisabled();

  // Marker dragging must be disabled
  expect(await page.evaluate(() => window.markerDraggingEnabled)).toBe(false);

  // Changing the deployment site label and saving updates ONLY the label
  await page.locator('#label').fill('Secured Facility - Updated Title');
  await page.getByRole('button', { name: 'Save Deployment Site', exact: true }).click();

  // Verify that only the label was updated in the DB
  const updates = await page.evaluate(() => window.locationUpdates);
  expect(updates.length).toBe(1);
  expect(updates[0]).toEqual({
    id: 'secured-facility-id',
    data: { label: 'Secured Facility - Updated Title' }
  });
});

test('allows full geofence editing when no guards are deployed at the location', async ({ page }) => {
  await openLocationsWithGuards(page, []);

  // Check table has no deployed badge
  const table = page.locator('#locationTable');
  await expect(table).not.toContainText('Deployed');

  // Click Edit
  await page.getByRole('button', { name: 'Edit', exact: true }).click();

  // Safeguard banner must be hidden
  await expect(page.locator('#geofenceSafeguardBanner')).toBeHidden();

  // Controls must be enabled
  await expect(page.locator('#radius')).toBeEnabled();
  await expect(page.locator('#addressSearch')).toBeEnabled();
  await expect(page.locator('#addressSearchButton')).toBeEnabled();

  // Marker dragging must be enabled
  expect(await page.evaluate(() => window.markerDraggingEnabled)).toBe(true);
});
