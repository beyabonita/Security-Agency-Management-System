const fs=require('node:fs'),path=require('node:path');
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){
  if(['node_modules','test-results','downloads','.git'].some(x=>e.name.startsWith(x)))continue;
  const file=path.join(dir,e.name);
  if(e.isDirectory()){walk(file);continue;}
  if(!/\.(html|js|cjs|dart)$/.test(file))continue;
  let s=fs.readFileSync(file,'utf8');
  const n=s.replace(/(?<!IT )\bAdmin\b/g,'Operational Head').replace(/(?<!IT )\bADMIN\b/g,'OPERATIONAL HEAD')
    .replace(/your admin\b/g,'your Operational Head').replace(/an admin\b/g,'an Operational Head');
  if(s!==n)fs.writeFileSync(file,n);
}}
walk('lib');walk('web');walk('test');
for(const file of ['web/admin/js/admin-shell.js','web/inspector/js/inspector-shell.js']){
 let s=fs.readFileSync(file,'utf8');
 const icon='<svg class="ax-nav-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true" focusable="false"><path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3Z"/><path d="M9 3v15M15 6v15"/><circle cx="15" cy="11" r="2" fill="currentColor"/></svg>';
 s=s.replace("link.textContent = 'Live guard map';",`link.innerHTML = '${icon}<span>Live guard map</span>';`);
 fs.writeFileSync(file,s);
}
