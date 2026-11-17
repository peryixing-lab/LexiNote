'use strict';

// Full Harness runtime + DOM + ArkTS dispatcher verification for:
// 1. Direct chat without forced file/scope selection (no blocking scope bar, no file attachment bloat)
// 2. Full software capability invocation: direct note creation/editing, mind maps, canvases, and app settings
// 3. Verified note citations & clickable navigation
// 4. Direct write execution with one-click Undo card
// 5. Host-controlled capability enforcement (including ArkTS events.on gating)

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRuntime, makeFile } = require('./lib/js-runtime-harness.cjs');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const ROOT = path.resolve(__dirname, '../..');
const HARNESS_DIR = process.env.LEXINOTE_HARNESS_DIR || path.resolve(ROOT, '../lexinote-Harness');
const DIST_SOURCE = fs.readFileSync(path.join(HARNESS_DIR, 'dist/main.js'), 'utf8');
const MANIFEST = JSON.parse(fs.readFileSync(path.join(HARNESS_DIR, 'manifest.json'), 'utf8'));

let assertions = 0;
const ok = (v, m) => { assertions += 1; assert.ok(v, m); };
const eq = (a, b, m) => { assertions += 1; assert.deepEqual(a, b, m); };

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(predicate, label, timeoutMs = 2500) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const value = predicate();
      if (value) { return value; }
    } catch (_error) {
      // Wait for next microtask/timer tick.
    }
    await delay(15);
  }
  throw new Error(`timeout waiting for: ${label}`);
}

function surface() {
  return document.getElementById('plugin-surface');
}

function clickButtonByText(root, label) {
  const btns = Array.from(root.querySelectorAll('button'));
  const target = btns.find((b) => String(b.textContent || '').trim() === label || String(b.textContent || '').includes(label));
  ok(Boolean(target), `button "${label}" exists`);
  target.dispatchEvent({ type: 'click', preventDefault() {} });
  return target;
}

function bootPayload({ files, activeFile, editor, capabilities, vaultId }) {
  return {
    type: 'boot',
    protocol: 1,
    pluginId: MANIFEST.id,
    kind: 'lexinote',
    token: 'token-harness-e2e',
    runtimeVersion: '1',
    capabilities: capabilities || MANIFEST.capabilities.slice(),
    vaultId: vaultId || 'vault-e2e',
    manifestJson: JSON.stringify(MANIFEST),
    filesJson: JSON.stringify(files || []),
    activeFileJson: JSON.stringify(activeFile || null),
    editorJson: JSON.stringify(editor || null),
    settingsJson: 'null',
    dataJson: '{}',
    sourceCode: DIST_SOURCE,
    sourceName: 'main.js',
    stylesCss: '',
    warnings: []
  };
}

async function runHarnessDomE2E() {
  const noteA = '# 课程笔记\n\n第一段概述。\n第二段待润色文本\n第三段总结。';
  const noteB = '# 阅读摘录\n\n- [ ] 完成习题';
  const noteC = '# 实验记录\n\n旧实验参数 42';
  const fA = makeFile('nA', '学习/课程笔记.md', { mtime: 3000 });
  const fB = makeFile('nB', '摘录/阅读摘录.md', { mtime: 2000 });
  const fC = makeFile('nC', '实验/实验记录.md', { mtime: 1000 });

  const selFrom = noteA.indexOf('第二段待润色文本');
  const selTo = selFrom + '第二段待润色文本'.length;
  const handle = createRuntime({
    contents: { nA: noteA, nB: noteB, nC: noteC }
  });
  const { runtime, host } = handle;
  const dom = handle.installDom();
  try {
    const boot = await handle.boot(bootPayload({
      files: [fA, fB, fC],
      activeFile: null,
      editor: {
        noteId: fA.id,
        fileId: fA.id,
        content: noteA,
        revision: 1,
        dirty: false,
        readOnly: false,
        selection: { from: selFrom, to: selTo }
      }
    }));
    eq(boot.ok, true, 'Harness boots cleanly even without an activeFile selected');
    const present = await runtime.present('harness');
    eq(present.ok, true, 'Harness view mounts cleanly');

    // Verify NO forced scope bar is rendered above composer input
    eq(surface().querySelector('.harness-scope-bar'), null, 'no forced scope bar in default composer');

    // 1. User chats directly without selecting any file -> AI calls replace_selection, create_mindmap, update_app_settings
    host.state.aiReplies.push({
      text: '',
      reasoning: '',
      toolCalls: [
        { id: 'call_sel_1', name: 'replace_selection', arguments: JSON.stringify({ content: '第二段已清晰改写并补充结论', reason: '提升可读性' }) },
        { id: 'call_map_1', name: 'create_mindmap', arguments: JSON.stringify({ title: '课程知识导图', layoutKind: 'both', markdown: '# 课程核心\n## 第一章\n## 第二章' }) },
        { id: 'call_set_1', name: 'update_app_settings', arguments: JSON.stringify({ theme: 'dark', fontSize: 19 }) }
      ]
    });
    host.state.aiReplies.push({
      text: '已直接改写 [课程笔记](学习/课程笔记.md#L4) 的选中内容，生成了《课程知识导图》，并将软件切换为深色模式（19px 字号）。',
      reasoning: '',
      toolCalls: []
    });

    const input = surface().querySelector('.harness-input');
    input.value = '润色选中文字，生成课程知识导图，并切换到深色模式';
    input.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });

    await waitFor(() => surface().querySelector('.harness-diff-card'), 'applied change card rendered');

    // 1a. User message sent cleanly as plain prompt (NOT stuffed with raw file attachments)
    const firstAiReqUser = host.state.aiCalls[0].messages.find((m) => m.role === 'user').content;
    eq(firstAiReqUser, '润色选中文字，生成课程知识导图，并切换到深色模式', 'user message is sent cleanly without forced file stuffing');

    // 1b. Editor selection was replaced directly & immediately!
    eq(host.state.editor.content, '# 课程笔记\n\n第一段概述。\n第二段已清晰改写并补充结论\n第三段总结。', 'replace_selection directly updates editor');

    // 1c. Mind map was created and opened directly!
    eq(host.state.mindmaps.length, 1, 'mindmap created via tool');
    eq(host.state.mindmaps[0].title, '课程知识导图', 'mindmap title matches');

    // 1d. App settings were updated directly!
    eq(host.state.appSettings.theme, 'dark', 'app theme updated to dark');
    eq(host.state.appSettings.appearance.fontSize, 19, 'app fontSize updated to 19');

    // 1e. Verified citation pill click -> calls workspace.openFile
    const citePill = await waitFor(() => surface().querySelector('.harness-cite-pill'), 'citation pill rendered');
    ok(citePill.textContent.includes('课程笔记'), 'citation shows note title');
    ok(citePill.textContent.includes('#L4'), 'citation shows line fragment #L4');
    citePill.dispatchEvent({ type: 'click', preventDefault() {} });
    await waitFor(() => host.calls.some((c) => c.method === 'workspace.openFile' && c.params.fileId === 'nA'), 'citation click opens target note');

    // 1f. Applied change card supports one-click Undo to revert editor content!
    clickButtonByText(surface().querySelector('.harness-diff-card'), '撤销本次写入');
    await waitFor(() => surface().querySelectorAll('.harness-diff-badge').some((n) => n.classList.contains('undone')), 'change undone');
    eq(host.state.editor.content, noteA, 'undo restores exact pre-edit content');

    // 2. Direct file creation, note update, and canvas creation in second turn
    host.state.aiReplies.push({
      text: '',
      reasoning: '',
      toolCalls: [
        { id: 'call_new_note', name: 'create_note', arguments: JSON.stringify({ path: '总结/新笔记.md', content: '# 新笔记\n直接创建成功' }) },
        { id: 'call_upd', name: 'update_note', arguments: JSON.stringify({ path: '实验/实验记录.md', find: '42', replace: '99' }) },
        { id: 'call_canvas', name: 'create_canvas', arguments: JSON.stringify({ title: '实验流程白板', cards: [{ id: 'c1', title: '步骤一', body: '准备数据' }] }) }
      ]
    });
    host.state.aiReplies.push({
      text: '已创建 [新笔记](总结/新笔记.md)、更新 [实验记录](实验/实验记录.md) 并生成自由白板。',
      reasoning: '',
      toolCalls: []
    });

    const input2 = surface().querySelector('.harness-input');
    input2.value = '创建新笔记、更新实验参数为99并新建实验流程白板';
    input2.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });

    await waitFor(() => host.state.canvases.length === 1, 'canvas created');
    eq(host.state.contents.get('nC'), '# 实验记录\n\n旧实验参数 99', 'update_note directly mutates note C');
    const createdFile = host.state.files.find((f) => f.path === '总结/新笔记.md');
    ok(Boolean(createdFile), 'create_note directly creates file in vault');
    eq(host.state.contents.get(createdFile.id), '# 新笔记\n直接创建成功', 'created file content matches');
    eq(host.state.canvases[0].title, '实验流程白板', 'canvas title matches');
    console.log('PASS Harness DOM E2E: direct chat without forced file selection, direct note/mindmap/canvas/settings tools & undo');
  } finally {
    await runtime.unload().catch(() => {});
    handle.removeDom();
  }
}

async function runHostCapabilityBoundaryChecks() {
  // Verify restricted runtime capabilities surface E_PERMISSION_DENIED inside Harness UI & tools
  const f1 = makeFile('n1', '只读笔记.md', { mtime: 1000 });
  const restrictedCaps = MANIFEST.capabilities.filter((c) => c !== 'editor.read' && c !== 'vault.write' && c !== 'editor.write');
  const handle = createRuntime({
    contents: { n1: '# 只读\n正文' }
  });
  const { runtime, host } = handle;
  const dom = handle.installDom();
  try {
    await handle.boot(bootPayload({
      files: [f1],
      activeFile: f1,
      capabilities: restrictedCaps
    }));
    await runtime.present('harness');

    // Calling update_note without vault.write must fail with E_PERMISSION_DENIED and leave note untouched
    host.state.aiReplies.push({
      text: '',
      reasoning: '',
      toolCalls: [{ id: 'c_denied', name: 'update_note', arguments: JSON.stringify({ path: '只读笔记.md', content: 'tampered' }) }]
    });
    host.state.aiReplies.push({ text: '宿主拒绝写入（E_PERMISSION_DENIED）。', reasoning: '', toolCalls: [] });
    const inp = surface().querySelector('.harness-input');
    inp.value = '尝试修改';
    inp.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await waitFor(() => surface().querySelectorAll('.harness-tool').some((n) => n.classList.contains('error') && n.textContent.includes('E_PERMISSION_DENIED')), 'write denied surfaces E_PERMISSION_DENIED');
    eq(host.state.contents.get('n1'), '# 只读\n正文', 'note remains unmodified when vault.write denied');
  } finally {
    await runtime.unload().catch(() => {});
    handle.removeDom();
  }

  // Real ArkTS PluginRpcDispatcher event capability enforcement check
  const box = createSandbox();
  box.reset();
  const S = box.prepareStorage();
  await S.createVault(box.contexts, 'EventsTest', '');
  const { PluginCapability } = box.load('plugin/model/PluginModels');
  const { PluginRpcMethod, PluginRpcRequest } = box.load('plugin/model/PluginContracts');
  const { PluginRpcDispatcher, PluginSession } = box.load('plugin/runtime/PluginRpcDispatcher');
  const { PluginPermissionService } = box.load('plugin/core/PluginPermissionService');

  PluginRpcDispatcher.setContext(box.contexts);
  const pid = 'example.events.test';
  await PluginPermissionService.clearAll(pid);
  await PluginPermissionService.grant(pid, PluginCapability.VAULT_READ, [PluginCapability.VAULT_READ, PluginCapability.EDITOR_READ]);
  await PluginPermissionService.grant(pid, PluginCapability.EDITOR_READ, [PluginCapability.VAULT_READ, PluginCapability.EDITOR_READ]);

  const sess = new PluginSession();
  sess.pluginId = pid;
  sess.kind = 'lexinote';
  sess.capabilities = [PluginCapability.VAULT_READ, PluginCapability.EDITOR_READ];
  sess.vaultScopes = [];

  function req(id, method, params) {
    const item = new PluginRpcRequest();
    item.id = id;
    item.pluginId = pid;
    item.method = method;
    item.params = JSON.stringify(params);
    return item;
  }

  // Subscribing editor.changed allowed with editor.read; workspace.active-file-changed refused without workspace.views
  const okSubRaw = await PluginRpcDispatcher.dispatch(sess, req('e1', PluginRpcMethod.EVENTS_ON, { event: 'editor.changed' }));
  const okSub = JSON.parse(okSubRaw);
  ok(Boolean(okSub && okSub.subscriptionId), 'events.on(editor.changed) succeeds when editor.read granted');

  await assert.rejects(
    PluginRpcDispatcher.dispatch(sess, req('e2', PluginRpcMethod.EVENTS_ON, { event: 'workspace.active-file-changed' })),
    (err) => String(err.message).startsWith('E_PERMISSION_DENIED'),
    'events.on(workspace.active-file-changed) refuses without workspace.views'
  );
  assertions += 1;

  // Revoking vault.read immediately blocks vault.modified subscription via live PluginPermissionService check
  await PluginPermissionService.revoke(pid, PluginCapability.VAULT_READ);
  await assert.rejects(
    PluginRpcDispatcher.dispatch(sess, req('e3', PluginRpcMethod.EVENTS_ON, { event: 'vault.modified' })),
    (err) => String(err.message).startsWith('E_PERMISSION_DENIED'),
    'events.on(vault.modified) refuses after vault.read revoked'
  );
  assertions += 1;
  console.log('PASS Host capability boundaries: restricted plugin & ArkTS events.on gating enforced');
}

(async () => {
  await runHarnessDomE2E();
  await runHostCapabilityBoundaryChecks();
  console.log(`plugin-harness-context-diff-regression: ${assertions} assertions passed`);
})();
