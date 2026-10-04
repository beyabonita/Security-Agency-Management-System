const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const manifest=JSON.parse(fs.readFileSync('testing/site-day-duplicates-web-manifest.json','utf8'));
 const rows=manifest.filter(x=>!['vercel.json','index.html'].includes(x.path)&&!x.path.startsWith('downloads/'));
 let checked=0;
 for(let offset=0;offset<rows.length;offset+=6)await Promise.all(rows.slice(offset,offset+6).map(async row=>{
  const base=row.path.startsWith('it-admin/')||row.path.startsWith('system-access-7d92a4/')?'https://security-agency-management-system-admin.vercel.app/':'https://security-agency-management-system-nu.vercel.app/';
  const response=await fetch(base+row.path,{signal:AbortSignal.timeout(30000)});
  assert.equal(response.status,200,row.path);assert.equal(hash(Buffer.from(await response.arrayBuffer())),row.sha256,row.path);checked++;
 }));
 fs.writeFileSync('testing/site-day-duplicates-web-verification.json',JSON.stringify({verifiedWebFiles:checked}));console.log('Verified '+checked+' live web files.');
})().catch(e=>{console.error(e);process.exit(1)});
