const {test,expect}=require('@playwright/test');
for(const portal of ['staff','system-access-7d92a4'])for(const theme of ['light','dark'])test(`${portal} ${theme} eye stays stationary on hover, focus and press`,async({page})=>{
 await page.route('https://**',r=>r.fulfill({body:''}));
 await page.route('**/supabase-firebase-bridge.js',r=>r.fulfill({contentType:'text/javascript',body:'window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};window.appSupabase={};'}));
 for(const file of ['platform-configuration.js','notification-center.js'])await page.route('**/'+file,r=>r.fulfill({body:''}));
 await page.addInitScript(t=>localStorage.setItem('sentinel-link-theme',t),theme);
 await page.emulateMedia({reducedMotion:'reduce'});
 await page.goto('/'+portal+'/login.html');
 const eye=page.locator('#passwordToggle');const input=page.locator('#password');
 const original=await eye.boundingBox();
 const assertFixed=async()=>{
  const rect=await eye.boundingBox();expect(Math.abs(rect.x-original.x)).toBeLessThan(.5);expect(Math.abs(rect.y-original.y)).toBeLessThan(.5);
  const box=await input.boundingBox();expect(rect.y).toBeGreaterThanOrEqual(box.y-1);expect(rect.y+rect.height).toBeLessThanOrEqual(box.y+box.height+1);
 };
 await eye.hover();await assertFixed();await eye.focus();await assertFixed();
 await page.mouse.down();await assertFixed();await page.mouse.up();
 await expect(input).toHaveAttribute('type','text');await assertFixed();
 await eye.click();await expect(input).toHaveAttribute('type','password');await assertFixed();
});
