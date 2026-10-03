# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: schedule_lifecycle.spec.js >> after the first shift ends today remains available for the night shift
- Location: schedule_lifecycle.spec.js:187:1

# Error details

```
Error: expect(locator).toBeDisabled() failed

Locator: locator('#rosterGuard0')
Expected: disabled
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toBeDisabled" with timeout 5000ms
  - waiting for locator('#rosterGuard0')

```

```yaml
- link "Skip to main content":
  - /url: "#main-content"
- paragraph: Loading schedule…
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
  - heading "Duty Scheduling" [level=1]
  - text: Operations Head Operations Head
  - button "Sign out"
  - button "Switch to dark mode": Dark mode
- main:
  - text: Assign a 24-hour guard roster Shifting setup
  - combobox "Shifting setup" [disabled]:
    - option "Loading shifting setups…" [selected]
  - text: Schedule date
  - textbox "Schedule date": 2026-09-04
  - text: Deployment site
  - combobox "Deployment site":
    - option "Select location" [selected]
  - status
  - button "Reload saved setups"
  - group: Create a new shifting setup
  - status: Load saved shifting setups to view and assign a roster.
  - button "Assign all shifts" [disabled]
  - paragraph: Each Guard records their own Time In and Time Out. Next-day end times are marked (+1 day).
  - text: Scheduled guard shifts Month
  - textbox "Month"
  - text: DTR cut-off
  - combobox "DTR cut-off":
    - option "1st–15th" [selected]
    - option "16th–end of month"
  - text: Personnel
  - combobox "Personnel":
    - option "All personnel" [selected]
  - paragraph: Planned times only. The DTR report uses actual attendance. All times are Philippine time (UTC+8).
  - table:
    - rowgroup:
      - row "Personnel Duty date Scheduled IN Scheduled OUT Planned hours Deployment site Status & actions":
        - columnheader "Personnel"
        - columnheader "Duty date"
        - columnheader "Scheduled IN"
        - columnheader "Scheduled OUT"
        - columnheader "Planned hours"
        - columnheader "Deployment site"
        - columnheader "Status & actions"
    - rowgroup:
      - row "No schedule entries yet. Assign a roster above to get started.":
        - cell "No schedule entries yet. Assign a roster above to get started."
```

# Test source

```ts
  91  | async function showRows(page, rows) {
  92  |   await page.evaluate(async rows => { scheduleTest.rows = rows; await refreshSchedules(); }, rows);
  93  | }
  94  | const deleteButtons = page => page.locator('#scheduleTable [data-delete-schedule]');
  95  | async function saveSetup(page,name='Four-shift rotation',count='4'){
  96  |   await page.locator('#newRosterSetup summary').click();
  97  |   await page.locator('#rosterSetupName').fill(name);
  98  |   await page.locator('#rosterSetupCount').selectOption(count);
  99  |   await page.locator('#saveRosterSetup').click();
  100 |   await expect(page.locator('#rosterSetup')).toHaveValue('saved-setup-0');
  101 | }
  102 | async function fillRoster(page, date = '2099-01-01') {
  103 |   await page.locator('#rosterDate').fill(date);
  104 |   await page.locator('#rosterSite').selectOption('test-site');
  105 |   await page.locator('#rosterGuard0').selectOption('test-guard');
  106 |   await page.locator('#rosterGuard1').selectOption('peer');
  107 | }
  108 | 
  109 | test('roster is the only editor and the explanation panel is removed', async ({ page }) => {
  110 |   await expect(page.getByText('Custom personnel duty plan')).toHaveCount(0);
  111 |   await expect(page.locator('#guardUser,#scheduleMode,#overtimeEnabled')).toHaveCount(0);
  112 |   await expect(page.getByRole('button', {name:'Create schedule', exact:true})).toHaveCount(0);
  113 |   await expect(page.getByRole('button', {name:'Assign all shifts', exact:true})).toBeVisible();
  114 |   await expect(page.locator('.roster-dtr-guide')).toHaveCount(0);
  115 |   await expect(page.getByText('How the roster appears on the DTR')).toHaveCount(0);
  116 |   expect(await page.evaluate(() => typeof window.addSchedule)).toBe('undefined');
  117 | });
  118 | 
  119 | test('personnel and site loading work without custom-editor controls', async ({ page }) => {
  120 |   const errors=[]; page.on('pageerror',error=>errors.push(error.message));
  121 |   await page.evaluate(() => {
  122 |     const users=[{id:'loaded-guard',data:()=>({role:'user',firstName:'Loaded',lastName:'Guard',active:true})}];
  123 |     const sites=[{id:'loaded-site',data:()=>({label:'Loaded post',active:true})}];
  124 |     db.collection=name=>({get:async()=>users,where:()=>({get:async()=>sites})});
  125 |     loadGuards(); loadLocations();
  126 |   });
  127 |   await expect(page.locator('#rosterGuard0 option[value="loaded-guard"]')).toHaveCount(1);
  128 |   await expect(page.locator('#rosterSite option[value="loaded-site"]')).toHaveCount(1);
  129 |   expect(errors).toEqual([]);
  130 | });
  131 | 
  132 | test('an overnight roster remains on the starting date and first DTR cutoff', async ({ page }) => {
  133 |   await fillRoster(page, '2099-01-15');
  134 |   await expect(page.locator('#rosterPreview')).toContainText('Jan 1–15, 2099');
  135 |   await expect(page.locator('#rosterPreview')).toContainText('6:00 AM (+1)');
  136 |   await page.locator('#saveRoster').click();
  137 |   await expect(page.getByText('2 shifts assigned successfully.', {exact:true})).toBeVisible();
  138 |   await expect(page.locator('#scheduleTable tr')).toHaveCount(2);
  139 |   const night = page.locator('#scheduleTable tr').filter({hasText:'Guard Two'});
  140 |   await expect(night.locator('.schedule-dtr-time')).toHaveText(['6:00 PM','6:00 AM (+1)']);
  141 |   await expect(night).toContainText('12 hours');
  142 |   expect(await page.evaluate(() => scheduleTest.created[0].map(row => row.duty_date))).toEqual(['2099-01-15','2099-01-15']);
  143 |   await page.locator('#scheduleCutoff').selectOption('second');
  144 |   await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
  145 | });
  146 | 
  147 | for (const kind of ['missing contract dates', 'outside contract dates', 'overnight contract end', 'inactive guard', 'past date']) {
  148 |   test(kind + ' prevents a roster request', async ({ page }) => {
  149 |     await fillRoster(page);
  150 |     await page.evaluate(kind => {
  151 |       if (kind === 'missing contract dates') guards[0].employmentCategory = 'contract';
  152 |       if (kind === 'outside contract dates') Object.assign(guards[0], {employmentCategory:'contract',contractStartDate:'2099-01-02',contractEndDate:'2099-01-31'});
  153 |       if (kind === 'overnight contract end') Object.assign(guards.find(g=>g.id==='peer'), {employmentCategory:'contract',contractStartDate:'2099-01-01',contractEndDate:'2099-01-01'});
  154 |       if (kind === 'inactive guard') guards[0].active = false;
  155 |     }, kind);
  156 |     if (kind === 'past date') {
  157 |       await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  158 |       await page.locator('#rosterDate').fill('2026-09-03');
  159 |     }
  160 |     await page.locator('#saveRoster').click();
  161 |     await expect(page.locator('.sl-toast')).toBeVisible();
  162 |     expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster'))).toEqual([]);
  163 |   });
  164 | }
  165 | 
  166 | test('a failed save prevents duplicate submission and preserves selected guards', async ({ page }) => {
  167 |   await fillRoster(page);
  168 |   await page.evaluate(() => { scheduleTest.pendingCreate=true; scheduleTest.createError={message:'Schedule conflict. Choose different Guards.'}; });
  169 |   await page.locator('#saveRoster').click();
  170 |   await expect(page.locator('#saveRoster')).toBeDisabled();
  171 |   await expect(page.locator('#rosterSetup')).toBeDisabled();
  172 |   await page.evaluate(() => { document.getElementById('saveRoster').dispatchEvent(new Event('click')); finishTestCreate(); });
  173 |   await expect(page.getByText('Schedule conflict. Choose different Guards.',{exact:true})).toBeVisible();
  174 |   await expect(page.locator('#saveRoster')).toBeEnabled();
  175 |   await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  176 |   await expect(page.locator('#rosterGuard1')).toHaveValue('peer');
  177 |   expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').length)).toBe(1);
  178 | });
  179 | 
  180 | test('an incomplete RPC response cannot report a saved roster', async ({ page }) => {
  181 |   await fillRoster(page); await page.evaluate(() => scheduleTest.malformedResult=true);
  182 |   await page.locator('#saveRoster').click();
  183 |   await expect(page.getByText('Could not confirm all assignments. Refresh the schedule before retrying.',{exact:true})).toBeVisible();
  184 |   await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  185 | });
  186 | 
  187 | test('after the first shift ends today remains available for the night shift', async ({ page }) => {
  188 |   await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  189 |   await page.reload();
  190 |   await expect(page.locator('#rosterDate')).toHaveValue('2026-09-04');
> 191 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
      |                                               ^ Error: expect(locator).toBeDisabled() failed
  192 |   await expect(page.locator('#rosterGuard1')).toBeEnabled();
  193 | });
  194 | 
  195 | test('today at 7 PM assigns only the ongoing night shift, preserving its actual overnight hours', async({page})=>{
  196 |   await page.clock.setFixedTime(new Date('2026-09-04T11:00:00Z'));
  197 |   await page.locator('#rosterDate').fill('2026-09-04');
  198 |   await page.locator('#rosterSite').selectOption('test-site');
  199 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
  200 |   await page.locator('#rosterGuard1').selectOption('peer');
  201 |   await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  202 |   await expect(page.getByText('1 shift assigned successfully.',{exact:true})).toBeVisible();
  203 |   expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer']);
  204 |   expect(await page.evaluate(()=>scheduleTest.created[0].map(row=>[row.start_at,row.end_at]))).toEqual([['2026-09-04T10:00:00.000Z','2026-09-04T22:00:00.000Z']]);
  205 | });
  206 | 
  207 | test('three-shift setup at exactly 2 PM skips the completed morning and requires both remaining guards', async({page})=>{
  208 |   await page.clock.setFixedTime(new Date('2026-09-04T06:00:00Z'));
  209 |   await page.locator('#rosterDate').fill('2026-09-04');
  210 |   await page.locator('#rosterSetup').selectOption('3');
  211 |   await page.locator('#rosterSite').selectOption('test-site');
  212 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
  213 |   await page.locator('#rosterGuard1').selectOption('peer');
  214 |   await page.locator('#rosterGuard2').selectOption('third');
  215 |   await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  216 |   await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  217 |   expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer','third']);
  218 |   await page.locator('#rosterDate').fill('2026-09-05');
  219 |   await expect(page.locator('#rosterGuard0')).toBeEnabled();
  220 |   await expect(page.getByRole('button',{name:'Assign all shifts'})).toBeVisible();
  221 | });
  222 | 
  223 | test('attendance reports completion and requests protect period history', async ({ page }, info) => {
  224 |   await showRows(page, [record(unusedId, 'Unused duty'),
  225 |     record('open', 'On duty', { attendance_sessions: { id: 'session', status: 'open' } }),
  226 |     record('closed', 'Done', { attendance_sessions: [{ status: 'closed' }], marked_done: true }),
  227 |     record('report', 'Reported', { accomplishment_reports: { id: 'report' } }),
  228 |     record('change', 'Requested', { shift_swap_requests: [{ id: 'change' }] }),
  229 |     record('swap-target', 'Exchange target', { swap_target_requests: [{ id: 'exchange' }] }),
  230 |     record('legacy', 'Legacy', { marked_done: true })]);
  231 |   await expect(deleteButtons(page)).toHaveCount(1);
  232 |   await expect(page.locator('#scheduleTable').getByText('DTR protected', { exact: true })).toHaveCount(2);
  233 |   for (const label of ['Report protected', 'Approval history', 'History protected']) await expect(page.locator('#scheduleTable')).toContainText(label);
  234 |   await expect(page.locator('#scheduleTable').getByText('Approval history', { exact: true })).toHaveCount(2);
  235 |   await page.locator('.schedule-table').screenshot({ path: info.outputPath('schedule-history-protection.png') });
  236 | });
  237 | 
  238 | test('schedule loading explicitly selects both swap relationships in one query', async ({ page }, info) => {
  239 |   await showRows(page, [record(unusedId, 'Available duty'), record('target', 'Target duty', {swap_target_requests:[{id:'swap'}]})]);
  240 |   await expect(page.locator('#scheduleTable')).toContainText('Available duty');
  241 |   await expect(page.locator('#scheduleTable')).toContainText('Target duty');
  242 |   await expect(page.getByRole('button',{name:'Retry loading schedules'})).toHaveCount(0);
  243 |   const reads=await page.evaluate(()=>scheduleTest.calls.filter(call=>call.table==='schedules'));
  244 |   expect(reads).toHaveLength(1);
  245 |   expect(reads[0].columns).toContain('shift_swap_requests:shift_swap_requests!shift_swap_requests_requested_schedule_id_fkey(id)');
  246 |   expect(reads[0].columns).toContain('swap_target_requests:shift_swap_requests!shift_swap_requests_target_schedule_id_fkey(id)');
  247 |   await expect(deleteButtons(page)).toHaveCount(1);
  248 |   await page.locator('.schedule-table').screenshot({path:info.outputPath('schedule-both-swap-relationships.png')});
  249 | });
  250 | 
  251 | test('schedule names prefer the current profile and safely preserve historical names', async ({ page }) => {
  252 |   await showRows(page, [record('test-guard', 'Old profile name'),
  253 |     record(unusedId, '<img src=x onerror=alert(1)> Former guard')]);
  254 |   await expect(page.locator('#scheduleTable')).toContainText('Test guard');
  255 |   await expect(page.locator('#scheduleTable')).not.toContainText('Old profile name');
  256 |   await expect(page.locator('#scheduleTable')).toContainText('<img src=x onerror=alert(1)> Former guard');
  257 |   await expect(page.locator('#scheduleTable img')).toHaveCount(0);
  258 | });
  259 | 
  260 | test('cancelled deletion leaves the period and confirmed deletion has a busy state', async ({ page }) => {
  261 |   await showRows(page, [record(unusedId, 'Unused duty')]);
  262 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  263 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([]);
  264 |   await page.evaluate(() => { scheduleTest.pendingDelete = true; });
  265 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  266 |   await expect(deleteButtons(page)).toBeDisabled(); await expect(deleteButtons(page)).toContainText('Deleting');
  267 |   await page.evaluate(() => finishTestDelete()); await expect(deleteButtons(page)).toHaveCount(0);
  268 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([{ rpc: 'delete_unused_schedule', args: { p_schedule_id: unusedId } }]);
  269 | });
  270 | 
  271 | test('concurrent Time In protects the schedule with readable error feedback', async ({ page }) => {
  272 |   await showRows(page, [record(unusedId, 'Duty just started')]);
  273 |   await page.evaluate(() => {
  274 |     scheduleTest.deleteError = { code: 'P0001', details: 'SCHEDULE_ATTENDANCE_HISTORY', message: "This schedule has recorded attendance and must be kept for the guard's DTR." };
  275 |     scheduleTest.rows[0].attendance_sessions = { id: 'new-session', status: 'open' };
  276 |   });
  277 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  278 |   await expect(page.getByText("This schedule has recorded attendance and must be kept for the guard's DTR.", { exact: true })).toBeVisible();
  279 |   await expect(page.locator('#scheduleTable')).toContainText('DTR protected'); await expect(deleteButtons(page)).toHaveCount(0);
  280 | });
  281 | 
  282 | test('legacy foreign-key errors do not expose SQL details', async ({ page }) => {
  283 |   await showRows(page, [record(unusedId, 'Linked duty')]);
  284 |   await page.evaluate(() => { scheduleTest.deleteError = { code: '23503', message: 'violates foreign key constraint attendance_sessions_schedule_id_fkey' }; });
  285 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  286 |   await expect(page.getByText('This schedule has linked duty records and must be kept for historical records.', { exact: true })).toBeVisible();
  287 |   await expect(page.getByText(/violates foreign key constraint/)).toHaveCount(0);
  288 | });
  289 | 
  290 | test('failed history load offers retry and older responses cannot erase newer protection', async ({ page }) => {
  291 |   await showRows(page, [record(unusedId, 'Existing duty')]);
```