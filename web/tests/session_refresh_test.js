const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const bridgeSource = fs.readFileSync(
  path.resolve(__dirname, '..', 'js', 'supabase-firebase-bridge.js'),
  'utf8',
);

let authEvent;
const calls = [];
const client = {
  auth: {
    onAuthStateChange(callback) {
      authEvent = callback;
      return { data: { subscription: { unsubscribe() {} } } };
    },
    async signInWithPassword() { return { data: {}, error: null }; },
    async signOut() { return { error: null }; },
  },
  from() { throw new Error('Not used by auth event test'); },
  async rpc(name) {
    assert.equal(name, 'current_platform_announcement');
    return { data: null, error: null };
  },
  functions: { invoke() {} },
  channel() { return { on() { return this; }, subscribe() { return this; } }; },
  removeChannel() {},
};
const window = {
  supabase: {
    createClient(_url, _key, options) {
      calls.push(options);
      return client;
    },
  },
};
window.window = window;
const context = vm.createContext({
  window,
  location: { hostname: 'security-agency-management-system-nu.vercel.app' },
  document: { readyState: 'complete', write() { throw new Error('Unexpected SDK loading fallback'); } },
  Promise,
  Set,
  Object,
  String,
  Date,
  Math,
  queueMicrotask,
  console,
});
vm.runInContext(bridgeSource, context, { filename: 'supabase-firebase-bridge.js' });

(async () => {
  assert.ok(authEvent, 'registers the official SDK auth event listener immediately');
  assert.equal(calls[0].auth.autoRefreshToken, true);
  assert.equal(calls[0].auth.persistSession, true);

  const observed = [];
  window.auth.onAuthStateChanged((user) => observed.push(user));
  authEvent('INITIAL_SESSION', { user: { id: 'guard-1', email: 'guard@example.test' } });
  await new Promise((resolve) => queueMicrotask(resolve));
  assert.equal(observed.at(-1).uid, 'guard-1');

  authEvent('TOKEN_REFRESHED', { user: { id: 'guard-1', email: 'guard@example.test' } });
  await new Promise((resolve) => queueMicrotask(resolve));
  assert.equal(window.auth.currentUser.uid, 'guard-1');

  authEvent('SIGNED_OUT', null);
  await new Promise((resolve) => queueMicrotask(resolve));
  assert.equal(window.auth.currentUser, null);
  assert.equal(observed.at(-1), null);

  console.log('Session refresh checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
