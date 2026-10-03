const {chromium}=require('../web/tests/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch();const page=await browser.newPage({viewport:{width:1280,height:1100}});
 await page.addInitScript(()=>window.SENTINEL_LIVE_TRACKING_ENABLED=true);
 await page.route('**/supabase-firebase-bridge.js',r=>r.fulfill({contentType:'text/javascript',body:'window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};'}));
 await page.route('**/notification-center.js',r=>r.fulfill({contentType:'text/javascript',body:''}));
 await page.goto('http://127.0.0.1:4173/admin/schedule.html');
 await page.evaluate(()=>{
  document.getElementById('loadingScreen').remove();
  guards=[{id:'one',name:'Juan Dela Cruz',active:true,role:'user'},{id:'two',name:'Maria Santos',active:true,role:'user'},{id:'three',name:'Pedro Reyes',active:true,role:'user'}];
  locations=[{id:'site',label:'Main gate'}];document.getElementById('rosterSetup').value='3';renderShiftRoster();
  document.getElementById('rosterSite').value='site';
 });
 for(const [i,g] of ['one','two','three'].entries())await page.locator('#rosterGuard'+i).selectOption(g);
 await page.screenshot({path:'testing/shift-roster-desktop.png'});
 await page.setViewportSize({width:390,height:1000});
 await page.screenshot({path:'testing/shift-roster-phone.png',fullPage:true});
 if(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth))throw Error('Schedule page overflows phone viewport');
 await browser.close();console.log('Roster previews captured; no horizontal phone overflow.');
})().catch(e=>{console.error(e);process.exit(1)});
