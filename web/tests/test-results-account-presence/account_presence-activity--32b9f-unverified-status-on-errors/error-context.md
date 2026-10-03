# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: account_presence.spec.js >> activity table includes all roles, updates logout in place, filters, and clears unverified status on errors
- Location: account_presence.spec.js:30:1

# Error details

```
Error: expect(locator).not.toContainText(expected) failed

Locator: locator('[data-accounts]')
Expected substring: not "Online"
Received string: "Online status could not be verified."
Timeout: 5000ms

Call log:
  - Expect "not toContainText" with timeout 5000ms
  - waiting for locator('[data-accounts]')
    14 × locator resolved to <tbody data-accounts="">…</tbody>
       - unexpected value "Online status could not be verified."

```

```yaml
- rowgroup:
  - row "Online status could not be verified.":
    - cell "Online status could not be verified."
```

# Test source

```ts
  1  | const {test,expect}=require('@playwright/test');
  2  | const fs=require('node:fs');
  3  | const path=require('node:path');
  4  | test('browser presence follows auth, stops on logout, and rejects a delayed initial session',async({page})=>{
  5  |   await page.goto('/favicon.png');
  6  |   await page.clock.install();
  7  |   await page.evaluate(()=>{
  8  |     window.presenceCalls=[];
  9  |     window.appSupabase={auth:{
  10 |       onAuthStateChange:callback=>window.authEvent=callback,
  11 |       getSession:()=>new Promise(resolve=>window.initialSession=resolve),
  12 |     },rpc:(name,args)=>{window.presenceCalls.push({name,args});return {abortSignal:async()=>({error:null})};}};
  13 |   });
  14 |   await page.addScriptTag({path:path.resolve(__dirname,'../js/account-presence.js')});
  15 |   await page.evaluate(()=>window.authEvent('SIGNED_IN',{user:{id:'ops'}}));
  16 |   await page.clock.runFor(10);
  17 |   await expect.poll(()=>page.evaluate(()=>window.presenceCalls.length)).toBe(1);
  18 |   await page.clock.runFor(30000);
  19 |   expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(2);
  20 |   await page.evaluate(()=>window.authEvent('SIGNED_OUT',null));
  21 |   await page.clock.runFor(10);
  22 |   await page.evaluate(()=>window.initialSession({data:{session:{user:{id:'ops'}}}}));
  23 |   await page.clock.runFor(60000);
  24 |   expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(2);
  25 |   await page.evaluate(()=>window.authEvent('SIGNED_IN',{user:{id:'guard'}}));
  26 |   await page.clock.runFor(10);
  27 |   expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(3);
  28 | });
  29 | 
  30 | test('activity table includes all roles, updates logout in place, filters, and clears unverified status on errors',async({page})=>{
  31 |   await page.route('https://**',route=>route.fulfill({body:''}));
  32 |   await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
  33 |     window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};
  34 |     window.activityCalls=[];window.activityError=false;
  35 |     window.people=['it_admin','admin','inspector','user'].map((role,index)=>({name:['IT Admin','Ops Head','Test Inspector','Test Guard'][index],username:role,role,online:true,account_enabled:true,last_seen_at:'2026-09-14T01:00:00Z'}));
  36 |     window.appSupabase={rpc:async(name,args)=>{
  37 |       window.activityCalls.push(args);
  38 |       if(window.activityError)throw new Error('Offline');
  39 |       const rows=window.people.filter(p=>!args.p_role||p.role===args.p_role);
  40 |       return {data:{accounts:{total:rows.length,rows},history:{total:1,rows:[{name:'Ops Head',role:'admin',status:window.people[1].online?'Online':'Session ended',signed_in_at:'2026-09-14T01:00:00Z',signed_out_at:window.people[1].online?null:'2026-09-14T02:00:00Z',client_kind:'web'}]},checked_at:'2026-09-14T02:00:00Z'},error:null};
  41 |     }};` }));
  42 |   await page.route('**/platform-configuration.js',route=>route.fulfill({body:''}));
  43 |   await page.route('**/notification-center.js',route=>route.fulfill({body:''}));
  44 |   await page.goto('/it-admin/clients.html');
  45 |   await page.evaluate(()=>mountAccountActivity(document.getElementById('accountActivity')));
  46 |   await expect(page.getByRole('heading',{name:'Platform health',exact:true})).toHaveCount(0);
  47 |   await expect(page.locator('[data-accounts] tr')).toHaveCount(4);
  48 |   await expect(page.locator('[data-accounts]')).toContainText('Inspector');
  49 |   await expect(page.locator('[data-accounts]')).toContainText('Guard');
  50 |   await page.evaluate(()=>window.people[1].online=false);
  51 |   await page.locator('[data-refresh]').click();
  52 |   await expect(page.locator('[data-accounts] tr').filter({hasText:'Ops Head'})).toContainText('Offline');
  53 |   await expect(page.locator('[data-history]')).toContainText('Session ended');
  54 |   await page.locator('[data-role]').selectOption('inspector');
  55 |   await expect(page.locator('[data-accounts] tr')).toHaveCount(1);
  56 |   await page.evaluate(()=>window.activityError=true);
  57 |   await page.locator('[data-refresh]').click();
  58 |   await expect(page.locator('[data-feedback]')).toContainText('Status unavailable');
> 59 |   await expect(page.locator('[data-accounts]')).not.toContainText('Online');
     |                                                     ^ Error: expect(locator).not.toContainText(expected) failed
  60 |   await page.setViewportSize({width:390,height:844});
  61 |   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
  62 | });
  63 | 
```