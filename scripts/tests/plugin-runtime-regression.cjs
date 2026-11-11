'use strict';

/**
 * Regression: LexiNote plugin runtime core (boot, command dispatch, RPC guard rails,
 * loader limits, unload/replace, failure isolation).
 *
 * Run with:
 *   /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
 *     scripts/tests/plugin-runtime-regression.cjs
 */

const assert = require('node:assert/strict');
const {
  createRuntime,
  createSuite,
  rejectsWith,
  makeFile
} = require('./lib/js-runtime-harness.cjs');

const suite = createSuite('plugin-runtime-regression');

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const COMMAND_PLUGIN = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) {
    globalThis.__runtimeCtx = ctx;
    ctx.subscriptions.add(ctx.commands.register({
      id: 'do-it',
      title: '执行',
      run: async () => {
        const count = (Number(await ctx.storage.get('runs')) || 0) + 1;
        await ctx.storage.set('runs', count);
        await ctx.ui.notice('已执行', 2000);
      }
    }));
  },
  async deactivate() {
    globalThis.__runtimeDeactivated = true;
  }
});`;

const IDLE_PLUGIN = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) { globalThis.__runtimeCtx = ctx; },
  async deactivate() {}
});`;

suite.test('boots a LexiNote plugin, runs its command and emits the expected RPC calls', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    const file = makeFile('f1', 'a.md', { mtime: 1234 });
    const result = await handle.boot({ sourceCode: COMMAND_PLUGIN, files: [file], activeFile: file });
    assert.deepEqual(result, {
      ok: true,
      pluginId: 'example.test',
      kind: 'lexinote',
      warnings: []
    });

    const register = host.findCall('commands.register');
    assert.ok(register, 'commands.register must be sent during activation');
    assert.deepEqual(register.params, { id: 'do-it', title: '执行' });
    const rawRegister = host.rawCalls.find((call) => call.method === 'commands.register');
    assert.equal(typeof rawRegister.params, 'string', 'ArkTS expects params as JSON text');
    assert.deepEqual(JSON.parse(rawRegister.params), { id: 'do-it', title: '执行' });

    assert.equal(runtime.runCommand('example.test:do-it'), true);
    await delay(20);

    const get = host.findCall('storage.get');
    const set = host.findCall('storage.set');
    const notice = host.findCall('ui.notice');
    assert.ok(get && set && notice, 'command must read/write storage and show a notice');
    assert.deepEqual(get.params, { key: 'runs' });
    assert.deepEqual(set.params, { key: 'runs', value: '1' });
    assert.deepEqual(notice.params, { message: '已执行', timeoutMs: 2000 });
    assert.equal(host.state.storage.get('runs'), '1');
    assert.equal(host.state.notices.length, 1);
  } finally {
    await runtime.unload();
  }
});

suite.test('accepts the raw ArkTS core-event shape without a payload envelope', async () => {
  const handle = createRuntime();
  const { runtime } = handle;
  try {
    const source = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) {
    ctx.events.on('vault.created', (payload) => { globalThis.__rawEvent = payload; });
  }
});`;
    await handle.boot({ sourceCode: source, files: [makeFile('f1', 'a.md')] });
    const accepted = runtime.receiveEvent(JSON.stringify({
      event: 'vault.created',
      seq: 42,
      fileId: 'f9',
      path: 'raw.md',
      oldPath: '',
      vaultId: 'vault-1',
      revision: 7
    }));
    assert.equal(accepted, true);
    await delay(5);
    assert.ok(globalThis.__rawEvent, 'the SDK handler must receive a payload');
    assert.equal(globalThis.__rawEvent.fileId, 'f9');
    assert.equal(globalThis.__rawEvent.path, 'raw.md');
    assert.equal(globalThis.__rawEvent.seq, 42);
    assert.equal(globalThis.__rawEvent.type, 'vault.created');
    assert.ok(runtime.__inspect().mirror.getByPath('raw.md'), 'the mirror must learn about the new file');
  } finally {
    await runtime.unload();
  }
});

suite.test('rejects a request after the configurable timeout with E_TIMEOUT', async () => {
  const handle = createRuntime({ requestTimeoutMs: 40 });
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    host.autoRespond = false;
    const context = globalThis.__runtimeCtx;
    const started = Date.now();
    const error = await rejectsWith(context.vault.read('a.md'), 'E_TIMEOUT');
    assert.ok(error.message.includes('40ms'), `timeout message should mention the configured limit: ${error.message}`);
    assert.ok(Date.now() - started >= 30, 'timeout must not fire immediately');
    assert.equal(host.pending.length, 1, 'the request reached the host but was never answered');
  } finally {
    await runtime.unload();
  }
});

suite.test('drops unknown and out-of-order response ids without resolving the wrong promise', async () => {
  const handle = createRuntime({ requestTimeoutMs: 500 });
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    host.autoRespond = false;
    const context = globalThis.__runtimeCtx;

    let settled = false;
    const first = context.vault.read('a.md').then(
      (value) => {
        settled = true;
        return value;
      },
      (error) => {
        settled = true;
        throw error;
      }
    );
    await delay(5);
    assert.equal(host.pending.length, 1);

    assert.equal(host.sendResponse({
      protocol: 1,
      id: 'unknown-id',
      ok: true,
      result: JSON.stringify('wrong value')
    }), false, 'unknown response id must be dropped');
    await delay(10);
    assert.equal(settled, false, 'unknown id must not resolve the pending promise');

    const pendingFirst = host.pending.shift();
    host.respond(pendingFirst.id, 'first value');
    assert.equal(await first, 'first value');

    {
      const second = context.vault.read('a.md');
      const third = context.vault.read('a.md');
      await delay(5);
      assert.equal(host.pending.length, 2);
      const secondRequest = host.pending.shift();
      const thirdRequest = host.pending.shift();
      // Answer the later request first; correlation is by id, not arrival order.
      host.respond(thirdRequest.id, 'third value');
      host.respond(secondRequest.id, 'second value');
      assert.equal(await second, 'second value');
      assert.equal(await third, 'third value');
    }
  } finally {
    await runtime.unload();
  }
});

suite.test('caps in-flight requests at 16 and rejects the overflow with E_RATE_LIMITED', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    host.autoRespond = false;
    const context = globalThis.__runtimeCtx;

    const pending = [];
    for (let index = 0; index < 16; index += 1) {
      const promise = context.vault.read('a.md');
      promise.catch(() => {});
      pending.push(promise);
    }
    await delay(10);
    assert.equal(host.pending.length, 16, 'all 16 requests must reach the host');

    const error = await rejectsWith(context.vault.read('a.md'), 'E_RATE_LIMITED');
    assert.ok(error.message.includes('16'), 'rate limit message should mention the cap');
    const noticePromise = context.ui.notice('overflow');
    await rejectsWith(noticePromise, 'E_RATE_LIMITED');
  } finally {
    await runtime.unload();
  }
});

suite.test('rejects non-whitelisted modules with E_UNSUPPORTED_MODULE', async () => {
  for (const name of ['fs', 'electron', 'path', 'child_process']) {
    const handle = createRuntime();
    try {
      const result = await handle.boot({ sourceCode: `require('${name}');` });
      assert.equal(result.ok, false, `${name} must not load`);
      assert.equal(result.code, 'E_UNSUPPORTED_MODULE', `${name} must surface the loader code`);
      assert.ok(
        result.error.startsWith('E_UNSUPPORTED_MODULE: '),
        `error must keep the canonical prefix: ${result.error}`
      );
      assert.equal(handle.runtime.__inspect().active, false, 'a failed boot must not stay active');
    } finally {
      await handle.runtime.unload();
    }
  }
});

suite.test('boots source beyond the former native and JavaScript size caps', async () => {
  const handle = createRuntime();
  try {
    const source = `${IDLE_PLUGIN}\n/*${'x'.repeat(16 * 1024 * 1024 + 1)}*/`;
    const result = await handle.boot({ sourceCode: source });
    assert.equal(result.ok, true, result.error);
    assert.ok(globalThis.__runtimeCtx, 'the large plugin must activate');
    assert.equal(handle.runtime.__inspect().active, true);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('unload releases subscriptions and a second boot replaces the first instance', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    const firstSource = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) {
    globalThis.__first = true;
    globalThis.__firstCtx = ctx;
    globalThis.__eventCount = 0;
    ctx.subscriptions.add(ctx.events.on('vault.created', () => { globalThis.__eventCount += 1; }));
    ctx.subscriptions.add(ctx.commands.register({ id: 'first', title: 'First', run: () => { globalThis.__firstRan = true; } }));
  },
  async deactivate() {
    globalThis.__firstOff = true;
    await globalThis.__firstCtx.storage.set('closed', true);
  }
});`;
    await handle.boot({ sourceCode: firstSource, files: [makeFile('f1', 'a.md')] });
    assert.equal(runtime.runCommand('example.test:first'), true);
    await delay(5);
    assert.equal(globalThis.__firstRan, true);
    assert.equal(host.emit('vault.created', { fileId: 'f2', path: 'new.md' }), true);
    assert.equal(globalThis.__eventCount, 1);

    const secondSource = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) {
    globalThis.__second = true;
    ctx.subscriptions.add(ctx.commands.register({ id: 'second', title: 'Second', run: () => {} }));
  },
  async deactivate() {}
});`;
    const second = await handle.boot({
      pluginId: 'example.second',
      sourceCode: secondSource,
      files: [makeFile('f1', 'a.md')]
    });
    assert.equal(second.ok, true);
    assert.equal(globalThis.__firstOff, true, 'replacing a plugin must run its deactivate()');
    assert.equal(runtime.__inspect().pluginId, 'example.second');
    assert.deepEqual(runtime.__inspect().commands, ['second']);
    assert.equal(runtime.runCommand('example.test:first'), false, 'old command must be gone');

    const before = globalThis.__eventCount;
    host.emit('vault.created', { fileId: 'f3', path: 'another.md' });
    assert.equal(globalThis.__eventCount, before, 'old event handlers must be released');

    await runtime.unload();
    assert.equal(runtime.__inspect().active, false);
    assert.equal(host.emit('vault.created', { fileId: 'f4', path: 'after-unload.md' }), false);

    // Booting the same plugin id twice must replace, never leak a second instance.
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    assert.equal(runtime.__inspect().active, true);
    assert.equal(runtime.__inspect().pluginId, 'example.test');
  } finally {
    await runtime.unload();
  }
});

suite.test('answers RPCs issued by deactivate() while the teardown is still running', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    const source = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) { globalThis.__teardownCtx = ctx; },
  async deactivate() { await globalThis.__teardownCtx.storage.set('closed', true); }
});`;
    await handle.boot({ sourceCode: source });
    await runtime.unload();
    assert.equal(host.state.storage.get('closed'), 'true', 'deactivate RPCs must be answered during teardown');
    assert.equal(runtime.__inspect().active, false);
  } finally {
    await runtime.unload();
  }
});

suite.test('isolates a throwing plugin with E_PLUGIN_FAILED and keeps the runtime usable', async () => {
  const handle = createRuntime();
  const { runtime } = handle;
  try {
    const evalFailure = await handle.boot({ sourceCode: `throw new Error('boom during evaluation');` });
    assert.equal(evalFailure.ok, false);
    assert.equal(evalFailure.code, 'E_PLUGIN_FAILED');
    assert.ok(evalFailure.error.includes('boom during evaluation'));

    const activateFailure = await handle.boot({
      sourceCode: `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({ async activate() { throw new Error('boom during activate'); } });`
    });
    assert.equal(activateFailure.ok, false);
    assert.equal(activateFailure.code, 'E_PLUGIN_FAILED');
    assert.ok(activateFailure.error.includes('boom during activate'));
    assert.equal(runtime.__inspect().active, false);

    assert.equal(runtime.receiveEvent('{not json'), false, 'malformed events must not throw');
    assert.equal(runtime.receiveResponse('{not json'), false, 'malformed responses must not throw');
    assert.equal(runtime.runCommand('whatever'), false);

    const healthy = await handle.boot({ sourceCode: IDLE_PLUGIN });
    assert.equal(healthy.ok, true, 'the runtime must still boot a healthy plugin afterwards');
    assert.equal(runtime.__inspect().active, true);
  } finally {
    await runtime.unload();
  }
});

suite.test('rejects with E_RUNTIME_UNAVAILABLE when the host bridge is missing', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    const context = globalThis.__runtimeCtx;
    delete globalThis.lexiPluginBridge;
    await rejectsWith(context.vault.read('a.md'), 'E_RUNTIME_UNAVAILABLE');
    globalThis.lexiPluginBridge = host.bridge;
    assert.equal(await context.vault.read('a.md'), '');
  } finally {
    await runtime.unload();
  }
});

suite.test('keeps the canonical "<code>: <message>" shape for host failures', async () => {
  const handle = createRuntime();
  const { runtime, host } = handle;
  try {
    await handle.boot({ sourceCode: IDLE_PLUGIN, files: [makeFile('f1', 'a.md')] });
    const context = globalThis.__runtimeCtx;
    host.responder = (request) => {
      if (request.method === 'vault.readText') {
        return { error: { code: 'E_PERMISSION_DENIED', message: 'denied by host' } };
      }
      return null;
    };
    const error = await rejectsWith(context.vault.read('a.md'), 'E_PERMISSION_DENIED');
    assert.equal(error.message, 'E_PERMISSION_DENIED: denied by host');
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
