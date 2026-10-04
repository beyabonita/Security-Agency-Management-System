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
      map: () => ({ fitBounds() {}, on() {}, invalidateSize() {}, flyTo() {}, flyToBounds() {}, getZoom: () => 17 }),
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


const search = require('../js/ph-location-search.js');
const place = (extra = {}) => ({name: 'Fortune Towne', display_name: 'Fortune Towne, Bacolod, Philippines', lat:'10.6793125', lon:'122.9943915', address:{country_code:'ph'}, class:'place', type:'village', osm_type:'node', osm_id:1, ...extra});

test('normalizes Philippine names, removes invalid and duplicate results, and filters saved sites', () => {
  expect(search.variants('Fortune Town', 'Bacolod')).toEqual(['Fortune Town, Bacolod', 'Fortune Towne, Bacolod']);
  expect(search.variants('Brgy. Sto. Niño')).toContain('Barangay Santo Niño');
  expect(search.filter([place(), place(), place({osm_id:2,address:{country_code:'us'}}), place({osm_id:3,lat:''}), place({osm_id:4,lon:'NaN'})], 'Fortune Town')).toHaveLength(1);
  expect(search.filter([place(), place({osm_id:2,class:'highway',type:'residential'})], '', 'roads')).toHaveLength(1);
  expect(search.matchesSite({label:'Santo Niño',address:'Cebu City',active:true}, 'nino cebu', 'active')).toBe(true);
  expect(search.matchesSite({label:'Santo Niño',address:'Cebu City',active:false}, 'nino', 'active')).toBe(false);
});

test('searches nationwide with spelling fallback, caches results, and selects the correct pin', async ({page}) => {
  await openLocations(page);
  const requests=[];
  await page.route('https://nominatim.openstreetmap.org/search?**', async route => {
    const url=new URL(route.request().url()); requests.push(url);
    await route.fulfill({json:url.searchParams.get('q')==='Fortune Towne, Bacolod'?[place()]:[]});
  });
  await page.getByRole('button',{name:'Add Deployment Site',exact:true}).click();
  await page.locator('#addressSearch').fill('Fortune Town, Bacolod');
  await page.locator('#addressSearchButton').click();
  await expect(page.locator('#addressSuggestions button')).toHaveCount(1);
  expect(requests.map(url=>url.searchParams.get('q'))).toEqual(['Fortune Town, Bacolod','Fortune Towne, Bacolod']);
  for(const url of requests){expect(url.searchParams.get('countrycodes')).toBe('ph');expect(url.searchParams.get('limit')).toBe('40');expect(url.searchParams.has('bounded')).toBe(false);}
  await page.locator('#addressSearchButton').click();
  await expect(page.locator('#addressSearchStatus')).toContainText('1 Philippine results');
  expect(requests).toHaveLength(2);
  await page.locator('#addressSuggestions button').click();
  await expect(page.locator('#lat')).toHaveValue('10.6793125');
  await expect(page.locator('#address')).toHaveValue('Fortune Towne, Bacolod, Philippines');
  expect(await page.evaluate(()=>window.locationWrites)).toEqual([]);
});

test('place type filters results locally and saved site filters preserve records', async ({page}) => {
  await openLocations(page);
  let requests=0;
  await page.route('https://nominatim.openstreetmap.org/search?**', route=>{requests++;return route.fulfill({json:[place(),place({osm_id:2,name:'Fortune Road',class:'highway',type:'residential'}),place({osm_id:3,name:'<img src=x onerror=alert(1)>',class:'amenity',type:'school'})]});});
  await page.getByRole('button',{name:'Add Deployment Site',exact:true}).click();
  await page.locator('#addressSearch').fill('Fortune');
  await page.locator('#addressSearchButton').click();
  await expect(page.locator('#addressSuggestions button')).toHaveCount(3);
  await expect(page.locator('#addressSuggestions img')).toHaveCount(0);
  await page.locator('#addressType').selectOption('roads');
  await expect(page.locator('#addressSuggestions button')).toHaveCount(1);
  await expect(page.locator('#addressSuggestions')).toBeVisible();
  await expect(page.locator('#addressSuggestions')).toContainText('Fortune Road');
  expect(requests).toBe(1);
  await page.locator('#siteFilter').fill('manila existing');
  await expect(page.locator('#locationTable')).toContainText('Existing site');
  await page.locator('#siteStatusFilter').selectOption('disabled');
  await expect(page.locator('#locationTable')).toContainText('No deployment sites match');
  await page.locator('#siteStatusFilter').selectOption('all');
  await expect(page.locator('#locationTable')).toContainText('Existing site');
  expect(await page.evaluate(()=>window.locationWrites)).toEqual([]);
});

test('a delayed search cannot reopen suggestions after the query changes or the form closes', async ({page}) => {
  await openLocations(page);
  let release;
  const pending=new Promise(resolve=>release=resolve);
  await page.route('https://nominatim.openstreetmap.org/search?**', async route=>{await pending;await route.fulfill({json:[place()]});});
  await page.getByRole('button',{name:'Add Deployment Site',exact:true}).click();
  await page.locator('#addressSearch').fill('Fortune');
  const request=page.waitForRequest('https://nominatim.openstreetmap.org/search?**');
  await page.locator('#addressSearchButton').click();await request;
  await page.locator('#addressSearch').fill('Cebu');
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  release();
  await page.evaluate(()=>geocoderQueue);
  await expect(page.locator('#addressSuggestions')).not.toHaveClass(/show/);
  await expect(page.locator('#addressSearch')).toHaveValue('Cebu');
  await expect(page.locator('#addressSearchButton')).toBeEnabled();
  await expect(page.locator('#lat')).toHaveValue('');
});

test('prioritizes Negros Occidental and Oriental locations and resolves local directory barangays', async ({ page }) => {
  // Unit check: Talisay Negros Occidental must score higher than Talisay Cebu
  const talisayCebu = { name: 'Talisay', display_name: 'Talisay, Cebu, Central Visayas, Philippines', lat: '10.245', lon: '123.849', address: { country_code: 'ph' } };
  const talisayNegros = { name: 'Talisay', display_name: 'Talisay, Negros Occidental, Negros Island Region, Philippines', lat: '10.7397', lon: '122.9691', address: { country_code: 'ph', state: 'Negros Occidental' } };
  const filtered = search.filter([talisayCebu, talisayNegros], 'talisay');
  expect(filtered[0].display_name).toContain('Negros Occidental');

  // Directory check: Zone 1 Talisay must resolve accurately
  const zone1Matches = search.searchNegros('Zone 1 Talisay');
  expect(zone1Matches.length).toBeGreaterThan(0);
  expect(zone1Matches[0].name).toBe('Zone 1');
  expect(zone1Matches[0].display_name).toContain('Talisay, Negros Occidental');
  expect(zone1Matches[0].is_negros).toBe(true);

  // Saved agency site check
  const savedSites = [{ label: 'Lilia Store', address: 'Domingo Lizares St, Zone 1, Talisay', latitude: 10.738, longitude: 122.966 }];
  const savedMatches = search.searchSavedSites(savedSites, 'Lilia Store');
  expect(savedMatches.length).toBe(1);
  expect(savedMatches[0].is_agency_site).toBe(true);
  expect(savedMatches[0].name).toBe('Lilia Store');

  // UI verification: Opening form and searching Zone 1 shows Negros badge and selects pin
  await openLocations(page);
  await page.route('https://nominatim.openstreetmap.org/search?**', route => route.fulfill({ json: [] }));
  await page.getByRole('button', { name: 'Add Deployment Site', exact: true }).click();
  await page.locator('#addressSearch').fill('Zone 1 Talisay');
  await page.locator('#addressSearchButton').click();

  const suggestion = page.locator('#addressSuggestions button').first();
  await expect(suggestion).toBeVisible();
  await expect(suggestion).toContainText('Zone 1');
  await expect(suggestion).toContainText('Negros');

  await suggestion.click();
  await expect(page.locator('#lat')).toHaveValue('10.738');
  await expect(page.locator('#lng')).toHaveValue('122.966');
});

test('strictly excludes nationwide non-Negros results (e.g. Paranaque, Cavite, Davao, Iloilo) and finds Negros hubs', async ({ page }) => {
  // Unit test: filter must reject non-Negros results and keep only Negros Island
  const paranaque = { name: 'Seven Eleven', display_name: 'Seven Eleven, Sun Valley, Parañaque, Metro Manila, 1711, Philippines', lat: '14.4926', lon: '121.0284', address: { country_code: 'ph', city: 'Parañaque', state: 'Metro Manila' } };
  const cavite = { name: 'Seven Eleven', display_name: 'Seven Eleven, General Trias, Cavite, Calabarzon, 4107, Philippines', lat: '14.3555', lon: '120.9182', address: { country_code: 'ph', state: 'Cavite' } };
  const davao = { name: 'Seven-Eleven', display_name: 'Seven-Eleven, Digos, Davao del Sur, Davao Region, 8002, Philippines', lat: '6.9411', lon: '125.3040', address: { country_code: 'ph', state: 'Davao del Sur' } };
  const iloilo = { name: 'Seven-Eleven', display_name: 'Seven-Eleven, Carles, Iloilo, Western Visayas, 5019, Philippines', lat: '11.5732', lon: '123.1345', address: { country_code: 'ph', state: 'Iloilo' } };
  const negrosSanCarlos = { name: 'Seven Eleven', display_name: 'Seven Eleven & Brigada, Rizal Street, San Carlos City, Negros Occidental, 6127, Philippines', lat: '10.4821', lon: '123.4198', address: { country_code: 'ph', state: 'Negros Occidental' } };

  const filtered = search.filter([paranaque, cavite, davao, iloilo, negrosSanCarlos], 'Seven Eleven');
  expect(filtered).toHaveLength(1);
  expect(filtered[0].display_name).toContain('Negros Occidental');

  // Verify that if all results are outside Negros, filter returns empty (never leaks fallback)
  const nonNegrosOnly = search.filter([paranaque, cavite, davao, iloilo], 'Seven Eleven');
  expect(nonNegrosOnly).toHaveLength(0);

  // Verify searchNegros canonical word matching for Seven eleven / 7-Eleven
  const localHubs = search.searchNegros('Seven eleven');
  expect(localHubs.length).toBeGreaterThan(0);
  expect(localHubs.every(h => h.is_negros)).toBe(true);

  // UI verification: searching 'Seven eleven' does not display non-Negros results
  await openLocations(page);
  await page.route('https://nominatim.openstreetmap.org/search?**', route => {
    route.fulfill({ json: [paranaque, cavite, davao, iloilo] });
  });
  await page.getByRole('button', { name: 'Add Deployment Site', exact: true }).click();
  await page.locator('#addressSearch').fill('Seven eleven');
  await page.locator('#addressSearchButton').click();

  const firstSuggestion = page.locator('#addressSuggestions button').first();
  await expect(firstSuggestion).toBeVisible();

  const suggestions = page.locator('#addressSuggestions button');
  const count = await suggestions.count();
  expect(count).toBeGreaterThan(0);
  for (let i = 0; i < count; i++) {
    const text = await suggestions.nth(i).innerText();
    expect(text).not.toContain('Metro Manila');
    expect(text).not.toContain('Parañaque');
    expect(text).not.toContain('Cavite');
    expect(text).not.toContain('Davao');
    expect(text).not.toContain('Iloilo');
    expect(text).toContain('Negros');
  }
});

