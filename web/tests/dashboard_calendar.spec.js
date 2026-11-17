const { test, expect } = require('@playwright/test');

test.describe('Dashboard Operations Calendar Future Dates Guard', () => {
    test('does not show attendance badges for future dates (Nov 18-30)', async ({ page }) => {
        await page.route('**/supabase-firebase-bridge.js', route => {
            route.fulfill({
                contentType: 'text/javascript',
                body: `
                    window.firebase = {
                        auth: () => ({
                            onAuthStateChanged: (cb) => {
                                setTimeout(() => cb({ uid: 'admin-1' }), 10);
                            }
                        }),
                        firestore: () => ({
                            collection: () => ({
                                doc: () => ({
                                    get: async () => ({ exists: true, data: () => ({ role: 'admin' }) })
                                })
                            })
                        })
                    };
                    const mockSchedules = [];
                    // Generate 2 schedules for every day in November 2026
                    for (let d = 1; d <= 30; d++) {
                        const dayStr = '2026-11-' + String(d).padStart(2, '0');
                        mockSchedules.push(
                            { id: 'sched-day-' + d, user_id: 'guard-1', location_id: 'loc-1', location_label: 'Balboa Deployment Site', guard_name: 'Juan Santos', start_at: dayStr + 'T06:00:00+08:00', end_at: dayStr + 'T18:00:00+08:00', duty_date: dayStr, approval_status: 'approved' },
                            { id: 'sched-night-' + d, user_id: 'guard-2', location_id: 'loc-1', location_label: 'Balboa Deployment Site', guard_name: 'Pedro Reyes', start_at: dayStr + 'T18:00:00+08:00', end_at: dayStr + 'T23:59:00+08:00', duty_date: dayStr, approval_status: 'approved' }
                        );
                    }
                    const mockAttendance = [
                        { id: 'att-1', user_id: 'guard-1', schedule_id: 'sched-day-1', duty_date: '2026-11-01', scheduled_start_at: '2026-11-01T06:00:00+08:00', clock_in_at: '2026-11-01T05:58:00+08:00', status: 'closed' }
                    ];

                    const mockTables = {
                        profiles: [
                            { id: 'admin-1', role: 'admin', active: true, first_name: 'Operations', last_name: 'Head' },
                            { id: 'guard-1', role: 'user', active: true, first_name: 'Juan', last_name: 'Santos', assigned_location_id: 'loc-1', employment_category: 'regular' },
                            { id: 'guard-2', role: 'user', active: true, first_name: 'Pedro', last_name: 'Reyes', assigned_location_id: 'loc-1', employment_category: 'regular' }
                        ],
                        locations: [
                            { id: 'loc-1', label: 'Balboa Deployment Site', address: 'Camia Street, Bacolod', active: true }
                        ],
                        schedules: mockSchedules,
                        attendance_sessions: mockAttendance,
                        incidents: [],
                        shift_swap_requests: []
                    };

                    function createQuery(tableName) {
                        const tableData = mockTables[tableName] || [];
                        const res = { data: tableData, error: null };
                        const p = Promise.resolve(res);
                        const queryObj = {
                            select: () => queryObj,
                            order: () => queryObj,
                            limit: () => Promise.resolve(res),
                            then: (onFulfill, onReject) => p.then(onFulfill, onReject),
                            catch: (onReject) => p.catch(onReject)
                        };
                        return queryObj;
                    }

                    window.appSupabase = {
                        auth: {
                            getSession: async () => ({ data: { session: { user: { id: 'admin-1' } } } })
                        },
                        from: (tbl) => createQuery(tbl)
                    };
                    window.finishPageLoading = () => {
                        const loader = document.getElementById('loadingScreen');
                        if (loader) loader.style.display = 'none';
                    };
                `
            });
        });

        await page.goto('/admin/dashboard.html');
        await page.addStyleTag({ content: '#loadingScreen { display: none !important; }' });

        // Ensure calendar grid is rendered
        await expect(page.locator('#dashboardCalendarGrid')).toBeVisible({ timeout: 10000 });

        // Day 1 has 1 Present and 1 Absent (since Day 1 is in the past)
        const day1Cell = page.locator('button[data-cal-date="2026-11-01"]');
        await expect(day1Cell.locator('.ig-cal-mini-pill.is-present')).toHaveCount(1);
        await expect(day1Cell.locator('.ig-cal-mini-pill.is-absent')).toHaveCount(1);

        // Future dates from November 18 to November 30 MUST be completely empty of badges
        for (let d = 18; d <= 30; d++) {
            const dateStr = '2026-11-' + String(d).padStart(2, '0');
            const cell = page.locator(`button[data-cal-date="${dateStr}"]`);
            await expect(cell).toBeVisible();

            // Must have zero attendance or incident badges
            const badges = cell.locator('.ig-cal-mini-pill');
            await expect(badges).toHaveCount(0);
        }

        // Clicking on a future date (Nov 18) must show 0 Present and 0 Absent
        const day18Cell = page.locator('button[data-cal-date="2026-11-18"]');
        await day18Cell.click();
        await expect(page.locator('#calSelectedPresent')).toHaveText('0');
        await expect(page.locator('#calSelectedAbsent')).toHaveText('0');
        await expect(page.locator('#calSelectedSwaps')).toHaveText('0');
        await expect(page.locator('#calSelectedIncidents')).toHaveText('0');
        await expect(page.locator('#calSelectedDayDetails')).toContainText('Future date');

        // Test Today button selects today (Nov 17)
        const calTodayBtn = page.locator('#calTodayBtn');
        await calTodayBtn.click();
        const todayCell = page.locator('button[data-cal-date="2026-11-17"]');
        await expect(todayCell).toHaveClass(/is-today/);

        // Test Next button navigates to December 2026 and all dates remain completely empty of attendance badges
        const calNextBtn = page.locator('#calNextBtn');
        await calNextBtn.click();
        await expect(page.locator('#calendarMonthLabel')).toContainText('December 2026');
        const dec1Cell = page.locator('button[data-cal-date="2026-12-01"]');
        await expect(dec1Cell).toBeVisible();
        await expect(dec1Cell.locator('.ig-cal-mini-pill')).toHaveCount(0);
    });
});
