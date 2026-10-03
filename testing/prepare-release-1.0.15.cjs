const fs=require('node:fs');
for(const file of ['pubspec.yaml','web/vercel.json','web/staff/login.html','docs/GUARD_APP_DOWNLOAD.md']) {
  const content=fs.readFileSync(file,'utf8').replaceAll('1.0.14','1.0.15').replaceAll('Build 15','Build 16').replace('1.0.15+15','1.0.15+16');
  fs.writeFileSync(file,content);
}
for(const file of ['verify-release-1.0.14-apk.ps1','stage-release-1.0.14.cjs','verify-release-1.0.14.cjs']) {
  const content=fs.readFileSync('testing/'+file,'utf8').replaceAll('1.0.14','1.0.15')
    .replaceAll("versionCode='15'","versionCode='16'").replaceAll('build=15','build=16')
    .replaceAll("[2]!=='15'","[2]!=='16'").replaceAll('1.0.15+15','1.0.15+16');
  fs.writeFileSync('testing/'+file.replaceAll('1.0.14','1.0.15'),content);
}
