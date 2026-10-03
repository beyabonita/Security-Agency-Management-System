const fs=require('node:fs'),{spawnSync}=require('node:child_process');
const names=['20260911000000_gps_timeout_and_same_day_requests','20260911000001_duty_relief_and_shift_rosters'];
const migration=process.argv.includes('--applied')?'':names.map(n=>fs.readFileSync('supabase/migrations/'+n+'.sql','utf8')).join('\n');
const test=fs.readFileSync('supabase/tests/database/010_duty_relief_rosters.sql','utf8').replace(/^begin;/,'');
fs.writeFileSync('testing/duty-improvements-rollback.sql',`begin;\nset local lock_timeout='5s';\nset local statement_timeout='90s';\n${migration}\n${test}`);
const r=spawnSync('npx',['--yes','supabase','db','query','--linked','--file','testing/duty-improvements-rollback.sql'],{shell:true,encoding:'utf8',timeout:150000});
const log=(r.stdout||'')+'\n'+(r.stderr||'')+(r.error?.message||'');
fs.writeFileSync('testing/duty-improvements-database.log',log);console.log(log);
if(r.status!==0||/not ok\b|Looks like you failed/.test(log))process.exitCode=1;
