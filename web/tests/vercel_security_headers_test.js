const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const configPath = path.resolve(__dirname, '..', 'vercel.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const headerRoute = config.headers?.find((route) => route.source === '/(.*)');

assert.ok(headerRoute, 'A site-wide Vercel header route is required.');

const headers = new Map(
  headerRoute.headers.map(({ key, value }) => [key.toLowerCase(), value]),
);
const csp = headers.get('content-security-policy') || '';

for (const requiredHeader of [
  'content-security-policy',
  'permissions-policy',
  'referrer-policy',
  'x-content-type-options',
  'x-frame-options',
  'strict-transport-security',
]) {
  assert.ok(headers.has(requiredHeader), `Missing ${requiredHeader} header.`);
}

for (const requiredDirective of [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  'connect-src',
]) {
  assert.ok(csp.includes(requiredDirective), `CSP must include ${requiredDirective}.`);
}

assert.ok(!csp.includes('*'), 'CSP must not allow every origin.');
assert.ok(!csp.includes('firebase'), 'CSP must not allow legacy Firebase hosts.');
assert.ok(
  csp.includes('https://nominatim.openstreetmap.org'),
  'CSP must allow the Philippine address-search service.',
);
assert.equal(headers.get('x-content-type-options'), 'nosniff');
assert.equal(headers.get('x-frame-options'), 'DENY');

console.log('Vercel security-header checks passed.');
