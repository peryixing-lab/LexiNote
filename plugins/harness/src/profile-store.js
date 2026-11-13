'use strict';

const { text } = require('./util');
const { serviceName } = require('./providers');

/**
 * Provider profiles for Harness.
 *
 * On a host that exposes per-profile bindings (`ai.status().profileId`), profiles are
 * persisted by the host and this plugin keeps only metadata: the API key is write-only,
 * is never stored in plugin storage, and never travels through `boot.dataJson`.
 *
 * On an older host the legacy single-binding implementation below is kept as a
 * compatibility path. That path is the only one that still stores a key locally.
 */

const LEGACY_KEY = 'harness.providers.v1';
const STORAGE_KEY = 'harness.providers.v2';
const MAX_PROFILES = 32;
const MAX_STORAGE_CHARS = 36000;

function fail(code, message) {
  const error = new Error(`${code}: ${message}`);
  error.code = code;
  throw error;
}

function copy(value) { return JSON.parse(JSON.stringify(value)); }
function address(value) { return text(value).trim().replace(/\/+$/, ''); }

function newProfileId() {
  return `service_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e9).toString(36)}`;
}

function emptyBook() {
  return { version: 2, activeProfileId: '', profiles: [] };
}

function publicProfile(profile) {
  if (!profile) {
    return {
      configured: false, profileId: '', name: '', provider: '', baseUrl: '', model: '',
      maxTokens: 0, temperature: 0, balanceProvider: '', needsApiKey: true
    };
  }
  return {
    profileId: profile.profileId,
    name: profile.name || '',
    provider: profile.provider,
    baseUrl: profile.baseUrl,
    model: profile.model,
    maxTokens: profile.maxTokens,
    temperature: profile.temperature,
    balanceProvider: profile.balanceProvider || '',
    configured: profile.configured === true,
    needsApiKey: profile.configured !== true
  };
}

function validateMetadata(profile, patch, creating) {
  if (typeof patch.name === 'string' || creating) {
    profile.name = typeof patch.name === 'string' ? patch.name.trim() : '';
  }
  if (profile.name.length > 64) { fail('E_INVALID_ARGUMENT', '服务商名称最多 64 字符'); }
  if (typeof patch.provider === 'string' && patch.provider) { profile.provider = patch.provider; }
  if (!['openai-compatible', 'anthropic-compatible'].includes(profile.provider)) {
    fail('E_INVALID_ARGUMENT', '请选择 OpenAI 或 Anthropic 兼容接口');
  }
  if (typeof patch.baseUrl === 'string' && patch.baseUrl) { profile.baseUrl = address(patch.baseUrl); }
  if (!/^https?:\/\/[^\s\/?#@]+(?:\/[^\s?#]*)?$/i.test(profile.baseUrl) || profile.baseUrl.length > 8192) {
    fail('E_INVALID_ARGUMENT', 'Base URL 需为完整的 http(s) 地址，最多 8192 字符，不含账号、查询参数或片段');
  }
  if (typeof patch.model === 'string' && patch.model) { profile.model = patch.model.trim(); }
  if (!profile.model || profile.model.length > 128) {
    fail('E_INVALID_ARGUMENT', '模型名称长度必须在 1-128 之间');
  }
  if (typeof patch.maxTokens === 'number' && Number.isFinite(patch.maxTokens)) {
    profile.maxTokens = Math.max(512, Math.min(32768, Math.floor(patch.maxTokens)));
  }
  if (typeof patch.temperature === 'number' && Number.isFinite(patch.temperature)) {
    profile.temperature = Math.max(0, Math.min(2, patch.temperature));
  }
}

function normalizeBook(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { return null; }
  if (raw.version !== 2 || !Array.isArray(raw.profiles)) { return null; }
  if (raw.profiles.length > MAX_PROFILES) { return null; }
  const book = emptyBook();
  const ids = new Set();
  for (const item of raw.profiles) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) { return null; }
    if (typeof item.profileId !== 'string' || !item.profileId || ids.has(item.profileId)) { return null; }
    if (typeof item.provider !== 'string' || typeof item.baseUrl !== 'string' ||
      typeof item.model !== 'string') { return null; }
    ids.add(item.profileId);
    book.profiles.push({
      profileId: item.profileId,
      name: typeof item.name === 'string' ? item.name : '',
      provider: item.provider,
      baseUrl: item.baseUrl,
      model: item.model,
      maxTokens: typeof item.maxTokens === 'number' ? item.maxTokens : 8192,
      temperature: typeof item.temperature === 'number' ? item.temperature : 0.3,
      configured: item.configured === true
    });
  }
  book.activeProfileId = typeof raw.activeProfileId === 'string' ? raw.activeProfileId : '';
  if (book.activeProfileId && !ids.has(book.activeProfileId)) {
    book.activeProfileId = book.profiles.length ? book.profiles[0].profileId : '';
  }
  return book;
}

function findProfile(book, profileId) {
  return book.profiles.find((profile) => profile.profileId === profileId);
}

function createHostProfileContext(ctx) {
  const ai = {};
  let book = null;
  let loading = null;
  let mutations = Promise.resolve();
  let migrated = false;

  async function persist(next) {
    const json = JSON.stringify(next);
    if (json.length > MAX_STORAGE_CHARS) {
      fail('E_QUOTA_EXCEEDED', '服务商配置空间不足，请删除不再使用的服务商');
    }
    await ctx.storage.set(STORAGE_KEY, next);
    book = next;
  }

  function serialize(operation) {
    const next = mutations.catch(() => {}).then(operation);
    mutations = next;
    return next;
  }

  async function migrateLegacy() {
    if (migrated) { return emptyBook(); }
    migrated = true;
    const raw = await ctx.storage.get(LEGACY_KEY);
    if (!raw || typeof raw !== 'object' || Array.isArray(raw) || !Array.isArray(raw.profiles)) {
      return emptyBook();
    }
    const next = emptyBook();
    const legacyProfiles = raw.profiles.slice(0, MAX_PROFILES);
    let hasKey = false;
    let failed = false;
    for (const item of legacyProfiles) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) { continue; }
      if (typeof item.profileId !== 'string' || !item.profileId) { continue; }
      const key = typeof item.apiKey === 'string' ? item.apiKey.trim() : '';
      const metadata = {
        profileId: item.profileId,
        name: typeof item.name === 'string' ? item.name : '',
        provider: item.provider === 'anthropic-compatible' ? 'anthropic-compatible' : 'openai-compatible',
        baseUrl: typeof item.baseUrl === 'string' ? item.baseUrl : '',
        model: typeof item.model === 'string' ? item.model : '',
        maxTokens: typeof item.maxTokens === 'number' ? item.maxTokens : 8192,
        temperature: typeof item.temperature === 'number' ? item.temperature : 0.3
      };
      if (key.length > 0) {
        hasKey = true;
        try {
          await ctx.ai.configure({
            action: 'save', profileId: metadata.profileId, name: metadata.name,
            provider: metadata.provider, baseUrl: metadata.baseUrl, model: metadata.model,
            maxTokens: metadata.maxTokens, temperature: metadata.temperature,
            apiKey: key, select: false
          });
        } catch (error) {
          failed = true;
          ctx.log('warn', `迁移旧服务商「${serviceName(metadata, metadata.name)}」失败：${error && error.message || error}`);
          break;
        }
      }
      next.profiles.push(Object.assign({}, metadata, { configured: key.length > 0 }));
    }
    if (failed) {
      // Never leave a key in plugin storage when the host refused to take it. Keep the
      // metadata so the user can fix the URL and re-enter the key once.
      const scrubbed = copy(raw);
      if (Array.isArray(scrubbed.profiles)) {
        for (const item of scrubbed.profiles) {
          if (item && typeof item === 'object' && !Array.isArray(item)) { item.apiKey = ''; }
        }
      }
      await ctx.storage.set(LEGACY_KEY, scrubbed);
      ctx.log('warn', '旧服务商迁移失败，已清除插件存储中的 Key；请在模型设置中重新填写');
      return emptyBook();
    }
    next.activeProfileId = typeof raw.activeProfileId === 'string' ? raw.activeProfileId : '';
    if (next.activeProfileId && !findProfile(next, next.activeProfileId)) {
      next.activeProfileId = next.profiles.length ? next.profiles[0].profileId : '';
    }
    if (hasKey) {
      await persist(next);
      await ctx.storage.remove(LEGACY_KEY);
      const active = findProfile(next, next.activeProfileId);
      if (active && active.configured) {
        try { await ctx.ai.configure({ action: 'select', profileId: active.profileId }); }
        catch (error) { ctx.log('warn', `选择迁移后的服务商失败：${error && error.message || error}`); }
      }
    } else if (next.profiles.length > 0) {
      await persist(next);
      await ctx.storage.remove(LEGACY_KEY);
    }
    return next;
  }

  async function load() {
    if (book) { return book; }
    if (!loading) {
      loading = (async () => {
        const raw = await ctx.storage.get(STORAGE_KEY);
        const saved = normalizeBook(raw);
        if (!saved && raw !== null && raw !== undefined && raw !== '' && typeof raw === 'object') {
          fail('E_INVALID_ARGUMENT', '插件服务商配置损坏，请清除模型绑定后重试');
        }
        if (saved) {
          book = saved;
          // The v2 record is authoritative; any surviving v1 record is stale and must not
          // keep a key in plugin storage after a partial migration.
          await ctx.storage.remove(LEGACY_KEY);
        } else {
          book = await migrateLegacy();
        }
        await mergeHostStatus();
        return book;
      })();
    }
    try { return await loading; }
    finally { loading = null; }
  }

  async function mergeHostStatus() {
    let status = null;
    try { status = await ctx.ai.status(); } catch (error) { return; }
    if (!status || typeof status.profileId !== 'string' || !status.profileId) { return; }
    let profile = findProfile(book, status.profileId);
    if (!profile) {
      profile = {
        profileId: status.profileId,
        name: typeof status.name === 'string' ? status.name : '',
        provider: status.provider || 'openai-compatible',
        baseUrl: status.baseUrl || '',
        model: status.model || '',
        maxTokens: typeof status.maxTokens === 'number' ? status.maxTokens : 8192,
        temperature: typeof status.temperature === 'number' ? status.temperature : 0.3,
        balanceProvider: typeof status.balanceProvider === 'string' ? status.balanceProvider : '',
        configured: status.configured === true
      };
      book.profiles.push(profile);
    } else {
      profile.configured = status.configured === true;
      if (typeof status.balanceProvider === 'string') { profile.balanceProvider = status.balanceProvider; }
    }
    book.activeProfileId = status.profileId;
    await persist(book);
  }

  async function activeProfile() {
    const current = await load();
    return findProfile(current, current.activeProfileId);
  }

  ai.status = async function status() {
    await load();
    const currentStatus = await ctx.ai.status();
    if (currentStatus && typeof currentStatus.profileId === 'string' && currentStatus.profileId) {
      return currentStatus;
    }
    return publicProfile(await activeProfile());
  };

  ai.profiles = async function profiles() {
    const current = await load();
    return {
      activeProfileId: current.activeProfileId,
      profiles: current.profiles.map(publicProfile)
    };
  };

  ai.configure = function configure(patch) {
    return serialize(async () => {
      const current = await load();
      const before = copy(current);
      const action = patch && patch.clear ? 'clear' : ((patch && patch.action) || 'save');
      if (action === 'clear') {
        const next = emptyBook();
        await persist(next);
        try { await ctx.ai.configure({ clear: true }); }
        catch (error) { await persist(before); throw error; }
        return publicProfile(null);
      }
      if (action === 'select') {
        if (!patch || !patch.profileId) { fail('E_INVALID_ARGUMENT', '缺少服务商标识'); }
        const next = copy(current);
        next.activeProfileId = patch.profileId;
        await persist(next);
        try { await ctx.ai.configure({ action: 'select', profileId: patch.profileId }); }
        catch (error) { await persist(before); throw error; }
        return publicProfile(findProfile(next, patch.profileId));
      }
      if (action === 'remove') {
        if (!patch || !patch.profileId) { fail('E_INVALID_ARGUMENT', '缺少服务商标识'); }
        const next = copy(current);
        next.profiles = next.profiles.filter((profile) => profile.profileId !== patch.profileId);
        if (next.activeProfileId === patch.profileId) {
          next.activeProfileId = next.profiles.length ? next.profiles[0].profileId : '';
        }
        await persist(next);
        try { await ctx.ai.configure({ action: 'remove', profileId: patch.profileId }); }
        catch (error) { await persist(before); throw error; }
        return publicProfile(findProfile(next, next.activeProfileId));
      }
      const requestedId = patch && typeof patch.profileId === 'string' ? patch.profileId : '';
      const creating = action === 'create' || !requestedId || !findProfile(current, requestedId);
      const profileId = requestedId || newProfileId();
      const existing = findProfile(current, profileId);
      const previousBaseUrl = existing ? existing.baseUrl : '';
      const profile = existing ? copy(existing) : {
        profileId, name: '', provider: 'openai-compatible', baseUrl: '', model: '',
        maxTokens: 8192, temperature: 0.3, configured: false
      };
      profile.profileId = profileId;
      validateMetadata(profile, patch || {}, creating);
      const nextKey = patch && typeof patch.apiKey === 'string' ? patch.apiKey.trim() : '';
      if (creating && !nextKey) { fail('E_MISSING_CREDENTIAL', '首次绑定需要填写 API Key'); }
      if (!creating && !nextKey && address((patch && patch.baseUrl) || '') !== previousBaseUrl) {
        fail('E_INVALID_ARGUMENT', '更换 Base URL 时请重新填写 API Key');
      }
      const payload = {
        action: creating ? 'create' : 'save',
        profileId,
        name: profile.name,
        provider: profile.provider,
        baseUrl: profile.baseUrl,
        model: profile.model,
        maxTokens: profile.maxTokens,
        temperature: profile.temperature
      };
      if (nextKey) { payload.apiKey = nextKey; }
      if (!creating && current.activeProfileId && current.activeProfileId !== profileId) {
        payload.select = false;
      }
      // Local write first: a storage failure must leave the host binding untouched.
      profile.configured = !!nextKey || profile.configured;
      const next = copy(current);
      if (existing) {
        const index = next.profiles.findIndex((item) => item.profileId === profileId);
        next.profiles[index] = profile;
      } else {
        next.profiles.push(profile);
      }
      if (payload.select !== false) { next.activeProfileId = profileId; }
      if (!next.activeProfileId) { next.activeProfileId = profileId; }
      await persist(next);
      let saved;
      try { saved = await ctx.ai.configure(payload); }
      catch (error) { await persist(before); throw error; }
      const savedMatches = saved && typeof saved.profileId === 'string' && saved.profileId === profileId;
      const stillActive = saved && typeof saved.profileId === 'string' && saved.profileId
        ? saved.profileId : profileId;
      profile.configured = !!nextKey || profile.configured ||
        (savedMatches && saved.configured === true);
      if (existing) {
        const index = next.profiles.findIndex((item) => item.profileId === profileId);
        next.profiles[index] = profile;
      } else {
        next.profiles[next.profiles.length - 1] = profile;
      }
      if (payload.select !== false) { next.activeProfileId = stillActive; }
      if (!next.activeProfileId) { next.activeProfileId = stillActive; }
      try { await persist(next); } catch (error) {
        ctx.log('warn', `模型服务已绑定，但本地服务商列表保存失败：${error && error.message || error}`);
      }
      if (payload.select === false) {
        const activeStatus = await ctx.ai.status();
        if (activeStatus && activeStatus.profileId) { return activeStatus; }
      }
      return publicProfile(profile);
    });
  };

  ai.models = function models() { return ctx.ai.models(); };
  ai.chat = function chat(params) { return ctx.ai.chat(params); };
  ai.balance = function balance(options) { return ctx.ai.balance(options); };

  return { ai };
}

function createLegacyProfileContext(ctx) {
  let store = null;
  let loading = null;
  let mutations = Promise.resolve();
  let dispatches = Promise.resolve();
  const balances = new Map();

  function active(value) {
    return value.profiles.find(profile => profile.profileId === value.activeProfileId);
  }

  function legacyPublic(profile) {
    if (!profile) {
      return {
        configured: false, profileId: '', name: '', provider: '', baseUrl: '', model: '',
        maxTokens: 0, temperature: 0, balanceProvider: '', needsApiKey: true
      };
    }
    return {
      profileId: profile.profileId, name: profile.name,
      provider: profile.provider, baseUrl: profile.baseUrl, model: profile.model,
      maxTokens: profile.maxTokens, temperature: profile.temperature,
      configured: !!profile.apiKey || profile.hostManaged === true,
      needsApiKey: !profile.apiKey,
      balanceProvider: profile.balanceProvider || ''
    };
  }

  async function persist(next) {
    if (JSON.stringify(next).length > MAX_STORAGE_CHARS) {
      fail('E_QUOTA_EXCEEDED', '服务商配置空间不足，请删除不再使用的服务商或缩短地址');
    }
    await ctx.storage.set(LEGACY_KEY, next);
    store = next;
  }

  async function read() {
    const saved = await ctx.storage.get(LEGACY_KEY);
    if (saved !== null && saved !== undefined && saved !== '') {
      if (!saved || saved.version !== 1 || !Array.isArray(saved.profiles) || saved.profiles.length > MAX_PROFILES) {
        fail('E_INVALID_ARGUMENT', '插件服务商配置损坏，请恢复插件本地数据后重试');
      }
      const ids = new Set();
      for (const profile of saved.profiles) {
        if (!profile || typeof profile.profileId !== 'string' || !profile.profileId || ids.has(profile.profileId) ||
          typeof profile.apiKey !== 'string' || typeof profile.baseUrl !== 'string' || typeof profile.model !== 'string') {
          fail('E_INVALID_ARGUMENT', '插件服务商配置损坏，请恢复插件本地数据后重试');
        }
        ids.add(profile.profileId);
      }
      const next = copy(saved);
      if (!active(next)) { next.activeProfileId = next.profiles.length ? next.profiles[0].profileId : ''; }
      return next;
    }
    const next = { version: 1, activeProfileId: '', profiles: [] };
    const bound = await ctx.ai.status();
    if (bound && bound.configured) {
      next.profiles.push({
        profileId: 'legacy', name: '', provider: bound.provider, baseUrl: address(bound.baseUrl),
        model: bound.model, apiKey: '', hostManaged: true,
        maxTokens: bound.maxTokens || 8192, temperature: typeof bound.temperature === 'number' ? bound.temperature : 0.3,
        balanceProvider: bound.balanceProvider || ''
      });
      next.activeProfileId = 'legacy';
    }
    await persist(next);
    return next;
  }

  async function load() {
    if (store) { return store; }
    if (!loading) { loading = read(); }
    try { store = await loading; return store; }
    finally { loading = null; }
  }

  function validate(profile, patch, creating) {
    validateMetadata(profile, patch, creating);
    if (typeof patch.apiKey === 'string' && patch.apiKey.trim()) {
      if (patch.apiKey.trim().length > 8192) { fail('E_INVALID_ARGUMENT', 'API Key 过长'); }
      profile.apiKey = patch.apiKey.trim();
      profile.hostManaged = false;
    }
    if ((creating || !profile.hostManaged) && !profile.apiKey) {
      fail('E_INVALID_ARGUMENT', '请填写此服务商的 API Key');
    }
  }

  async function mutate(patch) {
    const before = await load();
    const next = copy(before);
    const action = patch.clear ? 'remove' : patch.action || 'save';
    if (!['save', 'create', 'select', 'remove'].includes(action)) { fail('E_INVALID_ARGUMENT', '未知服务商操作'); }
    const id = patch.profileId || next.activeProfileId;
    const previous = next.profiles.find(profile => profile.profileId === id);
    if ((patch.profileId || action === 'select') && !previous) { fail('E_NOT_FOUND', '服务商不存在，请刷新后重试'); }
    if (action === 'select') {
      if (!previous.apiKey && !previous.hostManaged) {
        fail('E_MODEL_UNAVAILABLE', `请先编辑「${serviceName(previous, previous.name)}」补填 API Key，旧宿主无法读回原 Key`);
      }
      next.activeProfileId = previous.profileId;
    } else if (action === 'remove') {
      next.profiles = next.profiles.filter(profile => profile.profileId !== id);
      if (id === next.activeProfileId) { next.activeProfileId = next.profiles.length ? next.profiles[0].profileId : ''; }
    } else {
      const creating = action === 'create' || !previous;
      if (creating && next.profiles.length >= MAX_PROFILES) { fail('E_QUOTA_EXCEEDED', '最多保存 32 个服务商'); }
      const profile = creating ? {
        profileId: `service_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e9).toString(36)}`,
        name: '', provider: 'openai-compatible', baseUrl: '', model: '', apiKey: '',
        hostManaged: false, maxTokens: 8192, temperature: 0.3
      } : previous;
      if (!creating && typeof patch.baseUrl === 'string' && address(patch.baseUrl) !== profile.baseUrl && !text(patch.apiKey).trim()) {
        fail('E_INVALID_ARGUMENT', '更换 Base URL 时请重新填写 API Key');
      }
      validate(profile, patch, creating);
      if (creating) { next.profiles.push(profile); next.activeProfileId = profile.profileId; }
    }
    if (next.activeProfileId !== store.activeProfileId) {
      for (const profile of next.profiles) { if (!profile.apiKey) { profile.hostManaged = false; } }
    }
    await persist(next);
    balances.delete(id);
    try {
      await enqueueDispatch(async () => {
        const selected = active(next);
        if (action === 'remove') {
          const bound = await ctx.ai.status();
          if (!selected || (previous && sameService(previous, bound) && !selected.hostManaged)) {
            await ctx.ai.configure({ clear: true });
          }
        }
        if (selected && (selected.apiKey || selected.hostManaged) &&
          (action === 'select' || selected.profileId !== before.activeProfileId || id === selected.profileId)) {
          await ensureBinding(selected);
        }
      });
    } catch (failure) {
      await persist(before);
      throw failure;
    }
    return legacyPublic(active(next));
  }

  function sameService(left, right) {
    return !!left && !!right && left.provider === right.provider && address(left.baseUrl) === address(right.baseUrl);
  }

  function enqueueDispatch(start) {
    const dispatched = dispatches.catch(() => {}).then(start);
    dispatches = dispatched;
    return dispatched;
  }

  async function ensureBinding(profile) {
    if (!profile) { fail('E_MODEL_UNAVAILABLE', '请先添加模型服务商'); }
    if (!profile.apiKey) {
      const current = (await load()).profiles.find(item => item.profileId === profile.profileId);
      const bound = await ctx.ai.status();
      if (!current || !current.hostManaged || !sameService(profile, bound) || !bound.configured) {
        fail('E_MODEL_UNAVAILABLE', `请编辑「${serviceName(profile, profile.name)}」补填 API Key，旧宿主无法读回原 Key`);
      }
      if (bound.model !== profile.model) { await ctx.ai.configure({ model: profile.model }); }
      return;
    }
    await ctx.ai.configure({ provider: profile.provider, baseUrl: profile.baseUrl, model: profile.model,
      apiKey: profile.apiKey, maxTokens: profile.maxTokens, temperature: profile.temperature });
  }

  async function request(method, params) {
    const profile = active(await load());
    if (typeof ctx.ai[method] !== 'function') { fail('E_UNSUPPORTED_API', `当前知萤未提供 ${method} 接口`); }
    let reply;
    await enqueueDispatch(async () => {
      await ensureBinding(profile);
      reply = { promise: ctx.ai[method](params) };
      reply.promise.catch(() => {});
    });
    return reply.promise;
  }

  const ai = {
    async status() {
      const selected = active(await load());
      if (selected && selected.hostManaged) {
        const bound = await ctx.ai.status();
        return legacyPublic(Object.assign({}, selected, { hostManaged: !!bound.configured && sameService(selected, bound) }));
      }
      return legacyPublic(selected);
    },
    async profiles() {
      const value = await load();
      return { activeProfileId: value.activeProfileId, profiles: value.profiles.map(legacyPublic) };
    },
    configure(patch) {
      const nextPatch = copy(patch || {});
      const result = mutations.catch(() => {}).then(() => mutate(nextPatch));
      mutations = result;
      return result;
    },
    models() { return request('models'); },
    chat(params) { return request('chat', params); },
    async balance(options) {
      const profile = active(await load());
      const saved = profile && balances.get(profile.profileId);
      if (!(options && options.force) && saved && saved.profile === profile && Date.now() - saved.at < 60000) {
        return copy(saved.value);
      }
      const value = await request('balance');
      if (profile) { balances.set(profile.profileId, { profile, at: Date.now(), value: copy(value) }); }
      return value;
    }
  };
  return Object.assign({}, ctx, { ai });
}

/**
 * Chooses the host-backed store when the host can address profiles by id. The probe is
 * `status().profileId`, which only hosts with per-profile bindings return; older hosts
 * keep the legacy single-binding behaviour and never see the new fields.
 */
function createProfileContext(ctx) {
  let mode = '';
  let host = null;
  let legacy = null;

  async function choose() {
    if (mode) { return mode; }
    let status = null;
    try { status = await ctx.ai.status(); } catch (error) { status = null; }
    if (status && typeof status.profileId === 'string') {
      host = createHostProfileContext(ctx);
      mode = 'host';
    } else {
      legacy = createLegacyProfileContext(ctx);
      mode = 'legacy';
      try { ctx.log('warn', '当前知萤宿主不支持按服务商隔离的密钥存储；API Key 仍保存在插件本地数据中，请升级知萤后重新保存服务商。'); } catch (error) { /* logging is optional */ }
    }
    return mode;
  }

  const ai = {
    async status() {
      return (await choose()) === 'host' ? host.ai.status() : legacy.ai.status();
    },
    async profiles() {
      return (await choose()) === 'host' ? host.ai.profiles() : legacy.ai.profiles();
    },
    async configure(patch) {
      return (await choose()) === 'host' ? host.ai.configure(patch) : legacy.ai.configure(patch);
    },
    async models() {
      return (await choose()) === 'host' ? host.ai.models() : legacy.ai.models();
    },
    async chat(params) {
      return (await choose()) === 'host' ? host.ai.chat(params) : legacy.ai.chat(params);
    },
    async balance(options) {
      return (await choose()) === 'host' ? host.ai.balance(options) : legacy.ai.balance(options);
    }
  };
  return Object.assign({}, ctx, { ai });
}

module.exports = { createProfileContext, STORAGE_KEY, LEGACY_KEY };
