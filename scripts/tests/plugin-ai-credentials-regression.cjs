// DSH-style credential separation, validation, masking, env fallback, compat, and URL policy.
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
const secretKeyV2 = (pluginId, profileId) => `pluginAiSecret.v2.${pluginId}:${profileId}`;
const bindingKey = (pluginId) => `pluginAiBinding.v2.${pluginId}`;
const secretPrefs = () => box.state.secretPrefs;

(async () => {
  ai.resetForTests();

  // 1. Secret separation: config binding has symbolic ref only; raw secret lives only in isolated host store.
  const longKey = 'sk-deepseek-12345678909988';
  const a = await configure('plugin.a', {
    action: 'create', profileId: 'a1', name: 'A', provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat', apiKey: longKey,
    credentialRef: 'DEEPSEEK_API_KEY'
  });
  eq(a.configured, true, 'profile configured');
  eq(a.profileId, 'a1', 'profile id kept');
  eq(a.credentialRef, 'DEEPSEEK_API_KEY', 'credentialRef preserved');
  eq(a.credentialSource, 'store', 'credentialSource reports store');
  eq(a.credentialWritable, true, 'credentialWritable true');
  eq(a.maskedApiKey, 'sk-deeps••••••••••••••9988', 'maskCredential matches deepseek-harness algorithm');
  eq(a.credential, {
    ref: 'DEEPSEEK_API_KEY',
    configured: true,
    source: 'store',
    writable: true,
    masked: 'sk-deeps••••••••••••••9988'
  }, 'CredentialInfo block matches deepseek-harness shape');
  ok(!JSON.stringify(a).includes(longKey), 'configure reply never contains the raw key');
  ok(!String(prefs().get(bindingKey('plugin.a'))).includes(longKey), 'binding record never contains the raw key');
  ok(String(prefs().get(bindingKey('plugin.a'))).includes('DEEPSEEK_API_KEY'), 'binding holds symbolic credentialRef');
  ok(!prefs().has(secretKeyV2('plugin.a', 'a1')), 'general prefs never hold secret slot');
  eq(secretPrefs().get(secretKeyV2('plugin.a', 'a1')), longKey, 'isolated host secret store holds key');
  ok(!JSON.stringify(await status('plugin.a')).includes(longKey), 'status never contains the raw key');

  // 2. Bindings are per plugin: B cannot read or spend A's key.
  eq((await status('plugin.b')).configured, false, 'other plugin starts unbound');
  await rejects(chat('plugin.b', { messages: [{ role: 'user', content: 'hi' }] }),
    PluginErrorCode.MISSING_CREDENTIAL, 'other plugin cannot chat on A');
  eq(box.state.httpRequests.length, 0, 'no request before a binding exists');

  // 3. Rotation applies to the next request.
  await configure('plugin.a', {
    action: 'save', profileId: 'a1', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', apiKey: 'sk-aaaa-rotated-1122'
  });
  box.expectHttp({ status: 200, body: JSON.stringify({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }] }) });
  await chat('plugin.a', { messages: [{ role: 'user', content: 'hi' }] });
  eq(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer sk-aaaa-rotated-1122', 'rotation used');

  // 4. Env fallback & clearApiKey (deepseek-harness CredentialResolution).
  ai.setEnvForTests('ENV_ONLY_KEY', 'sk-env-fallback-445566');
  const envProf = await configure('plugin.a', {
    action: 'create', profileId: 'env_prof', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', credentialRef: 'ENV_ONLY_KEY'
  });
  eq(envProf.configured, true, 'env fallback satisfies required key');
  eq(envProf.credential.configured, true, 'credential block marks configured via env');
  eq(envProf.profiles.find((p) => p.profileId === 'env_prof').hasKey, true, 'profile summary reports hasKey');
  eq(envProf.credentialSource, 'env', 'source reports env when store slot is empty');
  ok(!secretPrefs().has(secretKeyV2('plugin.a', 'env_prof')), 'env key is not copied into store');
  box.expectHttp({ status: 200, body: JSON.stringify({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }] }) });
  await chat('plugin.a', { messages: [{ role: 'user', content: 'env hi' }] });
  eq(box.state.httpRequests.at(-1).options.header.Authorization, 'Bearer sk-env-fallback-445566', 'chat uses env key');

  // Store overrides env, and clearApiKey removes store slot so env (if any) or missing takes effect.
  await configure('plugin.a', {
    action: 'save', profileId: 'env_prof', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', apiKey: 'sk-store-override-7788'
  });
  eq((await status('plugin.a')).credentialSource, 'store', 'store wins over env');
  const cleared = await configure('plugin.a', {
    action: 'save', profileId: 'env_prof', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', clearApiKey: true
  });
  ok(!secretPrefs().has(secretKeyV2('plugin.a', 'env_prof')), 'clearApiKey deletes stored secret');
  eq(cleared.credentialSource, 'env', 'clearing store falls back to env when env var set');
  await configure('plugin.a', { action: 'remove', profileId: 'env_prof' });
  ai.setEnvForTests('ENV_ONLY_KEY', '');

  // 5. Public plain HTTP is refused; loopback plain HTTP stays available for local models.
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
    action: 'create', profileId: 'local', baseUrl: 'http://127.0.0.1:11434', model: 'm'
  });
  eq(local.baseUrl, 'http://127.0.0.1:11434', 'loopback http accepted without key');
  const lan = await configure('plugin.a', {
    action: 'create', profileId: 'lan', baseUrl: 'http://192.168.1.5:11434', model: 'm', apiKey: 'sk-lan'
  });
  eq(lan.baseUrl, 'http://192.168.1.5:11434', 'private LAN http accepted');

  // 6. Anthropic sends one auth header, plus attribution; redirects are refused.
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
  eq(request.options.maxRedirects, undefined, 'maxRedirects omitted to avoid HarmonyOS 2300047');

  // 7. Model compat (`maxTokensField: max_completion_tokens`) applied to request body.
  await configure('plugin.a', {
    action: 'create', profileId: 'compat_prof', provider: 'openai-compatible',
    baseUrl: 'https://api.openai.com/v1', model: 'o3-mini', apiKey: 'sk-openai-123456',
    compat: { maxTokensField: 'max_completion_tokens', supportsDeveloperRole: false }
  });
  box.expectHttp({ status: 200, body: JSON.stringify({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }] }) });
  await chat('plugin.a', { messages: [{ role: 'user', content: 'hi' }], maxTokens: 512 });
  const compatBody = JSON.parse(box.state.httpRequests.at(-1).options.extraData);
  eq(compatBody.max_completion_tokens, 512, 'compat maxTokensField respected');
  ok(!Object.prototype.hasOwnProperty.call(compatBody, 'max_tokens'), 'legacy max_tokens omitted when max_completion_tokens set');
  await configure('plugin.a', { action: 'remove', profileId: 'compat_prof' });

  // 8. Select/remove keep the local state and do not leak the key.
  const selected = await configure('plugin.a', { action: 'select', profileId: 'a1' });
  eq(selected.profileId, 'a1', 'select returns the active profile');
  await configure('plugin.a', { action: 'remove', profileId: 'anthropic' });
  ok(!secretPrefs().has(secretKeyV2('plugin.a', 'anthropic')) && !prefs().has(secretKeyV2('plugin.a', 'anthropic')), 'removed secret cleared');
  ok(!String(prefs().get(bindingKey('plugin.a'))).includes('sk-anthropic'), 'removed key absent from binding');

  // 9. dsh apiKeyFailure validation: illegal chars, wrapped quotes, and ENV_VAR=value rejected without echoing secret.
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'bad', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-emoji-\u{1F600}'
  }), PluginErrorCode.INVALID_CREDENTIAL, 'illegal key refused');
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'quoted', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: '"sk-quoted-secret"'
  }), PluginErrorCode.INVALID_ARGUMENT, 'quoted key refused per deepseek-harness apiKeyFailure');
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'envline', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'DEEPSEEK_API_KEY=sk-123456'
  }), PluginErrorCode.INVALID_ARGUMENT, 'ENV_VAR=value line refused per deepseek-harness apiKeyFailure');
  await rejects(configure('plugin.a', {
    action: 'create', profileId: 'badref', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-ok', credentialRef: '123-bad'
  }), PluginErrorCode.INVALID_ARGUMENT, 'invalid credentialRef format rejected');
  try {
    await configure('plugin.a', {
      action: 'create', profileId: 'bad', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-emoji-\u{1F600}'
    });
    ok(false, 'illegal key must throw');
  } catch (error) {
    ok(!String(error.message).includes('\u{1F600}'), 'refusal never echoes the key');
  }

  // 10. Legacy host-wide record migrates once into the Harness binding and is removed.
  await prefs().set('pluginAiConfig.v1', JSON.stringify({
    provider: 'openai-compatible', baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat', apiKey: 'sk-legacy'
  }));
  const migrated = await status('lexinote.harness');
  eq(migrated.configured, true, 'legacy key migrated');
  eq(migrated.profileId, 'legacy', 'legacy profile id');
  ok(!prefs().get('pluginAiConfig.v1'), 'legacy record cleared');
  ok(!String(prefs().get(bindingKey('lexinote.harness'))).includes('sk-legacy'), 'legacy key not in binding');
  eq(secretPrefs().get(secretKeyV2('lexinote.harness', 'legacy')), 'sk-legacy', 'legacy key stored in isolated host slot');

  // 11. The legacy provider blob never reaches the page's boot mirror.
  const mirror = JSON.stringify({
    'harness.providers.v1': JSON.stringify({ version: 1, activeProfileId: 'legacy', profiles: [{ apiKey: 'sk-mirror' }] }),
    'harness.session.v1': '{"messages":[]}'
  });
  const stripped = ai.stripLegacyProviderData(mirror);
  ok(!stripped.includes('sk-mirror'), 'legacy key removed from boot mirror');
  ok(stripped.includes('harness.session.v1'), 'other plugin data preserved');

  // 12. A corrupt record still identifies as a per-plugin host; it never falls back to legacy storage.
  prefs().set(bindingKey('plugin.c'), JSON.stringify({ version: 1, profiles: [] }));
  const corrupt = await status('plugin.c');
  eq(corrupt.configured, false, 'corrupt binding reports unconfigured');
  eq(corrupt.profileId, '', 'corrupt binding still returns the host profile marker');
  await rejects(configure('plugin.c', {
    action: 'create', profileId: 'c1', baseUrl: 'https://api.deepseek.com', model: 'm', apiKey: 'sk-c'
  }), PluginErrorCode.INVALID_ARGUMENT, 'corrupt binding rejects writes');

  // 13. Clearing a plugin removes every profile and secret it owns.
  await ai.clear('plugin.a');
  eq(prefs().get(bindingKey('plugin.a')), '', 'binding cleared');
  ok(!secretPrefs().has(secretKeyV2('plugin.a', 'a1')) && !prefs().has(secretKeyV2('plugin.a', 'a1')), 'secret cleared');
  eq((await status('plugin.a')).configured, false, 'plugin unbound after clear');

  console.log(`plugin-ai-credentials-regression: ${checks} checks passed`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
