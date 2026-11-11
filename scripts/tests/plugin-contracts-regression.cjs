// P01 · neutral contract regression: protocol parsing, capability mapping, error encoding.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const ROOT = require('node:path').resolve(__dirname, '../../entry/src/main/ets/plugin/model');
const ts = require(process.env.LEXI_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const source = fs.readFileSync(path.join(ROOT, name + '.ets'), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const module = { exports: {} };
  cache.set(name, module.exports);
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename: name })((spec) => load(spec.replace('./', '')), module, module.exports);
  return module.exports;
}

const { PluginCapability, PluginState, PluginLimits, PluginFileRef, PluginRecord } = load('PluginModels');
const { PluginErrorCode, PluginErrors } = load('PluginErrors');
const { PluginRpcMethod, PluginRpcRequest, PluginRpcResponse } = load("PluginContracts");
const { PluginRpcEvent } = load('PluginContracts');


let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };
function throwsCode(fn, code, message) {
  assertions++;
  assert.throws(fn, (error) => String(error.message).startsWith(code), message);
}

// 1. Protocol parsing accepts a well formed request.
const good = JSON.stringify({ protocol: 1, id: 'r-1', pluginId: 'a.b', token: 't', method: 'vault.readText', params: '{}' });
const request = PluginRpcRequest.parse(good);
eq(request.method, 'vault.readText', 'method parsed');
eq(request.pluginId, 'a.b', 'pluginId parsed');
eq(request.protocol, 1, 'protocol parsed');
console.log('PASS a well formed request parses');

// 2. Protocol rejection cases.
throwsCode(() => PluginRpcRequest.parse(''), 'E_PROTOCOL', 'empty payload');
throwsCode(() => PluginRpcRequest.parse('not json'), 'E_PROTOCOL', 'invalid json');
throwsCode(() => PluginRpcRequest.parse(JSON.stringify({ protocol: 2, id: 'r', method: 'plugin.ping' })), 'E_PROTOCOL', 'wrong protocol');
throwsCode(() => PluginRpcRequest.parse(JSON.stringify({ protocol: 1, id: 'bad id!', method: 'plugin.ping' })), 'E_PROTOCOL', 'bad id');
throwsCode(() => PluginRpcRequest.parse(JSON.stringify({ protocol: 1, id: 'r', method: 'eval' })), 'E_UNSUPPORTED_API', 'unknown method');
throwsCode(() => PluginRpcRequest.parse(JSON.stringify({ protocol: 1, id: 'r', method: 'native.invoke' })), 'E_UNSUPPORTED_API', 'no generic native bridge');
throwsCode(() => PluginRpcRequest.parse('x'.repeat(PluginLimits.MAX_RPC_BYTES + 10)), 'E_RATE_LIMITED', 'oversized payload');
console.log('PASS protocol rejects bad versions, ids, unknown methods and oversized payloads');

// 3. Every method has a capability (or none) and the mapping is total.
for (const method of PluginRpcMethod.ALL) {
  const capability = PluginRpcMethod.capabilityOf(method);
  assertions++;
  assert.equal(typeof capability, 'string', `${method} maps to a string`);
  if (capability) { assertions++; assert.ok(PluginCapability.known(capability), `${method} capability is known`); }
}
eq(PluginRpcMethod.capabilityOf('vault.readText'), 'vault.read', 'read maps to vault.read');
eq(PluginRpcMethod.capabilityOf('vault.writeText'), 'vault.write', 'write maps to vault.write');
eq(PluginRpcMethod.capabilityOf('editor.replaceAll'), 'editor.write', 'editor write');
eq(PluginRpcMethod.capabilityOf('storage.set'), 'plugin.storage', 'storage');
eq(PluginRpcMethod.capabilityOf('plugin.ping'), '', 'ping needs no capability');
ok(!PluginRpcMethod.known('eval'), 'no eval method exists');
ok(PluginRpcMethod.ALL.every((method) => !method.includes('invoke')), 'no generic invoke method exists');
console.log('PASS the method table is a closed whitelist with a total capability mapping');

// 4. Responses round-trip.
const success = JSON.parse(PluginRpcResponse.success('r-1', '{"a":1}'));
eq(success.ok, true, 'success ok');
eq(JSON.parse(success.result).a, 1, 'result is JSON text');
const failure = JSON.parse(PluginRpcResponse.failure('r-2', 'E_CONFLICT', '冲突'));
eq(failure.ok, false, 'failure not ok');
eq(failure.error.code, 'E_CONFLICT', 'error code');
eq(failure.error.message, '冲突', 'error message');
const event = JSON.parse(PluginRpcEvent.of('a.b', 'vault.modified', 7, '{}'));
eq(event.type, 'event', 'event type');
eq(event.seq, 7, 'event seq');
console.log('PASS responses and events serialize to the documented shape');

// 5. Error encoding is stable across the boundary.
const raised = PluginErrors.raise(PluginErrorCode.CONFLICT, '已修改');
eq(raised.message, 'E_CONFLICT: 已修改', 'canonical message shape');
eq(PluginErrors.codeOf(raised), 'E_CONFLICT', 'codeOf extracts the code');
eq(PluginErrors.messageOf(raised), '已修改', 'messageOf strips the code');
eq(PluginErrors.codeOf(new Error('boom')), 'E_UNKNOWN', 'plain errors are E_UNKNOWN');
eq(PluginErrors.codeOf(undefined), 'E_UNKNOWN', 'missing error is E_UNKNOWN');
eq(PluginErrors.normalize(new Error('DOCUMENT_CHANGED_ELSEWHERE')).split(':')[0], 'E_CONFLICT', 'storage conflict normalized');
eq(PluginErrors.normalize(new Error('笔记不存在')).split(':')[0], 'E_NOT_FOUND', 'missing note normalized');
eq(PluginErrors.normalize(new Error('文件夹授权已失效')).split(':')[0], 'E_PERMISSION_DENIED', 'revoked grant normalized');
console.log('PASS errors keep one canonical shape from ArkTS to JavaScript');

// 6. FileRef never carries a physical path.
const ref = PluginFileRef.of('n1', 'v1', '课程/一.md', 'p1', 1, 2, 42);
eq(ref.path, '课程/一.md', 'logical path only');
eq(ref.name, '一.md', 'name is the basename');
eq(ref.extension, 'md', 'extension');
ok(!('physical' in ref), 'no physical field');
console.log('PASS FileRef exposes the logical path only');

// 7. Records clone deeply (no shared arrays).
const record = new PluginRecord();
record.id = 'a.b'; record.requestedCapabilities = ['vault.read']; record.grantedCapabilities = ['vault.read'];
const copy = PluginRecord.clone(record);
copy.requestedCapabilities.push('vault.write');
eq(record.requestedCapabilities.length, 1, 'clone does not share arrays');
eq(copy.id, 'a.b', 'clone keeps scalars');
console.log('PASS PluginRecord.clone is deep for arrays');

// 8. Constants are stable, which matters for persisted data.
eq(PluginState.ACTIVE, 'active', 'state ids are stable');
eq(PluginCapability.VAULT_READ, 'vault.read', 'capability ids are stable');
eq(Object.keys(PluginState).every((key) => typeof PluginState[key] === 'string'), true, 'PluginState is a bag of string constants');
ok(PluginLimits.MAX_RPC_BYTES > 0, 'limits are set');
console.log('PASS persisted identifiers are stable strings');

console.log(`\nplugin-contracts-regression: ${assertions} assertions passed`);
