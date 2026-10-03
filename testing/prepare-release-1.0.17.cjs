const fs=require('fs');
for(const file of ['pubspec.yaml','web/vercel.json','web/staff/login.html','docs/GUARD_APP_DOWNLOAD.md']){
 const content=fs.readFileSync(file,'utf8').replaceAll('1.0.16','1.0.17').replaceAll('Build 17','Build 18').replace('1.0.17+17','1.0.17+18');fs.writeFileSync(file,content);
}
for(const file of ['verify-release-1.0.16-apk.ps1','stage-release-1.0.16.cjs','verify-release-1.0.16.cjs']){
 const content=fs.readFileSync('testing/'+file,'utf8').replaceAll('1.0.16','1.0.17').replaceAll("versionCode='17'","versionCode='18'").replaceAll('build=17','build=18').replaceAll("[2]!=='17'","[2]!=='18'").replaceAll('1.0.17+17','1.0.17+18');fs.writeFileSync('testing/'+file.replaceAll('1.0.16','1.0.17'),content);
}
