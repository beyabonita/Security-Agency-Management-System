# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: inspector_team.spec.js >> unknown Guard cannot open a cached DTR and reassignment clears open records
- Location: inspector_team.spec.js:75:1

# Error details

```
Error: expect(locator).not.toHaveClass(expected) failed

Locator: locator('#dtrModal')
Expected pattern: not /show/
Received string: "modal fade ix-modal show"
Timeout: 5000ms

Call log:
  - Expect "not toHaveClass" with timeout 5000ms
  - waiting for locator('#dtrModal')
    13 × locator resolved to <div id="dtrModal" tabindex="-1" role="dialog" aria-modal="true" class="modal fade ix-modal show">…</div>
       - unexpected value "modal fade ix-modal show"

```

```yaml
- dialog:
  - heading "Daily Time Record" [level=5]
  - button "Close"
  - text: Month
  - textbox "Month": 2026-09
  - text: DTR cut-off
  - combobox "DTR cut-off"
  - text: Sep 1, 2026 - Sep 15, 2026 · 0 duty sessions
  - paragraph: The report follows the agency's twice-monthly DTR format.
  - button "Download Agency DTR"
```

# Test source

```ts
  1   | const { test, expect } = require('@playwright/test');
  2   | 
  3   | async function teamMocks(page, empty = false) {
  4   |   await page.route('**/platform-configuration.js', route => route.fulfill({ body: '' }));
  5   |   await page.route('**/notification-center.js', route => route.fulfill({ body: '' }));
  6   |   await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
  7   |     contentType: 'text/javascript',
  8   |     body: `
  9   |       window.teamQueries = []; window.teamMessages = []; window.teamDtrReads = []; window.teamRpcCalls = [];
  10  |       window.teamEmpty = ${JSON.stringify(empty)};
  11  |       const rows = {
  12  |         users: [
  13  |           {id:'inspector-a',role:'inspector',firstName:'Inspector',lastName:'One',active:true},
  14  |           {id:'guard-a',role:'user',firstName:'Assigned',lastName:'Guard',inspector_id:'inspector-a',active:true},
  15  |           {id:'guard-b',role:'user',firstName:'Other',lastName:'Guard',inspector_id:'inspector-b',active:true}
  16  |         ],
  17  |         schedules: [{id:'duty-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-06T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-06T09:00:00Z')},locationLabel:'Assigned post'}],
  18  |         locations: [{id:'site-a',label:'Assigned post',active:true}],
  19  |         incidents: [{id:'incident-a',userId:'guard-a',guardName:'Assigned Guard',category:'medical',status:'open',remarks:'Needs assistance',capturedAt:{toDate:()=>new Date('2026-09-05T02:00:00Z')}}],
  20  |       };
  21  |       function query(table, filters = [], id = null) {
  22  |         return {
  23  |           where: (key,op,value) => query(table,[...filters,[key,value]],id),
  24  |           doc: value => query(table,filters,value),
  25  |           orderBy: () => query(table,filters,id),
  26  |           get: async () => {
  27  |             window.teamQueries.push({table,filters,id});
  28  |             let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
  29  |             if(window.teamEmpty && filters.some(([key]) => key === 'inspector_id')) selected = [];
  30  |             const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
  31  |             return id ? docs[0] || {exists:false} : {docs,size:docs.length,forEach:fn=>docs.forEach(fn)};
  32  |           },
  33  |           onSnapshot: (next) => {
  34  |             let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
  35  |             const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
  36  |             Promise.resolve().then(() => next({docs,size:docs.length,forEach:fn=>docs.forEach(fn)}));
  37  |             return () => {};
  38  |           },
  39  |         };
  40  |       }
  41  |       window.firebase = {auth:()=>({onAuthStateChanged:fn=>Promise.resolve().then(()=>fn({uid:'inspector-a'})),signOut:async()=>{}}),firestore:()=>({collection:table=>query(table)})};
  42  |       window.appSupabase = {
  43  |         from:table=>({select:()=>({eq:(key,value)=>({order:async()=>{window.teamDtrReads.push({table,key,value});return {data:[],error:null};}})})}),
  44  |         rpc: async (name, params) => { window.teamRpcCalls.push({name,params}); return {data:null,error:null}; }
  45  |       };
  46  |       window.appDialog = {toast:message=>window.teamMessages.push(message),runBusy:async(_button,fn)=>fn()};
  47  |     `,
  48  |   }));
  49  | }
  50  | 
  51  | test.afterEach(async ({ page }, info) => {
  52  |   await page.screenshot({ path: info.outputPath('inspector-team.png'), fullPage: true });
  53  | });
  54  | 
  55  | test('My Guards queries assigned personnel and opens their DTR', async ({ page }) => {
  56  |   await teamMocks(page);
  57  |   await page.goto('/inspector/users.html');
  58  |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  59  |   await expect(page.locator('#userTableBody')).not.toContainText('Other Guard');
  60  |   await expect(page.locator('.ix-page-title')).toHaveText('My Guards');
  61  |   expect(await page.evaluate(() => teamQueries.some(query => query.filters.some(([key,value]) => key === 'inspector_id' && value === 'inspector-a')))).toBe(true);
  62  |   await page.getByRole('button', { name: 'View DTR' }).click();
  63  |   await expect(page.locator('#dtrModal')).toHaveClass(/show/);
  64  |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  65  |   expect(await page.evaluate(() => teamDtrReads)).toEqual([{table:'attendance_sessions',key:'user_id',value:'guard-a'}]);
  66  | });
  67  | 
  68  | test('empty assignment explains who assigns the Inspector team', async ({ page }) => {
  69  |   await teamMocks(page, true);
  70  |   await page.goto('/inspector/users.html');
  71  |   await expect(page.locator('#userTableBody')).toContainText('No Guards assigned to you yet');
  72  |   await expect(page.getByRole('button', { name: 'View DTR' })).toHaveCount(0);
  73  | });
  74  | 
  75  | test('unknown Guard cannot open a cached DTR and reassignment clears open records', async ({ page }) => {
  76  |   await teamMocks(page);
  77  |   await page.goto('/inspector/users.html');
  78  |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  79  |   await page.evaluate(() => viewDTR('guard-b'));
  80  |   expect(await page.evaluate(() => teamDtrReads.length)).toBe(0);
  81  |   await expect(page.getByText('This Guard is not in your assigned team. Refresh My Guards.')).toBeVisible();
  82  |   await page.getByRole('button', { name: 'View DTR' }).click();
  83  |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  84  |   await page.evaluate(async () => { teamEmpty = true; await loadGuards(); });
> 85  |   await expect(page.locator('#dtrModal')).not.toHaveClass(/show/);
      |                                               ^ Error: expect(locator).not.toHaveClass(expected) failed
  86  |   await expect(page.locator('#dtrRecordsList')).toBeEmpty();
  87  | });
  88  | 
  89  | test('Inspector overview counts assigned Guards only', async ({ page }) => {
  90  |   await teamMocks(page);
  91  |   await page.goto('/inspector/dashboard.html');
  92  |   await expect(page.locator('#totalGuards')).toHaveText('1');
  93  |   await expect(page.locator('#totalSchedules')).toHaveText('1');
  94  |   await expect(page.getByText('My assigned Guards')).toBeVisible();
  95  | });
  96  | 
  97  | test('Inspector acknowledges an assigned Guard incident through the secured RPC', async ({ page }) => {
  98  |   await teamMocks(page);
  99  |   await page.goto('/inspector/incidents.html');
  100 |   await expect(page.locator('#incidentTableBody')).toContainText('Assigned Guard');
  101 |   await page.locator('#incidentTableBody tr').click();
  102 |   await page.locator('#statusSelect').selectOption('acknowledged');
  103 |   await page.locator('#statusNote').fill('Response team notified.');
  104 |   await page.getByRole('button', { name: 'Save review' }).click();
  105 |   await expect.poll(() => page.evaluate(() => teamRpcCalls)).toEqual([{
  106 |     name: 'update_incident_status',
  107 |     params: {
  108 |       p_incident_id: 'incident-a',
  109 |       p_status: 'acknowledged',
  110 |       p_status_note: 'Response team notified.',
  111 |     },
  112 |   }]);
  113 | });
  114 | 
```