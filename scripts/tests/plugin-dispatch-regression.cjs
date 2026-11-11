// P10/P14 · RPC dispatcher security surface: capability, identity, vault scope, quotas.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { NoteItem } = box.load('core/LexiModels');
const { PluginCapability } = box.load('plugin/model/PluginModels');
const { PluginRpcMethod, PluginRpcRequest } = box.load('plugin/model/PluginContracts');
const { LexiPathRegistry } = box.load('plugin/adapters/LexiPathRegistry');
const { LexiEditorBridge, PluginEditorHandle } = box.load('plugin/adapters/LexiEditorBridge');
const { PluginRpcDispatcher, PluginSession } = box.load('plugin/runtime/PluginRpcDispatcher');
const { PluginPermissionService } = box.load('plugin/core/PluginPermissionService');
const { PluginCommandRegistry } = box.load('plugin/core/PluginCommandRegistry');
const S = box.prepareStorage();
const context = box.contexts;

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };
async function rejects(promise, code, message) {
  assertions++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}

function request(id, method, params = {}) {
  const item = new PluginRpcRequest();
  item.id = id; item.pluginId = 'example.test'; item.method = method;
  item.params = JSON.stringify(params);
  return item;
}

function session(capabilities) {
  const current = new PluginSession();
  current.pluginId = 'example.test';
  current.kind = 'lexinote';
  current.capabilities = capabilities;
  current.vaultScopes = [];
  return current;
}

(async () => {
  PluginRpcDispatcher.setContext(context);
  const vaultA = await S.createVault(context, '调度 A', '');
  const vaultB = await S.createVault(context, '调度 B', '');
  const note = new NoteItem();
  note.id = 'dispatch-note'; note.vaultId = vaultA.id; note.title = '调度笔记';
  note.content = '# 调度笔记\n内容';
  await S.saveNote(context, note);
  LexiPathRegistry.reset();
  await LexiPathRegistry.refresh(vaultA.id);

  const empty = session([]);

  // 1. Capability is checked before any native call.
  await rejects(PluginRpcDispatcher.dispatch(empty, request('r1', PluginRpcMethod.VAULT_READ,
    { vaultId: vaultA.id, fileId: 'dispatch-note' })), 'E_PERMISSION_DENIED', 'no capability, no read');
  console.log('PASS a method without its capability is refused before touching storage');

  // 2. Capability present in the session but not granted by the user is still refused.
  const reader = session([PluginCapability.VAULT_READ]);
  await rejects(PluginRpcDispatcher.dispatch(reader, request('r2', PluginRpcMethod.VAULT_READ,
    { vaultId: vaultA.id, fileId: 'dispatch-note' })), 'E_PERMISSION_DENIED', 'user grant required');
  await PluginPermissionService.clearAll('example.test');
  await PluginPermissionService.grant('example.test', PluginCapability.VAULT_READ,
    [PluginCapability.VAULT_READ]);
  PluginPermissionService.resetCache();
  await PluginPermissionService.load('example.test');
  const body = await PluginRpcDispatcher.dispatch(reader, request('r3', PluginRpcMethod.VAULT_READ,
    { vaultId: vaultA.id, fileId: 'dispatch-note' }));
  eq(JSON.parse(body), '# 调度笔记\n内容', 'read succeeds after the user grants the capability');
  console.log('PASS the user grant is required in addition to the manifest declaration');

  // 3. Identity is bound to the session.
  const forged = request('r4', PluginRpcMethod.VAULT_READ, { vaultId: vaultA.id, fileId: 'dispatch-note' });
  forged.pluginId = 'attacker.plugin';
  await rejects(PluginRpcDispatcher.dispatch(reader, forged), 'E_PERMISSION_DENIED', 'forged pluginId');
  console.log('PASS a request claiming another pluginId is refused');

  // 4. Vault scope is enforced.
  const scoped = session([PluginCapability.VAULT_READ]);
  scoped.vaultScopes = [vaultA.id];
  await rejects(PluginRpcDispatcher.dispatch(scoped, request('r5', PluginRpcMethod.VAULT_READ,
    { vaultId: vaultB.id, fileId: 'dispatch-note' })), 'E_VAULT_FORBIDDEN', 'out-of-scope vault');
  await rejects(PluginRpcDispatcher.dispatch(empty, request('r6', PluginRpcMethod.VAULT_LIST,
    { vaultId: 'vault-forged' })), 'E_PERMISSION_DENIED', 'unknown vault stops at the capability gate');
  console.log('PASS vault scope and unknown vaults are enforced');

  // 5. Reading a note from another vault by id does not leak.
  await rejects(PluginRpcDispatcher.dispatch(reader, request('r7', PluginRpcMethod.VAULT_READ,
    { vaultId: vaultB.id, fileId: 'dispatch-note' })), 'E_NOT_FOUND', 'cross-vault id is refused');
  console.log('PASS a note id from another vault resolves to E_NOT_FOUND');

  // 6. Editor methods without an editor fail explicitly.
  await PluginPermissionService.grant('example.test', PluginCapability.EDITOR_READ, [PluginCapability.EDITOR_READ]);
  await PluginPermissionService.grant('example.test', PluginCapability.EDITOR_WRITE, [PluginCapability.EDITOR_WRITE]);
  LexiEditorBridge.reset();
  eq(JSON.parse(await PluginRpcDispatcher.dispatch(session([PluginCapability.EDITOR_READ]),
    request('r8', PluginRpcMethod.EDITOR_ACTIVE))), null, 'editor.active is null when nothing is open');
  await rejects(PluginRpcDispatcher.dispatch(session([PluginCapability.EDITOR_WRITE]),
    request('r9', PluginRpcMethod.EDITOR_REPLACE_ALL, { text: 'x' })), 'E_EDITOR_READONLY',
    'writing without an editor fails explicitly');
  console.log('PASS editor calls without an editor return null or an explicit error');

  // 7. Editor write goes through the registered handle and reports the new content.
  const handle = new PluginEditorHandle();
  handle.editorId = 'disp-editor'; handle.noteId = 'dispatch-note'; handle.vaultId = vaultA.id;
  let text = '原文';
  handle.getContent = () => text;
  handle.getBaseContent = () => text;
  handle.isVisible = () => true; handle.isFocused = () => true;
  handle.getSelection = () => ({ from: 0, to: 0 });
  handle.replaceRange = (start, end, next) => { text = text.substring(0, start) + next + text.substring(end); return true; };
  handle.flush = async () => {};
  LexiEditorBridge.register(handle);
  const wrote = JSON.parse(await PluginRpcDispatcher.dispatch(session([PluginCapability.EDITOR_WRITE]),
    request('r10', PluginRpcMethod.EDITOR_REPLACE_ALL, { text: '改写' })));
  eq(wrote.content, '改写', 'editor content replaced');
  eq(text, '改写', 'the page handle actually received the edit');
  const snapshot = JSON.parse(await PluginRpcDispatcher.dispatch(session([PluginCapability.EDITOR_READ]),
    request('r11', PluginRpcMethod.EDITOR_ACTIVE)));
  eq(snapshot.noteId, 'dispatch-note', 'editor snapshot carries the note id');
  ok(typeof snapshot.cursor.line === 'number', 'editor snapshot carries a cursor');
  console.log('PASS editor writes reach the page handle and snapshots stay JSON shaped');
  LexiEditorBridge.reset();

  // 8. Storage quota and key validation.
  const storageSession = session([PluginCapability.PLUGIN_STORAGE]);
  await PluginPermissionService.grant('example.test', PluginCapability.PLUGIN_STORAGE, [PluginCapability.PLUGIN_STORAGE]);
  await rejects(PluginRpcDispatcher.dispatch(storageSession, request('r12', PluginRpcMethod.STORAGE_SET,
    { key: '../x', value: '1' })), 'E_INVALID_ARGUMENT', 'key injection refused');
  eq(JSON.parse(await PluginRpcDispatcher.dispatch(storageSession,
    request('r13', PluginRpcMethod.STORAGE_GET, { key: 'missing' }))), '', 'missing key is an empty string');
  console.log('PASS storage methods validate keys and never fabricate values');

  // 9. Metadata subset is exposed with explicit unsupported fields.
  await PluginPermissionService.grant('example.test', PluginCapability.METADATA_READ, [PluginCapability.METADATA_READ]);
  const meta = JSON.parse(await PluginRpcDispatcher.dispatch(session([PluginCapability.METADATA_READ]),
    request('r14', PluginRpcMethod.METADATA_GET, { vaultId: vaultA.id, fileId: 'dispatch-note' })));
  eq(meta.fileId, 'dispatch-note', 'metadata file id');
  eq(meta.path, '调度笔记.md', 'metadata uses the logical path');
  ok(meta.supportedFields.includes('headings'), 'supported fields present');
  ok(meta.unsupportedFields.length > 0, 'unsupported fields are named');
  console.log('PASS metadata exposes the verified subset and names what is unsupported');

  // 10. Commands cannot shadow built-in ids.
  await PluginPermissionService.grant('example.test', PluginCapability.UI_COMMANDS, [PluginCapability.UI_COMMANDS]);
  await rejects(PluginRpcDispatcher.dispatch(session([PluginCapability.UI_COMMANDS]),
    request('r15', PluginRpcMethod.COMMANDS_REGISTER, { id: 'save', title: '抢占保存' })),
  'E_INVALID_ARGUMENT', 'built-in command id is reserved');
  const registered = JSON.parse(await PluginRpcDispatcher.dispatch(session([PluginCapability.UI_COMMANDS]),
    request('r16', PluginRpcMethod.COMMANDS_REGISTER, { id: 'hello', title: '你好' })));
  eq(registered.id, 'example.test:hello', 'plugin command is qualified');
  eq(PluginCommandRegistry.visible().length, 1, 'command registered');
  console.log('PASS plugin commands are qualified and cannot shadow built-in ids');

  console.log(`\nplugin-dispatch-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
