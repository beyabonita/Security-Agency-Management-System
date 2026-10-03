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
  await page.locator('#addressSearch').fill('Fortune Town');
  await page.locator('#addressArea').fill('Bacolod');
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
