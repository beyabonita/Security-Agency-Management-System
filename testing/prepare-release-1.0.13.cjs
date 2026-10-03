const fs=require('node:fs');
for(const f of ['pubspec.yaml','web/vercel.json','web/staff/login.html','docs/GUARD_APP_DOWNLOAD.md']){
 let s=fs.readFileSync(f,'utf8').replaceAll('1.0.12','1.0.13').replaceAll('Build 13','Build 14').replace('1.0.13+13','1.0.13+14');fs.writeFileSync(f,s);
}
for(const [source,target] of [['testing/verify-release-apk.ps1','testing/verify-release-1.0.13-apk.ps1'],['testing/stage-release-1.0.12.cjs','testing/stage-release-1.0.13.cjs'],['testing/verify-release-1.0.12.cjs','testing/verify-release-1.0.13.cjs']]){
 let s=fs.readFileSync(source,'utf8').replaceAll('1.0.12','1.0.13').replaceAll("versionCode='13'","versionCode='14'").replaceAll("build=13","build=14").replaceAll("[2]!=='13'","[2]!=='14'").replaceAll('1.0.13+13','1.0.13+14');
 fs.writeFileSync(target,s);
}
