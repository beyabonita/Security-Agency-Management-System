// Read-only production verification; no operational records are changed.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const portal = 'https://security-agency-management-system-nu.vercel.app';
const download = 'https://security-agency-management-system-download.vercel.app';
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

async function main() {
  const results = [];
  for (const file of ['inspector/users.html', 'inspector/dashboard.html', 'js/supabase-firebase-bridge.js', 'staff/login.html', 'staff/guard-app-qr.png']) {
    const response = await fetch(`${portal}/${file}?release=1.0.10`, { signal: AbortSignal.timeout(60000) });
    const actual = digest(Buffer.from(await response.arrayBuffer()));
    const expected = digest(fs.readFileSync(path.join(root, 'web', file)));
    results.push({ name: `Published ${file} matches tested source`, status: response.ok && actual === expected ? 'PASS' : 'FAIL', http: response.status, sha256: actual });
  }
  for (const url of [`${portal}/staff/login.html`, 'https://security-agency-management-system-admin.vercel.app/system-access-7d92a4/login.html']) {
    const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
    results.push({ name: 'Login available', url, status: response.ok ? 'PASS' : 'FAIL', http: response.status });
  }
  const apkPath = path.join(root, 'web/downloads/security-agency-management-system-guard.apk');
  const response = await fetch(`${download}/downloads/security-agency-management-system-guard.apk?v=1.0.10`, { signal: AbortSignal.timeout(180000) });
  const hash = crypto.createHash('sha256');
  let size = 0;
  for await (const chunk of response.body) { hash.update(chunk); size += chunk.length; }
  const actual = hash.digest('hex');
  const expected = digest(fs.readFileSync(apkPath));
  const disposition = response.headers.get('content-disposition');
  results.push({ name: 'Complete Android download matches signed local APK', status: response.ok && actual === expected && disposition?.includes('v1.0.10.apk') ? 'PASS' : 'FAIL', http: response.status, size, sha256: actual, disposition });
  const report = { date: new Date().toISOString(), readOnly: true, results };
  const output = path.join(root, 'build/qa/inspector-production-release.json');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  if (results.some(result => result.status !== 'PASS')) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
