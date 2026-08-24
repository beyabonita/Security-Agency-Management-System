const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const functionsRoot = path.resolve(__dirname, '..', 'functions');
const read = (...parts) => fs.readFileSync(path.join(functionsRoot, ...parts), 'utf8');

const createAccount = read('admin-create-user', 'index.ts');
assert.match(createAccount, /authenticatedUserId\(request, service\)/);
assert.match(createAccount, /isPlatformAdmin/);
assert.match(createAccount, /isHr/);
assert.match(createAccount, /FIELD_ROLES/);
assert.match(createAccount, /PLATFORM_ROLES/);
assert.match(createAccount, /beneficiaryOrganizationId/);
assert.doesNotMatch(createAccount, /isBootstrap/);

const manageAccount = read('admin-manage-user', 'index.ts');
assert.match(manageAccount, /authenticatedUserId\(request, service\)/);
assert.match(manageAccount, /target\.organization_id !== caller\.organization_id/);
assert.match(manageAccount, /body\.action === ["']delete["']/);
assert.match(manageAccount, /Account deletion is disabled/);
assert.match(manageAccount, /removesActiveItAdmin/);
assert.match(manageAccount, /PLATFORM_ROLES/);
assert.match(manageAccount, /beneficiaryOrganizationId/);
assert.match(manageAccount, /Guard and Inspector accounts are managed by HR/);
assert.doesNotMatch(manageAccount, /select\(['"]\*['"]\)/);
assert.match(manageAccount, /optionalBoolean\(body, ["']active["']/);
assert.match(manageAccount, /account_update_rollback_failed/);

const provisionClient = read('it-provision-client', 'index.ts');
assert.match(provisionClient, /Client provisioning is disabled/);
assert.match(provisionClient, /status: 410/);
assert.doesNotMatch(provisionClient, /auth\.admin\.createUser/);

const sharedApi = read('_shared', 'api.ts');
assert.match(sharedApi, /configuredOrigins/);
assert.match(sharedApi, /request\.method !== ["']POST["']/);
assert.match(sharedApi, /Content-Type must be application\/json/);
assert.match(sharedApi, /crypto\.randomUUID\(\)/);
assert.match(sharedApi, /persistSession: false/);
assert.doesNotMatch(sharedApi, /Access-Control-Allow-Origin['"]?\s*[:,]\s*['"]\*/);

const sharedAccounts = read('_shared', 'accounts.ts');
assert.match(sharedAccounts, /databaseBusinessMessage/);

console.log('Edge Function authorization checks passed.');
