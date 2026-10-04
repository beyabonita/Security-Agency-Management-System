const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
(async()=>{
 const expected=JSON.parse(fs.readFileSync('testing/release-1.0.20-apk-verification.json','utf8').replace(/^\uFEFF/,''));
 const url='https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.20';
 const size=4*1024*1024, buffers=[];
 const first=await fetch(url,{headers:{Range:'bytes=0-'+(size-1)},signal:AbortSignal.timeout(600000)});
 assert.ok([200,206].includes(first.status));
 assert.ok(first.headers.get('content-disposition').includes('v1.0.20.apk'));
 assert.ok(first.headers.get('content-type').includes('application/vnd.android.package-archive'));
 let bytes;
 if(first.status===200){bytes=Buffer.from(await first.arrayBuffer());}
 else{
  assert.equal(first.headers.get('content-range'),'bytes 0-'+(size-1)+'/'+expected.bytes);
  buffers[0]=Buffer.from(await first.arrayBuffer());
  const count=Math.ceil(expected.bytes/size);
  for(let offset=1;offset<count;offset+=4){
   await Promise.all(Array.from({length:Math.min(4,count-offset)},(_,j)=>offset+j).map(async i=>{
    const start=i*size,end=Math.min((i+1)*size,expected.bytes)-1;
    const r=await fetch(url,{headers:{Range:'bytes='+start+'-'+end},signal:AbortSignal.timeout(180000)});
    assert.equal(r.status,206);assert.equal(r.headers.get('content-range'),'bytes '+start+'-'+end+'/'+expected.bytes);
    buffers[i]=Buffer.from(await r.arrayBuffer());assert.equal(buffers[i].length,end-start+1);
   }));
   console.log('Verified download segments '+Math.min(offset+4,count)+'/'+count);
  }
  bytes=Buffer.concat(buffers);
 }
 assert.equal(bytes.length,expected.bytes);
 const sha256=crypto.createHash('sha256').update(bytes).digest('hex');assert.equal(sha256,expected.sha256);
 const result={apk:url,bytes:bytes.length,sha256,verified:true};fs.writeFileSync('testing/release-1.0.20-live-verification.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
})().catch(e=>{console.error(e);process.exit(1)});
