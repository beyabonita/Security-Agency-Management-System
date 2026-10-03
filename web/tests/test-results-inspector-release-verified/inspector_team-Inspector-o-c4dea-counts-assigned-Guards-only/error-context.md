# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: inspector_team.spec.js >> Inspector overview counts assigned Guards only
- Location: inspector_team.spec.js:109:1

# Error details

```
Error: expect(locator).toHaveText(expected) failed

Locator:  locator('#totalSchedules')
Expected: "1"
Received: "2"
Timeout:  5000ms

Call log:
  - Expect "toHaveText" with timeout 5000ms
  - waiting for locator('#totalSchedules')
    14 × locator resolved to <div class="ix-stat-num" id="totalSchedules">2</div>
       - unexpected value "2"

```

```yaml
- text: "2"
```

# Test source

```ts
  13  |           {id:'inspector-a',role:'inspector',firstName:'Inspector',lastName:'One',active:true},
  14  |           {id:'guard-a',role:'user',firstName:'Assigned',lastName:'Guard',inspector_id:'inspector-a',active:true},
  15  |           {id:'guard-b',role:'user',firstName:'Other',lastName:'Guard',inspector_id:'inspector-b',active:true}
  16  |         ],
  17  |         schedules: [
  18  |           {id:'duty-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-06T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-06T09:00:00Z')},locationLabel:'Assigned post',dtrPeriod:'morning',approvalStatus:'approved'},
  19  |           {id:'cancelled-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-07T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-07T09:00:00Z')},locationLabel:'Cancelled site',approvalStatus:'cancelled'},
  20  |           {id:'duty-b',userId:'guard-b',startAt:{toDate:()=>new Date('2026-09-08T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-08T09:00:00Z')},locationLabel:'Other Guard site',approvalStatus:'approved'}
  21  |         ],
  22  |         locations: [{id:'site-a',label:'Assigned post',active:true}],
  23  |         incidents: [{id:'incident-a',userId:'guard-a',guardName:'Assigned Guard',category:'medical',status:'open',remarks:'Needs assistance',capturedAt:{toDate:()=>new Date('2026-09-05T02:00:00Z')}}],
  24  |       };
  25  |       function query(table, filters = [], id = null) {
  26  |         return {
  27  |           where: (key,op,value) => query(table,[...filters,[key,value]],id),
  28  |           doc: value => query(table,filters,value),
  29  |           orderBy: () => query(table,filters,id),
  30  |           get: async () => {
  31  |             window.teamQueries.push({table,filters,id});
  32  |             let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
  33  |             if(window.teamEmpty && filters.some(([key]) => key === 'inspector_id')) selected = [];
  34  |             const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
  35  |             return id ? docs[0] || {exists:false} : {docs,size:docs.length,forEach:fn=>docs.forEach(fn)};
  36  |           },
  37  |           onSnapshot: (next) => {
  38  |             let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
  39  |             const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
  40  |             Promise.resolve().then(() => next({docs,size:docs.length,forEach:fn=>docs.forEach(fn)}));
  41  |             return () => {};
  42  |           },
  43  |         };
  44  |       }
  45  |       window.firebase = {auth:()=>({onAuthStateChanged:fn=>Promise.resolve().then(()=>fn({uid:'inspector-a'})),signOut:async()=>{}}),firestore:()=>({collection:table=>query(table)})};
  46  |       window.appSupabase = {
  47  |         from:table=>({select:()=>({eq:(key,value)=>({order:async()=>{window.teamDtrReads.push({table,key,value});return {data:[],error:null};}})})}),
  48  |         rpc: async (name, params) => { window.teamRpcCalls.push({name,params}); return {data:null,error:null}; }
  49  |       };
  50  |       window.appDialog = {toast:message=>window.teamMessages.push(message),runBusy:async(_button,fn)=>fn()};
  51  |     `,
  52  |   }));
  53  | }
  54  | 
  55  | test.afterEach(async ({ page }, info) => {
  56  |   await page.screenshot({ path: info.outputPath('inspector-team.png'), fullPage: true });
  57  | });
  58  | 
  59  | test('My Guards queries assigned personnel and opens their DTR', async ({ page }) => {
  60  |   await teamMocks(page);
  61  |   await page.goto('/inspector/users.html');
  62  |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  63  |   await expect(page.locator('#userTableBody')).not.toContainText('Other Guard');
  64  |   await expect(page.locator('.ix-page-title')).toHaveText('My Guards');
  65  |   expect(await page.evaluate(() => teamQueries.some(query => query.filters.some(([key,value]) => key === 'inspector_id' && value === 'inspector-a')))).toBe(true);
  66  |   await page.getByRole('button', { name: 'View DTR' }).click();
  67  |   await expect(page.locator('#dtrModal')).toHaveClass(/show/);
  68  |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  69  |   expect(await page.evaluate(() => teamDtrReads)).toEqual([{table:'attendance_sessions',key:'user_id',value:'guard-a'}]);
  70  | });
  71  | 
  72  | test('Inspector views only an assigned Guard active schedule, grouped by DTR cut-off', async ({ page }) => {
  73  |   await teamMocks(page);
  74  |   await page.goto('/inspector/users.html');
  75  |   await page.getByRole('button', { name: 'View schedule', exact: true }).click();
  76  |   const dialog = page.locator('#scheduleModal');
  77  |   await expect(dialog).toHaveClass(/show/);
  78  |   await expect(dialog).toContainText('Assigned Guard');
  79  |   await expect(dialog).toContainText('Assigned post');
  80  |   await expect(dialog).toContainText('Morning');
  81  |   await expect(dialog).not.toContainText('Cancelled site');
  82  |   await expect(dialog).not.toContainText('Other Guard site');
  83  |   await page.evaluate(() => viewGuardSchedule('guard-b'));
  84  |   await expect(page.getByText('This Guard is not in your assigned team. Refresh My Guards.')).toBeVisible();
  85  |   await page.screenshot({ path: test.info().outputPath('assigned-guard-schedule.png'), fullPage: true });
  86  | });
  87  | 
  88  | test('empty assignment explains who assigns the Inspector team', async ({ page }) => {
  89  |   await teamMocks(page, true);
  90  |   await page.goto('/inspector/users.html');
  91  |   await expect(page.locator('#userTableBody')).toContainText('No Guards assigned to you yet');
  92  |   await expect(page.getByRole('button', { name: 'View DTR' })).toHaveCount(0);
  93  | });
  94  | 
  95  | test('unknown Guard cannot open a cached DTR and reassignment clears open records', async ({ page }) => {
  96  |   await teamMocks(page);
  97  |   await page.goto('/inspector/users.html');
  98  |   await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  99  |   await page.evaluate(() => viewDTR('guard-b'));
  100 |   expect(await page.evaluate(() => teamDtrReads.length)).toBe(0);
  101 |   await expect(page.getByText('This Guard is not in your assigned team. Refresh My Guards.')).toBeVisible();
  102 |   await page.getByRole('button', { name: 'View DTR' }).click();
  103 |   await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  104 |   await page.evaluate(async () => { teamEmpty = true; await loadGuards(); });
  105 |   await expect(page.locator('#dtrModal')).not.toHaveClass(/show/);
  106 |   await expect(page.locator('#dtrRecordsList')).toBeEmpty();
  107 | });
  108 | 
  109 | test('Inspector overview counts assigned Guards only', async ({ page }) => {
  110 |   await teamMocks(page);
  111 |   await page.goto('/inspector/dashboard.html');
  112 |   await expect(page.locator('#totalGuards')).toHaveText('1');
> 113 |   await expect(page.locator('#totalSchedules')).toHaveText('1');
      |                                                 ^ Error: expect(locator).toHaveText(expected) failed
  114 |   await expect(page.getByText('My assigned Guards')).toBeVisible();
  115 | });
  116 | 
  117 | test('Inspector acknowledges an assigned Guard incident through the secured RPC', async ({ page }) => {
  118 |   await teamMocks(page);
  119 |   await page.goto('/inspector/incidents.html');
  120 |   await expect(page.locator('#incidentTableBody')).toContainText('Assigned Guard');
  121 |   await page.locator('#incidentTableBody tr').click();
  122 |   await page.locator('#statusSelect').selectOption('acknowledged');
  123 |   await page.locator('#statusNote').fill('Response team notified.');
  124 |   await page.getByRole('button', { name: 'Save review' }).click();
  125 |   await expect.poll(() => page.evaluate(() => teamRpcCalls)).toEqual([{
  126 |     name: 'update_incident_status',
  127 |     params: {
  128 |       p_incident_id: 'incident-a',
  129 |       p_status: 'acknowledged',
  130 |       p_status_note: 'Response team notified.',
  131 |     },
  132 |   }]);
  133 | });
  134 | 
```