// Read-only production smoke test. Supply QA credentials in environment variables.
// No data is saved, no emergency is acknowledged, and no notification is marked read.
const { chromium } = require('@playwright/test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, process.env.QA_EVIDENCE_DIR || '../../build/qa/google-icons/live');
const portal = 'https://security-agency-management-system-nu.vercel.app';
const system = 'https://security-agency-management-system-admin.vercel.app';
const download = 'https://security-agency-management-system-download.vercel.app';
const roles = [
  { name: 'HR', base: portal, login: '/staff/login.html', home: '/admin/dashboard.html',
    pages: ['/admin/dashboard.html', '/admin/users.html', '/admin/locations.html', '/admin/schedule.html', '/admin/incidents.html', '/admin/swaps.html'] },
  { name: 'INSPECTOR', base: portal, login: '/staff/login.html', home: '/inspector/dashboard.html',
    pages: ['/inspector/dashboard.html', '/inspector/users.html', '/inspector/locations.html', '/inspector/incidents.html', '/inspector/swaps.html'] },
  { name: 'IT', base: system, login: '/system-access-7d92a4/login.html', home: '/it-admin/dashboard.html',
    pages: ['/it-admin/dashboard.html', '/it-admin/clients.html', '/it-admin/users.html'] },
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
        const response = await page.goto(role.base + role.login, { waitUntil: 'load' });
        assert.equal(response.status(), 200);
        assert.match(response.headers()['content-security-policy'], /font-src 'self'/);
        await page.evaluate(() => document.fonts.load('500 24px "Material Symbols Rounded"'));
        await page.screenshot({ path: path.join(output, role.name.toLowerCase() + '-login.png'), fullPage: true });
        await page.locator('#username').fill(username);
        await page.locator('#password').fill(password);
        await page.locator(role.name === 'IT' ? '#login' : '#loginBtn').click();
        await page.waitForURL('**' + role.home, { timeout: 30000 });
        for (const route of role.pages) {
          await page.goto(role.base + route, { waitUntil: 'load' });
          const loader = page.locator('#loadingScreen');
          if (await loader.count()) await loader.waitFor({ state: 'hidden', timeout: 30000 });
          const details = await page.evaluate(async () => {
            const faces = await document.fonts.load('500 24px "Material Symbols Rounded"');
            const icons = [...document.querySelectorAll('.material-symbols-rounded')];
            return {
              loaded: faces.length > 0 && faces.every(face => face.status === 'loaded'),
              iconCount: icons.length,
              incorrectIcons: icons.filter(icon => !getComputedStyle(icon).fontFamily.includes('Material Symbols Rounded') || !icon.closest('[aria-hidden="true"]')).map(icon => icon.textContent.trim()),
              horizontalOverflow: document.documentElement.scrollWidth > innerWidth + 1,
              theme: document.documentElement.dataset.theme,
            };
          });
          assert.equal(details.loaded, true, route + ' font loaded');
          assert.ok(details.iconCount >= 3, route + ' icons present');
          assert.deepEqual(details.incorrectIcons, [], route + ' icon accessibility/styling');
          assert.equal(details.horizontalOverflow, false, route + ' layout');
          const screenshot = role.name.toLowerCase() + '-' + route.split('/').pop().replace('.html', '') + '.png';
          await page.screenshot({ path: path.join(output, screenshot), fullPage: true });
          results.push({ role: role.name, route, checkedAt: new Date().toISOString(), ...details, screenshot, status: 'PASS' });
        }
        assert.deepEqual(errors, [], role.name + ' browser script errors');
      } finally {
        await page.evaluate(async () => { await window.appSupabase?.auth.signOut({ scope: 'local' }); }).catch(() => {});
        await context.close();
      }
    }
    const context = await browser.newContext();
    try {
      const font = await context.request.get(download + '/assets/fonts/material-symbols-rounded.woff2');
      assert.equal(font.status(), 200);
      assert.deepEqual(await font.body(), fs.readFileSync(path.resolve(__dirname, '../assets/fonts/material-symbols-rounded.woff2')));
      const logo = await context.request.get(portal + '/icons/sentinel-link-mark.png');
      assert.equal(logo.status(), 200);
      assert.deepEqual(await logo.body(), fs.readFileSync(path.resolve(__dirname, '../icons/sentinel-link-mark.png')));
      const apk = await context.request.head(download + '/downloads/security-agency-management-system-guard.apk?v=1.0.10');
      assert.equal(apk.status(), 200);
      assert.equal(Number(apk.headers()['content-length']), fs.statSync(path.resolve(__dirname, '../downloads/security-agency-management-system-guard.apk')).size);
      assert.match(apk.headers()['content-disposition'], /attachment;.*Guard-v1\.0\.7\.apk/);
      results.push({ route: 'Android download, agency logo, and bundled icon asset', checkedAt: new Date().toISOString(), status: 'PASS' });
    } finally { await context.close(); }
  } catch (error) {
    results.push({ status: 'FAIL', error: error.message, checkedAt: new Date().toISOString() });
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    await browser.close();
  }
  console.log(JSON.stringify({ checkedAt: new Date().toISOString(), pagesChecked: 14, assetChecks: 3, status: 'PASS' }, null, 2));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
