const { test, expect } = require('@playwright/test');
const path = require('node:path');

async function mockRecordsData(page) {
    await page.route('**/supabase-firebase-bridge.js', route => {
        route.fulfill({
            contentType: 'text/javascript',
            body: `
                window.firebase = { auth: () => ({ onAuthStateChanged: () => {} }), firestore: () => ({}) };
                window.appSupabase = {
                    auth: {
                        getUser: async () => ({ data: { user: { id: 'admin-1', email: 'admin@twentytwenty.com' } } }),
                        onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } })
                    },
                    from: (table) => {
                        return {
                            select: () => {
                                const mockData = {
                                    profiles: [
                                        { id: 'admin-1', role: 'admin', active: true, first_name: 'Operations', last_name: 'Head' },
                                        { id: 'guard-1', role: 'user', active: true, personnel_id: 'SEC-2026-0001', first_name: 'Nicor', last_name: 'Bea', gender: 'Male', mobile_number: '09123456789', employment_category: 'regular', contract_status: 'Active', date_hired: '2025-01-10', created_at: '2025-01-10T00:00:00Z', removed_at: null },
                                        { id: 'guard-2', role: 'user', active: false, personnel_id: 'SEC-2026-0002', first_name: 'Maria', last_name: 'Santos', gender: 'Female', mobile_number: '09198765432', employment_category: 'reliever', contract_status: 'Expired', date_hired: '2024-06-15', created_at: '2024-06-15T00:00:00Z', removed_at: '2026-08-01T00:00:00Z' }
                                    ],
                                    locations: [
                                        { id: 'loc-1', label: 'Balboa Deployment Site', address: 'Camia Street, Mandalagan, Bacolod' },
                                        { id: 'loc-2', label: 'SM City Bacolod', address: 'Reclamation Area, Bacolod' }
                                    ],
                                    schedules: [
                                        { id: 'sched-1', user_id: 'guard-1', location_id: 'loc-1', location_label: 'Balboa Deployment Site · Camia St', duty_date: '2026-10-01', start_at: '2026-10-01T06:00:00Z', end_at: '2026-10-01T18:00:00Z', duty_category: 'regular' },
                                        { id: 'sched-2', user_id: 'guard-1', location_id: 'loc-1', location_label: 'Balboa Deployment Site · Camia St', duty_date: '2026-10-02', start_at: '2026-10-02T06:00:00Z', end_at: '2026-10-02T18:00:00Z', duty_category: 'regular' }
                                    ],
                                    attendance_sessions: [
                                        { id: 'sess-1', schedule_id: 'sched-1', user_id: 'guard-1', clock_in_at: '2026-10-01T05:58:00Z', clock_out_at: '2026-10-01T18:05:00Z', overtime_minutes: 60, status: 'closed' },
                                        { id: 'sess-2', schedule_id: 'sched-2', user_id: 'guard-1', clock_in_at: '2026-10-02T06:15:00Z', clock_out_at: '2026-10-02T18:00:00Z', overtime_minutes: 0, status: 'closed' }
                                    ],
                                    incidents: [
                                        { id: 'inc-1', user_id: 'guard-1', guard_name: 'Nicor Bea', category: 'theft', description: 'Attempted shoplifting apprehended at exit.', location_label: 'Balboa Deployment Site', status: 'resolved', status_note: 'Turned over to local police precinct.', video_path: null, photo_data: 'data:image/png;base64,sample', created_at: '2026-10-01T14:30:00Z' },
                                        { id: 'inc-2', user_id: 'guard-2', guard_name: 'Maria Santos', category: 'disturbance', description: 'Intoxicated visitor shouting near lobby.', location_label: 'SM City Bacolod', status: 'open', status_note: '', video_path: 'video.mp4', video_duration_seconds: 15, photo_data: null, created_at: '2026-10-03T19:00:00Z' }
                                    ]
                                };
                                return {
                                    order: () => Promise.resolve({ data: mockData[table] || [], error: null }),
                                    then: (resolve) => resolve({ data: mockData[table] || [], error: null })
                                };
                            }
                        };
                    }
                };
            `
        });
    });
}

test.describe('Records & Reports Module', () => {
    test('renders Records tab in sidebar navigation and opens Records page', async ({ page }) => {
        await mockRecordsData(page);
        await page.goto('/admin/dashboard.html');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        const recordsLink = page.locator('.ax-nav a[href="records.html"]');
        await expect(recordsLink).toBeVisible();
        await expect(recordsLink).toContainText('Records');

        await recordsLink.click();
        await expect(page).toHaveURL(/records\.html/);
        await expect(page.locator('.ax-page-title')).toContainText('Records & Reports');
    });

    test('switches between Personnel Masterlist, Summary of Incident Report, and Monthly Attendance Summary tabs', async ({ page }) => {
        await mockRecordsData(page);
        await page.goto('/admin/records.html');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        // Tab 1: Personnel Masterlist is active by default
        await expect(page.locator('#panel-personnel')).toBeVisible();
        await expect(page.locator('#panel-incidents')).toBeHidden();
        await expect(page.locator('#panel-attendance')).toBeHidden();

        // Switch to Incident Reports tab
        await page.locator('.records-tab-btn[data-tab="incidents"]').click();
        await expect(page.locator('#panel-incidents')).toBeVisible();
        await expect(page.locator('#panel-personnel')).toBeHidden();
        await expect(page.locator('#panel-attendance')).toBeHidden();

        // Switch to Attendance Summary tab
        await page.locator('.records-tab-btn[data-tab="attendance"]').click();
        await expect(page.locator('#panel-attendance')).toBeVisible();
        await expect(page.locator('#panel-incidents')).toBeHidden();
        await expect(page.locator('#panel-personnel')).toBeHidden();
    });

    test('Personnel Masterlist renders required columns and filters properly', async ({ page }) => {
        await mockRecordsData(page);
        await page.goto('/admin/records.html#personnel');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        const headers = page.locator('#pmTable thead th');
        await expect(headers).toContainText([
            'Personnel ID', 'Full Name', 'Gender', 'Contact Number', 'Duty Category',
            'Employment Status', 'Contract Status', 'Date Hired', 'Date of Employment Ended',
            'Client Assigned Post', 'Shift'
        ]);

        const rows = page.locator('#pmTableBody tr');
        await expect(rows).toHaveCount(2);
        await expect(rows.first()).toContainText('Nicor Bea');
        await expect(rows.first()).toContainText('09123456789');

        // Apply Employment Status filter (Active only)
        await page.locator('#pmFilterEmpStatus').selectOption('active');
        await page.locator('#pmBtnApply').click();
        await expect(page.locator('#pmTableBody tr')).toHaveCount(1);
        await expect(page.locator('#pmTableBody')).toContainText('Nicor Bea');
        await expect(page.locator('#pmTableBody')).not.toContainText('Maria Santos');

        // Reset filter
        await page.locator('#pmBtnReset').click();
        await expect(page.locator('#pmTableBody tr')).toHaveCount(2);
    });

    test('Summary of Incident Report renders required columns and filters properly', async ({ page }) => {
        await mockRecordsData(page);
        await page.goto('/admin/records.html#incidents');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        const headers = page.locator('#irTable thead th');
        await expect(headers).toContainText([
            'Incident ID', 'Incident by Client/Post', 'Incident Status',
            'Reported By', 'Response Summary', 'Evidence Summary'
        ]);

        const rows = page.locator('#irTableBody tr');
        await expect(rows).toHaveCount(2);
        await expect(rows.first()).toContainText('Theft');
        await expect(rows.first()).toContainText('Nicor Bea');

        // Filter by Status: Resolved
        await page.locator('#irFilterStatus').selectOption('resolved');
        await page.locator('#irBtnApply').click();
        await expect(page.locator('#irTableBody tr')).toHaveCount(1);
        await expect(page.locator('#irTableBody')).toContainText('resolved');
        await expect(page.locator('#irTableBody')).not.toContainText('open');

        // Reset filter
        await page.locator('#irBtnReset').click();
        await expect(page.locator('#irTableBody tr')).toHaveCount(2);
    });

    test('Monthly Attendance Summary renders required columns and aggregates stats', async ({ page }) => {
        await mockRecordsData(page);
        await page.goto('/admin/records.html#attendance');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        const headers = page.locator('#attTable thead th');
        await expect(headers).toContainText([
            'Personnel', 'Total Scheduled Duty Days', 'Total Present',
            'Total Absent', 'Total Late', 'Total Overtime Hours'
        ]);

        // Filter for October 2026
        await page.locator('#attFilterMonth').selectOption('10');
        await page.locator('#attFilterYear').selectOption('2026');
        await page.locator('#attBtnApply').click();

        const rows = page.locator('#attTableBody tr');
        await expect(rows).toHaveCount(2);
        const nicorRow = rows.filter({ hasText: 'Nicor Bea' });
        await expect(nicorRow).toContainText('2'); // 2 scheduled days
        await expect(nicorRow).toContainText('1.0 hrs'); // 60 mins overtime
    });

    test('supports dark mode and responsive layout', async ({ page }) => {
        await mockRecordsData(page);
        await page.addInitScript(() => localStorage.setItem('sentinel-link-theme', 'dark'));
        await page.setViewportSize({ width: 390, height: 844 });
        await page.goto('/admin/records.html');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        await expect(page.locator('.records-container')).toBeVisible();
        await expect(page.locator('#pmTable')).toBeVisible();
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(391);
    });
});
