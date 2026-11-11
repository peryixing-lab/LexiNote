'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRuntime } = require('./lib/js-runtime-harness.cjs');
const root = path.resolve(__dirname, '../..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'plugins/harness/manifest.json'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'plugins/harness/dist/main.js'), 'utf8');
const tick = () => new Promise((resolve) => setTimeout(resolve, 10));
async function until(predicate) {
  for (let n = 0; n < 200; n++) { if (predicate()) return; await tick(); }
  throw new Error('Timed out waiting for UI state');
}
let checks = 0;
const eq = (a, b) => { checks++; assert.deepEqual(a, b); };
const ok = (value) => { checks++; assert.ok(value); };

async function run(mode) {
  let delayStatus = false;
  let failSave = false;
  let delayBalance = false;
  let delayChat = false;
  let failModels = false;
  const handle = createRuntime({ mode, host: { responder(request) {
    if (request.method === 'ai.status' && delayStatus) { return { manual: true }; }
    if (request.method === 'ai.configure' && failSave) {
      return { error: { code: 'E_INVALID_ARGUMENT', message: '测试保存失败' } };
    }
    if (request.method === 'ai.balance' && delayBalance) { return { manual: true }; }
    if (request.method === 'ai.chat' && delayChat) { return { manual: true }; }
    if (request.method === 'ai.models' && failModels) {
      return { error: { code: 'E_MODEL_UNAVAILABLE', message: '测试模型列表获取失败' } };
    }
    return null;
  } } });
  const { host, runtime } = handle;
  handle.installDom();
  const surface = () => document.getElementById('plugin-surface');
  const click = (label) => {
    const node = surface().querySelectorAll('button').find((item) => item.textContent === label);
    assert.ok(node, `button ${label} exists`);
    node.dispatchEvent({ type: 'click' });
  };
  const inputs = () => surface().querySelector('.harness-config').querySelectorAll('input');
  const field = (label) => inputs().find((node) => node.getAttribute('aria-label') === label);
  const set = (node, value) => { node.value = value; node.dispatchEvent({ type: 'input' }); };
  try {
    eq((await handle.boot({ pluginId: manifest.id, manifestJson: JSON.stringify(manifest),
      capabilities: manifest.capabilities, sourceCode: source, kind: 'lexinote' })).ok, true);
    eq((await runtime.present()).ok, true);
    await until(() => surface().textContent.includes('fake-model'));
    delayStatus = true;
    click('模型');
    ok(surface().querySelector('.harness-models'));
    eq(surface().querySelector('.harness-config'), null);
    eq(surface().querySelector('.harness-models').querySelectorAll('input').length, 0);
    eq(surface().querySelector('.harness-composer').querySelectorAll('button')
      .some((node) => node.textContent === '获取模型'), false);
    eq(host.calls.filter((call) => call.method === 'ai.models').length, 0);
    click('配置服务');
    ok(surface().querySelector('.harness-config'));
    click('取消');
    ok(surface().querySelector('.harness-models'));
    eq(surface().querySelector('.harness-config'), null);
    click('配置服务');
    const urlField = field('Base URL');
    const longBase = `https://127.0.0.1:8080/${'path123/'.repeat(100)}v1`;
    set(urlField, longBase);
    urlField.focus();
    urlField.selectionStart = 222;
    urlField.selectionEnd = 222;
    set(field('模型名称'), 'custom-model');
    set(field('API Key'), 'private-key');
    set(field('常用模型'), 'custom-model, other-model');
    await until(() => host.pending.some((item) => item.method === 'ai.status'));
    host.respond(host.pending.find((item) => item.method === 'ai.status'), {
      configured: true, provider: 'openai-compatible', baseUrl: 'https://old.test/v1', model: 'fake-model'
    });
    delayStatus = false;
    await tick();
    eq(field('Base URL'), urlField);
    eq(document.activeElement, urlField);
    eq(urlField.selectionStart, 222);
    eq(urlField.value, longBase);
    eq(urlField.maxLength, 8192);
    eq(urlField.type, 'url');
    eq(urlField.inputMode, 'url');
    eq(urlField.getAttribute('autocapitalize'), 'off');
    let blocked = false;
    for (const digit of '0123456789') {
      urlField.dispatchEvent({ type: 'keydown', key: digit, preventDefault() { blocked = true; } });
      urlField.dispatchEvent({ type: 'beforeinput', data: digit, inputType: 'insertText', preventDefault() { blocked = true; } });
    }
    eq(blocked, false);
    set(field('服务商名称'), '我的中转服务');
    eq(field('API Key').value, 'private-key');
    failSave = true;
    click('保存');
    await until(() => surface().textContent.includes('测试保存失败'));
    eq(field('Base URL').value, longBase);
    eq(field('模型名称').value, 'custom-model');
    eq(field('API Key').value, 'private-key');
    failSave = false;
    click('保存');
    await until(() => !surface().querySelector('.harness-config'));
    ok(surface().querySelector('.harness-models'));
    const saved = host.calls.filter((call) => call.method === 'ai.configure').at(-1).params;
    eq(saved.baseUrl, longBase);
    eq(saved.apiKey, 'private-key');
    ok(!host.state.storage.get('harness.models.v1').includes('private-key'));
    ok(!host.state.storage.get('harness.services.v1').includes('private-key'));
    eq(surface().querySelector('.harness-provider-name').textContent, '我的中转服务');
    ok(surface().querySelector('.harness-models-service').textContent.includes('我的中转服务'));
    eq(surface().querySelector('.harness-composer').querySelectorAll('select').length, 0);
    eq(surface().querySelectorAll('.harness-model-option').map((item) => item.getAttribute('aria-label')),
      ['切换到 custom-model', '切换到 other-model']);
    click('关闭');
    eq(surface().querySelector('.harness-overlay'), null);
    console.log(`PASS ${mode}: long URL input survives delayed status, caret/focus preserved, failed save retains draft`);

    const composer = surface().querySelector('.harness-input');
    composer.value = '未发送的草稿';
    composer.focus();
    composer.selectionStart = 3;
    click('模型');
    click('获取模型');
    await until(() => surface().querySelector('.harness-models-list').textContent.includes('fake-reasoner'));
    ok(surface().querySelector('.harness-models').textContent.includes('fake-reasoner'));
    eq(surface().querySelector('.harness-input'), composer);
    eq(document.activeElement, composer);
    eq(composer.selectionStart, 3);
    eq(composer.value, '未发送的草稿');
    failModels = true;
    click('获取模型');
    await until(() => surface().querySelector('.harness-models').textContent.includes('测试模型列表获取失败'));
    ok(surface().querySelector('.harness-models').textContent.includes('fake-reasoner'));
    eq(surface().querySelector('.harness-toolbar-error').textContent, '');
    failModels = false;
    const modelOption = surface().querySelectorAll('.harness-model-option')
      .find((node) => node.getAttribute('aria-label') === '切换到 fake-reasoner');
    modelOption.dispatchEvent({ type: 'click' });
    await until(() => surface().querySelector('.harness-sub').textContent.includes('fake-reasoner'));
    eq(host.calls.filter((call) => call.method === 'ai.configure').at(-1).params, { model: 'fake-reasoner' });
    eq(surface().querySelectorAll('.harness-model-option')
      .find((node) => node.getAttribute('aria-label') === '切换到 fake-reasoner').getAttribute('aria-pressed'), 'true');
    ok(!surface().querySelector('.harness-models').textContent.includes('测试模型列表获取失败'));
    click('关闭');
    eq(surface().querySelectorAll('button').some((node) => node.textContent === '获取模型'), false);
    eq(surface().querySelector('.harness-current-model').textContent, 'fake-reasoner');
    click('余额 / 配额');
    await until(() => surface().textContent.includes('CNY 12.3400'));
    eq(surface().querySelector('.harness-input'), composer);
    console.log(`PASS ${mode}: model manager navigation, in-page catalog/errors/switching, quota query and composer stability`);

    host.state.aiReplies.push({ text: '**低风险清理**\n\n- [ ] 把 `file://` 链接改为行内代码\n- [x] 已完成\n\n' +
      '> 引用\n\n```js\nconst a = "<script>";\n```\n\n|项目|状态|\n|---|---|\n|Markdown|正常|\n\n' +
      '<img src=x onerror=alert(1)>\n\n[危险](javascript:alert(1))',
      toolCalls: [], model: 'fake-reasoner', usage: { inputTokens: 1, outputTokens: 1 } });
    composer.value = '测试 Markdown';
    composer.dispatchEvent({ type: 'keydown', key: 'Enter', isComposing: true });
    eq(host.state.aiCalls.length, 0);
    composer.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await until(() => surface().querySelector('.harness-markdown'));
    const markdown = surface().querySelector('.harness-markdown');
    eq(markdown.querySelector('strong').textContent, '低风险清理');
    eq(markdown.querySelectorAll('input').map((item) => [item.type, item.checked, item.disabled]),
      [['checkbox', false, true], ['checkbox', true, true]]);
    eq(markdown.querySelector('code').textContent, 'file://');
    ok(markdown.querySelector('pre').textContent.includes('const a = "<script>";'));
    ok(markdown.querySelector('table'));
    ok(markdown.querySelector('blockquote'));
    eq(markdown.querySelector('img'), null);
    eq(markdown.querySelector('script'), null);
    eq(markdown.querySelectorAll('a').some((node) => /javascript:/i.test(node.getAttribute('href') || '')), false);
    console.log(`PASS ${mode}: Markdown emphasis, code, tasks, quote, table, HTML/script safety and IME guard`);

    await until(() => surface().querySelectorAll('button').some((node) => node.textContent === '发送'));
    delayBalance = true;
    click('刷新');
    await until(() => host.pending.some((item) => item.method === 'ai.balance'));
    const oldBalance = host.pending.filter((item) => item.method === 'ai.balance').at(-1);
    click('模型');
    const nextModel = surface().querySelectorAll('.harness-model-option')
      .find((node) => node.getAttribute('aria-label') === '切换到 fake-model');
    nextModel.dispatchEvent({ type: 'click' });
    await until(() => host.pending.filter((item) => item.method === 'ai.balance').length === 2);
    const newBalance = host.pending.filter((item) => item.method === 'ai.balance').at(-1);
    host.respond(newBalance, { supported: true, provider: 'New Provider', updatedAt: Date.now(),
      windows: [{ label: '余额', unit: 'USD', remainingValue: 9 }] });
    await until(() => surface().textContent.includes('USD 9.0000'));
    host.respond(oldBalance, { supported: true, provider: 'Old Provider', updatedAt: Date.now(),
      windows: [{ label: '余额', unit: 'CNY', remainingValue: 999 }] });
    await tick();
    ok(surface().textContent.includes('USD 9.0000'));
    ok(!surface().textContent.includes('Old Provider'));

    click('关闭');
    delayChat = true;
    composer.value = '正在执行';
    composer.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await until(() => host.pending.some((item) => item.method === 'ai.chat'));
    eq(surface().querySelector('.harness-model-trigger').disabled, true);
    const count = host.calls.filter((call) => call.method === 'ai.configure').length;
    surface().querySelector('.harness-model-trigger').dispatchEvent({ type: 'click' });
    eq(surface().querySelector('.harness-models'), null);
    await tick();
    eq(host.calls.filter((call) => call.method === 'ai.configure').length, count);
    host.respond(host.pending.find((item) => item.method === 'ai.chat'), { text: '完成', toolCalls: [] });
    await until(() => surface().textContent.includes('完成'));
    await until(() => surface().querySelectorAll('button').some((node) => node.textContent === '发送'));
    console.log(`PASS ${mode}: stale balance ignored and active turn prevents model changes`);
  } finally { await runtime.unload(); handle.removeDom(); }
}

(async () => {
  await run('source');
  await run('built');
  console.log(`plugin-harness-ui-regression: ${checks} checks passed`);
})().catch((error) => { console.error(error); process.exit(1); });
