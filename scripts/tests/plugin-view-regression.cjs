// P16 · Native plugin views: declaration registry, capability gate, open request.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
box.prepareStorage();
const { PluginViewRegistry } = box.load('plugin/core/PluginViewRegistry');
const { PluginPermissionService } = box.load('plugin/core/PluginPermissionService');
const { PluginCapability } = box.load('plugin/model/PluginModels');
const { PluginRpcMethod, PluginRpcRequest } = box.load('plugin/model/PluginContracts');
const { PluginRpcDispatcher, PluginSession } = box.load('plugin/runtime/PluginRpcDispatcher');

let assertions = 0;
const ok = (value, message) => { assertions++; assert.ok(value, message); };
const eq = (left, right, message) => { assertions++; assert.deepEqual(left, right, message); };
async function rejects(promise, code, message) {
  assertions++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}

function request(id, method, params = {}) {
  const item = new PluginRpcRequest();
  item.id = id; item.pluginId = 'example.views'; item.method = method;
  item.params = JSON.stringify(params);
  return item;
}

function session(capabilities) {
  const current = new PluginSession();
  current.pluginId = 'example.views';
  current.kind = 'lexinote';
  current.capabilities = capabilities;
  return current;
}

(async () => {
  PluginViewRegistry.reset();

  // 1. Registry rules.
  const first = PluginViewRegistry.register('example.views', 'harness', 'Harness');
  eq(first.title, 'Harness', 'view registered');
  ok(PluginViewRegistry.has('example.views', 'harness'), 'view is present');
  const again = PluginViewRegistry.register('example.views', 'harness', 'Harness 2');
  eq(again.createdAt, first.createdAt, 're-register updates instead of duplicating');
  eq(PluginViewRegistry.list('example.views').length, 1, 'one view');
  assertions++;
  assert.throws(() => PluginViewRegistry.register('example.views', 'Bad ID', 'x'), /E_INVALID_ARGUMENT/);
  assertions++;
  assert.throws(() => PluginViewRegistry.register('example.views', 'ok', '  '), /E_INVALID_ARGUMENT/);
  for (let index = 1; index < 8; index += 1) {
    PluginViewRegistry.register('example.views', `view-${index}`, `V${index}`);
  }
  assertions++;
  assert.throws(() => PluginViewRegistry.register('example.views', 'view-overflow', 'X'), /E_QUOTA_EXCEEDED/);
  console.log('PASS view ids, titles, idempotent registration and the per-plugin quota');

  // 2. Open request only succeeds for a declared view and is published for the workspace.
  eq(PluginViewRegistry.requestOpen('example.views', 'missing'), false, 'unknown view is refused');
  eq(box.state.appStorage.get('lexiPluginOpenView'), undefined, 'nothing published for unknown view');
  eq(PluginViewRegistry.requestOpen('example.views', 'harness'), true, 'declared view opens');
  const published = JSON.parse(box.state.appStorage.get('lexiPluginOpenView'));
  eq(published.pluginId, 'example.views', 'request carries plugin id');
  eq(published.viewId, 'harness', 'request carries view id');
  eq(box.state.appStorage.get('lexiPluginRuntimeNeeded'), true, 'runtime is requested');
  console.log('PASS ctx.views.open publishes a scoped request only for declared views');

  // 3. Capability gate: ui.views is required before the registry is touched.
  PluginViewRegistry.reset();
  PluginViewRegistry.register('example.views', 'harness', 'Harness');
  PluginRpcDispatcher.setContext(box.contexts);
  const denied = session([]);
  await rejects(PluginRpcDispatcher.dispatch(denied,
    request('v1', PluginRpcMethod.VIEWS_REGISTER, { id: 'other', title: 'Other' })),
    'E_PERMISSION_DENIED', 'no capability, no view');
  ok(!PluginViewRegistry.has('example.views', 'other'), 'denied registration did not leak');

  await PluginPermissionService.clearAll('example.views');
  await PluginPermissionService.grant('example.views', PluginCapability.UI_VIEWS, [PluginCapability.UI_VIEWS]);
  PluginPermissionService.resetCache();
  await PluginPermissionService.load('example.views');
  const allowed = session([PluginCapability.UI_VIEWS]);
  const registered = JSON.parse(await PluginRpcDispatcher.dispatch(allowed,
    request('v2', PluginRpcMethod.VIEWS_REGISTER, { id: 'other', title: 'Other' })));
  eq(registered.id, 'other', 'declared through RPC');
  eq(JSON.parse(await PluginRpcDispatcher.dispatch(allowed,
    request('v3', PluginRpcMethod.VIEWS_OPEN, { id: 'other' }))), null, 'open returns null');
  const opened = JSON.parse(box.state.appStorage.get('lexiPluginOpenView'));
  eq(opened.viewId, 'other', 'dispatcher open publishes the view');
  await rejects(PluginRpcDispatcher.dispatch(allowed,
    request('v4', PluginRpcMethod.VIEWS_OPEN, { id: 'nope' })), 'E_NOT_FOUND', 'unknown view');

  await PluginRpcDispatcher.dispatch(allowed,
    request('v5', PluginRpcMethod.VIEWS_UNREGISTER, { id: 'other' }));
  ok(!PluginViewRegistry.has('example.views', 'other'), 'unregister removes the declaration');
  console.log('PASS views.* is capability gated and open/unregister behave');

  // 4. Teardown drops every declaration owned by the plugin.
  PluginViewRegistry.releasePlugin('example.views');
  eq(PluginViewRegistry.list('example.views').length, 0, 'release clears the plugin');
  eq(PluginViewRegistry.requestOpen('example.views', 'harness'), false, 'released view cannot open');
  console.log('PASS disabling the plugin releases its views');

  // 5. Capabilities are known to the manifest validator.
  ok(PluginCapability.known('ai.inference'), 'ai.inference is a known capability');
  ok(PluginCapability.known('ui.views'), 'ui.views is a known capability');
  ok(!PluginCapability.known('network.plugin'), 'unknown capabilities stay unknown');
  console.log('PASS ai.inference and ui.views are part of the capability table');

  console.log(`\nplugin-view-regression: ${assertions} assertions passed`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
