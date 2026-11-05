const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');

async function main() {
  let state = { revision: 0, fighters: [], battles: [] };
  let transportFailure = false;
  let attempts = [];
  let currentUser = { id: 'account-a', email: 'a@example.com' };
  const client = {
    auth: {
      getSession: async () => ({ data: { session: { user: currentUser } } }),
      onAuthStateChange() {},
      signInWithPassword: async () => ({ data: { user: currentUser } }),
      signOut: async () => ({})
    },
    async rpc(name, params) {
      if (name === 'arena_read') {
        return { data: params.p_revision === state.revision
          ? { revision: state.revision, unchanged: true } : structuredClone(state) };
      }
      attempts.push(params.p_request);
      if (transportFailure) {
        transportFailure = false;
        return { error: { message: 'Network interrupted' } };
      }
      if (params.p_revision !== state.revision) {
        return { error: { code: 'P0001', message: 'ARENA_CONFLICT' } };
      }
      state = { ...cloud.applyChanges(state, params.p_changes), revision: state.revision + 1 };
      return { data: state.revision };
    }
  };
  const context = {
    window: { supabase: { createClient: () => client } },
    crypto: webcrypto, URL, setTimeout,
    self: {}
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync('core.js', 'utf8'), context);
  context.Arena = context.self.Arena;
  vm.runInContext(fs.readFileSync('cloud.js', 'utf8'), context);
  const cloud = context.window.ArenaCloud;
  await cloud.init(() => {});
  await cloud.read();
  await cloud.write(tx => tx.objectStore('fighters').add({ id: 'a', name: 'Alpha', verse: 'World' }));
  assert.equal((await cloud.read()).fighters.length, 1);
  transportFailure = true;
  attempts = [];
  await cloud.write(tx => tx.objectStore('fighters').add({ id: 'b', name: 'Beta', verse: 'World' }));
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0], attempts[1], 'Transport retry must preserve request identity');
  state.revision++;
  await assert.rejects(cloud.write(tx => tx.objectStore('fighters').delete('a')), /Another device/);
  assert.equal(state.fighters.length, 2, 'Conflict must not delete a record');
  await cloud.read();
  await cloud.write(tx => tx.objectStore('battles').add({
    id: 'battle', winner: 'a', loser: 'b', result: 'easy',
    date: new Date().toISOString(), voided: false
  }));
  assert.equal((await cloud.read()).battles.length, 1);
  await cloud.signOut();
  await assert.rejects(cloud.write(() => {}), /Open your cloud archive/);
  currentUser = { id: 'account-b', email: 'b@example.com' };
  state = { revision: 0, fighters: [], battles: [] };
  await cloud.signIn('b@example.com', 'test');
  assert.equal((await cloud.read()).fighters.length, 0, 'Account switching must clear cached records');
  console.log('Cloud adapter tests passed: changes, retry IDs, conflicts, sign-out, account isolation.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
