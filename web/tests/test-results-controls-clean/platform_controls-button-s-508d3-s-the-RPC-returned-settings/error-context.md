# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: platform_controls.spec.js >> button submits the real form and renders the RPC-returned settings
- Location: web\tests\platform_controls.spec.js:148:3

# Error details

```
Error: expect(locator).toHaveAttribute(expected) failed

Locator: locator('[data-platform-support] a')
Expected: "mailto:canonical@example.com"
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toHaveAttribute" with timeout 5000ms
  - waiting for locator('[data-platform-support] a')

```

```yaml
- link "Skip to main content":
  - /url: "#main-content"
- complementary:
  - text: Security Agency Management System
  - paragraph: IT Admin Panel
  - paragraph: Platform maintenance
  - navigation:
    - text: System
    - link "System overview":
      - /url: dashboard.html
    - link "System controls":
      - /url: clients.html
  - text: System administration
- banner:
  - text: System Administration
  - heading "System controls" [level=1]
  - button "Switch to dark mode": Dark mode
  - button "0 unread notifications"
  - button "Sign out"
- main:
  - status:
    - strong: System notice
    - text: Saved server notice
  - tablist "System controls":
    - tab "Configuration" [selected]
    - tab "Account access"
    - tab "Activity & history"
  - link "Open staff portal ↗":
    - /url: https://security-agency-management-system-nu.vercel.app/staff/login.html
  - tabpanel "Configuration":
    - heading "Platform configuration" [level=2]
    - group:
      - text: Support email
      - textbox "Support email Shown as Contact support on login pages and web portals.":
        - /placeholder: support@example.com
        - text: canonical@example.com
      - text: Shown as Contact support on login pages and web portals. New-site geofence default (meters)
      - spinbutton "New-site geofence default (meters) For new deployment sites only. Existing sites keep their own radius.": "350"
      - text: For new deployment sites only. Existing sites keep their own radius. Portal announcement
      - textbox "Portal announcement Publishing requires 3–240 characters and notifies active accounts, including Guards.":
        - /placeholder: Optional notice for web portal users
        - text: Saved server notice
      - text: Publishing requires 3–240 characters and notifies active accounts, including Guards.
      - checkbox "Show this announcement in the web portals" [checked]
      - text: Show this announcement in the web portals
      - button "Save configuration"
    - text: Configuration saved.
- status
```

# Test source

```ts
  69  |       };
  70  |       const query = table => {
  71  |         const builder = {
  72  |           select() { return this; }, eq() { return this; }, order() { return this; },
  73  |           in() { return this; }, limit() { return this; }, is() { return this; },
  74  |           maybeSingle: () => resultFor(table, true),
  75  |           then: (resolve, reject) => resultFor(table, false).then(resolve, reject)
  76  |         };
  77  |         return builder;
  78  |       };
  79  |       const emptySnapshot = { size: 0, empty: true, docs: [], forEach() {} };
  80  |       const collection = () => {
  81  |         const builder = {
  82  |           where() { return this; }, orderBy() { return this; }, limit() { return this; },
  83  |           get: async () => emptySnapshot,
  84  |           doc: () => ({ get: async () => ({ exists: true, data: () => profile }) })
  85  |         };
  86  |         return builder;
  87  |       };
  88  |       window.firebase = {
  89  |         auth: () => ({
  90  |           onAuthStateChanged: callback => setTimeout(() => callback(options.signedOut ? null : { uid: profile.id }), 0),
  91  |           signOut: async () => {}
  92  |         }),
  93  |         firestore: () => ({ collection })
  94  |       };
  95  |       window.appSupabase = {
  96  |         auth: {
  97  |           getSession: async () => ({ data: { session: options.signedOut ? null : { user: { id: profile.id } } } }),
  98  |           onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } })
  99  |         },
  100 |         from: query,
  101 |         rpc: async (name, params) => {
  102 |           state.calls.push({ name, params });
  103 |           if (name === 'current_platform_announcement') return {
  104 |             data: state.settings.portal_announcement_enabled ? state.settings.portal_announcement : '', error: null
  105 |           };
  106 |           if (name === 'current_platform_support_email') return { data: state.settings.support_email, error: null };
  107 |           if (name === 'update_platform_settings') {
  108 |             if (state.holdSave) await new Promise(resolve => { state.releaseSave = resolve; });
  109 |             if (state.saveError) return { data: null, error: { message: state.saveError } };
  110 |             state.settings = {
  111 |               support_email: params.p_support_email,
  112 |               default_geofence_radius: params.p_default_geofence_radius,
  113 |               portal_announcement: params.p_portal_announcement,
  114 |               portal_announcement_enabled: params.p_portal_announcement_enabled,
  115 |               updated_at: '2026-09-04T02:00:00Z',
  116 |               ...state.savedSettings
  117 |             };
  118 |             return { data: options.returnArray ? [copy(state.settings)] : copy(state.settings), error: null };
  119 |           }
  120 |           throw new Error('Unexpected mock RPC: ' + name);
  121 |         },
  122 |         channel: () => ({ on() { return this; }, subscribe() { return this; } }),
  123 |         removeChannel: async () => {}
  124 |       };
  125 |     })();`,
  126 |   }));
  127 | }
  128 | 
  129 | async function openControls(page, options = {}) {
  130 |   await mockPlatformBackend(page, options);
  131 |   await page.goto('/it-admin/clients.html', { waitUntil: 'domcontentloaded' });
  132 |   await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  133 |   if (!options.settingsError) await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  134 | }
  135 | 
  136 | async function savedCalls(page) {
  137 |   return page.evaluate(() => window.platformTestBackend.calls.filter(call => call.name === 'update_platform_settings'));
  138 | }
  139 | 
  140 | async function fillSettings(page, { email = 'updated@example.com', radius = '275', announcement = 'Updated portal notice', enabled = true } = {}) {
  141 |   await page.locator('#supportEmail').fill(email);
  142 |   await page.locator('#defaultGeofenceRadius').fill(radius);
  143 |   await page.locator('#portalAnnouncement').fill(announcement);
  144 |   await page.locator('#portalAnnouncementEnabled').setChecked(enabled);
  145 | }
  146 | 
  147 | for (const submitMethod of ['button', 'Enter']) {
  148 |   test(`${submitMethod} submits the real form and renders the RPC-returned settings`, async ({ page }) => {
  149 |     await openControls(page, {
  150 |       returnArray: submitMethod === 'Enter',
  151 |       savedSettings: { support_email: 'canonical@example.com', default_geofence_radius: 350, portal_announcement: 'Saved server notice' },
  152 |     });
  153 |     await fillSettings(page, { announcement: '  Updated portal notice  ' });
  154 |     if (submitMethod === 'button') await page.getByRole('button', { name: 'Save configuration', exact: true }).click();
  155 |     else await page.locator('#supportEmail').press('Enter');
  156 | 
  157 |     await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  158 |     expect(await savedCalls(page)).toEqual([{
  159 |       name: 'update_platform_settings',
  160 |       params: {
  161 |         p_support_email: 'updated@example.com', p_default_geofence_radius: 275,
  162 |         p_portal_announcement: 'Updated portal notice', p_portal_announcement_enabled: true,
  163 |       },
  164 |     }]);
  165 |     await expect(page.locator('#supportEmail')).toHaveValue('canonical@example.com');
  166 |     await expect(page.locator('#defaultGeofenceRadius')).toHaveValue('350');
  167 |     await expect(page.locator('#portalAnnouncement')).toHaveValue('Saved server notice');
  168 |     await expect(page.locator('[data-platform-announcement]')).toContainText('Saved server notice');
> 169 |     await expect(page.locator('[data-platform-support] a')).toHaveAttribute('href', 'mailto:canonical@example.com');
      |                                                             ^ Error: expect(locator).toHaveAttribute(expected) failed
  170 |     await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  171 |     await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  172 |   });
  173 | }
  174 | 
  175 | test('publishing requires three trimmed characters and input changes recover validation', async ({ page }) => {
  176 |   await openControls(page);
  177 |   await fillSettings(page, { announcement: '  ab  ' });
  178 |   await page.locator('#savePlatformSettings').click();
  179 |   expect(await savedCalls(page)).toEqual([]);
  180 |   await expect(page.locator('#portalAnnouncement')).toHaveJSProperty('validationMessage', 'Enter an announcement of at least 3 characters before publishing.');
  181 |   await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  182 | 
  183 |   await page.locator('#portalAnnouncement').fill(' abc ');
  184 |   await page.locator('#savePlatformSettings').click();
  185 |   await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  186 |   expect((await savedCalls(page))[0].params.p_portal_announcement).toBe('abc');
  187 |   await page.locator('#portalAnnouncementEnabled').uncheck();
  188 |   await page.locator('#portalAnnouncement').fill('');
  189 |   await page.locator('#savePlatformSettings').click();
  190 |   await expect.poll(async () => (await savedCalls(page)).length).toBe(2);
  191 |   expect((await savedCalls(page))[1].params).toMatchObject({ p_portal_announcement: '', p_portal_announcement_enabled: false });
  192 |   await expect(page.locator('[data-platform-announcement]')).toHaveCount(0);
  193 | });
  194 | 
  195 | test('radius validation rejects missing, out-of-range and fractional values and accepts both boundaries', async ({ page }) => {
  196 |   await openControls(page);
  197 |   const radius = page.locator('#defaultGeofenceRadius');
  198 |   for (const value of ['', '24', '1001', '25.5']) {
  199 |     await radius.fill(value);
  200 |     await page.locator('#savePlatformSettings').click();
  201 |     expect(await radius.evaluate(element => element.validity.valid)).toBe(false);
  202 |     expect(await savedCalls(page)).toEqual([]);
  203 |     await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  204 |   }
  205 |   for (const value of ['25', '1000']) {
  206 |     await radius.fill(value);
  207 |     await page.locator('#savePlatformSettings').click();
  208 |     await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  209 |     expect((await savedCalls(page)).at(-1).params.p_default_geofence_radius).toBe(Number(value));
  210 |   }
  211 |   expect((await savedCalls(page)).length).toBe(2);
  212 | });
  213 | 
  214 | test('a failed save preserves entered fields and clears busy state so retry succeeds', async ({ page }) => {
  215 |   await openControls(page, { holdSave: true, saveError: 'Configuration service unavailable' });
  216 |   await fillSettings(page);
  217 |   await page.locator('#savePlatformSettings').click();
  218 |   await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'true');
  219 |   await expect(page.locator('#savePlatformSettings')).toHaveText('Saving configuration…');
  220 |   await expect(page.locator('#supportEmail')).toBeDisabled();
  221 |   await page.evaluate(() => window.platformTestBackend.releaseSave());
  222 |   await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration service unavailable');
  223 |   await expect(page.locator('#supportEmail')).toHaveValue('updated@example.com');
  224 |   await expect(page.locator('#defaultGeofenceRadius')).toHaveValue('275');
  225 |   await expect(page.locator('#portalAnnouncement')).toHaveValue('Updated portal notice');
  226 |   await expect(page.locator('#portalAnnouncementEnabled')).toBeChecked();
  227 |   await expect(page.locator('#platformSettingsForm')).toHaveAttribute('aria-busy', 'false');
  228 |   await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  229 |   await expect(page.locator('#savePlatformSettings')).toHaveText('Save configuration');
  230 |   await page.evaluate(() => {
  231 |     window.platformTestBackend.saveError = null;
  232 |     window.platformTestBackend.holdSave = false;
  233 |   });
  234 |   await page.locator('#savePlatformSettings').click();
  235 |   await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  236 |   expect((await savedCalls(page)).length).toBe(2);
  237 | });
  238 | 
  239 | test('an in-flight save blocks duplicate submissions and preserves the submitted snapshot', async ({ page }) => {
  240 |   await openControls(page, { holdSave: true });
  241 |   await fillSettings(page);
  242 |   await page.locator('#savePlatformSettings').click();
  243 |   await expect(page.locator('#savePlatformSettings')).toBeDisabled();
  244 |   await expect(page.locator('#platformSettingsFields')).toHaveJSProperty('disabled', true);
  245 |   // Exercise the handler guard even if a second submit event arrives while
  246 |   // native interaction is disabled. The first submission remains a real click.
  247 |   await page.locator('#platformSettingsForm').dispatchEvent('submit');
  248 |   await page.locator('#platformSettingsForm').dispatchEvent('submit');
  249 |   expect((await savedCalls(page)).length).toBe(1);
  250 |   await page.evaluate(() => window.platformTestBackend.releaseSave());
  251 |   await expect(page.locator('#platformSettingsFeedback')).toHaveText('Configuration saved.');
  252 |   await expect(page.locator('#savePlatformSettings')).toBeEnabled();
  253 |   expect((await savedCalls(page))[0].params.p_support_email).toBe('updated@example.com');
  254 | });
  255 | 
  256 | test('removed audit and administrative sections are not rendered or queried', async ({page}) => {
  257 |  await openControls(page);
  258 |  await expect(page.getByRole('heading',{name:'Recent configuration changes'})).toHaveCount(0);
  259 |  await expect(page.getByRole('heading',{name:'Administrative actions'})).toHaveCount(0);
  260 |  expect(await page.evaluate(()=>platformTestBackend.queries.includes('platform_settings_audit'))).toBe(false);
  261 | });
  262 | 
  263 | test('a configuration load failure disables the form until Retry loading succeeds', async ({ page }) => {
  264 |   await openControls(page, { settingsError: 'Could not load platform configuration' });
  265 |   await expect(page.locator('#platformSettingsFeedback')).toHaveText('Could not load platform configuration');
  266 |   await expect(page.locator('#platformSettingsFields')).toHaveJSProperty('disabled', true);
  267 |   await expect(page.locator('#supportEmail')).toBeDisabled();
  268 |   await expect(page.locator('#savePlatformSettings')).toBeDisabled();
  269 |   await page.locator('#platformSettingsForm').dispatchEvent('submit');
```