const fs=require('node:fs'),path=require('node:path');
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){
 if(e.name==='node_modules'||e.name.startsWith('test-results')||e.name==='downloads')continue;
 const f=path.join(dir,e.name);if(e.isDirectory()){walk(f);continue;}if(!/\.(dart|js|html|cjs)$/.test(f))continue;
 let s=fs.readFileSync(f,'utf8'),n=s.replaceAll('awaiting admin','awaiting Operational Head').replaceAll('Awaiting admin','Awaiting Operational Head').replaceAll('No admin verification','No Operational Head verification').replaceAll('\\nAdmin:', '\\nOperational Head:').replaceAll('active Admins','active Operational Heads');
 if(f.endsWith('letter_request_screen_test.dart'))n=n.replaceAll("tapText(tester, 'Swap')","tapText(tester, 'Swap Duty')").replaceAll("tapText(tester, 'Absence')","tapText(tester, 'Absent')").replaceAll("find.text('Absence')","find.text('Absent')");
 if(s!==n)fs.writeFileSync(f,n);
}}
walk('lib');walk('web');walk('test');
