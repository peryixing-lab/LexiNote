'use strict';

const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');
const box = createSandbox();
box.reset();
box.prepareStorage();
const { PluginAiService: ai } = box.load('plugin/ai/PluginAiService');
const { PluginAiQuota: quota } = box.load('plugin/ai/PluginAiQuota');
const { PluginRpcMethod, PluginRpcRequest } = box.load('plugin/model/PluginContracts');
const { PluginRpcDispatcher, PluginSession } = box.load('plugin/runtime/PluginRpcDispatcher');
const configure = (patch) => ai.configure(JSON.stringify(patch)).then(JSON.parse);
const respond = (body, status = 200) => box.expectHttp({ status, body: JSON.stringify(body) });
const lastRequest = () => box.state.httpRequests.at(-1);
let checks = 0;
const eq = (a, b) => { checks++; assert.deepEqual(a, b); };
const ok = (value) => { checks++; assert.ok(value); };

(async () => {
  ai.resetForTests();
  const longBase = `https://gateway.example/${'long-path/'.repeat(100)}v1`;
  const key = `sk-${'k'.repeat(700)}`;
  eq((await configure({ baseUrl: longBase, model: 'alpha', apiKey: key })).baseUrl, longBase);
  await assert.rejects(configure({ provider: 'anthropic', baseUrl: 'ftp://invalid' }), /E_INVALID_ARGUMENT/);
  eq(JSON.parse(await ai.status()).provider, 'openai-compatible');
  await assert.rejects(configure({ baseUrl: 'https://different.example/v1' }), /重新填写/);
  eq(JSON.parse(await ai.status()).baseUrl, longBase);
  await assert.rejects(configure({ baseUrl: `https://g.test/${'a'.repeat(8192)}`, apiKey: key }), /8192/);
  respond({ data: [{ id: 'alpha' }, { id: 'beta' }, { id: 'alpha' }, { id: '' }] });
  eq(JSON.parse(await ai.models()), ['alpha', 'beta']);
  eq(lastRequest().url, `${longBase}/models`);
  eq(lastRequest().options.method, 'GET');
  ok(!JSON.stringify(JSON.parse(await ai.status())).includes(key));
  const beforeUnsupported = box.state.httpRequests.length;
  eq(JSON.parse(await ai.balance()).supported, false);
  eq(box.state.httpRequests.length, beforeUnsupported);
  respond({}, 404);
  await assert.rejects(ai.models(), /HTTP 404/);
  respond({ unexpected: true });
  await assert.rejects(ai.models(), /手动添加/);
  console.log('PASS long configuration, atomic rejected patches, model catalog, unsupported services');

  await configure({ baseUrl: 'https://api.deepseek.com/anthropic/v1/messages', apiKey: 'secret-ds' });
  respond({ balance_infos: [{ currency: 'CNY', total_balance: '-0.01' }, { currency: 'USD', total_balance: '1.23' }] });
  const balance = JSON.parse(await ai.balance());
  eq(balance.windows.map((item) => item.remainingValue), [-0.01, 1.23]);
  eq(lastRequest().url, 'https://api.deepseek.com/user/balance');
  eq(lastRequest().options.header.Authorization, 'Bearer secret-ds');
  const count = box.state.httpRequests.length;
  eq(JSON.parse(await ai.balance()), balance);
  eq(box.state.httpRequests.length, count);
  await configure({ model: 'beta' });
  respond({ balance_infos: [{ currency: 'CNY', total_balance: '2' }] });
  eq(JSON.parse(await ai.balance()).windows[0].remainingValue, 2);

  await configure({ baseUrl: 'https://openrouter.ai/api/v1', apiKey: 'secret-or' });
  respond({ data: { total_credits: '20.5', total_usage: 3.25 } });
  eq(JSON.parse(await ai.balance()).windows[0].remainingValue, 17.25);
  eq(lastRequest().url, 'https://openrouter.ai/api/v1/credits');
  respond({ data: [{ id: 'vendor/model' }] });
  eq(JSON.parse(await ai.models()), ['vendor/model']);
  eq(lastRequest().url, 'https://openrouter.ai/api/v1/models');
  for (const url of ['https://api.deepseek.com.evil.test/v1', 'https://evil.test/api.deepseek.com',
    'http://api.deepseek.com/v1', 'https://api.deepseek.com:444/v1', 'https://api.deepseek.com@evil.test']) {
    eq(quota.provider(url), '');
  }
  console.log('PASS balances, signed/string amounts, cache invalidation and exact provider matching');

  await configure({ baseUrl: 'https://open.bigmodel.cn/api/paas/v4', apiKey: 'secret-glm' });
  respond({ data: { limits: [
    { type: 'CREDIT_LIMIT', unit: 3, number: 5, usage: '100', remaining: '80', currentValue: '30' },
    { type: 'TOKENS_LIMIT', unit: 6, number: 7, percentage: 45 },
    { type: 'TOKENS_LIMIT', unit: 1, number: 30, percentage: 10 },
    { type: 'SEARCH', percentage: 30 }, { type: 'CREDIT_LIMIT', unit: 3 }
  ] } });
  const glm = JSON.parse(await ai.balance());
  eq(glm.windows.map((item) => [item.label, item.usedPercent]), [['5 小时额度', 30], ['每周额度', 45], ['每月额度', 10]]);
  eq(lastRequest().options.header.Authorization, 'secret-glm');
  respond({ data: [{ id: 'glm' }] });
  await ai.models();
  eq(lastRequest().url, 'https://open.bigmodel.cn/api/paas/v4/models');
  const kimi = quota.parse('Kimi For Coding', JSON.stringify({ usages: {
    limit_5h: { used_ratio: '0.25', reset_time: '2026-11-12T00:00:00Z' },
    limit_month_code: { used_ratio: 0.1 }, limit_month_total: { used_ratio: 0.9 }
  }, usage: { limit: '100', remaining: '60' } }));
  eq(kimi.windows.map((item) => item.usedPercent), [25, 10, 40]);
  eq(kimi.windows[0].resetAt, Date.parse('2026-11-12T00:00:00Z'));
  const legacy = quota.parse('Kimi For Coding', JSON.stringify({ limits: [
    { detail: { limit: '10', used: '2', resetTime: 1700000000 } },
    { detail: { limit: '10', remaining: '3', resetTime: 1700001000 } }
  ] }));
  eq(legacy.windows[0].usedPercent, 70);
  const minimax = quota.parse('MiniMax Coding Plan', JSON.stringify({ base_resp: { status_code: 0 }, model_remains: [
    { model_name: 'video', current_interval_remaining_percent: 1 },
    { model_name: 'general', current_interval_remaining_percent: 75, current_weekly_status: 3, current_weekly_remaining_percent: 100 }
  ] }));
  eq(minimax.windows.map((item) => item.usedPercent), [25]);
  assert.throws(() => quota.parse('MiniMax Coding Plan', '{"base_resp":{"status_code":1004}}'));
  assert.throws(() => quota.parse('GLM Coding Plan', '{"success":false}'));
  assert.throws(() => quota.parse('DeepSeek', '{"balance_infos":[{"total_balance":null}]}'));
  console.log('PASS GLM, Kimi (current/legacy), MiniMax quota windows and business errors');

  PluginRpcDispatcher.setContext(box.contexts);
  const session = new PluginSession();
  session.pluginId = 'test.ai';
  for (const method of [PluginRpcMethod.AI_BALANCE, PluginRpcMethod.AI_MODELS]) {
    const request = new PluginRpcRequest();
    request.pluginId = session.pluginId; request.method = method;
    await assert.rejects(PluginRpcDispatcher.dispatch(session, request), /E_PERMISSION_DENIED/);
    eq(PluginRpcMethod.capabilityOf(method), 'ai.inference');
  }
  await configure({ clear: true });
  await assert.rejects(ai.models(), /先绑定/);
  console.log(`plugin-ai-catalog-regression: ${checks} checks plus error assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
