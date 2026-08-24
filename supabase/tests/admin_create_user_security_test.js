const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const functionsRoot = path.resolve(__dirname, '..', 'functions');
const read = (...parts) => fs.readFileSync(path.join(functionsRoot, ...parts), 'utf8');
const source = read('admin-create-user', 'index.ts');
const sharedAccounts = read('_shared', 'accounts.ts');
const sharedApi = read('_shared', 'api.ts');

assert.ok(!source.includes('isBootstrap'), 'HR must never receive a bootstrap path to the IT Admin role.');
assert.match(source, /isHr && !FIELD_ROLES\.includes/);
assert.match(source, /isPlatformAdmin[\s\S]*!PLATFORM_ROLES\.includes/);
assert.match(source, /beneficiaryOrganizationId\(service\)/);
assert.doesNotMatch(source, /body\.organizationId/);
assert.match(source, /const authEmail = `\$\{username\}@\$\{AUTH_EMAIL_DOMAIN\}`/);
assert.match(source, /requestedEmail && requestedEmail !== authEmail/);
assert.match(source, /\.eq\(["']username["'], username\)\s*\.maybeSingle\(\)/);
assert.match(source, /usernameValid\(username\)/);
assert.match(source, /service\.auth\.admin\.deleteUser\(\s*targetId/);
assert.match(source, /\.select\(["']id["']\)\s*\.maybeSingle\(\)/);

assert.match(sharedAccounts, /BENEFICIARY_SLUG = ["']twentytwenty-security-agency["']/);
assert.match(sharedAccounts, /PLATFORM_ROLES = \[["']admin["'], ["']it_admin["']\]/);
assert.match(sharedAccounts, /FIELD_ROLES = \[["']user["'], ["']inspector["']\]/);
assert.match(sharedAccounts, /\.eq\(["']slug["'], BENEFICIARY_SLUG\)/);
assert.match(sharedApi, /request\.method !== ["']POST["']/);
assert.match(sharedApi, /MAX_JSON_BODY_BYTES/);
assert.ok(sharedApi.includes('/^Bearer\\s+(\\S+)$/i'));
assert.doesNotMatch(sharedApi, /Access-Control-Allow-Origin['"]?\s*[:,]\s*['"]\*/);

console.log('Admin account-provisioning security checks passed.');
