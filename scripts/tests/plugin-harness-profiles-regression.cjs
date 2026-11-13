'use strict';
// Standalone ZIP -> unmodified SDK -> original single-binding native service.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');
const { createRuntime } = require('./lib/js-runtime-harness.cjs');
const root = path.resolve(__dirname, '../..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'plugins/harness/manifest.json'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'plugins/harness/dist/main.js'), 'utf8');
const { STORAGE_KEY } = require('../../plugins/harness/src/profile-store');
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
async function until(predicate) {
  for (let n = 0; n < 300; n++) { if (predicate()) return; await tick(); }
  throw Error('Timed out waiting for multi-provider UI');
}

async function run(mode) {
  const box = createSandbox(); box.reset();
  const storage = box.prepareStorage();
  const { PluginAiService: ai } = box.load('plugin/ai/PluginAiService');
  await storage.setSetting('pluginAiConfig.v1', JSON.stringify({ provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', apiKey: 'secret-deepseek' }));
  ai.resetForTests();
  let handle;
  let holdBalances = false;
  const held = [];
  handle = createRuntime({ mode, host: { responder(request) {
    if (!request.method.startsWith('ai.')) { return null; }
    const method = request.method.slice(3);
    if (typeof ai[method] !== 'function') { return null; }
    const hold = holdBalances && method === 'balance';
    Promise.resolve().then(() => ai[method](JSON.stringify(request.params))).then(raw => {
      const answer = () => handle.host.respond(request, JSON.parse(raw));
      if (hold) { held.push(answer); } else { answer(); }
    }, error => handle.host.respond(request, null, {
      code: String(error.message).split(':')[0], message: error.message
    }));
    return { manual: true };
  } } });
  const { runtime, host } = handle;
  handle.installDom();
  const surface = () => document.getElementById('plugin-surface');
  const click = label => {
    const button = surface().querySelectorAll('button').find(node => node.textContent === label);
    assert.ok(button, label + ' exists'); button.dispatchEvent({ type: 'click' });
  };
  const clickLabel = label => {
    const button = surface().querySelectorAll('button').find(node => node.getAttribute('aria-label') === label);
    assert.ok(button, label + ' exists'); button.dispatchEvent({ type: 'click' });
  };
  const field = label => surface().querySelector('.harness-config').querySelectorAll('input')
    .find(node => node.getAttribute('aria-label') === label);
  const set = (label, value) => { const node = field(label); node.value = value; node.dispatchEvent({ type: 'input' }); };
  const rows = () => surface().querySelectorAll('.harness-service-row');
  const models = () => surface().querySelectorAll('.harness-model-option').map(node => node.getAttribute('aria-label'));
  const current = () => surface().querySelector('.harness-current-model').textContent;
  const respond = body => box.expectHttp({ status: 200, body: JSON.stringify(body) });
  try {
    assert.equal((await handle.boot({ pluginId: manifest.id, manifestJson: JSON.stringify(manifest),
      capabilities: manifest.capabilities, sourceCode: source, kind: 'lexinote' })).ok, true);
    assert.equal((await runtime.present()).ok, true);
    await until(() => host.calls.some(call => call.method === 'ai.status'));
    await tick();
    click('模型');
    await until(() => rows().length === 1);
    assert.ok(!surface().textContent.includes('需补填 Key'), 'migrated host binding already has a key');
    click('配置服务');
    set('API Key', 'secret-deepseek');
    click('保存');
    await until(() => !surface().querySelector('.harness-config'));
    click('添加服务商');
    assert.equal(field('API Key').value, '');
    assert.equal(field('Base URL').value, '');
    assert.equal(field('模型名称').value, '');
    set('服务商名称', 'Router 工作');
    set('Base URL', 'https://openrouter.ai/api/v1');
    set('模型名称', 'vendor/beta');
    set('常用模型', 'vendor/beta, vendor/other');
    click('保存并使用');
    assert.ok(surface().querySelector('.harness-settings-error').textContent.includes('API Key'));
    assert.equal(JSON.parse(host.state.storage.get(STORAGE_KEY)).profiles.length, 1);
    set('API Key', 'secret-router');
    click('保存并使用');
    await until(() => !surface().querySelector('.harness-config') && rows().length === 2);
    assert.equal(current(), 'vendor/beta');
    assert.equal(surface().querySelector('.harness-provider-name').textContent, 'Router 工作');
    const nonProfileStorage = () => [...host.state.storage].filter(([key]) => key !== STORAGE_KEY);
    assert.ok(!JSON.stringify(nonProfileStorage()).includes('secret-'));
    const storedProfiles = JSON.parse(host.state.storage.get(STORAGE_KEY)).profiles;
    assert.ok(!storedProfiles.some(profile => Object.prototype.hasOwnProperty.call(profile, 'apiKey')),
      'plugin storage never holds an API key');
    assert.ok([...box.state.prefs.entries()].some(([key, value]) =>
      key.startsWith('pluginAiSecret.v2.') && String(value).includes('secret-router')),
      'host secret slot holds the key');
    respond({ data: [{ id: 'vendor/beta' }, { id: 'vendor/router-only' }] });
    click('获取模型');
    await until(() => models().includes('切换到 vendor/router-only'));
    assert.equal(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer secret-router');
    clickLabel('使用服务商 DeepSeek');
    await until(() => current() === 'deepseek-chat');
    assert.ok(!models().includes('切换到 vendor/router-only'));
    respond({ data: [{ id: 'deepseek-chat' }, { id: 'deepseek-reasoner' }] });
    click('获取模型');
    await until(() => models().includes('切换到 deepseek-reasoner'));
    assert.equal(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer secret-deepseek');

    const routerRow = rows().find(row => row.textContent.includes('Router 工作'));
    routerRow.querySelectorAll('button').find(node => node.textContent === '编辑').dispatchEvent({ type: 'click' });
    assert.equal(field('模型名称').value, 'vendor/beta', 'inactive service form uses its own model');
    assert.equal(field('API Key').value, '');
    set('模型名称', 'vendor/edited');
    set('常用模型', 'vendor/edited, vendor/edited-only');
    click('保存');
    await until(() => !surface().querySelector('.harness-config'));
    assert.equal(current(), 'deepseek-chat', 'editing another service does not change the selected one');
    assert.ok(models().includes('切换到 deepseek-reasoner'));
    assert.ok(!models().includes('切换到 vendor/edited-only'));
    clickLabel('使用服务商 Router 工作');
    await until(() => current() === 'vendor/edited');
    assert.ok(models().includes('切换到 vendor/edited-only'));
    assert.ok(!models().includes('切换到 deepseek-reasoner'));
    console.log(`PASS ${mode}: migration, adding with a new key, service switching and inactive edits preserve separate model lists`);

    click('添加服务商');
    set('服务商名称', 'Router 备用');
    set('Base URL', 'https://openrouter.ai/api/v1');
    set('模型名称', 'vendor/spare');
    set('API Key', 'secret-spare');
    click('保存并使用');
    await until(() => !surface().querySelector('.harness-config') && rows().length === 3);
    clickLabel('使用服务商 Router 工作');
    await until(() => current() === 'vendor/edited');
    click('关闭');
    holdBalances = true;
    respond({ data: { total_credits: 100, total_usage: 1 } });
    click('余额 / 配额');
    await until(() => held.length === 1);
    assert.equal(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer secret-router');
    holdBalances = false;
    click('模型');
    respond({ data: { total_credits: 5, total_usage: 2 } });
    clickLabel('使用服务商 Router 备用');
    await until(() => surface().textContent.includes('USD 3.0000'));
    assert.equal(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer secret-spare');
    held.shift()(); await tick();
    assert.ok(surface().textContent.includes('USD 3.0000'));
    assert.ok(!surface().textContent.includes('USD 99.0000'));
    click('关闭'); click('余额 / 配额');
    respond({ choices: [{ message: { role: 'assistant', content: '备用账号对话正常' }, finish_reason: 'stop' }] });
    const composer = surface().querySelector('.harness-input');
    composer.value = '测试账号路由';
    composer.dispatchEvent({ type: 'keydown', key: 'Enter', shiftKey: false, isComposing: false });
    await until(() => surface().textContent.includes('备用账号对话正常'));
    assert.equal(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer secret-spare');
    assert.equal(JSON.parse(box.state.httpRequests.at(-1).options.extraData).model, 'vendor/spare');
    await until(() => surface().querySelectorAll('button').some(node => node.textContent === '发送'));
    click('模型');

    clickLabel('删除服务商 Router 备用');
    click('取消删除');
    assert.equal(rows().length, 3);
    clickLabel('删除服务商 Router 备用'); click('确认删除');
    await until(() => rows().length === 2);
    assert.equal(current(), 'deepseek-chat', 'deleting the active service selects a remaining service');
    clickLabel('删除服务商 DeepSeek'); click('确认删除');
    await until(() => rows().length === 1);
    assert.equal(current(), 'vendor/edited');
    clickLabel('删除服务商 Router 工作'); click('确认删除');
    await until(() => rows().length === 0);
    assert.equal(JSON.parse(await ai.status()).configured, false);
    click('添加服务商');
    assert.equal(field('API Key').value, '');
    click('取消');
    assert.ok(!JSON.stringify(nonProfileStorage()).includes('secret-'));
    assert.ok(!surface().textContent.includes('secret-'));
    assert.equal(host.calls.filter(call => call.method === 'ai.profiles').length, 0, 'no new host API is required');
    assert.equal(host.invalid.length, 0);
    console.log(`PASS ${mode}: same-address accounts, late balance isolation, explicit deletion and empty-state re-add work through the real native service`);
  } finally { await runtime.unload(); handle.removeDom(); }
}
async function runAvailability(mode) {
  let outcome = { error: { code: 'E_TIMEOUT', message: '测试本地配置读取失败' } };
  const handle = createRuntime({ mode, host: { responder(request) {
    if (request.method === 'ai.status') {
      return { result: { configured: false, profileId: '', name: '', provider: '', baseUrl: '',
        model: '', maxTokens: 0, temperature: 0, balanceProvider: '', needsApiKey: true } };
    }
    return request.method === 'storage.get' && request.params.key === STORAGE_KEY ? outcome : null;
  } } });
  const { runtime, host } = handle;
  handle.installDom();
  const surface = () => document.getElementById('plugin-surface');
  const click = label => {
    const node = surface().querySelectorAll('button').find(item => item.textContent === label);
    assert.ok(node, label + ' exists'); node.dispatchEvent({ type: 'click' });
  };
  try {
    assert.equal((await handle.boot({ pluginId: manifest.id, manifestJson: JSON.stringify(manifest),
      capabilities: manifest.capabilities, sourceCode: source, kind: 'lexinote' })).ok, true);
    assert.equal((await runtime.present()).ok, true);
    await until(() => surface().textContent.includes('测试本地配置读取失败'));
    click('模型');
    click('添加服务商');
    await until(() => surface().textContent.includes('重试读取配置'));
    assert.equal(surface().querySelector('.harness-config'), null);
    assert.equal(host.calls.filter(call => call.method === 'ai.configure').length, 0);

    outcome = { error: { code: 'E_TIMEOUT', message: '测试存储超时' } };
    click('重试读取配置');
    await until(() => surface().textContent.includes('测试存储超时'));
    assert.ok(!surface().textContent.includes('请更新知萤应用'));
    assert.ok(surface().textContent.includes('读取插件服务商配置失败'));

    outcome = { manual: true };
    click('重试读取配置');
    await until(() => host.pending.some(call => call.method === 'storage.get' && call.params.key === STORAGE_KEY));
    assert.ok(surface().textContent.includes('正在检查…'));
    click('关闭');
    host.respond(host.pending.find(call => call.method === 'storage.get' && call.params.key === STORAGE_KEY),
      JSON.stringify({ version: 2, activeProfileId: '', profiles: [] }));
    await tick();
    assert.equal(surface().querySelector('.harness-config'), null, 'late retry must not reopen a dismissed manager');

    outcome = null;
    click('模型');
    await tick();
    click('添加服务商');
    assert.ok(surface().querySelector('.harness-config'), 'recovered host allows adding');
    assert.equal(host.calls.filter(call => call.method === 'ai.profiles').length, 0);
    console.log(`PASS ${mode}: old host supported without ai.profiles; failed local reads retry without overwriting config`);
  } finally { await runtime.unload(); handle.removeDom(); }
}

(async () => {
  for (const mode of ['source', 'built']) { await run(mode); await runAvailability(mode); }
})().catch(error => { console.error(error); process.exitCode = 1; });
