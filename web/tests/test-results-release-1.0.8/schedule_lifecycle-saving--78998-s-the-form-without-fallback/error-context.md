# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: schedule_lifecycle.spec.js >> saving disables repeat clicks and a migration failure retains the form without fallback
- Location: schedule_lifecycle.spec.js:143:1

# Error details

```
Error: expect(locator).toBeDisabled() failed

Locator: getByRole('button', { name: 'Create schedule', exact: true })
Expected: disabled
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toBeDisabled" with timeout 5000ms
  - waiting for getByRole('button', { name: 'Create schedule', exact: true })

```

```yaml
- link "Skip to main content":
  - /url: "#main-content"
- complementary:
  - text: Control center
  - paragraph: Admin Portal
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
  - text: Admin Console
  - heading "Duty Scheduling" [level=1]
  - text: Admin Admin
  - button "Sign out"
  - button "Switch to dark mode": Dark mode
- main:
  - text: Add schedule entry 1
  - heading "Personnel" [level=2]
  - text: Duty personnel
  - combobox "Duty personnel":
    - option "Select personnel"
    - option "Test guard" [selected]
    - option "Inspector"
  - text: Personnel name
  - textbox "Personnel name":
    - /placeholder: Select personnel above
    - text: Test guard
  - text: Duty category
  - combobox "Duty category" [disabled]:
    - option "Not applicable"
    - option "Regular" [selected]
    - option "Contract"
  - text: "2"
  - heading "Assignment" [level=2]
  - text: Deployment site
  - combobox "Deployment site":
    - option "Select location"
    - option "Test post" [selected]
  - text: Guards clock in and out at this site. 3
  - heading "DTR duty plan" [level=2]
  - text: Duty date
  - textbox "Duty date": 2099-01-01
  - text: "DTR cut-off: Jan 1–15, 2099 Time recording"
  - combobox "Time recording":
    - option "Separate Morning / Afternoon" [selected]
    - option "Continuous shift"
  - checkbox "Morning" [checked]
  - text: Morning Time In
  - textbox "Time In": 08:00
  - text: Time Out
  - textbox "Time Out": 12:00
  - checkbox "Afternoon" [checked]
  - text: Afternoon Time In
  - textbox "Time In": 13:00
  - text: Time Out
  - textbox "Time Out": 17:00
  - checkbox "Overtime"
  - text: Overtime Time In
  - textbox "Time In" [disabled]: 17:00
  - text: Time Out
  - textbox "Time Out" [disabled]: 19:00
  - checkbox "Overtime starts the following day" [disabled]
  - text: Overtime starts the following day
  - paragraph: Each enabled period needs its own actual Time In and Time Out. Disabled periods are not scheduled.
  - status: 8 hours planned · 2 periods
  - button "Saving duty plan…" [disabled]
  - text: Scheduled duty · DTR layout Month
  - textbox "Month": 2099-01
  - text: DTR cut-off
  - combobox "DTR cut-off":
    - option "1st–15th" [selected]
    - option "16th–end of month"
  - text: Personnel
  - combobox "Personnel":
    - option "All personnel" [selected]
    - option "Test guard"
    - option "Inspector"
  - paragraph: Planned times only. The DTR report uses actual attendance. All times are Philippine time (UTC+8).
  - table:
    - rowgroup:
      - row "Personnel Duty date Morning Afternoon Overtime Planned hours Deployment site Periods & actions":
        - columnheader "Personnel"
        - columnheader "Duty date"
        - columnheader "Morning"
        - columnheader "Afternoon"
        - columnheader "Overtime"
        - columnheader "Planned hours"
        - columnheader "Deployment site"
        - columnheader "Periods & actions"
      - row "IN OUT IN OUT IN OUT":
        - columnheader "IN"
        - columnheader "OUT"
        - columnheader "IN"
        - columnheader "OUT"
        - columnheader "IN"
        - columnheader "OUT"
    - rowgroup:
      - row "No schedule entries yet. Add one above to get started.":
        - cell "No schedule entries yet. Add one above to get started."
```

# Test source

```ts
  47  |       }; },
  48  |     };
  49  |   });
  50  |   await page.goto('/admin/schedule.html');
  51  |   await page.addStyleTag({ content: '#loadingScreen { display:none!important }' });
  52  |   await page.evaluate(() => {
  53  |     guards.push({ id: 'test-guard', role: 'user', name: 'Test guard', active: true, employmentCategory: 'regular' },
  54  |       { id: 'test-inspector', role: 'inspector', name: 'Inspector', active: true });
  55  |     locations.push({ id: 'test-site', label: 'Test post', address: 'Test address' });
  56  |     document.querySelector('#guardUser').innerHTML = '<option value="">Select personnel</option><option value="test-guard">Test guard</option><option value="test-inspector">Inspector</option>';
  57  |     document.querySelector('#scheduleLocation').innerHTML = '<option value="">Select location</option><option value="test-site">Test post</option>';
  58  |     document.querySelector('#schedulePersonnelFilter').innerHTML = '<option value="">All personnel</option><option value="test-guard">Test guard</option><option value="test-inspector">Inspector</option>';
  59  |     window.setDefaultScheduleDates(); window.setScheduleListPeriod('2099-01-01');
  60  |   });
  61  | });
  62  | async function fillPersonnel(page, id = 'test-guard') {
  63  |   await page.locator('#guardUser').selectOption(id);
  64  |   await page.locator('#scheduleLocation').selectOption('test-site');
  65  |   await page.locator('#startDate').fill('2099-01-01');
  66  | }
  67  | async function showRows(page, rows) {
  68  |   await page.evaluate(async rows => { scheduleTest.rows = rows; await refreshSchedules(); }, rows);
  69  | }
  70  | const createButton = page => page.getByRole('button', { name: 'Create schedule', exact: true });
  71  | const deleteButtons = page => page.locator('#scheduleTable [data-delete-schedule]');
  72  | 
  73  | test('split duty saves one atomic RPC and groups six DTR columns on one duty date', async ({ page }, info) => {
  74  |   await fillPersonnel(page);
  75  |   await expect(page.locator('#shiftSummary')).toHaveText('8 hours planned · 2 periods');
  76  |   await page.locator('#overtimeEnabled').check();
  77  |   await createButton(page).click();
  78  |   await expect(page.getByText('Duty plan saved: 3 periods for Jan 1, 2099.', { exact: true })).toBeVisible();
  79  |   const calls = await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'create_dtr_schedule'));
  80  |   expect(calls).toEqual([{ rpc: 'create_dtr_schedule', args: {
  81  |     p_user_id: 'test-guard', p_location_id: 'test-site', p_duty_date: '2099-01-01', p_periods: [
  82  |       { period: 'morning', start_time: '08:00', end_time: '12:00', next_day: false },
  83  |       { period: 'afternoon', start_time: '13:00', end_time: '17:00', next_day: false },
  84  |       { period: 'overtime', start_time: '17:00', end_time: '19:00', next_day: false },
  85  |     ],
  86  |   } }]);
  87  |   await expect(page.locator('#scheduleTable tr')).toHaveCount(1);
  88  |   await expect(page.locator('#scheduleTable .schedule-dtr-time')).toHaveText(['8:00 AM', '12:00 PM', '1:00 PM', '5:00 PM', '5:00 PM', '7:00 PM']);
  89  |   await expect(page.locator('#scheduleTable')).toContainText('10 hours');
  90  |   await expect(deleteButtons(page)).toHaveCount(3);
  91  |   await expect(page.locator('#guardUser')).toHaveValue('');
  92  |   await expect(page.locator('#overtimeEnabled')).not.toBeChecked();
  93  |   await page.locator('.schedule-table').screenshot({ path: info.outputPath('split-three-periods.png') });
  94  | });
  95  | 
  96  | test('overnight continuous duty and following-day OT retain the first cutoff', async ({ page }) => {
  97  |   await fillPersonnel(page);
  98  |   await page.locator('#startDate').fill('2099-01-15');
  99  |   await page.locator('#scheduleMode').selectOption('continuous');
  100 |   await page.locator('#startTime').fill('20:00'); await page.locator('#endTime').fill('05:00');
  101 |   await page.locator('#overtimeEnabled').check(); await page.locator('#overtimeIn').fill('05:00');
  102 |   await page.locator('#overtimeOut').fill('07:00'); await page.locator('#overtimeNextDay').check();
  103 |   await createButton(page).click();
  104 |   await expect(page.locator('#scheduleCutoff')).toHaveValue('first');
  105 |   await expect(page.locator('#scheduleTable .schedule-dtr-time')).toHaveText(['—', '5:00 AM (+1)', '8:00 PM', '—', '5:00 AM (+1)', '7:00 AM (+1)']);
  106 |   const rows = await page.evaluate(() => scheduleTest.created[0]);
  107 |   expect(rows.map(row => row.duty_date)).toEqual(['2099-01-15', '2099-01-15']);
  108 |   expect(rows[1].start_at).toBe('2099-01-15T21:00:00.000Z');
  109 |   await page.locator('#scheduleCutoff').selectOption('second');
  110 |   await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
  111 | });
  112 | 
  113 | test('after-hours defaults move the whole plan while afternoon-only can remain today', async ({ page }) => {
  114 |   await page.clock.setFixedTime(new Date('2026-09-04T04:00:00Z'));
  115 |   await page.evaluate(() => setDefaultScheduleDates());
  116 |   await expect(page.locator('#startDate')).toHaveValue('2026-09-05');
  117 |   await page.locator('#morningEnabled').uncheck();
  118 |   await page.evaluate(() => setDefaultScheduleDates());
  119 |   await expect(page.locator('#startDate')).toHaveValue('2026-09-04');
  120 |   await expect(page.locator('#morningIn')).toBeDisabled();
  121 |   await page.clock.setFixedTime(new Date('2026-09-04T09:00:00Z'));
  122 |   await page.evaluate(() => clearForm());
  123 |   await expect(page.locator('#startDate')).toHaveValue('2026-09-05');
  124 | });
  125 | 
  126 | for (const invalid of ['equal times', 'overlap', 'no periods', 'expired morning', 'inactive guard']) {
  127 |   test(`${invalid} cannot save a partial plan`, async ({ page }) => {
  128 |     await fillPersonnel(page);
  129 |     if (invalid === 'equal times') await page.locator('#morningOut').fill('08:00');
  130 |     if (invalid === 'overlap') await page.locator('#morningOut').fill('14:00');
  131 |     if (invalid === 'no periods') { await page.locator('#morningEnabled').uncheck(); await page.locator('#afternoonEnabled').uncheck(); }
  132 |     if (invalid === 'expired morning') {
  133 |       await page.clock.setFixedTime(new Date('2026-09-04T04:00:00Z'));
  134 |       await page.locator('#startDate').fill('2026-09-04');
  135 |     }
  136 |     if (invalid === 'inactive guard') await page.evaluate(() => { guards[0].active = false; });
  137 |     await createButton(page).click();
  138 |     await expect(page.locator('.sl-toast')).toBeVisible();
  139 |     expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'create_dtr_schedule'))).toEqual([]);
  140 |   });
  141 | }
  142 | 
  143 | test('saving disables repeat clicks and a migration failure retains the form without fallback', async ({ page }) => {
  144 |   await fillPersonnel(page);
  145 |   await page.evaluate(() => { scheduleTest.pendingCreate = true; scheduleTest.createError = { code: 'PGRST202' }; });
  146 |   await createButton(page).click();
> 147 |   await expect(createButton(page)).toBeDisabled();
      |                                    ^ Error: expect(locator).toBeDisabled() failed
  148 |   await expect(createButton(page)).toContainText('Saving duty plan');
  149 |   await page.evaluate(() => { addSchedule(document.querySelector('.btn-add-schedule')); finishTestCreate(); });
  150 |   await expect(page.getByText(/DTR scheduling is not enabled on this database yet/)).toBeVisible();
  151 |   await expect(createButton(page)).toBeEnabled();
  152 |   await expect(page.locator('#guardUser')).toHaveValue('test-guard');
  153 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'create_dtr_schedule').length)).toBe(1);
  154 |   expect(await page.evaluate(() => scheduleTest.created)).toEqual([]);
  155 | });
  156 | 
  157 | test('an unexpected RPC result never reports false success', async ({ page }) => {
  158 |   await fillPersonnel(page); await page.evaluate(() => { scheduleTest.malformedResult = true; });
  159 |   await createButton(page).click();
  160 |   await expect(page.getByText(/saved plan could not be confirmed/)).toBeVisible();
  161 |   await expect(page.getByText(/^Duty plan saved:/)).toHaveCount(0);
  162 |   await expect(page.locator('#guardUser')).toHaveValue('test-guard');
  163 | });
  164 | 
  165 | test('Inspector assignment uses one continuous period without Guard DTR cells', async ({ page }) => {
  166 |   await fillPersonnel(page, 'test-inspector');
  167 |   await expect(page.locator('#scheduleMode')).toBeDisabled();
  168 |   await expect(page.locator('#splitPeriods')).toBeHidden(); await expect(page.locator('#overtimePeriod')).toBeHidden();
  169 |   await createButton(page).click();
  170 |   const request = await page.evaluate(() => scheduleTest.calls.find(call => call.rpc === 'create_dtr_schedule').args);
  171 |   expect(request.p_periods).toEqual([{ period: 'auto', start_time: '08:00', end_time: '17:00', next_day: false }]);
  172 |   await expect(page.locator('#scheduleTable')).toContainText('Inspector assignment · No attendance DTR');
  173 | });
  174 | 
  175 | test('create delete and recreate an unused split plan keeps all intended periods', async ({ page }) => {
  176 |   await fillPersonnel(page); await createButton(page).click();
  177 |   const initial = await page.evaluate(() => scheduleTest.created[0]);
  178 |   for (let remaining = 2; remaining > 0; remaining -= 1) {
  179 |     await deleteButtons(page).first().click();
  180 |     await page.getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true }).click();
  181 |     await expect(deleteButtons(page)).toHaveCount(remaining - 1);
  182 |   }
  183 |   await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
  184 |   await fillPersonnel(page); await createButton(page).click();
  185 |   await expect(deleteButtons(page)).toHaveCount(2);
  186 |   const recreated = await page.evaluate(() => scheduleTest.created[1]);
  187 |   expect(recreated.map(row => [row.start_at, row.end_at, row.dtr_period])).toEqual(initial.map(row => [row.start_at, row.end_at, row.dtr_period]));
  188 | });
  189 | 
  190 | test('attendance reports completion and requests protect period history', async ({ page }, info) => {
  191 |   await showRows(page, [record(unusedId, 'Unused duty'),
  192 |     record('open', 'On duty', { attendance_sessions: { id: 'session', status: 'open' } }),
  193 |     record('closed', 'Done', { attendance_sessions: [{ status: 'closed' }], marked_done: true }),
  194 |     record('report', 'Reported', { accomplishment_reports: { id: 'report' } }),
  195 |     record('change', 'Requested', { shift_swap_requests: [{ id: 'change' }] }),
  196 |     record('legacy', 'Legacy', { marked_done: true })]);
  197 |   await expect(deleteButtons(page)).toHaveCount(1);
  198 |   await expect(page.locator('#scheduleTable').getByText('DTR protected', { exact: true })).toHaveCount(2);
  199 |   for (const label of ['Report protected', 'Approval history', 'History protected']) await expect(page.locator('#scheduleTable')).toContainText(label);
  200 |   await page.locator('.schedule-table').screenshot({ path: info.outputPath('schedule-history-protection.png') });
  201 | });
  202 | 
  203 | test('cancelled deletion leaves the period and confirmed deletion has a busy state', async ({ page }) => {
  204 |   await showRows(page, [record(unusedId, 'Unused duty')]);
  205 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  206 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc))).toEqual([]);
  207 |   await page.evaluate(() => { scheduleTest.pendingDelete = true; });
  208 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true }).click();
  209 |   await expect(deleteButtons(page)).toBeDisabled(); await expect(deleteButtons(page)).toContainText('Deleting');
  210 |   await page.evaluate(() => finishTestDelete()); await expect(deleteButtons(page)).toHaveCount(0);
  211 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc))).toEqual([{ rpc: 'delete_unused_schedule', args: { p_schedule_id: unusedId } }]);
  212 | });
  213 | 
  214 | test('concurrent Time In protects the schedule with readable error feedback', async ({ page }) => {
  215 |   await showRows(page, [record(unusedId, 'Duty just started')]);
  216 |   await page.evaluate(() => {
  217 |     scheduleTest.deleteError = { code: 'P0001', details: 'SCHEDULE_ATTENDANCE_HISTORY', message: "This schedule has recorded attendance and must be kept for the guard's DTR." };
  218 |     scheduleTest.rows[0].attendance_sessions = { id: 'new-session', status: 'open' };
  219 |   });
  220 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true }).click();
  221 |   await expect(page.getByText("This schedule has recorded attendance and must be kept for the guard's DTR.", { exact: true })).toBeVisible();
  222 |   await expect(page.locator('#scheduleTable')).toContainText('DTR protected'); await expect(deleteButtons(page)).toHaveCount(0);
  223 | });
  224 | 
  225 | test('legacy foreign-key errors do not expose SQL details', async ({ page }) => {
  226 |   await showRows(page, [record(unusedId, 'Linked duty')]);
  227 |   await page.evaluate(() => { scheduleTest.deleteError = { code: '23503', message: 'violates foreign key constraint attendance_sessions_schedule_id_fkey' }; });
  228 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true }).click();
  229 |   await expect(page.getByText('This schedule has linked duty records and must be kept for historical records.', { exact: true })).toBeVisible();
  230 |   await expect(page.getByText(/violates foreign key constraint/)).toHaveCount(0);
  231 | });
  232 | 
  233 | test('failed history load offers retry and older responses cannot erase newer protection', async ({ page }) => {
  234 |   await showRows(page, [record(unusedId, 'Existing duty')]);
  235 |   await page.evaluate(async () => { scheduleTest.readError = { message: 'Temporary network error' }; await refreshSchedules(); });
  236 |   await expect(deleteButtons(page)).toHaveCount(0);
  237 |   await page.evaluate(() => { scheduleTest.readError = null; });
  238 |   await page.getByRole('button', { name: 'Retry loading schedules' }).click(); await expect(deleteButtons(page)).toHaveCount(1);
  239 |   await page.evaluate(async fresh => {
  240 |     const resolvers = []; appSupabase.from = () => ({ select: () => ({ order: () => new Promise(resolve => resolvers.push(resolve)) }) });
  241 |     const first = refreshSchedules(), second = refreshSchedules();
  242 |     resolvers[1]({ data: [fresh] }); await second; resolvers[0]({ data: [] }); await first;
  243 |   }, record(unusedId, 'Newer protected row', { attendance_sessions: { status: 'open' } }));
  244 |   await expect(page.locator('#scheduleTable')).toContainText('Newer protected row');
  245 |   await expect(page.locator('#scheduleTable')).toContainText('DTR protected');
  246 | });
  247 | 
```