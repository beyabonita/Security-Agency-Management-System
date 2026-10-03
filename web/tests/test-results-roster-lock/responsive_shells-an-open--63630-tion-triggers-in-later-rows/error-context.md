# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: responsive_shells.spec.js >> an open personnel action menu stays above action triggers in later rows
- Location: responsive_shells.spec.js:199:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator:  locator('#personnel-actions-first')
Expected: visible
Received: hidden
Timeout:  5000ms

Call log:
  - Expect "toBeVisible" with timeout 5000ms
  - waiting for locator('#personnel-actions-first')
    13 × locator resolved to <div id="personnel-actions-first" class="personnel-actions-menu">…</div>
       - unexpected value "hidden"

```

```yaml
- link "Skip to main content":
  - /url: "#main-content"
- complementary:
  - paragraph: Operations Head
  - paragraph: Security Agency Management System
  - navigation:
    - text: Manage
    - link "Dashboard":
      - /url: dashboard.html
    - link "Personnel":
      - /url: users.html
    - link "Deployment Sites":
      - /url: locations.html
    - link "Schedule":
      - /url: schedule.html
    - link "Incidents":
      - /url: incidents.html
    - link "Duty requests":
      - /url: swaps.html
  - text: TwentyTwenty Security Agency
- banner:
  - text: Operations Head Console
  - heading "Personnel" [level=1]
  - button "Sign out"
  - button "Switch to dark mode": Dark mode
- main:
  - text: Personnel records
  - button "Add Guard / Inspector"
  - region "Guard Personnel":
    - heading "Guard Personnel" [level=2]
    - text: "0"
    - table:
      - rowgroup:
        - row "Personnel Duty Category Days of Duty Status Home Post Inspector Actions DTR Device":
          - columnheader "Personnel"
          - columnheader "Duty Category"
          - columnheader "Days of Duty"
          - columnheader "Status"
          - columnheader "Home Post"
          - columnheader "Inspector"
          - columnheader "Actions"
          - columnheader "DTR"
          - columnheader "Device"
      - rowgroup:
        - row "Personnel first Regular 1 Active Site Unassigned Actions DTR Device":
          - cell "Personnel first"
          - cell "Regular"
          - cell "1"
          - cell "Active"
          - cell "Site"
          - cell "Unassigned"
          - cell "Actions":
            - button "Actions"
          - cell "DTR"
          - cell "Device"
        - row "Personnel second Regular 1 Active Site Unassigned Actions DTR Device":
          - cell "Personnel second"
          - cell "Regular"
          - cell "1"
          - cell "Active"
          - cell "Site"
          - cell "Unassigned"
          - cell "Actions":
            - button "Actions"
          - cell "DTR"
          - cell "Device"
  - region "Inspector Personnel":
    - heading "Inspector Personnel" [level=2]
    - text: "0"
    - table:
      - rowgroup:
        - row "Personnel Status Actions Device":
          - columnheader "Personnel"
          - columnheader "Status"
          - columnheader "Actions"
          - columnheader "Device"
      - rowgroup:
        - row "Loading inspectors…":
          - cell "Loading inspectors…"
```

# Test source

```ts
  125 |           location_label: 'Main Detachment',
  126 |         }],
  127 |       });
  128 |     });
  129 |     await expect(page.locator('#dtrPeriodMonth')).toBeVisible();
  130 |     await expect(page.locator('#dtrPeriodCutoff option')).toHaveCount(2);
  131 |     await expect(page.locator('#dtrModal')).toContainText('1st–15th');
  132 |     await expect(page.locator('#dtrModal')).toContainText('16th–end of month');
  133 |     await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  134 |     await expect(page.locator('.dtr-sheet-preview')).toContainText('TWENTY TWENTY SECURITY AGENCY, INC.');
  135 |     await expect(page.locator('.dtr-sheet-preview')).toContainText('DAILY TIME RECORD');
  136 |     await expect(page.locator('.dtr-sheet-meta')).toContainText('Pedro D. Dela Cruz');
  137 |     await expect(page.locator('.dtr-sheet-table tbody tr')).toHaveCount(15);
  138 |     await expect(page.locator('.dtr-sheet-table thead')).toContainText('Assigned shift / Site');
  139 |     await expect(page.locator('.dtr-sheet-table thead')).toContainText('Actual');
  140 |     await expect(page.locator('.dtr-sheet-table thead')).toContainText('Worked');
  141 |     await expect(page.locator('.dtr-day-card')).toHaveCount(0);
  142 |     await expect(page.getByRole('button', { name: 'Download Agency DTR' })).toBeVisible();
  143 | 
  144 |     const dimensions = await page.evaluate(() => ({
  145 |       viewport: document.documentElement.clientWidth,
  146 |       page: document.documentElement.scrollWidth,
  147 |       stageScrollable: document.querySelector('#dtrRecordsList').scrollWidth
  148 |         > document.querySelector('#dtrRecordsList').clientWidth,
  149 |     }));
  150 |     expect(dimensions.page).toBeLessThanOrEqual(dimensions.viewport + 1);
  151 |     expect(dimensions.stageScrollable).toBe(true);
  152 |   }
  153 | });
  154 | 
  155 | test('IT Admin navigation opens as a mobile drawer', async ({ page }) => {
  156 |   await openProtectedLayout(page, '/it-admin/clients.html');
  157 |   const toggle = page.locator('[data-it-nav-toggle]');
  158 |   await expect(toggle).toBeVisible();
  159 |   await toggle.click();
  160 |   await expect(page.locator('#itSidebar')).toHaveClass(/ax-open/);
  161 |   await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  162 | });
  163 | 
  164 | test('every staff role shell uses the shared agency mark', async ({ page }) => {
  165 |   for (const [path, selector] of [
  166 |     ['/admin/dashboard.html', '.ax-brand'],
  167 |     ['/inspector/dashboard.html', '.ix-shell-brand'],
  168 |     ['/it-admin/dashboard.html', '.ax-brand'],
  169 |   ]) {
  170 |     await openProtectedLayout(page, path);
  171 |     const background = await page.locator(selector).evaluate(
  172 |       (element) => getComputedStyle(element, '::before').backgroundImage,
  173 |     );
  174 |     expect(background, `${path} should render the shared agency mark`)
  175 |       .toContain('sentinel-link-mark.png');
  176 |   }
  177 | });
  178 | 
  179 | test('HR create-personnel modal keeps its actions visible on a phone', async ({ page }) => {
  180 |   await openProtectedLayout(page, '/admin/users.html');
  181 |   await page.locator('#createGuardModal').evaluate((modal) => {
  182 |     modal.style.display = 'block';
  183 |     modal.classList.add('show');
  184 |   });
  185 | 
  186 |   const modal = page.locator('#createGuardModal .modal-content');
  187 |   const footer = page.locator('#createGuardModal .modal-footer');
  188 |   await expect(modal).toBeVisible();
  189 |   await expect(footer).toBeVisible();
  190 |   const metrics = await footer.evaluate((element) => {
  191 |     const bounds = element.getBoundingClientRect();
  192 |     return { top: bounds.top, bottom: bounds.bottom, viewport: window.innerHeight };
  193 |   });
  194 |   expect(metrics.top).toBeGreaterThanOrEqual(0);
  195 |   expect(metrics.bottom).toBeLessThanOrEqual(metrics.viewport + 1);
  196 |   await expect(page.locator('#createGuardBtn')).toHaveText('Create Guard');
  197 | });
  198 | 
  199 | test('an open personnel action menu stays above action triggers in later rows', async ({ page }) => {
  200 |   await page.setViewportSize({ width: 1280, height: 720 });
  201 |   await openProtectedLayout(page, '/admin/users.html');
  202 |   await page.locator('#guardTableBody').evaluate((body) => {
  203 |     const row = (id) => `<tr>
  204 |       <td>Personnel ${id}</td><td>Regular</td><td>1</td><td>Active</td>
  205 |       <td>Site</td><td>Unassigned</td>
  206 |       <td><div class="personnel-actions">
  207 |         <button type="button" class="personnel-actions-trigger">Actions</button>
  208 |         <div class="personnel-actions-menu" id="personnel-actions-${id}">
  209 |           <button type="button" class="action-btn">Edit</button>
  210 |           <button type="button" class="action-btn">Disable</button>
  211 |           <button type="button" class="action-btn">Set Home Post</button>
  212 |           <button type="button" class="action-btn">History</button>
  213 |           <button type="button" class="action-btn">Set Inspector</button>
  214 |           <button type="button" class="action-btn">Reports</button>
  215 |         </div>
  216 |       </div></td><td>DTR</td><td>Device</td>
  217 |     </tr>`;
  218 |     body.innerHTML = row('first') + row('second');
  219 |   });
  220 | 
  221 |   const firstActions = page.locator('.personnel-actions').first();
  222 |   const firstMenu = page.locator('#personnel-actions-first');
  223 |   const secondTrigger = page.locator('.personnel-actions-trigger').nth(1);
  224 |   await firstActions.hover();
> 225 |   await expect(firstMenu).toBeVisible();
      |                           ^ Error: expect(locator).toBeVisible() failed
  226 | 
  227 |   const secondTriggerBounds = await secondTrigger.boundingBox();
  228 |   expect(secondTriggerBounds).not.toBeNull();
  229 |   const topMenuId = await page.evaluate(({ x, y }) => {
  230 |     return document.elementFromPoint(x, y)?.closest('.personnel-actions-menu')?.id || null;
  231 |   }, {
  232 |     x: secondTriggerBounds.x + secondTriggerBounds.width / 2,
  233 |     y: secondTriggerBounds.y + secondTriggerBounds.height / 2,
  234 |   });
  235 |   expect(topMenuId).toBe('personnel-actions-first');
  236 | });
  237 | 
  238 | test('deployment-site search, location permission, and cached edit stay reliable', async ({ page }) => {
  239 |   await page.setViewportSize({ width: 1280, height: 800 });
  240 |   await page.unroute('**/supabase-firebase-bridge.js');
  241 |   await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
  242 |     contentType: 'text/javascript',
  243 |     body: `
  244 |       window.firebase = {
  245 |         auth: () => ({ onAuthStateChanged: () => {}, signOut: async () => {} }),
  246 |         firestore: () => ({ collection: () => ({}) })
  247 |       };
  248 |       window.appSupabase = { rpc: async () => ({ data: 100, error: null }) };
  249 |       window.testToastMessages = [];
  250 |       window.appDialog = { toast: (message) => window.testToastMessages.push(message) };
  251 |     `,
  252 |   }));
  253 | 
  254 |   let requestedSearchUrl = null;
  255 |   await page.route('https://nominatim.openstreetmap.org/search?**', (route) => {
  256 |     requestedSearchUrl = new URL(route.request().url());
  257 |     return route.fulfill({
  258 |       contentType: 'application/json',
  259 |       json: [
  260 |         {
  261 |           name: 'Silay',
  262 |           display_name: 'Silay, Negros Occidental, Philippines',
  263 |           lat: '10.7994126',
  264 |           lon: '122.9756149',
  265 |           boundingbox: ['10.75', '10.85', '122.92', '123.03'],
  266 |           address: { city: 'Silay', country: 'Philippines', country_code: 'ph' },
  267 |         },
  268 |         {
  269 |           name: 'Foreign result',
  270 |           display_name: 'Foreign result, Japan',
  271 |           lat: '35.6762',
  272 |           lon: '139.6503',
  273 |           boundingbox: ['35.6', '35.7', '139.6', '139.7'],
  274 |           address: { country: 'Japan', country_code: 'jp' },
  275 |         },
  276 |       ],
  277 |     });
  278 |   });
  279 | 
  280 |   await page.goto('/admin/locations.html', { waitUntil: 'domcontentloaded' });
  281 |   await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  282 |   await page.waitForFunction(() => window.L && typeof window.initMap === 'function');
  283 |   await page.locator('#locationForm').evaluate((form) => { form.style.display = 'block'; });
  284 |   await page.evaluate(() => window.initMap());
  285 |   await expect(page.locator('.sl-location-marker')).toHaveCount(0);
  286 | 
  287 |   await page.locator('#addressSearch').fill('Silay');
  288 |   await page.locator('#addressSearchButton').click();
  289 |   await expect(page.locator('.address-suggestion')).toHaveCount(1);
  290 |   await expect(page.locator('.address-suggestion')).toContainText('Silay');
  291 | 
  292 |   expect(requestedSearchUrl).not.toBeNull();
  293 |   expect(requestedSearchUrl.searchParams.get('countrycodes')).toBe('ph');
  294 |   expect(requestedSearchUrl.searchParams.get('bounded')).toBe('1');
  295 |   expect(requestedSearchUrl.searchParams.get('viewbox')).toBe('116.4,21.3,127.0,4.2');
  296 | 
  297 |   await page.locator('.address-suggestion').click();
  298 |   await expect(page.locator('#selectedAddressDisplay')).toContainText('Silay');
  299 |   await expect(page.locator('.sl-location-marker')).toHaveCount(1);
  300 |   await expect(page.locator('#lat')).toHaveValue('10.7994126');
  301 |   await expect(page.locator('#lng')).toHaveValue('122.9756149');
  302 | 
  303 |   await page.evaluate(() => {
  304 |     Object.defineProperty(navigator, 'geolocation', {
  305 |       configurable: true,
  306 |       value: {
  307 |         getCurrentPosition: (_success, failure) => { window.rejectTestGeolocation = failure; },
  308 |       },
  309 |     });
  310 |   });
  311 |   await page.locator('#useCurrentLocationButton').click();
  312 |   await page.evaluate(() => window.rejectTestGeolocation({ code: 1 }));
  313 |   await expect(page.locator('#addressSearchStatus')).toContainText('selected address was kept');
  314 |   await expect(page.locator('#address')).toHaveValue('Silay, Negros Occidental, Philippines');
  315 |   expect(await page.evaluate(() => window.testToastMessages)).toEqual([]);
  316 | 
  317 |   await page.locator('#useCurrentLocationButton').click();
  318 |   await page.evaluate(() => {
  319 |     const rejectStaleRequest = window.rejectTestGeolocation;
  320 |     window.cancelCurrentLocationRequest();
  321 |     window.setAddressSearchStatus('');
  322 |     rejectStaleRequest({ code: 1 });
  323 |   });
  324 |   await expect(page.locator('#addressSearchStatus')).toHaveText('');
  325 |   expect(await page.evaluate(() => window.testToastMessages)).toEqual([]);
```