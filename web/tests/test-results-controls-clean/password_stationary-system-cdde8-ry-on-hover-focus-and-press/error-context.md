# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: password_stationary.spec.js >> system-access-7d92a4 light eye stays stationary on hover, focus and press
- Location: web\tests\password_stationary.spec.js:2:90

# Error details

```
Error: expect(received).toBeLessThanOrEqual(expected)

Expected: <= 485
Received:    486.59375
```

# Page snapshot

```yaml
- main [ref=e2]:
  - generic [ref=e3]:
    - img "Twenty-Twenty Security Agency" [ref=e5]
    - generic [ref=e6]: Twenty-Twenty Security Agency
    - heading "Security Agency Management System" [level=1] [ref=e7]
    - paragraph [ref=e8]: Private platform administration for maintenance, upgrades, privileged access, and system governance.
    - generic [ref=e9]: Restricted IT administrator access
  - generic [ref=e11]:
    - button "Switch to dark mode" [ref=e13] [cursor=pointer]:
      - generic [ref=e14]: dark_mode
      - generic [ref=e15]: Dark mode
    - generic [ref=e16]:
      - paragraph [ref=e17]: Private access
      - heading "Welcome back" [level=2] [ref=e18]
      - paragraph [ref=e19]: Sign in with your IT administrator credentials.
      - generic [ref=e20]: Email
      - textbox "Email" [ref=e21]:
        - /placeholder: name@gmail.com
      - generic [ref=e22]: Password
      - generic [ref=e23]:
        - textbox "Password" [ref=e24]:
          - /placeholder: Enter password
        - button "Show password" [ref=e25]
      - alert [ref=e29]
      - button "Continue to system control" [ref=e30] [cursor=pointer]
```

# Test source

```ts
  1  | const {test,expect}=require('@playwright/test');
  2  | for(const portal of ['staff','system-access-7d92a4'])for(const theme of ['light','dark'])test(`${portal} ${theme} eye stays stationary on hover, focus and press`,async({page})=>{
  3  |  await page.route('https://**',r=>r.fulfill({body:''}));
  4  |  await page.route('**/supabase-firebase-bridge.js',r=>r.fulfill({contentType:'text/javascript',body:'window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};window.appSupabase={};'}));
  5  |  for(const file of ['platform-configuration.js','notification-center.js'])await page.route('**/'+file,r=>r.fulfill({body:''}));
  6  |  await page.addInitScript(t=>localStorage.setItem('sentinel-link-theme',t),theme);
  7  |  await page.emulateMedia({reducedMotion:'reduce'});
  8  |  await page.goto('/'+portal+'/login.html');
  9  |  const eye=page.locator('#passwordToggle');const input=page.locator('#password');
  10 |  const original=await eye.boundingBox();
  11 |  const assertFixed=async()=>{
  12 |   const rect=await eye.boundingBox();expect(Math.abs(rect.x-original.x)).toBeLessThan(.5);expect(Math.abs(rect.y-original.y)).toBeLessThan(.5);
> 13 |   const box=await input.boundingBox();expect(rect.y).toBeGreaterThanOrEqual(box.y-1);expect(rect.y+rect.height).toBeLessThanOrEqual(box.y+box.height+1);
     |                                                                                                                 ^ Error: expect(received).toBeLessThanOrEqual(expected)
  14 |  };
  15 |  await eye.hover();await assertFixed();await eye.focus();await assertFixed();
  16 |  await page.mouse.down();await assertFixed();await page.mouse.up();
  17 |  await expect(input).toHaveAttribute('type','text');await assertFixed();
  18 |  await eye.click();await expect(input).toHaveAttribute('type','password');await assertFixed();
  19 | });
  20 | 
```