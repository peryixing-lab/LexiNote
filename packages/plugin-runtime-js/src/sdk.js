'use strict';

/**
 * The LexiNote plugin SDK.
 *
 * `definePlugin({ activate, deactivate })` marks a plugin bundle; the runtime calls
 * `activate(context)` once after boot and `deactivate()` during unload. Every native
 * operation is promise based and goes through the host RPC table documented in
 * docs/plugin-system and PluginContracts.ets. Nothing here touches the DOM or Node.js.
 *
 * Error rules:
 *  - host failures keep the host code (`E_*`) and the `"<code>: <detail>"` message;
 *  - a missing capability/method is rejected with `E_UNSUPPORTED_API` only when the host
 *    actually refuses it — the SDK never fabricates a successful result.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  normalizeVaultPath,
  toJsonText,
  rawErrorMessage
} = require('./util');

/** Public SDK semver-ish surface, independent from the host runtime version. */
const apiVersion = '1.1';
const runtimeVersion = '1';

/** Model turns are slow; the generic 15 s RPC budget would abort healthy requests. */
const AI_TIMEOUT_MS = 120000;
const VIEW_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;

// Must match the host rule in PluginCommandRegistry (`^[a-z0-9][a-z0-9._-]{0,63}$`), so an
// author sees the same rejection locally instead of a host-side log line after activation.
const COMMAND_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;

/**
 * Minimal disposable helper. `DISPOSABLE(fn)` runs `fn` exactly once, on the first
 * `dispose()` call; `dispose()` after that is a no-op.
 */
function DISPOSABLE(dispose) {
  let disposed = false;
  const disposable = {
    get disposed() {
      return disposed;
    },
    dispose() {
      if (disposed) {
        return;
      }
      disposed = true;
      if (typeof dispose === 'function') {
        dispose();
      }
    }
  };
  return disposable;
}

DISPOSABLE.NONE = Object.freeze({
  disposed: true,
  dispose() {}
});

function normalizeDisposable(value) {
  if (typeof value === 'function') {
    return DISPOSABLE(value);
  }
  if (!value || typeof value.dispose !== 'function') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'subscriptions.add 需要 Disposable 或函数');
  }
  return value;
}

/**
 * Declares a LexiNote plugin. The returned frozen marker object is what the runtime
 * loads from `module.exports`.
 */
function definePlugin(definition) {
  if (!isPlainObject(definition) || typeof definition.activate !== 'function') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'definePlugin 需要 { activate(ctx), deactivate?() }');
  }
  if (definition.deactivate !== undefined && typeof definition.deactivate !== 'function') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'deactivate 必须是函数');
  }
  const activate = definition.activate;
  const deactivate = typeof definition.deactivate === 'function'
    ? definition.deactivate
    : function noopDeactivate() {};
  return Object.freeze({
    __lexinote: true,
    activate,
    deactivate
  });
}

function decodeStoredValue(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    return value;
  }
  if (value.length === 0) {
    return null;
  }
  try {
    return JSON.parse(value);
  } catch (error) {
    // Older/foreign data may be a raw string rather than JSON text; return it unchanged
    // instead of pretending it did not exist.
    return value;
  }
}

/**
 * Creates the context object handed to `activate()`.
 *
 * @param {object} options
 * @param {object} options.boot parsed boot payload
 * @param {import('./bridge').PluginBridge} options.bridge
 * @param {import('./mirror').FileMirror} options.mirror
 * @param {Function} [options.log] local diagnostic sink
 */
function createContext(options) {
  const settings = isPlainObject(options) ? options : {};
  const boot = isPlainObject(settings.boot) ? settings.boot : {};
  const bridge = settings.bridge;
  const mirror = settings.mirror;
  if (!bridge || typeof bridge.request !== 'function') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'createContext 缺少 bridge');
  }
  if (!mirror || typeof mirror.getByPath !== 'function') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'createContext 缺少 mirror');
  }

  const pluginId = typeof boot.pluginId === 'string' ? boot.pluginId : '';
  const vaultId = typeof boot.vaultId === 'string' ? boot.vaultId : '';
  const capabilities = Array.isArray(boot.capabilities)
    ? boot.capabilities.filter((item) => typeof item === 'string')
    : [];

  const localLogger = typeof settings.log === 'function' ? settings.log : function noopLog() {};
  let disposed = false;

  const commandMap = new Map();
  const handlersByEvent = new Map();
  const disposables = [];

  function log(level, message) {
    const severity = typeof level === 'string' && level.length > 0 ? level : 'info';
    const text = typeof message === 'string' ? message : String(message);
    localLogger(severity, text);
    bridge.log(severity, text);
  }

  function assertActive() {
    if (disposed) {
      throw createError(ERROR_CODES.CANCELLED, '插件已卸载');
    }
  }

  function rpc(method, params, timeoutMs) {
    if (disposed) {
      return Promise.reject(createError(ERROR_CODES.CANCELLED, '插件已卸载'));
    }
    return bridge.request(method, params, typeof timeoutMs === 'number' ? { timeoutMs } : undefined);
  }

  function quietRpc(method, params) {
    try {
      const promise = bridge.request(method, params);
      if (promise && typeof promise.catch === 'function') {
        promise.catch(function ignore() {});
      }
    } catch (error) {
      // Teardown must not throw.
    }
  }

  const subscriptions = {
    add(value) {
      if (disposed) {
        throw createError(ERROR_CODES.CANCELLED, '插件已卸载');
      }
      const disposable = normalizeDisposable(value);
      disposables.push(disposable);
      return disposable;
    },
    get size() {
      return disposables.length;
    },
    list() {
      return disposables.slice();
    },
    disposeAll() {
      for (let index = disposables.length - 1; index >= 0; index -= 1) {
        try {
          disposables[index].dispose();
        } catch (error) {
          log('error', `释放订阅失败：${rawErrorMessage(error)}`);
        }
      }
      disposables.length = 0;
    }
  };

  const capabilitySet = Object.freeze({
    has(capability) {
      return typeof capability === 'string' && capabilities.indexOf(capability) >= 0;
    },
    list() {
      return capabilities.slice();
    }
  });

  /**
   * Resolves a FileRef or vault-relative path to a FileRef. Paths fall back to the host
   * lookup so a plugin can reference a note that was created after boot. An unknown path
   * rejects with E_NOT_FOUND instead of inventing a file.
   */
  async function resolveFile(input) {
    if (typeof input === 'string') {
      const trimmed = normalizeVaultPath(input);
      if (trimmed.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '文件路径不能为空');
      }
      const known = mirror.getByPath(trimmed);
      if (known) {
        return known;
      }
      const found = await rpc('vault.getByPath', { vaultId, path: trimmed });
      if (found && typeof found === 'object' && typeof found.id === 'string' && found.id.length > 0) {
        return mirror.upsert(found);
      }
      throw createError(ERROR_CODES.NOT_FOUND, `文件不存在：${trimmed}`);
    }
    if (isPlainObject(input) && typeof input.id === 'string' && input.id.length > 0) {
      return mirror.getById(input.id) || input;
    }
    throw createError(ERROR_CODES.INVALID_ARGUMENT, '需要 FileRef 或知识库相对路径');
  }

  function upsertSafely(ref) {
    try {
      return mirror.upsert(ref);
    } catch (error) {
      return ref;
    }
  }

  function expectedUpdatedAt(ref) {
    const known = ref && typeof ref.id === 'string' ? mirror.getById(ref.id) : null;
    if (known && typeof known.mtime === 'number') {
      return known.mtime;
    }
    if (ref && typeof ref.mtime === 'number') {
      return ref.mtime;
    }
    return 0;
  }

  const vault = Object.freeze({
    async listMarkdown() {
      const list = await rpc('vault.listMarkdown', { vaultId });
      if (!Array.isArray(list)) {
        return [];
      }
      for (let index = 0; index < list.length; index += 1) {
        upsertSafely(list[index]);
      }
      return list;
    },
    async get(path) {
      const target = normalizeVaultPath(path);
      const found = await rpc('vault.getByPath', { vaultId, path: target });
      if (found && typeof found === 'object') {
        return upsertSafely(found);
      }
      return null;
    },
    async read(input) {
      const ref = await resolveFile(input);
      return rpc('vault.readText', { vaultId, fileId: ref.id });
    },
    async create(path, content) {
      const target = normalizeVaultPath(path);
      if (target.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '创建文件需要非空路径');
      }
      const ref = await rpc('vault.createText', {
        vaultId,
        path: target,
        content: typeof content === 'string' ? content : ''
      });
      return ref && typeof ref === 'object' ? upsertSafely(ref) : ref;
    },
    async write(input, content) {
      const ref = await resolveFile(input);
      const updated = await rpc('vault.writeText', {
        vaultId,
        fileId: ref.id,
        content: typeof content === 'string' ? content : String(content === undefined ? '' : content),
        expectedUpdatedAt: expectedUpdatedAt(ref)
      });
      return updated && typeof updated === 'object' ? upsertSafely(updated) : updated;
    },
    async rename(input, newPath) {
      const ref = await resolveFile(input);
      const target = normalizeVaultPath(newPath);
      if (target.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '新路径不能为空');
      }
      const renamed = await rpc('vault.renameText', { vaultId, fileId: ref.id, newPath: target });
      if (renamed && typeof renamed === 'object') {
        return upsertSafely(renamed);
      }
      const fallback = mirror.getById(ref.id);
      if (fallback) {
        mirror.removeById(ref.id);
      }
      return renamed;
    },
    async delete(input) {
      const ref = await resolveFile(input);
      await rpc('vault.deleteText', { vaultId, fileId: ref.id });
      mirror.removeById(ref.id);
      return null;
    }
  });

  const metadata = Object.freeze({
    async get(input) {
      const ref = await resolveFile(input);
      const snapshot = await rpc('metadata.get', { vaultId, fileId: ref.id });
      if (snapshot && typeof snapshot === 'object') {
        mirror.setMetadata(ref.id, snapshot);
      }
      return snapshot;
    }
  });

  const workspace = Object.freeze({
    async activeFile() {
      const ref = await rpc('workspace.activeFile', {});
      if (ref && typeof ref === 'object') {
        return mirror.setActiveFile(ref);
      }
      mirror.setActiveFile(null);
      return null;
    },
    async openFile(input) {
      const ref = await resolveFile(input);
      await rpc('workspace.openFile', { vaultId, fileId: ref.id });
      mirror.setActiveFile(ref);
      return null;
    },
    async snapshot() {
      const snapshot = await rpc('workspace.snapshot', {});
      return mirror.setWorkspace(snapshot) || snapshot;
    }
  });

  const editor = Object.freeze({
    async active() {
      const snapshot = await rpc('editor.active', {});
      return mirror.setEditor(snapshot);
    },
    /** Synchronous convenience: the mirrored editor text, never an RPC. */
    getValue() {
      const snapshot = mirror.editor();
      return snapshot && typeof snapshot.content === 'string' ? snapshot.content : '';
    },
    async replaceSelection(text) {
      const result = await rpc('editor.replaceSelection', {
        text: typeof text === 'string' ? text : String(text === undefined ? '' : text)
      });
      mirror.patchEditor(result);
      return result;
    },
    async replaceAll(text, expectedVersion) {
      const snapshot = mirror.editor();
      const version = typeof expectedVersion === 'number' && isFinite(expectedVersion)
        ? expectedVersion
        : (snapshot ? snapshot.revision : 0);
      const result = await rpc('editor.replaceAll', {
        text: typeof text === 'string' ? text : String(text === undefined ? '' : text),
        expectedVersion: version
      });
      mirror.patchEditor(result);
      return result;
    }
  });

  const commands = {
    /**
     * Registers a command with the host and returns a Disposable. The callback is kept
     * locally for `__lexiRuntime.runCommand`; the host learns about the command through
     * `commands.register`. `disposable.ready` resolves true/false (it never rejects) so a
     * caller that cares can observe a host refusal without creating an unhandled
     * rejection.
     */
    register(command) {
      assertActive();
      if (!isPlainObject(command) || typeof command.id !== 'string' || !COMMAND_ID_PATTERN.test(command.id)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '命令 id 必须是小写字母或数字开头、1-64 位的 a-z 0-9 . _ -');
      }
      if (typeof command.run !== 'function') {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '命令必须提供 run 函数');
      }
      if (commandMap.has(command.id)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, `命令 ${command.id} 已注册`);
      }
      const title = typeof command.title === 'string' && command.title.length > 0
        ? command.title
        : command.id;
      const record = { id: command.id, title, run: command.run };
      commandMap.set(command.id, record);

      const disposable = DISPOSABLE(() => {
        if (commandMap.delete(command.id)) {
          quietRpc('commands.unregister', { id: command.id });
        }
      });
      disposable.ready = rpc('commands.register', { id: record.id, title: record.title }).then(
        () => true,
        (error) => {
          log('error', `命令 ${record.id} 注册失败：${rawErrorMessage(error)}`);
          return false;
        }
      );
      return disposable;
    },
    unregister(id) {
      const record = commandMap.get(id);
      if (!record) {
        return null;
      }
      commandMap.delete(id);
      quietRpc('commands.unregister', { id });
      return null;
    }
  };
  Object.freeze(commands);

  function dispatchEvent(event, payload, meta) {
    const entries = handlersByEvent.get(event);
    if (!entries || entries.size === 0) {
      return 0;
    }
    const list = Array.from(entries);
    for (let index = 0; index < list.length; index += 1) {
      const entry = list[index];
      if (!entry.active) {
        continue;
      }
      try {
        const outcome = entry.handler(payload, meta);
        if (outcome && typeof outcome.catch === 'function') {
          outcome.catch((error) => log('error', `事件处理器失败 ${event}: ${rawErrorMessage(error)}`));
        }
      } catch (error) {
        log('error', `事件处理器失败 ${event}: ${rawErrorMessage(error)}`);
      }
    }
    return list.length;
  }

  const events = {
    /**
     * Subscribes to a core event. Delivery always goes through receiveEvent; the host
     * subscription id, when returned, is released again by the disposable.
     */
    on(type, handler) {
      assertActive();
      if (typeof type !== 'string' || type.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '事件类型不能为空');
      }
      if (typeof handler !== 'function') {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '事件处理器必须是函数');
      }
      let entries = handlersByEvent.get(type);
      if (!entries) {
        entries = new Set();
        handlersByEvent.set(type, entries);
      }
      const entry = { handler, active: true, subscriptionId: null, type };
      entries.add(entry);

      const disposable = DISPOSABLE(() => {
        if (!entry.active) {
          return;
        }
        entry.active = false;
        const current = handlersByEvent.get(type);
        if (current) {
          current.delete(entry);
          if (current.size === 0) {
            handlersByEvent.delete(type);
          }
        }
        if (entry.subscriptionId !== null) {
          quietRpc('events.off', { subscriptionId: entry.subscriptionId });
        }
      });
      disposable.ready = rpc('events.on', { event: type }).then(
        (result) => {
          if (result && typeof result === 'object' && result.subscriptionId !== undefined) {
            entry.subscriptionId = result.subscriptionId;
          }
          // The plugin may have disposed the subscription before the host answered.
          // Release it immediately instead of leaking a host-side subscription.
          if (!entry.active && entry.subscriptionId !== null) {
            quietRpc('events.off', { subscriptionId: entry.subscriptionId });
          }
          return true;
        },
        (error) => {
          log('warn', `事件 ${type} 订阅失败：${rawErrorMessage(error)}`);
          return false;
        }
      );
      return disposable;
    }
  };
  Object.freeze(events);

  const ui = Object.freeze({
    async notice(message, timeoutMs) {
      const params = {
        message: typeof message === 'string' ? message : String(message === undefined ? '' : message)
      };
      if (typeof timeoutMs === 'number' && isFinite(timeoutMs) && timeoutMs >= 0) {
        params.timeoutMs = Math.floor(timeoutMs);
      }
      return rpc('ui.notice', params);
    },
    async confirm(options) {
      const source = typeof options === 'string'
        ? { body: options }
        : (isPlainObject(options) ? options : {});
      const title = typeof source.title === 'string' && source.title.length > 0 ? source.title : '确认';
      const body = typeof source.body === 'string'
        ? source.body
        : (typeof source.message === 'string' ? source.message : '');
      const answer = await rpc('ui.confirm', { title, body });
      return answer === true || answer === 'true';
    }
  });

  const storage = Object.freeze({
    async get(key) {
      if (typeof key !== 'string' || key.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'storage key 不能为空');
      }
      if (mirror.hasData(key)) {
        return decodeStoredValue(mirror.dataValue(key));
      }
      const raw = await rpc('storage.get', { key });
      mirror.setDataValue(key, raw);
      return decodeStoredValue(raw);
    },
    async set(key, value) {
      if (typeof key !== 'string' || key.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'storage key 不能为空');
      }
      const text = toJsonText(value);
      await rpc('storage.set', { key, value: text });
      mirror.setDataValue(key, text);
      return null;
    },
    async remove(key) {
      if (typeof key !== 'string' || key.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'storage key 不能为空');
      }
      await rpc('storage.remove', { key });
      mirror.removeDataValue(key);
      return null;
    }
  });

  /** Validates one chat message and strips anything the host cannot serialize. */
  function normalizeAiMessage(message, index) {
    if (!isPlainObject(message)) {
      throw createError(ERROR_CODES.INVALID_ARGUMENT, `messages[${index}] 必须是对象`);
    }
    const role = typeof message.role === 'string' ? message.role : '';
    if (role !== 'system' && role !== 'user' && role !== 'assistant' && role !== 'tool') {
      throw createError(ERROR_CODES.INVALID_ARGUMENT, `messages[${index}].role 非法`);
    }
    const normalized = {
      role,
      content: typeof message.content === 'string' ? message.content : ''
    };
    if (role === 'assistant' && Array.isArray(message.toolCalls)) {
      normalized.toolCalls = message.toolCalls.map(function (call, position) {
        if (!isPlainObject(call) || typeof call.name !== 'string' || call.name.length === 0) {
          throw createError(ERROR_CODES.INVALID_ARGUMENT, `toolCalls[${position}] 缺少 name`);
        }
        return {
          id: typeof call.id === 'string' && call.id.length > 0 ? call.id : `call_${index}_${position}`,
          name: call.name,
          arguments: typeof call.arguments === 'string' ? call.arguments : '{}'
        };
      });
    }
    if (role === 'tool') {
      normalized.toolCallId = typeof message.toolCallId === 'string' ? message.toolCallId : '';
      normalized.toolName = typeof message.toolName === 'string' ? message.toolName : '';
      normalized.isError = message.isError === true;
    }
    return normalized;
  }

  function normalizeAiTool(tool, index) {
    if (!isPlainObject(tool) || typeof tool.name !== 'string' || tool.name.length === 0) {
      throw createError(ERROR_CODES.INVALID_ARGUMENT, `tools[${index}] 缺少 name`);
    }
    return {
      name: tool.name,
      description: typeof tool.description === 'string' ? tool.description : '',
      parameters: isPlainObject(tool.parameters)
        ? tool.parameters
        : { type: 'object', properties: {}, required: [] }
    };
  }

  /**
   * Host-brokered model inference. The plugin never sees the API key: `status()` reports
   * only whether a key exists, and `configure()` can set one without reading it back.
   */
  const ai = Object.freeze({
    async models() { return rpc('ai.models', {}, 30000); },
    async balance() { return rpc('ai.balance', {}, 30000); },
    async status() {
      return rpc('ai.status');
    },
    async configure(options) {
      assertActive();
      const source = isPlainObject(options) ? options : {};
      const params = {};
      if (typeof source.provider === 'string') { params.provider = source.provider; }
      if (typeof source.baseUrl === 'string') { params.baseUrl = source.baseUrl; }
      if (typeof source.model === 'string') { params.model = source.model; }
      if (typeof source.apiKey === 'string' && source.apiKey.length > 0) { params.apiKey = source.apiKey; }
      if (typeof source.maxTokens === 'number' && isFinite(source.maxTokens)) {
        params.maxTokens = Math.floor(source.maxTokens);
      }
      if (typeof source.temperature === 'number' && isFinite(source.temperature)) {
        params.temperature = source.temperature;
      }
      if (source.clear === true) { params.clear = true; }
      return rpc('ai.configure', params, 30000);
    },
    async chat(request) {
      assertActive();
      if (!isPlainObject(request) || !Array.isArray(request.messages) || request.messages.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'ai.chat 需要 { messages: [...] }');
      }
      const params = {
        messages: request.messages.map(normalizeAiMessage),
        tools: Array.isArray(request.tools) ? request.tools.map(normalizeAiTool) : []
      };
      if (typeof request.maxTokens === 'number' && isFinite(request.maxTokens)) {
        params.maxTokens = Math.floor(request.maxTokens);
      }
      if (typeof request.temperature === 'number' && isFinite(request.temperature)) {
        params.temperature = request.temperature;
      }
      return rpc('ai.chat', params, AI_TIMEOUT_MS);
    }
  });

  /**
   * Native plugin views. Only a declaration + a render callback live here; the host
   * decides when the surface is visible. `render(container, ctx)` receives a detached
   * DOM node that belongs to the plugin until the next `present()`.
   */
  const viewRegistry = new Map();

  const views = Object.freeze({
    register(definition) {
      assertActive();
      if (!isPlainObject(definition)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'views.register 需要 { id, title, render }');
      }
      const id = typeof definition.id === 'string' ? definition.id : '';
      if (!VIEW_ID_PATTERN.test(id)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '视图 id 必须是小写字母或数字开头、1-64 位的 a-z 0-9 . _ -');
      }
      if (typeof definition.render !== 'function') {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '视图必须提供 render(container, ctx)');
      }
      if (viewRegistry.has(id)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, `视图 ${id} 已注册`);
      }
      const title = typeof definition.title === 'string' && definition.title.length > 0
        ? definition.title
        : id;
      const entry = { id, title, render: definition.render };
      viewRegistry.set(id, entry);
      const disposable = DISPOSABLE(() => {
        if (viewRegistry.delete(id)) {
          quietRpc('views.unregister', { id });
        }
      });
      disposable.ready = rpc('views.register', { id, title }).then(
        () => true,
        (error) => {
          // A refused declaration must not stay presentable: the host is the authority.
          if (viewRegistry.get(id) === entry) {
            viewRegistry.delete(id);
          }
          log('error', `视图 ${id} 注册失败：${rawErrorMessage(error)}`);
          return false;
        }
      );
      return disposable;
    },
    unregister(id) {
      if (!viewRegistry.delete(id)) { return null; }
      quietRpc('views.unregister', { id });
      return null;
    },
    open(id) {
      assertActive();
      const target = typeof id === 'string' && id.length > 0
        ? id
        : (viewRegistry.keys().next().value || '');
      if (!target) {
        throw createError(ERROR_CODES.UNSUPPORTED_API, '没有可打开的插件视图');
      }
      return rpc('views.open', { id: target });
    },
    list() {
      return Array.from(viewRegistry.keys());
    }
  });

  async function presentView(viewId) {
    if (typeof document === 'undefined' || !document.body) {
      throw createError(ERROR_CODES.UNSUPPORTED_API, '当前环境不支持插件视图');
    }
    const entry = typeof viewId === 'string' && viewId.length > 0
      ? viewRegistry.get(viewId)
      : viewRegistry.values().next().value;
    if (!entry) {
      throw createError(ERROR_CODES.UNSUPPORTED_API, '插件没有注册视图');
    }
    let root = document.getElementById('plugin-surface');
    if (!root) {
      root = document.createElement('div');
      root.id = 'plugin-surface';
      document.body.appendChild(root);
    }
    root.replaceChildren();
    const container = document.createElement('div');
    container.className = 'lexinote-plugin-view';
    container.setAttribute('data-plugin-id', pluginId);
    container.setAttribute('data-view-id', entry.id);
    container.style.width = '100%';
    container.style.height = '100%';
    root.appendChild(container);
    await Promise.resolve(entry.render(container, context));
    return { viewId: entry.id, title: entry.title };
  }

  async function runCommand(localId) {
    const record = commandMap.get(localId);
    if (!record) {
      return false;
    }
    await record.run();
    return true;
  }

  function dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    subscriptions.disposeAll();
    // Commands/subsections that were not tracked as subscriptions still need cleanup.
    const remaining = Array.from(commandMap.keys());
    for (let index = 0; index < remaining.length; index += 1) {
      quietRpc('commands.unregister', { id: remaining[index] });
    }
    commandMap.clear();
    handlersByEvent.clear();
    const remainingViews = Array.from(viewRegistry.keys());
    for (let index = 0; index < remainingViews.length; index += 1) {
      quietRpc('views.unregister', { id: remainingViews[index] });
    }
    viewRegistry.clear();
  }

  const internal = {
    bridge,
    mirror,
    pluginId,
    vaultId,
    commandMap,
    handlersByEvent,
    viewRegistry,
    presentView,
    dispatchEvent,
    runCommand,
    dispose,
    log,
    isDisposed() {
      return disposed;
    }
  };

  const context = {
    pluginId,
    apiVersion,
    runtimeVersion: typeof boot.runtimeVersion === 'string' && boot.runtimeVersion.length > 0
      ? boot.runtimeVersion
      : runtimeVersion,
    vaultId,
    capabilities: capabilitySet,
    subscriptions,
    vault,
    metadata,
    workspace,
    editor,
    commands,
    events,
    ui,
    ai,
    views,
    storage,
    log(level, message) {
      log(level, message);
    }
  };
  Object.defineProperty(context, '__internal', {
    value: internal,
    enumerable: false,
    configurable: false,
    writable: false
  });
  return Object.freeze(context);
}

/** Runs `fn` and normalises its failure into the canonical coded Error shape. */
function normalizeFailure(error, fallbackCode) {
  if (error && typeof error.code === 'string' && /^E_[A-Z_]+$/.test(error.code)) {
    return error;
  }
  return createError(fallbackCode || ERROR_CODES.PLUGIN_FAILED, rawErrorMessage(error));
}

module.exports = {
  definePlugin,
  apiVersion,
  runtimeVersion,
  DISPOSABLE,
  createContext,
  normalizeFailure
};
