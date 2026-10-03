// Read-only production checks: no login, account creation, schedule or data edits.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname,'..');
const portal = 'https://security-agency-management-system-nu.vercel.app';
const api = 'https://uqtupmpofjqrnefgrexm.supabase.co';
const results = [];
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
(async () => {
  for (const file of ['admin/users.html','admin/schedule.html','js/contract-period.js','js/supabase-firebase-bridge.js']) {
    const response = await fetch(portal+'/'+file+'?verify=contract-periods');
    const actual = hash(Buffer.from(await response.arrayBuffer()));
    const expected = hash(fs.readFileSync(path.join(root,'web',file)));
    results.push({name:'Published '+file,status:response.ok && actual===expected?'PASS':'FAIL',http:response.status,sha256:actual});
  }
  const key = fs.readFileSync(path.join(root,'web/js/supabase-firebase-bridge.js'),'utf8').match(/const KEY = '([^']+)'/)[1];
  const schema = await fetch(api+'/rest/v1/profiles?select=contract_start_date,contract_end_date&limit=1',{headers:{apikey:key}});
  results.push({name:'Contract columns available through API schema (anonymous read)',status:schema.ok?'PASS':'FAIL',http:schema.status});
  for (const name of ['admin-create-user','admin-manage-user']) {
    const response = await fetch(api+'/functions/v1/'+name,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:'{}'});
    results.push({name:name+' denies unauthenticated callers',status:response.status===401?'PASS':'FAIL',http:response.status});
  }
  const it = await fetch('https://security-agency-management-system-admin.vercel.app/system-access-7d92a4/login.html');
  results.push({name:'IT Admin login remains available',status:it.ok?'PASS':'FAIL',http:it.status});
  const apk = await fetch('https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.10',{method:'HEAD'});
  results.push({name:'Android download remains available',status:apk.ok && Number(apk.headers.get('content-length')) > 0?'PASS':'FAIL',http:apk.status,size:apk.headers.get('content-length')});
  const report = {date:new Date().toISOString(),readOnly:true,results};
  const directory=path.join(root,'build/qa/contract-periods');fs.mkdirSync(directory,{recursive:true});
  fs.writeFileSync(path.join(directory,'deployment-check.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  if(results.some(result=>result.status==='FAIL'))process.exitCode=1;
})().catch(error=>{console.error(error.message);process.exitCode=1;});
