'use strict';
const assert = require('node:assert/strict');
const { createProfileContext, STORAGE_KEY } = require('../src/profile-store');
const { createSandbox } = require('../../../scripts/tests/lib/plugin-sandbox.cjs');
const box = createSandbox(); box.reset();
const hostStorage = box.prepareStorage();
const { PluginAiService: native } = box.load('plugin/ai/PluginAiService');
const data = new Map();
let failStorage = false;
let failHost = false;
const clone = value => JSON.parse(JSON.stringify(value));
const ctx = { storage: {
  async get(key) { return data.has(key) ? clone(data.get(key)) : null; },
  async set(key, value) {
    if (failStorage) { throw Error('测试存储写入失败'); }
    data.set(key, clone(value));
  },
  async remove(key) { data.delete(key); }
}, ai: Object.fromEntries(['status', 'configure', 'models', 'balance', 'chat'].map(method => [method, async patch => {
  if (failHost && method === 'configure') { throw Error('测试宿主写入失败'); }
  return JSON.parse(await native[method](JSON.stringify(patch || {})));
}])) };
const respond = body => box.expectHttp({ status: 200, body: JSON.stringify(body) });
const lastKey = () => box.state.httpRequests.at(-1).options.header.Authorization;

(async () => {
  await hostStorage.setSetting('pluginAiConfig.v1', JSON.stringify({ provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', apiKey: 'secret-original' }));
  native.resetForTests();
  let ai = createProfileContext(ctx).ai;
  assert.equal((await ai.status()).needsApiKey, false);
  assert.ok(!JSON.stringify(await ai.profiles()).includes('secret-original'));
  respond({ data: [{ id: 'deepseek-chat' }] });
  await ai.models();
  assert.equal(lastKey(), 'Bearer secret-original', 'migration preserves a usable original host binding');
  await assert.rejects(ai.configure({ action: 'create', baseUrl: 'https://openrouter.ai/api/v1', model: 'vendor/model' }), /API Key/);
  assert.equal((await ai.profiles()).profiles.length, 1, 'new profiles never inherit a host key');
  const router = await ai.configure({ action: 'create', name: 'Router', baseUrl: 'https://openrouter.ai/api/v1',
    model: 'vendor/model', apiKey: 'secret-router' });
  const legacySelection = await ai.configure({ action: 'select', profileId: 'legacy' });
  assert.equal(legacySelection.profileId, 'legacy', 'migrated host key is selectable');
  await ai.configure({ action: 'select', profileId: router.profileId });
  assert.equal((await ai.status()).profileId, router.profileId);
  await ai.configure({ profileId: 'legacy', apiKey: 'secret-original' });
  assert.equal((await ai.status()).profileId, router.profileId, 'inactive edits do not change the selected provider');
  const before = clone(data.get(STORAGE_KEY));
  failStorage = true;
  await assert.rejects(ai.configure({ action: 'create', baseUrl: 'https://proxy.example/v1', model: 'test', apiKey: 'secret-failed' }), /存储写入失败/);
  failStorage = false;
  assert.deepEqual(data.get(STORAGE_KEY), before);
  assert.equal(JSON.parse(await native.status()).baseUrl, router.baseUrl, 'failed plugin persistence must not overwrite the host key');
  failHost = true;
  await assert.rejects(ai.configure({ action: 'select', profileId: 'legacy' }), /宿主写入失败/);
  failHost = false;
  assert.deepEqual(data.get(STORAGE_KEY), before, 'host refusal rolls back the local selection');
  assert.equal((await ai.status()).profileId, router.profileId);

  const spare = await ai.configure({ action: 'create', name: 'Spare', baseUrl: router.baseUrl,
    model: 'vendor/spare', apiKey: 'secret-spare' });
  await native.configureFor('other.plugin', JSON.stringify({ baseUrl: router.baseUrl, model: 'other', apiKey: 'secret-other-plugin' }));
  respond({ data: [{ id: 'vendor/spare' }] });
  await ai.models();
  assert.equal(lastKey(), 'Bearer secret-spare', 'same-address accounts and external host changes cannot reuse the wrong key');
  ai = createProfileContext(ctx).ai;
  assert.equal((await ai.status()).profileId, spare.profileId, 'selection survives reload');
  await ai.configure({ action: 'select', profileId: router.profileId });
  respond({ data: [{ id: 'vendor/model' }] });
  await ai.models();
  assert.equal(lastKey(), 'Bearer secret-router');
  const catalog = await ai.profiles();
  assert.ok(!JSON.stringify(catalog).includes('secret-'), 'public metadata never contains keys');
  for (const profile of catalog.profiles) { await ai.configure({ action: 'remove', profileId: profile.profileId }); }
  assert.equal(JSON.parse(await native.status()).configured, false);
  ai = createProfileContext(ctx).ai;
  assert.equal((await ai.profiles()).profiles.length, 0, 'deletion does not re-import the former host binding');
  const empty = clone(data.get(STORAGE_KEY));
  data.set(STORAGE_KEY, { version: 1, profiles: [{ apiKey: 'corrupt-secret' }] });
  await assert.rejects(createProfileContext(ctx).ai.profiles(), error => !error.message.includes('corrupt-secret') && /配置损坏/.test(error.message));
  data.set(STORAGE_KEY, empty);
  ai = createProfileContext(ctx).ai;
  await Promise.all([1, 2, 3].map(index => ai.configure({ action: 'create', baseUrl: 'https://proxy.example/v1',
    model: `model-${index}`, apiKey: `secret-${index}` })));
  assert.equal((await ai.profiles()).profiles.length, 3, 'concurrent profile saves do not lose accounts');
  console.log('PASS plugin-owned profiles: original host compatibility, migration, credential routing, atomic failures, reload, deletion and concurrent saves');
})().catch(error => { console.error(error); process.exitCode = 1; });
