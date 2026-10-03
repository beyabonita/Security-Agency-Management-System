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
  expires_at: null,
};

async function mockAuthenticatedNotificationBackend(page, options = {}) {
  await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.firebase = {
        auth: () => ({ onAuthStateChanged: () => {}, signOut: async () => {} }),
        firestore: () => ({ collection: () => ({}) })
      };
      window.notificationRpcCalls = [];
      const profile = { id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', role: ${JSON.stringify(options.role || 'admin')}, active: true, organization_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' };
      const notifications = ${JSON.stringify(options.notifications || [criticalNotification])};
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
          if (name === 'current_platform_announcement' || name === 'current_platform_support_email') return { data: null, error: null };
          window.notificationRpcCalls.push({ name, params });
          if (name === 'mark_notification_read') {
            if (${!!options.pendingRead}) await new Promise(resolve => { window.finishNotificationRead = resolve; });
            if (${!!options.failRead}) return { data: null, error: { message: 'Network unavailable' } };
          }
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

const normalNotice = {
  ...criticalNotification,
  kind: 'system', priority: 'normal', title: 'TEST', message: 'JUST TESTING\nPlease review this notice.',
  action_key: 'system', entity_type: null, entity_id: null, metadata: {}, requires_ack: false,
  read_at: '2026-08-28T01:09:00Z', acknowledged_at: null,
};

async function openNotice(page, options = {}) {
  await mockAuthenticatedNotificationBackend(page, { notifications: [normalNotice], ...options });
  const folder = { admin: 'admin', inspector: 'inspector', it_admin: 'it-admin' }[options.role || 'admin'];
  await page.goto('/' + folder + '/dashboard.html', { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.locator('.sl-notification-bell').click();
  await page.locator('.sl-notification-item-actions').getByRole('button', { name: /^(View|Open alert)$/ }).click();
  return page.getByRole('dialog');
}

for (const role of ['admin', 'inspector', 'it_admin']) {
  test(role + ' View opens a read notice instead of reloading the dashboard', async ({ page }, info) => {
    await page.addInitScript(() => localStorage.setItem('sentinel-link-theme', 'dark'));
    const dialog = await openNotice(page, { role });
    const originalUrl = page.url();
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('TEST');
    await expect(dialog.locator('.sl-notification-detail-message')).toHaveText(normalNotice.message);
    await expect(dialog).toContainText('Sent');
    await expect(dialog).toContainText('normal');
    await expect(dialog.locator('.sl-notification-detail-status')).toHaveText('Read');
    await expect(page.locator('.sl-notification-drawer')).toBeHidden();
    await expect(page.locator('.sl-notification-backdrop')).toBeHidden();
    await expect(dialog.getByRole('button', { name: /Open/ })).toHaveCount(0);
    expect(await page.evaluate(() => window.notificationRpcCalls)).toEqual([]);
    await page.screenshot({ path: info.outputPath(role + '-notification-detail.png') });
    await dialog.getByRole('button', { name: 'Done', exact: true }).click();
    await expect(page.locator('.sl-notification-drawer')).toBeVisible();
    // Wait beyond the old drawer close timer; it must not hide a reopened drawer.
    await page.waitForTimeout(300);
    await expect(page.locator('.sl-notification-drawer')).toBeVisible();
    await expect(page.locator('.sl-notification-action')).toHaveCSS('color', 'rgb(248, 236, 238)');
    expect(page.url()).toBe(originalUrl);
  });
}

test('View stays usable while marking read and recovers if that update fails', async ({ page }, info) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const dialog = await openNotice(page, {
    notifications: [{ ...normalNotice, read_at: null }], pendingRead: true, failRead: true,
  });
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('.sl-notification-detail-status')).toHaveText('Marking as read…');
  await page.evaluate(() => window.finishNotificationRead());
  await expect(dialog.locator('[data-error="true"]')).toContainText('Could not mark this notification as read');
  await expect(dialog.locator('.sl-notification-detail-message')).toHaveText(normalNotice.message);
  await page.screenshot({ path: info.outputPath('notification-read-failure.png') });
  await dialog.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(page.locator('.sl-notification-item')).toHaveAttribute('data-read', 'false');
  expect(errors).toEqual([]);
});

test('unread notice is marked read once and can be viewed again', async ({ page }) => {
  const dialog = await openNotice(page, { notifications: [{ ...normalNotice, read_at: null }] });
  await expect(dialog.locator('.sl-notification-detail-status')).toHaveText('Read');
  await dialog.getByRole('button', { name: 'Done', exact: true }).click();
  await expect(page.locator('.sl-notification-item')).toHaveAttribute('data-read', 'true');
  await page.locator('.sl-notification-item-actions').getByRole('button', { name: 'View', exact: true }).click();
  await expect(dialog).toBeVisible();
  expect(await page.evaluate(() => window.notificationRpcCalls.filter(call => call.name === 'mark_notification_read').length)).toBe(1);
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(page.locator('.sl-notification-drawer')).toBeVisible();
});

test('inspector can open the duty request page from notification details', async ({ page }) => {
  const dialog = await openNotice(page, { role: 'inspector', notifications: [{
    ...normalNotice, kind: 'shift_request', action_key: 'shift_request', title: 'Duty request submitted',
  }] });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Open duty requests' }).click();
  await expect(page).toHaveURL(/\/inspector\/swaps\.html$/);
});

test('viewing an emergency does not implicitly acknowledge it', async ({ page }) => {
  const dialog = await openNotice(page, { notifications: [{ ...criticalNotification, priority: 'high' }] });
  await expect(dialog).toContainText('Acknowledgement is still required');
  await expect(dialog.getByRole('button', { name: 'Open incident reports' })).toBeVisible();
  expect(await page.evaluate(() => window.notificationRpcCalls.map(call => call.name))).toEqual(['mark_notification_read']);
});

test('mobile notice details safely display long text and unknown actions', async ({ page }, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => localStorage.setItem('sentinel-link-theme', 'dark'));
  const message = '<img src=x onerror="window.notificationXss=true">\n' + 'LongNotice'.repeat(80);
  const dialog = await openNotice(page, { notifications: [{
    ...normalNotice, title: '<script>not a script</script>', message,
    kind: 'unknown', action_key: 'https://example.com',
  }] });
  await expect(dialog.locator('.sl-notification-detail-message')).toHaveText(message);
  await expect(dialog.locator('img, script')).toHaveCount(0);
  await expect(dialog.getByRole('button', { name: /Open/ })).toHaveCount(0);
  expect(await page.evaluate(() => window.notificationXss)).toBeUndefined();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  await dialog.getByRole('button', { name: 'Done', exact: true }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath('notification-details-mobile.png') });
  await dialog.getByRole('button', { name: 'Done', exact: true }).click();
  await expect(dialog).toHaveCount(0);
});

test('dark emergency dialog and notification drawer retain readable text and actions', async ({ page }, info) => {
  await page.addInitScript(() => localStorage.setItem('sentinel-link-theme', 'dark'));
  await mockAuthenticatedNotificationBackend(page);
  await page.goto('/admin/dashboard.html', { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  const alert = page.getByRole('alertdialog');
  await expect(alert).toBeVisible();
  await expect(alert).toHaveCSS('background-color', 'rgb(33, 24, 27)');
  await expect(alert.locator('.sl-critical-message')).toHaveCSS('color', 'rgb(209, 181, 186)');
  await expect(alert.locator('h2')).toHaveCSS('color', 'rgb(248, 236, 238)');
  await page.screenshot({ path: info.outputPath('emergency-dialog-dark.png') });
  await page.getByRole('button', { name: 'Acknowledge alert' }).click();
  await page.locator('.sl-notification-bell').click();
  const drawer = page.locator('.sl-notification-drawer');
  await expect(drawer).toHaveCSS('background-color', 'rgb(33, 24, 27)');
  await expect(drawer.locator('.sl-notification-item-title')).toHaveCSS('color', 'rgb(248, 236, 238)');
  await expect(drawer.locator('.sl-notification-item-message')).toHaveCSS('color', 'rgb(209, 181, 186)');
  await page.screenshot({ path: info.outputPath('notification-drawer-dark.png') });
  await page.evaluate(() => sentinelTheme.set('light'));
  await expect(drawer.locator('.sl-notification-item-title')).toHaveCSS('color', 'rgb(23, 26, 33)');
  await page.evaluate(() => sentinelTheme.set('dark'));
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(drawer).toBeVisible();
  await page.screenshot({ path: info.outputPath('notification-drawer-dark-mobile.png') });
});
