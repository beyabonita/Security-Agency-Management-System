const { expect, test } = require('@playwright/test');

test('Operations Head dashboard renders deployment, contract, attendance, and incident summaries', async ({ page }) => {
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.3', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      const rows = {
        profiles: [
          { id: 'hr', role: 'admin', active: true, first_name: 'Nico', last_name: 'Bea' },
          { id: 'guard-day', role: 'user', active: true, assigned_location_id: 'site-a', employment_category: 'contract', contract_start_date: '2026-01-01', contract_end_date: '2026-12-31' },
          { id: 'guard-night', role: 'user', active: true, assigned_location_id: 'site-a', employment_category: 'contract', contract_start_date: '2026-01-01', contract_end_date: '2026-10-20' },
          { id: 'inspector-a', role: 'inspector', active: true }
        ],
        locations: [
          { id: 'site-a', label: 'State University of Northern Negros', address: 'Sagay', active: true }
        ],
        schedules: [
          { id: 'schedule-day', user_id: 'guard-day', location_id: 'site-a', location_label: 'State University of Northern Negros', location_address: 'Sagay', guard_name: 'Day Guard', start_at: '2026-10-04T00:00:00Z', end_at: '2026-10-04T10:00:00Z', duty_date: '2026-10-04', approval_status: 'approved' },
          { id: 'schedule-night', user_id: 'guard-night', location_id: 'site-a', location_label: 'State University of Northern Negros', location_address: 'Sagay', guard_name: 'Night Guard', start_at: '2026-10-04T12:00:00Z', end_at: '2026-10-04T22:00:00Z', duty_date: '2026-10-04', approval_status: 'approved' }
        ],
        attendance_sessions: [
          { id: 'session-day', user_id: 'guard-day', schedule_id: 'schedule-day', location_id: 'site-a', location_label: 'State University of Northern Negros', duty_date: '2026-10-04', scheduled_start_at: '2026-10-04T00:00:00Z', clock_in_at: '2026-10-04T00:03:00Z', status: 'open' }
        ],
        incidents: [
          { id: 'incident-a', user_id: 'guard-day', category: 'fire', location_label: 'Sagay', status: 'open', created_at: '2026-10-04T02:00:00Z', captured_at: '2026-10-04T02:00:00Z' }
        ]
      };
      function snapshot(data) {
        return {
          size: data.length,
          docs: data.map(row => ({ id: row.id, exists: true, data: () => row })),
          forEach(callback) { this.docs.forEach(callback); }
        };
      }
      function query(table) {
        const source = table === 'users' ? 'profiles' : table;
        const api = {
          select() { return api; },
          order() { return api; },
          limit() { return Promise.resolve({ data: rows[source] || [], error: null }); },
          eq(field, value) { return { get: async () => snapshot((rows[source] || []).filter(row => row[field] === value)) }; },
          async get() { return snapshot(rows[source] || []); },
          doc(id) { return { get: async () => ({ exists: true, data: () => (rows[source] || []).find(row => row.id === id) || {} }) }; },
          then(resolve) { return resolve({ data: rows[source] || [], error: null }); }
        };
        return api;
      }
      window.firebase = {
        auth: () => ({ onAuthStateChanged: callback => setTimeout(() => callback({ uid: 'hr' }), 0), signOut: async () => {} }),
        firestore: () => ({ collection: table => query(table) })
      };
      window.appSupabase = { from: table => query(table), auth: { getSession: async () => ({ data: { session: null } }) } };
      window.appDialog = { toast: message => { window.lastToast = message; } };
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };
    `,
  }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.goto('/admin/dashboard.html', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#totalGuards')).toHaveText('2');
  await expect(page.locator('#totalDeployed')).toHaveText('2');
  await expect(page.locator('#totalLocations')).toHaveText('1');
  await expect(page.locator('#totalInspectors')).toHaveText('1');
  await expect(page.locator('#deploymentTableBody')).toContainText('State University of Northern Negros');
  await expect(page.locator('#deploymentTableBody')).toContainText('Sagay');
  await expect(page.locator('#contractLegend')).toContainText('Active Contract');
  await expect(page.locator('#attendanceLegend')).toContainText('Present');
  await expect(page.locator('#recentIncidentTableBody')).toContainText('Fire / hazard');
  await expect(page.locator('#recentIncidentTableBody tr').first()).toHaveAttribute('data-incident-id', 'incident-a');
  await expect(page.locator('#incidentSummary')).toContainText('Sagay');
  await expect(page.locator('#incidentSummary')).toContainText('Highest incident area');
  await expect(page.locator('#incidentSummary')).toContainText('Top reporting guard');
  await expect(page.locator('#incidentSummary')).toContainText('Top incident rate');
  await expect(page.locator('#incidentSummary')).toContainText('Open: 1');
  await page.click('#incidentTimeFilter button[data-days="365"]');
  await expect(page.locator('#incidentTimeFilter button[data-days="365"]')).toHaveClass(/is-active/);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
