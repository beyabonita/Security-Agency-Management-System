const { expect, test } = require('@playwright/test');

const criticalNotification = {
  id: '11111111-1111-1111-1111-111111111111',
  kind: 'emergency',
  priority: 'critical',
  title: 'Emergency: Fire / hazard',
  message: 'Pedro Dela Cruz reported an incident at Main Gate. Immediate review is required.',
  action_key: 'emergency',
  entity_type: 'incident',
  entity_id: '22222222-2222-2222-2222-222222222222',
  metadata: { category: 'fire', location_label: 'Main Gate' },
  requires_ack: true,
  read_at: null,
  acknowledged_at: null,
  created_at: '2026-08-23T01:00:00Z',
  expires_at: '2026-09-23T01:00:00Z',
};

async function mockAuthenticatedNotificationBackend(page) {
  await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.firebase = {
        auth: () => ({ onAuthStateChanged: () => {}, signOut: async () => {} }),
        firestore: () => ({ collection: () => ({}) })
      };
      window.notificationRpcCalls = [];
      const profile = { id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', role: 'admin', active: true, organization_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' };
      const notifications = [${JSON.stringify(criticalNotification)}];
      const query = (table) => {
        const builder = {
          select: () => builder,
          eq: () => builder,
          order: () => builder,
          maybeSingle: async () => ({ data: table === 'profiles' ? profile : null, error: null }),
          limit: async () => ({ data: table === 'user_notifications' ? notifications : [], error: null }),
        };
        return builder;
      };
      window.appSupabase = {
        auth: {
          getSession: async () => ({ data: { session: { user: { id: profile.id } } } }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
        },
        from: query,
        rpc: async (name, params) => {
          window.notificationRpcCalls.push({ name, params });
          if (name === 'acknowledge_notification') {
            notifications[0].read_at = new Date().toISOString();
            notifications[0].acknowledged_at = new Date().toISOString();
          }
          return { data: name === 'send_broadcast_notification' ? 3 : null, error: null };
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

test('critical emergency notification is persistent until acknowledged', async ({ page }) => {
  await mockAuthenticatedNotificationBackend(page);
  await page.goto('/admin/dashboard.html', { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });

  const bell = page.locator('.sl-notification-bell');
  await expect(bell).toBeVisible();
  await expect(page.locator('.sl-notification-badge')).toHaveText('!');
  await expect(page.getByRole('alertdialog')).toBeVisible();
  await expect(page.getByRole('alertdialog')).toContainText('Emergency: Fire / hazard');
  await expect(page.getByRole('alertdialog')).toContainText('Main Gate');

  await page.getByRole('button', { name: 'Acknowledge alert' }).click();
  await expect(page.getByRole('alertdialog')).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => window.notificationRpcCalls.at(-1)?.name))
    .toBe('acknowledge_notification');
});

test('notification drawer is responsive and exposes HR broadcast controls', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await mockAuthenticatedNotificationBackend(page);
  await page.goto('/admin/dashboard.html', { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.getByRole('button', { name: 'Acknowledge alert' }).click();

  await page.locator('.sl-notification-bell').click();
  const drawer = page.locator('.sl-notification-drawer');
  await expect(drawer).toBeVisible();
  await expect(drawer).toHaveClass(/sl-notification-drawer-open/);
  await expect(drawer).toContainText('Emergency: Fire / hazard');
  await expect(page.getByRole('button', { name: /Send notice/i })).toBeVisible();

  await expect.poll(async () => {
    const bounds = await drawer.boundingBox();
    return bounds ? Math.ceil(bounds.x + bounds.width) : 9999;
  }).toBeLessThanOrEqual(391);
});
