// P16 · Harness plugin end-to-end: boot, native view, chat turn, tools, errors, commands.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRuntime, makeFile } = require('./lib/js-runtime-harness.cjs');

const ROOT = path.resolve(__dirname, '../..');
const SOURCE = fs.readFileSync(path.join(ROOT, 'plugins/harness/dist/main.js'), 'utf8');
const MANIFEST = JSON.parse(fs.readFileSync(path.join(ROOT, 'plugins/harness/manifest.json'), 'utf8'));
const PLUGIN_ID = MANIFEST.id;

let assertions = 0;
const ok = (value, message) => { assertions++; assert.ok(value, message); };
const eq = (left, right, message) => { assertions++; assert.deepEqual(left, right, message); };

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(predicate, message, timeoutMs) {
  const deadline = Date.now() + (timeoutMs || 2000);
  while (Date.now() < deadline) {
    if (predicate()) { return true; }
    await delay(20);
  }
  throw new Error(`timeout waiting for ${message}`);
}

function bootPayload(file) {
  return {
    type: 'boot',
    protocol: 1,
    pluginId: PLUGIN_ID,
    kind: 'lexinote',
    token: 'token-harness',
    runtimeVersion: '1',
    capabilities: MANIFEST.capabilities,
    vaultId: 'vault-1',
    manifestJson: JSON.stringify(MANIFEST),
    filesJson: JSON.stringify([file]),
    activeFileJson: JSON.stringify(file),
    editorJson: 'null',
    settingsJson: 'null',
    dataJson: '{}',
    sourceCode: SOURCE,
    sourceName: 'main.js',
    stylesCss: '',
    warnings: []
  };
}

function storedSession(host) {
  const raw = host.state.storage.get('harness.session.v1');
  return raw ? JSON.parse(raw) : null;
}

function surface() {
  return document.getElementById('plugin-surface');
}

function sendText(value) {
  const input = surface().querySelector('.harness-input');
  ok(!!input, 'composer input exists');
  input.value = value;
  input.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
}

(async () => {
  const file = makeFile('n1', '课程/第一课.md', { mtime: 1200 });
  const handle = createRuntime({
    contents: { n1: '# 第一课\n\n- [ ] 写作业\n\n今天学了矩阵。' }
  });
  const { runtime, host } = handle;
  const dom = handle.installDom();
  try {
    const boot = await handle.boot(bootPayload(file));
    eq(boot.ok, true, 'boot succeeds');
    eq(boot.warnings, [], 'manifest is accepted without warnings');
    eq(runtime.__inspect().commands.sort(), ['harness-new-session', 'harness-open', 'harness-organize-active'],
      'three commands registered');
    const views = host.calls.filter((call) => call.method === 'views.register');
    eq(views.length, 1, 'one view declared');
    eq(views[0].params.id, 'harness', 'view id');
    ok(storedSession(host), 'session persisted during activation');
    console.log('PASS Harness boots, declares its view and registers commands');

    // 1. Native view is rendered inside the runtime surface.
    const present = await runtime.present();
    eq(present.ok, true, 'present succeeds');
    const root = surface();
    ok(root, 'plugin surface exists');
    eq(root.children.length, 1, 'one view mounted');
    ok(root.children[0].classList.contains('harness-root'), 'view root class');
    ok(dom.body.textContent.includes('Harness'), 'header title rendered');
    ok(dom.body.textContent.includes('在下面输入问题'), 'empty state rendered');
    console.log('PASS ctx.views + runtime.present mount the chat surface');

    // 2. One full tool turn.
    host.state.aiReplies.push(
      {
        text: '我先读一下这篇笔记。',
        reasoning: '需要先读原文',
        toolCalls: [{ id: 'call-1', name: 'read_note', arguments: '{"path":"课程/第一课.md"}' }],
        finishReason: 'tool_calls',
        model: 'fake-model',
        usage: { inputTokens: 10, outputTokens: 5 }
      },
      {
        text: '摘要：这是一篇矩阵笔记。\n\n行动项：\n- [ ] 写作业',
        reasoning: '',
        toolCalls: [],
        finishReason: 'stop',
        model: 'fake-model',
        usage: { inputTokens: 20, outputTokens: 8 }
      }
    );
    sendText('帮我整理这篇笔记');
    await waitFor(() => host.state.aiCalls.length >= 2, 'two model calls');
    await waitFor(() => dom.body.textContent.includes('摘要：这是一篇矩阵笔记'), 'assistant answer');

    const secondCall = host.state.aiCalls[1];
    ok(Array.isArray(secondCall.messages), 'second call carries history');
    const toolMessage = secondCall.messages[secondCall.messages.length - 1];
    eq(toolMessage.role, 'tool', 'tool result appended');
    eq(toolMessage.toolCallId, 'call-1', 'tool result correlates');
    ok(toolMessage.content.includes('今天学了矩阵'), 'tool actually read the note');
    eq(toolMessage.isError, false, 'tool succeeded');
    ok(dom.body.textContent.includes('read_note'), 'tool row rendered');
    ok(dom.body.textContent.includes('写作业'), 'final answer rendered');

    const stored = storedSession(host);
    ok(stored.messages.some((message) => message.role === 'assistant' && message.content.includes('摘要')),
      'assistant answer persisted');
    ok(stored.messages.some((message) => message.role === 'tool' && message.toolName === 'read_note'),
      'tool message persisted');
    console.log('PASS a model turn executes tools, feeds results back and persists the transcript');

    // 3. A tool failure is reported to the model and the user, not swallowed.
    host.state.aiReplies.push(
      {
        text: '',
        toolCalls: [{ id: 'call-2', name: 'read_note', arguments: '{"path":"不存在.md"}' }],
        finishReason: 'tool_calls',
        model: 'fake-model',
        usage: { inputTokens: 1, outputTokens: 1 }
      },
      { text: '这篇笔记不存在。', toolCalls: [], finishReason: 'stop', model: 'fake-model',
        usage: { inputTokens: 1, outputTokens: 1 } }
    );
    sendText('读一下不存在.md');
    await waitFor(() => host.state.aiCalls.length >= 4, 'failure turn calls');
    await waitFor(() => dom.body.textContent.includes('这篇笔记不存在'), 'failure answer');
    const failureSession = storedSession(host);
    const failedTool = failureSession.messages.filter((message) => message.role === 'tool').pop();
    eq(failedTool.isError, true, 'tool failure flagged');
    ok(failedTool.content.includes('E_') || failedTool.content.includes('不存在'), 'tool failure text');
    console.log('PASS tool errors are surfaced instead of fabricated success');

    // 4. A model transport failure is visible in the composer area.
    host.state.aiReplies.push({
      error: { code: 'E_MODEL_UNAVAILABLE', message: '尚未绑定模型服务' }
    });
    sendText('再说一次');
    await waitFor(() => dom.body.textContent.includes('E_MODEL_UNAVAILABLE'), 'model error shown');
    ok(dom.body.querySelector('.harness-error'), 'error element rendered');
    console.log('PASS model failures are shown as an explicit error');

    // 5. Commands: open publishes a view request; new session clears the transcript.
    runtime.runCommand(`${PLUGIN_ID}:harness-open`);
    await waitFor(() => host.state.openedViews.includes('harness'), 'views.open call');
    eq(host.state.openedViews.filter((id) => id === 'harness').length >= 1, true, 'open recorded');

    runtime.runCommand(`${PLUGIN_ID}:harness-new-session`);
    await waitFor(() => {
      const current = storedSession(host);
      return current && current.messages.filter((message) => message.role !== 'system').length === 0;
    }, 'session reset');
    await waitFor(() => dom.body.textContent.includes('在下面输入问题'), 'empty state');
    ok(dom.body.textContent.includes('在下面输入问题'), 'empty state returned');
    console.log('PASS commands open the view and reset the session');

    // 6. Disabling releases the declaration; re-enabling registers it again.
    await runtime.unload();
    eq(host.calls.filter((call) => call.method === 'views.unregister').length >= 1, true,
      'unload unregisters views');
    console.log('PASS unload releases view declarations');
  } finally {
    await runtime.unload();
    handle.removeDom();
  }

  // 7. A host-refused view declaration must not stay presentable.
  const denied = createRuntime({
    host: {
      responder: (request) => request.method === 'views.register'
        ? { error: { code: 'E_PERMISSION_DENIED', message: '插件未获得能力 ui.views' } }
        : null
    }
  });
  denied.installDom();
  try {
    const source = `const { definePlugin } = require('@lexinote/sdk');
module.exports = definePlugin({
  async activate(ctx) {
    ctx.views.register({ id: 'v', title: 'V', render(container) { container.textContent = 'x'; } });
  },
  async deactivate() {}
});`;
    const deniedBoot = await denied.boot({ sourceCode: source, capabilities: ['ui.views'] });
    eq(deniedBoot.ok, true, 'activation itself does not throw');
    await delay(50);
    const refused = await denied.runtime.present();
    eq(refused.ok, false, 'present refuses a view the host rejected');
    ok(String(refused.error).includes('注册视图') || String(refused.error).includes('E_UNSUPPORTED_API'),
      'the refusal is explicit');
    console.log('PASS a host-refused view is removed from the runtime registry');
  } finally {
    await denied.runtime.unload();
    denied.removeDom();
  }

  console.log(`\nplugin-harness-regression: ${assertions} assertions passed`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
