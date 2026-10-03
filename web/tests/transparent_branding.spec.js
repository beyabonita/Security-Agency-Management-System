const { expect, test } = require('@playwright/test');

const surfaces = [
  ['/staff/login.html', '.sentinel-mark', null],
  ['/system-access-7d92a4/login.html', '.system-symbol,.system-mobile-mark', null],
  ['/admin/dashboard.html', '.ax-brand', '::before'],
  ['/inspector/dashboard.html', '.ax-brand', '::before'],
  ['/it-admin/dashboard.html', '.ax-brand', '::before'],
];

for (const theme of ['light', 'dark']) {
  test(`transparent agency logo has no white tile on ${theme} portal surfaces`, async ({ page }, info) => {
    test.setTimeout(60000);
    await page.setViewportSize({ width: theme === 'dark' ? 390 : 1440, height: 1000 });
    await page.addInitScript(value => localStorage.setItem('sentinel-link-theme', value), theme);
    await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
      contentType: 'text/javascript',
      body: `window.firebase = { auth: () => ({ onAuthStateChanged() {}, signOut: async () => {} }), firestore: () => ({ collection: () => ({}) }) };`,
    }));
    await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
    for (const [route, selector, pseudo] of surfaces) {
      await page.goto(route, { waitUntil: 'load' });
      await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
      for (const mark of await page.locator(selector).all()) {
        const style = await mark.evaluate((element, pseudo) => {
          const value = getComputedStyle(element, pseudo);
          return { background: value.backgroundColor, shadow: value.boxShadow, image: value.backgroundImage };
        }, pseudo);
        expect(style.background, route).toBe('rgba(0, 0, 0, 0)');
        expect(style.shadow, route).toBe('none');
        if (pseudo) expect(style.image).toContain('sentinel-link-mark.png');
      }
      // Verify the served image has actual transparent pixels, not a white PNG
      // sitting in a transparent CSS container.
      const pixels = await page.evaluate(async () => {
        const image = new Image();
        image.src = '/icons/sentinel-link-mark.png';
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 64;
        const context = canvas.getContext('2d');
        context.drawImage(image, 0, 0, 64, 64);
        return { cornerAlpha: context.getImageData(0, 0, 1, 1).data[3], centerAlpha: context.getImageData(32, 32, 1, 1).data[3] };
      });
      expect(pixels.cornerAlpha).toBe(0);
      expect(pixels.centerAlpha).toBeGreaterThan(0);
      const menu = page.locator('#axMenuToggle,[data-it-nav-toggle]');
      if (theme === 'dark' && await menu.count()) await menu.first().click();
      await page.screenshot({ path: info.outputPath(route.replaceAll('/', '_') + '-' + theme + '.png'), fullPage: true });
    }
  });
}
