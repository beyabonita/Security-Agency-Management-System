const { expect, test } = require('@playwright/test');
test.use({ timezoneId: 'America/Los_Angeles' }); // Agency time must be independent of browser time.
const unusedId = '4c6a6329-52a7-44d7-bc00-390f4c3a1668';
const record = (id, name, extra = {}) => ({
  id, user_id: id, guard_name: name, duty_date: '2099-01-01', dtr_period: 'auto',
  start_at: '2099-01-01T00:00:00Z', end_at: '2099-01-01T09:00:00Z',
  location_label: 'Test post', marked_done: false, approval_status: 'approved',
  attendance_sessions: null, accomplishment_reports: null, shift_swap_requests: [], swap_target_requests: [], ...extra,
});
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-04T03:00:00Z'));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({ contentType: 'text/javascript',
    body: 'window.firebase = { auth: () => ({ onAuthStateChanged() {} }), firestore: () => ({}) };' }));
  await page.route('**/notification-center.js', route => route.abort());
  await page.addInitScript(() => {
    const initialSetups=[{id:'2',name:'2 Shifts',version:1,shifts:[{start_time:'06:00',end_time:'18:00'},{start_time:'18:00',end_time:'06:00'}]},
      {id:'3',name:'3 Shifts',version:1,shifts:[{start_time:'06:00',end_time:'14:00'},{start_time:'14:00',end_time:'22:00'},{start_time:'22:00',end_time:'06:00'}]}];
    window.scheduleTest = { rows: [], calls: [], created: [], readError: null, deleteError: null, createError: null, events: [], setups: JSON.parse(sessionStorage.getItem('testSetups')||JSON.stringify(initialSetups)) };
    window.appSupabase = {
      from(table) { return { select(columns) {
        scheduleTest.calls.push({ table, columns });
        return { order: async () => {
          if(table==='shift_roster_setups'){
            const data=structuredClone(scheduleTest.setups);
            if(scheduleTest.pendingSetupRead)await new Promise(resolve=>{window.finishSetupRead=resolve;});
            return {data,error:scheduleTest.setupReadError};
          }
          // Match the real schema: reciprocal swaps give this relation two FKs.
          // Do not let a schema-ambiguous SELECT silently pass the UI suite.
          const ambiguous = /(?:^|,)\s*shift_swap_requests\s*\(/.test(columns);
          return { data: ambiguous ? null : scheduleTest.rows,
            error: ambiguous ? { code: 'PGRST201', message: 'More than one relationship was found for schedules and shift_swap_requests' } : scheduleTest.readError };
        } };
      } }; },
      async rpc(name, args) {
        const state = scheduleTest;
        state.calls.push({ rpc: name, args });
        if(name==='list_shift_roster_setups'){
          const data=structuredClone(state.setups).map(s=>({...s,in_use:Boolean(s.in_use)}));
          if(state.pendingSetupRead)await new Promise(resolve=>{window.finishSetupRead=resolve;});
          return {data,error:state.setupReadError};
        }
        if(name==='save_shift_roster_setup'||name==='update_shift_roster_setup'){
          if(state.pendingSetup)await new Promise(resolve=>{window.finishTestSetup=resolve;});
          if(state.setupError)return {data:null,error:state.setupError};
          const existing=state.setups.find(s=>s.id===args.p_setup_id);
          if(name==='update_shift_roster_setup'&&existing.version!==args.p_expected_version)return {data:null,error:{message:'This setup changed in another session. Reload saved setups before editing.'}};
          const data={id:existing?.id||'saved-setup-'+state.setups.filter(s=>s.id.startsWith('saved-setup-')).length,name:args.p_name,shifts:args.p_shifts,version:(existing?.version||0)+1};
          state.setups=state.setups.filter(s=>s.id!==data.id);
          state.setups.push(data);sessionStorage.setItem('testSetups',JSON.stringify(state.setups));
          return {data,error:null};
        }
        if(name==='remove_shift_roster_setup'){
          if(state.setupError)return {data:null,error:state.setupError};
          state.setups=state.setups.filter(s=>s.id!==args.p_setup_id);sessionStorage.setItem('testSetups',JSON.stringify(state.setups));
          return {data:args.p_setup_id,error:null};
        }
        if (name === 'assign_saved_shift_roster') {
          if (state.pendingCreate) await new Promise(resolve => { window.finishTestCreate = resolve; });
          if (state.createError) return { data: null, error: state.createError };
          if (state.malformedResult) return { data: [], error: null };
          const times = state.setups.find(s=>s.id===args.p_setup_id).shifts.map(s=>[s.start_time,s.end_time]);
          const plan = { periods: times.map(([start_time,end_time]) => SchedulePeriod.buildDutyPlan(args.p_duty_date,[{period:'auto',start_time,end_time}]).periods[0]) };
          const rows = plan.periods.map((period, index) => ({
            id: `created-${state.created.length}-${index}`, user_id: args.p_guard_ids[index], guard_name: 'Test guard',
            duty_date: args.p_duty_date, dtr_period: period.period, location_id: args.p_location_id,
            location_label: 'Test post', start_at: period.startAt.toISOString(), end_at: period.endAt.toISOString(),
            marked_done: false, approval_status: 'approved', attendance_sessions: null,
            accomplishment_reports: null, shift_swap_requests: [],
          })).filter(row=>row.user_id!==null);
          state.created.push(rows); state.rows.push(...rows);state.setups.find(s=>s.id===args.p_setup_id).in_use=true;
          return { data: rows, error: null };
        }
        if (state.pendingDelete) await new Promise(resolve => { window.finishTestDelete = resolve; });
        if (!state.deleteError) state.rows = state.rows.filter(row => row.id !== args.p_schedule_id);
        return { data: args.p_schedule_id, error: state.deleteError };
      },
      channel() { return {
        on(_type, config, callback) { scheduleTest.events.push({ table: config.table, callback }); return this; },
        subscribe() { return this; },
      }; },
    };
  });
  await page.goto('/admin/schedule.html');
  await page.addStyleTag({ content: '#loadingScreen { display:none!important }' });
  await page.evaluate(async () => {
    guards.push({ id: 'test-guard', role: 'user', name: 'Test guard', active: true, employmentCategory: 'regular' },
      { id: 'test-inspector', role: 'inspector', name: 'Inspector', active: true },
      { id: 'peer', role: 'user', name: 'Guard Two', active: true, employmentCategory: 'regular' },
      { id: 'third', role: 'user', name: 'Guard Three', active: true, employmentCategory: 'regular' });
    locations.push({ id: 'test-site', label: 'Test post', address: 'Test address' });
    document.querySelector('#schedulePersonnelFilter').innerHTML = '<option value="">All personnel</option><option value="test-guard">Test guard</option><option value="test-inspector">Inspector</option>';
    await window.loadRosterSetups();window.renderShiftRoster(); window.setScheduleListPeriod('2099-01-01');
  });
});
async function showRows(page, rows) {
  await page.evaluate(async rows => { scheduleTest.rows = rows; await refreshSchedules(); }, rows);
}
const deleteButtons = page => page.locator('#scheduleTable [data-delete-schedule]');
async function saveSetup(page,name='Four-shift rotation',count='4'){
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupName').fill(name);
  await page.locator('#rosterSetupCount').selectOption(count);
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetup')).toHaveValue('saved-setup-0');
}
async function fillRoster(page, date = '2099-01-01') {
  await page.locator('#rosterDate').fill(date);
  await page.locator('#rosterSite').selectOption('test-site');
  await page.locator('#rosterGuard0').selectOption('test-guard');
  await page.locator('#rosterGuard1').selectOption('peer');
}

test('roster is the only editor and the explanation panel is removed', async ({ page }) => {
  await expect(page.getByText('Custom personnel duty plan')).toHaveCount(0);
  await expect(page.locator('#guardUser,#scheduleMode,#overtimeEnabled')).toHaveCount(0);
  await expect(page.getByRole('button', {name:'Create schedule', exact:true})).toHaveCount(0);
  await expect(page.getByRole('button', {name:'Assign all shifts', exact:true})).toBeVisible();
  await expect(page.locator('.roster-dtr-guide')).toHaveCount(0);
  await expect(page.getByText('How the roster appears on the DTR')).toHaveCount(0);
  expect(await page.evaluate(() => typeof window.addSchedule)).toBe('undefined');
});

test('personnel and site loading work without custom-editor controls', async ({ page }) => {
  const errors=[]; page.on('pageerror',error=>errors.push(error.message));
  await page.evaluate(() => {
    const users=[{id:'loaded-guard',data:()=>({role:'user',firstName:'Loaded',lastName:'Guard',active:true})},{id:'loaded-inspector',data:()=>({role:'inspector',firstName:'Loaded',lastName:'Inspector',active:true})}];
    const sites=[{id:'loaded-site',data:()=>({label:'Loaded post',active:true})}];
    db.collection=name=>({get:async()=>users,where:()=>({get:async()=>sites})});
    loadGuards(); loadLocations();
  });
  await expect(page.locator('#rosterGuard0 option[value="loaded-guard"]')).toHaveCount(1);
  await expect(page.locator('#rosterSite option[value="loaded-site"]')).toHaveCount(1);
  await expect(page.locator('#schedulePersonnelFilter option')).toHaveText(['All guards','Loaded Guard']);
  expect(errors).toEqual([]);
});

test('an overnight roster remains on the starting date and first DTR cutoff', async ({ page }) => {
  await fillRoster(page, '2099-01-15');
  await expect(page.locator('#rosterPreview')).toContainText('Jan 1–15, 2099');
  await expect(page.locator('#rosterPreview')).toContainText('6:00 AM (next day)');
  await page.locator('#saveRoster').click();
  await expect(page.getByText('2 shifts assigned successfully.', {exact:true})).toBeVisible();
  await expect(page.locator('#scheduleTable tr')).toHaveCount(2);
  const night = page.locator('#scheduleTable tr').filter({hasText:'Guard Two'});
  await expect(night.locator('.schedule-dtr-time')).toHaveText(['6:00 PM','6:00 AM (next day)']);
  await expect(night).toContainText('12 hours');
  expect(await page.evaluate(() => scheduleTest.created[0].map(row => row.duty_date))).toEqual(['2099-01-15','2099-01-15']);
  await page.locator('#scheduleCutoff').selectOption('second');
  await expect(page.locator('#scheduleTable')).toContainText('No scheduled duty for this cut-off');
});

for (const kind of ['missing contract dates', 'outside contract dates', 'overnight contract end', 'inactive guard', 'past date']) {
  test(kind + ' prevents a roster request', async ({ page }) => {
    await fillRoster(page);
    await page.evaluate(kind => {
      if (kind === 'missing contract dates') guards[0].employmentCategory = 'contract';
      if (kind === 'outside contract dates') Object.assign(guards[0], {employmentCategory:'contract',contractStartDate:'2099-01-02',contractEndDate:'2099-01-31'});
      if (kind === 'overnight contract end') Object.assign(guards.find(g=>g.id==='peer'), {employmentCategory:'contract',contractStartDate:'2099-01-01',contractEndDate:'2099-01-01'});
      if (kind === 'inactive guard') guards[0].active = false;
    }, kind);
    if (kind === 'past date') {
      await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
      await page.locator('#rosterDate').fill('2026-09-03');
    }
    await page.locator('#saveRoster').click();
    await expect(page.locator('.sl-toast')).toBeVisible();
    expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster'))).toEqual([]);
  });
}

test('a failed save prevents duplicate submission and preserves selected guards', async ({ page }) => {
  await fillRoster(page);
  await page.evaluate(() => { scheduleTest.pendingCreate=true; scheduleTest.createError={message:'Schedule conflict. Choose different Guards.'}; });
  await page.locator('#saveRoster').click();
  await expect(page.locator('#saveRoster')).toBeDisabled();
  await expect(page.locator('#rosterSetup')).toBeDisabled();
  await page.evaluate(() => { document.getElementById('saveRoster').dispatchEvent(new Event('click')); finishTestCreate(); });
  await expect(page.getByText('Schedule conflict. Choose different Guards.',{exact:true})).toBeVisible();
  await expect(page.locator('#saveRoster')).toBeEnabled();
  await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  await expect(page.locator('#rosterGuard1')).toHaveValue('peer');
  expect(await page.evaluate(() => scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').length)).toBe(1);
});

test('an incomplete RPC response cannot report a saved roster', async ({ page }) => {
  await fillRoster(page); await page.evaluate(() => scheduleTest.malformedResult=true);
  await page.locator('#saveRoster').click();
  await expect(page.getByText('Could not confirm all assignments. Refresh the schedule before retrying.',{exact:true})).toBeVisible();
  await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
});

test('after the first shift ends today remains available for the night shift', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-09-04T10:00:00Z'));
  await page.reload();
  await page.evaluate(()=>loadRosterSetups());
  await expect(page.locator('#rosterDate')).toHaveValue('2026-09-04');
  await expect(page.locator('#rosterGuard0')).toBeDisabled();
  await expect(page.locator('#rosterGuard1')).toBeEnabled();
});

test('today at 7 PM assigns only the ongoing night shift, preserving its actual overnight hours', async({page})=>{
  await page.clock.setFixedTime(new Date('2026-09-04T11:00:00Z'));
  await page.locator('#rosterDate').fill('2026-09-04');
  await page.locator('#rosterSite').selectOption('test-site');
  await expect(page.locator('#rosterGuard0')).toBeDisabled();
  await page.locator('#rosterGuard1').selectOption('peer');
  await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  await expect(page.getByText('1 shift assigned successfully.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer']);
  expect(await page.evaluate(()=>scheduleTest.created[0].map(row=>[row.start_at,row.end_at]))).toEqual([['2026-09-04T10:00:00.000Z','2026-09-04T22:00:00.000Z']]);
});

test('three-shift setup at exactly 2 PM skips the completed morning and requires both remaining guards', async({page})=>{
  await page.clock.setFixedTime(new Date('2026-09-04T06:00:00Z'));
  await page.locator('#rosterDate').fill('2026-09-04');
  await page.locator('#rosterSetup').selectOption('3');
  await page.locator('#rosterSite').selectOption('test-site');
  await expect(page.locator('#rosterGuard0')).toBeDisabled();
  await page.locator('#rosterGuard1').selectOption('peer');
  await page.locator('#rosterGuard2').selectOption('third');
  await page.getByRole('button',{name:'Assign remaining shifts'}).click();
  await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer','third']);
  await page.locator('#rosterDate').fill('2026-09-05');
  await expect(page.locator('#rosterGuard0')).toBeEnabled();
  await expect(page.getByRole('button',{name:'Assign all shifts'})).toBeVisible();
});

test('attendance reports completion and requests protect period history', async ({ page }, info) => {
  await showRows(page, [record(unusedId, 'Unused duty'),
    record('open', 'On duty', { attendance_sessions: { id: 'session', status: 'open' } }),
    record('closed', 'Done', { attendance_sessions: [{ status: 'closed' }], marked_done: true }),
    record('report', 'Reported', { accomplishment_reports: { id: 'report' } }),
    record('change', 'Requested', { shift_swap_requests: [{ id: 'change' }] }),
    record('swap-target', 'Exchange target', { swap_target_requests: [{ id: 'exchange' }] }),
    record('legacy', 'Legacy', { marked_done: true })]);
  await expect(deleteButtons(page)).toHaveCount(1);
  await expect(page.locator('#scheduleTable button[disabled]')).toHaveCount(6);
  await expect(page.locator('#scheduleTable button[disabled]')).toHaveText(['Delete','Delete','Delete','Delete','Delete','Delete']);
  await expect(page.locator('#scheduleTable button[title="A duty request is linked."]')).toHaveCount(2);
  await page.locator('.schedule-table').screenshot({ path: info.outputPath('schedule-history-protection.png') });
});

test('schedule loading explicitly selects both swap relationships in one query', async ({ page }, info) => {
  await showRows(page, [record(unusedId, 'Available duty'), record('target', 'Target duty', {swap_target_requests:[{id:'swap'}]})]);
  await expect(page.locator('#scheduleTable')).toContainText('Available duty');
  await expect(page.locator('#scheduleTable')).toContainText('Target duty');
  await expect(page.getByRole('button',{name:'Retry loading schedules'})).toHaveCount(0);
  const reads=await page.evaluate(()=>scheduleTest.calls.filter(call=>call.table==='schedules'));
  expect(reads).toHaveLength(1);
  expect(reads[0].columns).toContain('shift_swap_requests:shift_swap_requests!shift_swap_requests_requested_schedule_id_fkey(id)');
  expect(reads[0].columns).toContain('swap_target_requests:shift_swap_requests!shift_swap_requests_target_schedule_id_fkey(id)');
  await expect(deleteButtons(page)).toHaveCount(1);
  await page.locator('.schedule-table').screenshot({path:info.outputPath('schedule-both-swap-relationships.png')});
});

test('schedule names prefer the current profile and safely preserve historical names', async ({ page }) => {
  await showRows(page, [record('test-guard', 'Old profile name'),
    record(unusedId, '<img src=x onerror=alert(1)> Former guard')]);
  await expect(page.locator('#scheduleTable')).toContainText('Test guard');
  await expect(page.locator('#scheduleTable')).not.toContainText('Old profile name');
  await expect(page.locator('#scheduleTable')).toContainText('<img src=x onerror=alert(1)> Former guard');
  await expect(page.locator('#scheduleTable img')).toHaveCount(0);
});

test('cancelled deletion leaves the period and confirmed deletion has a busy state', async ({ page }) => {
  await showRows(page, [record(unusedId, 'Unused duty')]);
  await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([]);
  await page.evaluate(() => { scheduleTest.pendingDelete = true; });
  await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  await expect(deleteButtons(page)).toBeDisabled(); await expect(deleteButtons(page)).toContainText('Deleting');
  await page.evaluate(() => finishTestDelete()); await expect(deleteButtons(page)).toHaveCount(0);
  expect(await page.evaluate(() => scheduleTest.calls.filter(call => call.rpc === 'delete_unused_schedule'))).toEqual([{ rpc: 'delete_unused_schedule', args: { p_schedule_id: unusedId } }]);
});

test('concurrent Time In protects the schedule with readable error feedback', async ({ page }) => {
  await showRows(page, [record(unusedId, 'Duty just started')]);
  await page.evaluate(() => {
    scheduleTest.deleteError = { code: 'P0001', details: 'SCHEDULE_ATTENDANCE_HISTORY', message: "This schedule has recorded attendance and must be kept for the guard's DTR." };
    scheduleTest.rows[0].attendance_sessions = { id: 'new-session', status: 'open' };
  });
  await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  await expect(page.getByText("This schedule has recorded attendance and must be kept for the guard's DTR.", { exact: true })).toBeVisible();
  await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.'); await expect(deleteButtons(page)).toHaveCount(0);
});

test('legacy foreign-key errors do not expose SQL details', async ({ page }) => {
  await showRows(page, [record(unusedId, 'Linked duty')]);
  await page.evaluate(() => { scheduleTest.deleteError = { code: '23503', message: 'violates foreign key constraint attendance_sessions_schedule_id_fkey' }; });
  await deleteButtons(page).click(); await page.getByRole('dialog').getByRole('button', { name: 'Delete period', exact: true }).click();
  await expect(page.getByText('This schedule has linked duty records and must be kept for historical records.', { exact: true })).toBeVisible();
  await expect(page.getByText(/violates foreign key constraint/)).toHaveCount(0);
});

test('failed history load offers retry and older responses cannot erase newer protection', async ({ page }) => {
  await showRows(page, [record(unusedId, 'Existing duty')]);
  await page.evaluate(async () => { scheduleTest.readError = { message: 'Temporary network error' }; await refreshSchedules(); });
  await expect(deleteButtons(page)).toHaveCount(0);
  await page.evaluate(() => { scheduleTest.readError = null; });
  await page.getByRole('button', { name: 'Retry loading schedules' }).click(); await expect(deleteButtons(page)).toHaveCount(1);
  await page.evaluate(async fresh => {
    const resolvers = []; appSupabase.from = () => ({ select: () => ({ order: () => new Promise(resolve => resolvers.push(resolve)) }) });
    const first = refreshSchedules(), second = refreshSchedules();
    resolvers[1]({ data: [fresh] }); await second; resolvers[0]({ data: [] }); await first;
  }, record(unusedId, 'Newer protected row', { attendance_sessions: { status: 'open' } }));
  await expect(page.locator('#scheduleTable')).toContainText('Newer protected row');
  await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.');
});

test('linked-record realtime refreshes protection without duplicate subscriptions', async ({ page }) => {
  await showRows(page, [record(unusedId, 'Live duty')]);
  await page.evaluate(() => { loadSchedules(); loadSchedules(); });
  expect(await page.evaluate(() => scheduleTest.events.map(event => event.table))).toEqual(['schedules', 'attendance_sessions', 'accomplishment_reports', 'shift_swap_requests']);
  await page.evaluate(() => { scheduleTest.rows[0].attendance_sessions = { status: 'open' }; scheduleTest.events.find(event => event.table === 'attendance_sessions').callback(); });
  await expect(page.locator('#scheduleTable button[disabled]')).toHaveAttribute('title','Recorded attendance — kept for DTR.');
});

test('2- and 3-shift rosters show named Guards and save one atomic request', async ({page}) => {
  await page.evaluate(()=>{
    renderShiftRoster();
    appSupabase.rpc=async(name,args)=>{
      scheduleTest.calls.push({rpc:name,args});
      const times=args.p_setup_id==='2'?[['06:00','18:00'],['18:00','06:00']]:[['06:00','14:00'],['14:00','22:00'],['22:00','06:00']];
      const rows=times.map((p,i)=>{const plan=SchedulePeriod.buildDutyPlan(args.p_duty_date,[{period:'auto',start_time:p[0],end_time:p[1],next_day:false}]);return {id:'roster-'+i,user_id:args.p_guard_ids[i],location_id:args.p_location_id,duty_date:args.p_duty_date,start_at:plan.periods[0].startAt.toISOString(),end_at:plan.periods[0].endAt.toISOString(),approval_status:'approved'};});
      scheduleTest.rows=rows;return {data:rows,error:null};
    };
  });
  await page.getByLabel('Schedule date',{exact:true}).fill('2099-01-03');
  await page.locator('#rosterSite').selectOption('test-site');
  await page.locator('#rosterGuard0').selectOption('test-guard');
  await page.locator('#rosterGuard1').selectOption('peer');
  await expect(page.locator('#rosterPreview')).toContainText('6:00 AM – 6:00 PM — Test guard');
  await expect(page.locator('#rosterPreview')).toContainText('6:00 PM – 6:00 AM (next day) — Guard Two');
  await page.getByRole('button',{name:'Assign all shifts'}).click();
  await expect(page.locator('#assignedRoster')).toContainText('Guard Two');
  await page.getByLabel('Shifting setup').selectOption('3');
  await expect(page.locator('#rosterGuards select')).toHaveCount(3);
  await page.locator('#rosterGuard2').selectOption('third');
  await expect(page.locator('#rosterPreview')).toContainText('10:00 PM – 6:00 AM (next day) — Guard Three');
  await page.getByRole('button',{name:'Assign all shifts'}).click();
  await expect.poll(()=>page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').length)).toBe(2);
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').at(-1).args.p_guard_ids)).toEqual(['test-guard','peer','third']);
});

test('roster prevents duplicate guards and preserves selection on save failure',async({page})=>{
  await page.evaluate(()=>renderShiftRoster());
  await page.locator('#rosterDate').fill('2099-01-03');await page.locator('#rosterSite').selectOption('test-site');
  await page.locator('#rosterGuard0').selectOption('test-guard');await page.locator('#rosterGuard1').selectOption('test-guard');
  await page.getByRole('button',{name:'Assign all shifts'}).click();
  await expect(page.getByText('Choose a site, today or a future date, and a different Guard for every shift.')).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='assign_saved_shift_roster').length)).toBe(0);
});

test('saved custom setup survives reload and assigns exact midnight and overnight times',async({page})=>{
  await saveSetup(page,'Four-shift rotation');
  await expect(page.locator('#rosterGuards select')).toHaveCount(4);
  await expect(page.locator('#rosterSetup option:checked')).toHaveText('Four-shift rotation (4 shifts)');
  await page.reload();await page.addStyleTag({content:'#loadingScreen {display:none!important}'});
  await page.evaluate(async()=>{
    await loadRosterSetups();
    guards.push(...['one','two','three','four'].map(id=>({id,role:'user',name:id,active:true,employmentCategory:'regular'})));
    locations.push({id:'test-site',label:'Test post'});renderShiftRoster();
  });
  await page.locator('#rosterSetup').selectOption('saved-setup-0');
  await page.locator('#rosterDate').fill('2026-09-15');
  await page.locator('#rosterSite').selectOption('test-site');
  for(const [i,id]of ['one','two','three','four'].entries())await page.locator('#rosterGuard'+i).selectOption(id);
  await page.locator('#saveRoster').click();
  await expect(page.getByText('4 shifts assigned successfully.',{exact:true})).toBeVisible();
  const result=await page.evaluate(()=>({args:scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args,rows:scheduleTest.created[0]}));
  expect(result.args.p_setup_id).toBe('saved-setup-0');
  expect(result.rows.map(row=>[row.start_at,row.end_at,row.duty_date,row.dtr_period])).toEqual([
    ['2026-09-14T16:00:00.000Z','2026-09-14T22:00:00.000Z','2026-09-15','auto'],
    ['2026-09-14T22:00:00.000Z','2026-09-15T04:00:00.000Z','2026-09-15','auto'],
    ['2026-09-15T04:00:00.000Z','2026-09-15T10:00:00.000Z','2026-09-15','auto'],
    ['2026-09-15T10:00:00.000Z','2026-09-15T16:00:00.000Z','2026-09-15','auto'],
  ]);
  await expect(page.locator('#scheduleTable')).toContainText('12:00 AM (next day)');
});

test('custom shift setup supports changed times and skips ended shifts today',async({page})=>{
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupName').fill('Seven to seven');
  await page.locator('#setupStart0').fill('07:00');await page.locator('#setupEnd0').fill('19:00');
  await page.locator('#setupStart1').fill('19:00');await page.locator('#setupEnd1').fill('07:00');
  await page.locator('#saveRosterSetup').click();
  await page.clock.setFixedTime(new Date('2026-09-04T11:00:00Z'));
  await page.locator('#rosterDate').fill('2026-09-04');
  await page.locator('#rosterSite').selectOption('test-site');
  await expect(page.locator('#rosterGuard0')).toBeDisabled();
  await page.locator('#rosterGuard1').selectOption('peer');
  await page.locator('#saveRoster').click();
  await expect(page.getByText('1 shift assigned successfully.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_guard_ids)).toEqual([null,'peer']);
});

test('setup editor rejects gaps and preserves entered values after save errors',async({page})=>{
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupName').fill('Evening rotation');
  await page.locator('#setupEnd0').fill('17:00');
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetupError')).toContainText('without gaps or overlaps');
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='save_shift_roster_setup').length)).toBe(0);
  await page.locator('#setupStart0').fill('07:00');await page.locator('#setupEnd0').fill('19:00');
  await page.locator('#setupStart1').fill('19:00');await page.locator('#setupEnd1').fill('07:00');
  await page.evaluate(()=>scheduleTest.setupError={message:'A shifting setup already uses that name. Choose another name.'});
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetupError')).toContainText('already uses that name');
  await expect(page.locator('#rosterSetupName')).toHaveValue('Evening rotation');
  await expect(page.locator('#setupEnd0')).toHaveValue('19:00');
  await expect(page.locator('#saveRosterSetup')).toBeEnabled();
});

test('setup saving blocks duplicate submission and safely displays names',async({page})=>{
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupName').fill('<img src=x onerror=alert(1)>');
  await page.locator('#rosterSetupCount').selectOption('4');
  await page.evaluate(()=>scheduleTest.pendingSetup=true);
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#saveRosterSetup')).toBeDisabled();await expect(page.locator('#saveRoster')).toBeDisabled();
  await page.evaluate(()=>document.querySelector('#rosterSetupForm').dispatchEvent(new Event('submit',{cancelable:true})));
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='save_shift_roster_setup').length)).toBe(1);
  await page.evaluate(()=>finishTestSetup());
  await expect(page.locator('#rosterSetup option:checked')).toHaveText('<img src=x onerror=alert(1)> (4 shifts)');
  await expect(page.locator('#rosterSetup img')).toHaveCount(0);
});

test('saved setups have a retry when loading fails without blocking standard rosters',async({page})=>{
  await page.evaluate(async()=>{scheduleTest.setupReadError={message:'offline'};await loadRosterSetups();});
  await expect(page.locator('#retryRosterSetups')).toBeVisible();
  await fillRoster(page);await page.locator('#saveRoster').click();
  await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  await page.evaluate(()=>scheduleTest.setupReadError=null);
  await page.locator('#retryRosterSetups').click();
  await expect(page.locator('#rosterSetupsStatus')).toBeEmpty();
});

test('custom setup editor fits desktop and phone in both themes',async({page},info)=>{
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupCount').selectOption('4');
  for(const width of [390,1440])for(const theme of ['light','dark']){
    await page.setViewportSize({width,height:1100});
    await page.evaluate(theme=>{window.sentinelTheme.set(theme);window.scrollTo(0,0);},theme);
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    await expect(page.locator('#saveRosterSetup')).toBeVisible();
    await page.screenshot({path:info.outputPath(`custom-setup-${width}-${theme}.png`),fullPage:true});
  }
});

test('duplicate built-in and saved shift times are blocked even with a different name',async({page})=>{
  await page.locator('#newRosterSetup summary').click();
  await page.locator('#rosterSetupName').fill('Another standard two');
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetupError')).toContainText('already exists: 2 Shifts');
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='save_shift_roster_setup').length)).toBe(0);
  await page.locator('#newRosterSetup summary').click();await saveSetup(page);
  await page.locator('#newRosterSetup summary').click();await page.locator('#rosterSetupName').fill('Duplicate four');
  await page.locator('#rosterSetupCount').selectOption('4');await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetupError')).toContainText('already exists: Four-shift rotation');
  expect(await page.evaluate(()=>scheduleTest.calls.filter(c=>c.rpc==='save_shift_roster_setup').length)).toBe(1);
});

test('edit opens saved values and updates future assignment preview, cancel preserves setup',async({page})=>{
  await saveSetup(page);await page.locator('#editRosterSetup').click();
  await expect(page.locator('#setupStart0')).toHaveValue('00:00');
  await page.locator('#rosterSetupName').fill('Cancelled name');await page.locator('#cancelRosterSetup').click();
  await expect(page.locator('#rosterSetup option:checked')).toContainText('Four-shift rotation');
  await page.locator('#editRosterSetup').click();await page.locator('#rosterSetupName').fill('Seven to seven');
  await page.locator('#rosterSetupCount').selectOption('2');
  await page.locator('#setupStart0').fill('07:00');await page.locator('#setupEnd0').fill('19:00');
  await page.locator('#setupStart1').fill('19:00');await page.locator('#setupEnd1').fill('07:00');
  await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetup option:checked')).toHaveText('Seven to seven (2 shifts)');
  await expect(page.locator('#rosterGuards select')).toHaveCount(2);
  await expect(page.locator('#rosterPreview')).toContainText('7:00 PM – 7:00 AM (next day)');
  await fillRoster(page);await page.locator('#saveRoster').click();
  await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args.p_expected_version)).toBe(2);
});

test('remove can be cancelled, then persists after reload without removing scheduled duty',async({page})=>{
  await saveSetup(page);await showRows(page,[record(unusedId,'Existing duty')]);
  await page.locator('#removeRosterSetup').click();
  await page.getByRole('dialog').getByRole('button',{name:'Cancel',exact:true}).click();
  await expect(page.locator('#rosterSetup')).toHaveValue('saved-setup-0');
  await page.locator('#removeRosterSetup').click();
  await page.getByRole('dialog').getByRole('button',{name:'Remove setup',exact:true}).click();
  await expect(page.locator('#rosterSetup')).toHaveValue('2');
  await expect(page.locator('#rosterSetup option')).toHaveCount(2);
  expect(await page.evaluate(()=>scheduleTest.rows.map(r=>r.id))).toEqual([unusedId]);
  await page.evaluate(()=>loadRosterSetups());await expect(page.locator('#rosterSetup option')).toHaveCount(2);
  await page.reload();await page.evaluate(()=>loadRosterSetups());await expect(page.locator('#rosterSetup option')).toHaveCount(2);
});

test('setup mutations wait until the usage check finishes',async({page})=>{
 await saveSetup(page);
 await page.evaluate(()=>{scheduleTest.pendingSetupRead=true;void loadRosterSetups();});
 await expect(page.locator('#editRosterSetup')).toBeDisabled();await expect(page.locator('#removeRosterSetup')).toBeDisabled();
 await page.evaluate(()=>{scheduleTest.pendingSetupRead=false;finishSetupRead();});
 await expect(page.locator('#removeRosterSetup')).toBeEnabled();
 await page.locator('#removeRosterSetup').click();await page.getByRole('dialog').getByRole('button',{name:'Remove setup',exact:true}).click();
 await expect(page.locator('#rosterSetup option')).toHaveCount(2);
});

test('reload reflects edits and removals from another session, and stale edits are rejected',async({page})=>{
  await saveSetup(page);await page.locator('#editRosterSetup').click();
  await page.evaluate(()=>{const item=scheduleTest.setups.find(s=>s.id==='saved-setup-0');item.version++;item.name='Updated elsewhere';});
  await page.locator('#rosterSetupName').fill('My stale edit');await page.locator('#saveRosterSetup').click();
  await expect(page.locator('#rosterSetupError')).toContainText('changed in another session');
  await page.locator('#retryRosterSetups').click();
  await expect(page.locator('#rosterSetup option:checked')).toContainText('Updated elsewhere');
  await page.evaluate(()=>scheduleTest.setups=[]);await page.locator('#retryRosterSetups').click();
  await expect(page.locator('#rosterSetup option')).toHaveText(['No shifting setups']);
});

test('setup edit and removal controls fit on a phone and failed removal keeps the selection',async({page},info)=>{
  await page.setViewportSize({width:390,height:1000});await saveSetup(page);await page.locator('#editRosterSetup').click();
  await page.evaluate(()=>sentinelTheme.set('dark'));
  await page.screenshot({path:info.outputPath('setup-management-phone.png'),fullPage:true});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(page.locator('#cancelRosterSetup')).toBeVisible();await page.locator('#cancelRosterSetup').click();
  await page.evaluate(()=>scheduleTest.setupError={message:'Connection unavailable. Please try again.'});
  await page.locator('#removeRosterSetup').click();await page.getByRole('dialog').getByRole('button',{name:'Remove setup',exact:true}).click();
  await expect(page.getByText('Connection unavailable. Please try again.',{exact:true})).toBeVisible();
  await expect(page.locator('#rosterSetup')).toHaveValue('saved-setup-0');await expect(page.locator('#removeRosterSetup')).toBeEnabled();
});

test('both initial setups expose edit and remove and edited times drive assignments',async({page})=>{
  for(const id of ['2','3']){
    await page.locator('#rosterSetup').selectOption(id);
    await expect(page.locator('#editRosterSetup')).toBeVisible();await expect(page.locator('#removeRosterSetup')).toBeVisible();
    await page.locator('#editRosterSetup').click();await expect(page.locator('#rosterSetupName')).toHaveValue(id+' Shifts');
    await expect(page.locator('#rosterSetupCount')).toHaveValue(id);await page.locator('#cancelRosterSetup').click();
  }
  await page.locator('#rosterSetup').selectOption('2');await page.locator('#editRosterSetup').click();
  await page.locator('#setupStart0').fill('07:00');await page.locator('#setupEnd0').fill('19:00');
  await page.locator('#setupStart1').fill('19:00');await page.locator('#setupEnd1').fill('07:00');
  await page.locator('#saveRosterSetup').click();await expect(page.locator('#rosterSetup option:checked')).toHaveText('2 Shifts');
  await fillRoster(page);await page.locator('#saveRoster').click();
  await expect(page.getByText('2 shifts assigned successfully.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>scheduleTest.calls.find(c=>c.rpc==='assign_saved_shift_roster').args)).toMatchObject({p_setup_id:'2',p_expected_version:2});
  expect(await page.evaluate(()=>scheduleTest.created[0][1].end_at)).toBe('2099-01-01T23:00:00.000Z');
});

test('remove both initial setups, reload an empty list, and recreate a removed setup',async({page},info)=>{
  for(const id of ['2','3']){
    await page.locator('#rosterSetup').selectOption(id);await page.locator('#removeRosterSetup').click();
    await page.getByRole('dialog').getByRole('button',{name:'Remove setup',exact:true}).click();
    await expect(page.locator(`#rosterSetup option[value="${id}"]`)).toHaveCount(0);
  }
  await expect(page.locator('#rosterSetup')).toBeDisabled();await expect(page.locator('#saveRoster')).toBeDisabled();
  await expect(page.locator('#rosterPreview')).toContainText('Create a shifting setup to get started.');
  await page.reload();await page.addStyleTag({content:'#loadingScreen {display:none!important}'});await page.evaluate(()=>loadRosterSetups());
  await expect(page.locator('#rosterSetup option')).toHaveText(['No shifting setups']);
  await expect(page.locator('#manageRosterSetup')).toBeHidden();
  await page.screenshot({path:info.outputPath('empty-shifting-setups.png'),fullPage:true});
  await saveSetup(page,'2 Shifts','2');
  await expect(page.locator('#rosterSetup option')).toHaveText(['2 Shifts']);
  await expect(page.locator('#editRosterSetup')).toBeVisible();await expect(page.locator('#removeRosterSetup')).toBeVisible();
  await expect(page.locator('#saveRoster')).toBeEnabled();
});

test('initial loading failure never falls back to fixed or removed setups',async({page})=>{
  await page.reload();await page.addStyleTag({content:'#loadingScreen {display:none!important}'});
  await page.evaluate(async()=>{scheduleTest.setupReadError={message:'offline'};await loadRosterSetups();});
  await expect(page.locator('#saveRoster')).toBeDisabled();await expect(page.locator('#rosterSetup')).toBeDisabled();
  await expect(page.locator('#rosterSetupsStatus')).toContainText('Could not check shifting setups');
  await page.evaluate(()=>scheduleTest.setupReadError=null);await page.locator('#retryRosterSetups').click();
  await expect(page.locator('#rosterSetup option')).toHaveText(['2 Shifts','3 Shifts']);
  await expect(page.locator('#editRosterSetup')).toBeVisible();
});

test('assignment immediately locks edit and remove but allows further assignments',async({page})=>{
 await fillRoster(page);await page.locator('#saveRoster').click();
 await expect(page.locator('#editRosterSetup')).toBeDisabled();await expect(page.locator('#removeRosterSetup')).toBeDisabled();
 await expect(page.locator('#rosterSetupLock')).toHaveText('In use — editing and removal locked.');
 await expect(page.locator('#saveRoster')).toBeEnabled();
 await page.locator('#rosterSetup').selectOption('3');await expect(page.locator('#editRosterSetup')).toBeEnabled();
 await page.locator('#rosterSetup').selectOption('2');await expect(page.locator('#removeRosterSetup')).toBeDisabled();
});
test('usage refresh locks an open editor and later unlocks finished duties',async({page},info)=>{
 await page.locator('#editRosterSetup').click();
 await page.evaluate(async()=>{scheduleTest.setups[0].in_use=true;await loadRosterSetups();});
 await expect(page.locator('#newRosterSetup')).not.toHaveAttribute('open','');
 await expect(page.locator('#editRosterSetup')).toBeDisabled();await expect(page.locator('#removeRosterSetup')).toBeDisabled();
 for(const width of [390,1440]){
  await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:info.outputPath('locked-setup-'+width+'.png'),fullPage:true,animations:'disabled'});
 }
 await page.evaluate(async()=>{scheduleTest.setups[0].in_use=false;await loadRosterSetups();});
 await expect(page.locator('#editRosterSetup')).toBeEnabled();await expect(page.locator('#removeRosterSetup')).toBeEnabled();
});
test('failed usage check disables mutations until a successful retry',async({page})=>{
 await page.evaluate(async()=>{scheduleTest.setupReadError={message:'offline'};await loadRosterSetups();});
 await expect(page.locator('#editRosterSetup')).toBeDisabled();await expect(page.locator('#removeRosterSetup')).toBeDisabled();
 await page.evaluate(async()=>{scheduleTest.setupReadError=null;await loadRosterSetups();});
 await expect(page.locator('#editRosterSetup')).toBeEnabled();
});

test('usage-only refresh preserves the guard selection and focused control',async({page})=>{
 await fillRoster(page);await page.locator('#rosterGuard0').focus();
 const same=await page.evaluate(async()=>{const before=document.querySelector('#rosterGuard0');scheduleTest.setups[0].in_use=true;await loadRosterSetups({silent:true});return before===document.querySelector('#rosterGuard0')&&document.activeElement===before;});
 expect(same).toBe(true);await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');await expect(page.locator('#editRosterSetup')).toBeDisabled();
});

test('scheduled guard shifts exclude Inspector assignments and show only action buttons',async({page})=>{
 await showRows(page,[record('test-guard','Test guard'),record('test-inspector','Inspector')]);
 await expect(page.locator('#scheduleTable tr')).toHaveCount(1);
 await expect(page.locator('#scheduleTable')).not.toContainText('Inspector');
 await expect(page.locator('.schedule-table thead th').last()).toHaveText('Actions');
 await expect(page.locator('#scheduleTable .schedule-period-actions')).toHaveText('Delete');
});

test('editing existing shift times updates the selected guard shifts preview and assignment labels', async ({ page }) => {
  await fillRoster(page);
  await expect(page.locator('#rosterPreview')).toContainText('6:00 AM – 6:00 PM');
  await expect(page.locator('#rosterPreview')).toContainText('6:00 PM – 6:00 AM (next day)');

  // Click the Edit Shift Times button in Selected Guard Shifts header
  await page.locator('#editRosterTimesBtn').click();
  await expect(page.locator('#editRosterTimesModal')).toBeVisible();

  // Test preset: 7 AM - 7 PM
  await page.locator('.roster-preset-btn[data-preset="07:00-19:00"]').click();
  await expect(page.locator('#modalShiftStart0')).toHaveValue('07:00');
  await expect(page.locator('#modalShiftEnd0')).toHaveValue('19:00');
  await expect(page.locator('#modalShiftStart1')).toHaveValue('19:00');
  await expect(page.locator('#modalShiftEnd1')).toHaveValue('07:00');

  // Save the modified times
  await page.locator('#saveRosterTimesBtn').click();
  await expect(page.locator('#editRosterTimesModal')).not.toBeVisible();

  // Selected guard shifts preview should now display 7:00 AM – 7:00 PM
  await expect(page.locator('#rosterPreview')).toContainText('7:00 AM – 7:00 PM');
  await expect(page.locator('#rosterPreview')).toContainText('7:00 PM – 7:00 AM (next day)');

  // Guard slot labels also reflect the updated shift times
  await expect(page.locator('#rosterGuards label').first()).toContainText('7:00 AM – 7:00 PM');
  await expect(page.locator('#rosterGuards label').nth(1)).toContainText('7:00 PM – 7:00 AM (next day)');

  // Confirm row action buttons are removed and re-editing via top button works cleanly
  await expect(page.locator('.edit-shift-row-btn')).toHaveCount(0);
  await page.locator('#editRosterTimesBtn').click();
  await expect(page.locator('#editRosterTimesModal')).toBeVisible();
  await page.locator('.roster-preset-btn[data-preset="08:00-20:00"]').click();
  await page.locator('#saveRosterTimesBtn').click();
  await expect(page.locator('#editRosterTimesModal')).not.toBeVisible();

  await expect(page.locator('#rosterPreview')).toContainText('8:00 AM – 8:00 PM');
  await expect(page.locator('#rosterPreview')).toContainText('8:00 PM – 8:00 AM (next day)');
});

test('selecting a guard for a second shift is prevented and resets the slot with warning', async ({ page }) => {
  await fillRoster(page);
  await expect(page.locator('#rosterGuard0')).toHaveValue('test-guard');
  await expect(page.locator('#rosterGuard1')).toHaveValue('peer');

  // Try to put 'test-guard' into Shift 2 as well
  await page.locator('#rosterGuard1').selectOption('test-guard');

  // Warning toast should be shown
  await expect(page.getByText('already assigned to Shift 1. A guard cannot be put on double shifts.')).toBeVisible();

  // Shift 2 slot should be reset so double shifts are prevented
  await expect(page.locator('#rosterGuard1')).toHaveValue('');
  await expect(page.locator('#rosterStatus1')).toContainText('Double shift prevented: already in Shift 1');
});

test('deployment site combobox opens dropdown on focus/click and filters options on typing', async ({ page }) => {
  await page.evaluate(() => {
    locations.push({ id: 'other-site', label: 'Other post', address: 'Other address' });
    window.renderShiftRoster();
  });
  await fillRoster(page);
  await expect(page.locator('#rosterSiteFilter')).toHaveValue('Test post');

  // Focus and open dropdown
  await page.locator('#rosterSiteFilter').click();
  await expect(page.locator('#rosterSiteMenu')).toBeVisible();

  // Type to filter
  await page.locator('#rosterSiteFilter').fill('other');
  await expect(page.locator('#rosterSiteMenu .roster-combobox-item')).toHaveCount(1);
  await expect(page.locator('#rosterSiteMenu')).toContainText('Other post');

  // Click the filtered option
  await page.locator('#rosterSiteMenu .roster-combobox-item').click();
  await expect(page.locator('#rosterSiteMenu')).not.toBeVisible();
  await expect(page.locator('#rosterSiteFilter')).toHaveValue('Other post');
  await expect(page.locator('#rosterSite')).toHaveValue('other-site');
});




