const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const files=JSON.parse(fs.readFileSync('testing/live-gps-deployed-files.json','utf8').replace(/^\uFEFF/,''));
const stage=path.join(require('node:os').tmpdir(),'sams-gps-fix-'+Date.now());
const changed=new Set(['js/live-tracking.js','js/live-marker-motion.js','admin/live-tracking.html','inspector/live-tracking.html']);
const hash=b=>crypto.createHash('sha1').update(b).digest('hex');
function flatten(nodes,prefix='') {return nodes.flatMap(n=>n.type==='directory'?flatten(n.children,prefix+n.name+'/'):[{name:(prefix+n.name).replace(/^src\//,''),uid:n.uid}]);}
(async()=>{
 const inventory=flatten(files);
 if(!inventory.some(file=>file.name==='js/live-marker-motion.js'))inventory.push({name:'js/live-marker-motion.js'});
 for(const {name,uid} of inventory){
   const source=path.resolve('web',name),target=path.resolve(stage,name);
   if(!target.startsWith(stage+path.sep))throw Error('Invalid path');
   let bytes=fs.existsSync(source)?fs.readFileSync(source):null;
   if(!changed.has(name)&&(!bytes||hash(bytes)!==uid)){
     if(name==='.vercelignore') bytes=Buffer.from('.vercel/\n.env*\ntests/\n');
     else {
       const result=await fetch('https://security-agency-management-system-nu.vercel.app/'+name);
       if(!result.ok)throw Error('Cannot retrieve deployed '+name+': '+result.status);
       bytes=Buffer.from(await result.arrayBuffer());
       if(hash(bytes)!==uid)throw Error('Deployed baseline differs: '+name);
     }
   }
   fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,bytes);
 }
 fs.mkdirSync(path.join(stage,'.vercel'),{recursive:true});
 fs.copyFileSync('.vercel/project.json',path.join(stage,'.vercel/project.json'));
 fs.writeFileSync('testing/live-gps-stage-path.txt',stage);
 console.log('Staged '+inventory.length+' files; only live-map updates and explanatory labels changed. Existing APK preserved.');
})().catch(e=>{console.error(e);process.exit(1);});
