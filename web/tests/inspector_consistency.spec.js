const {test,expect}=require('@playwright/test');
const path=require('node:path');
async function mock(page) {
  await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};window.appSupabase={auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange(){return {data:{subscription:{unsubscribe(){}}}}}};`}));
  for(const file of ['platform-configuration.js','notification-center.js'])await page.route('**/'+file,route=>route.fulfill({body:''}));
}
test('all Inspector pages use the Operations Head sidebar and contained content',async({page},info)=>{
  await mock(page);
  await page.addInitScript(()=>localStorage.setItem('sentinel-link-theme','light'));
  for(const file of ['dashboard','users','locations','incidents','swaps','live-tracking']){
    for(const width of [1440,390]){
      await page.setViewportSize({width,height:900});
      await page.goto('/inspector/'+file+'.html');
      await page.addStyleTag({content:'#loadingScreen{display:none!important}'});
      await expect(page.locator('.ax-sidebar')).toHaveCount(1);
      await expect(page.locator('.ix-shell')).toHaveCount(0);
      await expect(page.locator('.ax-topbar')).toBeVisible();
      if(file!=='swaps')await expect(page.locator('.ax-nav a[href="'+file+'.html"]')).toHaveAttribute('aria-current','page');
      await expect(page.locator('.ax-brand')).toHaveCSS('display','grid');
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
      await expect(page.locator('.ax-nav a[href="../admin/schedule.html"]')).toHaveCount(0);
      if(width===390){
        await page.locator('#ixMenuToggle').click();
        await expect(page.locator('.ax-sidebar')).toHaveClass(/ax-open/);
        await page.keyboard.press('Escape');
        await expect(page.locator('.ax-sidebar')).not.toHaveClass(/ax-open/);
      }
      if(file==='dashboard'){
        await page.evaluate(()=>{setInspectorUserName('Kyla Marie');document.querySelectorAll('.ax-stat-num').forEach((el,i)=>el.textContent=String(i+1));});
        await page.screenshot({path:info.outputPath('inspector-'+width+'.png')});
        await page.evaluate(()=>{localStorage.setItem('sentinel-link-theme','dark');document.documentElement.dataset.theme='dark';});
        await page.screenshot({path:info.outputPath('inspector-'+width+'-dark.png')});
      }
    }
  }
});
test('assigned shift totals count Guard assignments across dates while excluding drafts and cancellations',async({page})=>{
  await page.goto('/favicon.png');
  await page.addScriptTag({path:path.resolve(__dirname,'../js/dashboard-shifts.js')});
  expect(await page.evaluate(()=>{
    const docs=[{userId:'g1',approvalStatus:'approved'}, {userId:'g1',approval_status:'changed'}, {userId:'g1',approvalStatus:'draft'}, {userId:'g1',approvalStatus:'cancelled'}, {userId:'g2',approvalStatus:'approved'}, {userId:'inspector',approvalStatus:'approved'}].map(data=>({data:()=>data}));
    return [countAssignedGuardShifts(docs,new Set(['g1','g2'])),countAssignedGuardShifts(docs,new Set(['g1']))];
  })).toEqual([3,2]);
});
for(const portal of ['staff','system-access-7d92a4'])test(portal+' has one icon-only accessible password toggle',async({page})=>{
  await mock(page);await page.goto('/'+portal+'/login.html');
  const button=page.locator('#passwordToggle'),password=page.locator('#password');
  await password.fill('Test123!');
  await expect(button).toHaveText('');await expect(button.locator('svg')).toHaveCount(1);
  await expect(button).toHaveAttribute('aria-label','Show password');
  await button.click();await expect(password).toHaveAttribute('type','text');
  await expect(button).toHaveAttribute('aria-label','Hide password');await expect(button).toHaveText('');
  await button.focus();await page.keyboard.press('Enter');await expect(password).toHaveAttribute('type','password');
});
