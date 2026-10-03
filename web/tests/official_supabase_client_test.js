const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.resolve(__dirname, '..', 'js', 'supabase-firebase-bridge.js'),
  'utf8',
);

const calls = [];
function query(table) {
  const filters = [];
  const builder = {
    select() { return builder; },
    eq(column, value) { filters.push([column, value]); return builder; },
    order() { return builder; },
    limit() { return builder; },
    insert() { return builder; },
    upsert() { return builder; },
    update() { return builder; },
    delete() { return builder; },
    single() { return builder; },
    then(resolve) {
      calls.push({ kind: 'query', table, filters });
      return Promise.resolve({ data: [{ id: 'profile-1', first_name: 'Sentinel' }], error: null }).then(resolve);
    },
  };
  return builder;
}

const client = {
  auth: {
    onAuthStateChange(callback) {
      queueMicrotask(() => callback('INITIAL_SESSION', { user: { id: 'initial-user', email: 'initial@example.com' } }));
      return { data: { subscription: { unsubscribe() {} } } };
    },
    async signInWithPassword(credentials) {
      calls.push({ kind: 'signInWithPassword', credentials });
      return { data: { session: { user: { id: 'signed-in-user', email: credentials.email } } }, error: null };
    },
    async signOut() { return { error: null }; },
  },
  from: query,
  async rpc(name, params) {
    calls.push({ kind: 'rpc', name, params });
    return { data: null, error: null };
  },
  functions: { async invoke() { return { data: { id: 'new-user' }, error: null }; } },
  channel() { return { on() { return this; }, subscribe() { return this; } }; },
  removeChannel() {},
};

const window = {
  supabase: {
    createClient(url, key, options) {
      calls.push({ kind: 'createClient', url, key, options });
      return client;
    },
  },
};
window.window = window;
const context = vm.createContext({
  window,
  location: { hostname: 'security-agency-management-system-nu.vercel.app' },
  document: { readyState: 'complete', write() { throw new Error('SDK loader should not run when SDK is present'); } },
  console,
  Promise,
  Set,
  Object,
  String,
  Date,
  Math,
  queueMicrotask,
});

vm.runInContext(source, context, { filename: 'supabase-firebase-bridge.js' });

(async () => {
  await new Promise((resolve) => queueMicrotask(resolve));
  const create = calls.find((call) => call.kind === 'createClient');
  assert.ok(create, 'uses the official Supabase createClient');
  assert.equal(create.options.auth.autoRefreshToken, true);
  assert.equal(create.options.auth.persistSession, true);

  let initialUser;
  window.firebase.auth().onAuthStateChanged((user) => { initialUser = user; });
  await new Promise((resolve) => queueMicrotask(resolve));
  assert.equal(initialUser.uid, 'initial-user');
  assert.equal(initialUser.email, 'initial@example.com');

  const signedIn = await window.firebase.auth().signInWithEmailAndPassword('guard@example.com', 'secret');
  assert.equal(signedIn.user.uid, 'signed-in-user');
  const credentials = calls.find((call) => call.kind === 'signInWithPassword').credentials;
  assert.equal(credentials.email, 'guard@example.com');
  assert.equal(credentials.password, 'secret');

  await window.db.collection('incidents').doc('incident-1').update({
    status: 'acknowledged', statusNote: 'Seen by Inspector',
  });
  const rpc = calls.find((call) => call.kind === 'rpc' && call.name === 'update_incident_status');
  assert.ok(rpc, 'routes incident updates through the secure RPC');
  assert.equal(rpc.name, 'update_incident_status');
  assert.equal(rpc.params.p_incident_id, 'incident-1');
  assert.equal(rpc.params.p_status, 'acknowledged');
  assert.equal(rpc.params.p_status_note, 'Seen by Inspector');

  const profile = await window.db.collection('users').doc('profile-1').get();
  assert.equal(profile.data().firstName, 'Sentinel');
  console.log('Official Supabase client compatibility checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
