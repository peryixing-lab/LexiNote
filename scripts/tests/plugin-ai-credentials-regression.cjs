// DSH-style credential seam: per-plugin profiles, write-only keys, URL/redirect policy.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
box.prepareStorage();
const { PluginAiService: ai } = box.load('plugin/ai/PluginAiService');
const { PluginErrorCode } = box.load('plugin/model/PluginErrors');

let checks = 0;
const ok = (value, message) => { checks++; assert.ok(value, message); };
const eq = (left, right, message) => { checks++; assert.deepEqual(left, right, message); };
async function rejects(promise, code, message) {
  checks++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}
const configure = (pluginId, patch) => ai.configureFor(pluginId, JSON.stringify(patch)).then(JSON.parse);
const status = (pluginId) => ai.statusFor(pluginId).then(JSON.parse);
const chat = (pluginId, params) => ai.chatFor(pluginId, JSON.stringify(params));
const prefs = () => box.state.prefs;
const secretKey = (pluginId, profileId) => `pluginAiSecret.v2.${pluginId}:${profileId}`;
const bindingKey = (pluginId) => `pluginAiBinding.v2.${pluginId}`;

(async () => {
  ai.resetForTests();

  // 1. The key is write-only and lives only in the host secret slot.
  const a = await configure('plugin.a', {
    action: 'create', profileId: 'a1', name: 'A', provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat', apiKey: 'sk-aaaa'
  });
  eq(a.configured, true, 'profile configured');
  eq(a.profileId, 'a1', 'profile id kept');
  ok(!JSON.stringify(a).includes('sk-aaaa'), 'configure reply never contains the key');
  ok(!String(prefs().get(bindingKey('plugin.a'))).includes('sk-aaaa'), 'binding record never contains the key');
  eq(prefs().get(secretKey('plugin.a', 'a1')), 'sk-aaaa', 'key lives in the host secret slot');
  ok(!JSON.stringify(await status('plugin.a')).includes('sk-aaaa'), 'status never contains the key');

  // 2. Bindings are per plugin: B cannot read or spend A's key.
  eq((await status('plugin.b')).configured, false, 'other plugin starts unbound');
  await rejects(chat('plugin.b', { messages: [{ role: 'user', content: 'hi' }] }),
    PluginErrorCode.MISSING_CREDENTIAL, 'other plugin cannot chat on A');
  eq(box.state.httpRequests.length, 0, 'no request before a binding exists');

  // 3. Rotation applies to the next request.
  await configure('plugin.a', {
    action: 'save', profileId: 'a1', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', apiKey: 'sk-aaaa-rotated'
  });
  box.expectHttp({ status: 200, body: JSON.stringify({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }] }) });
  await chat('plugin.a', { messages: [{ role: 'user', content: 'hi' }] });
  eq(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer sk-aaaa-rotated', 'rotation used');

  // 4. Public plain HTTP is refused; loopback plain HTTP stays available for local models.
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'plain', baseUrl: 'http://api.deepseek.com', model: 'm', apiKey: 'sk-plain'
  }), PluginErrorCode.INVALID_ARGUMENT, 'public http refused');
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'lookalike', baseUrl: 'http://127.0.0.1.evil.test', model: 'm', apiKey: 'sk-lookalike'
  }), PluginErrorCode.INVALID_ARGUMENT, 'private prefix must not accept a public lookalike');
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'lookalike6', baseUrl: 'http://[::1].evil.test', model: 'm', apiKey: 'sk-lookalike6'
  }), PluginErrorCode.INVALID_ARGUMENT, 'IPv6 lookalike refused');
  const local = await configure('plugin.a', {
    action: 'create', profileId: 'local', baseUrl: 'http://127.0.0.1:11434', model: 'm', apiKey: 'sk-local'
  });
  eq(local.baseUrl, 'http://127.0.0.1:11434', 'loopback http accepted');
  const lan = await configure('plugin.a', {
    action: 'create', profileId: 'lan', baseUrl: 'http://192.168.1.5:11434', model: 'm', apiKey: 'sk-lan'
  });
  eq(lan.baseUrl, 'http://192.168.1.5:11434', 'private LAN http accepted');

  // 5. Anthropic sends one auth header, plus attribution; redirects are refused.
  await configure('plugin.a', {
    action: 'create', profileId: 'anthropic', provider: 'anthropic-compatible',
    baseUrl: 'https://api.deepseek.com/anthropic', model: 'deepseek-flash', apiKey: 'sk-anthropic'
  });
  box.expectHttp({ status: 200, body: JSON.stringify({ content: [{ type: 'text', text: 'ok' }], stop_reason: 'end_turn' }) });
  await chat('plugin.a', { messages: [{ role: 'user', content: 'hi' }] });
  const request = box.state.httpRequests.at(-1);
  eq(request.options.header['x-api-key'], 'sk-anthropic', 'anthropic key header');
  ok(!Object.prototype.hasOwnProperty.call(request.options.header, 'Authorization'), 'no duplicate bearer header');
  ok(String(request.options.header['User-Agent']).startsWith('LexiNote/'), 'user agent sent');
  eq(request.options.maxRedirects, 0, 'redirects refused');

  // 6. Select/remove keep the local state and do not leak the key.
  const selected = await configure('plugin.a', { action: 'select', profileId: 'a1' });
  eq(selected.profileId, 'a1', 'select returns the active profile');
  await configure('plugin.a', { action: 'remove', profileId: 'anthropic' });
  eq(prefs().get(secretKey('plugin.a', 'anthropic')), '', 'removed secret cleared');
  ok(!String(prefs().get(bindingKey('plugin.a'))).includes('sk-anthropic'), 'removed key absent from binding');

  // 7. Invalid key characters are refused without echoing the value.
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'bad', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-emoji-\u{1F600}'
  }), PluginErrorCode.INVALID_CREDENTIAL, 'illegal key refused');
  try {
    await configure('plugin.a', {
      action: 'create', profileId: 'bad', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-emoji-\u{1F600}'
    });
    ok(false, 'illegal key must throw');
  } catch (error) {
    ok(!String(error.message).includes('\u{1F600}'), 'refusal never echoes the key');
  }

  // 8. Legacy host-wide record migrates once into the Harness binding and is removed.
  await prefs().set('pluginAiConfig.v1', JSON.stringify({
    provider: 'openai-compatible', baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat', apiKey: 'sk-legacy'
  }));
  const migrated = await status('lexinote.harness');
  eq(migrated.configured, true, 'legacy key migrated');
  eq(migrated.profileId, 'legacy', 'legacy profile id');
  eq(prefs().get('pluginAiConfig.v1'), '', 'legacy record cleared');
  ok(!String(prefs().get(bindingKey('lexinote.harness'))).includes('sk-legacy'), 'legacy key not in binding');
  eq(prefs().get(secretKey('lexinote.harness', 'legacy')), 'sk-legacy', 'legacy key in secret slot');

  // 9. The legacy provider blob never reaches the page's boot mirror.
  const mirror = JSON.stringify({
    'harness.providers.v1': JSON.stringify({ version: 1, activeProfileId: 'legacy', profiles: [{ apiKey: 'sk-mirror' }] }),
    'harness.session.v1': '{"messages":[]}'
  });
  const stripped = ai.stripLegacyProviderData(mirror);
  ok(!stripped.includes('sk-mirror'), 'legacy key removed from boot mirror');
  ok(stripped.includes('harness.session.v1'), 'other plugin data preserved');

  // 10. A corrupt record still identifies as a per-plugin host; it never falls back to legacy storage.
  prefs().set(bindingKey('plugin.c'), JSON.stringify({ version: 1, profiles: [] }));
  const corrupt = await status('plugin.c');
  eq(corrupt.configured, false, 'corrupt binding reports unconfigured');
  eq(corrupt.profileId, '', 'corrupt binding still returns the host profile marker');
  await rejects(configure('plugin.c', {
    action: 'create', profileId: 'c1', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-c'
  }), PluginErrorCode.INVALID_ARGUMENT, 'corrupt binding rejects writes');

  // 11. Clearing a plugin removes every profile and secret it owns.
  await ai.clear('plugin.a');
  eq(prefs().get(bindingKey('plugin.a')), '', 'binding cleared');
  eq(prefs().get(secretKey('plugin.a', 'a1')), '', 'secret cleared');
  eq((await status('plugin.a')).configured, false, 'plugin unbound after clear');

  console.log(`plugin-ai-credentials-regression: ${checks} checks passed`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
