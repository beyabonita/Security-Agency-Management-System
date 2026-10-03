const {test,expect}=require('@playwright/test');
const path=require('node:path');
const fs=require('node:fs');

async function openIdentity(page){
  await page.clock.install();
  await page.setContent('<span class="ax-user-chip" id="axUserName" hidden aria-live="polite"></span>');
  await page.evaluate(()=>{
    window.appDialog={};window.pendingProfiles=[];window.profileCalls=[];
    window.firebase={auth:()=>({onAuthStateChanged(callback){window.identityAuth=callback;return ()=>{window.identityUnsubscribed=true;};}})};
    window.appSupabase={from(table){return {select(columns){return {eq(field,id){return {single(){
      profileCalls.push({table,columns,field,id});
      return new Promise(resolve=>pendingProfiles.push({id,resolve}));
    }};}};}};}};
  });
  await page.addScriptTag({path:path.resolve(__dirname,'../admin/js/admin-shell.js')});
  await page.evaluate(()=>initAdminIdentity());
}
async function auth(page,id){await page.evaluate(id=>identityAuth(id?{uid:id}:null),id);await page.clock.runFor(1);}
async function respond(page,data,error=null){await page.evaluate(({data,error})=>pendingProfiles.shift().resolve({data,error}),{data,error});}
const profile=(name='Angel Anne',last='Samanion')=>({first_name:name,middle_initial:'',last_name:last,role:'admin',active:true});

test('every Operations Head header has only an initially hidden name chip and the shared loader',()=>{
  for(const file of ['dashboard','users','locations','schedule','swaps','incidents','live-tracking']){
    const html=fs.readFileSync(path.resolve(__dirname,'../admin/'+file+'.html'),'utf8');
    expect(html).not.toContain('<span class="ax-role-pill">Operations Head</span>');
    expect(html).toContain('id="axUserName" hidden aria-live="polite"></span>');
    expect(html).toContain('js/admin-shell.js');
  }
});

test('shared loader displays the account name including on pages without their own loader',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await expect(page.locator('#axUserName')).toBeHidden();
  await respond(page,{...profile(),middle_initial:' D. '});
  await expect(page.locator('#axUserName')).toBeVisible();await expect(page.locator('#axUserName')).toHaveText('Angel Anne D. Samanion');
  expect(await page.evaluate(()=>profileCalls[0].id)).toBe('head-a');
  await page.evaluate(()=>initAdminIdentity());expect(await page.evaluate(()=>profileCalls.length)).toBe(1);
});

test('brief profile failure retries and token refresh keeps the same account name',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await respond(page,null,{message:'offline'});
  await expect(page.locator('#axUserName')).toBeHidden();await page.clock.runFor(1500);await respond(page,profile());
  await expect(page.locator('#axUserName')).toHaveText('Angel Anne Samanion');
  await auth(page,'head-a');await respond(page,null,{message:'offline'});
  await expect(page.locator('#axUserName')).toHaveText('Angel Anne Samanion');
  await page.clock.runFor(1500);await respond(page,profile());
});

test('late responses cannot restore an old account name after switching or signing out',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await auth(page,'head-b');
  await respond(page,profile('Old','Account'));await expect(page.locator('#axUserName')).toBeHidden();
  await respond(page,profile('New','Account'));await expect(page.locator('#axUserName')).toHaveText('New Account');
  await auth(page,'head-b');await auth(page,null);await respond(page,profile('New','Account'));
  await expect(page.locator('#axUserName')).toBeHidden();await expect(page.locator('#axUserName')).toBeEmpty();
});

test('stalled profile request times out and retries without displaying a role placeholder',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await page.clock.runFor(11500);
  expect(await page.evaluate(()=>profileCalls.length)).toBe(2);
  await page.evaluate(data=>pendingProfiles[1].resolve({data}),profile());
  await expect(page.locator('#axUserName')).toHaveText('Angel Anne Samanion');
  await respond(page,profile('Old','Response'));await expect(page.locator('#axUserName')).toHaveText('Angel Anne Samanion');
});

test('missing names and failed loads never display Operations Head as the person name',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await respond(page,profile('',''));
  await expect(page.locator('#axUserName')).toHaveText('Name unavailable');
  await auth(page,'head-b');
  for(const delay of [1500,3000]){await respond(page,null,{message:'offline'});await page.clock.runFor(delay);}
  await respond(page,null,{message:'offline'});await expect(page.locator('#axUserName')).toHaveText('Name unavailable');
  await page.evaluate(()=>window.dispatchEvent(new Event('online')));await respond(page,profile('Recovered','Account'));
  await expect(page.locator('#axUserName')).toHaveText('Recovered Account');
});

test('inactive accounts clear names and profile text is rendered safely',async({page})=>{
  await openIdentity(page);await auth(page,'head-a');await respond(page,profile('<img src=x onerror=alert(1)>',''));
  await expect(page.locator('#axUserName img')).toHaveCount(0);
  await expect(page.locator('#axUserName')).toContainText('<img');
  await auth(page,'head-a');await respond(page,{...profile(),active:false});await expect(page.locator('#axUserName')).toBeHidden();
  await page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));expect(await page.evaluate(()=>identityUnsubscribed)).toBe(true);
});
