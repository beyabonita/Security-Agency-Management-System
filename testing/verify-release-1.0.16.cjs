const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root='https://security-agency-management-system-nu.vercel.app';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
(async()=>{
  const results=[];
  for(const file of ['/js/live-tracking.js','/js/live-tracking-model.js','/js/live-marker-motion.js','/staff/login.html','/staff/guard-app-qr.png']) {
    const response=await fetch(root+file,{signal:AbortSignal.timeout(30000)});
    assert.equal(response.status,200,file);
    const content=Buffer.from(await response.arrayBuffer());
    assert.equal(hash(content),hash(fs.readFileSync('web'+file)),file+' differs from tested source');
    results.push({file,verified:true});
  }
  for(const base of ['https://security-agency-management-system-admin.vercel.app','https://security-agency-management-system-download.vercel.app']) {
    const response=await fetch(base+'/js/live-tracking-model.js',{signal:AbortSignal.timeout(30000)});
    assert.equal(response.status,200);
    assert.equal(hash(Buffer.from(await response.arrayBuffer())),hash(fs.readFileSync('web/js/live-tracking-model.js')));
    results.push({alias:base,verified:true});
  }
  const url='https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.16';
  const response=await fetch(url,{signal:AbortSignal.timeout(600000)});
  assert.equal(response.status,200);
  assert.ok(response.headers.get('content-type').includes('application/vnd.android.package-archive'));
  assert.ok(response.headers.get('content-disposition').includes('v1.0.16.apk'));
  const digest=crypto.createHash('sha256');let bytes=0,lastProgress=0;
  for await(const chunk of response.body){bytes+=chunk.length;digest.update(chunk);if(bytes-lastProgress>8388608){console.log('Downloaded '+Math.round(bytes/1048576)+' MB');lastProgress=bytes;}}
  const sha256=digest.digest('hex');
  const expected=JSON.parse(fs.readFileSync('testing/release-1.0.16-apk-verification.json','utf8').replace(/^\uFEFF/,''));
  assert.equal(sha256,expected.sha256);assert.equal(bytes,expected.bytes);
  results.push({apk:url,bytes,sha256,verified:true});
  fs.writeFileSync('testing/release-1.0.16-live-verification.json',JSON.stringify(results,null,2));
  console.log(JSON.stringify(results,null,2));
})().catch(error=>{console.error(error);process.exit(1);});

