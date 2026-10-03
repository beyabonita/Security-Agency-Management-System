const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
const manifest=JSON.parse(fs.readFileSync('testing/release-1.0.15-web-manifest.json','utf8'));
const rows=manifest.filter(x=>x.path!=='vercel.json'&&x.path!=='index.html'&&!x.path.startsWith('it-admin/')&&!x.path.startsWith('system-access-7d92a4/')&&!x.path.startsWith('downloads/'));
let checked=0;
for(let offset=0;offset<rows.length;offset+=6)await Promise.all(rows.slice(offset,offset+6).map(async row=>{
const response=await fetch('https://security-agency-management-system-nu.vercel.app/'+row.path,{signal:AbortSignal.timeout(30000)});
assert.equal(response.status,200,row.path);assert.equal(hash(Buffer.from(await response.arrayBuffer())),row.sha256,row.path);checked++;
}));
for(const row of manifest.filter(x=>x.path.startsWith('it-admin/')||x.path.startsWith('system-access-7d92a4/'))){
const response=await fetch('https://security-agency-management-system-admin.vercel.app/'+row.path,{signal:AbortSignal.timeout(30000)});
assert.equal(response.status,200,row.path);assert.equal(hash(Buffer.from(await response.arrayBuffer())),row.sha256,row.path);checked++;
}
const migrationLog=fs.readFileSync('testing/roster-migrations-after-deploy.txt','utf8');
assert(migrationLog.includes('"local":"20260913000001","remote":"20260913000001"'));
const rpc=await fetch('https://uqtupmpofjqrnefgrexm.supabase.co/rest/v1/rpc/list_shift_roster_setups',{method:'POST',headers:{apikey:'sb_publishable_WhymBQujSZgXctoTe0hwCA_Q4DRCPcw','Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(30000)});
assert([401,403].includes(rpc.status),'Usage RPC must reject anonymous callers');const body=await rpc.json();assert.equal(body.code,'42501');
const result={deployment:'https://security-agency-management-system-pnswuv6gd-codex-a9d1.vercel.app',verifiedWebFiles:checked,migration:'20260913000001',anonymousUsageAccess:'denied'};
fs.writeFileSync('testing/roster-live-verification.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
})().catch(e=>{console.error(e);process.exit(1)});
