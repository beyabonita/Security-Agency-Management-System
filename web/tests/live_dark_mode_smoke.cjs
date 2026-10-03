// Read-only verification against the deployed portals. Credentials are supplied
// through environment variables and are never written to the evidence files.
const { chromium } = require('@playwright/test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../build/qa/dark-mode/live');
const portal = 'https://security-agency-management-system-nu.vercel.app';
const system = 'https://security-agency-management-system-admin.vercel.app';
const roles = [
  { name: 'HR', base: portal, login: '/staff/login.html', home: '/admin/dashboard.html',
    pages: ['/admin/dashboard.html','/admin/users.html','/admin/locations.html','/admin/schedule.html','/admin/incidents.html','/admin/swaps.html'] },
  { name: 'INSPECTOR', base: portal, login: '/staff/login.html', home: '/inspector/dashboard.html',
    pages: ['/inspector/dashboard.html','/inspector/users.html','/inspector/locations.html','/inspector/incidents.html','/inspector/swaps.html'] },
  { name: 'IT', base: system, login: '/system-access-7d92a4/login.html', home: '/it-admin/dashboard.html',
    pages: ['/it-admin/dashboard.html','/it-admin/clients.html','/it-admin/users.html'] },
];
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const results = [];
  try {
    for (const role of roles) {
      const username = process.env['QA_' + role.name + '_USERNAME'];
      const password = process.env['QA_' + role.name + '_PASSWORD'];
      assert.ok(username && password, 'Missing QA credentials for ' + role.name);
      const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, colorScheme: 'dark' });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      try {
        await page.goto(role.base + role.login, { waitUntil: 'domcontentloaded' });
        await page.locator('#username').fill(username);
        await page.locator('#password').fill(password);
        await page.locator(role.name === 'IT' ? '#login' : '#loginBtn').click();
        await page.waitForURL('**' + role.home, { timeout: 30000 });
        for (const route of role.pages) {
          await page.goto(role.base + route, { waitUntil: 'networkidle' });
          const loader = page.locator('#loadingScreen');
          if (await loader.count()) await loader.waitFor({ state: 'hidden', timeout: 30000 });
          assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
          assert.ok(await page.locator('[data-theme-toggle]').first().isVisible(), 'Theme control missing');
          const appearance = await page.evaluate(() => {
            const panel = document.querySelector('.it-card,.ax-panel,.ix-panel,.glass-card,.form-panel');
            return { theme: window.sentinelTheme.get(), panelBackground: panel ? getComputedStyle(panel).backgroundColor : null,
              title: document.querySelector('h1')?.textContent?.trim(),
              horizontalOverflow: document.documentElement.scrollWidth > innerWidth + 1,
              criticalAlertVisible: !!document.querySelector('.sl-critical-dialog') };
          });
          if (appearance.panelBackground) assert.equal(appearance.panelBackground, 'rgb(33, 24, 27)', route);
          assert.equal(appearance.horizontalOverflow, false, route);
          const filename = role.name.toLowerCase() + '-' + route.split('/').pop().replace('.html', '') + '-dark.png';
          await page.screenshot({ path: path.join(output, filename), fullPage: true });
          // Do not acknowledge emergencies, mark notifications read, or save forms.
          results.push({ role: role.name, route, checkedAt: new Date().toISOString(), ...appearance, screenshot: filename, status: 'PASS' });
        }
        assert.deepEqual(errors, [], role.name + ' browser script errors');
      } finally {
        await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
        await context.close();
      }
    }
  } finally {
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    await browser.close();
  }
  console.log(JSON.stringify({ checkedAt: new Date().toISOString(), pagesChecked: results.length, status: 'PASS' }, null, 2));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
