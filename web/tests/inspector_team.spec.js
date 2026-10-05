const { test, expect } = require('@playwright/test');

async function teamMocks(page, empty = false) {
  await page.clock.setFixedTime(new Date('2026-09-05T02:00:00Z'));
  await page.route('**/platform-configuration.js', route => route.fulfill({ body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ body: '' }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.teamQueries = []; window.teamMessages = []; window.teamDtrReads = []; window.teamRpcCalls = [];
      window.teamEmpty = ${JSON.stringify(empty)};
      const rows = {
        users: [
          {id:'inspector-a',role:'inspector',firstName:'Inspector',lastName:'One',active:true},
          {id:'guard-a',role:'user',firstName:'Assigned',lastName:'Guard',inspector_id:'inspector-a',active:true},
          {id:'guard-b',role:'user',firstName:'Other',lastName:'Guard',inspector_id:'inspector-b',active:true}
        ],
        schedules: [
          {id:'duty-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-06T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-06T09:00:00Z')},locationLabel:'Assigned post',dtrPeriod:'morning',approvalStatus:'approved'},
          {id:'cancelled-a',userId:'guard-a',startAt:{toDate:()=>new Date('2026-09-07T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-07T09:00:00Z')},locationLabel:'Cancelled site',approvalStatus:'cancelled'},
          {id:'duty-b',userId:'guard-b',startAt:{toDate:()=>new Date('2026-09-08T00:00:00Z')},endAt:{toDate:()=>new Date('2026-09-08T09:00:00Z')},locationLabel:'Other Guard site',approvalStatus:'approved'}
        ],
        locations: [{id:'site-a',label:'Assigned post',active:true}],
        incidents: [{id:'incident-a',userId:'guard-a',guardName:'Assigned Guard',category:'medical',status:'open',remarks:'Needs assistance',capturedAt:{toDate:()=>new Date('2026-09-05T02:00:00Z')}}],
      };
      function query(table, filters = [], id = null) {
        return {
          where: (key,op,value) => query(table,[...filters,[key,value]],id),
          doc: value => query(table,filters,value),
          orderBy: () => query(table,filters,id),
          get: async () => {
            window.teamQueries.push({table,filters,id});
            let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
            if(window.teamEmpty && filters.some(([key]) => key === 'inspector_id')) selected = [];
            const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
            return id ? docs[0] || {exists:false} : {docs,size:docs.length,forEach:fn=>docs.forEach(fn)};
          },
          onSnapshot: (next) => {
            let selected = (rows[table] || []).filter(row => (!id || row.id === id) && filters.every(([key,value]) => row[key] === value));
            const docs = selected.map(row => ({id:row.id,exists:true,data:()=>row}));
            Promise.resolve().then(() => next({docs,size:docs.length,forEach:fn=>docs.forEach(fn)}));
            return () => {};
          },
        };
      }
      window.firebase = {auth:()=>({onAuthStateChanged:fn=>Promise.resolve().then(()=>fn({uid:'inspector-a'})),signOut:async()=>{}}),firestore:()=>({collection:table=>query(table)})};
      window.appSupabase = {
        from:table=>({select:()=>({eq:(key,value)=>({order:async()=>{window.teamDtrReads.push({table,key,value});return {data:[],error:null};}})})}),
        rpc: async (name, params) => { window.teamRpcCalls.push({name,params}); return {data:null,error:null}; }
      };
      window.appDialog = {toast:message=>window.teamMessages.push(message),runBusy:async(_button,fn)=>fn()};
    `,
  }));
}

test.afterEach(async ({ page }, info) => {
  await page.screenshot({ path: info.outputPath('inspector-team.png'), fullPage: true });
});

test('My Guards queries assigned personnel and opens their DTR', async ({ page }) => {
  await teamMocks(page);
  await page.goto('/inspector/users.html');
  await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  await expect(page.locator('#userTableBody')).not.toContainText('Other Guard');
  await expect(page.locator('.ax-page-title')).toHaveText('My Guards');
  expect(await page.evaluate(() => teamQueries.some(query => query.filters.some(([key,value]) => key === 'inspector_id' && value === 'inspector-a')))).toBe(true);
  await page.getByRole('button', { name: 'View DTR' }).click();
  await expect(page.locator('#dtrModal')).toHaveClass(/show/);
  await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  expect(await page.evaluate(() => teamDtrReads)).toEqual([{table:'attendance_sessions',key:'user_id',value:'guard-a'}]);
});

test('Inspector views only an assigned Guard active schedule, grouped by DTR cut-off', async ({ page }) => {
  await teamMocks(page);
  await page.goto('/inspector/users.html');
  await page.getByRole('button', { name: 'View schedule', exact: true }).click();
  const dialog = page.locator('#scheduleModal');
  await expect(dialog).toHaveClass(/show/);
  await expect(dialog).toContainText('Assigned Guard');
  await expect(dialog).toContainText('Assigned post');
  await expect(dialog).toContainText('Morning');
  await expect(dialog).not.toContainText('Cancelled site');
  await expect(dialog).not.toContainText('Other Guard site');
  await page.evaluate(() => viewGuardSchedule('guard-b'));
  await expect(page.getByText('This Guard is not in your assigned team. Refresh My Guards.')).toBeVisible();
  await page.screenshot({ path: test.info().outputPath('assigned-guard-schedule.png'), fullPage: true });
});

test('empty assignment explains who assigns the Inspector team', async ({ page }) => {
  await teamMocks(page, true);
  await page.goto('/inspector/users.html');
  await expect(page.locator('#userTableBody')).toContainText('No Guards assigned to you yet');
  await expect(page.getByRole('button', { name: 'View DTR' })).toHaveCount(0);
});

test('unknown Guard cannot open a cached DTR and reassignment clears open records', async ({ page }) => {
  await teamMocks(page);
  await page.goto('/inspector/users.html');
  await expect(page.locator('#userTableBody')).toContainText('Assigned Guard');
  await page.evaluate(() => viewDTR('guard-b'));
  expect(await page.evaluate(() => teamDtrReads.length)).toBe(0);
  await expect(page.getByText('This Guard is not in your assigned team. Refresh My Guards.')).toBeVisible();
  await page.getByRole('button', { name: 'View DTR' }).click();
  await expect(page.locator('.dtr-sheet-preview')).toBeVisible();
  await page.evaluate(async () => { teamEmpty = true; await loadGuards(); });
  await expect(page.locator('#dtrModal')).not.toHaveClass(/show/);
  await expect(page.locator('#dtrRecordsList')).toBeEmpty();
});

test('Inspector overview counts assigned Guards only', async ({ page }) => {
  await teamMocks(page);
  await page.goto('/inspector/dashboard.html');
  await expect(page.locator('#totalGuards')).toHaveText('1');
  await expect(page.locator('#totalSchedules')).toHaveText('1');
  await expect(page.getByText('My assigned Guards')).toBeVisible();
});

test('Inspector reviews an assigned Guard incident through the secured RPC', async ({ page }) => {
  await teamMocks(page);
  await page.goto('/inspector/incidents.html');
  await expect(page.locator('#incidentTableBody')).toContainText('Assigned Guard');
  await page.locator('#incidentTableBody tr').click();
  const options = await page.locator('#statusSelect option').allInnerTexts();
  expect(options).toEqual(['Under investigation', 'Escalated', 'Resolved']);
  await page.locator('#statusSelect').selectOption('under_investigation');
  await page.locator('#statusNote').fill('Response team notified.');
  await page.getByRole('button', { name: 'Save review' }).click();
  await expect.poll(() => page.evaluate(() => teamRpcCalls)).toEqual([{
    name: 'update_incident_status',
    params: {
      p_incident_id: 'incident-a',
      p_status: 'under_investigation',
      p_status_note: 'Response team notified.',
    },
  }]);
});

test('Inspector dashboard and My Guards show scheduled duty and distinguish awaiting clock-in from clocked-in', async ({ page }) => {
  await teamMocks(page);
  // Set time during duty-a (2026-09-06T02:00:00Z)
  await page.clock.setFixedTime(new Date('2026-09-06T02:00:00Z'));

  // 1. Visit dashboard when guard has not clocked in yet
  await page.goto('/inspector/dashboard.html');
  const roster = page.locator('#liveRosterList');
  await expect(roster).toContainText('Assigned Guard');
  await expect(roster).toContainText('Assigned post');
  await expect(roster).toContainText('Awaiting Clock-In');
  await expect(roster).toContainText('Awaiting Time In');

  // 2. Visit My Guards when guard has not clocked in yet
  await page.goto('/inspector/users.html');
  const userTable = page.locator('#userTableBody');
  await expect(userTable).toContainText('Assigned Guard');
  await expect(userTable).toContainText('Assigned post (Scheduled · Awaiting Time In)');

  // 3. Mock live clock-in for guard-a
  await page.evaluate(() => {
    window.appSupabase.rpc = async (name) => {
      if (name === 'live_guard_map_snapshot') {
        return {
          data: {
            server_now: new Date().toISOString(),
            locations: [{
              user_id: 'guard-a',
              guard_name: 'Assigned Guard',
              location_label: 'Assigned post',
              client_name: 'Assigned post',
              latitude: 14.5995,
              longitude: 120.9842,
              duty_start_at: '2026-09-06T00:00:00Z',
              duty_end_at: '2026-09-06T09:00:00Z',
              mobile_number: '09123456789'
            }]
          },
          error: null
        };
      }
      return { data: null, error: null };
    };
  });

  // Re-check My Guards with live clock-in
  await page.evaluate(() => loadGuards());
  await expect(userTable).toContainText('Assigned post (Clocked in)');

  // Re-check Dashboard with live clock-in
  await page.goto('/inspector/dashboard.html');
  await page.evaluate(() => {
    window.appSupabase.rpc = async (name) => {
      if (name === 'live_guard_map_snapshot') {
        return {
          data: {
            server_now: new Date().toISOString(),
            locations: [{
              user_id: 'guard-a',
              guard_name: 'Assigned Guard',
              location_label: 'Assigned post',
              client_name: 'Assigned post',
              latitude: 14.5995,
              longitude: 120.9842,
              duty_start_at: '2026-09-06T00:00:00Z',
              duty_end_at: '2026-09-06T09:00:00Z',
              mobile_number: '09123456789'
            }]
          },
          error: null
        };
      }
      return { data: null, error: null };
    };
  });
  await page.evaluate(() => loadDashboard());
  await expect(page.locator('#liveRosterList')).toContainText('Live GPS');
  await expect(page.locator('#liveRosterList')).toContainText('View on map');
});
