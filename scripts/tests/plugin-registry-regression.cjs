// P05 · state machine, event bus, resource tracker, permissions and plugin storage.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { PluginRecord, PluginState, PluginCapability, PluginEventType, PluginLimits } = box.load('plugin/model/PluginModels');
const { PluginRegistry } = box.load('plugin/core/PluginRegistry');
const { PluginEventBus } = box.load('plugin/core/PluginEventBus');
const { PluginResourceTracker } = box.load('plugin/core/PluginResourceTracker');
const { PluginPermissionService } = box.load('plugin/core/PluginPermissionService');
const { PluginDataStore } = box.load('plugin/core/PluginDataStore');
const S = box.prepareStorage();

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };
async function rejects(promise, code, message) {
  assertions++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}

function record(id, capabilities = []) {
  const item = new PluginRecord();
  item.id = id; item.name = id; item.version = '1.0.0';
  item.requestedCapabilities = capabilities;
  item.state = PluginState.INSTALLED_DISABLED;
  return item;
}

(async () => {
  // 1. Empty catalogue, then persistence round-trip.
  await PluginRegistry.load();
  eq(PluginRegistry.list().length, 0, 'empty catalogue');
  await PluginRegistry.upsert(record('example.hello', [PluginCapability.VAULT_READ]));
  eq(PluginRegistry.list().length, 1, 'record stored');
  PluginRegistry.reset();
  await PluginRegistry.load();
  eq(PluginRegistry.list().length, 1, 'record survives a reload from the key-value store');
  eq(PluginRegistry.get('example.hello').name, 'example.hello', 'fields survive');
  console.log('PASS the installed-plugin catalogue round-trips through storage');

  // 2. Legal state machine.
  await PluginRegistry.setState('example.hello', PluginState.STARTING);
  await PluginRegistry.setState('example.hello', PluginState.ACTIVE);
  eq(PluginRegistry.get('example.hello').enabled, true, 'ACTIVE implies enabled');
  await PluginRegistry.setState('example.hello', PluginState.STOPPING);
  await PluginRegistry.setState('example.hello', PluginState.INSTALLED_DISABLED);
  eq(PluginRegistry.get('example.hello').enabled, false, 'DISABLED implies not enabled');
  await rejects(PluginRegistry.setState('example.hello', PluginState.ACTIVE), 'E_INVALID_ARGUMENT',
    'DISABLED -> ACTIVE must be rejected without STARTING');
  await rejects(PluginRegistry.setState('missing', PluginState.STARTING), 'E_NOT_FOUND', 'unknown plugin');
  ok(PluginRegistry.canTransition(PluginState.STARTING, PluginState.FAILED), 'STARTING can fail');
  ok(!PluginRegistry.canTransition(PluginState.ACTIVE, PluginState.INSTALLED_DISABLED), 'ACTIVE must stop first');
  console.log('PASS the state machine only allows the documented transitions');

  // 3. A record found ACTIVE on disk is never assumed running.
  const live = record('example.live');
  live.state = PluginState.ACTIVE; live.enabled = true;
  await PluginRegistry.upsert(live);
  PluginRegistry.reset();
  await PluginRegistry.load();
  eq(PluginRegistry.get('example.live').state, PluginState.INSTALLED_DISABLED, 'restored as disabled');
  eq(PluginRegistry.get('example.live').enabled, false, 'restored as not enabled');
  console.log('PASS a plugin recorded as ACTIVE is downgraded on reload instead of faking a live runtime');

  // 4. Event bus: ordering, per-vault sequence, isolation.
  PluginEventBus.reset();
  const seen = [];
  PluginEventBus.subscribe('p1', PluginEventType.VAULT_CREATED, (event) => seen.push(`p1:${event.seq}`));
  PluginEventBus.subscribe('p2', PluginEventType.VAULT_CREATED, () => { throw new Error('boom'); });
  PluginEventBus.subscribe('p2', PluginEventType.VAULT_MODIFIED, (event) => seen.push(`p2m:${event.seq}`));
  const created = { type: PluginEventType.VAULT_CREATED, vaultId: 'v1', seq: 0, fileId: 'n1', path: 'a.md' };
  eq(PluginEventBus.publish(created), 2, 'two handlers were invoked');
  eq(created.seq, 1, 'first event gets seq 1');
  PluginEventBus.publish({ type: PluginEventType.VAULT_MODIFIED, vaultId: 'v1', seq: 0, fileId: 'n1', path: 'a.md' });
  PluginEventBus.publish({ type: PluginEventType.VAULT_CREATED, vaultId: 'v2', seq: 0, fileId: 'n2', path: 'b.md' });
  eq(PluginEventBus.lastSeq('v1'), 2, 'sequence is per vault');
  eq(PluginEventBus.lastSeq('v2'), 1, 'second vault restarts at 1');
  eq(seen.includes('p2m:2'), true, 'modify listener only got the modify event');
  ok(PluginEventBus.lastError().includes('boom'), 'a throwing listener is recorded, not propagated');
  await rejects(Promise.resolve().then(() => PluginEventBus.subscribe('p3', 'nope', () => {})),
    'E_INVALID_ARGUMENT', 'unknown event names are refused');
  console.log('PASS events keep per-vault ordering and one throwing plugin cannot break the others');

  // 5. Subscription release is complete and repeatable.
  PluginEventBus.unsubscribePlugin('p1');
  PluginEventBus.unsubscribePlugin('p2');
  eq(PluginEventBus.totalSubscriptions(), 0, 'all subscriptions released');
  eq(PluginEventBus.unsubscribePlugin('p1'), 0, 'second release is a no-op');
  console.log('PASS unsubscribing a plugin releases every listener exactly once');

  // 6. Resource tracker releases in reverse order even when a cleanup throws.
  PluginResourceTracker.reset();
  const released = [];
  PluginResourceTracker.add('p1', 'a', () => released.push('a'));
  PluginResourceTracker.add('p1', 'b', () => { released.push('b'); throw new Error('cleanup failed'); });
  PluginResourceTracker.add('p1', 'c', () => released.push('c'));
  PluginResourceTracker.add('p2', 'x', () => released.push('x'));
  eq(PluginResourceTracker.count('p1'), 3, 'three resources tracked');
  eq(PluginResourceTracker.releaseAll('p1'), 3, 'all three released');
  eq(released, ['c', 'b', 'a'], 'reverse order and cleanup continued past the throwing one');
  eq(PluginResourceTracker.failureCount(), 1, 'the failure was counted, not swallowed silently');
  eq(PluginResourceTracker.releaseAll('p1'), 0, 'a second release is a no-op');
  eq(PluginResourceTracker.count('p2'), 1, 'other plugins are untouched');
  console.log('PASS resources release in reverse order and a throwing cleanup cannot stop the rest');

  // 7. Permissions: default deny, manifest bounded, revocation is immediate.
  await PluginRegistry.upsert(record('example.perm', [PluginCapability.VAULT_READ, PluginCapability.UI_NOTICE]));
  await PluginPermissionService.clearAll('example.perm');
  PluginPermissionService.resetCache();
  eq(await PluginPermissionService.has('example.perm', PluginCapability.VAULT_READ), false, 'default deny');
  await rejects(PluginPermissionService.grant('example.perm', PluginCapability.VAULT_WRITE,
    [PluginCapability.VAULT_READ]), 'E_PERMISSION_DENIED', 'cannot grant what the manifest did not request');
  await rejects(PluginPermissionService.grant('example.perm', 'root.everything',
    [PluginCapability.VAULT_READ]), 'E_INVALID_ARGUMENT', 'unknown capabilities are refused');
  await PluginPermissionService.grant('example.perm', PluginCapability.VAULT_READ,
    [PluginCapability.VAULT_READ, PluginCapability.UI_NOTICE]);
  eq(await PluginPermissionService.has('example.perm', PluginCapability.VAULT_READ), true, 'granted');
  PluginPermissionService.resetCache();
  eq(await PluginPermissionService.has('example.perm', PluginCapability.VAULT_READ), true, 'grant persisted');
  await PluginPermissionService.revoke('example.perm', PluginCapability.VAULT_READ);
  eq(await PluginPermissionService.has('example.perm', PluginCapability.VAULT_READ), false, 'revoked immediately');
  await rejects(PluginPermissionService.require('example.perm', PluginCapability.VAULT_READ),
    'E_PERMISSION_DENIED', 'require() fails after revocation');
  console.log('PASS capabilities default to deny, stay inside the manifest and revoke immediately');

  // Full consent is scoped to one plugin and survives reload without authorizing peers.
  const requested = [PluginCapability.PLUGIN_STORAGE, PluginCapability.UI_COMMANDS];
  await PluginPermissionService.clearAll('calendar');
  await PluginPermissionService.clearAll('assistant');
  eq(await PluginPermissionService.grantAll('calendar', requested), requested, 'full grant matches the declared set');
  PluginPermissionService.resetCache();
  eq(await PluginPermissionService.granted('calendar'), requested, 'full grant persists across cache reload');
  eq(await PluginPermissionService.granted('assistant'), [], 'other plugins remain ungranted');
  await rejects(PluginPermissionService.grantAll('calendar', [PluginCapability.VAULT_WRITE, 'root.everything']),
    'E_INVALID_ARGUMENT', 'invalid full grant fails atomically');
  eq(await PluginPermissionService.granted('calendar'), requested, 'failed request does not partially add write access');
  const saveRawValue = S.setRawValue;
  try {
    S.setRawValue = async () => { throw new Error('E_STORAGE: save failed'); };
    await rejects(PluginPermissionService.grantAll('calendar', [PluginCapability.VAULT_WRITE]),
      'E_STORAGE', 'failed persistence rejects consent');
    eq(await PluginPermissionService.granted('calendar'), requested, 'failed persistence never publishes a new cached grant');
  } finally {
    S.setRawValue = saveRawValue;
  }
  await PluginPermissionService.grantAll('assistant', [PluginCapability.UI_NOTICE]);
  await PluginPermissionService.clearAll('calendar');
  PluginPermissionService.resetCache();
  eq(await PluginPermissionService.granted('calendar'), [], 'turning full permissions off persists revocation');
  eq(await PluginPermissionService.granted('assistant'), [PluginCapability.UI_NOTICE], 'revocation leaves another plugin unchanged');
  console.log('PASS per-plugin full consent is persistent, isolated and atomic');

  // 8. Plugin storage is namespaced and quota bounded.
  await PluginDataStore.clear('p1');
  await PluginDataStore.clear('p2');
  await PluginDataStore.set('p1', 'daily', '{"date":"2026-11-10"}');
  await PluginDataStore.set('p2', 'daily', '{"date":"other"}');
  eq(await PluginDataStore.get('p1', 'daily'), '{"date":"2026-11-10"}', 'value round-trip');
  eq(await PluginDataStore.get('p2', 'daily'), '{"date":"other"}', 'namespaces do not collide');
  eq(await PluginDataStore.get('p1', 'missing'), '', 'missing key yields empty string');
  await rejects(PluginDataStore.set('p1', '../escape', 'x'), 'E_INVALID_ARGUMENT', 'key injection refused');
  await rejects(PluginDataStore.set('p1', 'big', 'x'.repeat(PluginLimits.MAX_STORAGE_BYTES + 1)),
    'E_QUOTA_EXCEEDED', 'quota enforced');
  eq(JSON.parse(await PluginDataStore.snapshot('p1')).daily, '{"date":"2026-11-10"}', 'snapshot is a plain object');
  await PluginDataStore.remove('p1', 'daily');
  eq(await PluginDataStore.get('p1', 'daily'), '', 'removed');
  console.log('PASS plugin storage is namespaced, quota bounded and key validated');

  // 9. Repeated enable/disable never duplicates subscriptions or commands.
  PluginEventBus.reset();
  PluginResourceTracker.reset();
  for (let cycle = 0; cycle < 100; cycle++) {
    const id = PluginEventBus.subscribe('loop', PluginEventType.VAULT_CREATED, () => {});
    PluginResourceTracker.add('loop', 'sub', () => {});
    PluginEventBus.unsubscribe(id);
    PluginResourceTracker.releaseAll('loop');
    await PluginRegistry.setState('example.hello', PluginState.STARTING);
    await PluginRegistry.setState('example.hello', PluginState.ACTIVE);
    await PluginRegistry.setState('example.hello', PluginState.STOPPING);
    await PluginRegistry.setState('example.hello', PluginState.INSTALLED_DISABLED);
  }
  eq(PluginEventBus.totalSubscriptions(), 0, 'no subscription leaked over 100 cycles');
  eq(PluginResourceTracker.total(), 0, 'no resource leaked over 100 cycles');
  eq(PluginRegistry.get('example.hello').state, PluginState.INSTALLED_DISABLED, 'ends disabled');
  console.log('PASS 100 enable/disable cycles leak no subscriptions, resources or state');

  console.log(`\nplugin-registry-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
