// Runs isolated pgTAP fixtures with pending migrations inside one rollback-only
// transaction on the explicitly linked project. No migration is committed here.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const testFile = path.resolve(root, process.argv[2] || '');
const testRoot = path.join(root, 'supabase', 'tests', 'database') + path.sep;
if (!testFile.startsWith(testRoot) || !testFile.endsWith('.sql')) throw new Error('Select a database test inside supabase/tests/database.');
const source = fs.readFileSync(testFile, 'utf8');
if (!/^\s*rollback;\s*$/im.test(source) || /^\s*commit\s*;/im.test(source)) throw new Error('Tests must roll back without COMMIT.');
const pending = [
  '20260905000000_dtr_schedule_periods.sql',
  '20260905000001_inspector_assigned_guard_scope.sql',
].map(name => fs.readFileSync(path.join(root, 'supabase', 'migrations', name), 'utf8'));
const artifactDir = path.join(root, 'testing', 'verification', '2026-09-05-inspector-letters');
fs.mkdirSync(artifactDir, { recursive: true });
const name = path.basename(testFile, '.sql');
const sqlPath = path.join(artifactDir, `${name}-rollback.sql`);
fs.writeFileSync(sqlPath, `begin;\nset local lock_timeout = '5s';\nset local statement_timeout = '90s';\n${pending.join('\n')}\n${source.replace(/^\s*begin;\s*$/im, '')}`);
const result = spawnSync('npx', ['--yes', 'supabase', 'db', 'query', '--linked', '--file', JSON.stringify(sqlPath)], {
  cwd: root, shell: true, encoding: 'utf8', timeout: 150000,
});
const log = [new Date().toISOString(), 'Rollback-only linked database verification', result.stdout || '', result.stderr || '', result.error?.message || ''].join('\n');
fs.writeFileSync(path.join(artifactDir, `${name}.log`), log);
process.stdout.write(log);
if (result.status !== 0 || /not ok\b|Looks like you failed/.test(result.stdout || '')) process.exitCode = 1;
