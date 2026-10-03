// Executes new exchange migration + selected pgTAP suite in a rollback-only transaction.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const test = process.argv[2] || '008_reciprocal_duty_swaps.sql';
if (!/^\d{3}_[a-z_]+\.sql$/.test(test)) throw new Error('Choose a database test filename.');
const source = fs.readFileSync(path.join(root,'supabase/tests/database',test),'utf8');
if (!/^\s*rollback;\s*$/im.test(source) || /^\s*commit;/im.test(source)) throw new Error('Rollback-only test required.');
const migrations = process.argv.includes('--applied') ? [] : process.argv.includes('--scope-only')
  ? ['20260905000003_bind_exchange_to_current_agency.sql']
  : ['20260905000002_reciprocal_duty_swaps.sql','20260905000003_bind_exchange_to_current_agency.sql'];
const migration = migrations.map(name => fs.readFileSync(path.join(root,'supabase/migrations',name),'utf8')).join('\n');
const directory = path.join(root,'build/qa/duty-exchange');
fs.mkdirSync(directory,{recursive:true});
const sql = path.join(directory,`${test}-rollback.sql`);
fs.writeFileSync(sql,`begin;\nset local lock_timeout='5s';\nset local statement_timeout='90s';\n${migration}\n${source.replace(/^\s*begin;\s*$/im,'')}`);
const result = spawnSync('npx',['--yes','supabase','db','query','--linked','--file',JSON.stringify(sql)],
  {cwd:root,shell:true,encoding:'utf8',timeout:150000});
const log = `${new Date().toISOString()}\nRollback-only exchange verification\n${result.stdout || ''}\n${result.stderr || ''}\n${result.error?.message || ''}`;
fs.writeFileSync(path.join(directory,`${test}.log`),log);
process.stdout.write(log);
if (result.status !== 0 || /not ok\b|Looks like you failed/.test(log)) process.exitCode=1;
