const fs=require('node:fs');
for(const f of ['pubspec.yaml','web/vercel.json','web/staff/login.html','docs/GUARD_APP_DOWNLOAD.md']) {
  const s=fs.readFileSync(f,'utf8').replaceAll('1.0.13','1.0.14').replaceAll('Build 14','Build 15').replace('1.0.14+14','1.0.14+15');
  fs.writeFileSync(f,s);
}
for(const [source,target] of [
  ['testing/verify-release-1.0.13-apk.ps1','testing/verify-release-1.0.14-apk.ps1'],
  ['testing/stage-release-1.0.13.cjs','testing/stage-release-1.0.14.cjs']
]) {
  const s=fs.readFileSync(source,'utf8').replaceAll('1.0.13','1.0.14')
    .replaceAll("versionCode='14'","versionCode='15'").replaceAll('build=14','build=15')
    .replaceAll("[2]!=='14'","[2]!=='15'").replaceAll('1.0.14+14','1.0.14+15');
  fs.writeFileSync(target,s);
}
