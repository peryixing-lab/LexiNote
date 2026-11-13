'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRuntime } = require('./lib/js-runtime-harness.cjs');
const root = path.resolve(__dirname, '../..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'plugins/harness/manifest.json'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'plugins/harness/dist/main.js'), 'utf8');
const key = 'harness.session.v1';
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
async function until(predicate) {
  for (let count = 0; count < 300; count++) { if (predicate()) { return; } await tick(); }
  throw Error('Timed out waiting for conversation history');
}
async function run(mode) {
  let failSave = false;
  let holdChat = false;
  const handle = createRuntime({ mode, host: { responder(request) {
    if (failSave && request.method === 'storage.set' && request.params.key === key) {
      return { error: { code: 'E_IO', message: '测试对话保存失败' } };
    }
    if (holdChat && request.method === 'ai.chat') { return { manual: true }; }
    return null;
  } } });
  const { host, runtime } = handle;
  handle.installDom();
  const surface = () => document.getElementById('plugin-surface');
  const button = label => surface().querySelectorAll('button').find(node => node.textContent === label);
  const click = label => { const node = button(label); assert.ok(node, label + ' exists'); node.dispatchEvent({ type: 'click' }); };
  const clickLabel = label => {
    const node = surface().querySelectorAll('button').find(item => item.getAttribute('aria-label') === label);
    assert.ok(node, label + ' exists'); node.dispatchEvent({ type: 'click' });
  };
  const rows = () => surface().querySelectorAll('.harness-history-row');
  const input = () => surface().querySelector('.harness-input');
  const draft = value => { input().value = value; input().dispatchEvent({ type: 'input' }); };
  const saved = () => JSON.parse(host.state.storage.get(key));
  const legacy = { id: 'legacy-chat', title: '旧主题', createdAt: 1000, updatedAt: 2000, todos: [], draft: '旧草稿',
    messages: [{ role: 'user', content: '旧主题的问题' }, { role: 'assistant', content: '旧主题的回答' }] };
  let restartData;
  try {
    assert.equal((await handle.boot({ pluginId: manifest.id, manifestJson: JSON.stringify(manifest),
      capabilities: manifest.capabilities, sourceCode: source, kind: 'lexinote', dataJson: JSON.stringify({ [key]: legacy }) })).ok, true);
    assert.equal((await runtime.present()).ok, true);
    await until(() => surface().textContent.includes('fake-model'));
    assert.equal(input().value, '旧草稿');
    assert.ok(surface().textContent.includes('旧主题的回答'));
    draft('旧主题未发送的草稿');
    await until(() => saved().draft === '旧主题未发送的草稿');
    click('新会话');
    await until(() => input().value === '' && saved().id !== legacy.id);
    assert.ok(saved().history.some(entry => entry.id === legacy.id));
    assert.ok(!surface().textContent.includes('旧主题的回答'));
    draft('另一段草稿');
    click('历史');
    await until(() => rows().length === 2 && button('新建对话') && !button('新建对话').disabled);
    const search = surface().querySelector('.harness-history-search');
    search.value = '旧主题'; search.focus(); search.selectionStart = 2;
    search.dispatchEvent({ type: 'input' });
    assert.equal(rows().length, 1);
    assert.equal(surface().querySelector('.harness-history-search'), search);
    assert.equal(document.activeElement, search);
    await tick();
    assert.equal(search.selectionStart, 2);
    clickLabel('打开对话 旧主题');
    await until(() => !surface().querySelector('.harness-history'));
    assert.equal(input().value, '旧主题未发送的草稿');
    assert.ok(surface().textContent.includes('旧主题的回答'));
    host.state.aiReplies.push({ text: '继续回答旧主题', toolCalls: [] });
    input().value = '继续提问';
    input().dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await until(() => surface().textContent.includes('继续回答旧主题') && button('发送'));
    const sent = host.state.aiCalls.at(-1).messages;
    assert.ok(sent.some(message => message.content === '旧主题的问题'));
    assert.ok(sent.some(message => message.content === '旧主题的回答'));
    assert.equal(sent.at(-1).content, '继续提问');
    assert.equal(saved().draft, '');

    const currentId = saved().id;
    failSave = true;
    click('新会话');
    await until(() => surface().textContent.includes('新建对话失败'));
    assert.equal(saved().id, currentId);
    assert.ok(surface().textContent.includes('继续回答旧主题'));
    failSave = false;
    click('历史');
    await until(() => rows().length === 2 && !button('新建对话').disabled);
    clickLabel('删除对话 新会话');
    click('取消删除');
    assert.equal(rows().length, 2);
    clickLabel('删除对话 新会话'); click('确认删除对话');
    await until(() => rows().length === 1 && !button('新建对话').disabled);
    assert.equal(saved().id, currentId);
    click('关闭');
    holdChat = true;
    input().value = '保持当前对话';
    input().dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await until(() => host.pending.some(request => request.method === 'ai.chat'));
    assert.equal(button('历史').disabled, true);
    button('历史').dispatchEvent({ type: 'click' });
    assert.equal(surface().querySelector('.harness-history'), null);
    host.respond(host.pending.find(request => request.method === 'ai.chat'), { text: '当前对话完成', toolCalls: [] });
    await until(() => surface().textContent.includes('当前对话完成') && button('发送'));
    holdChat = false;
    draft('重启后的草稿');
    // Unload immediately, before the debounce: deactivate must flush the draft.
    await runtime.unload();
    assert.equal(saved().draft, '重启后的草稿');
    restartData = Object.fromEntries(host.state.storage);
    assert.equal(host.invalid.length, 0);
    console.log(`PASS ${mode}: legacy history, draft autosave, new/resume/search, continuation context, failed-save protection, deletion and busy guard`);
  } finally { await runtime.unload(); handle.removeDom(); }

  const reloaded = createRuntime({ mode });
  reloaded.installDom();
  try {
    assert.equal((await reloaded.boot({ pluginId: manifest.id, manifestJson: JSON.stringify(manifest),
      capabilities: manifest.capabilities, sourceCode: source, kind: 'lexinote', dataJson: JSON.stringify(restartData) })).ok, true);
    assert.equal((await reloaded.runtime.present()).ok, true);
    await until(() => surface().textContent.includes('fake-model'));
    assert.equal(input().value, '重启后的草稿');
    assert.ok(surface().textContent.includes('继续回答旧主题'));
    click('历史');
    await until(() => rows().length === 1 && !button('新建对话').disabled);
    clickLabel('删除对话 旧主题'); click('确认删除对话');
    await until(() => rows().length === 0 && !button('新建对话').disabled);
    click('关闭');
    assert.equal(input().value, '');
    assert.ok(!surface().textContent.includes('继续回答旧主题'));
    assert.ok(surface().textContent.includes('在下面输入问题'));
    console.log(`PASS ${mode}: restart restores active transcript/draft, deleted history stays deleted, removing current conversation returns to an empty one`);
  } finally { await reloaded.runtime.unload(); reloaded.removeDom(); }
}
(async () => { await run('source'); await run('built'); })().catch(error => { console.error(error); process.exitCode = 1; });
