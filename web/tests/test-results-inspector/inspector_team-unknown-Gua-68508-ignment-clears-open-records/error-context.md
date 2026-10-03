# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: inspector_team.spec.js >> unknown Guard cannot open a cached DTR and reassignment clears open records
- Location: inspector_team.spec.js:65:1

# Error details

```
Error: expect(received).toContain(expected) // indexOf

Matcher error: received value must not be null nor undefined

Received has value: undefined
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - link "Skip to main content" [ref=e2] [cursor=pointer]:
    - /url: "#main-content"
  - generic [ref=e3]:
    - banner [ref=e4]:
      - generic [ref=e5]:
        - generic [ref=e6]:
          - generic [ref=e7]: Field audit
          - generic [ref=e8]:
            - paragraph [ref=e9]: Security Agency Management System
            - paragraph [ref=e10]: Read-only field review
        - generic [ref=e11]:
          - generic [ref=e12]: Audit mode
          - generic [ref=e13]: Inspector One
          - button "Sign out" [ref=e14] [cursor=pointer]
          - button "Switch to dark mode" [ref=e15] [cursor=pointer]:
            - generic [ref=e16]: dark_mode
            - generic [ref=e17]: Dark mode
      - navigation "Inspector navigation" [ref=e18]:
        - generic [ref=e19]:
          - link "Overview" [ref=e20] [cursor=pointer]:
            - /url: dashboard.html
            - generic [ref=e21]: dashboard
            - text: Overview
          - link "My Guards" [ref=e22]:
            - /url: users.html
            - generic [ref=e23]: table_view
            - text: My Guards
          - link "Sites" [ref=e24] [cursor=pointer]:
            - /url: locations.html
            - generic [ref=e25]: location_on
            - text: Sites
          - link "Alerts" [ref=e26] [cursor=pointer]:
            - /url: incidents.html
            - generic [ref=e27]: emergency
            - text: Alerts
    - generic [ref=e28]:
      - generic [ref=e29]:
        - paragraph [ref=e30]: Records
        - heading "My Guards" [level=1] [ref=e31]
      - main [ref=e32]:
        - generic [ref=e33]: Assigned Guards & DTR
        - table [ref=e36]:
          - rowgroup [ref=e37]:
            - row [ref=e38]:
              - columnheader "Guard" [ref=e39]
              - columnheader "Status" [ref=e40]
              - columnheader "Scheduled duty" [ref=e41]
              - columnheader "DTR" [ref=e42]
          - rowgroup [ref=e43]:
            - row [ref=e44]:
              - cell "Assigned Guard @" [ref=e45]:
                - generic [ref=e46]: Assigned Guard
                - generic [ref=e47]: "@"
              - cell "Active" [ref=e48]
              - 'cell "Next: Assigned post" [ref=e50]'
              - cell [ref=e51]:
                - button "View DTR" [ref=e52] [cursor=pointer]
  - status:
    - status [ref=e53]:
      - generic [ref=e54]: warning
      - generic [ref=e55]: This Guard is not in your assigned team. Refresh My Guards.
      - button "Dismiss notification" [ref=e56] [cursor=pointer]:
        - generic [ref=e57]: close
```

# Test source

```ts
  1  | const { test, expect } = require('@playwright/test');
  2  | 
  3  | async function teamMocks(page, empty = false) {
  4  |   await page.route('**/platform-configuration.js', route => route.fulfill({ body: '' }));
  5  |   await page.route('**/notification-center.js', route => route.fulfill({ body: '' }));
  6  |   await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
  7  |     contentType: 'text/javascript',
  8  |     body: `
  9  |       window.teamQueries = []; window.teamMessages = []; window.teamDtrReads = [];
  10 |       window.teamEmpty = ${JSON.stringify(empty)};
  11 |       const rows = {
  12 |         users: [
  13 |           {id:'inspector-a',role:'inspector',firstName:'Inspector',lastName:'One',active:true},
  14 |           {id:'guard-a',role:'user',firstName:'Assigned',lastName:'Guard',inspector_id:'inspector-a',active:true},
  15 |           {id:'guard-b',role:'user',firstName:'Other',lastName:'Guard',inspector_id:'inspector-b',active:true}
  16 |         ],
  17 |         schedules: [{id:'duty-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-06T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-06T09:00:00Z')},locationLabel:'Assigned post'}],
  18 |         locations: [{id:'site-a',label:'Assigned post',active:true}],
  19 |       };
  20 |       function query(table, filters = [], id = null) {
  21 |         return {
  22 |           where: (key,op,value) => query(table,[...filters,[key,value]],id),
  23 |           doc: value => query(table,filters,value),
  24 |           orderBy: () => query(table,filters,id),
  25 |           get: async () => {
  26 |             window.teamQueries.push({table,filters,id});
  27 |             let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
  28 |             if(window.teamEmpty && filters.some(([key]) => key === 'inspector_id')) selected = [];
  29 |             const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
  30 |             return id ? docs[0] || {exists:false} : {docs,size:docs.length,forEach:fn=>docs.forEach(fn)};
  31 |           },
  32 |         };
  33 |       }
  34 |       window.firebase = {auth:()=>({onAuthStateChanged:fn=>Promise.resolve().then(()=>fn({uid:'inspector-a'})),signOut:async()=>{}}),firestore:()=>({collection:table=>query(table)})};
  35 |       window.appSupabase = {from:table=>({select:()=>({eq:(key,value)=>({order:async()=>{window.teamDtrReads.push({table,key,value});return {data:[],error:null};}})})})};
  36 |       window.appDialog = {toast:message=>window.teamMessages.push(message),runBusy:async(_button,fn)=>fn()};
  37 |     `,
  38 |   }));
  39 | }
  40 | 
  41 | test.afterEach(async ({ page }, info) => {
  42 |   await page.screenshot({ path: info.outputPath('inspector-team.png'), fullPage: true });
  43 | });
  44 | 
  45 | test('My Guards queries assigned personnel and opens their DTR', async ({ page }) => {
  46 |   await teamMocks(page);
  47 |   await page.goto('/inspector/users.html');
  48 |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  49 |   await expect(page.locator('#userTableBody')).not.toContainText('Other Guard');
  50 |   await expect(page.locator('.ix-page-title')).toHaveText('My Guards');
  51 |   expect(await page.evaluate(() => teamQueries.some(query => query.filters.some(([key,value]) => key === 'inspector_id' && value === 'inspector-a')))).toBe(true);
  52 |   await page.getByRole('button', { name: 'View DTR' }).click();
  53 |   await expect(page.locator('#dtrModal')).toHaveClass(/show/);
  54 |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  55 |   expect(await page.evaluate(() => teamDtrReads)).toEqual([{table:'attendance_sessions',key:'user_id',value:'guard-a'}]);
  56 | });
  57 | 
  58 | test('empty assignment explains who assigns the Inspector team', async ({ page }) => {
  59 |   await teamMocks(page, true);
  60 |   await page.goto('/inspector/users.html');
  61 |   await expect(page.locator('#userTableBody')).toContainText('No Guards assigned to you yet');
  62 |   await expect(page.getByRole('button', { name: 'View DTR' })).toHaveCount(0);
  63 | });
  64 | 
  65 | test('unknown Guard cannot open a cached DTR and reassignment clears open records', async ({ page }) => {
  66 |   await teamMocks(page);
  67 |   await page.goto('/inspector/users.html');
  68 |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  69 |   await page.evaluate(() => viewDTR('guard-b'));
  70 |   expect(await page.evaluate(() => teamDtrReads.length)).toBe(0);
> 71 |   expect(await page.evaluate(() => teamMessages.at(-1))).toContain('not in your assigned team');
     |                                                          ^ Error: expect(received).toContain(expected) // indexOf
  72 |   await page.getByRole('button', { name: 'View DTR' }).click();
  73 |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  74 |   await page.evaluate(async () => { teamEmpty = true; await loadGuards(); });
  75 |   await expect(page.locator('#dtrModal')).not.toHaveClass(/show/);
  76 |   await expect(page.locator('#dtrRecordsList')).toBeEmpty();
  77 | });
  78 | 
  79 | test('Inspector overview counts assigned Guards only', async ({ page }) => {
  80 |   await teamMocks(page);
  81 |   await page.goto('/inspector/dashboard.html');
  82 |   await expect(page.locator('#totalGuards')).toHaveText('1');
  83 |   await expect(page.locator('#totalSchedules')).toHaveText('1');
  84 |   await expect(page.getByText('My assigned Guards')).toBeVisible();
  85 | });
  86 | 
```