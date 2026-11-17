import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import esbuild from 'esbuild';

const require = createRequire(import.meta.url);
const ROOT = process.cwd();
const OUT_DIR = join(ROOT, '.tmp-plugin-credentials-test');
const USER_DATA = join(OUT_DIR, 'user-data');

function fail(message, detail) {
  console.error(`FAIL: ${message}`, detail !== undefined ? detail : '');
  process.exitCode = 1;
}

function ok(cond, message, detail) {
  if (!cond) { fail(message, detail); }
}

function eq(actual, expected, message) {
  if (actual !== expected) {
    fail(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

async function main() {
  rmSync(OUT_DIR, { recursive: true, force: true });
  mkdirSync(USER_DATA, { recursive: true });

  const bundled = join(OUT_DIR, 'pluginAiService.cjs');
  await esbuild.build({
    entryPoints: [join(ROOT, 'src', 'main', 'pluginAiService.ts')],
    bundle: true,
    platform: 'node',
    format: 'cjs',
    outfile: bundled
  });

  const { PluginAiService, maskCredential, checkKey } = require(bundled);
  const envStore = {};
  const service = new PluginAiService(USER_DATA, { env: envStore });

  // 1. Credential separation: plugin-ai.json carries credentialRef & zero secret; plugin-credentials.json is 0600
  const status1 = service.configureFor('lexinote.harness', {
    action: 'create',
    name: 'DeepSeek',
    provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
    apiKey: 'sk-deepseek-harness-secret-9988',
    compat: { maxTokensField: 'max_completion_tokens', supportsDeveloperRole: true }
  });

  eq(status1.credentialRef, 'DEEPSEEK_API_KEY', 'derives DEEPSEEK_API_KEY credentialRef');
  eq(status1.maskedApiKey, maskCredential('sk-deepseek-harness-secret-9988'), 'returns dsh maskedApiKey');
  eq(status1.maskedApiKey, 'sk-deeps\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u20229988', 'exact dsh mask pattern');
  ok(status1.credential?.configured === true && status1.credential?.source === 'store', 'CredentialInfo reports store source');
  eq(status1.compat?.maxTokensField, 'max_completion_tokens', 'compat persisted on status');

  const configJson = readFileSync(join(USER_DATA, 'plugin-ai.json'), 'utf8');
  ok(!configJson.includes('sk-deepseek-harness-secret-9988'), 'plugin-ai.json never writes plaintext secret');
  ok(configJson.includes('DEEPSEEK_API_KEY'), 'plugin-ai.json stores credentialRef');

  const credPath = join(USER_DATA, 'plugin-credentials.json');
  ok(existsSync(credPath), 'plugin-credentials.json created');
  if (process.platform !== 'win32') {
    eq(statSync(credPath).mode & 0o777, 0o600, 'plugin-credentials.json mode is 0600');
    chmodSync(credPath, 0o644);
    let refused = false;
    try {
      service.configureFor('lexinote.harness', { action: 'save', model: 'deepseek-reasoner' });
    } catch (err) {
      refused = String(err?.message || err).includes('chmod 600');
    }
    ok(refused, 'rejects group/other readable credentials file matching dsh assertOwnerOnly');
    chmodSync(credPath, 0o600);
  }

  // 2. Dynamic per-request resolution & env fallback
  envStore.DEEPSEEK_API_KEY = 'sk-env-fallback-key-123456';
  const afterClear = service.configureFor('lexinote.harness', {
    action: 'clearCredential',
    profileId: status1.profileId
  });
  eq(afterClear.credentialSource, 'env', 'falls back to env source when stored key is cleared');
  eq(afterClear.configured, true, 'configured true with env fallback');
  delete envStore.DEEPSEEK_API_KEY;
  const unconfigured = service.statusFor('lexinote.harness');
  eq(unconfigured.configured, false, 'configured false when neither store nor env has secret');

  // 3. apiKeyFailure validation rules (quotes, KEY=VAL, blank, whitespace)
  for (const bad of ['   ', '"sk-quoted-123456"', 'OPENAI_API_KEY=sk-123456', 'sk-with space']) {
    const res = checkKey(bad);
    ok(!res.ok, `rejects invalid key: ${JSON.stringify(bad)}`);
  }

  // 4. clearFor cleans both bindings and private credentials
  service.configureFor('lexinote.harness', {
    action: 'save',
    profileId: status1.profileId,
    apiKey: 'sk-restore-key-abcdef1234'
  });
  service.clearFor('lexinote.harness');
  const clearedCreds = JSON.parse(readFileSync(credPath, 'utf8'));
  eq(Object.keys(clearedCreds.records || {}).length, 0, 'clearFor removes all stored credentials for plugin');

  rmSync(OUT_DIR, { recursive: true, force: true });
  if (!process.exitCode) {
    console.log('plugin-credentials-test PASSED (dsh credential separation + 0600 + mask + env + validation)');
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
