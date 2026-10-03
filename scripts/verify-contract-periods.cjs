// Only isolated rollback fixtures are executed, never real personnel changes.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const test = process.argv.slice(2).find(arg => !arg.startsWith('--')) || '009_fixed_period_contracts.sql';
if (!/^\d{3}_[a-z_]+\.sql$/.test(test)) throw new Error('Choose a database test filename.');
const source = fs.readFileSync(path.join(root,'supabase/tests/database',test),'utf8');
if (!/^\s*rollback;\s*$/im.test(source) || /^\s*commit;/im.test(source)) throw new Error('Rollback-only test required.');
const migration = process.argv.includes('--applied') ? '' : fs.readFileSync(path.join(root,'supabase/migrations/20260905000004_fixed_period_contracts.sql'),'utf8');
const directory = path.join(root,'build/qa/contract-periods');
fs.mkdirSync(directory,{recursive:true});
const sql = path.join(directory,`${test}-rollback.sql`);
fs.writeFileSync(sql,`begin;\nset local lock_timeout='5s';\nset local statement_timeout='90s';\n${migration}\n${source.replace(/^\s*begin;\s*$/im,'')}`);
const result = spawnSync('npx',['--yes','supabase','db','query','--linked','--file',JSON.stringify(sql)],
  {cwd:root,shell:true,encoding:'utf8',timeout:150000});
const log = `${new Date().toISOString()}\nRollback-only contract verification\n${result.stdout || ''}\n${result.stderr || ''}\n${result.error?.message || ''}`;
fs.writeFileSync(path.join(directory,`${test}.log`),log);
process.stdout.write(log);
if (result.status !== 0 || /not ok\b|Looks like you failed/.test(log)) process.exitCode=1;
