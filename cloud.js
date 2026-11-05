/* Account-scoped cloud persistence. The publishable key is intentionally public. */
(function () {
  'use strict';

  const PROJECT_URL = 'https://eayukimggwhlqludrdcs.supabase.co';
  const PUBLISHABLE_KEY = 'sb_publishable_lhv9VWPxCIqLMewiBQ0XRQ_AbRdb5Zq';
  let client;
  let user = null;
  let revision = -1;
  let snapshot = { fighters: [], battles: [] };
  let generation = 0;
  let reading = null;
  let onChange = () => {};

  function reset(nextUser) {
    if ((user?.id || null) === (nextUser?.id || null)) return;
    user = nextUser;
    revision = -1;
    snapshot = { fighters: [], battles: [] };
    generation++;
    reading = null;
    onChange();
  }

  function explain(error) {
    const message = error.message || String(error);
    if (message.includes('ARENA_CONFLICT')) {
      return new Error('Another device saved changes first. Refresh the archive, review the latest result, and try again.');
    }
    if (error.code === 'PGRST202' || message.includes('Could not find the function')) {
      return new Error('Cloud setup is needed. Run supabase-setup.sql in your Supabase SQL Editor, then refresh.');
    }
    return new Error(message);
  }

  async function read() {
    if (!user) throw new Error('Sign in to open your cloud archive.');
    if (reading) return reading;
    const expectedGeneration = generation;
    const task = (async () => {
      const { data, error } = await client.rpc('arena_read', { p_revision: revision });
      if (error) throw explain(error);
      if (generation !== expectedGeneration) throw new Error('Account changed. Please refresh.');
      if (!data.unchanged) {
        snapshot = Arena.validate({ version: 1, fighters: data.fighters, battles: data.battles });
        revision = data.revision;
      }
      return snapshot;
    })();
    reading = task;
    try {
      return await task;
    } finally {
      if (reading === task) reading = null;
    }
  }

  function collectChanges(callback) {
    const changes = [];
    callback({
      objectStore(bucket) {
        if (!['fighters', 'battles'].includes(bucket)) throw new Error('Invalid collection.');
        return {
          add(data) { changes.push({ bucket, action: 'add', data }); },
          put(data) { changes.push({ bucket, action: 'put', data }); },
          delete(id) { changes.push({ bucket, action: 'delete', id }); },
          clear() { changes.push({ bucket, action: 'clear' }); }
        };
      }
    });
    return changes;
  }

  function applyChanges(current, changes) {
    const maps = {
      fighters: new Map(current.fighters.map(record => [record.id, record])),
      battles: new Map(current.battles.map(record => [record.id, record]))
    };
    for (const change of changes) {
      const records = maps[change.bucket];
      if (change.action === 'clear') records.clear();
      else if (change.action === 'delete') records.delete(change.id);
      else records.set(change.data.id, change.data);
    }
    return { fighters: [...maps.fighters.values()], battles: [...maps.battles.values()] };
  }

  async function write(callback) {
    if (!user || revision < 0) throw new Error('Open your cloud archive before saving.');
    const expectedGeneration = generation;
    const changes = collectChanges(callback);
    if (!changes.length) return;
    const params = { p_revision: revision, p_request: crypto.randomUUID(), p_changes: changes };
    let response = await client.rpc('arena_apply', params);
    // Retry a transport failure with the same request ID. The server deduplicates it.
    if (response.error && !response.error.code) {
      response = await client.rpc('arena_apply', params);
    }
    if (generation !== expectedGeneration) throw new Error('Account changed during the save. Sign in again to verify it.');
    if (response.error) {
      revision = -1;
      throw explain(response.error);
    }
    snapshot = applyChanges(snapshot, changes);
    revision = response.data;
  }

  async function init(callback) {
    onChange = callback;
    if (!window.supabase) throw new Error('The sign-in service could not load. Reload when online.');
    client = window.supabase.createClient(PROJECT_URL, PUBLISHABLE_KEY);
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    user = data.session?.user || null;
    client.auth.onAuthStateChange((_event, session) => {
      // Keep database calls outside Supabase's auth callback lock.
      setTimeout(() => reset(session?.user || null), 0);
    });
  }

  async function signIn(email, password) {
    if (!client) throw new Error('Reload the page to connect the sign-in service.');
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    reset(data.user);
  }

  async function signOut() {
    const { error } = await client.auth.signOut({ scope: 'local' });
    if (error) throw error;
    reset(null);
  }

  window.ArenaCloud = {
    init, read, write, signIn, signOut,
    get user() { return user; },
    // Exported for the regression suite.
    collectChanges, applyChanges
  };
})();
