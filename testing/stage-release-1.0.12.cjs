const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const root=process.cwd(),web=path.join(root,'web');
const version=fs.readFileSync('pubspec.yaml','utf8').match(/^version:\s*([\d.]+)\+(\d+)/m);
if(version?.[1]!=='1.0.12'||version?.[2]!=='13')throw Error('Release version is not 1.0.12+13');
const apk=path.join(web,'downloads/security-agency-management-system-guard.apk');
const verified=JSON.parse(fs.readFileSync('testing/release-1.0.12-apk-verification.json','utf8').replace(/^\uFEFF/,''));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
if(!verified.releaseMode||!verified.sameSigningCertificate||hash(apk)!==verified.sha256)throw Error('Release APK verification is missing or differs');
const stage=path.join(os.tmpdir(),'sams-release-1.0.12-'+Date.now());
const folders=['admin','assets','css','icons','inspector','it-admin','js','staff','system-access-7d92a4','downloads'];
const manifest=[];
function copy(relative){
 const source=path.join(web,relative),target=path.resolve(stage,relative);
 if(!target.startsWith(stage+path.sep))throw Error('Invalid staging path');
 if(fs.statSync(source).isDirectory()){
   fs.mkdirSync(target,{recursive:true});
   for(const entry of fs.readdirSync(source)){
     if(entry.startsWith('.')||entry==='node_modules'||entry==='tests')continue;
     copy(path.join(relative,entry));
   }
 }else{fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(source,target);manifest.push({path:relative.replaceAll('\\','/'),sha256:hash(source)});}
}
folders.forEach(copy);
['favicon.png','index.html','manifest.json','vercel.json'].forEach(copy);
fs.writeFileSync(path.join(stage,'.vercelignore'),'.vercel/\n.env*\ntests/\n');
fs.mkdirSync(path.join(stage,'.vercel'),{recursive:true});fs.copyFileSync('.vercel/project.json',path.join(stage,'.vercel/project.json'));
fs.writeFileSync('testing/release-1.0.12-stage-path.txt',stage);
fs.writeFileSync('testing/release-1.0.12-web-manifest.json',JSON.stringify(manifest,null,2));
console.log(`Staged ${manifest.length} web files including verified APK 1.0.12+13.`);
