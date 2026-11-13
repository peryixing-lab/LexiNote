'use strict';

/**
 * LexiNote JavaScript plugin runtime entry point.
 *
 * The host owns one WebView per active plugin and talks to this module through the
 * `window.__lexiRuntime` object:
 *
 *   __lexiRuntime.boot(jsonString)            // once per load
 *   __lexiRuntime.receiveResponse(jsonString) // late answers to bridge.request
 *   __lexiRuntime.receiveEvent(jsonString)    // core events
 *   __lexiRuntime.runCommand(qualifiedId)     // "<pluginId>:<localId>"
 *   __lexiRuntime.unload()                    // teardown
 *
 * Every entry point is defensive: malformed input, an unknown plugin id or a throwing
 * plugin must never escape into the host as an uncaught exception. Failures are logged
 * through the bridge and reported in the returned result object.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  normalizeVaultPath,
  parseJson,
  rawErrorMessage
} = require('./util');
const { FileMirror } = require('./mirror');
const { PluginBridge } = require('./bridge');
const { executeBundle, validateManifest } = require('./loader');
const sdk = require('./sdk');
const { createObsidianApi } = require('./obsidian');

const PROTOCOL_VERSION = 1;
const RUNTIME_VERSION = '1';

/** Exactly one plugin instance may be alive per WebView. */
let active = null;
/** The instance currently running its teardown callback; responses still route to it. */
let closing = null;

function localLog(level, message) {
  const target = active || closing;
  if (target && target.bridge) {
    target.bridge.log(level, message);
  }
}

function parseBoot(raw) {
  let payload = raw;
  if (typeof raw === 'string') {
    if (raw.length === 0) {
      throw createError(ERROR_CODES.PROTOCOL, 'boot 载荷为空');
    }
    try {
      payload = JSON.parse(raw);
    } catch (error) {
      throw createError(ERROR_CODES.PROTOCOL, 'boot 载荷不是合法 JSON');
    }
  }
  if (!isPlainObject(payload)) {
    throw createError(ERROR_CODES.PROTOCOL, 'boot 载荷必须是对象');
  }
  if (payload.type !== undefined && payload.type !== 'boot') {
    throw createError(ERROR_CODES.PROTOCOL, `未知 boot 类型 ${String(payload.type)}`);
  }
  if (payload.protocol !== PROTOCOL_VERSION) {
    throw createError(ERROR_CODES.PROTOCOL, `不支持的协议版本 ${String(payload.protocol)}`);
  }
  if (typeof payload.pluginId !== 'string' || payload.pluginId.length === 0) {
    throw createError(ERROR_CODES.PROTOCOL, 'boot 缺少 pluginId');
  }
  const kind = payload.kind === 'obsidian' ? 'obsidian' : 'lexinote';
  if (payload.kind !== undefined && payload.kind !== 'lexinote' && payload.kind !== 'obsidian') {
    throw createError(ERROR_CODES.PROTOCOL, `不支持的插件类型 ${String(payload.kind)}`);
  }
  if (typeof payload.sourceCode !== 'string') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'boot 缺少 sourceCode');
  }
  return {
    type: 'boot',
    protocol: PROTOCOL_VERSION,
    pluginId: payload.pluginId,
    kind,
    token: typeof payload.token === 'string' ? payload.token : '',
    runtimeVersion: typeof payload.runtimeVersion === 'string' ? payload.runtimeVersion : RUNTIME_VERSION,
    capabilities: Array.isArray(payload.capabilities)
      ? payload.capabilities.filter((item) => typeof item === 'string')
      : [],
    vaultId: typeof payload.vaultId === 'string' ? payload.vaultId : '',
    manifestJson: typeof payload.manifestJson === 'string' ? payload.manifestJson : '{}',
    filesJson: typeof payload.filesJson === 'string' ? payload.filesJson : '[]',
    activeFileJson: typeof payload.activeFileJson === 'string' ? payload.activeFileJson : 'null',
    editorJson: typeof payload.editorJson === 'string' ? payload.editorJson : 'null',
    settingsJson: typeof payload.settingsJson === 'string' ? payload.settingsJson : 'null',
    dataJson: typeof payload.dataJson === 'string' ? payload.dataJson : '{}',
    sourceCode: payload.sourceCode,
    stylesCss: typeof payload.stylesCss === 'string' ? payload.stylesCss : '',
    platform: typeof payload.platform === 'string' && payload.platform.length > 0 ? payload.platform : 'win32',
    sourceName: typeof payload.sourceName === 'string' && payload.sourceName.length > 0
      ? payload.sourceName
      : 'main.js',
    warnings: Array.isArray(payload.warnings)
      ? payload.warnings.filter((item) => typeof item === 'string')
      : []
  };
}

function createInstance(payload, options) {
  const config = isPlainObject(options) ? options : {};
  const mirror = new FileMirror();
  mirror.load(payload);
  const bridge = new PluginBridge({
    pluginId: payload.pluginId,
    token: payload.token,
    timeoutMs: config.requestTimeoutMs,
    maxInFlight: config.maxInFlight,
    sendProvider: () => (typeof globalThis !== 'undefined' ? globalThis.lexiPluginBridge : null)
  });
  const context = sdk.createContext({
    boot: payload,
    bridge,
    mirror,
    log: (level, message) => {
      if (typeof config.log === 'function') {
        try {
          config.log(level, message);
        } catch (error) {
          // ignore
        }
      }
    }
  });
  const manifest = parseJson(payload.manifestJson, {});
  const obsidianApi = createObsidianApi({
    context,
    mirror,
    pluginId: payload.pluginId,
    vaultId: payload.vaultId,
    manifest,
    platform: payload.platform,
    onUiHook: (event) => {
      if (typeof globalThis !== 'undefined' && typeof globalThis.__lexiDesktopUiHook === 'function') {
        globalThis.__lexiDesktopUiHook(event);
      }
    },
    log: (level, message) => {
      if (typeof config.log === 'function') {
        try {
          config.log(level, message);
        } catch (error) {
          // ignore
        }
      }
    }
  });
  obsidianApi.__internal.setStyles(payload.stylesCss);

  const warnings = payload.warnings.slice();
  const check = validateManifest(manifest, payload.kind);
  if (!check.ok) {
    warnings.push(`manifest 校验失败：${check.errors.join('；')}`);
  }
  for (let index = 0; index < check.warnings.length; index += 1) {
    warnings.push(check.warnings[index]);
  }

  return {
    pluginId: payload.pluginId,
    kind: payload.kind,
    payload,
    mirror,
    bridge,
    context,
    obsidianApi,
    manifest,
    warnings,
    definition: null,
    plugin: null,
    activated: false,
    startedAt: Date.now()
  };
}

async function startLexinote(instance) {
  const modules = {
    obsidian: instance.obsidianApi,
    sdk,
    '@lexinote/sdk': sdk
  };
  const exported = executeBundle(instance.payload.sourceCode, modules, instance.payload.sourceName);
  let definition = null;
  if (exported && exported.__lexinote === true && typeof exported.activate === 'function') {
    definition = exported;
  } else if (exported && exported.default && exported.default.__lexinote === true && typeof exported.default.activate === 'function') {
    definition = exported.default;
  } else if (exported && typeof exported.activate === 'function') {
    // Tolerant path: a hand-written bundle that did not use definePlugin().
    definition = {
      __lexinote: true,
      activate: exported.activate,
      deactivate: typeof exported.deactivate === 'function' ? exported.deactivate : function noop() {}
    };
  }
  if (!definition) {
    throw createError(
      ERROR_CODES.PLUGIN_FAILED,
      '插件必须通过 definePlugin({ activate, deactivate }) 导出'
    );
  }
  instance.definition = definition;
  await Promise.resolve(definition.activate(instance.context));
  instance.activated = true;
}

async function startObsidian(instance) {
  const modules = {
    obsidian: instance.obsidianApi,
    sdk,
    '@lexinote/sdk': sdk
  };
  const exported = executeBundle(instance.payload.sourceCode, modules, instance.payload.sourceName);
  let plugin = null;
  const constructor = typeof exported === 'function' ? exported : exported && exported.default;
  if (typeof constructor === 'function') {
    plugin = new constructor(instance.obsidianApi.app, instance.manifest);
  }
  if (exported && typeof exported === 'object') {
    if (typeof exported.onload === 'function') {
      plugin = exported;
    } else if (exported.default && typeof exported.default.onload === 'function') {
      plugin = exported.default;
    }
  }
  if (!plugin) {
    throw createError(
      ERROR_CODES.PLUGIN_FAILED,
      'Obsidian 插件必须导出 Plugin 类或实例'
    );
  }
  instance.obsidianApi.__internal.setPlugin(plugin);
  instance.plugin = plugin;
  await Promise.resolve(plugin.onload());
  instance.activated = true;
}

async function closeInstance(instance) {
  if (!instance || instance.closed) {
    return false;
  }
  instance.closed = true;
  try {
    if (instance.kind === 'obsidian' && instance.plugin && typeof instance.plugin.onunload === 'function') {
      await Promise.resolve(instance.plugin.onunload());
    } else if (instance.kind === 'lexinote' && instance.activated && instance.definition) {
      await Promise.resolve(instance.definition.deactivate());
    }
  } catch (error) {
    localLog('error', `插件清理回调失败：${rawErrorMessage(error)}`);
  }
  try {
    await instance.obsidianApi.__internal.releasePlugin();
  } catch (error) {
    localLog('error', `Obsidian 资源释放失败：${rawErrorMessage(error)}`);
  }
  try {
    instance.context.__internal.dispose();
  } catch (error) {
    localLog('error', `订阅释放失败：${rawErrorMessage(error)}`);
  }
  try {
    instance.bridge.close();
  } catch (error) {
    // Bridge teardown must never throw.
  }
  return true;
}

/** Boots one plugin. Replaces (and fully unloads) any previous instance first. */
async function boot(raw, options) {
  if (active) {
    await unload();
  }
  let payload;
  try {
    payload = parseBoot(raw);
  } catch (error) {
    return {
      ok: false,
      pluginId: '',
      kind: '',
      code: error.code || ERROR_CODES.PROTOCOL,
      error: rawErrorMessage(error)
    };
  }

  let instance = null;
  try {
    instance = createInstance(payload, options);
    active = instance;
    if (payload.kind === 'obsidian') {
      await startObsidian(instance);
    } else {
      await startLexinote(instance);
    }
    return {
      ok: true,
      pluginId: instance.pluginId,
      kind: instance.kind,
      warnings: instance.warnings.slice()
    };
  } catch (error) {
    const failure = sdk.normalizeFailure(error, ERROR_CODES.PLUGIN_FAILED);
    if (instance && instance.bridge) {
      instance.bridge.log('error', `插件启动失败：${rawErrorMessage(failure)}`);
    }
    if (active === instance) {
      active = null;
    }
    if (instance) {
      closing = instance;
      try {
        await closeInstance(instance);
      } finally {
        if (closing === instance) {
          closing = null;
        }
      }
    }
    return {
      ok: false,
      pluginId: payload.pluginId,
      kind: payload.kind,
      code: failure.code || ERROR_CODES.PLUGIN_FAILED,
      error: rawErrorMessage(failure)
    };
  }
}

/** Handles one late RPC response. Unknown ids are dropped inside the bridge. */
function receiveResponse(raw) {
  const target = active || closing;
  if (!target || !target.bridge) {
    return false;
  }
  try {
    return target.bridge.handleResponse(raw);
  } catch (error) {
    localLog('warn', `处理响应失败：${rawErrorMessage(error)}`);
    return false;
  }
}

function eventRefFromPayload(instance, payload) {
  if (isPlainObject(payload.file)) {
    try {
      return instance.mirror.upsert(payload.file);
    } catch (error) {
      return null;
    }
  }
  const id = typeof payload.fileId === 'string' && payload.fileId.length > 0
    ? payload.fileId
    : (typeof payload.id === 'string' ? payload.id : '');
  const path = typeof payload.path === 'string' ? normalizeVaultPath(payload.path) : '';
  const existing = id ? instance.mirror.getById(id) : (path ? instance.mirror.getByPath(path) : null);
  if (existing) {
    if (path.length === 0 || existing.path === path) {
      return existing;
    }
    return {
      id: existing.id,
      vaultId: existing.vaultId,
      projectId: existing.projectId,
      path,
      name: existing.name,
      extension: existing.extension,
      kind: existing.kind,
      size: existing.size,
      ctime: existing.ctime,
      mtime: typeof payload.at === 'number' ? payload.at : existing.mtime
    };
  }
  if (id.length === 0 || path.length === 0) {
    return null;
  }
  const at = typeof payload.at === 'number' && isFinite(payload.at) ? payload.at : Date.now();
  return {
    id,
    vaultId: typeof payload.vaultId === 'string' ? payload.vaultId : instance.payload.vaultId,
    projectId: typeof payload.projectId === 'string' ? payload.projectId : '',
    path,
    name: '',
    extension: '',
    kind: 'file',
    size: 0,
    ctime: at,
    mtime: at
  };
}

function applyEventToMirror(instance, eventName, payload) {
  const mirror = instance.mirror;
  const ref = eventRefFromPayload(instance, payload);
  const oldPath = typeof payload.oldPath === 'string'
    ? normalizeVaultPath(payload.oldPath)
    : (typeof payload.previousPath === 'string' ? normalizeVaultPath(payload.previousPath) : '');

  let deletedFile = null;
  if (eventName === 'vault.deleted' && ref) {
    // Capture the existing TFile before the mirror forgets the file, so delete handlers
    // receive the same instance that listings just returned.
    try {
      deletedFile = instance.obsidianApi.__internal.fileForRef(ref);
    } catch (error) {
      deletedFile = null;
    }
  }

  if (eventName === 'vault.created' || eventName === 'vault.modified') {
    if (ref) {
      mirror.upsert(ref);
    }
  } else if (eventName === 'vault.renamed') {
    if (ref) {
      mirror.upsert(ref);
    } else if (oldPath.length > 0) {
      const previous = mirror.getByPath(oldPath);
      if (previous && typeof payload.path === 'string') {
        mirror.upsert({
          id: previous.id,
          vaultId: previous.vaultId,
          projectId: previous.projectId,
          path: payload.path,
          name: previous.name,
          extension: previous.extension,
          kind: previous.kind,
          size: previous.size,
          ctime: previous.ctime,
          mtime: previous.mtime
        });
      }
    }
  } else if (eventName === 'vault.deleted') {
    if (ref && ref.id) {
      mirror.removeById(ref.id);
    } else if (payload.path) {
      mirror.removeByPath(payload.path);
    }
  } else if (eventName === 'workspace.active-file-changed') {
    if (ref) {
      mirror.upsert(ref);
      mirror.setActiveFile(ref);
    }
  } else if (eventName === 'editor.changed') {
    const editor = mirror.editor();
    if (editor) {
      const patch = {};
      if (typeof payload.content === 'string') {
        patch.content = payload.content;
      }
      if (typeof payload.revision === 'number') {
        patch.version = payload.revision;
      }
      if (typeof payload.dirty === 'boolean') {
        patch.dirty = payload.dirty;
      }
      if (Object.keys(patch).length > 0) {
        mirror.patchEditor(patch);
      }
    }
  } else if (eventName === 'metadata.resolved') {
    if (ref && isPlainObject(payload.metadata)) {
      mirror.setMetadata(ref.id, payload.metadata);
    }
  }
  return { ref, oldPath, deletedFile };
}

function emitObsidianEvent(instance, eventName, payload, contextInfo) {
  const api = instance.obsidianApi;
  const internal = api.__internal;
  const vault = internal.vault;
  internal.syncVault();

  if (eventName === 'vault.created' || eventName === 'vault.modified') {
    const file = contextInfo.ref ? internal.fileForRef(contextInfo.ref) : null;
    if (file) {
      if (eventName === 'vault.modified') {
        internal.invalidateContent(contextInfo.ref);
      }
      internal.emitVaultEvent(eventName === 'vault.created' ? 'create' : 'modify', file);
    }
  } else if (eventName === 'vault.renamed') {
    const file = contextInfo.ref ? internal.fileForRef(contextInfo.ref) : null;
    if (file) {
      internal.emitVaultEvent('rename', file, contextInfo.oldPath);
    }
  } else if (eventName === 'vault.deleted') {
    if (contextInfo.deletedFile) {
      internal.emitVaultEvent('delete', contextInfo.deletedFile);
    }
  } else if (eventName === 'workspace.active-file-changed') {
    const activeRef = instance.mirror.activeFile();
    const file = activeRef ? internal.fileForRef(activeRef) : null;
    if (file) {
      internal.emitWorkspaceEvent('file-open', file);
    }
    const view = internal.getActiveView();
    internal.emitWorkspaceEvent('active-leaf-change', view ? view.leaf : null);
  }
}

/** Dispatches one core event. Returns false for malformed or foreign messages. */
function receiveEvent(raw) {
  if (!active) {
    return false;
  }
  let message = raw;
  if (typeof raw === 'string') {
    try {
      message = JSON.parse(raw);
    } catch (error) {
      localLog('warn', `事件不是合法 JSON：${rawErrorMessage(error)}`);
      return false;
    }
  }
  if (!isPlainObject(message)) {
    return false;
  }
  if (message.protocol !== undefined && message.protocol !== PROTOCOL_VERSION) {
    return false;
  }
  if (message.type !== undefined && message.type !== 'event') {
    return false;
  }
  if (typeof message.event !== 'string' || message.event.length === 0) {
    return false;
  }
  if (typeof message.pluginId === 'string' && message.pluginId !== active.pluginId) {
    return false;
  }
  const eventName = message.event;
  let payload = message.payload;
  if (typeof payload === 'string') {
    payload = parseJson(payload, {});
  }
  if (!isPlainObject(payload)) {
    payload = {};
  }
  if (!isPlainObject(message.payload)) {
    // The ArkTS host sends the core event fields at the top level:
    // `{event, seq, fileId, path, oldPath, vaultId, revision}`. Accept that shape as
    // well as the documented `{payload: "<json>"}` envelope.
    const keys = Object.keys(message);
    for (let index = 0; index < keys.length; index += 1) {
      const key = keys[index];
      if (key === 'protocol' || key === 'type' || key === 'pluginId' || key === 'event' || key === 'payload') {
        continue;
      }
      if (!Object.prototype.hasOwnProperty.call(payload, key)) {
        payload[key] = message[key];
      }
    }
    if (payload.type === undefined) {
      payload.type = eventName;
    }
    if (payload.seq === undefined && typeof message.seq === 'number') {
      payload.seq = message.seq;
    }
  }

  const instance = active;
  try {
    const contextInfo = applyEventToMirror(instance, eventName, payload);
    instance.context.__internal.dispatchEvent(eventName, payload, {
      event: eventName,
      seq: typeof message.seq === 'number' ? message.seq : 0,
      pluginId: instance.pluginId
    });
    if (instance.kind === 'obsidian') {
      emitObsidianEvent(instance, eventName, payload, contextInfo);
    }
    return true;
  } catch (error) {
    localLog('error', `事件 ${eventName} 处理失败：${rawErrorMessage(error)}`);
    return false;
  }
}

/** Invokes a command by qualified id; failures are logged, never propagated. */
function runCommand(qualifiedId) {
  if (!active) {
    return false;
  }
  if (typeof qualifiedId !== 'string') {
    return false;
  }
  const colon = qualifiedId.indexOf(':');
  if (colon <= 0 || colon === qualifiedId.length - 1) {
    return false;
  }
  const pluginId = qualifiedId.slice(0, colon);
  const localId = qualifiedId.slice(colon + 1);
  if (pluginId !== active.pluginId) {
    localLog('warn', `拒绝执行其他插件的命令 ${qualifiedId}`);
    return false;
  }
  const instance = active;
  if (!instance.context.__internal.commandMap.has(localId)) {
    instance.bridge.log('warn', `命令不存在：${localId}`);
    return false;
  }
  try {
    const outcome = instance.context.__internal.runCommand(localId);
    if (outcome && typeof outcome.then === 'function') {
      outcome.catch((error) => {
        instance.bridge.log('error', `命令 ${localId} 执行失败：${rawErrorMessage(error)}`);
      });
    }
    return true;
  } catch (error) {
    instance.bridge.log('error', `命令 ${localId} 执行失败：${rawErrorMessage(error)}`);
    return false;
  }
}

/** Tears the active instance down. Safe to call before boot or twice. */
async function unload() {
  const instance = active;
  active = null;
  if (!instance) {
    return false;
  }
  closing = instance;
  try {
    return await closeInstance(instance);
  } finally {
    if (closing === instance) {
      closing = null;
    }
  }
}

/** Diagnostic view used by the regression harness; not part of the host contract. */
function inspect() {
  const instance = active;
  if (!instance) {
    return {
      active: false,
      pluginId: '',
      kind: '',
      commands: [],
      subscriptions: 0,
      bridge: null,
      context: null,
      obsidianApi: null,
      mirror: null
    };
  }
  return {
    active: true,
    pluginId: instance.pluginId,
    kind: instance.kind,
    commands: Array.from(instance.context.__internal.commandMap.keys()),
    subscriptions: instance.context.subscriptions.size,
    bridge: instance.bridge,
    context: instance.context,
    obsidianApi: instance.obsidianApi,
    mirror: instance.mirror,
    warnings: instance.warnings.slice(),
    activated: instance.activated
  };
}

// Exactly the five host-facing entry points are enumerable. Diagnostics stay available
// but non-enumerable so the host contract is not accidentally widened.
const runtime = {
  boot,
  receiveResponse,
  receiveEvent,
  runCommand,
  async present(viewId) {
    if (!active) { return { ok: false, error: '没有正在运行的插件' }; }
    try {
      if (active.kind === 'obsidian') {
        await active.obsidianApi.__internal.present();
      } else {
        await active.context.__internal.presentView(typeof viewId === 'string' ? viewId : '');
      }
      return { ok: true };
    } catch (error) {
      active.bridge.log('error', `插件视图加载失败：${rawErrorMessage(error)}`);
      return { ok: false, error: rawErrorMessage(error) };
    }
  },
  async triggerRibbon(id) {
    if (!active || active.kind !== 'obsidian') { return false; }
    try {
      return await active.obsidianApi.__internal.triggerRibbon(id);
    } catch (error) {
      active.bridge.log('error', `功能区按钮执行失败：${rawErrorMessage(error)}`);
      return false;
    }
  },
  unload
};
Object.defineProperties(runtime, {
  inspect: { value: inspect, enumerable: false, writable: false },
  __inspect: { value: inspect, enumerable: false, writable: false },
  protocol: { value: PROTOCOL_VERSION, enumerable: false, writable: false },
  runtimeVersion: { value: RUNTIME_VERSION, enumerable: false, writable: false }
});

if (typeof globalThis !== 'undefined') {
  globalThis.__lexiRuntime = runtime;
  if (typeof globalThis.window !== 'undefined' && globalThis.window !== globalThis) {
    globalThis.window.__lexiRuntime = runtime;
  }
}

module.exports = runtime;
