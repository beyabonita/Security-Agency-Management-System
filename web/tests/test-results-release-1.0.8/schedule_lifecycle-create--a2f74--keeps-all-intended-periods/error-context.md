# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: schedule_lifecycle.spec.js >> create delete and recreate an unused split plan keeps all intended periods
- Location: schedule_lifecycle.spec.js:175:1

# Error details

```
Test timeout of 30000ms exceeded.
```

```
Error: locator.click: Test timeout of 30000ms exceeded.
Call log:
  - waiting for getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true })

```

# Page snapshot

```yaml
- generic [ref=e1]:
  - link "Skip to main content" [ref=e2] [cursor=pointer]:
    - /url: "#main-content"
  - generic [ref=e3]:
    - complementary [ref=e4]:
      - generic [ref=e5]:
        - generic [ref=e6]: Control center
        - paragraph [ref=e7]: Admin Portal
        - paragraph [ref=e8]: Security Agency Management System
      - navigation [ref=e9]:
        - generic [ref=e10]: Manage
        - link "Dashboard" [ref=e11] [cursor=pointer]:
          - /url: dashboard.html
          - generic [ref=e12]: dashboard
          - text: Dashboard
        - link "Personnel" [ref=e13] [cursor=pointer]:
          - /url: users.html
          - generic [ref=e14]: groups
          - text: Personnel
        - link "Deployment Sites" [ref=e15] [cursor=pointer]:
          - /url: locations.html
          - generic [ref=e16]: location_on
          - text: Deployment Sites
        - link "Schedule" [ref=e17]:
          - /url: schedule.html
          - generic [ref=e18]: calendar_month
          - text: Schedule
        - link "Incidents" [ref=e19] [cursor=pointer]:
          - /url: incidents.html
          - generic [ref=e20]: emergency
          - text: Incidents
        - link "Duty requests" [ref=e21] [cursor=pointer]:
          - /url: swaps.html
          - generic [ref=e22]: swap_horiz
          - text: Duty requests
      - generic [ref=e23]: TwentyTwenty Security Agency
    - generic [ref=e24]:
      - banner [ref=e25]:
        - generic [ref=e27]:
          - generic [ref=e28]: Admin Console
          - heading "Duty Scheduling" [level=1] [ref=e29]
        - generic [ref=e30]:
          - generic [ref=e31]: Admin
          - generic [ref=e32]: Admin
          - button "Sign out" [ref=e33] [cursor=pointer]
          - button "Switch to dark mode" [ref=e34] [cursor=pointer]:
            - generic [ref=e35]: dark_mode
            - generic [ref=e36]: Dark mode
      - main [ref=e37]:
        - generic [ref=e38]: Add schedule entry
        - generic [ref=e39]:
          - generic [ref=e40]:
            - generic [ref=e41]:
              - generic [ref=e42]: "1"
              - heading "Personnel" [level=2] [ref=e43]
            - generic [ref=e44]:
              - generic [ref=e45]:
                - generic [ref=e46]: Duty personnel
                - combobox "Duty personnel" [ref=e47]:
                  - option "Select personnel" [selected]
                  - option "Test guard"
                  - option "Inspector"
              - generic [ref=e48]:
                - generic [ref=e49]: Personnel name
                - textbox "Personnel name" [ref=e50]:
                  - /placeholder: Select personnel above
              - generic [ref=e51]:
                - generic [ref=e52]: Duty category
                - combobox "Duty category" [disabled] [ref=e53]:
                  - option "Not applicable" [selected]
                  - option "Regular"
                  - option "Contract"
          - generic [ref=e54]:
            - generic [ref=e55]:
              - generic [ref=e56]: "2"
              - heading "Assignment" [level=2] [ref=e57]
            - generic [ref=e59]:
              - generic [ref=e60]: Deployment site
              - combobox "Deployment site" [ref=e61]:
                - option "Select location" [selected]
                - option "Test post"
              - generic [ref=e62]: Guards clock in and out at this site.
          - generic [ref=e63]:
            - generic [ref=e64]:
              - generic [ref=e65]: "3"
              - heading "DTR duty plan" [level=2] [ref=e66]
            - generic [ref=e67]:
              - generic [ref=e68]:
                - generic [ref=e69]:
                  - generic [ref=e70]: Duty date
                  - textbox "Duty date" [ref=e71]: 2026-09-04
                  - generic [ref=e72]: "DTR cut-off: Sep 1–15, 2026"
                - generic [ref=e73]:
                  - generic [ref=e74]: Time recording
                  - combobox "Time recording" [ref=e75]:
                    - option "Separate Morning / Afternoon" [selected]
                    - option "Continuous shift"
              - generic [ref=e76]:
                - generic [ref=e77]:
                  - generic [ref=e78] [cursor=pointer]:
                    - checkbox "Morning" [checked] [ref=e79]
                    - text: Morning
                  - generic [ref=e80]:
                    - generic [ref=e81]: Time In
                    - textbox "Time In" [ref=e82]: 08:00
                  - generic [ref=e83]:
                    - generic [ref=e84]: Time Out
                    - textbox "Time Out" [ref=e85]: 12:00
                - generic [ref=e86]:
                  - generic [ref=e87] [cursor=pointer]:
                    - checkbox "Afternoon" [checked] [ref=e88]
                    - text: Afternoon
                  - generic [ref=e89]:
                    - generic [ref=e90]: Time In
                    - textbox "Time In" [ref=e91]: 13:00
                  - generic [ref=e92]:
                    - generic [ref=e93]: Time Out
                    - textbox "Time Out" [ref=e94]: 17:00
              - generic [ref=e95]:
                - generic [ref=e96] [cursor=pointer]:
                  - checkbox "Overtime" [ref=e97]
                  - text: Overtime
                - generic [ref=e98]:
                  - generic [ref=e99]: Time In
                  - textbox "Time In" [disabled] [ref=e100]: 17:00
                - generic [ref=e101]:
                  - generic [ref=e102]: Time Out
                  - textbox "Time Out" [disabled] [ref=e103]: 19:00
                - generic [ref=e104] [cursor=pointer]:
                  - checkbox "Overtime starts the following day" [disabled] [ref=e105]
                  - text: Overtime starts the following day
              - paragraph [ref=e106]: Each enabled period needs its own actual Time In and Time Out. Disabled periods are not scheduled.
              - status [ref=e107]: 8 hours planned · 2 periods
          - button "Create schedule" [ref=e109] [cursor=pointer]:
            - generic [ref=e110]: add
            - text: Create schedule
        - generic [ref=e111]: Scheduled duty · DTR layout
        - generic [ref=e112]:
          - generic [ref=e113]:
            - generic [ref=e114]:
              - generic [ref=e115]: Month
              - textbox "Month" [ref=e116]: 2099-01
            - generic [ref=e117]:
              - generic [ref=e118]: DTR cut-off
              - combobox "DTR cut-off" [ref=e119]:
                - option "1st–15th" [selected]
                - option "16th–end of month"
            - generic [ref=e120]:
              - generic [ref=e121]: Personnel
              - combobox "Personnel" [ref=e122]:
                - option "All personnel"
                - option "Test guard" [selected]
                - option "Inspector"
          - paragraph [ref=e123]: Planned times only. The DTR report uses actual attendance. All times are Philippine time (UTC+8).
          - generic "Scheduled duty in DTR columns" [ref=e124]:
            - table [ref=e125]:
              - rowgroup [ref=e126]:
                - row [ref=e127]:
                  - columnheader "Personnel" [ref=e128]
                  - columnheader "Duty date" [ref=e129]
                  - columnheader "Morning" [ref=e130]
                  - columnheader "Afternoon" [ref=e131]
                  - columnheader "Overtime" [ref=e132]
                  - columnheader "Planned hours" [ref=e133]
                  - columnheader "Deployment site" [ref=e134]
                  - columnheader "Periods & actions" [ref=e135]
                - row [ref=e136]:
                  - columnheader "IN" [ref=e137]
                  - columnheader "OUT" [ref=e138]
                  - columnheader "IN" [ref=e139]
                  - columnheader "OUT" [ref=e140]
                  - columnheader "IN" [ref=e141]
                  - columnheader "OUT" [ref=e142]
              - rowgroup [ref=e143]:
                - row [ref=e144]:
                  - cell [ref=e145]:
                    - strong [ref=e146]: Test guard
                  - cell "Jan 1, 2099" [ref=e147]
                  - cell "8:00 AM" [ref=e148]
                  - cell "12:00 PM" [ref=e149]
                  - cell "1:00 PM" [ref=e150]
                  - cell "5:00 PM" [ref=e151]
                  - cell "Not scheduled" [ref=e152]: —
                  - cell "Not scheduled" [ref=e153]: —
                  - cell "8 hours" [ref=e154]
                  - cell [ref=e155]:
                    - generic [ref=e156]:
                      - generic [ref=e157]: location_on
                      - text: Test post
                  - cell [ref=e158]:
                    - generic [ref=e159]:
                      - generic [ref=e160]:
                        - strong [ref=e161]: Morning
                        - text: Scheduled
                      - button "Delete Morning period" [ref=e162] [cursor=pointer]: Delete
                    - generic [ref=e163]:
                      - generic [ref=e164]:
                        - strong [ref=e165]: Afternoon
                        - text: Scheduled
                      - button "Delete Afternoon period" [ref=e166] [cursor=pointer]: Delete
  - status
  - dialog [ref=e168]:
    - generic [ref=e169]:
      - generic [ref=e170]: delete
      - generic [ref=e171]:
        - heading "Delete duty period" [level=2] [ref=e172]
        - paragraph [ref=e173]: Delete Morning on Jan 1, 2099? Only this unused period will be removed; other periods and recorded attendance are kept.
      - button "Close" [ref=e174] [cursor=pointer]:
        - generic [ref=e175]: close
    - generic [ref=e176]:
      - button "Cancel" [ref=e177] [cursor=pointer]
      - button "Delete period" [active] [ref=e178] [cursor=pointer]
```

# Test source

```ts
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
  147 |   await expect(createButton(page)).toBeDisabled();
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
> 180 |     await page.getByRole('dialog').getByRole('button', { name: 'Delete schedule', exact: true }).click();
      |                                                                                                  ^ Error: locator.click: Test timeout of 30000ms exceeded.
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
  248 | test('linked-record realtime refreshes protection without duplicate subscriptions', async ({ page }) => {
  249 |   await showRows(page, [record(unusedId, 'Live duty')]);
  250 |   await page.evaluate(() => { loadSchedules(); loadSchedules(); });
  251 |   expect(await page.evaluate(() => scheduleTest.events.map(event => event.table))).toEqual(['schedules', 'attendance_sessions', 'accomplishment_reports', 'shift_swap_requests']);
  252 |   await page.evaluate(() => { scheduleTest.rows[0].attendance_sessions = { status: 'open' }; scheduleTest.events.find(event => event.table === 'attendance_sessions').callback(); });
  253 |   await expect(page.locator('#scheduleTable')).toContainText('DTR protected');
  254 | });
  255 | 
```