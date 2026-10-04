const { expect, test } = require('@playwright/test');

const accomplishmentNotice = {
  id: '33333333-3333-3333-3333-333333333333',
  kind: 'accomplishment',
  priority: 'normal',
  title: 'New accomplishment report',
  message: 'A Guard submitted an accomplishment report for review.',
  action_key: 'accomplishment',
  entity_type: 'accomplishment_report',
  entity_id: 'report-target-123',
  metadata: { guard_id: 'guard-test-456', review_status: 'submitted' },
  requires_ack: false,
  read_at: null,
  acknowledged_at: null,
  created_at: '2026-10-05T02:37:00Z',
  expires_at: null,
};

const mockGuardUser = {
  id: 'guard-test-456',
  firstName: 'Juan',
  lastName: 'Dela Cruz',
  role: 'user',
  active: true,
};

const mockReports = [
  {
    id: 'report-old-001',
    guard_id: 'guard-test-456',
    summary: 'Previous routine patrol',
    detailed_narrative: 'All perimeter gates secured and checked.',
    review_status: 'reviewed',
    submitted_at: '2026-10-04T10:00:00Z',
    reviewed_at: '2026-10-04T12:00:00Z',
    review_note: 'Approved good work.',
  },
  {
    id: 'report-target-123',
    guard_id: 'guard-test-456',
    summary: 'Night perimeter inspection',
    detailed_narrative: 'Detected broken lock on south entrance, posted warning sign.',
    review_status: 'submitted',
    submitted_at: '2026-10-05T02:37:00Z',
    reviewed_at: null,
    review_note: null,
  },
];

async function setupMockBackend(page) {
  await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.firebase = {
        auth: () => ({
          onAuthStateChanged: (cb) => {
            setTimeout(() => cb({ uid: 'admin-user-id', email: 'admin@test.com' }), 0);
          },
          signOut: async () => {}
        }),
        firestore: () => ({
          collection: (name) => {
            if (name === 'users') {
              return {
                doc: (id) => ({
                  get: async () => ({
                    exists: true,
                    data: () => id === 'admin-user-id' ? { role: 'admin' } : (id === 'guard-test-456' ? ${JSON.stringify(mockGuardUser)} : null)
                  })
                }),
                get: async () => ({
                  forEach: (fn) => {
                    fn({ id: 'guard-test-456', data: () => ${JSON.stringify(mockGuardUser)} });
                    fn({ id: 'admin-user-id', data: () => ({ role: 'admin' }) });
                  }
                })
              };
            }
            return {
              doc: () => ({ get: async () => ({ exists: false }) }),
              get: async () => ({ forEach: () => {} })
            };
          }
        })
      };

      const profile = { id: 'admin-user-id', role: 'admin', active: true, organization_id: 'org-123' };
      const notifications = [${JSON.stringify(accomplishmentNotice)}];
      const reports = ${JSON.stringify(mockReports)};

      window.appSupabase = {
        auth: {
          getSession: async () => ({ data: { session: { user: { id: profile.id } } } }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
        },
        from: (table) => {
          let filterCol = null;
          let filterVal = null;
          const createBuilder = () => ({
            select: () => createBuilder(),
            eq: (col, val) => {
              filterCol = col;
              filterVal = val;
              return createBuilder();
            },
            abortSignal: () => createBuilder(),
            limit: async () => {
              if (table === 'user_notifications') return { data: notifications, error: null };
              return { data: [], error: null };
            },
            maybeSingle: async () => {
              if (table === 'profiles') return { data: profile, error: null };
              if (table === 'accomplishment_reports') {
                const found = reports.find(r => r[filterCol] === filterVal);
                return { data: found || null, error: null };
              }
              return { data: null, error: null };
            },
            then: (resolve, reject) => {
              if (table === 'accomplishment_reports') {
                const filtered = filterCol
                  ? reports.filter(r => r[filterCol] === filterVal)
                  : reports;
                return Promise.resolve({ data: filtered, error: null }).then(resolve, reject);
              }
              return Promise.resolve({ data: [], error: null }).then(resolve, reject);
            }
          });
          return createBuilder();
        },
        rpc: async (name) => {
          if (name === 'current_platform_announcement' || name === 'current_platform_support_email') return { data: null, error: null };
          if (name === 'mark_notification_read') return { data: null, error: null };
          return { data: null, error: null };
        },
        channel: () => ({
          on() { return this; },
          subscribe() { return this; },
        }),
        removeChannel: async () => {},
      };
    `,
  }));
}

test('clicking open personnel reports from notification navigates and highlights specific report', async ({ page }) => {
  await setupMockBackend(page);
  await page.goto('/admin/dashboard.html');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });

  // Open notification drawer
  const bell = page.locator('.sl-notification-bell');
  await expect(bell).toBeVisible();
  await bell.click();

  const drawer = page.locator('.sl-notification-drawer');
  await expect(drawer).toBeVisible();

  // Find accomplishment notification item and click View
  const item = page.locator('.sl-notification-item', { hasText: 'New accomplishment report' });
  await expect(item).toBeVisible();
  await item.getByRole('button', { name: 'View' }).click();

  // The dialog opens
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText('New accomplishment report');

  const actionBtn = dialog.getByRole('button', { name: 'Open personnel reports' });
  await expect(actionBtn).toBeVisible();

  // Clicking Open personnel reports navigates to users.html with query params
  await actionBtn.click();
  await page.waitForURL(/\/admin\/users\.html\?reportId=report-target-123&guardId=guard-test-456/);

  // Users page opens the accomplishment modal
  const modal = page.locator('#accomplishmentModal');
  await expect(modal).toBeVisible();
  await expect(page.locator('#accomplishmentGuardName')).toContainText('Juan Dela Cruz');

  // Verify the target report card is rendered with the target class and Target Report badge
  const targetCard = page.locator('#accomplishment-report-target-123');
  await expect(targetCard).toBeVisible();
  await expect(targetCard).toHaveClass(/target-accomplishment-card/);
  await expect(targetCard).toContainText('Target Report');
  await expect(targetCard).toContainText('Night perimeter inspection');
  await expect(targetCard).toContainText('Detected broken lock on south entrance');
});

test('direct load with reportId query parameter automatically opens target report', async ({ page }) => {
  await setupMockBackend(page);
  await page.goto('/admin/users.html?reportId=report-target-123');
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });

  const modal = page.locator('#accomplishmentModal');
  await expect(modal).toBeVisible();
  await expect(page.locator('#accomplishmentGuardName')).toContainText('Juan Dela Cruz');

  const targetCard = page.locator('#accomplishment-report-target-123');
  await expect(targetCard).toBeVisible();
  await expect(targetCard).toHaveClass(/target-accomplishment-card/);
  await expect(targetCard).toContainText('Target Report');
});
