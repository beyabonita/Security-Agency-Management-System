// Read-only checks of deployed assets; no production accounts or duties are mutated.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {chromium}=require('@playwright/test');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'build/qa/duty-exchange');
fs.mkdirSync(out,{recursive:true});
const staff='https://security-agency-management-system-nu.vercel.app';
const system='https://security-agency-management-system-admin.vercel.app';
const download='https://security-agency-management-system-download.vercel.app';
const checks=[];
async function check(name,fn){try{const result=await fn();checks.push({name,status:'PASS',result});}
catch(error){checks.push({name,status:'FAIL',error:error.message});}}
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
(async()=>{
  for(const file of ['admin/js/duty-requests.js','css/duty-requests.css']){
    await check(`Deployed ${file} matches tested source`,async()=>{
      const response=await fetch(`${staff}/${file}?verify=duty-exchange`);
      if(!response.ok)throw new Error(`HTTP ${response.status}`);
      const bytes=Buffer.from(await response.arrayBuffer());
      const expected=fs.readFileSync(path.join(root,'web',file));
      if(hash(bytes)!==hash(expected))throw new Error('Deployed asset differs from local tested source');
      return {url:response.url,sha256:hash(bytes)};
    });
  }
  await check('Android APK is version 1.0.10',async()=>{
    const response=await fetch(`${download}/downloads/security-agency-management-system-guard.apk?v=1.0.10`,{method:'HEAD'});
    const disposition=response.headers.get('content-disposition');
    if(!response.ok || Number(response.headers.get('content-length')) <= 0 || !disposition?.includes('v1.0.10.apk'))
      throw new Error(`Unexpected APK response: ${response.status}, ${response.headers.get('content-length')}, ${disposition}`);
    return {status:response.status,bytes:response.headers.get('content-length'),disposition};
  });
  const browser=await chromium.launch({headless:true});
  try{
    for(const [name,url] of [['staff',`${staff}/staff/login.html`],['it-admin',`${system}/system-access-7d92a4/login.html`]]){
      await check(`${name} login remains available`,async()=>{
        const page=await browser.newPage({viewport:{width:1280,height:900}});
        const errors=[];page.on('pageerror',error=>errors.push(error.message));
        await page.goto(url,{waitUntil:'networkidle'});
        await page.locator('input[type=password]').waitFor({state:'visible'});
        await page.screenshot({path:path.join(out,`live-${name}-login.png`),fullPage:true});
        if(errors.length)throw new Error(errors.join('; '));
        const result={url:page.url(),screenshot:`live-${name}-login.png`};
        await page.close();return result;
      });
    }
    await check('Logged-out visitor cannot enter Operations Head duty requests',async()=>{
      const page=await browser.newPage();
      await page.goto(`${staff}/admin/swaps.html`);
      await page.waitForURL('**/staff/login.html');
      await page.screenshot({path:path.join(out,'live-duty-requests-auth-redirect.png')});
      await page.close();return 'Redirected to staff login';
    });
  }finally{await browser.close();}
  const report={timestamp:new Date().toISOString(),type:'Read-only deployed smoke checks',checks};
  fs.writeFileSync(path.join(out,'live-smoke.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  if(checks.some(c=>c.status==='FAIL'))process.exitCode=1;
})().catch(error=>{console.error(error);process.exitCode=1;});
