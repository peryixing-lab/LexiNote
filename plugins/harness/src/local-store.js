'use strict';

/** Serialize plugin writes: the existing host stores all of a plugin's keys together. */
function createLocalContext(ctx) {
  let writes = Promise.resolve();
  const enqueue = operation => {
    const next = writes.catch(() => {}).then(operation);
    writes = next;
    return next;
  };
  return Object.assign({}, ctx, { storage: {
    async get(key) { await writes.catch(() => {}); return ctx.storage.get(key); },
    set(key, value) { return enqueue(() => ctx.storage.set(key, value)); },
    remove(key) { return enqueue(() => ctx.storage.remove(key)); }
  } });
}

/** Leave room for conversations and accounts when upgrading older cache budgets. */
async function compactLookups(ctx) {
  for (const [key, limit] of [['harness.models.v1', 24000], ['harness.services.v1', 10000]]) {
    const stored = await ctx.storage.get(key);
    if (!stored || typeof stored !== 'object' || Array.isArray(stored) || JSON.stringify(stored).length <= limit) { continue; }
    const next = Object.assign({}, stored);
    while (JSON.stringify(next).length > limit && Object.keys(next).length) { delete next[Object.keys(next)[0]]; }
    await ctx.storage.set(key, next);
  }
}

module.exports = { createLocalContext, compactLookups };
