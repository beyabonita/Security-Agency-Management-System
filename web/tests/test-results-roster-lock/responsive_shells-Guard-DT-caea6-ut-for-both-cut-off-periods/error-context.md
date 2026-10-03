# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: responsive_shells.spec.js >> Guard DTR modals show the agency PDF layout for both cut-off periods
- Location: responsive_shells.spec.js:106:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator: getByRole('button', { name: 'Download Agency DTR' })
Expected: visible
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toBeVisible" with timeout 5000ms
  - waiting for getByRole('button', { name: 'Download Agency DTR' })

```

```yaml
- link "Skip to main content":
  - /url: "#main-content"
- banner:
  - paragraph: Security Agency Management System
  - button "Sign out"
  - button "Switch to dark mode"
  - navigation "Inspector navigation":
    - button "Menu"
- paragraph: Records
- heading "My Guards" [level=1]
- main:
  - text: Assigned Guards & DTR
  - table:
    - rowgroup:
      - row "Guard Status Scheduled duty Schedule DTR":
        - columnheader "Guard"
        - columnheader "Status"
        - columnheader "Scheduled duty"
        - columnheader "Schedule"
        - columnheader "DTR"
    - rowgroup:
      - row "Loading…":
        - cell "Loading…"
- heading "Daily Time Record" [level=5]
- button "Close"
- text: Month
- textbox "Month"
- text: DTR cut-off
- combobox "DTR cut-off":
  - option "1st–15th" [selected]
  - option "16th–end of month"
- text: Select a reporting period.
- article "Daily Time Record preview":
  - img "Twenty Twenty Security Agency logo"
  - heading "TWENTY TWENTY SECURITY AGENCY, INC." [level=2]
  - paragraph: P. Hernaez Ext. (Fronting Villa Celia Subd.)
  - paragraph: Brgy. Taculing, Bacolod City, Negros Occidental 6100
  - paragraph: "Email: ttwenty2016@yahoo.com | Tel: (034) 466-5235 | Mobile: 09056654294"
  - heading "DAILY TIME RECORD · GUARD SHIFTS" [level=3]
  - strong: "Guard Name:"
  - text: Pedro D. Dela Cruz
  - strong: "Detachment:"
  - text: Main Detachment
  - strong: "Period Covered:"
  - text: Sep 1, 2026 - Sep 15, 2026
  - table "Attendance entries for Sep 1, 2026 - Sep 15, 2026":
    - caption: Attendance entries for Sep 1, 2026 - Sep 15, 2026
    - rowgroup:
      - row "Duty Date Assigned shift / Site Actual Time In Actual Time Out Total Overtime Hours Total Worked Hours Status":
        - columnheader "Duty Date"
        - columnheader "Assigned shift / Site"
        - columnheader "Actual Time In"
        - columnheader "Actual Time Out"
        - columnheader "Total Overtime Hours"
        - columnheader "Total Worked Hours"
        - columnheader "Status"
    - rowgroup:
      - row "1":
        - rowheader "1"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "2":
        - rowheader "2"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "3 Schedule unavailable Main Detachment 8:00 AM 5:00 PM 9:00 Completed":
        - rowheader "3"
        - cell "Schedule unavailable Main Detachment"
        - cell "8:00 AM"
        - cell "5:00 PM"
        - cell
        - cell "9:00"
        - cell "Completed"
      - row "4":
        - rowheader "4"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "5":
        - rowheader "5"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "6":
        - rowheader "6"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "7":
        - rowheader "7"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "8":
        - rowheader "8"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "9":
        - rowheader "9"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "10":
        - rowheader "10"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "11":
        - rowheader "11"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "12":
        - rowheader "12"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "13":
        - rowheader "13"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "14":
        - rowheader "14"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
      - row "15":
        - rowheader "15"
        - cell
        - cell
        - cell
        - cell
        - cell
        - cell
  - paragraph: I hereby certify that the above record is true and correct.
  - paragraph:
    - strong: NO. OF DAYS
    - text: "1"
  - paragraph:
    - strong: TOTAL OVERTIME HOURS
    - text: 0:00
  - paragraph:
    - strong: TOTAL WORKED HOURS
    - text: 9:00
  - paragraph: Approved By
  - paragraph: Guard Signature
  - text: Entries are recorded or Operations Head-verified Time In/Out values. Overnight times are marked “next day”. Overtime is verified time worked after the scheduled end and is already included in Total Worked Hours. Values use H:MM. Blank overtime means attendance or the scheduled end is unavailable. Recorded hours do not calculate overtime pay.
```

# Test source

```ts
  42  | 
  43  | test('HR navigation opens and closes as a mobile drawer', async ({ page }) => {
  44  |   await openProtectedLayout(page, '/admin/dashboard.html');
  45  |   const toggle = page.locator('#axMenuToggle');
  46  |   await expect(toggle).toBeVisible();
  47  |   await toggle.click();
  48  |   await expect(page.locator('.ax-sidebar')).toHaveClass(/ax-open/);
  49  |   await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  50  |   await page.keyboard.press('Escape');
  51  |   await expect(page.locator('.ax-sidebar')).not.toHaveClass(/ax-open/);
  52  | });
  53  | 
  54  | test('Inspector navigation exposes a compact mobile menu', async ({ page }) => {
  55  |   await openProtectedLayout(page, '/inspector/dashboard.html');
  56  |   const toggle = page.locator('#ixMenuToggle');
  57  |   await expect(toggle).toBeVisible();
  58  |   await toggle.click();
  59  |   await expect(page.locator('#ixTopnav')).toHaveClass(/ix-open/);
  60  |   await expect(page.locator('.ix-topnav-links')).toBeVisible();
  61  | });
  62  | 
  63  | test('Inspector portal has no personal attendance controls', async ({ page }) => {
  64  |   await openProtectedLayout(page, '/inspector/dashboard.html');
  65  |   await expect(page.locator('a[href="attendance.html"]')).toHaveCount(0);
  66  |   await expect(page.getByText('My Time In / Out', { exact: true })).toHaveCount(0);
  67  | 
  68  |   const removedPage = await page.goto('/inspector/attendance.html');
  69  |   expect(removedPage?.status()).toBe(404);
  70  | });
  71  | 
  72  | test('HR Personnel keeps DTR available for Guards only', async ({ page }) => {
  73  |   await openProtectedLayout(page, '/admin/users.html');
  74  | 
  75  |   await expect(page.locator('.ax-nav a[href="users.html"]')).toHaveText(/Personnel/);
  76  |   await expect(page.locator('[aria-labelledby="guardPersonnelHeading"] th').filter({ hasText: 'DTR' })).toHaveCount(1);
  77  |   await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] th').filter({ hasText: 'DTR' })).toHaveCount(0);
  78  |   await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] thead')).toContainText('Personnel');
  79  |   await expect(page.locator('[aria-labelledby="inspectorPersonnelHeading"] thead')).toContainText('Device');
  80  | });
  81  | 
  82  | test('roster DTR preview fits phone and desktop in light and dark themes', async ({ page }, testInfo) => {
  83  |   await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
  84  |     window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};
  85  |     window.appSupabase={rpc:async()=>({data:[2,3].map(count=>({id:String(count),name:count+' Shifts',version:1,in_use:false,shifts:RosterSetup.defaults(count)})),error:null})};
  86  |   `}));
  87  |   await openProtectedLayout(page, '/admin/schedule.html');
  88  |   await page.evaluate(()=>loadRosterSetups());
  89  |   await expect(page.locator('#scheduleMode')).toHaveCount(0);
  90  |   await page.locator('#rosterDate').fill('2099-09-15');
  91  |   await page.locator('#rosterSetup').selectOption('3');
  92  |   await expect(page.locator('#rosterPreview')).toContainText('Sep 1–15, 2099');
  93  |   await expect(page.locator('#rosterPreview')).toContainText('6:00 AM (next day)');
  94  |   await expect(page.locator('#rosterGuards select')).toHaveCount(3);
  95  |   for (const width of [390,1440]) {
  96  |     await page.setViewportSize({width,height:1000});
  97  |     for (const theme of ['light','dark']) {
  98  |       await page.evaluate(theme => sentinelTheme.set(theme), theme);
  99  |       await expect(page.locator('#rosterPreview')).toBeVisible();
  100 |       expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  101 |       await page.screenshot({path:testInfo.outputPath('roster-'+width+'-'+theme+'.png'),fullPage:true});
  102 |     }
  103 |   }
  104 | });
  105 | 
  106 | test('Guard DTR modals show the agency PDF layout for both cut-off periods', async ({ page }) => {
  107 |   for (const path of ['/admin/users.html', '/inspector/users.html']) {
  108 |     await openProtectedLayout(page, path);
  109 |     await page.waitForFunction(() => typeof window.DtrReport?.renderPreview === 'function');
  110 |     await page.locator('#dtrModal').evaluate((modal) => {
  111 |       modal.style.display = 'block';
  112 |       modal.classList.add('show');
  113 |     });
  114 |     await page.locator('#dtrRecordsList').evaluate((container) => {
  115 |       const period = window.DtrReport.periodFromSelection('2026-09', 'first');
  116 |       container.innerHTML = window.DtrReport.renderPreview({
  117 |         period,
  118 |         account: { firstName: 'Pedro', middleInitial: 'D', lastName: 'Dela Cruz' },
  119 |         detachment: 'Main Detachment',
  120 |         logoUrl: '../icons/sentinel-link-mark.png',
  121 |         sessions: [{
  122 |           duty_date: '2026-09-03',
  123 |           clock_in_at: '2026-09-03T08:00:00+08:00',
  124 |           clock_out_at: '2026-09-03T17:00:00+08:00',
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
> 142 |     await expect(page.getByRole('button', { name: 'Download Agency DTR' })).toBeVisible();
      |                                                                             ^ Error: expect(locator).toBeVisible() failed
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
  225 |   await expect(firstMenu).toBeVisible();
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
```