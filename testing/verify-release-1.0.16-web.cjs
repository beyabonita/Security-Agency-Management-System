const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const manifest=JSON.parse(fs.readFileSync('testing/release-1.0.16-web-manifest.json','utf8'));
 const rows=manifest.filter(x=>!['vercel.json','index.html'].includes(x.path)&&!x.path.startsWith('downloads/'));
 let checked=0;
 for(let offset=0;offset<rows.length;offset+=6)await Promise.all(rows.slice(offset,offset+6).map(async row=>{
  const base=row.path.startsWith('it-admin/')||row.path.startsWith('system-access-7d92a4/')?'https://security-agency-management-system-admin.vercel.app/':'https://security-agency-management-system-nu.vercel.app/';
  const response=await fetch(base+row.path,{signal:AbortSignal.timeout(30000)});
  assert.equal(response.status,200,row.path);assert.equal(hash(Buffer.from(await response.arrayBuffer())),row.sha256,row.path);checked++;
 }));
 const log=fs.readFileSync('testing/release-1.0.16-migrations.txt','utf8');
 for(const version of ['20260913000002','20260913000003','20260913000004'])assert(log.includes('"local":"'+version+'","remote":"'+version+'"'));
 const rpc=await fetch('https://uqtupmpofjqrnefgrexm.supabase.co/rest/v1/rpc/record_guard_timeout',{method:'POST',headers:{apikey:'sb_publishable_WhymBQujSZgXctoTe0hwCA_Q4DRCPcw','Content-Type':'application/json'},body:JSON.stringify({p_session_id:'00000000-0000-0000-0000-000000000000',p_latitude:14.6,p_longitude:120.98,p_claim_overtime:true}),signal:AbortSignal.timeout(30000)});
 assert([401,403].includes(rpc.status));assert.equal((await rpc.json()).code,'42501');
 const result={verifiedWebFiles:checked,migrations:'through 20260913000004',anonymousTimeoutAccess:'denied'};
 fs.writeFileSync('testing/release-1.0.16-web-verification.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
})().catch(e=>{console.error(e);process.exit(1)});
