const assert = require('node:assert/strict');
const policy = require('../js/password-policy.js');
const cases = require('../../supabase/tests/password-policy-cases.json');
cases.forEach((item,index)=>assert.equal(policy.error(item.password)===null,item.valid,`Password policy case ${index}`));
assert.equal(policy.error('Aa1!'+'a'.repeat(68)),null);
assert.ok(policy.error('Aa1!'+'a'.repeat(69)));
assert.ok(policy.error('Aa1!'+'😀'.repeat(18)));
assert.ok(policy.error(null));
console.log('Password policy cases passed.');
