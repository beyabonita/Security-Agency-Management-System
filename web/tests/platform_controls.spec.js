const { expect, test } = require('@playwright/test');

const initialSettings = {
  support_email: 'support@example.com',
  default_geofence_radius: 100,
  portal_announcement: '',
  portal_announcement_enabled: false,
  updated_at: '2026-09-04T01:00:00Z',
};

const pageErrors = new WeakMap();
test.beforeEach(async ({ page }) => {
  const errors = [];
  pageErrors.set(page, errors);
  page.on('pageerror', error => errors.push(error.message));
});
test.afterEach(async ({ page }) => {
  expect(pageErrors.get(page), 'No uncaught browser errors').toEqual([]);
});

async function mockPlatformBackend(page, options = {}) {
  // All network access outside the local fixture server is blocked, including
  // the real SDK. The bridge below is the only backend used by these tests.
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return url.origin === 'http://127.0.0.1:4173'
      ? route.continue()
      : route.fulfill({ contentType: 'text/javascript', body: '' });
  });
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `(() => {
      const options = ${JSON.stringify(options)};
      const profile = {
        id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        role: options.role || 'it_admin', active: true,
        organization_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        firstName: 'Platform', lastName: 'Tester'
      };
      const state = window.platformTestBackend = {
        settings: { ...${JSON.stringify(initialSettings)}, ...options.settings },
        calls: [], queries: [],
        settingsError: options.settingsError || null,
        auditError: options.auditError || null,
        saveError: options.saveError || null,
        holdSave: !!options.holdSave,
        holdAudit: !!options.holdAudit,
        savedSettings: options.savedSettings || null
      };
      const copy = value => JSON.parse(JSON.stringify(value));
      const resultFor = async (table, single) => {
        state.queries.push(table);
        if (table === 'platform_settings') return {
          data: state.settingsError ? null : copy(state.settings),
          error: state.settingsError ? { message: state.settingsError } : null
        };
        if (table === 'platform_settings_audit') {
          if (state.holdAudit) await new Promise(resolve => { state.releaseAudit = resolve; });
          return {
            data: state.auditError ? null : [{ changed_at: '2026-09-04T02:00:00Z', changed_fields: ['support_email'] }],
            error: state.auditError ? { message: state.auditError } : null
          };
        }
        if (table === 'organizations') return {
          data: { id: profile.organization_id, name: 'Test Workspace', active: true }, error: null
        };
        if (table === 'profiles') return { data: single ? profile : [profile], error: null };
        return { data: [], error: null };
      };
      const query = table => {
        const builder = {
          select() { return this; }, eq() { return this; }, order() { return this; },
          in() { return this; }, limit() { return this; }, is() { return this; },
          maybeSingle: () => resultFor(table, true),
          then: (resolve, reject) => resultFor(table, false).then(resolve, reject)
        };
        return builder;
      };
      const emptySnapshot = { size: 0, empty: true, docs: [], forEach() {} };
      const collection = () => {
        const builder = {
          where() { return this; }, orderBy() { return this; }, limit() { return this; },
          get: async () => emptySnapshot,
          doc: () => ({ get: async () => ({ exists: true, data: () => profile }) })
        };
        return builder;
      };
      window.firebase = {
        auth: () => ({
          onAuthStateChanged: callback => setTimeout(() => callback(options.signedOut ? null : { uid: profile.id }), 0),
          signOut: async () => {}
        }),
        firestore: () => ({ collection })
      };
      window.appSupabase = {
        auth: {
          getSession: async () => ({ data: { session: options.signedOut ? null : { user: { id: profile.id } } } }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } })
        },
        from: query,
        rpc: async (name, params) => {
          state.calls.push({ name, params });
          if (name === 'current_platform_announcement') return {
            data: state.settings.portal_announcement_enabled ? state.settings.portal_announcement : '', error: null
          };
          if (name === 'current_platform_support_email') return { data: state.settings.support_email, error: null };
          if (name === 'update_platform_settings') {
            if (state.holdSave) await new Promise(resolve => { state.releaseSave = resolve; });
            if (state.saveError) return { data: null, error: { message: state.saveError } };
            state.settings = {
              support_email: params.p_support_email,
              default_geofence_radius: params.p_default_geofence_radius,
              portal_announcement: params.p_portal_announcement,
              portal_announcement_enabled: params.p_portal_announcement_enabled,
              updated_at: '2026-09-04T02:00:00Z',
              ...state.savedSettings
            };
            return { data: options.returnArray ? [copy(state.settings)] : copy(state.settings), error: null };
          }
          throw new Error('Unexpected mock RPC: ' + name);
        },
        channel: () => ({ on() { return this; }, subscribe() { return this; } }),
        removeChannel: async () => {}
      };
    })();`,
  }));
}

async function openControls(page, options = {}) {
  await mockPlatformBackend(page, options);
  await page.goto('/it-admin/clients.html', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  if (!options.settingsError) await expect(page.locator('#savePlatformSettings')).toBeEnabled();
}

async function savedCalls(page) {
  return page.evaluate(() => window.platformTestBackend.calls.filter(call => call.name === 'update_platform_settings'));
}

async function fillSettings(page, { email = 'updated@example.com', radius = '275', announcement = 'Updated portal notice', enabled = true } = {}) {
  await page.locator('#supportEmail').fill(email);
  await page.locator('#defaultGeofenceRadius').fill(radius);
  await page.locator('#portalAnnouncement').fill(announcement);
  await page.locator('#portalAnnouncementEnabled').setChecked(enabled);
}

for (const submitMethod of ['button', 'Enter']) {
  test(`${submitMethod} submits the real form and renders the RPC-returned settings`, async ({ page }) => {
    await openControls(page, {
      returnArray: submitMethod === 'Enter',
      savedSettings: { support_email: 'canonical@example.com', default_geofence_radius: 350, portal_announcement: 'Saved server notice' },
    });
    await fillSettings(page, { announcement: '  Updated portal notice  ' });
    if (submitMethod === 'button') await page.getByRole('button', { name: 'Save configuration', exact: true }).click();
    else await page.locator('#supportEmail').press('Enter');

    await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
    expect(await savedCalls(page)).toEqual([{
      name: 'update_platform_settings',
      params: {
        p_support_email: 'updated@example.com', p_default_geofence_radius: 275,
        p_portal_announcement: 'Updated portal notice', p_portal_announcement_enabled: true,
      },
    }]);
    await expect(page.locator('#supportEmail')).toHaveValue('canonical@example.com');
    await expect(page.locator('#defaultGeofenceRadius')).toHaveValue('350');
    await expect(page.locator('#portalAnnouncement')).toHaveValue('Saved server notice');
    await expect(page.locator('[data-platform-announcement]')).toContainText('Saved server notice');
    await expect(page.locator('[data-platform-support]')).toHaveCount(0);
    await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
    await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  });
}

test('publishing requires three trimmed characters and input changes recover validation', async ({ page }) => {
  await openControls(page);
  await fillSettings(page, { announcement: '  ab  ' });
  await page.locator('#savePlatformSettings').click();
  expect(await savedCalls(page)).toEqual([]);
  await expect(page.locator('#portalAnnouncement')).toHaveJSProperty('validationMessage', 'Enter an announcement of at least 3 characters before publishing.');
  await expect(page.locator('#savePlatformSettings')).toBeEnabled();

  await page.locator('#portalAnnouncement').fill(' abc ');
  await page.locator('#savePlatformSettings').click();
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  expect((await savedCalls(page))[0].params.p_portal_announcement).toBe('abc');
  await page.locator('#portalAnnouncementEnabled').uncheck();
  await page.locator('#portalAnnouncement').fill('');
  await page.locator('#savePlatformSettings').click();
  await expect.poll(async () => (await savedCalls(page)).length).toBe(2);
  expect((await savedCalls(page))[1].params).toMatchObject({ p_portal_announcement: '', p_portal_announcement_enabled: false });
  await expect(page.locator('[data-platform-announcement]')).toHaveCount(0);
});

test('radius validation rejects missing, out-of-range and fractional values and accepts both boundaries', async ({ page }) => {
  await openControls(page);
  const radius = page.locator('#defaultGeofenceRadius');
  for (const value of ['', '24', '1001', '25.5']) {
    await radius.fill(value);
    await page.locator('#savePlatformSettings').click();
    expect(await radius.evaluate(element => element.validity.valid)).toBe(false);
    expect(await savedCalls(page)).toEqual([]);
    await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  }
  for (const value of ['25', '1000']) {
    await radius.fill(value);
    await page.locator('#savePlatformSettings').click();
    await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
    expect((await savedCalls(page)).at(-1).params.p_default_geofence_radius).toBe(Number(value));
  }
  expect((await savedCalls(page)).length).toBe(2);
});

test('a failed save preserves entered fields and clears busy state so retry succeeds', async ({ page }) => {
  await openControls(page, { holdSave: true, saveError: 'Configuration service unavailable' });
  await fillSettings(page);
  await page.locator('#savePlatformSettings').click();
  await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'true');
  await expect(page.locator('#savePlatformSettings')).toHaveText('Saving configuration…');
  await expect(page.locator('#supportEmail')).toBeDisabled();
  await page.evaluate(() => window.platformTestBackend.releaseSave());
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration service unavailable');
  await expect(page.locator('#supportEmail')).toHaveValue('updated@example.com');
  await expect(page.locator('#defaultGeofenceRadius')).toHaveValue('275');
  await expect(page.locator('#portalAnnouncement')).toHaveValue('Updated portal notice');
  await expect(page.locator('#portalAnnouncementEnabled')).toBeChecked();
  await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  await expect(page.locator('#savePlatformSettings')).toHaveText('Save configuration');
  await page.evaluate(() => {
    window.platformTestBackend.saveError = null;
    window.platformTestBackend.holdSave = false;
  });
  await page.locator('#savePlatformSettings').click();
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  expect((await savedCalls(page)).length).toBe(2);
});

test('an in-flight save blocks duplicate submissions and preserves the submitted snapshot', async ({ page }) => {
  await openControls(page, { holdSave: true });
  await fillSettings(page);
  await page.locator('#savePlatformSettings').click();
  await expect(page.locator('#savePlatformSettings')).toBeDisabled();
  await expect(page.locator('#platformSettingsFields')).toHaveJSProperty('disabled', true);
  // Exercise the handler guard even if a second submit event arrives while
  // native interaction is disabled. The first submission remains a real click.
  await page.locator('#platformSettingsForm').dispatchEvent('submit');
  await page.locator('#platformSettingsForm').dispatchEvent('submit');
  expect((await savedCalls(page)).length).toBe(1);
  await page.evaluate(() => window.platformTestBackend.releaseSave());
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  expect((await savedCalls(page))[0].params.p_support_email).toBe('updated@example.com');
});

test('removed audit and administrative sections are not rendered or queried', async ({page}) => {
 await openControls(page);
 await expect(page.getByRole('heading',{name:'Recent configuration changes'})).toHaveCount(0);
 await expect(page.getByRole('heading',{name:'Administrative actions'})).toHaveCount(0);
 expect(await page.evaluate(()=>platformTestBackend.queries.includes('platform_settings_audit'))).toBe(false);
});

test('a configuration load failure disables the form until Retry loading succeeds', async ({ page }) => {
  await openControls(page, { settingsError: 'Could not load platform configuration' });
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Could not load platform configuration');
  await expect(page.locator('#platformSettingsFields')).toHaveJSProperty('disabled', true);
  await expect(page.locator('#supportEmail')).toBeDisabled();
  await expect(page.locator('#savePlatformSettings')).toBeDisabled();
  await page.locator('#platformSettingsForm').dispatchEvent('submit');
  expect(await savedCalls(page)).toEqual([]);
  await page.evaluate(() => { window.platformTestBackend.settingsError = null; });
  await page.getByRole('button', { name: 'Retry loading', exact: true }).click();
  await expect(page.locator('#reloadPlatformSettings')).toBeHidden();
  await expect(page.locator('#supportEmail')).toHaveValue(initialSettings.support_email);
  await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  await fillSettings(page);
  await page.locator('#savePlatformSettings').click();
  await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  expect((await savedCalls(page)).length).toBe(1);
});

const surfaces = [
  { path: '/staff/login.html', signedOut: true },
  { path: '/system-access-7d92a4/login.html', signedOut: true },
  { path: '/admin/dashboard.html', role: 'admin' },
  { path: '/inspector/dashboard.html', role: 'inspector' },
  { path: '/it-admin/dashboard.html', role: 'it_admin' },
];

for (const surface of surfaces) {
  test(`${surface.path} opens support without leaving the page and supports keyboard copy`, async ({ page }) => {
    await mockPlatformBackend(page, surface);
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
        writeText: async value => { window.copiedSupportEmail = value; },
      } });
    });
    await page.goto(surface.path);
    const trigger = page.locator('[data-platform-support] a');
    await trigger.click();
    const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByLabel('Support email', { exact: true })).toHaveValue('support@example.com');
    await expect(dialog.getByRole('link', { name: 'Open email app' })).toHaveAttribute('href', 'mailto:support@example.com');
    await dialog.getByRole('button', { name: 'Copy email', exact: true }).press('Enter');
    await expect(dialog.getByRole('status')).toHaveText('Email address copied.');
    expect(await page.evaluate(() => window.copiedSupportEmail)).toBe('support@example.com');
    await expect(dialog).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect(trigger).toBeFocused();
    await page.evaluate(async () => {
      window.platformTestBackend.settings.support_email = 'help+new@example.com';
      await window.platformConfiguration.refresh();
    });
    await trigger.press('Enter');
    await expect(dialog.getByLabel('Support email', { exact: true })).toHaveValue('help+new@example.com');
    // Intercept the external protocol in the test only; never send mail or open an OS app.
    await dialog.getByRole('link', { name: 'Open email app' }).evaluate(link => {
      link.addEventListener('click', event => { event.preventDefault(); window.supportMailActivated = link.href; });
    });
    await dialog.getByRole('link', { name: 'Open email app' }).press('Enter');
    expect(await page.evaluate(() => window.supportMailActivated)).toBe('mailto:help%2Bnew@example.com');
    await expect(dialog.getByRole('status')).toContainText('If your email app does not open');
    await dialog.getByRole('button', { name: 'Done', exact: true }).click();
    expect(await savedCalls(page)).toEqual([]);
    await expect(page).toHaveURL(new RegExp(surface.path.replaceAll('.', '\\.') + '$'));
  });

  test(`${surface.path} refreshes support and safe announcement text without duplicates`, async ({ page }) => {
    await mockPlatformBackend(page, surface);
    await page.goto(surface.path, { waitUntil: 'domcontentloaded' });
    const support = page.locator('[data-platform-support]');
    const banner = page.locator('[data-platform-announcement]');
    await expect(support).toHaveCount(1);
    await expect(support).toBeVisible();
    await expect(support.getByRole('link', { name: 'Contact support: support@example.com', exact: true })).toHaveAttribute('href', 'mailto:support@example.com');
    await expect(banner).toHaveCount(0);

    const notice = '<img src=x onerror="window.platformXss=true"> Please review <script>window.platformXss=true</script>';
    await page.evaluate(async notice => {
      Object.assign(window.platformTestBackend.settings, {
        portal_announcement: notice, portal_announcement_enabled: true,
        support_email: 'help+portal@example.com',
      });
      await window.platformConfiguration.refresh();
      await window.platformConfiguration.refresh();
    }, notice);
    await expect(banner).toHaveCount(1);
    await expect(banner).toBeVisible();
    await expect(banner.locator('span')).toHaveText(notice);
    await expect(banner.locator('img, script')).toHaveCount(0);
    expect(await page.evaluate(() => window.platformXss)).toBeUndefined();
    await expect(support).toHaveCount(1);
    await expect(support.locator('a')).toHaveAttribute('href', 'mailto:help%2Bportal@example.com');

    await page.evaluate(async () => {
      window.platformTestBackend.settings.portal_announcement = 'Changed notice';
      await window.platformConfiguration.refresh();
    });
    await expect(banner).toHaveCount(1);
    await expect(banner.locator('span')).toHaveText('Changed notice');

    await page.evaluate(async () => {
      Object.assign(window.platformTestBackend.settings, { portal_announcement_enabled: false, support_email: '   ' });
      await window.platformConfiguration.refresh();
    });
    await expect(banner).toHaveCount(0);
    await expect(support).toHaveCount(0);
    expect(await savedCalls(page)).toEqual([]);
    expect(await page.evaluate(() => window.platformTestBackend.queries.filter(table => table.startsWith('platform_settings')))).toEqual([]);
    await expect(page).toHaveURL(new RegExp(surface.path.replaceAll('.', '\\.') + '$'));
  });
}

for (const clipboardMode of ['denied', 'missing']) {
  test(`support gives a manual-copy fallback when clipboard is ${clipboardMode}`, async ({ page }) => {
    await mockPlatformBackend(page, { signedOut: true });
    await page.addInitScript(mode => {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: mode === 'missing' ? undefined : {
        writeText: async () => { throw new Error('Permission denied'); },
      } });
    }, clipboardMode);
    await page.goto('/staff/login.html');
    await page.locator('[data-platform-support] a').click();
    const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
    await dialog.getByRole('button', { name: 'Copy email', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText('copy it manually');
    const address = dialog.getByLabel('Support email', { exact: true });
    await expect(address).toBeFocused();
    expect(await address.evaluate(input => input.value.slice(input.selectionStart, input.selectionEnd))).toBe('support@example.com');
    await expect(dialog.getByRole('button', { name: 'Copy email' })).toBeEnabled();
  });
}

test('pending clipboard access keeps keyboard focus and prevents duplicate copies', async ({ page }) => {
  await mockPlatformBackend(page, { signedOut: true });
  await page.addInitScript(() => {
    window.clipboardAttempts = 0;
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
      writeText: () => {
        window.clipboardAttempts++;
        return new Promise(resolve => { window.finishCopy = resolve; });
      },
    } });
  });
  await page.goto('/staff/login.html');
  await page.locator('[data-platform-support] a').click();
  const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
  const copy = dialog.getByRole('button', { name: 'Copy email', exact: true });
  await copy.press('Enter');
  await expect(copy).toBeFocused();
  await expect(copy).toHaveAttribute('aria-busy', 'true');
  await copy.press('Enter');
  expect(await page.evaluate(() => window.clipboardAttempts)).toBe(1);
  await page.keyboard.press('Tab');
  await expect(dialog.getByRole('link', { name: 'Open email app' })).toBeFocused();
  await page.evaluate(() => window.finishCopy());
  await expect(copy).not.toHaveAttribute('aria-busy');
  await expect(dialog.getByRole('status')).toHaveText('Email address copied.');
});

test('dialog forms still submit with Enter while cancel buttons activate natively', async ({ page }) => {
  await mockPlatformBackend(page, { signedOut: true });
  await page.goto('/staff/login.html');
  await page.evaluate(() => {
    void appDialog.form({ title: 'Test form', fields: [{ name: 'remark', label: 'Remark', required: true }] })
      .then(result => { window.dialogFormResult = result; });
  });
  await page.getByLabel('Remark').fill('Checked');
  await page.getByLabel('Remark').press('Enter');
  await expect.poll(() => page.evaluate(() => window.dialogFormResult)).toEqual({ remark: 'Checked' });
  await page.evaluate(() => {
    void appDialog.confirm('Test cancellation').then(result => { window.dialogCancelResult = result; });
  });
  await page.getByRole('button', { name: 'Cancel', exact: true }).press('Enter');
  await expect.poll(() => page.evaluate(() => window.dialogCancelResult)).toBeNull();
});

for (const path of ['/staff/login.html', '/system-access-7d92a4/login.html']) {
  for (const viewport of [{ width: 1366, height: 650 }, { width: 740, height: 900 }, { width: 390, height: 844 }, { width: 320, height: 640 }]) {
    for (const theme of ['light', 'dark']) {
      test(`${path} ${viewport.width}px ${theme}: notice, theme and support do not overlap`, async ({ page }, testInfo) => {
        await page.setViewportSize(viewport);
        await mockPlatformBackend(page, { signedOut: true, settings: {
          portal_announcement_enabled: true,
          portal_announcement: 'System maintenance is scheduled. '.repeat(7),
        } });
        await page.goto(path);
        await page.evaluate(theme => window.sentinelTheme.set(theme), theme);
        const toggle = page.locator('[data-theme-toggle]');
        const notice = page.locator('[data-platform-announcement]');
        await expect(toggle).toBeVisible();
        await expect(notice).toBeVisible();
        await expect.poll(async () => {
          const a = await toggle.boundingBox(), b = await notice.boundingBox();
          return a.y + a.height <= b.y;
        }).toBe(true);
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
        await page.screenshot({ path: testInfo.outputPath('login.png'), fullPage: true, animations: 'disabled' });
        await page.locator('[data-platform-support] a').click();
        const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
        await expect(dialog).toBeVisible();
        const bounds = await dialog.boundingBox();
        expect(bounds.x).toBeGreaterThanOrEqual(0);
        expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
        expect(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
        await page.screenshot({ path: testInfo.outputPath('support.png'), animations: 'disabled' });
      });
    }
  }
}

test('merged controls uses accessible tabs, desktop columns and contained mobile layout',async({page},info)=>{
 await page.emulateMedia({reducedMotion:'reduce'});
 await openControls(page);
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:950});
  await page.getByRole('tab',{name:'Configuration',exact:true}).click();
  await expect(page.locator('#panel-settings')).toBeVisible();
  await expect(page.locator('#panel-accounts')).toBeHidden();
  await expect(page.getByRole('heading',{name:'Live system status',exact:true})).toHaveCount(0);
  await expect(page.locator('[data-platform-support]')).toHaveCount(0);
  await page.screenshot({path:info.outputPath('controls-'+width+'.png'),fullPage:true});
  await page.getByRole('tab',{name:'Account access',exact:true}).click();
  await expect(page.locator('#panel-settings')).toBeHidden();
  await expect(page.locator('#createAccountButton')).toBeVisible();
  if(width===1440){
    const cards=await page.locator('#panel-accounts > .it-card').all();
    const left=await cards[0].boundingBox(),right=await cards[1].boundingBox();
    expect(Math.abs(left.y-right.y)).toBeLessThan(2);
  }
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:info.outputPath('accounts-'+width+'.png'),fullPage:true});
  await page.getByRole('tab',{name:'Account access',exact:true}).focus();await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('tab',{name:'Activity & history',exact:true})).toBeFocused();
  await expect(page.locator('#panel-activity')).toBeVisible();
 }
 await page.goto('/it-admin/users.html');
 await expect(page).toHaveURL(/clients.html#accounts$/);
 await expect(page.locator('#createAccountButton')).toBeVisible();
 await expect(page.locator('.ax-nav a[href="users.html"]')).toHaveCount(0);
});
