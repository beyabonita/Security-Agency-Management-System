# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: schedule_lifecycle.spec.js >> attendance reports completion and requests protect period history
- Location: schedule_lifecycle.spec.js:230:1

# Error details

```
Error: expect(locator).toHaveCount(expected) failed

Locator:  locator('#scheduleTable button[disabled]')
Expected: 5
Received: 6
Timeout:  5000ms

Call log:
  - Expect "toHaveCount" with timeout 5000ms
  - waiting for locator('#scheduleTable button[disabled]')
    13 × locator resolved to 6 elements
       - unexpected value "6"

```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - link "Skip to main content" [ref=e2] [cursor=pointer]:
    - /url: "#main-content"
  - generic [ref=e3]:
    - complementary [ref=e4]:
      - generic [ref=e5]:
        - paragraph [ref=e6]: Operations Head
        - paragraph [ref=e7]: Security Agency Management System
      - navigation [ref=e8]:
        - generic [ref=e9]: Manage
        - link "Dashboard" [ref=e10] [cursor=pointer]:
          - /url: dashboard.html
          - generic [ref=e11]: dashboard
          - text: Dashboard
        - link "Personnel" [ref=e12] [cursor=pointer]:
          - /url: users.html
          - generic [ref=e13]: groups
          - text: Personnel
        - link "Deployment Sites" [ref=e14] [cursor=pointer]:
          - /url: locations.html
          - generic [ref=e15]: location_on
          - text: Deployment Sites
        - link "Schedule" [ref=e16]:
          - /url: schedule.html
          - generic [ref=e17]: calendar_month
          - text: Schedule
        - link "Incidents" [ref=e18] [cursor=pointer]:
          - /url: incidents.html
          - generic [ref=e19]: emergency
          - text: Incidents
        - link "Duty requests" [ref=e20] [cursor=pointer]:
          - /url: swaps.html
          - generic [ref=e21]: swap_horiz
          - text: Duty requests
      - generic [ref=e22]: TwentyTwenty Security Agency
    - generic [ref=e23]:
      - banner [ref=e24]:
        - generic [ref=e26]:
          - generic [ref=e27]: Operations Head Console
          - heading "Duty Scheduling" [level=1] [ref=e28]
        - generic [ref=e29]:
          - button "Sign out" [ref=e30] [cursor=pointer]
          - button "Switch to dark mode" [ref=e31] [cursor=pointer]:
            - generic [ref=e32]: dark_mode
            - generic [ref=e33]: Dark mode
      - main [ref=e34]:
        - generic [ref=e35]: Assign a 24-hour guard roster
        - generic [ref=e36]:
          - generic [ref=e37]:
            - generic [ref=e38]:
              - generic [ref=e39]: Shifting setup
              - combobox "Shifting setup" [ref=e40]:
                - option "2 Shifts" [selected]
                - option "3 Shifts"
            - generic [ref=e41]:
              - generic [ref=e42]: Schedule date
              - textbox "Schedule date" [ref=e43]: 2026-09-04
            - generic [ref=e44]:
              - generic [ref=e45]: Deployment site
              - combobox "Deployment site" [ref=e46]:
                - option "Select location" [selected]
                - option "Test post"
          - generic [ref=e47]:
            - button "Edit setup" [ref=e48] [cursor=pointer]
            - button "Remove setup" [ref=e49] [cursor=pointer]
          - generic [ref=e50]:
            - status
            - button "Reload saved setups" [ref=e51] [cursor=pointer]
          - group [ref=e52]:
            - generic "Create a new shifting setup" [ref=e53] [cursor=pointer]
            - option "2" [selected]
            - option "3"
            - option "4"
            - option "5"
            - option "6"
            - option "7"
            - option "8"
            - option "9"
            - option "10"
            - option "11"
            - option "12"
          - generic "Guards for each shift" [ref=e54]:
            - generic [ref=e55]:
              - generic [ref=e56]: 6:00 AM – 6:00 PM
              - combobox "6:00 AM – 6:00 PM" [ref=e57]:
                - option "Select Guard 1" [selected]
                - option "Test guard"
                - option "Guard Two"
                - option "Guard Three"
              - paragraph
            - generic [ref=e58]:
              - generic [ref=e59]: 6:00 PM – 6:00 AM (next day)
              - combobox "6:00 PM – 6:00 AM (next day)" [ref=e60]:
                - option "Select Guard 2" [selected]
                - option "Test guard"
                - option "Guard Two"
                - option "Guard Three"
              - paragraph
          - status [ref=e61]:
            - paragraph [ref=e62]:
              - strong [ref=e63]: Selected guard shifts
            - paragraph [ref=e64]: "Duty date: Sep 4, 2026 · DTR cut-off: Sep 1–15, 2026"
            - generic "Planned guard shifts" [ref=e65]:
              - table [ref=e66]:
                - rowgroup [ref=e67]:
                  - row [ref=e68]:
                    - columnheader "Shift and Guard" [ref=e69]
                    - columnheader "Scheduled IN" [ref=e70]
                    - columnheader "Scheduled OUT" [ref=e71]
                    - columnheader "Planned hours" [ref=e72]
                - rowgroup [ref=e73]:
                  - row [ref=e74]:
                    - cell "6:00 AM – 6:00 PM — Select a Guard" [ref=e75]
                    - cell [ref=e76]:
                      - strong [ref=e77]: 6:00 AM
                    - cell [ref=e78]:
                      - strong [ref=e79]: 6:00 PM
                    - cell "12 hours" [ref=e80]
                  - row [ref=e81]:
                    - cell "6:00 PM – 6:00 AM (next day) — Select a Guard" [ref=e82]
                    - cell [ref=e83]:
                      - strong [ref=e84]: 6:00 PM
                    - cell [ref=e85]:
                      - strong [ref=e86]: 6:00 AM (next day)
                    - cell "12 hours" [ref=e87]
          - button "Assign all shifts" [ref=e88] [cursor=pointer]
          - generic [ref=e89]:
            - heading "Guards already assigned to this schedule" [level=3] [ref=e90]
            - paragraph [ref=e91]: 6:00 AM – 6:00 PM — Unassigned
            - paragraph [ref=e92]: 6:00 PM – 6:00 AM (next day) — Unassigned
        - generic [ref=e93]: Scheduled guard shifts
        - generic [ref=e94]:
          - generic [ref=e95]:
            - generic [ref=e96]:
              - generic [ref=e97]: Month
              - textbox "Month" [ref=e98]: 2099-01
            - generic [ref=e99]:
              - generic [ref=e100]: DTR cut-off
              - combobox "DTR cut-off" [ref=e101]:
                - option "1st–15th" [selected]
                - option "16th–end of month"
            - generic [ref=e102]:
              - generic [ref=e103]: Personnel
              - combobox "Personnel" [ref=e104]:
                - option "All personnel" [selected]
                - option "Test guard"
                - option "Inspector"
          - paragraph [ref=e105]: Philippine time (UTC+8)
          - generic "Scheduled guard shifts" [ref=e106]:
            - table [ref=e107]:
              - rowgroup [ref=e108]:
                - row [ref=e109]:
                  - columnheader "Personnel" [ref=e110]
                  - columnheader "Duty date" [ref=e111]
                  - columnheader "Scheduled IN" [ref=e112]
                  - columnheader "Scheduled OUT" [ref=e113]
                  - columnheader "Planned hours" [ref=e114]
                  - columnheader "Deployment site" [ref=e115]
                  - columnheader "Actions" [ref=e116]
              - rowgroup [ref=e117]:
                - row [ref=e118]:
                  - cell [ref=e119]:
                    - strong [ref=e120]: Unused duty
                  - cell "Jan 1, 2099" [ref=e121]
                  - cell "8:00 AM" [ref=e122]
                  - cell "5:00 PM" [ref=e123]
                  - cell "9 hours" [ref=e124]
                  - cell [ref=e125]:
                    - generic [ref=e126]:
                      - generic [ref=e127]: location_on
                      - text: Test post
                  - cell [ref=e128]:
                    - button "Delete Continuous shift period" [ref=e129] [cursor=pointer]: Delete
                - row [ref=e130]:
                  - cell [ref=e131]:
                    - strong [ref=e132]: On duty
                  - cell "Jan 1, 2099" [ref=e133]
                  - cell "8:00 AM" [ref=e134]
                  - cell "5:00 PM" [ref=e135]
                  - cell "9 hours" [ref=e136]
                  - cell [ref=e137]:
                    - generic [ref=e138]:
                      - generic [ref=e139]: location_on
                      - text: Test post
                  - cell [ref=e140]:
                    - 'button "Delete unavailable: Recorded attendance — kept for DTR." [disabled] [ref=e141]': Delete
                - row [ref=e142]:
                  - cell [ref=e143]:
                    - strong [ref=e144]: Done
                  - cell "Jan 1, 2099" [ref=e145]
                  - cell "8:00 AM" [ref=e146]
                  - cell "5:00 PM" [ref=e147]
                  - cell "9 hours" [ref=e148]
                  - cell [ref=e149]:
                    - generic [ref=e150]:
                      - generic [ref=e151]: location_on
                      - text: Test post
                  - cell [ref=e152]:
                    - 'button "Delete unavailable: Recorded attendance — kept for DTR." [disabled] [ref=e153]': Delete
                - row [ref=e154]:
                  - cell [ref=e155]:
                    - strong [ref=e156]: Reported
                  - cell "Jan 1, 2099" [ref=e157]
                  - cell "8:00 AM" [ref=e158]
                  - cell "5:00 PM" [ref=e159]
                  - cell "9 hours" [ref=e160]
                  - cell [ref=e161]:
                    - generic [ref=e162]:
                      - generic [ref=e163]: location_on
                      - text: Test post
                  - cell [ref=e164]:
                    - 'button "Delete unavailable: An accomplishment report is linked." [disabled] [ref=e165]': Delete
                - row [ref=e166]:
                  - cell [ref=e167]:
                    - strong [ref=e168]: Requested
                  - cell "Jan 1, 2099" [ref=e169]
                  - cell "8:00 AM" [ref=e170]
                  - cell "5:00 PM" [ref=e171]
                  - cell "9 hours" [ref=e172]
                  - cell [ref=e173]:
                    - generic [ref=e174]:
                      - generic [ref=e175]: location_on
                      - text: Test post
                  - cell [ref=e176]:
                    - 'button "Delete unavailable: A duty request is linked." [disabled] [ref=e177]': Delete
                - row [ref=e178]:
                  - cell [ref=e179]:
                    - strong [ref=e180]: Exchange target
                  - cell "Jan 1, 2099" [ref=e181]
                  - cell "8:00 AM" [ref=e182]
                  - cell "5:00 PM" [ref=e183]
                  - cell "9 hours" [ref=e184]
                  - cell [ref=e185]:
                    - generic [ref=e186]:
                      - generic [ref=e187]: location_on
                      - text: Test post
                  - cell [ref=e188]:
                    - 'button "Delete unavailable: A duty request is linked." [disabled] [ref=e189]': Delete
                - row [ref=e190]:
                  - cell [ref=e191]:
                    - strong [ref=e192]: Legacy
                  - cell "Jan 1, 2099" [ref=e193]
                  - cell "8:00 AM" [ref=e194]
                  - cell "5:00 PM" [ref=e195]
                  - cell "9 hours" [ref=e196]
                  - cell [ref=e197]:
                    - generic [ref=e198]:
                      - generic [ref=e199]: location_on
                      - text: Test post
                  - cell [ref=e200]:
                    - 'button "Delete unavailable: Completed duty — kept for records." [disabled] [ref=e201]': Delete
```

# Test source

```ts
  139 |   await fillRoster(page, '2099-01-15');
  140 |   await expect(page.locator('#rosterPreview')).toContainText('Jan 1–15, 2099');
  141 |   await expect(page.locator('#rosterPreview')).toContainText('6:00 AM (next day)');
  142 |   await page.locator('#saveRoster').click();
  143 |   await expect(page.getByText('2 shifts assigned successfully.', {exact:true})).toBeVisible();
  144 |   await expect(page.locator('#scheduleTable tr')).toHaveCount(2);
  145 |   const night = page.locator('#scheduleTable tr').filter({hasText:'Guard Two'});
  146 |   await expect(night.locator('.schedule-dtr-time')).toHaveText(['6:00 PM','6:00 AM (next day)']);
  147 |   await expect(night).toContainText('12 hours');
  148 |   expect(await page.evaluate(() => scheduleTest.created[0].map(row => row.duty_date))).toEqual(['2099-01-15','2099-01-15']);
  149 |   await page.locator('#scheduleCutoff').selectOption('second');
  150 |   await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
  151 | });
  152 | 
  153 | for (const kind of ['missing contract dates', 'outside contract dates', 'overnight contract end', 'inactive guard', 'past date']) {
  154 |   test(kind + ' prevents a roster request', async ({ page }) => {
  155 |     await fillRoster(page);
  156 |     await page.evaluate(kind => {
  157 |       if (kind === 'missing contract dates') guards[0].employmentCategory = 'contract';
  158 |       if (kind === 'outside contract dates') Object.assign(guards[0], {employmentCategory:'contract',contractStartDate:'2099-01-02',contractEndDate:'2099-01-31'});
  159 |       if (kind === 'overnight contract end') Object.assign(guards.find(g=>g.id==='peer'), {employmentCategory:'contract',contractStartDate:'2099-01-01',contractEndDate:'2099-01-01'});
  160 |       if (kind === 'inactive guard') guards[0].active = false;
  161 |     }, kind);
  162 |     if (kind === 'past date') {
  163 |       await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  164 |       await page.locator('#rosterDate').fill('2026-09-03');
  165 |     }
  166 |     await page.locator('#saveRoster').click();
  167 |     await expect(page.locator('.sl-toast')).toBeVisible();
  168 |     expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster'))).toEqual([]);
  169 |   });
  170 | }
  171 | 
  172 | test('a failed save prevents duplicate submission and preserves selected guards', async ({ page }) => {
  173 |   await fillRoster(page);
  174 |   await page.evaluate(() => { scheduleTest.pendingCreate=true; scheduleTest.createError={message:'Schedule conflict. Choose different Guards.'}; });
  175 |   await page.locator('#saveRoster').click();
  176 |   await expect(page.locator('#saveRoster')).toBeDisabled();
  177 |   await expect(page.locator('#rosterSetup')).toBeDisabled();
  178 |   await page.evaluate(() => { document.getElementById('saveRoster').dispatchEvent(new Event('click')); finishTestCreate(); });
  179 |   await expect(page.getByText('Schedule conflict. Choose different Guards.',{exact:true})).toBeVisible();
  180 |   await expect(page.locator('#saveRoster')).toBeEnabled();
  181 |   await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  182 |   await expect(page.locator('#rosterGuard1')).toHaveValue('peer');
  183 |   expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').length)).toBe(1);
  184 | });
  185 | 
  186 | test('an incomplete RPC response cannot report a saved roster', async ({ page }) => {
  187 |   await fillRoster(page); await page.evaluate(() => scheduleTest.malformedResult=true);
  188 |   await page.locator('#saveRoster').click();
  189 |   await expect(page.getByText('Could not confirm all assignments. Refresh the schedule before retrying.',{exact:true})).toBeVisible();
  190 |   await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  191 | });
  192 | 
  193 | test('after the first shift ends today remains available for the night shift', async ({ page }) => {
  194 |   await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  195 |   await page.reload();
  196 |   await page.evaluate(()=>loadRosterSetups());
  197 |   await expect(page.locator('#rosterDate')).toHaveValue('2026-09-04');
  198 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
  199 |   await expect(page.locator('#rosterGuard1')).toBeEnabled();
  200 | });
  201 | 
  202 | test('today at 7 PM assigns only the ongoing night shift, preserving its actual overnight hours', async({page})=>{
  203 |   await page.clock.setFixedTime(new Date('2026-09-04T11:00:00Z'));
  204 |   await page.locator('#rosterDate').fill('2026-09-04');
  205 |   await page.locator('#rosterSite').selectOption('test-site');
  206 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
  207 |   await page.locator('#rosterGuard1').selectOption('peer');
  208 |   await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  209 |   await expect(page.getByText('1 shift assigned successfully.',{exact:true})).toBeVisible();
  210 |   expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer']);
  211 |   expect(await page.evaluate(()=>scheduleTest.created[0].map(row=>[row.start_at,row.end_at]))).toEqual([['2026-09-04T10:00:00.000Z','2026-09-04T22:00:00.000Z']]);
  212 | });
  213 | 
  214 | test('three-shift setup at exactly 2 PM skips the completed morning and requires both remaining guards', async({page})=>{
  215 |   await page.clock.setFixedTime(new Date('2026-09-04T06:00:00Z'));
  216 |   await page.locator('#rosterDate').fill('2026-09-04');
  217 |   await page.locator('#rosterSetup').selectOption('3');
  218 |   await page.locator('#rosterSite').selectOption('test-site');
  219 |   await expect(page.locator('#rosterGuard0')).toBeDisabled();
  220 |   await page.locator('#rosterGuard1').selectOption('peer');
  221 |   await page.locator('#rosterGuard2').selectOption('third');
  222 |   await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  223 |   await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  224 |   expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer','third']);
  225 |   await page.locator('#rosterDate').fill('2026-09-05');
  226 |   await expect(page.locator('#rosterGuard0')).toBeEnabled();
  227 |   await expect(page.getByRole('button',{name:'Assign all shifts'})).toBeVisible();
  228 | });
  229 | 
  230 | test('attendance reports completion and requests protect period history', async ({ page }, info) => {
  231 |   await showRows(page, [record(unusedId, 'Unused duty'),
  232 |     record('open', 'On duty', { attendance_sessions: { id: 'session', status: 'open' } }),
  233 |     record('closed', 'Done', { attendance_sessions: [{ status: 'closed' }], marked_done: true }),
  234 |     record('report', 'Reported', { accomplishment_reports: { id: 'report' } }),
  235 |     record('change', 'Requested', { shift_swap_requests: [{ id: 'change' }] }),
  236 |     record('swap-target', 'Exchange target', { swap_target_requests: [{ id: 'exchange' }] }),
  237 |     record('legacy', 'Legacy', { marked_done: true })]);
  238 |   await expect(deleteButtons(page)).toHaveCount(1);
> 239 |   await expect(page.locator('#scheduleTable button[disabled]')).toHaveCount(6);
      |                                                                 ^ Error: expect(locator).toHaveCount(expected) failed
  240 |   await expect(page.locator('#scheduleTable button[disabled]')).toHaveText(['Delete','Delete','Delete','Delete','Delete','Delete']);
  241 |   await expect(page.locator('#scheduleTable button[title="A duty request is linked."]')).toHaveCount(2);
  242 |   await page.locator('.schedule-table').screenshot({ path: info.outputPath('schedule-history-protection.png') });
  243 | });
  244 | 
  245 | test('schedule loading explicitly selects both swap relationships in one query', async ({ page }, info) => {
  246 |   await showRows(page, [record(unusedId, 'Available duty'), record('target', 'Target duty', {swap_target_requests:[{id:'swap'}]})]);
  247 |   await expect(page.locator('#scheduleTable')).toContainText('Available duty');
  248 |   await expect(page.locator('#scheduleTable')).toContainText('Target duty');
  249 |   await expect(page.getByRole('button',{name:'Retry loading schedules'})).toHaveCount(0);
  250 |   const reads=await page.evaluate(()=>scheduleTest.calls.filter(call=>call.table==='schedules'));
  251 |   expect(reads).toHaveLength(1);
  252 |   expect(reads[0].columns).toContain('shift_swap_requests:shift_swap_requests!shift_swap_requests_requested_schedule_id_fkey(id)');
  253 |   expect(reads[0].columns).toContain('swap_target_requests:shift_swap_requests!shift_swap_requests_target_schedule_id_fkey(id)');
  254 |   await expect(deleteButtons(page)).toHaveCount(1);
  255 |   await page.locator('.schedule-table').screenshot({path:info.outputPath('schedule-both-swap-relationships.png')});
  256 | });
  257 | 
  258 | test('schedule names prefer the current profile and safely preserve historical names', async ({ page }) => {
  259 |   await showRows(page, [record('test-guard', 'Old profile name'),
  260 |     record(unusedId, '<img src=x onerror=alert(1)> Former guard')]);
  261 |   await expect(page.locator('#scheduleTable')).toContainText('Test guard');
  262 |   await expect(page.locator('#scheduleTable')).not.toContainText('Old profile name');
  263 |   await expect(page.locator('#scheduleTable')).toContainText('<img src=x onerror=alert(1)> Former guard');
  264 |   await expect(page.locator('#scheduleTable img')).toHaveCount(0);
  265 | });
  266 | 
  267 | test('cancelled deletion leaves the period and confirmed deletion has a busy state', async ({ page }) => {
  268 |   await showRows(page, [record(unusedId, 'Unused duty')]);
  269 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  270 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([]);
  271 |   await page.evaluate(() => { scheduleTest.pendingDelete = true; });
  272 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  273 |   await expect(deleteButtons(page)).toBeDisabled(); await expect(deleteButtons(page)).toContainText('Deleting');
  274 |   await page.evaluate(() => finishTestDelete()); await expect(deleteButtons(page)).toHaveCount(0);
  275 |   expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([{ rpc: 'delete_unused_schedule', args: { p_schedule_id: unusedId } }]);
  276 | });
  277 | 
  278 | test('concurrent Time In protects the schedule with readable error feedback', async ({ page }) => {
  279 |   await showRows(page, [record(unusedId, 'Duty just started')]);
  280 |   await page.evaluate(() => {
  281 |     scheduleTest.deleteError = { code: 'P0001', details: 'SCHEDULE_ATTENDANCE_HISTORY', message: "This schedule has recorded attendance and must be kept for the guard's DTR." };
  282 |     scheduleTest.rows[0].attendance_sessions = { id: 'new-session', status: 'open' };
  283 |   });
  284 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  285 |   await expect(page.getByText("This schedule has recorded attendance and must be kept for the guard's DTR.", { exact: true })).toBeVisible();
  286 |   await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.'); await expect(deleteButtons(page)).toHaveCount(0);
  287 | });
  288 | 
  289 | test('legacy foreign-key errors do not expose SQL details', async ({ page }) => {
  290 |   await showRows(page, [record(unusedId, 'Linked duty')]);
  291 |   await page.evaluate(() => { scheduleTest.deleteError = { code: '23503', message: 'violates foreign key constraint attendance_sessions_schedule_id_fkey' }; });
  292 |   await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  293 |   await expect(page.getByText('This schedule has linked duty records and must be kept for historical records.', { exact: true })).toBeVisible();
  294 |   await expect(page.getByText(/violates foreign key constraint/)).toHaveCount(0);
  295 | });
  296 | 
  297 | test('failed history load offers retry and older responses cannot erase newer protection', async ({ page }) => {
  298 |   await showRows(page, [record(unusedId, 'Existing duty')]);
  299 |   await page.evaluate(async () => { scheduleTest.readError = { message: 'Temporary network error' }; await refreshSchedules(); });
  300 |   await expect(deleteButtons(page)).toHaveCount(0);
  301 |   await page.evaluate(() => { scheduleTest.readError = null; });
  302 |   await page.getByRole('button', { name: 'Retry loading schedules' }).click(); await expect(deleteButtons(page)).toHaveCount(1);
  303 |   await page.evaluate(async fresh => {
  304 |     const resolvers = []; appSupabase.from = () => ({ select: () => ({ order: () => new Promise(resolve => resolvers.push(resolve)) }) });
  305 |     const first = refreshSchedules(), second = refreshSchedules();
  306 |     resolvers[1]({ data: [fresh] }); await second; resolvers[0]({ data: [] }); await first;
  307 |   }, record(unusedId, 'Newer protected row', { attendance_sessions: { status: 'open' } }));
  308 |   await expect(page.locator('#scheduleTable')).toContainText('Newer protected row');
  309 |   await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.');
  310 | });
  311 | 
  312 | test('linked-record realtime refreshes protection without duplicate subscriptions', async ({ page }) => {
  313 |   await showRows(page, [record(unusedId, 'Live duty')]);
  314 |   await page.evaluate(() => { loadSchedules(); loadSchedules(); });
  315 |   expect(await page.evaluate(() => scheduleTest.events.map(event => event.table))).toEqual(['schedules', 'attendance_sessions', 'accomplishment_reports', 'shift_swap_requests']);
  316 |   await page.evaluate(() => { scheduleTest.rows[0].attendance_sessions = { status: 'open' }; scheduleTest.events.find(event => event.table === 'attendance_sessions').callback(); });
  317 |   await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.');
  318 | });
  319 | 
  320 | test('2- and 3-shift rosters show named Guards and save one atomic request', async ({page}) => {
  321 |   await page.evaluate(()=>{
  322 |     renderShiftRoster();
  323 |     appSupabase.rpc=async(name,args)=>{
  324 |       scheduleTest.calls.push({rpc:name,args});
  325 |       const times=args.p_setup_id==='2'?[['06:00','18:00'],['18:00','06:00']]:[['06:00','14:00'],['14:00','22:00'],['22:00','06:00']];
  326 |       const rows=times.map((p,i)=>{const plan=SchedulePeriod.buildDutyPlan(args.p_duty_date,[{period:'auto',start_time:p[0],end_time:p[1],next_day:false}]);return {id:'roster-'+i,user_id:args.p_guard_ids[i],location_id:args.p_location_id,duty_date:args.p_duty_date,start_at:plan.periods[0].startAt.toISOString(),end_at:plan.periods[0].endAt.toISOString(),approval_status:'approved'};});
  327 |       scheduleTest.rows=rows;return {data:rows,error:null};
  328 |     };
  329 |   });
  330 |   await page.getByLabel('Schedule date',{exact:true}).fill('2099-01-03');
  331 |   await page.locator('#rosterSite').selectOption('test-site');
  332 |   await page.locator('#rosterGuard0').selectOption('test-guard');
  333 |   await page.locator('#rosterGuard1').selectOption('peer');
  334 |   await expect(page.locator('#rosterPreview')).toContainText('6:00 AM – 6:00 PM — Test guard');
  335 |   await expect(page.locator('#rosterPreview')).toContainText('6:00 PM – 6:00 AM (next day) — Guard Two');
  336 |   await page.getByRole('button',{name:'Assign all shifts'}).click();
  337 |   await expect(page.locator('#assignedRoster')).toContainText('Guard Two');
  338 |   await page.getByLabel('Shifting setup').selectOption('3');
  339 |   await expect(page.locator('#rosterGuards select')).toHaveCount(3);
```