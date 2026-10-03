# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: platform_controls.spec.js >> merged controls uses accessible tabs, desktop columns and contained mobile layout
- Location: web\tests\platform_controls.spec.js:474:1

# Error details

```
Error: expect(received).toBeLessThan(expected)

Expected: < 2
Received:   5.7170867919921875
```

# Page snapshot

```yaml
- generic [ref=e1]:
  - link "Skip to main content" [ref=e2] [cursor=pointer]:
    - /url: "#main-content"
  - generic [ref=e3]:
    - complementary [ref=e4]:
      - generic [ref=e5]:
        - generic [ref=e6]: Security Agency Management System
        - paragraph [ref=e7]: IT Admin Panel
        - paragraph [ref=e8]: Platform maintenance
      - navigation [ref=e9]:
        - generic [ref=e10]: System
        - link "System overview" [ref=e11] [cursor=pointer]:
          - /url: dashboard.html
          - generic [ref=e12]: dashboard
          - text: System overview
        - link "System controls" [ref=e13]:
          - /url: clients.html
          - generic [ref=e14]: tune
          - text: System controls
      - generic [ref=e15]: System administration
    - generic [ref=e16]:
      - banner [ref=e17]:
        - generic [ref=e19]:
          - generic [ref=e20]: System Administration
          - heading "System controls" [level=1] [ref=e21]
        - generic [ref=e22]:
          - button "Switch to dark mode" [ref=e24] [cursor=pointer]:
            - generic [ref=e25]: dark_mode
            - generic [ref=e26]: Dark mode
          - button "0 unread notifications" [ref=e28] [cursor=pointer]:
            - generic [ref=e29]: notifications
          - button "Sign out" [ref=e30] [cursor=pointer]
      - main [ref=e31]:
        - generic [ref=e32]:
          - tablist "System controls" [ref=e33]:
            - tab "Configuration" [ref=e34] [cursor=pointer]
            - tab "Account access" [active] [selected] [ref=e35] [cursor=pointer]
            - tab "Activity & history" [ref=e36] [cursor=pointer]
          - link "Open staff portal ↗" [ref=e37] [cursor=pointer]:
            - /url: https://security-agency-management-system-nu.vercel.app/staff/login.html
        - tabpanel "Account access" [ref=e38]:
          - generic [ref=e39]:
            - heading "Create privileged account" [level=3] [ref=e40]
            - generic [ref=e41]:
              - generic [ref=e42]:
                - generic [ref=e43]: Role
                - combobox "Role" [ref=e44]:
                  - option "Operations Head" [selected]
                  - option "IT Admin"
              - generic [ref=e45]:
                - generic [ref=e46]: First name
                - textbox "First name" [ref=e47]
              - generic [ref=e48]:
                - generic [ref=e49]: Last name
                - textbox "Last name" [ref=e50]
              - generic [ref=e51]:
                - generic [ref=e52]: Email
                - textbox "Email" [ref=e53]:
                  - /placeholder: name@gmail.com
              - generic [ref=e54]:
                - generic [ref=e55]: Temporary password
                - textbox "Temporary password" [ref=e56]
                - text: Use at least 8 characters with uppercase and lowercase letters, a number, and a symbol.
            - button "Create account" [ref=e58] [cursor=pointer]
          - generic [ref=e60]:
            - heading "Privileged accounts" [level=3] [ref=e61]
            - table [ref=e63]:
              - rowgroup [ref=e64]:
                - row [ref=e65]:
                  - columnheader "Name" [ref=e66]
                  - columnheader "Email" [ref=e67]
                  - columnheader "Access scope" [ref=e68]
                  - columnheader "Role" [ref=e69]
                  - columnheader "Account access" [ref=e70]
                  - columnheader "Actions" [ref=e71]
              - rowgroup [ref=e72]:
                - row [ref=e73]:
                  - cell "—" [ref=e74]
                  - cell "Email not added" [ref=e75]
                  - cell "System administration" [ref=e76]
                  - cell "IT Admin" [ref=e78]
                  - cell "Enabled" [ref=e79]
                  - cell [ref=e81]:
                    - button "Change my email" [ref=e82] [cursor=pointer]
        - 'link "Contact support: support@example.com" [ref=e84] [cursor=pointer]':
          - /url: mailto:support@example.com
          - text: Contact support
```

# Test source

```ts
  393 |   });
  394 | }
  395 | 
  396 | test('pending clipboard access keeps keyboard focus and prevents duplicate copies', async ({ page }) => {
  397 |   await mockPlatformBackend(page, { signedOut: true });
  398 |   await page.addInitScript(() => {
  399 |     window.clipboardAttempts = 0;
  400 |     Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
  401 |       writeText: () => {
  402 |         window.clipboardAttempts++;
  403 |         return new Promise(resolve => { window.finishCopy = resolve; });
  404 |       },
  405 |     } });
  406 |   });
  407 |   await page.goto('/staff/login.html');
  408 |   await page.locator('[data-platform-support] a').click();
  409 |   const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
  410 |   const copy = dialog.getByRole('button', { name: 'Copy email', exact: true });
  411 |   await copy.press('Enter');
  412 |   await expect(copy).toBeFocused();
  413 |   await expect(copy).toHaveAttribute('aria-busy', 'true');
  414 |   await copy.press('Enter');
  415 |   expect(await page.evaluate(() => window.clipboardAttempts)).toBe(1);
  416 |   await page.keyboard.press('Tab');
  417 |   await expect(dialog.getByRole('link', { name: 'Open email app' })).toBeFocused();
  418 |   await page.evaluate(() => window.finishCopy());
  419 |   await expect(copy).not.toHaveAttribute('aria-busy');
  420 |   await expect(dialog.getByRole('status')).toHaveText('Email address copied.');
  421 | });
  422 | 
  423 | test('dialog forms still submit with Enter while cancel buttons activate natively', async ({ page }) => {
  424 |   await mockPlatformBackend(page, { signedOut: true });
  425 |   await page.goto('/staff/login.html');
  426 |   await page.evaluate(() => {
  427 |     void appDialog.form({ title: 'Test form', fields: [{ name: 'remark', label: 'Remark', required: true }] })
  428 |       .then(result => { window.dialogFormResult = result; });
  429 |   });
  430 |   await page.getByLabel('Remark').fill('Checked');
  431 |   await page.getByLabel('Remark').press('Enter');
  432 |   await expect.poll(() => page.evaluate(() => window.dialogFormResult)).toEqual({ remark: 'Checked' });
  433 |   await page.evaluate(() => {
  434 |     void appDialog.confirm('Test cancellation').then(result => { window.dialogCancelResult = result; });
  435 |   });
  436 |   await page.getByRole('button', { name: 'Cancel', exact: true }).press('Enter');
  437 |   await expect.poll(() => page.evaluate(() => window.dialogCancelResult)).toBeNull();
  438 | });
  439 | 
  440 | for (const path of ['/staff/login.html', '/system-access-7d92a4/login.html']) {
  441 |   for (const viewport of [{ width: 1366, height: 650 }, { width: 740, height: 900 }, { width: 390, height: 844 }, { width: 320, height: 640 }]) {
  442 |     for (const theme of ['light', 'dark']) {
  443 |       test(`${path} ${viewport.width}px ${theme}: notice, theme and support do not overlap`, async ({ page }, testInfo) => {
  444 |         await page.setViewportSize(viewport);
  445 |         await mockPlatformBackend(page, { signedOut: true, settings: {
  446 |           portal_announcement_enabled: true,
  447 |           portal_announcement: 'System maintenance is scheduled. '.repeat(7),
  448 |         } });
  449 |         await page.goto(path);
  450 |         await page.evaluate(theme => window.sentinelTheme.set(theme), theme);
  451 |         const toggle = page.locator('[data-theme-toggle]');
  452 |         const notice = page.locator('[data-platform-announcement]');
  453 |         await expect(toggle).toBeVisible();
  454 |         await expect(notice).toBeVisible();
  455 |         await expect.poll(async () => {
  456 |           const a = await toggle.boundingBox(), b = await notice.boundingBox();
  457 |           return a.y + a.height <= b.y;
  458 |         }).toBe(true);
  459 |         expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  460 |         await page.screenshot({ path: testInfo.outputPath('login.png'), fullPage: true, animations: 'disabled' });
  461 |         await page.locator('[data-platform-support] a').click();
  462 |         const dialog = page.getByRole('dialog', { name: 'Contact support', exact: true });
  463 |         await expect(dialog).toBeVisible();
  464 |         const bounds = await dialog.boundingBox();
  465 |         expect(bounds.x).toBeGreaterThanOrEqual(0);
  466 |         expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
  467 |         expect(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
  468 |         await page.screenshot({ path: testInfo.outputPath('support.png'), animations: 'disabled' });
  469 |       });
  470 |     }
  471 |   }
  472 | }
  473 | 
  474 | test('merged controls uses accessible tabs, desktop columns and contained mobile layout',async({page},info)=>{
  475 |  await openControls(page);
  476 |  for(const width of [1440,390]){
  477 |   await page.setViewportSize({width,height:950});
  478 |   await page.getByRole('tab',{name:'Configuration',exact:true}).click();
  479 |   await expect(page.locator('#panel-settings')).toBeVisible();
  480 |   await expect(page.locator('#panel-accounts')).toBeHidden();
  481 |   if(width===1440){
  482 |     const cards=await page.locator('#panel-settings > .it-card').all();
  483 |     const left=await cards[0].boundingBox(),right=await cards[1].boundingBox();
  484 |     expect(Math.abs(left.y-right.y)).toBeLessThan(2);expect(right.x).toBeGreaterThan(left.x+left.width);
  485 |   }
  486 |   await page.screenshot({path:info.outputPath('controls-'+width+'.png'),fullPage:true});
  487 |   await page.getByRole('tab',{name:'Account access',exact:true}).click();
  488 |   await expect(page.locator('#panel-settings')).toBeHidden();
  489 |   await expect(page.locator('#createAccountButton')).toBeVisible();
  490 |   if(width===1440){
  491 |     const cards=await page.locator('#panel-accounts > .it-card').all();
  492 |     const left=await cards[0].boundingBox(),right=await cards[1].boundingBox();
> 493 |     expect(Math.abs(left.y-right.y)).toBeLessThan(2);
      |                                      ^ Error: expect(received).toBeLessThan(expected)
  494 |   }
  495 |   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  496 |   await page.screenshot({path:info.outputPath('accounts-'+width+'.png'),fullPage:true});
  497 |   await page.getByRole('tab',{name:'Account access',exact:true}).focus();await page.keyboard.press('ArrowRight');
  498 |   await expect(page.getByRole('tab',{name:'Activity & history',exact:true})).toBeFocused();
  499 |   await expect(page.locator('#panel-activity')).toBeVisible();
  500 |  }
  501 |  await page.goto('/it-admin/users.html');
  502 |  await expect(page).toHaveURL(/clients.html#accounts$/);
  503 |  await expect(page.locator('#createAccountButton')).toBeVisible();
  504 |  await expect(page.locator('.ax-nav a[href="users.html"]')).toHaveCount(0);
  505 | });
  506 | 
```