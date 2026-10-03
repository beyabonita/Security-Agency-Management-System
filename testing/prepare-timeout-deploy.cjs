const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const migration=fs.readFileSync('supabase/migrations/20260908000002_attendance_timeout_verification.sql','utf8');
fs.writeFileSync('testing/apply-timeout-verification.sql',`begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
do $$ begin
  if exists(select 1 from supabase_migrations.schema_migrations where version='20260908000002') then
    raise exception 'Timeout verification migration is already applied.';
  end if;
end $$;
${migration}
insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260908000002','attendance_timeout_verification',array[$migration$${migration}$migration$]);
notify pgrst,'reload schema';
commit;
select version,name from supabase_migrations.schema_migrations where version='20260908000002';
`);
const inventory=JSON.parse(fs.readFileSync('testing/timeout-verification-deployed-files.json','utf8').replace(/^\uFEFF/,''));
const stage=path.join(require('node:os').tmpdir(),'sams-timeout-verification-'+Date.now());
const changed=new Set(['admin/users.html','js/dtr-report.js']);
const hash=b=>crypto.createHash('sha1').update(b).digest('hex');
const flatten=(nodes,prefix='')=>nodes.flatMap(n=>n.type==='directory'?flatten(n.children,prefix+n.name+'/'):[{name:(prefix+n.name).replace(/^src\//,''),uid:n.uid}]);
(async()=>{
 for(const {name,uid} of flatten(inventory)){
   const source=path.resolve('web',name),target=path.resolve(stage,name);
   if(!target.startsWith(stage+path.sep))throw Error('Invalid staging path');
   let bytes=fs.existsSync(source)?fs.readFileSync(source):null;
   if(!changed.has(name)&&(!bytes||hash(bytes)!==uid)){
     if(name==='.vercelignore')bytes=Buffer.from('.vercel/\n.env*\ntests/\n');
     else {
       const response=await fetch('https://security-agency-management-system-nu.vercel.app/'+name);
       if(!response.ok)throw Error('Cannot retrieve baseline '+name);
       bytes=Buffer.from(await response.arrayBuffer());
       if(hash(bytes)!==uid)throw Error('Live baseline changed: '+name);
     }
   }
   fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,bytes);
 }
 fs.mkdirSync(path.join(stage,'.vercel'),{recursive:true});
 fs.copyFileSync('.vercel/project.json',path.join(stage,'.vercel/project.json'));
 fs.writeFileSync('testing/timeout-verification-stage-path.txt',stage);
 console.log('Staged only Admin DTR review and shared DTR report changes. Existing APK and map preserved.');
})().catch(e=>{console.error(e);process.exit(1);});
