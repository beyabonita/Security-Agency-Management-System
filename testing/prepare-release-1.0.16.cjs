const fs=require('node:fs');
for(const file of ['pubspec.yaml','web/vercel.json','web/staff/login.html','docs/GUARD_APP_DOWNLOAD.md']) {
 const content=fs.readFileSync(file,'utf8').replaceAll('1.0.15','1.0.16').replaceAll('Build 16','Build 17').replace('1.0.16+16','1.0.16+17');
 fs.writeFileSync(file,content);
}
for(const file of ['verify-release-1.0.15-apk.ps1','stage-release-1.0.15.cjs','verify-release-1.0.15.cjs']) {
 const content=fs.readFileSync('testing/'+file,'utf8').replaceAll('1.0.15','1.0.16').replaceAll("versionCode='16'","versionCode='17'").replaceAll('build=16','build=17').replaceAll("[2]!=='16'","[2]!=='17'").replaceAll('1.0.16+16','1.0.16+17');
 fs.writeFileSync('testing/'+file.replaceAll('1.0.15','1.0.16'),content);
}
