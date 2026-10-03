const fs=require('node:fs');
const path=require('node:path');
const version=fs.readFileSync(path.resolve(__dirname,'../../pubspec.yaml'),'utf8')
  .match(/^version:\s*([\d.]+)\+\d+\s*$/m)?.[1];
if(!version)throw new Error('The app release version is missing from pubspec.yaml.');
module.exports={
  version,
  apkUrl:`https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=${version}`,
  apkFileName:`Security-Agency-Management-System-Guard-v${version}.apk`,
  qrSource:`./guard-app-qr.png?v=apk-${version}`,
};
