const {test,expect}=require('@playwright/test');
const path=require('node:path');
test('browser presence follows auth, stops on logout, and rejects a delayed initial session',async({page})=>{
  await page.goto('/favicon.png');
  await page.clock.install();
  await page.evaluate(()=>{
    window.presenceCalls=[];
    window.appSupabase={auth:{
      onAuthStateChange:callback=>window.authEvent=callback,
      getSession:()=>new Promise(resolve=>window.initialSession=resolve),
    },rpc:(name,args)=>{window.presenceCalls.push({name,args});return {abortSignal:async()=>({error:null})};}};
  });
  await page.addScriptTag({path:path.resolve(__dirname,'../js/account-presence.js')});
  await page.evaluate(()=>window.authEvent('SIGNED_IN',{user:{id:'ops'}}));
  await page.clock.runFor(10);
  await expect.poll(()=>page.evaluate(()=>window.presenceCalls.length)).toBe(1);
  await page.clock.runFor(30000);
  expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(2);
  await page.evaluate(()=>window.authEvent('SIGNED_OUT',null));
  await page.clock.runFor(10);
  await page.evaluate(()=>window.initialSession({data:{session:{user:{id:'ops'}}}}));
  await page.clock.runFor(60000);
  expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(2);
  await page.evaluate(()=>window.authEvent('SIGNED_IN',{user:{id:'guard'}}));
  await page.clock.runFor(10);
  expect(await page.evaluate(()=>window.presenceCalls.length)).toBe(3);
});

test('activity table includes all roles, updates logout in place, filters, and clears unverified status on errors',async({page})=>{
  await page.route('https://**',route=>route.fulfill({body:''}));
  await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
    window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};
    window.activityCalls=[];window.activityError=false;
    window.people=['it_admin','admin','inspector','user'].map((role,index)=>({name:['IT Admin','Ops Head','Test Inspector','Test Guard'][index],username:role,role,online:true,account_enabled:true,last_seen_at:'2026-09-14T01:00:00Z'}));
    window.appSupabase={rpc:async(name,args)=>{
      window.activityCalls.push(args);
      if(window.activityError)throw new Error('Offline');
      const rows=window.people.filter(p=>!args.p_role||p.role===args.p_role);
      return {data:{accounts:{total:rows.length,rows},history:{total:1,rows:[{name:'Ops Head',role:'admin',status:window.people[1].online?'Online':'Session ended',signed_in_at:'2026-09-14T01:00:00Z',signed_out_at:window.people[1].online?null:'2026-09-14T02:00:00Z',client_kind:'web'}]},checked_at:'2026-09-14T02:00:00Z'},error:null};
    }};` }));
  await page.route('**/platform-configuration.js',route=>route.fulfill({body:''}));
  await page.route('**/notification-center.js',route=>route.fulfill({body:''}));
  await page.goto('/it-admin/clients.html#activity');
  await page.evaluate(()=>mountAccountActivity(document.getElementById('accountActivity')));
  await expect(page.getByRole('heading',{name:'Platform health',exact:true})).toHaveCount(0);
  await expect(page.locator('[data-accounts] tr')).toHaveCount(4);
  await expect(page.locator('[data-accounts]')).toContainText('Inspector');
  await expect(page.locator('[data-accounts]')).toContainText('Guard');
  await page.evaluate(()=>window.people[1].online=false);
  await page.locator('[data-refresh]').click();
  await expect(page.locator('[data-accounts] tr').filter({hasText:'Ops Head'})).toContainText('Offline');
  await expect(page.locator('[data-history]')).toContainText('Session ended');
  await page.locator('[data-role]').selectOption('inspector');
  await expect(page.locator('[data-accounts] tr')).toHaveCount(1);
  await page.evaluate(()=>window.activityError=true);
  await page.locator('[data-refresh]').click();
  await expect(page.locator('[data-feedback]')).toContainText('Status unavailable');
  await expect(page.locator('[data-accounts] .ax-badge')).toHaveCount(0);
  await page.setViewportSize({width:390,height:844});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
