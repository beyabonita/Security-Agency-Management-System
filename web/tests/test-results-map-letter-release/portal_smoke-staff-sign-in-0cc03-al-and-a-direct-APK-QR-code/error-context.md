# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: portal_smoke.spec.js >> staff sign-in offers a setup modal and a direct APK QR code
- Location: portal_smoke.spec.js:120:1

# Error details

```
Error: expect(locator).toHaveAttribute(expected) failed

Locator: locator('.qr-frame')
Expected pattern: /\/downloads\/security-agency-management-system-guard\.apk\?v=1\.0\.8$/
Received string:  "https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.9"
Timeout: 5000ms

Call log:
  - Expect "toHaveAttribute" with timeout 5000ms
  - waiting for locator('.qr-frame')
    11 × locator resolved to <a class="qr-frame" aria-label="Download the Android Guard app directly" download="Security-Agency-Management-System-Guard-v1.0.9.apk" href="https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.9">…</a>
       - unexpected value "https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.9"

```

```yaml
- link "Download the Android Guard app directly":
  - /url: https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.9
  - img "Scan to download the Android Guard app APK directly"
```

# Test source

```ts
  26  |   await expect.poll(() => page.evaluate(
  27  |     () => typeof window.appSupabase?.auth?.signInWithPassword,
  28  |   )).toBe('function');
  29  | 
  30  |   expect(errors.filter((message) => /could not load the official Supabase client|firebase is not defined/i.test(message))).toEqual([]);
  31  | });
  32  | 
  33  | test('local legacy login paths redirect to the correct access pages', async ({ page }) => {
  34  |   await page.goto('/admin/login.html', { waitUntil: 'domcontentloaded' });
  35  |   await expect(page).toHaveURL(/\/staff\/login\.html$/);
  36  | 
  37  |   await page.goto('/inspector/login.html', { waitUntil: 'domcontentloaded' });
  38  |   await expect(page).toHaveURL(/\/staff\/login\.html$/);
  39  | 
  40  |   await page.goto('/it-admin/login.html', { waitUntil: 'domcontentloaded' });
  41  |   await expect(page).toHaveURL(/\/system-access-7d92a4\/login\.html$/);
  42  | });
  43  | 
  44  | test('staff sign-in remains contained on a phone viewport', async ({ page }) => {
  45  |   await page.setViewportSize({ width: 390, height: 844 });
  46  |   await page.goto('/staff/login.html');
  47  | 
  48  |   const card = await page.locator('.login-panel').boundingBox();
  49  |   expect(card).not.toBeNull();
  50  |   expect(card.x).toBeGreaterThanOrEqual(0);
  51  |   expect(card.x + card.width).toBeLessThanOrEqual(390);
  52  |   await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible();
  53  | });
  54  | 
  55  | test('portal colour mode is available before sign-in and persists between access pages', async ({ page }) => {
  56  |   await page.goto('/staff/login.html');
  57  |   await expect.poll(() => page.evaluate(() => typeof window.sentinelTheme?.set)).toBe('function');
  58  | 
  59  |   await page.evaluate(() => window.sentinelTheme.set('light'));
  60  |   const toggle = page.locator('[data-theme-toggle]');
  61  |   await expect(toggle).toBeVisible();
  62  |   await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  63  |   await toggle.click();
  64  |   await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  65  | 
  66  |   await page.goto('/system-access-7d92a4/login.html');
  67  |   await expect.poll(() => page.evaluate(() => window.sentinelTheme?.get())).toBe('dark');
  68  |   await expect(page.locator('[data-theme-toggle]')).toBeVisible();
  69  | });
  70  | 
  71  | test('login pages use the agency-office background and keep dark fields legible', async ({ page, request }) => {
  72  |   const imageResponse = await request.get('/assets/twentytwenty-agency-office.jpg');
  73  |   expect(imageResponse.ok()).toBeTruthy();
  74  |   expect(imageResponse.headers()['content-type']).toContain('image/jpeg');
  75  | 
  76  |   await page.goto('/staff/login.html');
  77  |   await page.evaluate(() => window.sentinelTheme.set('dark'));
  78  |   // Inputs animate between theme surfaces. Poll the settled state rather than
  79  |   // sampling a first animation frame on a slower browser.
  80  |   await expect.poll(() => page.evaluate(
  81  |     () => getComputedStyle(document.querySelector('#username')).backgroundColor,
  82  |   )).not.toBe('rgb(255, 255, 255)');
  83  |   const staffStyles = await page.evaluate(() => {
  84  |     const background = getComputedStyle(document.querySelector('.access-background'));
  85  |     const panel = getComputedStyle(document.querySelector('.login-panel'));
  86  |     const input = getComputedStyle(document.querySelector('#username'));
  87  |     return {
  88  |       backgroundImage: background.backgroundImage,
  89  |       panelBackground: panel.backgroundColor,
  90  |       inputBackground: input.backgroundColor,
  91  |       inputColor: input.color,
  92  |     };
  93  |   });
  94  |   expect(staffStyles.backgroundImage).toContain('twentytwenty-agency-office.jpg');
  95  |   expect(staffStyles.panelBackground).not.toBe('rgb(255, 253, 253)');
  96  |   expect(staffStyles.inputBackground).not.toBe('rgb(255, 255, 255)');
  97  |   expect(staffStyles.inputColor).toBe('rgb(255, 244, 245)');
  98  | 
  99  |   await page.goto('/system-access-7d92a4/login.html');
  100 |   await expect.poll(() => page.evaluate(
  101 |     () => getComputedStyle(document.querySelector('#username')).backgroundColor,
  102 |   )).not.toBe('rgb(250, 245, 245)');
  103 |   const itStyles = await page.evaluate(() => {
  104 |     const pageSurface = getComputedStyle(document.querySelector('.ax-login-wrap'));
  105 |     const brandSurface = getComputedStyle(document.querySelector('.system-login-brand'));
  106 |     const input = getComputedStyle(document.querySelector('#username'));
  107 |     return {
  108 |       backgroundImage: pageSurface.backgroundImage,
  109 |       brandBackgroundImage: brandSurface.backgroundImage,
  110 |       inputBackground: input.backgroundColor,
  111 |       inputColor: input.color,
  112 |     };
  113 |   });
  114 |   expect(itStyles.backgroundImage).toContain('twentytwenty-agency-office.jpg');
  115 |   expect(itStyles.brandBackgroundImage).toContain('twentytwenty-agency-office.jpg');
  116 |   expect(itStyles.inputBackground).not.toBe('rgb(250, 245, 245)');
  117 |   expect(itStyles.inputColor).toBe('rgb(248, 236, 238)');
  118 | });
  119 | 
  120 | test('staff sign-in offers a setup modal and a direct APK QR code', async ({ page, request }) => {
  121 |   await page.goto('/staff/login.html');
  122 | 
  123 |   const qr = page.getByRole('img', { name: 'Scan to download the Android Guard app APK directly' });
  124 |   await expect(qr).toBeVisible();
  125 |   await expect(qr).toHaveAttribute('src', './guard-app-qr.png?v=apk-1.0.9');
> 126 |   await expect(page.locator('.qr-frame')).toHaveAttribute('href', /\/downloads\/security-agency-management-system-guard\.apk\?v=1\.0\.8$/);
      |                                           ^ Error: expect(locator).toHaveAttribute(expected) failed
  127 | 
  128 |   const setup = page.getByRole('link', { name: 'Open mobile setup' });
  129 |   await expect(setup).toHaveAttribute('href', './app-download.html');
  130 |   await expect(page.getByRole('link', { name: 'Get app' })).toHaveAttribute('href', './app-download.html');
  131 |   await setup.click();
  132 |   await expect(page.getByRole('dialog', { name: 'Install the Guard app', exact: true })).toBeVisible();
  133 |   await expect(page).toHaveURL(/\/staff\/login\.html$/);
  134 | 
  135 |   const qrResponse = await request.get('/staff/guard-app-qr.png');
  136 |   expect(qrResponse.ok()).toBeTruthy();
  137 |   expect(qrResponse.headers()['content-type']).toContain('image/png');
  138 | });
  139 | 
  140 | test('old mobile setup URL opens the Android modal on staff sign-in', async ({ page }) => {
  141 |   await page.goto('/staff/app-download.html');
  142 | 
  143 |   await expect(page).toHaveURL(/\/staff\/login\.html#guard-app-setup$/);
  144 |   await expect(page.getByRole('heading', { name: 'Install the Guard app' })).toBeVisible();
  145 |   const androidDownload = page.getByRole('link', { name: 'Download for Android' });
  146 |   await expect(androidDownload).toHaveAttribute(
  147 |     'href',
  148 |     'https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.9',
  149 |   );
  150 |   await expect(androidDownload).toHaveAttribute('download', 'Security-Agency-Management-System-Guard-v1.0.9.apk');
  151 |   await expect(page.locator('body')).not.toContainText(/iOS|iPhone|iPad|TestFlight/);
  152 | });
  153 | 
  154 | test('mobile setup blocks the APK on unsupported phones', async ({ browser }) => {
  155 |   const context = await browser.newContext({
  156 |     userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
  157 |     viewport: { width: 390, height: 844 },
  158 |   });
  159 |   const page = await context.newPage();
  160 |   await page.goto('/staff/app-download.html');
  161 | 
  162 |   await expect(page.locator('.sl-guard-app')).toHaveAttribute('data-platform', 'unsupported');
  163 |   await expect(page.locator('#deviceMessage')).toContainText('supports Android devices only');
  164 |   await expect(page.locator('#androidDownload')).not.toHaveAttribute('href');
  165 |   await expect(page.locator('#androidDownload')).toHaveAttribute('aria-disabled', 'true');
  166 |   await expect(page.locator('body')).not.toContainText(/iOS|iPhone|iPad|TestFlight/);
  167 |   await context.close();
  168 | });
  169 | 
  170 | test('mobile setup stays contained on an Android phone', async ({ browser }) => {
  171 |   const context = await browser.newContext({
  172 |     userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 Chrome/140.0.0.0 Mobile Safari/537.36',
  173 |     viewport: { width: 390, height: 844 },
  174 |   });
  175 |   const page = await context.newPage();
  176 |   await page.goto('/staff/app-download.html');
  177 | 
  178 |   await expect(page.locator('.sl-guard-app')).toHaveAttribute('data-platform', 'android');
  179 |   await expect(page.locator('#deviceMessage')).toContainText('Android detected');
  180 |   expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  181 |   await context.close();
  182 | });
  183 | 
  184 | test('IT Admin access page renders separately', async ({ page }) => {
  185 |   const errors = collectFatalClientErrors(page);
  186 |   await page.goto('/system-access-7d92a4/login.html');
  187 | 
  188 |   await expect(page).toHaveTitle(/Twenty-Twenty Security Agency — System Access/i);
  189 |   await expect(page.getByRole('heading', { name: 'Security Agency Management System' })).toBeVisible();
  190 |   await expect(page.getByRole('button', { name: /Continue to system control/i })).toBeVisible();
  191 |   await expect.poll(() => page.evaluate(
  192 |     () => typeof window.appSupabase?.auth?.signInWithPassword,
  193 |   )).toBe('function');
  194 | 
  195 |   expect(errors.filter((message) => /could not load the official Supabase client|firebase is not defined/i.test(message))).toEqual([]);
  196 | });
  197 | 
  198 | test('IT Admin access uses a compact card on a phone viewport', async ({ page }) => {
  199 |   await page.setViewportSize({ width: 390, height: 844 });
  200 |   await page.goto('/system-access-7d92a4/login.html');
  201 | 
  202 |   await expect(page.locator('.system-login-brand')).toBeHidden();
  203 |   await expect(page.locator('.system-mobile-mark')).toBeVisible();
  204 |   const card = await page.locator('.system-login-card').boundingBox();
  205 |   expect(card).not.toBeNull();
  206 |   expect(card.x).toBeGreaterThanOrEqual(0);
  207 |   expect(card.x + card.width).toBeLessThanOrEqual(390);
  208 | });
  209 | 
  210 | test('IT Admin access keeps the compact brand mark through tablet widths', async ({ page }) => {
  211 |   await page.setViewportSize({ width: 820, height: 900 });
  212 |   await page.goto('/system-access-7d92a4/login.html');
  213 | 
  214 |   await expect(page.locator('.system-login-brand')).toBeHidden();
  215 |   await expect(page.locator('.system-mobile-mark')).toBeVisible();
  216 |   await expect(page.locator('.system-mobile-mark img')).toHaveAttribute(
  217 |     'src',
  218 |     '../icons/sentinel-link-mark.png',
  219 |   );
  220 | });
  221 | 
  222 | test('shared action buttons expose and restore an animated busy state', async ({ page }) => {
  223 |   await page.goto('/staff/login.html');
  224 |   await expect.poll(() => page.evaluate(() => typeof window.appDialog?.runBusy)).toBe('function');
  225 | 
  226 |   await page.evaluate(() => {
```