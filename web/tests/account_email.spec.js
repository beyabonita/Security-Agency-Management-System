const {test,expect}=require('@playwright/test');
const path=require('node:path');
for(const portal of ['staff','system-access-7d92a4']) test(portal+' email login normalizes Gmail and retains legacy access',async({page})=>{
 await page.route('**/*', route => new URL(route.request().url()).origin === 'http://127.0.0.1:4173' ? route.continue() : route.fulfill({body:''}));
 await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`window.signinCalls=[];window.firebase={auth:()=>({onAuthStateChanged(){},signInWithEmailAndPassword:async(email,password)=>{signinCalls.push({email,password});throw Error('Test sign-in captured');},signOut:async()=>{}}),firestore:()=>({})};window.appSupabase={};`}));
 for(const file of ['platform-configuration.js','notification-center.js'])await page.route('**/'+file,route=>route.fulfill({body:''}));
 await page.goto('/'+portal+'/login.html');
 await expect(page.locator('label[for=username]')).toHaveText('Email');
 await page.locator('#username').fill(' Guard.Name@gmail.com ');await page.locator('#password').fill('AppPass1!');
 await page.evaluate(()=>login());
 expect(await page.evaluate(()=>signinCalls[0])).toEqual({email:'guard.name@gmail.com',password:'AppPass1!'});
 await page.locator('#username').fill('old.guard');await page.evaluate(()=>login());
 expect(await page.evaluate(()=>signinCalls[1].email)).toBe('old.guard@asamanion-26858.auth');
});
test('older incident aliases resolve to the current real email without changing saved reports',async({page})=>{
 await page.goto('/favicon.png');
 await page.addScriptTag({path:path.resolve(__dirname,'../js/incident-report-view.js')});
 expect(await page.evaluate(async()=>{
  window.appSupabase={from:()=>({select:()=>({in:async()=>({data:[{id:'g1',email:'guard@gmail.com'}]})})})};
  const rows=[{userId:'g1',guardEmail:'guard@asamanion-26858.auth'},{userId:'g2',guardEmail:'original@gmail.com'}];
  await incidentReportView.refreshEmails(rows);return rows.map(row=>row.guardEmail);
 })).toEqual(['guard@gmail.com','original@gmail.com']);
});
