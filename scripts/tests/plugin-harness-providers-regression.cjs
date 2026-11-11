'use strict';
const assert = require('node:assert/strict');
const { serviceName } = require('../../plugins/harness/src/providers.js');
for (const [baseUrl, expected] of [
  ['https://api.deepseek.com/v1', 'DeepSeek'],
  ['https://API.DEEPSEEK.COM:443/anthropic', 'DeepSeek'],
  ['https://openrouter.ai/api/v1', 'OpenRouter'],
  ['https://api.openai.com/v1', 'OpenAI'],
  ['https://open.bigmodel.cn/api/paas/v4', '智谱 GLM'],
  ['https://api.kimi.com/coding/v1', 'Kimi'],
  ['https://127.0.0.1:8080/v1', '127.0.0.1'],
  ['http://[::1]:8080/v1', '[::1]'],
  ['https://proxy.example/deepseek/v1', 'proxy.example'],
  ['https://api.deepseek.com.evil.test/v1', 'api.deepseek.com.evil.test']
]) {
  assert.equal(serviceName({ provider: 'openai-compatible', model: 'deepseek-flash', baseUrl }), expected);
}
assert.equal(serviceName({ baseUrl: 'https://proxy.example/v1' }, '  我的供应商  '), '我的供应商');
assert.equal(serviceName(null), '模型服务');
console.log('PASS provider display uses the actual service host, supports custom names and never infers it from the model ID');
