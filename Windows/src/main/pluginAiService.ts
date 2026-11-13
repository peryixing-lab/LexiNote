import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { dirname, join } from 'node:path';
import {
  type PluginAiBalance,
  type PluginAiQuotaWindow,
  type PluginAiStatus,
  PluginErrorCode,
  PluginLimits,
  codeOfPluginError,
  messageOfPluginError,
  raisePluginError,
  rawPluginErrorText
} from '../shared/pluginTypes';

interface PluginAiProfile {
  profileId: string;
  name: string;
  provider: 'openai-compatible' | 'anthropic-compatible';
  baseUrl: string;
  model: string;
  maxTokens: number;
  temperature: number;
}

interface PluginAiBinding {
  version: 2;
  activeProfileId: string;
  profiles: PluginAiProfile[];
}

interface PluginAiDiskStore {
  version: 1;
  bindings: Record<string, PluginAiBinding>;
  secrets: Record<string, string>;
}

const DEFAULT_BASE_URL = 'https://api.deepseek.com';
const USER_AGENT = 'LexiNote/2.0 (+https://github.com/peryixing-lab/LexiNote)';
const MAX_PROFILES = 32;
const PROFILE_ID_PATTERN = /^[A-Za-z0-9_.-]{1,64}$/;
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;

function isPrivateIPv4(host: string): boolean {
  const parts = host.split('.');
  if (parts.length !== 4) { return false; }
  const nums: number[] = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) { return false; }
    const val = Number(part);
    if (!Number.isFinite(val) || val < 0 || val > 255) { return false; }
    nums.push(val);
  }
  if (nums[0] === 127 || nums[0] === 10) { return true; }
  if (nums[0] === 192 && nums[1] === 168) { return true; }
  return nums[0] === 172 && nums[1] >= 16 && nums[1] <= 31;
}

function isPrivateHost(host: string): boolean {
  let name = host.trim().toLowerCase();
  if (name.startsWith('[')) {
    const end = name.indexOf(']');
    if (end < 0) { return false; }
    const rest = name.slice(end + 1);
    if (rest.length > 0 && !/^:\d+$/.test(rest)) { return false; }
    const addr = name.slice(0, end + 1);
    return addr === '[::1]' || addr.startsWith('[fe80:') || addr.startsWith('[fc') || addr.startsWith('[fd');
  }
  const colon = name.lastIndexOf(':');
  if (colon > 0 && name.indexOf(':') === colon) {
    name = name.slice(0, colon);
  }
  if (name === 'localhost' || name === '0.0.0.0' || name === 'host.docker.internal') {
    return true;
  }
  if (isPrivateIPv4(name)) { return true; }
  return name.endsWith('.local');
}

function normalizeBaseUrl(raw: string): string {
  const value = raw.trim().replace(/\/+$/, '');
  if (!value || value.length > 8192) {
    raisePluginError(PluginErrorCode.INVALID_ARGUMENT, 'Base URL 需为完整的 http(s) 地址，最多 8192 字符');
  }
  const match = /^(https?):\/\/([^\s/?#@]+)(\/[^\s?#]*)?$/i.exec(value);
  if (!match) {
    raisePluginError(PluginErrorCode.INVALID_ARGUMENT, 'Base URL 需为完整的 http(s) 地址，不含账号、查询参数或片段');
  }
  const scheme = match[1].toLowerCase();
  const host = match[2];
  if (scheme === 'https' || isPrivateHost(host)) { return value; }
  raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '公网 Base URL 必须使用 https://；本地或局域网地址可使用 http://');
}

function normalizeProvider(raw: string): 'openai-compatible' | 'anthropic-compatible' | '' {
  const value = raw.trim().toLowerCase();
  if (value === 'openai-compatible' || value === 'deepseek-openai' || value === 'openai') {
    return 'openai-compatible';
  }
  if (value === 'anthropic-compatible' || value === 'deepseek-anthropic' || value === 'anthropic') {
    return 'anthropic-compatible';
  }
  return '';
}

function checkKey(raw: string): { ok: boolean; value: string; reason: string } {
  const value = raw.trim();
  if (!value) { return { ok: false, value: '', reason: 'empty' }; }
  if (value.length > 8192) { return { ok: false, value: '', reason: 'tooLong' }; }
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code < 0x21 || code > 0x7e) { return { ok: false, value: '', reason: 'illegalCharacters' }; }
  }
  return { ok: true, value, reason: '' };
}

function redactSecret(text: string, key: string): string {
  let out = text;
  if (key.length > 0) { out = out.split(key).join('[redacted]'); }
  out = out.replace(/sk-[A-Za-z0-9_-]{8,}/g, 'sk-[redacted]');
  out = out.replace(/Bearer\s+[^\s,;]+/gi, 'Bearer [redacted]');
  out = out.replace(/x-api-key\s*[:=]\s*[^\s,;]+/gi, 'x-api-key: [redacted]');
  return out;
}

function quotaProvider(baseUrl: string): string {
  const match = /^https:\/\/([^/:?#@]+)(?::443)?(?:\/|$)/i.exec(baseUrl);
  const host = match ? match[1].toLowerCase() : '';
  if (host === 'api.deepseek.com') { return 'DeepSeek'; }
  if (host === 'openrouter.ai') { return 'OpenRouter'; }
  if (host === 'open.bigmodel.cn' || host === 'api.z.ai') { return 'GLM Coding Plan'; }
  if (host === 'api.kimi.com') { return 'Kimi For Coding'; }
  if (host === 'api.minimaxi.com' || host === 'api.minimax.io') { return 'MiniMax Coding Plan'; }
  return '';
}

function quotaEndpoint(baseUrl: string): string {
  const provider = quotaProvider(baseUrl);
  if (provider === 'DeepSeek') { return 'https://api.deepseek.com/user/balance'; }
  if (provider === 'OpenRouter') { return 'https://openrouter.ai/api/v1/credits'; }
  if (provider === 'GLM Coding Plan') {
    const origin = /^https:\/\/api\.z\.ai(?::443)?(?:\/|$)/i.test(baseUrl)
      ? 'https://api.z.ai' : 'https://open.bigmodel.cn';
    return `${origin}/api/monitor/usage/quota/limit`;
  }
  if (provider === 'Kimi For Coding') { return 'https://api.kimi.com/coding/v1/usages'; }
  if (provider === 'MiniMax Coding Plan') {
    const origin = /^https:\/\/api\.minimax\.io(?::443)?(?:\/|$)/i.test(baseUrl)
      ? 'https://api.minimax.io' : 'https://api.minimaxi.com';
    return `${origin}/v1/api/openplatform/coding_plan/remains`;
  }
  return '';
}

function toRecord(raw: unknown): Record<string, unknown> {
  return raw !== null && typeof raw === 'object' && !Array.isArray(raw)
    ? (raw as Record<string, unknown>)
    : {};
}

function toNum(raw: unknown): number {
  if (typeof raw !== 'number' && (typeof raw !== 'string' || raw.trim().length === 0)) { return Number.NaN; }
  const val = Number(raw);
  return Number.isFinite(val) ? val : Number.NaN;
}

function toResetAt(raw: unknown): number | undefined {
  const numeric = toNum(raw);
  if (Number.isFinite(numeric) && numeric > 0) { return numeric < 1e12 ? numeric * 1000 : numeric; }
  const parsed = typeof raw === 'string' ? Date.parse(raw) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : undefined;
}

function percentWindow(label: string, used: number, reset: unknown): PluginAiQuotaWindow {
  return {
    label,
    unit: '%',
    usedPercent: Math.max(0, Math.min(100, used)),
    resetAt: toResetAt(reset)
  };
}

function legacyQuotaWindow(label: string, raw: unknown): PluginAiQuotaWindow | undefined {
  const record = toRecord(raw);
  const total = toNum(record.limit);
  const remaining = toNum(record.remaining);
  const used = toNum(record.used);
  if (!(total > 0) || (!Number.isFinite(remaining) && !Number.isFinite(used))) { return undefined; }
  const usedAmount = Number.isFinite(remaining) ? total - remaining : used;
  return percentWindow(label, (usedAmount / total) * 100, record.resetTime);
}

function parseQuotaBalance(provider: string, raw: string): PluginAiBalance {
  const body = toRecord(JSON.parse(raw));
  const result: PluginAiBalance = {
    supported: true,
    provider,
    updatedAt: Date.now(),
    windows: []
  };
  if (body.success === false) {
    throw new Error('套餐接口拒绝查询，请检查 API Key 与套餐权限');
  }
  if (provider === 'DeepSeek') {
    const entries = Array.isArray(body.balance_infos) ? (body.balance_infos as Record<string, unknown>[]) : [];
    for (const entry of entries) {
      const remaining = toNum(entry.total_balance);
      if (!Number.isFinite(remaining)) { continue; }
      result.windows.push({
        label: '账户余额',
        unit: typeof entry.currency === 'string' ? entry.currency : '',
        remainingValue: remaining
      });
    }
  } else if (provider === 'OpenRouter') {
    const data = body.data ? toRecord(body.data) : body;
    const total = toNum(data.total_credits);
    const used = toNum(data.total_usage);
    if (Number.isFinite(total) && Number.isFinite(used)) {
      result.windows.push({
        label: '剩余额度',
        unit: 'USD',
        remainingValue: total - used,
        maxValue: total
      });
    }
  } else if (provider === 'GLM Coding Plan') {
    const data = toRecord(body.data);
    const limits = Array.isArray(data.limits) ? (data.limits as Record<string, unknown>[]) : [];
    for (const limit of limits) {
      const type = typeof limit.type === 'string' ? limit.type.toUpperCase() : '';
      if (type && type !== 'TOKENS_LIMIT' && type !== 'CREDIT_LIMIT') { continue; }
      const total = toNum(limit.usage);
      const remaining = toNum(limit.remaining);
      const current = toNum(limit.currentValue);
      let used = toNum(limit.percentage);
      if (total > 0 && (Number.isFinite(remaining) || Number.isFinite(current))) {
        used = (Math.max(Number.isFinite(remaining) ? total - remaining : 0, Number.isFinite(current) ? current : 0) / total) * 100;
      }
      if (!Number.isFinite(used)) { continue; }
      const unit = toNum(limit.unit);
      const count = toNum(limit.number);
      const minutes = unit === 5 ? count : unit === 3 ? count * 60 : unit === 1 ? count * 1440 : Number.NaN;
      const label = minutes > 0 && minutes <= 360
        ? '5 小时额度'
        : unit === 6
          ? '每周额度'
          : minutes > 18720
            ? '每月额度'
            : minutes > 360
              ? '每周额度'
              : unit === 3
                ? '5 小时额度'
                : '套餐额度';
      result.windows.push(percentWindow(label, used, limit.nextResetTime));
    }
  } else if (provider === 'Kimi For Coding') {
    const usages = toRecord(body.usages);
    const keys = ['limit_5h', 'limit_month_code', 'limit_month_total'];
    for (let i = 0; i < keys.length; i += 1) {
      if (i === 2 && result.windows.some((item) => item.label === '每月额度')) { continue; }
      const bucket = toRecord(usages[keys[i]]);
      const ratio = toNum(bucket.used_ratio !== undefined ? bucket.used_ratio : bucket.usedRatio);
      if (Number.isFinite(ratio) && ratio >= 0) {
        result.windows.push(
          percentWindow(i === 0 ? '5 小时额度' : '每月额度', ratio * 100, bucket.reset_time ?? bucket.resetTime)
        );
      }
    }
    if (!result.windows.some((item) => item.label === '5 小时额度')) {
      const limits = Array.isArray(body.limits) ? (body.limits as Record<string, unknown>[]) : [];
      let latest: PluginAiQuotaWindow | undefined;
      for (const limit of limits) {
        const win = legacyQuotaWindow('5 小时额度', limit.detail);
        if (win && (!latest || (win.resetAt || 0) >= (latest.resetAt || 0))) { latest = win; }
      }
      if (latest) { result.windows.unshift(latest); }
    }
    const weekly = legacyQuotaWindow('每周额度', body.usage);
    if (weekly) { result.windows.push(weekly); }
  } else if (provider === 'MiniMax Coding Plan') {
    const code = toNum(toRecord(body.base_resp).status_code);
    if (Number.isFinite(code) && code !== 0) {
      throw new Error('MiniMax 拒绝查询，请检查 Coding Plan Key');
    }
    const remains = Array.isArray(body.model_remains) ? (body.model_remains as Record<string, unknown>[]) : [];
    const general = remains.find((item) => item.model_name === 'general');
    if (general) {
      const prefixes = ['current_interval', 'current_weekly'];
      for (let i = 0; i < prefixes.length; i += 1) {
        const remaining = toNum(general[`${prefixes[i]}_remaining_percent`]);
        const state = toNum(general[`${prefixes[i]}_status`]);
        if (!Number.isFinite(remaining) || (state === 3 && remaining >= 100)) { continue; }
        result.windows.push(
          percentWindow(i === 0 ? '5 小时额度' : '每周额度', 100 - remaining, general[i === 0 ? 'end_time' : 'weekly_end_time'])
        );
      }
    }
  }
  if (result.windows.length === 0) {
    throw new Error('接口未返回可识别的余额或套餐额度');
  }
  return result;
}

export class PluginAiService {
  private readonly storePath: string;
  private readonly balanceCache = new Map<string, PluginAiBalance>();
  private cache: PluginAiDiskStore | null = null;

  constructor(userDataDir: string) {
    this.storePath = join(userDataDir, 'plugin-ai.json');
  }

  private readStore(): PluginAiDiskStore {
    if (this.cache) { return this.cache; }
    if (existsSync(this.storePath)) {
      try {
        const parsed = JSON.parse(readFileSync(this.storePath, 'utf8')) as Partial<PluginAiDiskStore>;
        if (parsed && typeof parsed === 'object') {
          this.cache = {
            version: 1,
            bindings: parsed.bindings && typeof parsed.bindings === 'object' ? parsed.bindings : {},
            secrets: parsed.secrets && typeof parsed.secrets === 'object' ? parsed.secrets : {}
          };
          return this.cache;
        }
      } catch {
        // Ignore corrupt file; fall through to clean empty store.
      }
    }
    this.cache = { version: 1, bindings: {}, secrets: {} };
    return this.cache;
  }

  private writeStore(store: PluginAiDiskStore): void {
    this.cache = store;
    mkdirSync(dirname(this.storePath), { recursive: true });
    const temp = `${this.storePath}.${process.pid}.${Date.now()}.tmp`;
    writeFileSync(temp, JSON.stringify(store, null, 2), 'utf8');
    renameSync(temp, this.storePath);
  }

  private secretSlot(pluginId: string, profileId: string): string {
    return `${pluginId}:${profileId}`;
  }

  private bindingOf(pluginId: string): PluginAiBinding {
    const store = this.readStore();
    const raw = store.bindings[pluginId];
    if (!raw || raw.version !== 2 || !Array.isArray(raw.profiles)) {
      return { version: 2, activeProfileId: '', profiles: [] };
    }
    return raw;
  }

  private activeProfile(binding: PluginAiBinding): PluginAiProfile | undefined {
    if (!binding.activeProfileId) { return undefined; }
    return binding.profiles.find((item) => item.profileId === binding.activeProfileId);
  }

  private isAnthropic(profile: PluginAiProfile): boolean {
    if (profile.provider === 'anthropic-compatible') { return true; }
    const url = profile.baseUrl.toLowerCase();
    return url.includes('/anthropic') || url.endsWith('/v1/messages');
  }

  private endpointUrl(profile: PluginAiProfile): string {
    const base = (profile.baseUrl.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
    if (this.isAnthropic(profile)) {
      if (base.endsWith('/v1/messages')) { return base; }
      if (/\/v\d+$/.test(base)) { return `${base}/messages`; }
      return `${base}/v1/messages`;
    }
    if (base.endsWith('/chat/completions')) { return base; }
    if (/\/v\d+$/.test(base)) { return `${base}/chat/completions`; }
    return `${base}/v1/chat/completions`;
  }

  statusFor(pluginId: string): PluginAiStatus {
    const store = this.readStore();
    const binding = this.bindingOf(pluginId);
    const profile = this.activeProfile(binding);
    if (!profile) {
      return {
        configured: false,
        profileId: '',
        name: '',
        provider: '',
        baseUrl: '',
        model: '',
        maxTokens: 0,
        temperature: 0,
        balanceProvider: '',
        needsApiKey: true
      };
    }
    const key = store.secrets[this.secretSlot(pluginId, profile.profileId)] || '';
    return {
      configured: key.length > 0,
      profileId: profile.profileId,
      name: profile.name,
      provider: profile.provider,
      baseUrl: profile.baseUrl,
      model: profile.model,
      maxTokens: profile.maxTokens,
      temperature: profile.temperature,
      balanceProvider: quotaProvider(profile.baseUrl),
      needsApiKey: key.length === 0
    };
  }

  configureFor(pluginId: string, rawParams: Record<string, unknown>): PluginAiStatus {
    if (rawParams.clear === true) {
      this.clearFor(pluginId);
      return this.statusFor(pluginId);
    }

    const store = this.readStore();
    const binding = structuredClone(this.bindingOf(pluginId));
    const action = typeof rawParams.action === 'string' ? rawParams.action : '';
    const requestedProfileId = typeof rawParams.profileId === 'string' ? rawParams.profileId.trim() : '';

    if (action === 'select') {
      if (!requestedProfileId) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '缺少服务商标识');
      }
      const found = binding.profiles.find((item) => item.profileId === requestedProfileId);
      if (!found) {
        raisePluginError(PluginErrorCode.NOT_FOUND, '服务商不存在，请刷新后重试');
      }
      const key = store.secrets[this.secretSlot(pluginId, requestedProfileId)] || '';
      if (!key) {
        raisePluginError(PluginErrorCode.MISSING_CREDENTIAL, '请先编辑此服务商补填 API Key');
      }
      binding.activeProfileId = requestedProfileId;
      store.bindings[pluginId] = binding;
      this.writeStore(store);
      this.balanceCache.delete(this.secretSlot(pluginId, requestedProfileId));
      return this.statusFor(pluginId);
    }

    if (action === 'remove' || rawParams.remove === true) {
      if (!requestedProfileId) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '缺少服务商标识');
      }
      const found = binding.profiles.find((item) => item.profileId === requestedProfileId);
      if (!found) {
        raisePluginError(PluginErrorCode.NOT_FOUND, '服务商不存在，请刷新后重试');
      }
      binding.profiles = binding.profiles.filter((item) => item.profileId !== requestedProfileId);
      delete store.secrets[this.secretSlot(pluginId, requestedProfileId)];
      if (binding.activeProfileId === requestedProfileId) {
        binding.activeProfileId = binding.profiles.length > 0 ? binding.profiles[0].profileId : '';
      }
      store.bindings[pluginId] = binding;
      this.writeStore(store);
      this.balanceCache.delete(this.secretSlot(pluginId, requestedProfileId));
      return this.statusFor(pluginId);
    }

    const profileId =
      requestedProfileId ||
      (binding.activeProfileId && action !== 'create'
        ? binding.activeProfileId
        : `service_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e9).toString(36)}`);
    if (!PROFILE_ID_PATTERN.test(profileId)) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '服务商标识非法');
    }

    const existing = binding.profiles.find((item) => item.profileId === profileId);
    const creating = existing === undefined;
    if (creating && binding.profiles.length >= MAX_PROFILES) {
      raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, `最多保存 ${MAX_PROFILES} 个服务商`);
    }

    const profile: PluginAiProfile = existing
      ? { ...existing }
      : {
          profileId,
          name: '',
          provider: 'openai-compatible',
          baseUrl: '',
          model: '',
          maxTokens: 8192,
          temperature: 0.3
        };

    if (typeof rawParams.name === 'string' || creating) {
      profile.name = typeof rawParams.name === 'string' ? rawParams.name.trim() : '';
      if (profile.name.length > 64) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '服务商名称最多 64 字符');
      }
    }

    if (typeof rawParams.provider === 'string' && rawParams.provider.length > 0) {
      const normalizedProvider = normalizeProvider(rawParams.provider);
      if (!normalizedProvider) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '模型服务类型只能是 openai-compatible 或 anthropic-compatible');
      }
      profile.provider = normalizedProvider;
    }

    let baseUrlChanged = false;
    if (typeof rawParams.baseUrl === 'string' && rawParams.baseUrl.length > 0) {
      const nextBaseUrl = normalizeBaseUrl(rawParams.baseUrl);
      baseUrlChanged = nextBaseUrl !== profile.baseUrl;
      profile.baseUrl = nextBaseUrl;
    }

    const apiKeyInput = typeof rawParams.apiKey === 'string' ? rawParams.apiKey.trim() : '';
    if (creating && !apiKeyInput) {
      raisePluginError(PluginErrorCode.MISSING_CREDENTIAL, '首次绑定需要填写 API Key');
    }
    if (!profile.baseUrl) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '请填写 Base URL');
    }

    if (typeof rawParams.model === 'string' && rawParams.model.trim().length > 0) {
      const model = rawParams.model.trim();
      if (model.length > 128) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '模型名称长度必须在 1-128 之间');
      }
      profile.model = model;
    } else if (!profile.model) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '请填写模型名称');
    }

    if (typeof rawParams.maxTokens === 'number' && Number.isFinite(rawParams.maxTokens) && rawParams.maxTokens > 0) {
      profile.maxTokens = Math.max(512, Math.min(32768, Math.floor(rawParams.maxTokens)));
    }
    if (typeof rawParams.temperature === 'number' && Number.isFinite(rawParams.temperature) && rawParams.temperature >= 0) {
      profile.temperature = Math.max(0, Math.min(2, rawParams.temperature));
    }

    const keyCheck = checkKey(apiKeyInput);
    if (apiKeyInput && !keyCheck.ok) {
      raisePluginError(PluginErrorCode.INVALID_CREDENTIAL, 'API Key 含不可用于 HTTP 请求头的字符，请粘贴原始 Key');
    }
    if (!creating && baseUrlChanged && !apiKeyInput) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '更换 Base URL 时请重新填写 API Key');
    }

    if (creating) {
      binding.profiles.push(profile);
    } else {
      binding.profiles = binding.profiles.map((item) => (item.profileId === profileId ? profile : item));
    }

    if (rawParams.select !== false || !binding.activeProfileId) {
      binding.activeProfileId = profileId;
    }
    if (apiKeyInput) {
      store.secrets[this.secretSlot(pluginId, profileId)] = keyCheck.value;
    }
    store.bindings[pluginId] = binding;
    this.writeStore(store);
    this.balanceCache.delete(this.secretSlot(pluginId, profileId));
    return this.statusFor(pluginId);
  }

  clearFor(pluginId: string): void {
    const store = this.readStore();
    const binding = this.bindingOf(pluginId);
    for (const profile of binding.profiles) {
      delete store.secrets[this.secretSlot(pluginId, profile.profileId)];
      this.balanceCache.delete(this.secretSlot(pluginId, profile.profileId));
    }
    delete store.bindings[pluginId];
    this.writeStore(store);
  }

  private resolveActive(pluginId: string): { profile: PluginAiProfile; key: string } {
    const store = this.readStore();
    const binding = this.bindingOf(pluginId);
    const profile = this.activeProfile(binding);
    if (!profile) {
      raisePluginError(PluginErrorCode.MISSING_CREDENTIAL, '请先绑定模型服务：请填写模型服务、模型名称与 API Key');
    }
    const rawKey = store.secrets[this.secretSlot(pluginId, profile.profileId)] || '';
    const check = checkKey(rawKey);
    if (check.reason === 'empty') {
      raisePluginError(PluginErrorCode.MISSING_CREDENTIAL, '此服务商缺少 API Key：请先补填');
    }
    if (!check.ok) {
      raisePluginError(PluginErrorCode.INVALID_CREDENTIAL, '此服务商的 API Key 含不可用于 HTTP 请求头的字符');
    }
    normalizeBaseUrl(profile.baseUrl);
    return { profile, key: check.value };
  }

  private httpFetch(
    urlString: string,
    method: 'GET' | 'POST',
    headers: Record<string, string>,
    body: string | undefined,
    timeoutMs: number
  ): Promise<{ status: number; body: string }> {
    return new Promise((resolvePromise, rejectPromise) => {
      const parsed = new URL(urlString);
      const isHttps = parsed.protocol === 'https:';
      const requestFn = isHttps ? httpsRequest : httpRequest;
      const req = requestFn(
        parsed,
        {
          method,
          headers,
          timeout: timeoutMs
        },
        (res) => {
          const status = res.statusCode ?? 0;
          if (status >= 300 && status < 400) {
            res.resume();
            rejectPromise(
              new Error('禁止 HTTP 重定向，请填写最终服务端地址')
            );
            return;
          }
          const chunks: Buffer[] = [];
          let total = 0;
          res.on('data', (chunk: Buffer) => {
            total += chunk.length;
            if (total > MAX_RESPONSE_BYTES) {
              req.destroy(new Error('模型服务响应超过大小限制'));
              return;
            }
            chunks.push(chunk);
          });
          res.on('end', () => {
            resolvePromise({
              status,
              body: Buffer.concat(chunks).toString('utf8')
            });
          });
        }
      );
      req.on('timeout', () => {
        req.destroy(new Error(`请求超时（>${timeoutMs}ms）`));
      });
      req.on('error', (error) => {
        rejectPromise(error);
      });
      if (body !== undefined) {
        req.write(body);
      }
      req.end();
    });
  }

  async chatFor(pluginId: string, rawParams: Record<string, unknown>): Promise<Record<string, unknown>> {
    const messages = Array.isArray(rawParams.messages) ? (rawParams.messages as Record<string, unknown>[]) : [];
    const tools = Array.isArray(rawParams.tools) ? (rawParams.tools as Record<string, unknown>[]) : [];
    const maxTokensParam = typeof rawParams.maxTokens === 'number' ? rawParams.maxTokens : 0;
    const tempParam = typeof rawParams.temperature === 'number' ? rawParams.temperature : -1;

    if (messages.length === 0) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, 'ai.chat 需要至少一条消息');
    }
    if (messages.length > PluginLimits.MAX_AI_MESSAGES) {
      raisePluginError(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_MESSAGES} 条消息`);
    }
    if (tools.length > PluginLimits.MAX_AI_TOOLS) {
      raisePluginError(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_TOOLS} 个工具`);
    }

    const active = this.resolveActive(pluginId);
    const anthropic = this.isAnthropic(active.profile);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'User-Agent': USER_AGENT
    };
    if (anthropic) {
      headers['x-api-key'] = active.key;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers.Authorization = `Bearer ${active.key}`;
    }

    const body = this.buildChatBody(active.profile, messages, tools, maxTokensParam, tempParam, anthropic);
    try {
      const response = await this.httpFetch(
        this.endpointUrl(active.profile),
        'POST',
        headers,
        body,
        PluginLimits.AI_TIMEOUT_MS
      );
      if (response.status < 200 || response.status >= 300) {
        let detail = response.body;
        try {
          const parsedErr = JSON.parse(response.body) as Record<string, unknown>;
          const nested = toRecord(parsedErr.error);
          if (typeof nested.message === 'string') { detail = nested.message; }
          else if (typeof parsedErr.message === 'string') { detail = parsedErr.message; }
        } catch {
          // keep prefix
        }
        raisePluginError(
          PluginErrorCode.MODEL_UNAVAILABLE,
          `模型接口返回 HTTP ${response.status}：${redactSecret(detail.slice(0, 300), active.key)}`
        );
      }
      return anthropic
        ? this.parseAnthropicReply(response.body, active.profile)
        : this.parseOpenAiReply(response.body, active.profile);
    } catch (error) {
      const code = codeOfPluginError(error);
      const text = redactSecret(
        code === PluginErrorCode.UNKNOWN ? rawPluginErrorText(error) : messageOfPluginError(error),
        active.key
      );
      if (code !== PluginErrorCode.UNKNOWN) {
        raisePluginError(code, text);
      }
      raisePluginError(PluginErrorCode.MODEL_UNAVAILABLE, `访问模型服务失败：${text}`);
    }
  }

  private buildChatBody(
    profile: PluginAiProfile,
    messages: Record<string, unknown>[],
    tools: Record<string, unknown>[],
    maxTokensParam: number,
    tempParam: number,
    anthropic: boolean
  ): string {
    const maxTokens = maxTokensParam > 0
      ? Math.max(512, Math.min(profile.maxTokens, Math.floor(maxTokensParam)))
      : profile.maxTokens;
    const temperature = tempParam >= 0 ? tempParam : profile.temperature;

    if (anthropic) {
      const systemParts: string[] = [];
      const formatted: Record<string, unknown>[] = [];
      for (const msg of messages) {
        const role = typeof msg.role === 'string' ? msg.role : 'user';
        const content = typeof msg.content === 'string' ? msg.content : '';
        if (role === 'system') {
          if (content.trim()) { systemParts.push(content); }
          continue;
        }
        if (role === 'assistant') {
          const blocks: Record<string, unknown>[] = [];
          if (content) { blocks.push({ type: 'text', text: content }); }
          if (Array.isArray(msg.toolCalls)) {
            (msg.toolCalls as Record<string, unknown>[]).forEach((call, idx) => {
              const name = typeof call.name === 'string' ? call.name : '';
              if (!name) { return; }
              let input: unknown = {};
              try {
                input = JSON.parse(typeof call.arguments === 'string' && call.arguments ? call.arguments : '{}');
              } catch {
                input = {};
              }
              blocks.push({
                type: 'tool_use',
                id: typeof call.id === 'string' && call.id ? call.id : `toolu_${idx}`,
                name,
                input
              });
            });
          }
          if (blocks.length > 0) { formatted.push({ role: 'assistant', content: blocks }); }
          continue;
        }
        const block: Record<string, unknown> =
          role === 'tool'
            ? {
                type: 'tool_result',
                tool_use_id: typeof msg.toolCallId === 'string' ? msg.toolCallId : '',
                content: content || 'OK',
                is_error: msg.isError === true
              }
            : { type: 'text', text: content };
        const prev = formatted[formatted.length - 1];
        if (prev && prev.role === 'user' && Array.isArray(prev.content)) {
          if (role === 'tool') {
            (prev.content as Record<string, unknown>[]).unshift(block);
          } else {
            (prev.content as Record<string, unknown>[]).push(block);
          }
        } else {
          formatted.push({ role: 'user', content: [block] });
        }
      }
      const payload: Record<string, unknown> = {
        model: profile.model,
        max_tokens: Math.max(1024, Math.min(64000, maxTokens)),
        messages: formatted
      };
      if (systemParts.length > 0) { payload.system = systemParts.join('\n\n'); }
      if (temperature >= 0) { payload.temperature = temperature; }
      const mappedTools = tools
        .filter((tool) => typeof tool.name === 'string' && tool.name.length > 0)
        .map((tool) => ({
          name: tool.name,
          description: typeof tool.description === 'string' ? tool.description : '',
          input_schema: tool.parameters ?? { type: 'object', properties: {}, required: [] }
        }));
      if (mappedTools.length > 0) { payload.tools = mappedTools; }
      return JSON.stringify(payload);
    }

    const openAiMessages = messages.map((msg) => {
      const role = typeof msg.role === 'string' ? msg.role : 'user';
      const content = typeof msg.content === 'string' ? msg.content : '';
      if (role === 'assistant') {
        const entry: Record<string, unknown> = { role: 'assistant', content };
        if (Array.isArray(msg.toolCalls) && msg.toolCalls.length > 0) {
          entry.tool_calls = (msg.toolCalls as Record<string, unknown>[])
            .filter((call) => typeof call.name === 'string' && call.name.length > 0)
            .map((call, idx) => ({
              id: typeof call.id === 'string' && call.id ? call.id : `call_${idx}`,
              type: 'function',
              function: {
                name: call.name,
                arguments: typeof call.arguments === 'string' && call.arguments ? call.arguments : '{}'
              }
            }));
        }
        return entry;
      }
      if (role === 'tool') {
        return {
          role: 'tool',
          tool_call_id: typeof msg.toolCallId === 'string' ? msg.toolCallId : '',
          content: content || 'Done'
        };
      }
      return { role: role === 'system' ? 'system' : 'user', content };
    });

    const payload: Record<string, unknown> = {
      model: profile.model,
      messages: openAiMessages,
      stream: false,
      max_tokens: Math.max(512, Math.min(32768, maxTokens)),
      temperature
    };
    const mappedTools = tools
      .filter((tool) => typeof tool.name === 'string' && tool.name.length > 0)
      .map((tool) => ({
        type: 'function',
        function: {
          name: tool.name,
          description: typeof tool.description === 'string' ? tool.description : '',
          parameters: tool.parameters ?? { type: 'object', properties: {}, required: [] }
        }
      }));
    if (mappedTools.length > 0) { payload.tools = mappedTools; }
    return JSON.stringify(payload);
  }

  private parseOpenAiReply(raw: string, profile: PluginAiProfile): Record<string, unknown> {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const choices = Array.isArray(parsed.choices) ? (parsed.choices as Record<string, unknown>[]) : [];
    if (choices.length === 0) {
      raisePluginError(PluginErrorCode.MODEL_UNAVAILABLE, '模型返回为空（choices 缺失）');
    }
    const choice = choices[0];
    const message = toRecord(choice.message);
    const toolCalls: Record<string, unknown>[] = [];
    if (Array.isArray(message.tool_calls)) {
      (message.tool_calls as Record<string, unknown>[]).forEach((call, idx) => {
        const fn = toRecord(call.function);
        const name = typeof fn.name === 'string' ? fn.name : '';
        if (!name) { return; }
        toolCalls.push({
          id: typeof call.id === 'string' ? call.id : `call_${idx}`,
          name,
          arguments: typeof fn.arguments === 'string' ? fn.arguments : '{}'
        });
      });
    }
    const usage = toRecord(parsed.usage);
    const finish = typeof choice.finish_reason === 'string'
      ? (choice.finish_reason === 'length' ? 'max-tokens' : choice.finish_reason)
      : 'stop';
    return {
      text: typeof message.content === 'string' ? message.content : '',
      reasoning: typeof message.reasoning_content === 'string' ? message.reasoning_content : '',
      toolCalls,
      finishReason: finish,
      model: profile.model,
      usage: {
        inputTokens: typeof usage.prompt_tokens === 'number' ? usage.prompt_tokens : 0,
        outputTokens: typeof usage.completion_tokens === 'number' ? usage.completion_tokens : 0
      }
    };
  }

  private parseAnthropicReply(raw: string, profile: PluginAiProfile): Record<string, unknown> {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const content = Array.isArray(parsed.content) ? (parsed.content as Record<string, unknown>[]) : [];
    let text = '';
    let reasoning = '';
    const toolCalls: Record<string, unknown>[] = [];
    content.forEach((block, idx) => {
      const type = typeof block.type === 'string' ? block.type : '';
      if (type === 'text' && typeof block.text === 'string') {
        text = text ? `${text}\n${block.text}` : block.text;
      } else if (type === 'thinking' && typeof block.thinking === 'string') {
        reasoning = block.thinking;
      } else if (type === 'tool_use') {
        const name = typeof block.name === 'string' ? block.name : '';
        if (!name) { return; }
        toolCalls.push({
          id: typeof block.id === 'string' ? block.id : `toolu_${idx}`,
          name,
          arguments: JSON.stringify(block.input !== undefined ? block.input : {})
        });
      }
    });
    const usage = toRecord(parsed.usage);
    const stop = typeof parsed.stop_reason === 'string'
      ? (parsed.stop_reason === 'tool_use' ? 'tool_calls' : parsed.stop_reason === 'max_tokens' ? 'max-tokens' : parsed.stop_reason)
      : 'stop';
    return {
      text,
      reasoning,
      toolCalls,
      finishReason: stop,
      model: profile.model,
      usage: {
        inputTokens: typeof usage.input_tokens === 'number' ? usage.input_tokens : 0,
        outputTokens: typeof usage.output_tokens === 'number' ? usage.output_tokens : 0
      }
    };
  }

  private async readJsonEndpoint(profile: PluginAiProfile, key: string, endpoint: string, quota: boolean): Promise<string> {
    normalizeBaseUrl(profile.baseUrl);
    const headers: Record<string, string> = {
      Accept: 'application/json',
      'User-Agent': USER_AGENT
    };
    if (quota && quotaProvider(profile.baseUrl) === 'GLM Coding Plan') {
      headers.Authorization = key;
    } else if (quota) {
      headers.Authorization = `Bearer ${key}`;
    } else if (this.isAnthropic(profile)) {
      headers['x-api-key'] = key;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers.Authorization = `Bearer ${key}`;
    }
    try {
      const res = await this.httpFetch(endpoint, 'GET', headers, undefined, 15000);
      if (res.status < 200 || res.status >= 300) {
        throw new Error(`HTTP ${res.status}，请检查服务地址、API Key 和套餐权限`);
      }
      return res.body;
    } catch (error) {
      const detail = redactSecret(rawPluginErrorText(error), key);
      raisePluginError(PluginErrorCode.MODEL_UNAVAILABLE, `查询失败：${detail.slice(0, 240)}`);
    }
  }

  async modelsFor(pluginId: string): Promise<string[]> {
    const active = this.resolveActive(pluginId);
    const endpoint = this.endpointUrl(active.profile).replace(/\/(?:chat\/completions|messages)$/, '/models');
    const raw = await this.readJsonEndpoint(active.profile, active.key, endpoint, false);
    try {
      const body = JSON.parse(raw) as Record<string, unknown>;
      const data = Array.isArray(body.data) ? (body.data as Record<string, unknown>[]) : null;
      if (!data) { throw new Error('模型列表缺少 data'); }
      const models: string[] = [];
      for (const item of data) {
        const id = typeof item.id === 'string' ? item.id.trim() : '';
        if (id && id.length <= 128 && !models.includes(id)) {
          models.push(id);
        }
        if (models.length >= 300) { break; }
      }
      return models;
    } catch {
      raisePluginError(PluginErrorCode.MODEL_UNAVAILABLE, '无法读取模型列表；可在模型设置中手动添加常用模型');
    }
  }

  async balanceFor(pluginId: string): Promise<PluginAiBalance> {
    const active = this.resolveActive(pluginId);
    const provider = quotaProvider(active.profile.baseUrl);
    if (!provider) {
      return { supported: false, provider: '', updatedAt: 0, windows: [] };
    }
    const cacheKey = this.secretSlot(pluginId, active.profile.profileId);
    const cached = this.balanceCache.get(cacheKey);
    if (cached && Date.now() - cached.updatedAt < 60000) {
      return cached;
    }
    const raw = await this.readJsonEndpoint(active.profile, active.key, quotaEndpoint(active.profile.baseUrl), true);
    try {
      const balance = parseQuotaBalance(provider, raw);
      this.balanceCache.set(cacheKey, balance);
      return balance;
    } catch {
      raisePluginError(PluginErrorCode.MODEL_UNAVAILABLE, '未能读取余额或套餐额度，请检查 Key 类型和套餐权限');
    }
  }
}
