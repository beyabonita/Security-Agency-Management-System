const fs=require('node:fs'),crypto=require('node:crypto');
const version='1.0.13';
const portals=['https://security-agency-management-system-nu.vercel.app','https://security-agency-management-system-admin.vercel.app'];
(async()=>{
 const results=[];
 for(const base of portals){
   const page=await fetch(base+(base.includes('-admin.')?'/it-admin/users.html':'/admin/users.html'));
   const html=await page.text();
   if(!page.ok||!html.includes('password-policy.js')||!html.includes('PasswordPolicy.error'))throw Error('Password form is not deployed: '+base);
   const script=await fetch(base+'/js/password-policy.js');
   if(!script.ok||!(await script.text()).includes('at least 8 characters'))throw Error('Password policy script missing: '+base);
   results.push({portal:base,passwordPolicy:'PASS'});
 }
 const motion=await fetch(portals[0]+'/js/live-marker-motion.js');
 if(!motion.ok)throw Error('Live marker module missing');
 const schedule=await fetch(portals[0]+'/admin/schedule.html');
 const scheduleHtml=await schedule.text();
 if(!schedule.ok||!scheduleHtml.includes('Operational Head')||!scheduleHtml.includes('rosterSetup')||!scheduleHtml.includes('3 Shifts'))throw Error('Operational Head shift roster is missing');
 for(const file of ['/admin/js/shift-roster.js','/admin/js/duty-requests.js','/admin/js/admin-shell.js','/inspector/js/inspector-shell.js','/js/dtr-report.js']){
   const response=await fetch(portals[0]+file);const body=await response.text();
   if(!response.ok)throw Error('Missing deployed file: '+file);
   const local=fs.readFileSync('web'+file,'utf8');
   if(body!==local)throw Error('Deployed source differs from verified source: '+file);
 }
 results.push({roster:'PASS',operationalHeadLabel:'PASS',liveMapIcon:'PASS',dutyRelief:'PASS'});
 const apkUrl=`https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=${version}`;
 const apk=await fetch(apkUrl,{signal:AbortSignal.timeout(180000)});
 if(!apk.ok||!apk.headers.get('content-type')?.includes('application/vnd.android.package-archive')||!apk.headers.get('content-disposition')?.includes(`v${version}.apk`))throw Error('Download metadata does not match release');
 const digest=crypto.createHash('sha256');let bytes=0;
 for await(const chunk of apk.body){bytes+=chunk.length;digest.update(chunk);}
 const remoteHash=digest.digest('hex');
 const local=JSON.parse(fs.readFileSync('testing/release-1.0.13-apk-verification.json','utf8').replace(/^\uFEFF/,''));
 if(remoteHash!==local.sha256||bytes!==local.bytes)throw Error('Downloaded APK differs from verified APK');
 results.push({download:'PASS',version,bytes,sha256:remoteHash});
 fs.writeFileSync('testing/release-1.0.13-live-verification.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
})().catch(e=>{console.error(e.message);process.exit(1);});
