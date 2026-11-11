'use strict';

/**
 * Regression: JavaScript plugin runtime security boundaries.
 *
 * These tests prove the *explicit* limits of the trusted-code loader: module
 * whitelisting, source validation, plugin-identity binding, manifest validation and the
 * absence of any Obsidian private escape hatch. They do not (and cannot) prove WebView
 * sandboxing — that is provided by ArkWeb, not by JavaScript.
 *
 * Run with:
 *   /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
 *     scripts/tests/plugin-security-regression.cjs
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  ROOT,
  createRuntime,
  createSuite,
  rejectsWith,
  makeFile
} = require('./lib/js-runtime-harness.cjs');

const suite = createSuite('plugin-security-regression');

const IDLE_PLUGIN = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) { globalThis.__securityCtx = ctx; },
  async deactivate() {}
});`;

function expectCode(fn, code, message) {
  let caught = null;
  try {
    fn();
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, message || `expected ${code}`);
  assert.equal(caught.code, code, `${message || ''} (got ${caught.message})`.trim());
  return caught;
}

suite.test('require() rejects fs, electron, child_process and path with E_UNSUPPORTED_MODULE', async () => {
  const handle = createRuntime();
  try {
    const loader = handle.modules.loader;
    const forbidden = ['fs', 'electron', 'child_process', 'path', 'http', 'https', 'node:fs', 'fs/promises'];
    for (const name of forbidden) {
      const error = expectCode(
        () => loader.executeBundle(`require(${JSON.stringify(name)});`, {}),
        'E_UNSUPPORTED_MODULE',
        `require(${name})`
      );
      assert.ok(error.message.startsWith(`E_UNSUPPORTED_MODULE: ${name}`), error.message);
    }
    // A computed module name cannot bypass the whitelist either.
    expectCode(() => loader.executeBundle("require('f' + 's');", {}), 'E_UNSUPPORTED_MODULE', 'computed fs');
    expectCode(() => loader.executeBundle("require('obsidian/../../fs');", {}), 'E_UNSUPPORTED_MODULE', 'traversal');
    expectCode(() => loader.executeBundle("require('./util');", {}), 'E_UNSUPPORTED_MODULE', 'relative id');
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('Obsidian private access cannot reach a filesystem adapter', async () => {
  const handle = createRuntime();
  try {
    const source = `const { Plugin } = require('obsidian');
class PrivateProbe extends Plugin {
  async onload() { globalThis.__privateProbe = this; }
  async onunload() {}
}
module.exports = new PrivateProbe();`;
    const result = await handle.boot({ kind: 'obsidian', sourceCode: source, files: [makeFile('f1', 'a.md')] });
    assert.equal(result.ok, true, result.error);
    const plugin = globalThis.__privateProbe;
    const error = expectCode(() => plugin.app.vault.adapter, 'E_UNSUPPORTED_API', 'vault.adapter');
    assert.ok(error.message.includes('adapter'), error.message);
    assert.equal('plugins' in plugin.app, false, 'app.plugins is not fabricated');
    assert.equal('requestUrl' in plugin.app, false, 'no network helper on app');

    // Accessing the private adapter while the bundle is evaluated must fail the boot
    // with the explicit code, not a generic crash or a silent undefined.
    const evil = `require('obsidian').app.vault.adapter.read('/etc/passwd');`;
    const failed = await handle.boot({ kind: 'obsidian', sourceCode: evil });
    assert.equal(failed.ok, false);
    assert.equal(failed.code, 'E_UNSUPPORTED_API');
    assert.ok(failed.error.startsWith('E_UNSUPPORTED_API: '), failed.error);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('large UTF-8 source runs while invalid source types are rejected', async () => {
  const handle = createRuntime();
  try {
    const loader = handle.modules.loader;
    const source = `module.exports = 'loaded';/*${'知萤'.repeat(400000)}*/`;
    assert.ok(Buffer.byteLength(source, 'utf8') > 2 * 1024 * 1024);
    assert.equal(loader.executeBundle(source, {}), 'loaded');
    for (const source of [null, undefined, 123, {}]) {
      expectCode(() => loader.executeBundle(source, {}), 'E_INVALID_ARGUMENT', 'invalid source');
    }
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('the bridge rejects a forged pluginId or token before the host sees it', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    const bridge = runtime.__inspect().bridge;
    const context = globalThis.__securityCtx;
    const before = host.calls.length;

    const forged = {
      protocol: 1,
      id: 'forged-1',
      pluginId: 'other.plugin',
      token: 'token-1',
      method: 'vault.readText',
      params: { vaultId: 'vault-1', fileId: 'f1' }
    };
    const pluginError = await rejectsWith(bridge.sendRaw(forged), 'E_PERMISSION_DENIED');
    assert.ok(pluginError.message.includes('other.plugin'), pluginError.message);
    assert.equal(host.calls.length, before, 'a forged request must never reach the host');

    const badToken = Object.assign({}, forged, {
      id: 'forged-2',
      pluginId: 'example.test',
      token: 'stolen-token'
    });
    await rejectsWith(bridge.sendRaw(badToken), 'E_PERMISSION_DENIED');

    const wrongProtocol = Object.assign({}, forged, {
      id: 'forged-3',
      pluginId: 'example.test',
      protocol: 2
    });
    await rejectsWith(bridge.sendRaw(wrongProtocol), 'E_PROTOCOL');

    // The plugin's own identity still works through the low-level helper.
    assert.equal(await bridge.sendRaw({
      protocol: 1,
      id: 'valid-1',
      pluginId: 'example.test',
      token: 'token-1',
      method: 'plugin.ping',
      params: {}
    }), true);

    // Host-side defence in depth: bypassing the bridge with the raw proxy still fails
    // validation in the fake host, and no privileged call is recorded.
    const invalidBefore = host.invalid.length;
    const ack = host.bridge.request(JSON.stringify(forged));
    assert.equal(typeof ack, 'string', 'the fake bridge always returns an ack string');
    assert.ok(host.invalid.length > invalidBefore, 'the host must independently reject a forged plugin id');
    assert.equal(host.calls.length, before + 1, 'only the valid ping is recorded');

    assert.equal(runtime.runCommand('other.plugin:whatever'), false);
    assert.equal(runtime.receiveEvent(JSON.stringify({
      protocol: 1,
      type: 'event',
      pluginId: 'other.plugin',
      event: 'vault.created',
      seq: 1,
      payload: '{}'
    })), false, 'foreign events are dropped');

    // The SDK itself still works after the forged attempts.
    assert.equal(await context.vault.read('a.md'), '');
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('manifest validation rejects unknown capabilities and schema drift', async () => {
  const handle = createRuntime();
  try {
    const loader = handle.modules.loader;
    const schemaPath = path.join(ROOT, 'packages/plugin-contracts/manifest.schema.json');
    const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

    assert.deepEqual(schema.required.slice().sort(), [
      'apiVersion',
      'format',
      'formatVersion',
      'id',
      'main',
      'name',
      'version'
    ].sort());
    assert.equal(schema.additionalProperties, false);
    assert.equal(schema.properties.id.pattern, loader.ID_PATTERN.source);
    assert.deepEqual(
      schema.properties.capabilities.items.enum.slice().sort(),
      loader.CAPABILITIES.slice().sort(),
      'manifest schema and loader capability enum must not drift'
    );

    const valid = {
      format: 'lexinote-plugin',
      formatVersion: 1,
      id: 'example.hello',
      name: '示例插件',
      version: '1.0.0',
      apiVersion: '1.0',
      main: 'main.js',
      description: 'test',
      author: 'LexiNote',
      capabilities: ['vault.read', 'ui.notice'],
      targets: ['harmonyos'],
      isDesktopOnly: false
    };
    const roundTripped = JSON.parse(JSON.stringify(valid));
    const accepted = loader.validateManifest(roundTripped, 'lexinote');
    assert.equal(accepted.ok, true, accepted.errors.join('; '));
    assert.deepEqual(accepted.manifest, valid);

    const unknown = Object.assign({}, roundTripped, {
      capabilities: ['vault.read', 'fs.read']
    });
    const rejected = loader.validateManifest(unknown, 'lexinote');
    assert.equal(rejected.ok, false);
    assert.ok(rejected.errors.some((item) => item.includes('未知能力 fs.read')), rejected.errors.join('; '));

    const badId = Object.assign({}, roundTripped, { id: 'Bad ID' });
    assert.equal(loader.validateManifest(badId, 'lexinote').ok, false);
    assert.equal(loader.validateManifest(Object.assign({}, roundTripped, { main: '../escape.js' }), 'lexinote').ok, false);
    assert.equal(loader.validateManifest(Object.assign({}, roundTripped, { script: 'evil.js' }), 'lexinote').ok, false);
    assert.equal(loader.validateManifest({ id: 'x' }, 'lexinote').ok, false);
    assert.equal(loader.validateManifest('{not json', 'lexinote').ok, false);

    const obsidian = {
      id: 'obsidian.hello',
      name: 'Obsidian Hello',
      version: '1.0.0',
      minAppVersion: '1.0.0',
      description: 'test',
      author: 'test',
      isDesktopOnly: false
    };
    assert.equal(loader.validateManifest(obsidian, 'obsidian').ok, true);
    assert.equal(loader.validateManifest(Object.assign({}, obsidian, { isDesktopOnly: 'no' }), 'obsidian').ok, false);
    assert.equal(loader.validateManifest(Object.assign({}, obsidian, { capabilities: [] }), 'obsidian').ok, false);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('malformed host input never throws out of the runtime', async () => {
  const handle = createRuntime();
  const { runtime } = handle;
  try {
    assert.equal((await runtime.boot('{')).ok, false);
    assert.equal((await runtime.boot('{}')).code, 'E_PROTOCOL');
    assert.equal(runtime.receiveResponse('{'), false);
    assert.equal(runtime.receiveResponse('null'), false);
    assert.equal(runtime.receiveEvent('[]'), false);
    assert.equal(runtime.receiveEvent('{}'), false);
    assert.equal(runtime.runCommand(''), false);
    assert.equal(runtime.runCommand('no-colon'), false);
    assert.equal(await runtime.unload(), false);
  } finally {
    await runtime.unload();
  }
});

suite.run().then((summary) => {
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}).catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
