import { http } from '@kit.NetworkKit';
import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginAiChatParams, PluginAiConfigureParams } from '../model/PluginContracts';
import { PluginLimits } from '../model/PluginModels';
import { PluginAiQuota, PluginAiBalance } from './PluginAiQuota';

/**
 * Host-brokered model inference for plugins (capability `ai.inference`).
 *
 * Credential handling follows the DeepSeek Harness (`dsh`) model:
 *  - settings carry a provider profile + symbolic `credentialRef`, never a secret;
 *  - the API key is write-only and lives in the host-only `lexinote_plugin_secrets`
 *    Preferences store keyed by `<pluginId>:<profileId>` (separated from config);
 *  - every request resolves the key dynamically, so key updates apply on the next request;
 *  - status and configure replies return `CredentialInfo` + `maskedApiKey` without raw secrets;
 *  - provider URLs are HTTPS (plain HTTP only for loopback/private LAN addresses),
 *    redirects are refused (`maxRedirects: 0`), and only one authentication header is sent per wire.
 */

const BINDING_PREFIX: string = 'pluginAiBinding.v2.';
const SECRET_PREFIX: string = 'pluginAiSecret.v2.';
/** Legacy single-binding record; read once and removed after migration. */
const AI_CONFIG_KEY: string = 'pluginAiConfig.v1';
const DEFAULT_BASE_URL: string = 'https://api.deepseek.com';
const DEFAULT_MODEL: string = 'deepseek-chat';
const DEFAULT_PLUGIN_ID: string = 'lexinote.harness';
const USER_AGENT: string = 'LexiNote/2.0 (+https://github.com/peryixing-lab/LexiNote)';
const MAX_PROFILES: number = 32;
const MAX_BINDING_CHARS: number = 36000;
const PROFILE_ID_PATTERN: RegExp = /^[A-Za-z0-9_.-]{1,64}$/;
const CREDENTIAL_REF_PATTERN: RegExp = /^[A-Za-z_][A-Za-z0-9_]*$/;
const ENV_LINE_PATTERN: RegExp = /^[A-Z][A-Z0-9_]*=[^=]/;

export class PluginAiCompatConfig {
  maxTokensField: string = '';
  thinkingFormat: string = '';
  supportsDeveloperRole: boolean = false;
  hasSupportsDeveloperRole: boolean = false;
}

export class PluginAiRetryPolicy {
  mode: string = '';
  maxRetries: number = -1;
}

export class PluginAiCredentialInfo {
  ref: string = '';
  configured: boolean = false;
  source: string = '';
  writable: boolean = true;
  masked: string = '';
}

export class PluginAiProfileSummary {
  profileId: string = '';
  name: string = '';
  provider: string = '';
  baseUrl: string = '';
  model: string = '';
  maxTokens: number = 0;
  temperature: number = 0;
  balanceProvider: string = '';
  hasKey: boolean = false;
  configured: boolean = false;
  needsApiKey: boolean = true;
  credentialRef: string = '';
  credentialSource: string = '';
  credentialWritable: boolean = true;
  maskedApiKey: string = '';
  credential: PluginAiCredentialInfo = new PluginAiCredentialInfo();
  compat: PluginAiCompatConfig | undefined = undefined;
  retryPolicy: PluginAiRetryPolicy | undefined = undefined;
}

/** One provider profile: everything the wire needs except the secret. */
export class PluginAiProfile {
  profileId: string = '';
  name: string = '';
  provider: string = 'openai-compatible';
  baseUrl: string = '';
  model: string = '';
  maxTokens: number = 8192;
  temperature: number = 0.3;
  credentialRef: string = '';
  compat: PluginAiCompatConfig | undefined = undefined;
  retryPolicy: PluginAiRetryPolicy | undefined = undefined;
}

/** Per-plugin profile list. The key is stored separately and is never part of this record. */
class PluginAiBinding {
  version: number = 2;
  activeProfileId: string = '';
  profiles: PluginAiProfile[] = [];
}

/** UI-safe view of the active profile. `profileId` is always present on this host. */
export class PluginAiStatus {
  configured: boolean = false;
  profileId: string = '';
  name: string = '';
  provider: string = '';
  baseUrl: string = '';
  model: string = '';
  maxTokens: number = 0;
  temperature: number = 0;
  balanceProvider: string = '';
  needsApiKey: boolean = true;
  credentialRef: string = '';
  credentialSource: string = '';
  credentialWritable: boolean = true;
  maskedApiKey: string = '';
  credential: PluginAiCredentialInfo = new PluginAiCredentialInfo();
  compat: PluginAiCompatConfig | undefined = undefined;
  retryPolicy: PluginAiRetryPolicy | undefined = undefined;
  profiles: PluginAiProfileSummary[] = [];
}

class PluginAiResolvedSecret {
  secret: string = '';
  source: string = '';
  ref: string = '';
}

export class PluginAiToolCall {
  id: string = '';
  name: string = '';
  arguments: string = '{}';
}

export class PluginAiUsage {
  inputTokens: number = 0;
  outputTokens: number = 0;
}

export class PluginAiReply {
  text: string = '';
  reasoning: string = '';
  toolCalls: PluginAiToolCall[] = [];
  finishReason: string = 'stop';
  model: string = '';
  usage: PluginAiUsage = new PluginAiUsage();
}

class PluginAiActive {
  profile: PluginAiProfile = new PluginAiProfile();
  key: string = '';
}

class PluginAiKeyCheck {
  ok: boolean = false;
  value: string = '';
  reason: string = '';
}

export class PluginAiService {
  private static balanceCache: Map<string, PluginAiBalance> = new Map();
  private static envOverrides: Map<string, string> = new Map();

  /** Test hook: forget in-memory caches. Stored secrets are untouched. */
  static resetForTests(): void {
    PluginAiService.balanceCache = new Map();
    PluginAiService.envOverrides = new Map();
  }

  /** Test hook: inject virtual env vars for testing `env` credential source resolution. */
  static setEnvForTests(name: string, value: string): void {
    if (value.length === 0) {
      PluginAiService.envOverrides.delete(name);
    } else {
      PluginAiService.envOverrides.set(name, value);
    }
  }

  private static bindingKey(pluginId: string): string {
    return `${BINDING_PREFIX}${pluginId}`;
  }

  private static secretKey(pluginId: string, profileId: string): string {
    return `${SECRET_PREFIX}${pluginId}:${profileId}`;
  }

  private static async getSecret(pluginId: string, profileId: string): Promise<string> {
    const slotKey = PluginAiService.secretKey(pluginId, profileId);
    const stored = await LexiStorageService.getPluginSecret(slotKey);
    if (stored.length > 0) {
      return stored;
    }
    // Migrate legacy plaintext slot if present in general settings Preferences
    const legacy = await LexiStorageService.getSetting(slotKey, '');
    if (legacy.length > 0) {
      await LexiStorageService.setPluginSecret(slotKey, legacy);
      await LexiStorageService.deleteSetting(slotKey);
      return legacy;
    }
    return '';
  }

  private static async setSecret(pluginId: string, profileId: string, value: string): Promise<void> {
    const slotKey = PluginAiService.secretKey(pluginId, profileId);
    if (value.length === 0) {
      await LexiStorageService.deletePluginSecret(slotKey);
    } else {
      await LexiStorageService.setPluginSecret(slotKey, value);
    }
    await LexiStorageService.deleteSetting(slotKey);
  }

  static maskCredential(value: string): string {
    if (value.length === 0) { return ''; }
    const chars: string[] = [];
    for (let i = 0; i < value.length; ) {
      const cp = value.codePointAt(i) ?? 0;
      chars.push(String.fromCodePoint(cp));
      i += cp > 0xffff ? 2 : 1;
    }
    const sepIdx = chars.findIndex((c: string): boolean => c === '-' || c === '_');
    const providerEnd = sepIdx >= 0 ? sepIdx + 1 : 0;
    const hidden = chars.length - providerEnd - 5 - 4;
    if (hidden < 8) {
      return '\u2022'.repeat(chars.length);
    }
    return `${chars.slice(0, providerEnd + 5).join('')}${'\u2022'.repeat(hidden)}${chars.slice(chars.length - 4).join('')}`;
  }

  static isValidCredentialRef(ref: string): boolean {
    return ref.length > 0 && CREDENTIAL_REF_PATTERN.test(ref);
  }

  static defaultCredentialRef(provider: string, baseUrl: string, profileId: string): string {
    const lower = baseUrl.toLowerCase();
    if (lower.includes('deepseek.com')) { return 'DEEPSEEK_API_KEY'; }
    if (lower.includes('anthropic.com') || provider === 'anthropic-compatible') { return 'ANTHROPIC_API_KEY'; }
    if (lower.includes('openrouter.ai')) { return 'OPENROUTER_API_KEY'; }
    if (lower.includes('siliconflow.cn')) { return 'SILICONFLOW_API_KEY'; }
    if (lower.includes('bigmodel.cn') || lower.includes('z.ai')) { return 'ZHIPU_API_KEY'; }
    if (lower.includes('kimi.com') || lower.includes('moonshot.cn')) { return 'MOONSHOT_API_KEY'; }
    if (lower.includes('minimaxi.com') || lower.includes('minimax.io')) { return 'MINIMAX_API_KEY'; }
    if (lower.includes('openai.com')) { return 'OPENAI_API_KEY'; }
    const cleaned = profileId.toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    if (cleaned.length === 0) { return 'OPENAI_API_KEY'; }
    const prefix = /^[0-9]/.test(cleaned) ? `KEY_${cleaned}` : cleaned;
    return `${prefix}_API_KEY`;
  }

  private static resolvedCredentialRef(profile: PluginAiProfile): string {
    if (profile.credentialRef.length > 0 && PluginAiService.isValidCredentialRef(profile.credentialRef)) {
      return profile.credentialRef;
    }
    return PluginAiService.defaultCredentialRef(profile.provider, profile.baseUrl, profile.profileId);
  }

  private static resolveEnvSecret(ref: string): string {
    if (ref.length === 0) { return ''; }
    const val = PluginAiService.envOverrides.get(ref);
    return typeof val === 'string' ? val.trim() : '';
  }

  private static async resolveSecretInfo(pluginId: string, profile: PluginAiProfile): Promise<PluginAiResolvedSecret> {
    const out = new PluginAiResolvedSecret();
    out.ref = PluginAiService.resolvedCredentialRef(profile);
    const stored = await PluginAiService.getSecret(pluginId, profile.profileId);
    if (stored.length > 0) {
      out.secret = stored;
      out.source = 'store';
      return out;
    }
    const envVal = PluginAiService.resolveEnvSecret(out.ref);
    if (envVal.length > 0) {
      out.secret = envVal;
      out.source = 'env';
      return out;
    }
    return out;
  }

  private static needsApiKeyForUrl(baseUrl: string): boolean {
    const match = /^https?:\/\/([^/:?#]+)(?::\d+)?(?:\/|$)/i.exec(baseUrl.trim());
    const host = match ? match[1].toLowerCase() : '';
    return !(host === '127.0.0.1' || host === 'localhost' || host === '[::1]' || host === '::1');
  }

  private static copyCompat(source: PluginAiCompatConfig | undefined): PluginAiCompatConfig | undefined {
    if (!source) { return undefined; }
    const copy = new PluginAiCompatConfig();
    copy.maxTokensField = source.maxTokensField;
    copy.thinkingFormat = source.thinkingFormat;
    copy.supportsDeveloperRole = source.supportsDeveloperRole;
    copy.hasSupportsDeveloperRole = source.hasSupportsDeveloperRole;
    return copy;
  }

  private static copyRetryPolicy(source: PluginAiRetryPolicy | undefined): PluginAiRetryPolicy | undefined {
    if (!source) { return undefined; }
    const copy = new PluginAiRetryPolicy();
    copy.mode = source.mode;
    copy.maxRetries = source.maxRetries;
    return copy;
  }

  private static copyProfile(source: PluginAiProfile): PluginAiProfile {
    const copy = new PluginAiProfile();
    copy.profileId = source.profileId;
    copy.name = source.name;
    copy.provider = source.provider;
    copy.baseUrl = source.baseUrl;
    copy.model = source.model;
    copy.maxTokens = source.maxTokens;
    copy.temperature = source.temperature;
    copy.credentialRef = source.credentialRef;
    copy.compat = PluginAiService.copyCompat(source.compat);
    copy.retryPolicy = PluginAiService.copyRetryPolicy(source.retryPolicy);
    return copy;
  }

  private static findProfile(binding: PluginAiBinding, profileId: string): PluginAiProfile | undefined {
    for (let index = 0; index < binding.profiles.length; index++) {
      if (binding.profiles[index].profileId === profileId) { return binding.profiles[index]; }
    }
    return undefined;
  }

  private static activeProfile(binding: PluginAiBinding): PluginAiProfile | undefined {
    if (binding.activeProfileId.length === 0) { return undefined; }
    return PluginAiService.findProfile(binding, binding.activeProfileId);
  }

  private static parseBinding(raw: string): PluginAiBinding {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(raw) as Record<string, Object>;
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '插件模型配置损坏，请清除模型绑定后重试');
    }
    if (parsed['version'] !== 2 || !Array.isArray(parsed['profiles'])) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '插件模型配置版本不兼容，请清除模型绑定后重试');
    }
    const source = parsed['profiles'] as Record<string, Object>[];
    if (source.length > MAX_PROFILES) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, `最多保存 ${MAX_PROFILES} 个服务商`);
    }
    const binding = new PluginAiBinding();
    const seen = new Set<string>();
    for (let index = 0; index < source.length; index++) {
      const item = source[index];
      const profile = new PluginAiProfile();
      profile.profileId = typeof item['profileId'] === 'string' ? item['profileId'] as string : '';
      profile.name = typeof item['name'] === 'string' ? item['name'] as string : '';
      profile.provider = typeof item['provider'] === 'string' ? item['provider'] as string : 'openai-compatible';
      profile.baseUrl = typeof item['baseUrl'] === 'string' ? item['baseUrl'] as string : '';
      profile.model = typeof item['model'] === 'string' ? item['model'] as string : '';
      profile.maxTokens = typeof item['maxTokens'] === 'number' ? item['maxTokens'] as number : 8192;
      profile.temperature = typeof item['temperature'] === 'number' ? item['temperature'] as number : 0.3;
      if (typeof item['credentialRef'] === 'string' && PluginAiService.isValidCredentialRef(item['credentialRef'] as string)) {
        profile.credentialRef = item['credentialRef'] as string;
      }
      const rawCompat = item['compat'] as Record<string, Object> | undefined;
      if (rawCompat && typeof rawCompat === 'object') {
        const compat = new PluginAiCompatConfig();
        if (typeof rawCompat['maxTokensField'] === 'string') { compat.maxTokensField = rawCompat['maxTokensField'] as string; }
        if (typeof rawCompat['thinkingFormat'] === 'string') { compat.thinkingFormat = rawCompat['thinkingFormat'] as string; }
        if (typeof rawCompat['supportsDeveloperRole'] === 'boolean') {
          compat.supportsDeveloperRole = rawCompat['supportsDeveloperRole'] as boolean;
          compat.hasSupportsDeveloperRole = true;
        }
        profile.compat = compat;
      }
      const rawRetry = item['retryPolicy'] as Record<string, Object> | undefined;
      if (rawRetry && typeof rawRetry === 'object') {
        const retry = new PluginAiRetryPolicy();
        if (typeof rawRetry['mode'] === 'string') { retry.mode = rawRetry['mode'] as string; }
        if (typeof rawRetry['maxRetries'] === 'number') { retry.maxRetries = rawRetry['maxRetries'] as number; }
        profile.retryPolicy = retry;
      }
      if (!PROFILE_ID_PATTERN.test(profile.profileId) || seen.has(profile.profileId) ||
        profile.baseUrl.length === 0 || profile.model.length === 0 ||
        (profile.provider !== 'openai-compatible' && profile.provider !== 'anthropic-compatible')) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '插件模型配置损坏，请清除模型绑定后重试');
      }
      seen.add(profile.profileId);
      binding.profiles.push(profile);
    }
    binding.activeProfileId = typeof parsed['activeProfileId'] === 'string'
      ? parsed['activeProfileId'] as string : '';
    if (binding.activeProfileId.length > 0 && !seen.has(binding.activeProfileId)) {
      binding.activeProfileId = binding.profiles.length > 0 ? binding.profiles[0].profileId : '';
    }
    return binding;
  }

  private static async persistBinding(pluginId: string, binding: PluginAiBinding): Promise<void> {
    const json = JSON.stringify(binding);
    if (json.length > MAX_BINDING_CHARS) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, '服务商配置空间不足，请删除不再使用的服务商');
    }
    await LexiStorageService.setSetting(PluginAiService.bindingKey(pluginId), json);
  }

  private static emptyBinding(): PluginAiBinding {
    return new PluginAiBinding();
  }

  /**
   * Reads the per-plugin binding. A legacy host-wide binding is migrated only for
   * the Harness plugin, so another plugin cannot claim a key it does not own.
   */
  private static async readBinding(pluginId: string, migrate: boolean): Promise<PluginAiBinding> {
    const raw = await LexiStorageService.getSetting(PluginAiService.bindingKey(pluginId), '');
    if (raw.length === 0) {
      return migrate ? PluginAiService.migrateLegacy(pluginId) : PluginAiService.emptyBinding();
    }
    return PluginAiService.parseBinding(raw);
  }

  private static async migrateLegacy(pluginId: string): Promise<PluginAiBinding> {
    if (pluginId !== DEFAULT_PLUGIN_ID) { return PluginAiService.emptyBinding(); }
    const raw = await LexiStorageService.getSetting(AI_CONFIG_KEY, '');
    if (raw.length === 0) { return PluginAiService.emptyBinding(); }
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(raw) as Record<string, Object>;
    } catch (error) {
      await LexiStorageService.deleteSetting(AI_CONFIG_KEY);
      return PluginAiService.emptyBinding();
    }
    const key = typeof parsed['apiKey'] === 'string' ? parsed['apiKey'] as string : '';
    const check = PluginAiService.checkKey(key);
    if (!check.ok) {
      await LexiStorageService.deleteSetting(AI_CONFIG_KEY);
      return PluginAiService.emptyBinding();
    }
    const profile = new PluginAiProfile();
    profile.profileId = 'legacy';
    profile.name = '';
    profile.provider = PluginAiService.normalizeProvider(
      typeof parsed['provider'] === 'string' ? parsed['provider'] as string : '') || 'openai-compatible';
    const legacyBase = typeof parsed['baseUrl'] === 'string' ? parsed['baseUrl'] as string : DEFAULT_BASE_URL;
    try {
      profile.baseUrl = PluginAiService.normalizeBaseUrl(legacyBase, true);
    } catch (error) {
      await LexiStorageService.deleteSetting(AI_CONFIG_KEY);
      return PluginAiService.emptyBinding();
    }
    profile.model = typeof parsed['model'] === 'string' && (parsed['model'] as string).length > 0
      ? parsed['model'] as string : DEFAULT_MODEL;
    profile.maxTokens = typeof parsed['maxTokens'] === 'number'
      ? Math.max(512, Math.min(32768, Math.floor(parsed['maxTokens'] as number))) : 8192;
    profile.temperature = typeof parsed['temperature'] === 'number'
      ? Math.max(0, Math.min(2, parsed['temperature'] as number)) : 0.3;
    profile.credentialRef = PluginAiService.defaultCredentialRef(profile.provider, profile.baseUrl, profile.profileId);
    const binding = new PluginAiBinding();
    binding.profiles.push(profile);
    binding.activeProfileId = profile.profileId;
    await PluginAiService.setSecret(pluginId, profile.profileId, check.value);
    try {
      await PluginAiService.persistBinding(pluginId, binding);
    } catch (error) {
      await PluginAiService.setSecret(pluginId, profile.profileId, '');
      return PluginAiService.emptyBinding();
    }
    await LexiStorageService.deleteSetting(AI_CONFIG_KEY);
    return binding;
  }

  private static async buildProfileSummary(pluginId: string, profile: PluginAiProfile): Promise<PluginAiProfileSummary> {
    const summary = new PluginAiProfileSummary();
    const resolved = await PluginAiService.resolveSecretInfo(pluginId, profile);
    const hasKey = resolved.secret.length > 0;
    const configured = profile.baseUrl.length > 0 && profile.model.length > 0 &&
      (!PluginAiService.needsApiKeyForUrl(profile.baseUrl) || hasKey);
    const masked = PluginAiService.maskCredential(resolved.secret);

    summary.profileId = profile.profileId;
    summary.name = profile.name;
    summary.provider = profile.provider;
    summary.baseUrl = profile.baseUrl;
    summary.model = profile.model;
    summary.maxTokens = profile.maxTokens;
    summary.temperature = profile.temperature;
    summary.balanceProvider = PluginAiQuota.provider(profile.baseUrl);
    summary.hasKey = hasKey;
    summary.configured = configured;
    summary.needsApiKey = !configured;
    summary.credentialRef = resolved.ref;
    summary.credentialSource = resolved.source;
    summary.credentialWritable = true;
    summary.maskedApiKey = masked;

    const cred = new PluginAiCredentialInfo();
    cred.ref = resolved.ref;
    cred.configured = hasKey;
    cred.source = resolved.source;
    cred.writable = true;
    cred.masked = masked;
    summary.credential = cred;

    summary.compat = PluginAiService.copyCompat(profile.compat);
    summary.retryPolicy = PluginAiService.copyRetryPolicy(profile.retryPolicy);
    return summary;
  }

  private static async publicStatus(pluginId: string, binding: PluginAiBinding): Promise<PluginAiStatus> {
    const profile = PluginAiService.activeProfile(binding);
    const status = new PluginAiStatus();
    if (!profile) {
      status.profileId = '';
      status.needsApiKey = true;
      return status;
    }
    const activeSummary = await PluginAiService.buildProfileSummary(pluginId, profile);
    const summaries: PluginAiProfileSummary[] = [];
    for (let i = 0; i < binding.profiles.length; i += 1) {
      summaries.push(await PluginAiService.buildProfileSummary(pluginId, binding.profiles[i]));
    }
    status.profileId = activeSummary.profileId;
    status.name = activeSummary.name;
    status.provider = activeSummary.provider;
    status.baseUrl = activeSummary.baseUrl;
    status.model = activeSummary.model;
    status.maxTokens = activeSummary.maxTokens;
    status.temperature = activeSummary.temperature;
    status.configured = activeSummary.configured;
    status.needsApiKey = activeSummary.needsApiKey;
    status.balanceProvider = activeSummary.balanceProvider;
    status.credentialRef = activeSummary.credentialRef;
    status.credentialSource = activeSummary.credentialSource;
    status.credentialWritable = true;
    status.maskedApiKey = activeSummary.maskedApiKey;
    status.credential = activeSummary.credential;
    status.compat = activeSummary.compat;
    status.retryPolicy = activeSummary.retryPolicy;
    status.profiles = summaries;
    return status;
  }

  private static serializeCredential(cred: PluginAiCredentialInfo): Record<string, Object> {
    const out: Record<string, Object> = {
      'ref': cred.ref,
      'configured': cred.configured,
      'writable': cred.writable
    };
    if (cred.source.length > 0) { out['source'] = cred.source; }
    if (cred.masked.length > 0) { out['masked'] = cred.masked; }
    return out;
  }

  private static serializeCompat(compat: PluginAiCompatConfig | undefined): Record<string, Object> | undefined {
    if (!compat) { return undefined; }
    const out: Record<string, Object> = {};
    if (compat.maxTokensField.length > 0) { out['maxTokensField'] = compat.maxTokensField; }
    if (compat.thinkingFormat.length > 0) { out['thinkingFormat'] = compat.thinkingFormat; }
    if (compat.hasSupportsDeveloperRole) { out['supportsDeveloperRole'] = compat.supportsDeveloperRole; }
    return Object.keys(out).length > 0 ? out : undefined;
  }

  private static serializeRetry(retry: PluginAiRetryPolicy | undefined): Record<string, Object> | undefined {
    if (!retry) { return undefined; }
    const out: Record<string, Object> = {};
    if (retry.mode.length > 0) { out['mode'] = retry.mode; }
    if (retry.maxRetries >= 0) { out['maxRetries'] = retry.maxRetries; }
    return Object.keys(out).length > 0 ? out : undefined;
  }

  private static serializeProfileSummary(item: PluginAiProfileSummary): Record<string, Object> {
    const out: Record<string, Object> = {
      'profileId': item.profileId,
      'name': item.name,
      'provider': item.provider,
      'baseUrl': item.baseUrl,
      'model': item.model,
      'maxTokens': item.maxTokens,
      'temperature': item.temperature,
      'balanceProvider': item.balanceProvider,
      'hasKey': item.hasKey,
      'configured': item.configured,
      'needsApiKey': item.needsApiKey,
      'credentialRef': item.credentialRef,
      'credentialSource': item.credentialSource,
      'credentialWritable': item.credentialWritable,
      'maskedApiKey': item.maskedApiKey,
      'credential': PluginAiService.serializeCredential(item.credential)
    };
    const compatObj = PluginAiService.serializeCompat(item.compat);
    if (compatObj) { out['compat'] = compatObj; }
    const retryObj = PluginAiService.serializeRetry(item.retryPolicy);
    if (retryObj) { out['retryPolicy'] = retryObj; }
    return out;
  }

  private static serializeStatus(status: PluginAiStatus): string {
    const profileObjs: Record<string, Object>[] = [];
    for (let i = 0; i < status.profiles.length; i += 1) {
      profileObjs.push(PluginAiService.serializeProfileSummary(status.profiles[i]));
    }
    const out: Record<string, Object> = {
      'configured': status.configured,
      'profileId': status.profileId,
      'name': status.name,
      'provider': status.provider,
      'baseUrl': status.baseUrl,
      'model': status.model,
      'maxTokens': status.maxTokens,
      'temperature': status.temperature,
      'balanceProvider': status.balanceProvider,
      'needsApiKey': status.needsApiKey,
      'credentialRef': status.credentialRef,
      'credentialSource': status.credentialSource,
      'credentialWritable': status.credentialWritable,
      'maskedApiKey': status.maskedApiKey,
      'credential': PluginAiService.serializeCredential(status.credential),
      'profiles': profileObjs
    };
    const compatObj = PluginAiService.serializeCompat(status.compat);
    if (compatObj) { out['compat'] = compatObj; }
    const retryObj = PluginAiService.serializeRetry(status.retryPolicy);
    if (retryObj) { out['retryPolicy'] = retryObj; }
    return JSON.stringify(out);
  }

  private static async statusOf(pluginId: string): Promise<string> {
    let binding: PluginAiBinding;
    try {
      binding = await PluginAiService.readBinding(pluginId, true);
    } catch (error) {
      // A corrupt record is still a per-plugin binding: report it as unconfigured so the
      // plugin does not mistake the host for an old single-binding host and fall back to
      // storing keys in plugin data. Subsequent writes surface the corruption explicitly.
      return PluginAiService.serializeStatus(new PluginAiStatus());
    }
    return PluginAiService.serializeStatus(await PluginAiService.publicStatus(pluginId, binding));
  }

  /**
   * Keeps the legacy provider blob out of the boot mirror. The page can still read it through
   * the storage RPC when it migrates, but the key is no longer handed to the page in
   * `boot.dataJson` before that migration runs.
   */
  static stripLegacyProviderData(dataJson: string): string {
    try {
      const parsed = JSON.parse(dataJson) as Record<string, Object>;
      const clean: Record<string, Object> = {};
      const keys = Object.keys(parsed);
      for (let index = 0; index < keys.length; index++) {
        if (keys[index] !== 'harness.providers.v1') { clean[keys[index]] = parsed[keys[index]]; }
      }
      return JSON.stringify(clean);
    } catch (error) {
      return dataJson;
    }
  }

  /** Legacy single-binding entry point. Harness RPCs use the `...For` methods with the session id. */
  static async status(): Promise<string> {
    return PluginAiService.statusOf(DEFAULT_PLUGIN_ID);
  }

  static async statusFor(pluginId: string): Promise<string> {
    return PluginAiService.statusOf(pluginId);
  }

  private static async resolveActive(pluginId: string): Promise<PluginAiActive> {
    const binding = await PluginAiService.readBinding(pluginId, true);
    const profile = PluginAiService.activeProfile(binding);
    if (!profile) {
      throw PluginErrors.raise(PluginErrorCode.MISSING_CREDENTIAL,
        '请先绑定模型服务：请在 Harness 面板中填写模型服务、模型名称与 API Key');
    }
    const resolved = await PluginAiService.resolveSecretInfo(pluginId, profile);
    const active = new PluginAiActive();
    active.profile = profile;
    if (resolved.secret.length === 0) {
      if (!PluginAiService.needsApiKeyForUrl(profile.baseUrl)) {
        active.key = '';
        return active;
      }
      throw PluginErrors.raise(PluginErrorCode.MISSING_CREDENTIAL,
        '此服务商缺少 API Key：请在 Harness 面板中补填');
    }
    const check = PluginAiService.checkKey(resolved.secret);
    if (!check.ok) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_CREDENTIAL,
        '此服务商的 API Key 含不可用于 HTTP 请求头的字符，请粘贴原始 Key');
    }
    active.key = check.value;
    return active;
  }

  /**
   * Saves/selects/removes one profile. `apiKey` is write-only: an empty value keeps
   * the stored key, and no reply carries it back.
   */
  static async configureFor(pluginId: string, paramsJson: string): Promise<string> {
    const params = PluginAiConfigureParams.from(paramsJson);
    if (params.clear) {
      await PluginAiService.clearFor(pluginId);
      return PluginAiService.statusOf(pluginId);
    }
    const binding = await PluginAiService.readBinding(pluginId, true);
    const action = params.action.trim().toLowerCase();
    if (action === 'select') {
      return PluginAiService.selectProfile(pluginId, binding, params.profileId);
    }
    if (action === 'clearcredential') {
      const targetId = params.profileId.trim().length > 0 ? params.profileId.trim() : binding.activeProfileId;
      if (targetId.length === 0 || !PluginAiService.findProfile(binding, targetId)) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '服务商不存在，请刷新后重试');
      }
      await PluginAiService.setSecret(pluginId, targetId, '');
      PluginAiService.balanceCache.delete(`${pluginId}:${targetId}`);
      return PluginAiService.statusOf(pluginId);
    }
    if (action === 'remove' || params.remove) {
      return PluginAiService.removeProfile(pluginId, binding, params.profileId);
    }
    return PluginAiService.saveProfile(pluginId, binding, params);
  }

  /** Legacy single-binding entry point. */
  static async configure(paramsJson: string): Promise<string> {
    return PluginAiService.configureFor(DEFAULT_PLUGIN_ID, paramsJson);
  }

  private static async selectProfile(pluginId: string, binding: PluginAiBinding,
    profileId: string): Promise<string> {
    const id = profileId.trim();
    if (id.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少服务商标识');
    }
    const profile = PluginAiService.findProfile(binding, id);
    if (!profile) {
      throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '服务商不存在，请刷新后重试');
    }
    const resolved = await PluginAiService.resolveSecretInfo(pluginId, profile);
    if (PluginAiService.needsApiKeyForUrl(profile.baseUrl) && resolved.secret.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.MISSING_CREDENTIAL,
        '请先编辑此服务商补填 API Key');
    }
    binding.activeProfileId = id;
    await PluginAiService.persistBinding(pluginId, binding);
    PluginAiService.balanceCache.delete(`${pluginId}:${id}`);
    return PluginAiService.statusOf(pluginId);
  }

  private static async removeProfile(pluginId: string, binding: PluginAiBinding,
    profileId: string): Promise<string> {
    const id = profileId.trim();
    if (id.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少服务商标识');
    }
    const profile = PluginAiService.findProfile(binding, id);
    if (!profile) {
      throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '服务商不存在，请刷新后重试');
    }
    const next: PluginAiProfile[] = [];
    for (let index = 0; index < binding.profiles.length; index++) {
      if (binding.profiles[index].profileId !== id) { next.push(binding.profiles[index]); }
    }
    binding.profiles = next;
    await PluginAiService.setSecret(pluginId, id, '');
    if (binding.activeProfileId === id) {
      binding.activeProfileId = next.length > 0 ? next[0].profileId : '';
    }
    await PluginAiService.persistBinding(pluginId, binding);
    PluginAiService.balanceCache.delete(`${pluginId}:${id}`);
    return PluginAiService.statusOf(pluginId);
  }

  private static async saveProfile(pluginId: string, binding: PluginAiBinding,
    params: PluginAiConfigureParams): Promise<string> {
    const requestedId = params.profileId.trim();
    let profileId = requestedId;
    if (profileId.length === 0) {
      profileId = binding.activeProfileId.length > 0 && params.action !== 'create'
        ? binding.activeProfileId
        : `service_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e9).toString(36)}`;
    }
    if (!PROFILE_ID_PATTERN.test(profileId)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '服务商标识非法');
    }
    const existing = PluginAiService.findProfile(binding, profileId);
    const creating = existing === undefined;
    if (creating && binding.profiles.length >= MAX_PROFILES) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, `最多保存 ${MAX_PROFILES} 个服务商`);
    }
    const profile = creating ? new PluginAiProfile() : PluginAiService.copyProfile(existing as PluginAiProfile);
    profile.profileId = profileId;
    if (creating) {
      profile.provider = 'openai-compatible';
      profile.maxTokens = 8192;
      profile.temperature = 0.3;
    }
    if (params.name.length > 0 || creating) {
      profile.name = params.name.trim();
      if (profile.name.length > 64) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '服务商名称最多 64 字符');
      }
    }
    if (params.provider.length > 0) {
      const provider = PluginAiService.normalizeProvider(params.provider);
      if (provider.length === 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
          '模型服务类型只能是 openai-compatible 或 anthropic-compatible');
      }
      profile.provider = provider;
    }
    let baseUrlChanged = false;
    if (params.baseUrl.length > 0) {
      const nextBaseUrl = PluginAiService.normalizeBaseUrl(params.baseUrl, false);
      baseUrlChanged = !creating && nextBaseUrl !== profile.baseUrl;
      profile.baseUrl = nextBaseUrl;
    }

    if (params.hasCredentialRef) {
      const ref = params.credentialRef.trim();
      if (ref.length > 0) {
        if (!PluginAiService.isValidCredentialRef(ref)) {
          throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
            'credentialRef 需为合法的环境变量名（^[A-Za-z_][A-Za-z0-9_]*$）');
        }
        profile.credentialRef = ref;
      } else {
        profile.credentialRef = '';
      }
    }
    if (profile.credentialRef.length === 0 && profile.baseUrl.length > 0) {
      profile.credentialRef = PluginAiService.defaultCredentialRef(profile.provider, profile.baseUrl, profile.profileId);
    }

    const effectiveKey = params.apiKey === '__KEEP__' ? '' : params.apiKey;
    const check = PluginAiService.checkKey(effectiveKey);
    if (effectiveKey.length > 0 && !check.ok) {
      throw PluginErrors.raise(
        check.reason === 'illegalCharacters' ? PluginErrorCode.INVALID_CREDENTIAL : PluginErrorCode.INVALID_ARGUMENT,
        check.reason === 'blank' ? 'API Key 不能为空白字符'
          : check.reason === 'wrappedQuotes' ? '请去掉 API Key 首尾的引号'
          : check.reason === 'envLine' ? '请只粘贴 API Key 值本身，不要包含 ENV_VAR= 前缀'
          : 'API Key 含不可用于 HTTP 请求头的字符，请粘贴原始 Key'
      );
    }
    const resolvedRefForEnv = profile.credentialRef.length > 0
      ? profile.credentialRef
      : PluginAiService.defaultCredentialRef(profile.provider, profile.baseUrl, profile.profileId);
    const envFallback = PluginAiService.resolveEnvSecret(resolvedRefForEnv);
    if (!params.clearApiKey && creating && PluginAiService.needsApiKeyForUrl(profile.baseUrl) && !check.ok && envFallback.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.MISSING_CREDENTIAL, '首次绑定需要填写 API Key');
    }
    const existingStored = !creating ? await PluginAiService.getSecret(pluginId, profileId) : '';
    if (!params.clearApiKey && !creating && baseUrlChanged && existingStored.length > 0 && !check.ok) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '更换 Base URL 时请重新填写 API Key');
    }

    if (profile.baseUrl.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '请填写 Base URL');
    }
    if (params.model.length > 0) {
      const model = params.model.trim();
      if (model.length === 0 || model.length > 128) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '模型名称长度必须在 1-128 之间');
      }
      profile.model = model;
    } else if (profile.model.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '请填写模型名称');
    }
    if (params.maxTokens > 0) {
      profile.maxTokens = Math.max(512, Math.min(32768, Math.floor(params.maxTokens)));
    }
    if (params.temperature >= 0) {
      profile.temperature = Math.max(0, Math.min(2, params.temperature));
    }

    if (params.compat) {
      const nextCompat = PluginAiService.copyCompat(profile.compat) ?? new PluginAiCompatConfig();
      const field = params.compat.maxTokensField.trim();
      if (field === 'max_tokens' || field === 'max_completion_tokens') {
        nextCompat.maxTokensField = field;
      } else if (field.length > 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
          'compat.maxTokensField 只能为 max_tokens 或 max_completion_tokens');
      }
      const tf = params.compat.thinkingFormat.trim().toLowerCase();
      if (tf.length > 0) {
        if (tf === 'auto' || tf === 'openai' || tf === 'deepseek' || tf === 'openrouter' ||
          tf === 'zai' || tf === 'qwen' || tf === 'chat-template') {
          nextCompat.thinkingFormat = tf;
        } else {
          throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `不支持的 compat.thinkingFormat：${tf}`);
        }
      }
      if (params.compat.hasSupportsDeveloperRole) {
        nextCompat.supportsDeveloperRole = params.compat.supportsDeveloperRole;
        nextCompat.hasSupportsDeveloperRole = true;
      }
      profile.compat = (nextCompat.maxTokensField.length > 0 || nextCompat.thinkingFormat.length > 0 || nextCompat.hasSupportsDeveloperRole)
        ? nextCompat : undefined;
    }

    if (params.retryPolicy) {
      const nextRetry = PluginAiService.copyRetryPolicy(profile.retryPolicy) ?? new PluginAiRetryPolicy();
      const mode = params.retryPolicy.mode.trim().toLowerCase();
      if (mode === 'normal' || mode === 'off') {
        nextRetry.mode = mode;
      } else if (mode.length > 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'retryPolicy.mode 只能为 normal 或 off');
      }
      if (params.retryPolicy.maxRetries >= 0) {
        nextRetry.maxRetries = Math.max(0, Math.min(3, Math.floor(params.retryPolicy.maxRetries)));
      }
      profile.retryPolicy = (nextRetry.mode.length > 0 || nextRetry.maxRetries >= 0) ? nextRetry : undefined;
    }

    if (creating) {
      binding.profiles.push(profile);
    } else {
      for (let index = 0; index < binding.profiles.length; index++) {
        if (binding.profiles[index].profileId === profileId) {
          binding.profiles[index] = profile;
          break;
        }
      }
    }
    if (params.select || binding.activeProfileId.length === 0) {
      binding.activeProfileId = profileId;
    }
    const previousKey = (params.clearApiKey || check.ok) ? await PluginAiService.getSecret(pluginId, profileId) : '';
    let wroteKey = false;
    if (params.clearApiKey && !check.ok) {
      await PluginAiService.setSecret(pluginId, profileId, '');
      wroteKey = true;
    } else if (check.ok) {
      await PluginAiService.setSecret(pluginId, profileId, check.value);
      wroteKey = true;
    }
    try {
      await PluginAiService.persistBinding(pluginId, binding);
    } catch (failure) {
      if (wroteKey) { await PluginAiService.setSecret(pluginId, profileId, previousKey); }
      throw PluginErrors.raise(PluginErrors.codeOf(failure), PluginErrors.messageOf(failure));
    }
    PluginAiService.balanceCache.delete(`${pluginId}:${profileId}`);
    return PluginAiService.statusOf(pluginId);
  }

  /** Removes every profile and secret owned by one plugin. Used by uninstall. */
  static async clear(pluginId: string): Promise<void> {
    await PluginAiService.clearFor(pluginId);
  }

  private static async clearFor(pluginId: string): Promise<void> {
    let binding: PluginAiBinding;
    try {
      binding = await PluginAiService.readBinding(pluginId, false);
    } catch (error) {
      binding = PluginAiService.emptyBinding();
    }
    for (let index = 0; index < binding.profiles.length; index++) {
      await PluginAiService.setSecret(pluginId, binding.profiles[index].profileId, '');
    }
    await LexiStorageService.setSetting(PluginAiService.bindingKey(pluginId), '');
    if (pluginId === DEFAULT_PLUGIN_ID) {
      await LexiStorageService.deleteSetting(AI_CONFIG_KEY);
    }
  }

  private static normalizeProvider(raw: string): string {
    const value = raw.trim().toLowerCase();
    if (value === 'openai-compatible' || value === 'deepseek-openai' || value === 'openai') {
      return 'openai-compatible';
    }
    if (value === 'anthropic-compatible' || value === 'deepseek-anthropic' || value === 'anthropic') {
      return 'anthropic-compatible';
    }
    return '';
  }

  private static isAnthropic(profile: PluginAiProfile): boolean {
    if (profile.provider === 'anthropic-compatible') { return true; }
    const url = profile.baseUrl.toLowerCase();
    return url.includes('/anthropic') || url.endsWith('/v1/messages');
  }

  private static endpointUrl(profile: PluginAiProfile): string {
    const base = (profile.baseUrl.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
    if (PluginAiService.isAnthropic(profile)) {
      if (base.endsWith('/v1/messages')) { return base; }
      if (/\/v\d+$/.test(base)) { return `${base}/messages`; }
      return `${base}/v1/messages`;
    }
    if (base.endsWith('/chat/completions')) { return base; }
    if (/\/v\d+$/.test(base)) { return `${base}/chat/completions`; }
    return `${base}/v1/chat/completions`;
  }

  private static checkKey(raw: string): PluginAiKeyCheck {
    const result = new PluginAiKeyCheck();
    if (raw.length === 0) { result.reason = 'empty'; return result; }
    const value = raw.trim();
    if (value.length === 0) { result.reason = 'blank'; return result; }
    if (value.length > 8192) { result.reason = 'tooLong'; return result; }
    if (((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'")) ||
      (value.startsWith('`') && value.endsWith('`'))) && value.length >= 2) {
      result.reason = 'wrappedQuotes';
      return result;
    }
    if (ENV_LINE_PATTERN.test(value)) {
      result.reason = 'envLine';
      return result;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code < 0x21 || code > 0x7e) { result.reason = 'illegalCharacters'; return result; }
    }
    result.ok = true;
    result.value = value;
    return result;
  }

  private static isPrivateHost(host: string): boolean {
    let name = host.trim().toLowerCase();
    if (name.startsWith('[')) {
      const end = name.indexOf(']');
      if (end < 0) { return false; }
      const rest = name.substring(end + 1);
      if (rest.length > 0 && !/^:\d+$/.test(rest)) { return false; }
      const address = name.substring(0, end + 1);
      return address === '[::1]' || address.startsWith('[fe80:') || address.startsWith('[fc') || address.startsWith('[fd');
    }
    const colon = name.lastIndexOf(':');
    if (colon > 0 && name.indexOf(':') === colon) { name = name.substring(0, colon); }
    if (name === 'localhost' || name === '0.0.0.0' || name === 'host.docker.internal') {
      return true;
    }
    if (PluginAiService.isPrivateIPv4(name)) { return true; }
    return name.endsWith('.local');
  }

  /** Exact dotted-quad check; a prefix test would accept `127.0.0.1.evil.test`. */
  private static isPrivateIPv4(host: string): boolean {
    const parts = host.split('.');
    if (parts.length !== 4) { return false; }
    const values: number[] = [];
    for (let index = 0; index < parts.length; index++) {
      if (!/^\d{1,3}$/.test(parts[index])) { return false; }
      const value = Number(parts[index]);
      if (!Number.isFinite(value) || value < 0 || value > 255) { return false; }
      values.push(value);
    }
    if (values[0] === 127 || values[0] === 10) { return true; }
    if (values[0] === 192 && values[1] === 168) { return true; }
    return values[0] === 172 && values[1] >= 16 && values[1] <= 31;
  }

  private static normalizeBaseUrl(raw: string, allowInsecure: boolean): string {
    const value = raw.trim().replace(/\/+$/, '');
    if (value.length === 0 || value.length > 8192) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
        'Base URL 需为完整的 http(s) 地址，最多 8192 字符');
    }
    const match = /^(https?):\/\/([^\s/?#@]+)(\/[^\s?#]*)?$/i.exec(value);
    if (!match) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
        'Base URL 需为完整的 http(s) 地址，不含账号、查询参数或片段');
    }
    const scheme = match[1].toLowerCase();
    const host = match[2];
    if (scheme === 'https') { return value; }
    if (allowInsecure || PluginAiService.isPrivateHost(host)) { return value; }
    throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
      '公网 Base URL 必须使用 https://；本地或局域网地址可使用 http://');
  }

  private static redact(text: string, key: string): string {
    let output = text;
    if (key.length > 0) { output = output.split(key).join('[redacted]'); }
    output = output.replace(/sk-[A-Za-z0-9_-]{8,}/g, 'sk-[redacted]');
    output = output.replace(/Bearer\s+[^\s,;]+/g, 'Bearer [redacted]');
    output = output.replace(/x-api-key\s*[:=]\s*[^\s,;]+/gi, 'x-api-key: [redacted]');
    return output;
  }

  private static errorDetail(raw: string, key: string): string {
    if (!raw || raw.length === 0) { return '模型服务返回空响应'; }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const error = parsed['error'] as Record<string, Object> | undefined;
      if (error && typeof error['message'] === 'string') {
        return PluginAiService.redact((error['message'] as string).substring(0, 300), key);
      }
      if (typeof parsed['message'] === 'string') {
        return PluginAiService.redact((parsed['message'] as string).substring(0, 300), key);
      }
    } catch (error) {
      // Fall through to the raw prefix.
    }
    return PluginAiService.redact(raw.substring(0, 300), key);
  }

  private static chatHeaders(profile: PluginAiProfile, key: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': USER_AGENT
    };
    if (PluginAiService.isAnthropic(profile)) {
      if (key.length > 0) { headers['x-api-key'] = key; }
      headers['anthropic-version'] = '2023-06-01';
    } else if (key.length > 0) {
      headers['Authorization'] = `Bearer ${key}`;
    }
    return headers;
  }

  private static retryLimit(policy: PluginAiRetryPolicy | undefined): number {
    if (!policy) { return 0; }
    const mode = policy.mode.trim().toLowerCase();
    if (mode !== 'normal') { return 0; }
    const count = policy.maxRetries >= 0 ? policy.maxRetries : 1;
    return Math.max(0, Math.min(3, Math.floor(count)));
  }

  private static async sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => { resolve(); }, ms);
    });
  }

  /** Runs one model turn. Returns a `PluginAiReply` JSON document. */
  static async chatFor(pluginId: string, paramsJson: string): Promise<string> {
    const params = PluginAiChatParams.from(paramsJson);
    if (params.messages.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'ai.chat 需要至少一条消息');
    }
    if (params.messages.length > PluginLimits.MAX_AI_MESSAGES) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_MESSAGES} 条消息`);
    }
    if (params.tools.length > PluginLimits.MAX_AI_TOOLS) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_TOOLS} 个工具`);
    }
    // Dynamic per-request resolution so key changes apply on the next turn.
    const active = await PluginAiService.resolveActive(pluginId);
    PluginAiService.normalizeBaseUrl(active.profile.baseUrl, false);
    const anthropic = PluginAiService.isAnthropic(active.profile);
    const headers = PluginAiService.chatHeaders(active.profile, active.key);
    const endpoint = PluginAiService.endpointUrl(active.profile);
    const body = PluginAiService.buildBody(active.profile, params);
    const maxRetries = PluginAiService.retryLimit(active.profile.retryPolicy);

    let attempt = 0;
    while (true) {
      const request = http.createHttp();
      let rawText = '';
      try {
        const response = await request.request(endpoint, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 20000,
          readTimeout: 120000,
          usingCache: false
        });
        rawText = typeof response.result === 'string'
          ? response.result
          : JSON.stringify(response.result);
        const code = response.responseCode;
        const retryableStatus = code === 429 || code === 502 || code === 503 || code === 504;
        if (retryableStatus && attempt < maxRetries) {
          attempt += 1;
          await PluginAiService.sleepMs(150 * attempt);
          continue;
        }
        if (code < 200 || code >= 300) {
          throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
            `模型接口返回 HTTP ${code}：${PluginAiService.errorDetail(rawText, active.key)}`);
        }
        const reply = anthropic
          ? PluginAiService.parseAnthropic(rawText, active.profile)
          : PluginAiService.parseOpenAi(rawText, active.profile);
        return JSON.stringify(reply);
      } catch (error) {
        const code = PluginErrors.codeOf(error);
        if (code === PluginErrorCode.UNKNOWN && attempt < maxRetries) {
          attempt += 1;
          await PluginAiService.sleepMs(150 * attempt);
          continue;
        }
        const message = PluginAiService.redact(PluginErrors.messageOf(error), active.key);
        if (code !== PluginErrorCode.UNKNOWN) {
          throw PluginErrors.raise(code, message);
        }
        throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
          `访问模型服务失败：${PluginAiService.redact(PluginErrors.rawOf(error), active.key)}`);
      } finally {
        try { request.destroy(); } catch (error) { /* teardown must not throw */ }
      }
    }
  }

  /** Legacy single-binding entry point. */
  static async chat(paramsJson: string): Promise<string> {
    return PluginAiService.chatFor(DEFAULT_PLUGIN_ID, paramsJson);
  }

  private static emptySchema(): Record<string, Object> {
    const properties: Record<string, Object> = {};
    const required: string[] = [];
    const schema: Record<string, Object> = {
      'type': 'object',
      'properties': properties,
      'required': required
    };
    return schema;
  }

  private static openAiTools(tools: Record<string, Object>[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < tools.length; index++) {
      const tool = tools[index];
      const name = typeof tool['name'] === 'string' ? (tool['name'] as string) : '';
      if (name.length === 0) { continue; }
      const description = typeof tool['description'] === 'string' ? (tool['description'] as string) : '';
      const schema = tool['parameters'] !== undefined && tool['parameters'] !== null
        ? tool['parameters'] as Object : PluginAiService.emptySchema();
      const fn: Record<string, Object> = {
        'name': name,
        'description': description,
        'parameters': schema
      };
      list.push({ 'type': 'function', 'function': fn });
    }
    return list;
  }

  private static toolCallsOf(message: Record<string, Object>): Record<string, Object>[] {
    const raw = message['toolCalls'];
    if (!Array.isArray(raw)) { return []; }
    const calls: Record<string, Object>[] = [];
    const source = raw as Record<string, Object>[];
    for (let index = 0; index < source.length; index++) {
      const call = source[index];
      const id = typeof call['id'] === 'string' ? (call['id'] as string) : `call_${index}`;
      const name = typeof call['name'] === 'string' ? (call['name'] as string) : '';
      if (name.length === 0) { continue; }
      const args = typeof call['arguments'] === 'string' ? (call['arguments'] as string) : '{}';
      const wire: Record<string, Object> = { 'name': name, 'arguments': args.length > 0 ? args : '{}' };
      calls.push({ 'id': id, 'type': 'function', 'function': wire });
    }
    return calls;
  }

  private static openAiMessages(messages: Record<string, Object>[],
    supportsDeveloperRole: boolean = false): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    const systemRole = supportsDeveloperRole ? 'developer' : 'system';
    for (let index = 0; index < messages.length; index++) {
      const message = messages[index];
      const role = typeof message['role'] === 'string' ? (message['role'] as string) : 'user';
      const content = typeof message['content'] === 'string' ? (message['content'] as string) : '';
      if (role === 'assistant') {
        const entry: Record<string, Object> = { 'role': 'assistant', 'content': content };
        const calls = PluginAiService.toolCallsOf(message);
        if (calls.length > 0) { entry['tool_calls'] = calls; }
        list.push(entry);
      } else if (role === 'tool') {
        const toolCallId = typeof message['toolCallId'] === 'string'
          ? message['toolCallId'] as string : '';
        list.push({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': content.length > 0 ? content : 'Done'
        });
      } else {
        list.push({ 'role': role === 'system' ? systemRole : 'user', 'content': content });
      }
    }
    return list;
  }

  private static anthropicTools(tools: Record<string, Object>[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < tools.length; index++) {
      const tool = tools[index];
      const name = typeof tool['name'] === 'string' ? (tool['name'] as string) : '';
      if (name.length === 0) { continue; }
      const description = typeof tool['description'] === 'string' ? (tool['description'] as string) : '';
      const schema = tool['parameters'] !== undefined && tool['parameters'] !== null
        ? tool['parameters'] as Object : PluginAiService.emptySchema();
      list.push({ 'name': name, 'description': description, 'input_schema': schema });
    }
    return list;
  }

  private static anthropicMessages(messages: Record<string, Object>[],
    systemParts: string[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < messages.length; index++) {
      const message = messages[index];
      const role = typeof message['role'] === 'string' ? (message['role'] as string) : 'user';
      const content = typeof message['content'] === 'string' ? (message['content'] as string) : '';
      if (role === 'system') {
        if (content.trim().length > 0) { systemParts.push(content); }
        continue;
      }
      if (role === 'assistant') {
        const blocks: Record<string, Object>[] = [];
        if (content.length > 0) { blocks.push({ 'type': 'text', 'text': content }); }
        const rawCalls = message['toolCalls'];
        if (Array.isArray(rawCalls)) {
          const calls = rawCalls as Record<string, Object>[];
          for (let callIndex = 0; callIndex < calls.length; callIndex++) {
            const call = calls[callIndex];
            const id = typeof call['id'] === 'string' ? (call['id'] as string) : `toolu_${callIndex}`;
            const name = typeof call['name'] === 'string' ? (call['name'] as string) : '';
            if (name.length === 0) { continue; }
            const argsText = typeof call['arguments'] === 'string' ? (call['arguments'] as string) : '{}';
            let input: Record<string, Object> = {};
            try {
              input = JSON.parse(argsText.length > 0 ? argsText : '{}') as Record<string, Object>;
            } catch (error) {
              input = {};
            }
            blocks.push({ 'type': 'tool_use', 'id': id, 'name': name, 'input': input });
          }
        }
        if (blocks.length > 0) { list.push({ 'role': 'assistant', 'content': blocks }); }
        continue;
      }
      const block: Record<string, Object> = role === 'tool'
        ? {
            'type': 'tool_result',
            'tool_use_id': typeof message['toolCallId'] === 'string' ? (message['toolCallId'] as string) : '',
            'content': content.length > 0 ? content : 'OK',
            'is_error': message['isError'] === true
          }
        : { 'type': 'text', 'text': content };
      const previous = list.length > 0 ? list[list.length - 1] : undefined;
      if (previous !== undefined && previous['role'] === 'user' && Array.isArray(previous['content'])) {
        const merged = previous['content'] as Record<string, Object>[];
        if (role === 'tool') {
          merged.unshift(block);
        } else {
          merged.push(block);
        }
      } else {
        list.push({ 'role': 'user', 'content': [block] });
      }
    }
    return list;
  }

  private static buildBody(profile: PluginAiProfile, params: PluginAiChatParams): string {
    const anthropic = PluginAiService.isAnthropic(profile);
    const systemParts: string[] = [];
    const supportsDev = profile.compat !== undefined && profile.compat.supportsDeveloperRole === true;
    const messages = anthropic
      ? PluginAiService.anthropicMessages(params.messages, systemParts)
      : PluginAiService.openAiMessages(params.messages, supportsDev);
    const maxTokens = params.maxTokens > 0
      ? Math.max(512, Math.min(profile.maxTokens, Math.floor(params.maxTokens)))
      : profile.maxTokens;
    const temperature = params.temperature >= 0 ? params.temperature : profile.temperature;
    if (anthropic) {
      const payload: Record<string, Object> = {
        'model': profile.model,
        'max_tokens': Math.max(1024, Math.min(64000, maxTokens)),
        'messages': messages
      };
      if (systemParts.length > 0) { payload['system'] = systemParts.join('\n\n'); }
      if (temperature >= 0) { payload['temperature'] = temperature; }
      const tools = PluginAiService.anthropicTools(params.tools);
      if (tools.length > 0) { payload['tools'] = tools; }
      return JSON.stringify(payload);
    }
    const maxTokensField = profile.compat !== undefined && profile.compat.maxTokensField === 'max_completion_tokens'
      ? 'max_completion_tokens' : 'max_tokens';
    const payload: Record<string, Object> = {
      'model': profile.model,
      'messages': messages,
      'stream': false,
      'temperature': temperature
    };
    payload[maxTokensField] = Math.max(512, Math.min(32768, maxTokens));
    const tools = PluginAiService.openAiTools(params.tools);
    if (tools.length > 0) { payload['tools'] = tools; }
    return JSON.stringify(payload);
  }

  private static parseOpenAi(raw: string, profile: PluginAiProfile): PluginAiReply {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const choices = parsed['choices'] as Record<string, Object>[] | undefined;
    if (!Array.isArray(choices) || choices.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, '模型返回为空（choices 缺失）');
    }
    const choice = choices[0];
    const reply = new PluginAiReply();
    reply.model = profile.model;
    const message = choice['message'] as Record<string, Object> | undefined;
    if (message) {
      if (typeof message['content'] === 'string') { reply.text = message['content'] as string; }
      if (typeof message['reasoning_content'] === 'string') {
        reply.reasoning = message['reasoning_content'] as string;
      }
      const calls = message['tool_calls'] as Record<string, Object>[] | undefined;
      if (Array.isArray(calls)) {
        for (let index = 0; index < calls.length; index++) {
          const call = calls[index];
          const fn = call['function'] as Record<string, Object> | undefined;
          if (!fn) { continue; }
          const toolCall = new PluginAiToolCall();
          toolCall.id = typeof call['id'] === 'string' ? (call['id'] as string) : `call_${index}`;
          toolCall.name = typeof fn['name'] === 'string' ? (fn['name'] as string) : '';
          toolCall.arguments = typeof fn['arguments'] === 'string' ? (fn['arguments'] as string) : '{}';
          if (toolCall.name.length > 0) { reply.toolCalls.push(toolCall); }
        }
      }
    }
    const finish = choice['finish_reason'];
    if (typeof finish === 'string') {
      reply.finishReason = finish === 'length' ? 'max-tokens' : finish;
    }
    const usage = parsed['usage'] as Record<string, Object> | undefined;
    if (usage) {
      if (typeof usage['prompt_tokens'] === 'number') { reply.usage.inputTokens = usage['prompt_tokens'] as number; }
      if (typeof usage['completion_tokens'] === 'number') { reply.usage.outputTokens = usage['completion_tokens'] as number; }
    }
    return reply;
  }

  private static parseAnthropic(raw: string, profile: PluginAiProfile): PluginAiReply {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const reply = new PluginAiReply();
    reply.model = profile.model;
    const content = parsed['content'] as Record<string, Object>[] | undefined;
    if (Array.isArray(content)) {
      for (let index = 0; index < content.length; index++) {
        const block = content[index];
        const type = typeof block['type'] === 'string' ? (block['type'] as string) : '';
        if (type === 'text' && typeof block['text'] === 'string') {
          const text = block['text'] as string;
          reply.text = reply.text.length > 0 ? `${reply.text}\n${text}` : text;
        } else if (type === 'thinking' && typeof block['thinking'] === 'string') {
          reply.reasoning = block['thinking'] as string;
        } else if (type === 'tool_use') {
          const call = new PluginAiToolCall();
          call.id = typeof block['id'] === 'string' ? (block['id'] as string) : `toolu_${index}`;
          call.name = typeof block['name'] === 'string' ? (block['name'] as string) : '';
          call.arguments = JSON.stringify(block['input'] !== undefined ? block['input'] : {});
          if (call.name.length > 0) { reply.toolCalls.push(call); }
        }
      }
    }
    const stop = parsed['stop_reason'];
    if (typeof stop === 'string') {
      reply.finishReason = stop === 'tool_use' ? 'tool_calls' : (stop === 'max_tokens' ? 'max-tokens' : stop);
    }
    const usage = parsed['usage'] as Record<string, Object> | undefined;
    if (usage) {
      if (typeof usage['input_tokens'] === 'number') { reply.usage.inputTokens = usage['input_tokens'] as number; }
      if (typeof usage['output_tokens'] === 'number') { reply.usage.outputTokens = usage['output_tokens'] as number; }
    }
    return reply;
  }

  /** Bounded GET using the active binding only; no plugin-supplied URL or headers. */
  private static async readJson(profile: PluginAiProfile, key: string,
    endpoint: string, quota: boolean): Promise<string> {
    PluginAiService.normalizeBaseUrl(profile.baseUrl, false);
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'User-Agent': USER_AGENT
    };
    if (key.length > 0) {
      if (quota && PluginAiQuota.provider(profile.baseUrl) === 'GLM Coding Plan') {
        headers['Authorization'] = key;
      } else if (quota) {
        headers['Authorization'] = `Bearer ${key}`;
      } else if (PluginAiService.isAnthropic(profile)) {
        headers['x-api-key'] = key;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = `Bearer ${key}`;
      }
    }
    const request = http.createHttp();
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        // Never reflect a credential-bearing provider response into the plugin UI.
        throw new Error(`HTTP ${response.responseCode}，请检查服务地址、API Key 和套餐权限`);
      }
      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (raw.length > 2 * 1024 * 1024) { throw new Error('服务响应过大'); }
      return raw;
    } catch (error) {
      const detail = PluginAiService.redact(PluginErrors.rawOf(error), key);
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, `查询失败：${detail.substring(0, 240)}`);
    } finally {
      try { request.destroy(); } catch (error) { /* teardown must not mask the result */ }
    }
  }

  static async modelsFor(pluginId: string): Promise<string> {
    const active = await PluginAiService.resolveActive(pluginId);
    const endpoint = PluginAiService.endpointUrl(active.profile)
      .replace(/\/(?:chat\/completions|messages)$/, '/models');
    const raw = await PluginAiService.readJson(active.profile, active.key, endpoint, false);
    try {
      const body = JSON.parse(raw) as Record<string, Object>;
      const data = body['data'] as Record<string, Object>[];
      if (!Array.isArray(data)) { throw new Error('模型列表缺少 data'); }
      const models: string[] = [];
      for (let index = 0; index < data.length; index++) {
        const id = data[index]['id'];
        if (typeof id === 'string' && (id as string).trim().length > 0 &&
          (id as string).length <= 128 && !models.includes(id as string)) {
          models.push(id as string);
        }
        if (models.length >= 300) { break; }
      }
      return JSON.stringify(models);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
        '无法读取模型列表；可在模型设置中手动添加常用模型');
    }
  }

  static async models(): Promise<string> {
    return PluginAiService.modelsFor(DEFAULT_PLUGIN_ID);
  }

  static async balanceFor(pluginId: string): Promise<string> {
    const active = await PluginAiService.resolveActive(pluginId);
    const provider = PluginAiQuota.provider(active.profile.baseUrl);
    if (!provider) { return JSON.stringify(new PluginAiBalance()); }
    const cacheKey = `${pluginId}:${active.profile.profileId}`;
    const cached = PluginAiService.balanceCache.get(cacheKey);
    if (cached && Date.now() - cached.updatedAt < 60000) { return JSON.stringify(cached); }
    const raw = await PluginAiService.readJson(active.profile, active.key,
      PluginAiQuota.endpoint(active.profile.baseUrl), true);
    try {
      const balance = PluginAiQuota.parse(provider, raw);
      PluginAiService.balanceCache.set(cacheKey, balance);
      return JSON.stringify(balance);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
        '未能读取余额或套餐额度，请检查 Key 类型和套餐权限');
    }
  }

  static async balance(): Promise<string> {
    return PluginAiService.balanceFor(DEFAULT_PLUGIN_ID);
  }
}
