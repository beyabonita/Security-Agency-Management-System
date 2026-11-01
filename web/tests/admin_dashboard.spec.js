const { expect, test } = require('@playwright/test');

test('Operations Head dashboard renders infographic KPIs, deployment bars, donuts, and incident cards', async ({ page }) => {
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.3', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      const todayManila = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
      const dayStartIso = todayManila + 'T08:00:00+08:00';
      const dayEndIso = todayManila + 'T18:00:00+08:00';
      const nightStartIso = todayManila + 'T20:00:00+08:00';
      const nightEndIso = todayManila + 'T23:59:00+08:00';
      const clockInIso = todayManila + 'T08:03:00+08:00';
      const incidentIso = new Date(Date.now() - 2 * 3600 * 1000).toISOString();

      const rows = {
        profiles: [
          { id: 'hr', role: 'admin', active: true, first_name: 'Nico', last_name: 'Bea' },
          { id: 'guard-day', role: 'user', active: true, first_name: 'Juan', last_name: 'Santos', assigned_location_id: 'site-a', employment_category: 'contract', contract_start_date: '2026-01-01', contract_end_date: '2099-12-31' },
          { id: 'guard-night', role: 'user', active: true, first_name: 'Pedro', last_name: 'Reyes', assigned_location_id: 'site-a', employment_category: 'contract', contract_start_date: '2025-01-01', contract_end_date: '2025-10-20' },
          { id: 'inspector-a', role: 'inspector', active: true }
        ],
        locations: [
          { id: 'site-a', label: 'State University of Northern Negros', address: 'Sagay', active: true }
        ],
        schedules: [
          { id: 'schedule-day', user_id: 'guard-day', location_id: 'site-a', location_label: 'State University of Northern Negros', location_address: 'Sagay', guard_name: 'Day Guard', start_at: dayStartIso, end_at: dayEndIso, duty_date: todayManila, approval_status: 'approved' },
          { id: 'schedule-night', user_id: 'guard-night', location_id: 'site-a', location_label: 'State University of Northern Negros', location_address: 'Sagay', guard_name: 'Night Guard', start_at: nightStartIso, end_at: nightEndIso, duty_date: todayManila, approval_status: 'approved' }
        ],
        attendance_sessions: [
          { id: 'session-day', user_id: 'guard-day', schedule_id: 'schedule-day', location_id: 'site-a', location_label: 'State University of Northern Negros', duty_date: todayManila, scheduled_start_at: dayStartIso, clock_in_at: clockInIso, status: 'open' }
        ],
        incidents: [
          { id: 'incident-a', user_id: 'guard-day', category: 'fire', location_label: 'Sagay', status: 'under_investigation', created_at: incidentIso, captured_at: incidentIso }
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
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto('/admin/dashboard.html', { waitUntil: 'domcontentloaded' });

  // Plain HTML tables are replaced with visual infographics
  await expect(page.locator('table')).toHaveCount(0);

  // 1. KPI Infographic Cards
  await expect(page.locator('#totalGuards')).toHaveText('2');
  await expect(page.locator('#guardsPctPill')).toHaveText('100% active');
  await expect(page.locator('#totalDeployed')).toHaveText('2');
  await expect(page.locator('#deployedPctPill')).toHaveText('100% deployed');
  await expect(page.locator('#totalLocations')).toHaveText('1');
  await expect(page.locator('#totalInspectors')).toHaveText('1');
  await expect(page.locator('#inspectorPctPill')).toHaveText('1 : 2 guards');

  // 2. Client Deployment Infographic Banner & Stacked Bar Cards
  await expect(page.locator('#deploySiteCount')).toHaveText('1');
  await expect(page.locator('#deployTotalAssigned')).toHaveText('2');
  await expect(page.locator('#deployDayTotal')).toHaveText('1');
  await expect(page.locator('#deployNightTotal')).toHaveText('1');
  await expect(page.locator('#deployDayPctLabel')).toHaveText('Day shift 50%');
  await expect(page.locator('#deploymentInfographicList')).toContainText('State University of Northern Negros');
  await expect(page.locator('#deploymentInfographicList')).toContainText('Sagay');
  await expect(page.locator('#deploymentInfographicList .ig-deploy-bar-day')).toHaveCount(1);
  await expect(page.locator('#deploymentInfographicList .ig-deploy-bar-night')).toHaveCount(1);

  // Filter interactivity on deployment infographic
  await page.selectOption('#deploymentShiftFilter', 'day');
  await expect(page.locator('#deployTotalAssigned')).toHaveText('1');
  await expect(page.locator('#deployNightTotal')).toHaveText('0');
  await page.selectOption('#deploymentShiftFilter', '');
  await page.fill('#deploymentSearch', 'nonexistent-site');
  await expect(page.locator('#deploymentInfographicList .ig-empty-state')).toContainText('No deployment records match the filters.');
  await page.fill('#deploymentSearch', '');
  await expect(page.locator('#deployTotalAssigned')).toHaveText('2');

  // 3. Contract & Attendance Donuts + Horizontal Progress Bars
  await expect(page.locator('#contractDonutTotal')).toHaveText('2');
  await expect(page.locator('#contractLegend')).toContainText('Active Contract');
  await expect(page.locator('#contractLegend .ig-legend-fill')).toHaveCount(3);
  await expect(page.locator('#attendanceDonutTotal')).toHaveText('2');
  await expect(page.locator('#attendanceLegend')).toContainText('Present');
  await expect(page.locator('#attendanceMetaFooter')).toContainText('Check-in rate: 50%');

  // 4. Recent Incidents Infographic Cards & Incident Intelligence Bar Charts
  await expect(page.locator('#recentIncidentFeed')).toContainText('Fire / hazard');
  await expect(page.locator('#recentIncidentFeed .ig-incident-card').first()).toHaveAttribute('data-incident-id', 'incident-a');
  await expect(page.locator('#incidentSummary')).toContainText('Sagay');
  await expect(page.locator('#incidentSummary')).toContainText('Juan Santos');
  await expect(page.locator('#incidentSummary')).toContainText('Highest incident area');
  await expect(page.locator('#incidentSummary')).toContainText('Top reporting guard');
  await expect(page.locator('#incidentSummary')).toContainText('Top incident rate');
  await expect(page.locator('#incidentSummary')).toContainText('Under investigation: 1');
  expect(await page.locator('#incidentSummary .ig-rank-bar-fill').count()).toBeGreaterThanOrEqual(3);

  await page.click('#incidentTimeFilter button[data-days="365"]');
  await expect(page.locator('#incidentTimeFilter button[data-days="365"]')).toHaveClass(/is-active/);

  // Desktop & Mobile responsive containment
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);

  // Dark mode legibility & surface check on infographic elements
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  for (const selector of ['.ig-kpi-card', '.ig-deploy-card', '.ig-incident-card', '.ig-legend-label', '.incident-status-pill.investigation']) {
    const metrics = await page.locator(selector).first().evaluate(el => {
      const rgb = v => (v.match(/[\d.]+/g) || []).map(Number);
      const lum = v => {
        const c = rgb(v).slice(0, 3).map(n => n / 255).map(n => n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4);
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
      };
      let bgEl = el;
      while (bgEl.parentElement && (rgb(getComputedStyle(bgEl).backgroundColor)[3] ?? 1) < 0.8) bgEl = bgEl.parentElement;
      const a = lum(getComputedStyle(el).color);
      const b = lum(getComputedStyle(bgEl).backgroundColor);
      return { bgLum: b, contrast: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) };
    });
    expect(metrics.bgLum, selector + ' dark background').toBeLessThan(0.15);
    expect(metrics.contrast, selector + ' dark contrast').toBeGreaterThanOrEqual(4.5);
  }
});
