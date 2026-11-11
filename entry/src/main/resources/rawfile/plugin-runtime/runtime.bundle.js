/*
 * LexiNote JavaScript plugin runtime — GENERATED FILE, DO NOT EDIT.
 * Source: packages/plugin-runtime-js/src/*.js
 * Rebuild: node scripts/build-plugin-runtime.cjs
 *
 * The bundle is loaded by entry/src/main/resources/rawfile/plugin-runtime/index.html
 * inside an ArkWeb WebView. It is a trusted-code runtime, not a sandbox.
 */
(function () {
  'use strict';
  var __modules = Object.create(null);
  var __cache = Object.create(null);
  function __define(id, factory) {
    if (Object.prototype.hasOwnProperty.call(__modules, id)) {
      throw new Error('E_PROTOCOL: duplicate runtime module ' + id);
    }
    __modules[id] = factory;
  }
  function __resolve(specifier) {
    if (typeof specifier !== 'string' || specifier.length === 0) {
      throw new Error('E_UNSUPPORTED_MODULE: ' + String(specifier));
    }
    if (specifier.charAt(0) === '.') {
      return specifier.replace(/^\.\//, '').replace(/\.js$/, '');
    }
    throw new Error('E_UNSUPPORTED_MODULE: ' + specifier);
  }
  function __require(id) {
    if (!Object.prototype.hasOwnProperty.call(__modules, id)) {
      throw new Error('E_UNSUPPORTED_MODULE: ' + id);
    }
    if (Object.prototype.hasOwnProperty.call(__cache, id)) {
      return __cache[id].exports;
    }
    var module = { exports: {} };
    __cache[id] = module;
    __modules[id](module, module.exports, function (specifier) {
      return __require(__resolve(specifier));
    }, id + '.js', '/');
    return module.exports;
  }

  // ---- module: util ----
  __define('util', function (module, exports, require) {
'use strict';

/**
 * Small, dependency-free helpers shared by the LexiNote JavaScript plugin runtime.
 *
 * This file is loaded inside an ArkWeb WebView as well as by plain Node.js, so it must
 * never touch `window`, `document`, Node built-ins, `process`, `fs` or `path`. The only
 * host facilities it may rely on are the ECMAScript standard library and `TextEncoder`
 * (with a manual UTF-8 fallback for engines that do not provide it).
 */

/** Canonical error codes shared with `entry/src/main/ets/plugin/model/PluginErrors.ets`. */
const ERROR_CODES = Object.freeze({
  INVALID_ARGUMENT: 'E_INVALID_ARGUMENT',
  INVALID_PATH: 'E_INVALID_PATH',
  PATH_EXISTS: 'E_PATH_EXISTS',
  NOT_FOUND: 'E_NOT_FOUND',
  VAULT_FORBIDDEN: 'E_VAULT_FORBIDDEN',
  PERMISSION_DENIED: 'E_PERMISSION_DENIED',
  CONFLICT: 'E_CONFLICT',
  EDITOR_CONFLICT: 'E_EDITOR_CONFLICT',
  EDITOR_READONLY: 'E_EDITOR_READONLY',
  UNSUPPORTED_API: 'E_UNSUPPORTED_API',
  UNSUPPORTED_MODULE: 'E_UNSUPPORTED_MODULE',
  PLUGIN_DISABLED: 'E_PLUGIN_DISABLED',
  PLUGIN_FAILED: 'E_PLUGIN_FAILED',
  QUOTA_EXCEEDED: 'E_QUOTA_EXCEEDED',
  TIMEOUT: 'E_TIMEOUT',
  CANCELLED: 'E_CANCELLED',
  RUNTIME_UNAVAILABLE: 'E_RUNTIME_UNAVAILABLE',
  RATE_LIMITED: 'E_RATE_LIMITED',
  INSTALL_REJECTED: 'E_INSTALL_REJECTED',
  DESKTOP_ONLY: 'E_DESKTOP_ONLY',
  DUPLICATE_PLUGIN: 'E_DUPLICATE_PLUGIN',
  PROTOCOL: 'E_PROTOCOL',
  IO: 'E_IO',
  UNKNOWN: 'E_UNKNOWN'
});

/**
 * Builds the single error shape used on both sides of the bridge:
 * `Error` whose `code` is an `E_*` string and whose `message` is `"<code>: <detail>"`.
 *
 * @param {string} code one of ERROR_CODES
 * @param {string} [detail]
 * @returns {Error}
 */
function createError(code, detail) {
  const head = typeof code === 'string' && code.length > 0 ? code : ERROR_CODES.UNKNOWN;
  const text = detail === undefined || detail === null ? '' : String(detail);
  const error = new Error(text.length > 0 ? `${head}: ${text}` : head);
  error.code = head;
  return error;
}

/** True for `{...}` objects created by `{}`, `new Object()` or `Object.create(null)`. */
function isPlainObject(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

/**
 * Escapes a value into a JSON string literal that is safe to embed inside an inline
 * `<script>` or an HTML attribute. The returned text includes the surrounding quotes.
 */
function escapeJson(value) {
  const text = typeof value === 'string' ? value : String(value);
  return JSON.stringify(text)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

/** UTF-8 byte length of a string, without depending on `Buffer`. */
function byteLength(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return 0;
  }
  if (typeof TextEncoder === 'function') {
    return new TextEncoder().encode(text).length;
  }
  let bytes = 0;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
      const next = text.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** Restricts `value` to the inclusive `[min, max]` range; non-numbers use `min`. */
function clamp(value, min, max) {
  const number = typeof value === 'number' && isFinite(value) ? value : min;
  if (number < min) {
    return min;
  }
  if (number > max) {
    return max;
  }
  return number;
}

/**
 * Throws unless `condition` is truthy.
 *
 * @param {*} condition
 * @param {string} code `E_*` code, or the detail when `detail` is omitted
 * @param {string} [detail]
 */
function assert(condition, code, detail) {
  if (condition) {
    return condition;
  }
  if (detail === undefined) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, code);
  }
  throw createError(code, detail);
}

/** Reads a leading `E_*` code out of `"E_FOO: detail"`; defaults to E_UNKNOWN. */
function codeOf(error) {
  if (error && typeof error.code === 'string' && /^E_[A-Z_]+$/.test(error.code)) {
    return error.code;
  }
  const text = rawErrorMessage(error);
  const colon = text.indexOf(':');
  if (colon > 0) {
    const head = text.slice(0, colon).trim();
    if (/^E_[A-Z_]+$/.test(head)) {
      return head;
    }
  }
  return ERROR_CODES.UNKNOWN;
}

/** Original thrown text, before any code stripping. */
function rawErrorMessage(error) {
  if (error === undefined || error === null) {
    return '未知错误';
  }
  if (typeof error === 'string') {
    return error;
  }
  if (typeof error.message === 'string' && error.message.length > 0) {
    return error.message;
  }
  return String(error);
}

/** Human readable message without a leading `E_*` code. */
function messageOf(error) {
  const text = rawErrorMessage(error);
  const colon = text.indexOf(':');
  if (colon > 0 && /^E_[A-Z_]+$/.test(text.slice(0, colon).trim())) {
    return text.slice(colon + 1).trim();
  }
  return text;
}

/** True when the value already carries an explicit `E_*` code. */
function isCodedError(error) {
  return Boolean(error) && typeof error.code === 'string' && /^E_[A-Z_]+$/.test(error.code);
}

/**
 * Vault-relative path normalisation used by the mirror, SDK and Obsidian shim:
 * backslashes become `/`, `.`/`..` segments collapse, repeated slashes collapse and a
 * leading slash is removed. The empty string denotes the vault root.
 */
function normalizeVaultPath(input) {
  const source = input === undefined || input === null ? '' : String(input);
  const parts = [];
  const segments = source.replace(/\\/g, '/').split('/');
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    if (segment === '' || segment === '.') {
      continue;
    }
    if (segment === '..') {
      if (parts.length > 0) {
        parts.pop();
      }
      continue;
    }
    parts.push(segment);
  }
  return parts.join('/');
}

/** Parent directory of a vault-relative path ('' for root). */
function parentPath(vaultPath) {
  const normalized = normalizeVaultPath(vaultPath);
  const slash = normalized.lastIndexOf('/');
  return slash < 0 ? '' : normalized.slice(0, slash);
}

/** Final path segment. */
function baseName(vaultPath) {
  const normalized = normalizeVaultPath(vaultPath);
  const slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.slice(slash + 1);
}

/** File extension without the dot ('' when there is none). */
function extensionOf(name) {
  const base = baseName(name);
  const dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.slice(dot + 1).toLowerCase();
}

/** `JSON.parse` that returns `fallback` for absent or malformed input. */
function parseJson(text, fallback) {
  if (typeof text !== 'string' || text.length === 0) {
    return fallback;
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    return fallback;
  }
}

/** `JSON.parse` that throws `E_PROTOCOL` instead of a raw SyntaxError. */
function parseJsonStrict(text, what) {
  if (typeof text !== 'string') {
    throw createError(ERROR_CODES.PROTOCOL, `${what || '值'}不是 JSON 文本`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    throw createError(ERROR_CODES.PROTOCOL, `${what || '值'}不是合法 JSON`);
  }
}

/** JSON text for any JSON-serializable value; `undefined` becomes `null`. */
function toJsonText(value) {
  if (value === undefined) {
    return 'null';
  }
  try {
    return JSON.stringify(value);
  } catch (error) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, '值不能序列化为 JSON');
  }
}

module.exports = {
  ERROR_CODES,
  createError,
  isPlainObject,
  escapeJson,
  byteLength,
  clamp,
  assert,
  codeOf,
  messageOf,
  rawErrorMessage,
  isCodedError,
  normalizeVaultPath,
  parentPath,
  baseName,
  extensionOf,
  parseJson,
  parseJsonStrict,
  toJsonText
};
  });

  // ---- module: mirror ----
  __define('mirror', function (module, exports, require) {
'use strict';

/**
 * FileMirror — the runtime's in-memory snapshot of the vault.
 *
 * Everything the host pushed at boot (files, active file, the active editor, workspace
 * snapshot, plugin settings and plugin storage) is cached here. Synchronous Obsidian
 * APIs (`getMarkdownFiles`, `getAbstractFileByPath`, `Editor.getValue`) read this mirror;
 * asynchronous APIs still go through RPC and refresh the mirror with the answer.
 *
 * The mirror is not authoritative. Whenever the host reports a newer value (an RPC
 * result or a core event) the mirror is replaced, never merged over the host value.
 */

const {
  normalizeVaultPath,
  baseName,
  extensionOf,
  parseJson,
  isPlainObject,
  createError,
  ERROR_CODES
} = require('./util');

/** Normalises any host-supplied FileRef into the documented, immutable shape. */
function toFileRef(raw) {
  if (!isPlainObject(raw)) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'FileRef 必须是对象');
  }
  const path = normalizeVaultPath(typeof raw.path === 'string' ? raw.path : '');
  const name = typeof raw.name === 'string' && raw.name.length > 0 ? raw.name : baseName(path);
  const ref = {
    id: typeof raw.id === 'string' ? raw.id : '',
    vaultId: typeof raw.vaultId === 'string' ? raw.vaultId : '',
    projectId: typeof raw.projectId === 'string' ? raw.projectId : '',
    path,
    name,
    extension: typeof raw.extension === 'string' && raw.extension.length > 0
      ? raw.extension.toLowerCase()
      : extensionOf(name),
    kind: typeof raw.kind === 'string' && raw.kind.length > 0 ? raw.kind : 'file',
    size: typeof raw.size === 'number' && isFinite(raw.size) ? raw.size : 0,
    ctime: typeof raw.ctime === 'number' && isFinite(raw.ctime) ? raw.ctime : 0,
    mtime: typeof raw.mtime === 'number' && isFinite(raw.mtime) ? raw.mtime : 0
  };
  return Object.freeze(ref);
}

function toEditorSnapshot(raw) {
  if (!isPlainObject(raw)) {
    return null;
  }
  return Object.freeze({
    editorId: typeof raw.editorId === 'string' ? raw.editorId : '',
    noteId: typeof raw.noteId === 'string' ? raw.noteId : '',
    vaultId: typeof raw.vaultId === 'string' ? raw.vaultId : '',
    windowId: typeof raw.windowId === 'string' ? raw.windowId : '',
    revision: typeof raw.revision === 'number' && isFinite(raw.revision) ? raw.revision : 0,
    baseContent: typeof raw.baseContent === 'string' ? raw.baseContent : '',
    content: typeof raw.content === 'string' ? raw.content : '',
    dirty: raw.dirty === true,
    readOnly: raw.readOnly === true,
    focused: raw.focused === true
  });
}

class FileMirror {
  constructor(boot) {
    this._byId = new Map();
    this._byPath = new Map();
    this._metadata = new Map();
    this._activeFile = null;
    this._editor = null;
    this._workspace = null;
    this._settings = null;
    this._data = new Map();
    this._revision = 0;
    if (boot) {
      this.load(boot);
    }
  }

  /**
   * Resets and fills the mirror from the boot payload. Malformed JSON fields degrade to
   * the documented defaults instead of failing the whole boot; the host validates the
   * manifest and file list before it gets here.
   */
  load(boot) {
    const payload = isPlainObject(boot) ? boot : {};
    this._byId.clear();
    this._byPath.clear();
    this._metadata.clear();
    this._activeFile = null;
    this._editor = null;
    this._workspace = null;
    this._settings = null;
    this._data.clear();

    const files = parseJson(payload.filesJson, []);
    if (Array.isArray(files)) {
      for (let index = 0; index < files.length; index += 1) {
        try {
          this.upsert(files[index]);
        } catch (error) {
          // A single malformed FileRef must not discard the rest of the vault snapshot.
        }
      }
    }

    const active = parseJson(payload.activeFileJson, null);
    if (active && isPlainObject(active)) {
      try {
        this.setActiveFile(active);
      } catch (error) {
        this._activeFile = null;
      }
    }

    const editor = parseJson(payload.editorJson, null);
    if (editor && isPlainObject(editor)) {
      this._editor = toEditorSnapshot(editor);
    }

    const settings = parseJson(payload.settingsJson, null);
    this._settings = settings === undefined ? null : settings;

    const data = parseJson(payload.dataJson, {});
    if (isPlainObject(data)) {
      const keys = Object.keys(data);
      for (let index = 0; index < keys.length; index += 1) {
        this._data.set(keys[index], data[keys[index]]);
      }
    }

    this._workspace = {
      windowId: '',
      vaultId: typeof payload.vaultId === 'string' ? payload.vaultId : '',
      activeFileId: this._activeFile ? this._activeFile.id : '',
      activeEditorId: this._editor ? this._editor.editorId : '',
      openFileIds: this._activeFile ? [this._activeFile.id] : [],
      revision: this._editor ? this._editor.revision : 0
    };
    return this;
  }

  /** Number of files currently known. */
  get size() {
    return this._byId.size;
  }

  get revision() {
    return this._revision;
  }

  upsert(raw) {
    const ref = toFileRef(raw);
    if (ref.id.length === 0) {
      throw createError(ERROR_CODES.INVALID_ARGUMENT, 'FileRef.id 不能为空');
    }
    const previous = this._byId.get(ref.id);
    if (previous && previous.path !== ref.path) {
      const mapped = this._byPath.get(previous.path);
      if (mapped && mapped.id === ref.id) {
        this._byPath.delete(previous.path);
      }
    }
    this._byId.set(ref.id, ref);
    this._byPath.set(ref.path, ref);
    this._revision += 1;
    if (this._activeFile && this._activeFile.id === ref.id) {
      this._activeFile = ref;
    }
    return ref;
  }

  removeById(id) {
    const ref = this._byId.get(id);
    if (!ref) {
      return false;
    }
    this._byId.delete(id);
    if (this._byPath.get(ref.path) === ref) {
      this._byPath.delete(ref.path);
    }
    if (this._activeFile && this._activeFile.id === id) {
      this._activeFile = null;
    }
    this._metadata.delete(id);
    this._revision += 1;
    return true;
  }

  removeByPath(rawPath) {
    const path = normalizeVaultPath(rawPath);
    const ref = this._byPath.get(path);
    return ref ? this.removeById(ref.id) : false;
  }

  getById(id) {
    return typeof id === 'string' ? this._byId.get(id) || null : null;
  }

  getByPath(rawPath) {
    if (typeof rawPath !== 'string') {
      return null;
    }
    return this._byPath.get(normalizeVaultPath(rawPath)) || null;
  }

  /** Every known file, in insertion order. */
  listAll() {
    return Array.from(this._byId.values());
  }

  /** Markdown files only; the host also filters, this is the local cache view. */
  listMarkdown() {
    const result = [];
    const files = this.listAll();
    for (let index = 0; index < files.length; index += 1) {
      const ref = files[index];
      if (ref.extension === 'md' || ref.extension === 'markdown' || /\.(md|markdown)$/i.test(ref.path)) {
        result.push(ref);
      }
    }
    return result;
  }

  /** Accepts a FileRef-like object, an id or a vault-relative path. */
  resolve(input) {
    if (input && typeof input === 'object' && typeof input.id === 'string' && input.id.length > 0) {
      return this.getById(input.id) || (isPlainObject(input) ? this.upsert(input) : null);
    }
    if (typeof input === 'string') {
      return this.getByPath(input);
    }
    return null;
  }

  setActiveFile(ref) {
    if (!ref) {
      this._activeFile = null;
      return null;
    }
    const resolved = this.resolve(ref);
    this._activeFile = resolved;
    return resolved;
  }

  activeFile() {
    return this._activeFile;
  }

  setEditor(snapshot) {
    this._editor = snapshot ? toEditorSnapshot(snapshot) : null;
    return this._editor;
  }

  editor() {
    return this._editor;
  }

  /** Applies the parts of an editor RPC result that the host actually returned. */
  patchEditor(patch) {
    if (!this._editor) {
      return null;
    }
    const current = this._editor;
    const next = {
      editorId: current.editorId,
      noteId: current.noteId,
      vaultId: current.vaultId,
      windowId: current.windowId,
      revision: current.revision,
      baseContent: current.baseContent,
      content: current.content,
      dirty: current.dirty,
      readOnly: current.readOnly,
      focused: current.focused
    };
    if (patch && typeof patch === 'object') {
      if (typeof patch.content === 'string') {
        next.content = patch.content;
      }
      if (typeof patch.version === 'number') {
        next.revision = patch.version;
      } else if (typeof patch.revision === 'number') {
        next.revision = patch.revision;
      }
      if (typeof patch.baseContent === 'string') {
        next.baseContent = patch.baseContent;
      }
      if (typeof patch.dirty === 'boolean') {
        next.dirty = patch.dirty;
      }
    }
    this._editor = Object.freeze(next);
    return this._editor;
  }

  setWorkspace(snapshot) {
    if (!isPlainObject(snapshot)) {
      return this._workspace;
    }
    this._workspace = Object.freeze({
      windowId: typeof snapshot.windowId === 'string' ? snapshot.windowId : '',
      vaultId: typeof snapshot.vaultId === 'string' ? snapshot.vaultId : '',
      activeFileId: typeof snapshot.activeFileId === 'string' ? snapshot.activeFileId : '',
      activeEditorId: typeof snapshot.activeEditorId === 'string' ? snapshot.activeEditorId : '',
      openFileIds: Array.isArray(snapshot.openFileIds)
        ? snapshot.openFileIds.filter((id) => typeof id === 'string')
        : [],
      revision: typeof snapshot.revision === 'number' && isFinite(snapshot.revision) ? snapshot.revision : 0
    });
    return this._workspace;
  }

  workspace() {
    return this._workspace;
  }

  setMetadata(fileId, snapshot) {
    if (typeof fileId === 'string' && isPlainObject(snapshot)) {
      this._metadata.set(fileId, snapshot);
    }
    return snapshot;
  }

  metadata(fileId) {
    return this._metadata.get(fileId) || null;
  }

  settings() {
    return this._settings;
  }

  dataValue(key) {
    return this._data.has(key) ? this._data.get(key) : undefined;
  }

  hasData(key) {
    return this._data.has(key);
  }

  setDataValue(key, value) {
    this._data.set(key, value);
  }

  removeDataValue(key) {
    this._data.delete(key);
  }

  dataSnapshot() {
    const result = {};
    this._data.forEach((value, key) => {
      result[key] = value;
    });
    return result;
  }
}

module.exports = {
  FileMirror,
  toFileRef,
  toEditorSnapshot
};
  });

  // ---- module: bridge ----
  __define('bridge', function (module, exports, require) {
'use strict';

/**
 * Bridge client for the synchronous ArkWeb proxy exposed by the host as
 * `window.lexiPluginBridge.request(jsonString)`.
 *
 * The proxy call is only an acknowledgement: the real answer arrives later through
 * `window.__lexiRuntime.receiveResponse(jsonString)`. Requests are therefore promise
 * based, with a bounded number in flight, a hard timeout and id-based correlation so an
 * out-of-order or forged response can never resolve the wrong promise.
 *
 * This module is deliberately free of Node built-ins; `setTimeout` / `clearTimeout` are
 * injected so tests can drive time deterministically.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  rawErrorMessage
} = require('./util');

const PROTOCOL_VERSION = 1;
const DEFAULT_TIMEOUT_MS = 15000;
const MAX_IN_FLIGHT = 16;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

function normalizeTimers(timers) {
  if (timers && typeof timers.setTimeout === 'function' && typeof timers.clearTimeout === 'function') {
    return timers;
  }
  return {
    setTimeout: (callback, delay) => setTimeout(callback, delay),
    clearTimeout: (handle) => clearTimeout(handle)
  };
}

class PluginBridge {
  /**
   * @param {object} options
   * @param {string} options.pluginId booted plugin id; every outbound request is stamped
   *   with it and requests carrying a different id are rejected before leaving the runtime
   * @param {string} [options.token] boot token echoed to the host
   * @param {number} [options.timeoutMs] per-request timeout (default 15000)
   * @param {number} [options.maxInFlight] concurrent request cap (default 16)
   * @param {Function} [options.sendProvider] returns the live `lexiPluginBridge` object
   * @param {object} [options.timers] `{setTimeout, clearTimeout}` injection point
   * @param {Function} [options.onLog] optional local diagnostic sink
   */
  constructor(options) {
    const settings = isPlainObject(options) ? options : {};
    this.pluginId = typeof settings.pluginId === 'string' ? settings.pluginId : '';
    this.token = typeof settings.token === 'string' ? settings.token : '';
    this.timeoutMs = typeof settings.timeoutMs === 'number' && isFinite(settings.timeoutMs) && settings.timeoutMs >= 1
      ? settings.timeoutMs
      : DEFAULT_TIMEOUT_MS;
    this.maxInFlight = typeof settings.maxInFlight === 'number' && isFinite(settings.maxInFlight) && settings.maxInFlight >= 1
      ? Math.floor(settings.maxInFlight)
      : MAX_IN_FLIGHT;
    this.sendFunction = typeof settings.send === 'function' ? settings.send : null;
    this.sendProvider = typeof settings.sendProvider === 'function' ? settings.sendProvider : null;
    this.timers = normalizeTimers(settings.timers);
    this.onLog = typeof settings.onLog === 'function' ? settings.onLog : null;
    this.pending = new Map();
    this.sequence = 0;
    this.closed = false;
  }

  get pendingCount() {
    return this.pending.size;
  }

  /** The live host proxy, or null. Resolved lazily so a page injected bridge can appear. */
  _bridge() {
    if (this.sendFunction) {
      return { request: this.sendFunction };
    }
    let bridge = null;
    try {
      if (this.sendProvider) {
        bridge = this.sendProvider();
      } else if (typeof globalThis !== 'undefined') {
        bridge = globalThis.lexiPluginBridge;
      }
    } catch (error) {
      bridge = null;
    }
    return bridge && typeof bridge.request === 'function' ? bridge : null;
  }

  _nextRequestId() {
    this.sequence += 1;
    return `r${this.sequence}`;
  }

  /**
   * Validates an outbound request against this bridge's identity. Exposed separately so
   * the security regression can prove that a request for another plugin id is rejected
   * by the JavaScript side, before the host ever sees it.
   */
  validateOutbound(request) {
    if (!isPlainObject(request)) {
      return createError(ERROR_CODES.PROTOCOL, '请求必须是对象');
    }
    if (request.protocol !== PROTOCOL_VERSION) {
      return createError(ERROR_CODES.PROTOCOL, `不支持的协议版本 ${String(request.protocol)}`);
    }
    if (typeof request.id !== 'string' || !REQUEST_ID_PATTERN.test(request.id)) {
      return createError(ERROR_CODES.PROTOCOL, '请求 id 非法');
    }
    if (typeof request.method !== 'string' || request.method.length === 0) {
      return createError(ERROR_CODES.PROTOCOL, '请求 method 不能为空');
    }
    if (request.pluginId !== this.pluginId) {
      return createError(
        ERROR_CODES.PERMISSION_DENIED,
        `请求插件 id 与已启动实例不一致（${String(request.pluginId)} != ${this.pluginId}）`
      );
    }
    if (this.token.length > 0 && request.token !== this.token) {
      return createError(ERROR_CODES.PERMISSION_DENIED, '请求 token 与已启动实例不一致');
    }
    // On the wire the ArkTS host stores params as JSON text (`PluginRpcRequest.params`
    // is a string and each dispatcher parses it itself). The SDK still accepts plain
    // objects from callers; request() serialises them below. Both forms are tolerated
    // here so sendRaw() can be used with either shape.
    if (request.params !== undefined && typeof request.params !== 'string' && !isPlainObject(request.params)) {
      return createError(ERROR_CODES.INVALID_ARGUMENT, '请求 params 必须是 JSON 文本或对象');
    }
    return null;
  }

  /**
   * Low-level diagnostic entry point. It never registers a pending promise and is not
   * used by the SDK; it exists so the tests (and future tooling) can assert the identity
   * guard without reaching into private fields.
   */
  sendRaw(request) {
    if (this.closed) {
      return Promise.reject(createError(ERROR_CODES.CANCELLED, '插件运行时已卸载'));
    }
    const failure = this.validateOutbound(request);
    if (failure) {
      return Promise.reject(failure);
    }
    const bridge = this._bridge();
    if (!bridge) {
      return Promise.reject(createError(ERROR_CODES.RUNTIME_UNAVAILABLE, '宿主桥 window.lexiPluginBridge 不可用'));
    }
    try {
      const outbound = Object.assign({}, request);
      if (isPlainObject(outbound.params)) {
        outbound.params = JSON.stringify(outbound.params);
      }
      bridge.request(JSON.stringify(outbound));
      return Promise.resolve(true);
    } catch (error) {
      return Promise.reject(createError(
        ERROR_CODES.RUNTIME_UNAVAILABLE,
        `宿主桥调用失败：${rawErrorMessage(error)}`
      ));
    }
  }

  /**
   * Sends one RPC and resolves with the parsed `result` document.
   *
   * @param {string} method
   * @param {object} [params]
   * @param {object} [options] `{ timeoutMs }` overrides the bridge default for one call
   *   (model turns need a much larger budget than vault reads).
   * @returns {Promise<*>}
   */
  request(method, params, options) {
    if (typeof method !== 'string' || method.length === 0) {
      return Promise.reject(createError(ERROR_CODES.INVALID_ARGUMENT, 'method 不能为空'));
    }
    if (this.closed) {
      return Promise.reject(createError(ERROR_CODES.CANCELLED, '插件运行时已卸载'));
    }
    if (this.pending.size >= this.maxInFlight) {
      return Promise.reject(createError(
        ERROR_CODES.RATE_LIMITED,
        `最多允许 ${this.maxInFlight} 个请求同时在途`
      ));
    }
    const bridge = this._bridge();
    if (!bridge) {
      return Promise.reject(createError(
        ERROR_CODES.RUNTIME_UNAVAILABLE,
        '宿主桥 window.lexiPluginBridge 不可用'
      ));
    }

    const request = {
      protocol: PROTOCOL_VERSION,
      id: this._nextRequestId(),
      pluginId: this.pluginId,
      token: this.token,
      method,
      // The ArkTS host parses `params` as JSON text (`PluginRpcRequest.params: string`),
      // so the object API stays on the SDK side and serialisation happens here.
      params: JSON.stringify(isPlainObject(params) ? params : {})
    };

    const settings = isPlainObject(options) ? options : {};
    const timeoutMs = typeof settings.timeoutMs === 'number' && isFinite(settings.timeoutMs) &&
      settings.timeoutMs >= 1
      ? Math.floor(settings.timeoutMs)
      : this.timeoutMs;

    return new Promise((resolve, reject) => {
      const timer = this.timers.setTimeout(() => {
        const entry = this.pending.get(request.id);
        if (!entry) {
          return;
        }
        this.pending.delete(request.id);
        reject(createError(
          ERROR_CODES.TIMEOUT,
          `${method} 请求超过 ${timeoutMs}ms 未返回`
        ));
      }, timeoutMs);

      this.pending.set(request.id, {
        resolve,
        reject,
        timer,
        method
      });

      const failure = this.validateOutbound(request);
      if (failure) {
        this._settle(request.id, failure);
        return;
      }

      try {
        // The synchronous return value is an ack only. The result arrives later through
        // receiveResponse(); ignoring the ack is intentional and documented.
        bridge.request(JSON.stringify(request));
      } catch (error) {
        this._settle(request.id, createError(
          ERROR_CODES.RUNTIME_UNAVAILABLE,
          `宿主桥调用失败：${rawErrorMessage(error)}`
        ));
      }
    });
  }

  _settle(id, error) {
    const entry = this.pending.get(id);
    if (!entry) {
      return false;
    }
    this.pending.delete(id);
    this.timers.clearTimeout(entry.timer);
    entry.reject(error);
    return true;
  }

  /**
   * Handles one host response. Returns true only when the response matched a live
   * request; unknown ids, wrong protocols and malformed JSON are dropped silently.
   *
   * @param {string|object} raw
   * @returns {boolean}
   */
  handleResponse(raw) {
    let message = raw;
    if (typeof raw === 'string') {
      if (raw.length === 0) {
        return false;
      }
      try {
        message = JSON.parse(raw);
      } catch (error) {
        this._logLocal('warn', `收到无法解析的响应：${rawErrorMessage(error)}`);
        return false;
      }
    }
    if (!isPlainObject(message)) {
      return false;
    }
    if (message.protocol !== undefined && message.protocol !== PROTOCOL_VERSION) {
      return false;
    }
    if (typeof message.id !== 'string') {
      return false;
    }
    const entry = this.pending.get(message.id);
    if (!entry) {
      // Unknown, duplicate, late or out-of-order response: drop it. Never resolve a
      // different promise just because its id happens to be nearby.
      return false;
    }
    this.pending.delete(message.id);
    this.timers.clearTimeout(entry.timer);

    if (message.ok === true) {
      let value = message.result;
      if (typeof value === 'string') {
        if (value.length === 0) {
          value = null;
        } else {
          try {
            value = JSON.parse(value);
          } catch (error) {
            entry.reject(createError(
              ERROR_CODES.PROTOCOL,
              `${entry.method} 的结果不是合法 JSON`
            ));
            return true;
          }
        }
      } else if (value === undefined) {
        value = null;
      }
      entry.resolve(value);
      return true;
    }

    const info = isPlainObject(message.error) ? message.error : {};
    const code = typeof info.code === 'string' && /^E_[A-Z_]+$/.test(info.code)
      ? info.code
      : ERROR_CODES.UNKNOWN;
    let detail = '';
    if (typeof info.message === 'string' && info.message.length > 0) {
      detail = info.message;
    } else if (typeof info.details === 'string' && info.details.length > 0) {
      detail = info.details;
    } else {
      detail = '宿主返回失败但未提供消息';
    }
    entry.reject(createError(code, detail));
    return true;
  }

  /** Rejects every pending request; used on unload so timers never outlive the runtime. */
  rejectAll(code, detail) {
    const ids = Array.from(this.pending.keys());
    for (let index = 0; index < ids.length; index += 1) {
      const entry = this.pending.get(ids[index]);
      if (!entry) {
        continue;
      }
      this.pending.delete(ids[index]);
      this.timers.clearTimeout(entry.timer);
      entry.reject(createError(code, detail));
    }
    return ids.length;
  }

  /** Marks the bridge closed and rejects anything still in flight with E_CANCELLED. */
  close() {
    this.closed = true;
    return this.rejectAll(ERROR_CODES.CANCELLED, '插件运行时已卸载');
  }

  /** Fire-and-forget diagnostic line. Missing bridges are ignored by design. */
  log(level, message) {
    const text = typeof message === 'string' ? message : String(message);
    const severity = typeof level === 'string' && level.length > 0 ? level : 'info';
    this._logLocal(severity, text);
    try {
      const bridge = this._bridge();
      if (bridge && typeof bridge.log === 'function') {
        bridge.log(severity, text);
        return true;
      }
    } catch (error) {
      // Diagnostics must never break plugin execution.
    }
    return false;
  }

  _logLocal(level, message) {
    if (this.onLog) {
      try {
        this.onLog(level, message);
      } catch (error) {
        // ignore
      }
    }
  }
}

function createBridge(options) {
  return new PluginBridge(options);
}

module.exports = {
  PluginBridge,
  createBridge,
  PROTOCOL_VERSION,
  DEFAULT_TIMEOUT_MS,
  MAX_IN_FLIGHT,
  REQUEST_ID_PATTERN
};
  });

  // ---- module: loader ----
  __define('loader', function (module, exports, require) {
'use strict';

/**
 * CommonJS loader for plugin bundles.
 *
 * IMPORTANT: this is a *trusted-code* loader, NOT a sandbox. Plugin code runs in the
 * same JavaScript realm as the runtime, with the same globals. The only hard boundary is
 * that `require` may resolve exactly two ids ('obsidian' and '@lexinote/sdk'); any other
 * module name — including 'fs', 'path', 'electron', 'process', 'child_process' and
 * 'http' — is rejected with `E_UNSUPPORTED_MODULE`. Real isolation comes from running
 * the runtime inside a dedicated ArkWeb WebView with network access blocked; the loader
 * cannot and does not claim to provide security on its own.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  isCodedError,
  rawErrorMessage
} = require('./util');

const ALLOWED_MODULES = Object.freeze({
  obsidian: true,
  '@lexinote/sdk': true
});

/** Host capability names. Kept in sync with PluginModels.ets / plugin-contracts. */
const CAPABILITIES = Object.freeze([
  'vault.read',
  'vault.write',
  'notes.metadata.read',
  'editor.read',
  'editor.write',
  'workspace.views',
  'ui.notice',
  'ui.modal',
  'ui.commands',
  'ai.inference',
  'ui.views',
  'plugin.storage',
  'network'
]);

const ID_PATTERN = /^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

const LEXINOTE_REQUIRED = Object.freeze([
  'format',
  'formatVersion',
  'id',
  'name',
  'version',
  'apiVersion',
  'main'
]);

const LEXINOTE_ALLOWED = Object.freeze([
  'format',
  'formatVersion',
  'id',
  'name',
  'version',
  'apiVersion',
  'main',
  'description',
  'author',
  'capabilities',
  'targets',
  'minHostVersion',
  'isDesktopOnly'
]);

const OBSIDIAN_REQUIRED = Object.freeze([
  'id',
  'name',
  'version',
  'minAppVersion',
  'description',
  'author',
  'isDesktopOnly'
]);

const OBSIDIAN_ALLOWED = Object.freeze([
  'id',
  'name',
  'version',
  'minAppVersion',
  'description',
  'author',
  'isDesktopOnly',
  'fundingUrl'
]);

function moduleValue(modules, id) {
  if (!modules || typeof modules !== 'object') {
    return { found: false, value: undefined };
  }
  if (Object.prototype.hasOwnProperty.call(modules, id)) {
    return { found: true, value: modules[id] };
  }
  // The runtime registers the SDK under its short bundle id.
  if (id === '@lexinote/sdk' && Object.prototype.hasOwnProperty.call(modules, 'sdk')) {
    return { found: true, value: modules.sdk };
  }
  return { found: false, value: undefined };
}

function createRequire(modules) {
  return function pluginRequire(name) {
    const id = typeof name === 'string' ? name : String(name);
    if (!Object.prototype.hasOwnProperty.call(ALLOWED_MODULES, id)) {
      throw createError(ERROR_CODES.UNSUPPORTED_MODULE, id);
    }
    const resolved = moduleValue(modules, id);
    if (!resolved.found) {
      throw createError(ERROR_CODES.UNSUPPORTED_MODULE, `${id}（运行时未提供该模块）`);
    }
    return resolved.value;
  };
}

/**
 * Executes one CommonJS plugin bundle.
 *
 * @param {string} source bundle text
 * @param {object} modules map of whitelisted module id -> exports
 * @param {string} [filename] `__filename` passed to the bundle
 * @returns {*} the bundle's `module.exports`
 */
function executeBundle(source, modules, filename) {
  if (typeof source !== 'string') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, '插件源码必须是字符串');
  }
  const name = typeof filename === 'string' && filename.length > 0 ? filename : 'main.js';
  const safeName = name.replace(/[\r\n\u2028\u2029]/g, ' ');
  const module = { exports: {} };
  const requireFn = createRequire(modules);

  let factory;
  try {
    // eslint-disable-next-line no-new-func
    factory = new Function(
      'module',
      'exports',
      'require',
      '__filename',
      '__dirname',
      `${source}\n//# sourceURL=lexinote-plugin://${safeName}`
    );
  } catch (error) {
    throw wrapBundleError(error);
  }

  try {
    factory(module, module.exports, requireFn, name, '/');
  } catch (error) {
    throw wrapBundleError(error);
  }
  return module.exports;
}

/**
 * Wraps unexpected bundle failures in `E_PLUGIN_FAILED: ...`.
 *
 * Explicit `E_*` failures raised by the runtime itself (notably E_UNSUPPORTED_MODULE,
 * E_QUOTA_EXCEEDED and E_UNSUPPORTED_API) are propagated unchanged: callers need the
 * precise code to explain a refusal, and wrapping them would hide it.
 */
function wrapBundleError(error) {
  if (isCodedError(error)) {
    return error;
  }
  return createError(ERROR_CODES.PLUGIN_FAILED, rawErrorMessage(error));
}

function hasOnlyAllowedKeys(object, allowed) {
  const keys = Object.keys(object);
  const unknown = [];
  for (let index = 0; index < keys.length; index += 1) {
    if (allowed.indexOf(keys[index]) < 0) {
      unknown.push(keys[index]);
    }
  }
  return unknown;
}

function checkString(errors, object, field, required) {
  const value = object[field];
  if (value === undefined || value === null) {
    if (required) {
      errors.push(`缺少字段 ${field}`);
    }
    return;
  }
  if (typeof value !== 'string' || value.length === 0) {
    errors.push(`字段 ${field} 必须是非空字符串`);
  }
}

function manifestResult(errors, warnings, manifest, kind) {
  return {
    ok: errors.length === 0,
    valid: errors.length === 0,
    errors,
    problems: errors,
    warnings,
    manifest,
    kind
  };
}

/**
 * Validates a `lexinote-plugin` or Obsidian manifest. Invalid manifests are reported,
 * never silently normalised into something that boots.
 *
 * @param {object|string} manifest manifest object or its JSON text
 * @param {'lexinote'|'obsidian'} [kind]
 * @returns {{ok:boolean, errors:string[], warnings:string[], manifest:object|null, kind:string}}
 */
function validateManifest(manifest, kind) {
  const errors = [];
  const warnings = [];
  const expectedKind = kind === 'obsidian' ? 'obsidian' : 'lexinote';
  let value = manifest;

  if (typeof manifest === 'string') {
    if (manifest.length === 0) {
      return manifestResult(['manifest 为空'], warnings, null, expectedKind);
    }
    try {
      value = JSON.parse(manifest);
    } catch (error) {
      return manifestResult(['manifest 不是合法 JSON'], warnings, null, expectedKind);
    }
  }

  if (!isPlainObject(value)) {
    return manifestResult(['manifest 必须是对象'], warnings, null, expectedKind);
  }

  const required = expectedKind === 'obsidian' ? OBSIDIAN_REQUIRED : LEXINOTE_REQUIRED;
  const allowed = expectedKind === 'obsidian' ? OBSIDIAN_ALLOWED : LEXINOTE_ALLOWED;

  const unknown = hasOnlyAllowedKeys(value, allowed);
  for (let index = 0; index < unknown.length; index += 1) {
    errors.push(`不允许的字段 ${unknown[index]}`);
  }

  for (let index = 0; index < required.length; index += 1) {
    // formatVersion is a number and isDesktopOnly a boolean in the manifest schemas.
    if (required[index] === 'formatVersion' || required[index] === 'isDesktopOnly') {
      continue;
    }
    checkString(errors, value, required[index], true);
  }
  checkString(errors, value, 'description', false);
  checkString(errors, value, 'author', false);

  if (typeof value.id === 'string' && value.id.length > 0 && !ID_PATTERN.test(value.id)) {
    errors.push(`插件 id 非法：${value.id}`);
  }
  if (typeof value.version === 'string' && value.version.length > 0 && !VERSION_PATTERN.test(value.version)) {
    errors.push(`插件版本号非法：${value.version}`);
  }

  if (expectedKind === 'lexinote') {
    if (value.format !== undefined && value.format !== 'lexinote-plugin') {
      errors.push(`format 必须是 lexinote-plugin，实际为 ${String(value.format)}`);
    }
    if (value.formatVersion === undefined) {
      errors.push('缺少字段 formatVersion');
    } else if (value.formatVersion !== 1) {
      errors.push(`不支持的 formatVersion ${String(value.formatVersion)}`);
    }
    if (typeof value.apiVersion === 'string' && value.apiVersion.length > 0 && !/^1(?:\.\d+){0,2}$/.test(value.apiVersion)) {
      errors.push(`不支持的 apiVersion ${value.apiVersion}（本运行时为 1.x）`);
    }
    if (typeof value.main === 'string' && value.main.length > 0 && value.main.indexOf('..') >= 0) {
      errors.push('main 不能包含上级目录引用');
    }
    if (value.isDesktopOnly !== undefined && typeof value.isDesktopOnly !== 'boolean') {
      errors.push('isDesktopOnly 必须是布尔值');
    }

    if (value.capabilities !== undefined) {
      if (!Array.isArray(value.capabilities)) {
        errors.push('capabilities 必须是字符串数组');
      } else {
        const seen = {};
        for (let index = 0; index < value.capabilities.length; index += 1) {
          const capability = value.capabilities[index];
          if (typeof capability !== 'string') {
            errors.push('capabilities 必须是字符串数组');
            continue;
          }
          if (CAPABILITIES.indexOf(capability) < 0) {
            errors.push(`未知能力 ${capability}`);
            continue;
          }
          if (seen[capability]) {
            warnings.push(`能力 ${capability} 重复声明`);
          }
          seen[capability] = true;
        }
      }
    }

    if (value.targets !== undefined) {
      if (!Array.isArray(value.targets)) {
        errors.push('targets 必须是字符串数组');
      } else {
        for (let index = 0; index < value.targets.length; index += 1) {
          if (typeof value.targets[index] !== 'string' || value.targets[index].length === 0) {
            errors.push('targets 必须是字符串数组');
            break;
          }
        }
      }
    }
  } else {
    if (typeof value.minAppVersion === 'string' && value.minAppVersion.length > 0 && !VERSION_PATTERN.test(value.minAppVersion)) {
      errors.push(`minAppVersion 非法：${value.minAppVersion}`);
    }
    if (value.isDesktopOnly === undefined) {
      errors.push('缺少字段 isDesktopOnly');
    } else if (typeof value.isDesktopOnly !== 'boolean') {
      errors.push('isDesktopOnly 必须是布尔值');
    }
  }

  return manifestResult(errors, warnings, value, expectedKind);
}

/** Same validation, but throws the canonical `E_INVALID_ARGUMENT` shape on failure. */
function assertValidManifest(manifest, kind) {
  const result = validateManifest(manifest, kind);
  if (!result.ok) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, result.errors.join('；'));
  }
  return result.manifest;
}

function isValidManifest(manifest, kind) {
  return validateManifest(manifest, kind).ok;
}

function manifestProblems(manifest, kind) {
  return validateManifest(manifest, kind).errors;
}

module.exports = {
  executeBundle,
  validateManifest,
  isValidManifest,
  manifestProblems,
  assertValidManifest,
  CAPABILITIES,
  ID_PATTERN,
  VERSION_PATTERN,
  ALLOWED_MODULES
};
  });

  // ---- module: sdk ----
  __define('sdk', function (module, exports, require) {
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
  });

  // ---- module: ui ----
  __define('ui', function (module, exports, require) {
'use strict';

// The plugin owns this local DOM surface. File and network access still go through
// the same capability checked bridge; rendering a view adds no host permissions.
function createPluginSurface() {
  if (typeof document === 'undefined' || !document.body) { return null; }
  const proto = document.createElement('div').constructor.prototype;
  const elementProto = Object.getPrototypeOf(proto);
  function method(name, callback) {
    if (!elementProto[name]) { Object.defineProperty(elementProto, name, { configurable: true, value: callback }); }
  }
  method('empty', function () { this.replaceChildren(); return this; });
  method('setText', function (text) { this.textContent = text; return this; });
  method('addClass', function (...names) { this.classList.add(...names); return this; });
  method('removeClass', function (...names) { this.classList.remove(...names); return this; });
  method('toggleClass', function (name, force) { this.classList.toggle(name, force); return this; });
  method('setAttr', function (name, value) { this.setAttribute(name, value); return this; });
  method('setAttrs', function (attrs) { Object.keys(attrs).forEach(key => this.setAttribute(key, attrs[key])); return this; });
  method('setCssProps', function (props) { Object.keys(props).forEach(key => this.style.setProperty(key, props[key])); return this; });
  method('onClickEvent', function (callback) { this.addEventListener('click', callback); return this; });
  method('createEl', function (tag, options, callback) {
    const el = document.createElement(tag);
    const opts = typeof options === 'string' ? { cls: options } : (options || {});
    if (opts.cls) { el.className = Array.isArray(opts.cls) ? opts.cls.join(' ') : opts.cls; }
    if (opts.text !== undefined) { el.textContent = opts.text; }
    if (opts.attr) { Object.keys(opts.attr).forEach(key => el.setAttribute(key, opts.attr[key])); }
    if (opts.type) { el.type = opts.type; }
    if (opts.parent) { opts.parent.appendChild(el); } else { this.appendChild(el); }
    if (typeof callback === 'function') { callback(el); }
    return el;
  });
  method('createDiv', function (options, callback) { return this.createEl('div', options, callback); });
  method('createSpan', function (options, callback) { return this.createEl('span', options, callback); });
  let root = document.getElementById('plugin-surface');
  if (!root) { root = document.body.createDiv({ attr: { id: 'plugin-surface' } }); }
  root.replaceChildren();
  const style = document.createElement('style');
  document.head.appendChild(style);

  class PluginSettingTab {
    constructor(app, plugin) { this.app = app; this.plugin = plugin; this.containerEl = document.createElement('div'); }
    async display() {
      if (typeof this.getSettingDefinitions !== 'function') { return; }
      this.containerEl.replaceChildren();
      const data = Object.assign({}, (await this.plugin.loadData()) || {});
      for (const definition of this.getSettingDefinitions()) {
        if (definition.type === 'heading') { this.containerEl.createEl('h4', { text: definition.name }); continue; }
        const setting = new Setting(this.containerEl).setName(definition.name || definition.key);
        if (definition.desc) { setting.setDesc(definition.desc); }
        const control = new Control(setting.controlEl, definition.type === 'textarea' ? 'textarea' : 'input', definition.type === 'password' ? 'password' : 'text');
        control.setValue(data[definition.key] === undefined ? (definition.default || '') : data[definition.key]);
        control.onChange(async value => { data[definition.key] = value; await this.plugin.saveData(data); });
      }
    }
    hide() {}
  }
  class Control {
    constructor(parent, tag, type) { this.inputEl = parent.createEl(tag || 'input'); if (type) { this.inputEl.type = type; } }
    setValue(value) { if (this.inputEl.type === 'checkbox') { this.inputEl.checked = !!value; } else { this.inputEl.value = value; } return this; }
    getValue() { return this.inputEl.type === 'checkbox' ? this.inputEl.checked : this.inputEl.value; }
    setPlaceholder(text) { this.inputEl.placeholder = text; return this; }
    setDisabled(disabled) { this.inputEl.disabled = disabled; return this; }
    setButtonText(text) { this.inputEl.textContent = text; return this; }
    setCta() { this.inputEl.classList.add('mod-cta'); return this; }
    setWarning() { this.inputEl.classList.add('mod-warning'); return this; }
    setTooltip(text) { this.inputEl.title = text; return this; }
    onClick(callback) { this.inputEl.addEventListener('click', callback); return this; }
    onChange(callback) { this.inputEl.addEventListener('change', () => callback(this.getValue())); return this; }
    addOption(value, label) { this.inputEl.createEl('option', { text: label, attr: { value } }); return this; }
    addOptions(options) { Object.keys(options).forEach(key => this.addOption(key, options[key])); return this; }
    setLimits(min, max, step) { Object.assign(this.inputEl, { min, max, step }); return this; }
    setDynamicTooltip() { return this; }
  }
  class Setting {
    constructor(parent) {
      this.settingEl = parent.createDiv('setting-item');
      this.infoEl = this.settingEl.createDiv('setting-item-info');
      this.nameEl = this.infoEl.createDiv('setting-item-name');
      this.descEl = this.infoEl.createDiv('setting-item-description');
      this.controlEl = this.settingEl.createDiv('setting-item-control');
    }
    setName(text) { this.nameEl.textContent = text; return this; }
    setDesc(text) { this.descEl.replaceChildren(); this.descEl.append(text); return this; }
    setHeading() { this.settingEl.classList.add('setting-item-heading'); return this; }
    setClass(name) { this.settingEl.classList.add(name); return this; }
    setDisabled(disabled) { this.controlEl.querySelectorAll('input,button,select').forEach(el => { el.disabled = disabled; }); return this; }
    addText(callback) { callback(new Control(this.controlEl, 'input', 'text')); return this; }
    addTextArea(callback) { callback(new Control(this.controlEl, 'textarea')); return this; }
    addToggle(callback) { callback(new Control(this.controlEl, 'input', 'checkbox')); return this; }
    addDropdown(callback) { callback(new Control(this.controlEl, 'select')); return this; }
    addButton(callback) { callback(new Control(this.controlEl, 'button')); return this; }
    addSlider(callback) { callback(new Control(this.controlEl, 'input', 'range')); return this; }
  }
  class Modal {
    constructor(app) {
      this.app = app;
      this.modalEl = document.createElement('div'); this.modalEl.className = 'modal';
      this.titleEl = this.modalEl.createEl('h3'); this.contentEl = this.modalEl.createDiv('modal-content');
      this.modalEl.createEl('button', { text: '×', cls: 'modal-close-button' }).onclick = () => this.close();
    }
    setTitle(text) { this.titleEl.textContent = text; return this; }
    setContent(text) { this.contentEl.textContent = text; return this; }
    open() { root.appendChild(this.modalEl); this.onOpen(); }
    close() { this.onClose(); this.modalEl.remove(); }
    onOpen() {}
    onClose() {}
  }
  return {
    root, PluginSettingTab, Setting, Modal,
    setStyles(css) { style.textContent = css || ''; },
    dispose() { root.replaceChildren(); style.remove(); }
  };
}

module.exports = { createPluginSurface };
  });

  // ---- module: obsidian ----
  __define('obsidian', function (module, exports, require) {
'use strict';

/**
 * Obsidian compatibility shim.
 *
 * This is a deliberately *partial* implementation of the Obsidian plugin API on top of
 * the LexiNote RPC layer. It is not a reimplementation of Obsidian and it does not fake
 * features the host cannot provide:
 *
 *  - Vault reads and writes are real and go through the host (`read`, `modify`, ...).
 *  - Listings are synchronous over the runtime's FileMirror, as in Obsidian.
 *  - `Vault.delete` maps to the host's soft delete (the note goes to the recycle bin and
 *    can be restored); it is not a permanent filesystem unlink.
 *  - Desktop sidebar views use a local DOM surface. Markdown post-processors and
 *    editor extensions remain unsupported. `requestUrl` throws because networking
 *    is not granted to plugins.
 *  - `Vault.adapter` is intentionally absent-to-throwing: there is no direct filesystem
 *    adapter in the runtime.
 *
 * A fresh module (with fresh class identities) is created per plugin runtime, so
 * `instanceof` and object identity behave the way a single Obsidian app would.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  normalizeVaultPath,
  parentPath,
  baseName,
  clamp,
  rawErrorMessage
} = require('./util');
const { toFileRef } = require('./mirror');
const { createPluginSurface } = require('./ui');

/**
 * Obsidian-compatible normalisation: backslashes become `/`, duplicate slashes and
 * leading/trailing slashes are removed, and `.`/`..` segments are resolved. Vault paths
 * are always relative, so the result never starts with `/`.
 */
function normalizePath(input) {
  const source = input === undefined || input === null ? '' : String(input);
  const parts = [];
  const segments = source.replace(/\\/g, '/').split('/');
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    if (segment === '' || segment === '.') {
      continue;
    }
    if (segment === '..') {
      if (parts.length > 0) {
        parts.pop();
      }
      continue;
    }
    parts.push(segment);
  }
  return parts.join('/');
}

/** True when `value` looks like an EditorPosition `{line, ch}`. */
function isPosition(value) {
  return isPlainObject(value) && typeof value.line === 'number' && typeof value.ch === 'number';
}

/** Index of the first character of every line, honouring CRLF, CR and LF. */
function lineStartsOf(text) {
  const starts = [0];
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    if (code === 13) {
      if (text.charCodeAt(index + 1) === 10) {
        index += 1;
      }
      starts.push(index + 1);
    } else if (code === 10) {
      starts.push(index + 1);
    }
  }
  return starts;
}

/** Content end offset of line `line` (before its CR/LF/CRLF terminator). */
function lineContentEnd(text, starts, line) {
  if (line + 1 >= starts.length) {
    return text.length;
  }
  const next = starts[line + 1];
  if (next > 0 && text.charCodeAt(next - 1) === 10) {
    return next - 2 >= starts[line] && text.charCodeAt(next - 2) === 13 ? next - 2 : next - 1;
  }
  if (next > 0 && text.charCodeAt(next - 1) === 13) {
    return next - 1;
  }
  return next;
}

/**
 * Converts an EditorPosition into a UTF-16 code-unit offset, exactly like Obsidian.
 * `ch` counts JS string units: a CJK character is 1, an emoji (surrogate pair) is 2.
 */
function positionToOffset(text, position) {
  if (!isPosition(position)) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, '位置必须是 {line, ch}');
  }
  const starts = lineStartsOf(text);
  const line = Math.max(0, Math.floor(position.line));
  if (line >= starts.length) {
    return text.length;
  }
  const ch = Math.max(0, Math.floor(position.ch));
  const start = starts[line];
  const end = lineContentEnd(text, starts, line);
  return Math.min(start + ch, end);
}

/** Converts a UTF-16 code-unit offset back into an EditorPosition. */
function offsetToPosition(text, offset) {
  const starts = lineStartsOf(text);
  const value = clamp(typeof offset === 'number' && isFinite(offset) ? Math.floor(offset) : 0, 0, text.length);
  let line = 0;
  for (let index = 0; index < starts.length; index += 1) {
    if (starts[index] <= value) {
      line = index;
    } else {
      break;
    }
  }
  const start = starts[line];
  const end = lineContentEnd(text, starts, line);
  return { line, ch: Math.max(0, Math.min(value, end) - start) };
}

function linesOf(text) {
  const starts = lineStartsOf(text);
  const result = [];
  for (let line = 0; line < starts.length; line += 1) {
    const end = lineContentEnd(text, starts, line);
    result.push(text.slice(starts[line], end));
  }
  return result;
}


/**
 * Builds one Obsidian API module instance.
 *
 * @param {object} options
 * @param {object} options.context LexiNote SDK context
 * @param {object} options.mirror FileMirror
 * @param {string} options.pluginId
 * @param {string} options.vaultId
 * @param {object} [options.manifest] parsed Obsidian manifest
 * @param {Function} [options.log]
 */
function createObsidianApi(options) {
  const surface = createPluginSurface();
  const viewFactories = new Map();
  const pluginLeaves = [];
  const ribbonActions = [];
  const settingTabs = [];
  const settings = isPlainObject(options) ? options : {};
  const context = settings.context;
  const mirror = settings.mirror;
  if (!context || !mirror) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, 'createObsidianApi 缺少 context/mirror');
  }
  const localLogger = typeof settings.log === 'function' ? settings.log : function noopLog() {};
  const pluginId = typeof settings.pluginId === 'string' ? settings.pluginId : '';
  const vaultId = typeof settings.vaultId === 'string' ? settings.vaultId : '';
  const manifest = isPlainObject(settings.manifest) ? settings.manifest : {};
  const notices = [];

  function log(level, message) {
    const severity = typeof level === 'string' && level.length > 0 ? level : 'info';
    const text = typeof message === 'string' ? message : String(message);
    localLogger(severity, text);
    context.log(severity, text);
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  class EventRef {
    constructor(events, name, callback, onOff) {
      this._events = events;
      this.name = name;
      this.callback = callback;
      this._onOff = typeof onOff === 'function' ? onOff : null;
      this._active = true;
    }

    off() {
      if (!this._active) {
        return;
      }
      this._active = false;
      this._events.off(this.name, this.callback);
      if (this._onOff) {
        const hook = this._onOff;
        this._onOff = null;
        hook();
      }
    }
  }

  class Events {
    constructor() {
      this._handlers = new Map();
    }

    on(name, callback, onOff) {
      if (typeof name !== 'string' || name.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '事件名不能为空');
      }
      if (typeof callback !== 'function') {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '事件回调必须是函数');
      }
      let list = this._handlers.get(name);
      if (!list) {
        list = [];
        this._handlers.set(name, list);
      }
      list.push(callback);
      return new EventRef(this, name, callback, onOff);
    }

    count(name) {
      const list = this._handlers.get(name);
      return list ? list.length : 0;
    }

    off(name, callback) {
      const list = this._handlers.get(name);
      if (!list) {
        return 0;
      }
      let removed = 0;
      for (let index = list.length - 1; index >= 0; index -= 1) {
        if (list[index] === callback) {
          list.splice(index, 1);
          removed += 1;
        }
      }
      if (list.length === 0) {
        this._handlers.delete(name);
      }
      return removed;
    }

    offref(ref) {
      if (ref && typeof ref.off === 'function') {
        ref.off();
      }
    }

    trigger(name) {
      const list = this._handlers.get(name);
      if (!list || list.length === 0) {
        return 0;
      }
      const args = Array.prototype.slice.call(arguments, 1);
      const snapshot = list.slice();
      for (let index = 0; index < snapshot.length; index += 1) {
        try {
          snapshot[index].apply(null, args);
        } catch (error) {
          log('error', `Obsidian 事件 ${name} 处理器失败：${rawErrorMessage(error)}`);
        }
      }
      return snapshot.length;
    }
  }

  // ---------------------------------------------------------------------------
  // Files and folders
  // ---------------------------------------------------------------------------

  class TAbstractFile {
    constructor(path, vault) {
      this.path = normalizeVaultPath(path);
      this.name = baseName(this.path) || '/';
      this.parent = null;
      this.vault = vault;
    }
  }

  function basenameOf(name, extension) {
    if (!extension) {
      return name;
    }
    const suffix = `.${extension}`;
    return name.length > suffix.length && name.toLowerCase().endsWith(suffix.toLowerCase())
      ? name.slice(0, -suffix.length)
      : name;
  }

  class TFile extends TAbstractFile {
    constructor(ref, vault) {
      super(ref.path, vault);
      this.stat = { ctime: 0, mtime: 0, size: 0 };
      this.extension = '';
      this.basename = '';
      Object.defineProperty(this, '_ref', {
        value: toFileRef(ref),
        writable: true,
        enumerable: false,
        configurable: true
      });
      this._update(this._ref);
    }

    _update(raw) {
      const ref = toFileRef(raw);
      this._ref = ref;
      this.path = ref.path;
      this.name = ref.name;
      this.extension = ref.extension;
      this.basename = basenameOf(ref.name, ref.extension);
      this.stat = { ctime: ref.ctime, mtime: ref.mtime, size: ref.size };
      return this;
    }
  }

  class TFolder extends TAbstractFile {
    constructor(path, vault) {
      super(path, vault);
      // `normalizeVaultPath('/')` is '', but the Obsidian root folder path is '/'.
      if (this.path.length === 0) {
        this.path = '/';
      }
      this.children = [];
      this.name = this.path === '/' ? '/' : baseName(this.path);
    }

    isRoot() {
      return this.path === '/';
    }
  }

  // Obsidian's event names map onto the host's core event names. Registering a local
  // listener must also create exactly one host subscription, otherwise the host has no
  // reason to deliver the event into this WebView at all.
  const VAULT_EVENT_TO_CORE = {
    create: 'vault.created',
    modify: 'vault.modified',
    rename: 'vault.renamed',
    delete: 'vault.deleted'
  };
  const WORKSPACE_EVENT_TO_CORE = {
    'file-open': 'workspace.active-file-changed',
    'active-leaf-change': 'workspace.active-file-changed'
  };
  const hostEventRefs = new Map();

  function acquireHostEvent(coreEvent) {
    let entry = hostEventRefs.get(coreEvent);
    if (entry) {
      return entry;
    }
    // The callback is intentionally a no-op: runtime.receiveEvent does the actual
    // Obsidian dispatch after updating the mirror. The subscription only asks the host
    // to start sending this core event.
    const disposable = context.events.on(coreEvent, function hostBridgeEvent() {});
    entry = { disposable };
    hostEventRefs.set(coreEvent, entry);
    return entry;
  }

  function releaseHostEvent(coreEvent) {
    const entry = hostEventRefs.get(coreEvent);
    if (!entry) {
      return;
    }
    hostEventRefs.delete(coreEvent);
    try {
      entry.disposable.dispose();
    } catch (error) {
      log('warn', `无法释放宿主事件订阅 ${coreEvent}: ${rawErrorMessage(error)}`);
    }
  }

  function disposeHostEvents() {
    Array.from(hostEventRefs.keys()).forEach((coreEvent) => releaseHostEvent(coreEvent));
  }

  // ---------------------------------------------------------------------------
  // Vault
  // ---------------------------------------------------------------------------

  class Vault {
    constructor() {
      this._files = new Map();
      this._byId = new Map();
      this._folders = new Map();
      this._contents = new Map();
      this._events = new Events();
      this._root = new TFolder('/', this);
      this._folders.set('/', this._root);
      this._sync();
    }

    /** Direct filesystem adapter is not part of this runtime. */
    get adapter() {
      throw createError(
        ERROR_CODES.UNSUPPORTED_API,
        'Vault.adapter 不可用：插件运行在无文件系统访问权的 WebView 中'
      );
    }

    _sync() {
      const refs = mirror.listAll();
      const nextFiles = new Map();
      const nextById = new Map();
      for (let index = 0; index < refs.length; index += 1) {
        const ref = refs[index];
        let file = this._byId.get(ref.id);
        if (!file) {
          file = this._files.get(ref.path);
        }
        if (!file) {
          file = new TFile(ref, this);
        } else {
          file._update(ref);
        }
        nextFiles.set(file.path, file);
        nextById.set(ref.id, file);
      }
      this._files = nextFiles;
      this._byId = nextById;

      const knownPaths = new Set(nextFiles.keys());
      Array.from(this._contents.keys()).forEach((path) => {
        if (!knownPaths.has(path)) {
          this._contents.delete(path);
        }
      });

      // Rebuild the folder tree while keeping TFolder instances stable for the same
      // path, matching Obsidian's object identity semantics for files *and* folders.
      const folderPaths = new Set();
      nextFiles.forEach((file) => {
        let current = parentPath(file.path);
        while (current.length > 0) {
          folderPaths.add(current);
          current = parentPath(current);
        }
      });
      this._folders.forEach((folder, folderPath) => {
        if (folderPath !== '/' && !folderPaths.has(folderPath)) {
          this._folders.delete(folderPath);
        }
      });
      this._root.parent = null;
      this._root.children = [];
      this._folders.forEach((folder) => {
        folder.children = [];
        folder.parent = null;
      });
      const orderedFolders = Array.from(folderPaths).sort((left, right) => {
        const depth = left.split('/').length - right.split('/').length;
        return depth !== 0 ? depth : left.localeCompare(right);
      });
      for (let index = 0; index < orderedFolders.length; index += 1) {
        this._ensureFolder(orderedFolders[index]);
      }
      nextFiles.forEach((file) => {
        const folder = this._ensureFolder(parentPath(file.path));
        file.parent = folder;
        if (folder.children.indexOf(file) < 0) {
          folder.children.push(file);
        }
      });
    }

    _ensureFolder(relative) {
      const path = normalizeVaultPath(relative);
      if (path.length === 0) {
        return this._root;
      }
      const segments = path.split('/');
      let current = '';
      let parent = this._root;
      for (let index = 0; index < segments.length; index += 1) {
        current = current.length === 0 ? segments[index] : `${current}/${segments[index]}`;
        let folder = this._folders.get(current);
        if (!folder) {
          folder = new TFolder(current, this);
          this._folders.set(current, folder);
        }
        folder.parent = parent;
        if (parent.children.indexOf(folder) < 0) {
          parent.children.push(folder);
        }
        parent = folder;
      }
      return parent;
    }

    _fileFor(ref) {
      if (!ref) {
        return null;
      }
      this._sync();
      const byId = typeof ref.id === 'string' ? this._byId.get(ref.id) : null;
      if (byId) {
        return byId;
      }
      const byPath = this._files.get(normalizeVaultPath(ref.path));
      if (byPath) {
        return byPath;
      }
      // Used for delete events: the mirror no longer has the file, but handlers still
      // receive the same TFile instance that was listed moments ago.
      const file = new TFile(ref, this);
      const folder = this._ensureFolder(parentPath(file.path));
      file.parent = folder;
      folder.children.push(file);
      this._files.set(file.path, file);
      this._byId.set(file._ref.id, file);
      return file;
    }

    _assertFile(file) {
      if (!(file instanceof TFile)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, '需要 TFile');
      }
      return file;
    }

    get name() {
      return 'LexiNote';
    }

    getRoot() {
      return this._root;
    }

    getFiles() {
      this._sync();
      const files = Array.from(this._files.values());
      const folders = Array.from(this._folders.values()).filter((folder) => folder !== this._root);
      return files.concat(folders);
    }

    getAllLoadedFiles() {
      return this.getFiles();
    }

    getMarkdownFiles() {
      this._sync();
      const result = [];
      this._files.forEach((file) => {
        if (file.extension === 'md' || file.extension === 'markdown') {
          result.push(file);
        }
      });
      return result;
    }

    getAbstractFileByPath(path) {
      this._sync();
      const target = normalizeVaultPath(path);
      if (target.length === 0) {
        return this._root;
      }
      return this._files.get(target) || this._folders.get(target) || null;
    }

    async read(file) {
      const target = this._assertFile(file);
      const text = await context.vault.read(target._ref);
      const value = typeof text === 'string' ? text : '';
      this._contents.set(target.path, value);
      return value;
    }

    async cachedRead(file) {
      const target = this._assertFile(file);
      if (this._contents.has(target.path)) {
        return this._contents.get(target.path);
      }
      return this.read(target);
    }

    async create(path, data) {
      const ref = await context.vault.create(path, typeof data === 'string' ? data : '');
      this._sync();
      const file = this._fileFor(ref);
      if (file) {
        this._contents.set(file.path, typeof data === 'string' ? data : '');
      }
      return file;
    }

    async modify(file, data) {
      const target = this._assertFile(file);
      const text = typeof data === 'string' ? data : String(data === undefined ? '' : data);
      await context.vault.write(target._ref, text);
      this._sync();
      this._contents.set(target.path, text);
    }

    async append(file, data) {
      const target = this._assertFile(file);
      const current = await this.read(target);
      const text = typeof data === 'string' ? data : String(data === undefined ? '' : data);
      await this.modify(target, current + text);
    }

    /** Maps to the host's soft delete (recycle bin), not a permanent unlink. */
    async delete(file, force) {
      const target = this._assertFile(file);
      await context.vault.delete(target._ref);
      this._contents.delete(target.path);
      this._sync();
    }

    async rename(file, newPath) {
      const target = this._assertFile(file);
      const oldPath = target.path;
      await context.vault.rename(target._ref, newPath);
      this._sync();
      if (this._contents.has(oldPath)) {
        const content = this._contents.get(oldPath);
        this._contents.delete(oldPath);
        this._contents.set(target.path, content);
      }
      return target;
    }

    _releaseHostIfUnused(coreEvent) {
      let active = 0;
      const names = Object.keys(VAULT_EVENT_TO_CORE);
      for (let index = 0; index < names.length; index += 1) {
        if (VAULT_EVENT_TO_CORE[names[index]] === coreEvent) {
          active += this._events.count(names[index]);
        }
      }
      if (active === 0) {
        releaseHostEvent(coreEvent);
      }
    }

    on(name, callback) {
      const coreEvent = VAULT_EVENT_TO_CORE[name];
      const self = this;
      const ref = this._events.on(
        name,
        callback,
        coreEvent ? () => self._releaseHostIfUnused(coreEvent) : null
      );
      if (coreEvent) {
        acquireHostEvent(coreEvent);
      }
      return ref;
    }

    off(name, callback) {
      const removed = this._events.off(name, callback);
      const coreEvent = VAULT_EVENT_TO_CORE[name];
      if (removed > 0 && coreEvent) {
        this._releaseHostIfUnused(coreEvent);
      }
    }

    offref(ref) {
      this._events.offref(ref);
    }
  }

  // ---------------------------------------------------------------------------
  // Metadata cache
  // ---------------------------------------------------------------------------

  class MetadataCache {
    constructor(vault) {
      this._vault = vault;
    }

    _toCache(snapshot) {
      if (!snapshot) {
        return null;
      }
      const headings = Array.isArray(snapshot.headings)
        ? snapshot.headings.map((heading) => ({
          heading: typeof heading.heading === 'string' ? heading.heading : '',
          level: typeof heading.level === 'number' ? heading.level : 1
        }))
        : [];
      const links = Array.isArray(snapshot.links)
        ? snapshot.links.map((link) => ({
          link: typeof link.link === 'string' ? link.link : '',
          original: typeof link.original === 'string' ? link.original : '',
          displayText: typeof link.displayText === 'string' ? link.displayText : ''
        }))
        : [];
      const tags = Array.isArray(snapshot.tags)
        ? snapshot.tags.map((tag) => ({ tag: typeof tag === 'string' ? tag : String(tag) }))
        : [];
      // Deliberately reduced: no `sections`, `listItems`, `blocks` or `frontmatter`
      // object, because the host only guarantees headings/links/tags.
      return { headings, links, tags };
    }

    getFileCache(file) {
      if (!(file instanceof TFile)) {
        return null;
      }
      return this._toCache(mirror.metadata(file._ref.id));
    }

    getCache(path) {
      const file = this._vault.getAbstractFileByPath(path);
      return file ? this.getFileCache(file) : null;
    }

    getFirstLinkpathDest(linkpath, sourcePath) {
      this._vault._sync();
      const raw = String(linkpath === undefined || linkpath === null ? '' : linkpath)
        .split('#')[0]
        .split('|')[0]
        .trim();
      if (raw.length === 0) {
        return null;
      }
      const target = normalizeVaultPath(raw);
      const candidates = [target];
      if (typeof sourcePath === 'string' && sourcePath.length > 0 && target.indexOf('/') < 0) {
        const relative = normalizeVaultPath(`${parentPath(sourcePath)}/${target}`);
        if (candidates.indexOf(relative) < 0) {
          candidates.push(relative);
        }
      }
      const expanded = [];
      for (let index = 0; index < candidates.length; index += 1) {
        const candidate = candidates[index];
        expanded.push(candidate);
        if (!/\.[A-Za-z0-9]+$/.test(candidate)) {
          expanded.push(`${candidate}.md`);
        }
      }
      for (let index = 0; index < expanded.length; index += 1) {
        const file = this._vault._files.get(expanded[index]);
        if (file) {
          return file;
        }
      }
      const lower = expanded.map((path) => path.toLowerCase());
      const files = Array.from(this._vault._files.values());
      for (let index = 0; index < files.length; index += 1) {
        if (lower.indexOf(files[index].path.toLowerCase()) >= 0) {
          return files[index];
        }
      }
      const wanted = baseName(target).toLowerCase();
      for (let index = 0; index < files.length; index += 1) {
        if (files[index].name.toLowerCase() === wanted || files[index].basename.toLowerCase() === wanted) {
          return files[index];
        }
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Editor
  // ---------------------------------------------------------------------------

  class Editor {
    constructor(editorOptions) {
      const optionsValue = isPlainObject(editorOptions) ? editorOptions : {};
      this._mirror = optionsValue.mirror || mirror;
      this._context = optionsValue.context || context;
      this.file = optionsValue.file || null;
      this._editorId = typeof optionsValue.editorId === 'string' ? optionsValue.editorId : '';
      this._selection = {
        anchor: { line: 0, ch: 0 },
        head: { line: 0, ch: 0 }
      };
    }

    getValue() {
      const snapshot = this._mirror.editor();
      return snapshot && typeof snapshot.content === 'string' ? snapshot.content : '';
    }

    getCursor(which) {
      const key = which === 'anchor' || which === 'from' ? 'anchor' : 'head';
      const position = this._selection[key];
      return { line: position.line, ch: position.ch };
    }

    getSelection() {
      return {
        anchor: { line: this._selection.anchor.line, ch: this._selection.anchor.ch },
        head: { line: this._selection.head.line, ch: this._selection.head.ch }
      };
    }

    setSelection(anchor, head) {
      if (!isPosition(anchor) || !isPosition(head)) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'setSelection 需要两个 {line, ch}');
      }
      const text = this.getValue();
      const anchorOffset = positionToOffset(text, anchor);
      const headOffset = positionToOffset(text, head);
      this._selection.anchor = offsetToPosition(text, anchorOffset);
      this._selection.head = offsetToPosition(text, headOffset);
    }

    posToOffset(position) {
      return positionToOffset(this.getValue(), position);
    }

    offsetToPos(offset) {
      return offsetToPosition(this.getValue(), offset);
    }

    getLine(line) {
      const lines = linesOf(this.getValue());
      const index = Math.floor(typeof line === 'number' ? line : 0);
      return index >= 0 && index < lines.length ? lines[index] : '';
    }

    lineCount() {
      return linesOf(this.getValue()).length;
    }

    _collapsedRange() {
      const text = this.getValue();
      const first = positionToOffset(text, this._selection.anchor);
      const second = positionToOffset(text, this._selection.head);
      return { from: Math.min(first, second), to: Math.max(first, second) };
    }

    _setOffsets(from, to) {
      const text = this.getValue();
      this._selection.anchor = offsetToPosition(text, from);
      this._selection.head = offsetToPosition(text, to);
    }

    async replaceSelection(text) {
      const value = typeof text === 'string' ? text : String(text === undefined ? '' : text);
      const range = this._collapsedRange();
      const result = await this._context.editor.replaceSelection(value);
      const content = result && typeof result.content === 'string' ? result.content : this.getValue();
      const caret = offsetToPosition(content, range.from + value.length);
      this._selection.anchor = { line: caret.line, ch: caret.ch };
      this._selection.head = { line: caret.line, ch: caret.ch };
      return undefined;
    }

    async replaceRange(text, from, to) {
      const value = typeof text === 'string' ? text : String(text === undefined ? '' : text);
      const content = this.getValue();
      const fromOffset = typeof from === 'number' ? clamp(from, 0, content.length) : positionToOffset(content, from);
      const toOffset = typeof to === 'number' ? clamp(to, 0, content.length) : positionToOffset(content, to);
      const start = Math.min(fromOffset, toOffset);
      const end = Math.max(fromOffset, toOffset);
      // The host only exposes `replaceSelection` (host selection) and `replaceAll`.
      // Replacing an arbitrary local range therefore has to go through a whole-document
      // write so the correct characters are removed, not whatever the host has selected.
      const next = `${content.slice(0, start)}${value}${content.slice(end)}`;
      const snapshot = this._mirror.editor();
      await this._context.editor.replaceAll(next, snapshot ? snapshot.revision : 0);
      const caret = offsetToPosition(next, start + value.length);
      this._selection.anchor = { line: caret.line, ch: caret.ch };
      this._selection.head = { line: caret.line, ch: caret.ch };
      return undefined;
    }

    async setValue(value) {
      const text = typeof value === 'string' ? value : String(value === undefined ? '' : value);
      const snapshot = this._mirror.editor();
      await this._context.editor.replaceAll(text, snapshot ? snapshot.revision : 0);
      this._selection.anchor = { line: 0, ch: 0 };
      this._selection.head = { line: 0, ch: 0 };
    }
  }

  // ---------------------------------------------------------------------------
  // Workspace / views
  // ---------------------------------------------------------------------------

  class Component {
    constructor() {
      this._events = [];
      this._intervals = new Set();
      this._domEvents = [];
      this._children = [];
      this._loaded = false;
    }

    registerEvent(ref) {
      if (ref && typeof ref.off === 'function') {
        this._events.push(ref);
      }
      return ref;
    }

    registerInterval(id) {
      this._intervals.add(id);
      return id;
    }

    registerDomEvent(el, type, callback, optionsValue) {
      if (!el || typeof el.addEventListener !== 'function' || typeof el.removeEventListener !== 'function') {
        throw createError(
          ERROR_CODES.UNSUPPORTED_API,
          'registerDomEvent 需要真实 DOM 元素；插件运行时没有 Obsidian UI DOM'
        );
      }
      el.addEventListener(type, callback, optionsValue);
      this._domEvents.push({ el, type, callback, options: optionsValue });
    }

    addChild(child) {
      if (!child) {
        return child;
      }
      this._children.push(child);
      if (typeof child.load === 'function') {
        const loaded = child.load();
        if (loaded && typeof loaded.catch === 'function') {
          loaded.catch((error) => log('error', `子组件加载失败：${rawErrorMessage(error)}`));
        }
      }
      return child;
    }

    removeChild(child) {
      const index = this._children.indexOf(child);
      if (index >= 0) {
        this._children.splice(index, 1);
      }
      if (child && typeof child.unload === 'function') {
        const unloaded = child.unload();
        if (unloaded && typeof unloaded.catch === 'function') {
          unloaded.catch(() => {});
        }
      }
      return child;
    }

    async load() {
      if (this._loaded) {
        return;
      }
      this._loaded = true;
      await this.onload();
    }

    async unload() {
      if (!this._loaded) {
        return;
      }
      this._loaded = false;
      try {
        await this.onunload();
      } finally {
        this._release();
      }
    }

    /** Releases every tracked resource; safe to call even when `load()` was skipped. */
    _release() {
      const events = this._events.splice(0);
      for (let index = events.length - 1; index >= 0; index -= 1) {
        try {
          events[index].off();
        } catch (error) {
          // ignore
        }
      }
      this._intervals.forEach((id) => {
        try {
          clearInterval(id);
        } catch (error) {
          // ignore
        }
      });
      this._intervals.clear();
      this._domEvents.forEach((entry) => {
        try {
          entry.el.removeEventListener(entry.type, entry.callback, entry.options);
        } catch (error) {
          // ignore
        }
      });
      this._domEvents.length = 0;
      const children = this._children.splice(0);
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child && typeof child._release === 'function') {
          child._release();
        }
      }
    }

    onload() {}

    onunload() {}
  }

  class WorkspaceLeaf {
    constructor(view) {
      this.view = view || null;
      this.viewType = view && typeof view.getViewType === 'function' ? view.getViewType() : '';
    }

    async setViewState(state) {
      if (!surface || !viewFactories.has(state.type)) {
        throw createError(ERROR_CODES.UNSUPPORTED_API, `未注册的插件视图：${state.type}`);
      }
      if (this.view && this.view.getViewType() === state.type) { return; }
      await this.detach();
      this.view = viewFactories.get(state.type)(this);
      this.viewType = state.type;
      pluginLeaves.push(this);
      surface.root.replaceChildren(this.view.containerEl);
      if (this.view.onOpen) { await this.view.onOpen(); }
    }

    getViewState() { return { type: this.viewType, active: true }; }

    async detach() {
      const view = this.view;
      this.view = null;
      const index = pluginLeaves.indexOf(this);
      if (index >= 0) { pluginLeaves.splice(index, 1); }
      if (view && view.onClose) { await view.onClose(); }
      if (view && view._release) { view._release(); }
      if (view && view.containerEl) { view.containerEl.remove(); }
    }
  }

  class ItemView extends Component {
    constructor(leaf) {
      super();
      this.leaf = leaf || new WorkspaceLeaf();
      this.app = app;
      this.containerEl = null;
      if (surface) {
        this.containerEl = document.createElement('div');
        this.containerEl.className = 'workspace-leaf-content';
        this.containerEl.createDiv('view-header');
        this.contentEl = this.containerEl.createDiv('view-content');
      }
    }

    getViewType() {
      return 'item';
    }

    getDisplayText() {
      return '';
    }
  }

  class MarkdownView extends ItemView {
    constructor(leaf, file, editor) {
      super(leaf);
      this.file = file || null;
      this.editor = editor || null;
      this.viewType = 'markdown';
    }

    getViewType() {
      return 'markdown';
    }

    getDisplayText() {
      return this.file ? this.file.basename : '';
    }
  }

  class Workspace {
    constructor(vault) {
      this._vault = vault;
      this._events = new Events();
      this._activeView = null;
      this._activeViewKey = '';
      this.activeLeaf = null;
    }

    _activeViewForCurrentState() {
      const snapshot = mirror.editor();
      let activeFile = mirror.activeFile();
      if (!activeFile && snapshot && snapshot.noteId) {
        activeFile = mirror.getById(snapshot.noteId);
      }
      const file = activeFile ? this._vault._fileFor(activeFile) : null;
      if (!snapshot && !file) {
        this._activeView = null;
        this._activeViewKey = '';
        return null;
      }
      const key = `${snapshot ? snapshot.editorId : ''}|${file ? file.path : ''}`;
      if (this._activeView && this._activeViewKey === key) {
        return this._activeView;
      }
      const editor = snapshot
        ? new Editor({
          mirror,
          context,
          file,
          editorId: snapshot.editorId
        })
        : null;
      const view = new MarkdownView(new WorkspaceLeaf(), file, editor);
      view.leaf.view = view;
      view.leaf.viewType = 'markdown';
      this._activeView = view;
      this._activeViewKey = key;
      this.activeLeaf = view.leaf;
      return view;
    }

    get activeEditor() {
      return this._activeViewForCurrentState();
    }

    getActiveFile() {
      const active = mirror.activeFile();
      return active ? this._vault._fileFor(active) : null;
    }

    getActiveViewOfType(type) {
      if (typeof type !== 'function') {
        return null;
      }
      const view = this._activeViewForCurrentState();
      if (!view) {
        return null;
      }
      return view instanceof type ? view : null;
    }

    async openLinkText(linkpath, sourcePath) {
      const target = metadataCache.getFirstLinkpathDest(linkpath, sourcePath);
      if (!target) {
        throw createError(ERROR_CODES.NOT_FOUND, `链接目标不存在：${String(linkpath)}`);
      }
      await context.workspace.openFile(target.path);
      return undefined;
    }

    getLeavesOfType(type) {
      if (surface) { return pluginLeaves.filter(leaf => leaf.viewType === type); }
      throw createError(
        ERROR_CODES.UNSUPPORTED_API,
        `Workspace.getLeavesOfType(${String(type)}) 不可用：宿主只有一个编辑器视图`
      );
    }

    getRightLeaf() { return new WorkspaceLeaf(); }
    getLeftLeaf() { return new WorkspaceLeaf(); }
    getLeaf() { return new WorkspaceLeaf(); }
    get layoutReady() { return !!surface; }
    onLayoutReady(callback) { if (surface) { return callback(); } }
    async revealLeaf(leaf) {
      if (surface && leaf && leaf.view) { surface.root.replaceChildren(leaf.view.containerEl); }
    }
    detachLeavesOfType(type) { return Promise.all(this.getLeavesOfType(type).map(leaf => leaf.detach())); }

    _releaseHostIfUnused(coreEvent) {
      let active = 0;
      const names = Object.keys(WORKSPACE_EVENT_TO_CORE);
      for (let index = 0; index < names.length; index += 1) {
        if (WORKSPACE_EVENT_TO_CORE[names[index]] === coreEvent) {
          active += this._events.count(names[index]);
        }
      }
      if (active === 0) {
        releaseHostEvent(coreEvent);
      }
    }

    on(name, callback) {
      const coreEvent = WORKSPACE_EVENT_TO_CORE[name];
      const self = this;
      const ref = this._events.on(
        name,
        callback,
        coreEvent ? () => self._releaseHostIfUnused(coreEvent) : null
      );
      if (coreEvent) {
        acquireHostEvent(coreEvent);
      }
      return ref;
    }

    off(name, callback) {
      const removed = this._events.off(name, callback);
      const coreEvent = WORKSPACE_EVENT_TO_CORE[name];
      if (removed > 0 && coreEvent) {
        this._releaseHostIfUnused(coreEvent);
      }
    }

    offref(ref) {
      this._events.offref(ref);
    }
  }

  // ---------------------------------------------------------------------------
  // Component / Plugin
  // ---------------------------------------------------------------------------

  const pluginState = {
    instance: null
  };

  class Plugin extends Component {
    constructor(appValue, manifestValue) {
      super();
      this.app = appValue || app;
      this.manifest = manifestValue || manifest;
      this._commandDisposables = [];
      pluginState.instance = this;
    }

    async loadData() {
      return context.storage.get('plugin-data');
    }

    async saveData(data) {
      return context.storage.set('plugin-data', data);
    }

    addCommand(command) {
      if (!isPlainObject(command) || typeof command.id !== 'string' || command.id.length === 0) {
        throw createError(ERROR_CODES.INVALID_ARGUMENT, 'addCommand 需要 { id, name, callback }');
      }
      const self = this;
      let run = null;
      if (typeof command.callback === 'function') {
        run = function runCallback() {
          return command.callback.call(self);
        };
      } else if (typeof command.editorCallback === 'function') {
        run = function runEditorCallback() {
          const view = self.app.workspace.activeEditor;
          return command.editorCallback.call(self, view ? view.editor : null);
        };
      } else if (typeof command.checkCallback === 'function') {
        run = function runCheckCallback() {
          if (command.checkCallback.call(self, false)) {
            return command.checkCallback.call(self, true);
          }
          return undefined;
        };
      }
      if (!run) {
        throw createError(
          ERROR_CODES.UNSUPPORTED_API,
          'addCommand 需要 callback/editorCallback/checkCallback 之一'
        );
      }
      const disposable = context.commands.register({
        id: command.id,
        title: typeof command.name === 'string' && command.name.length > 0 ? command.name : command.id,
        run
      });
      this._commandDisposables.push(disposable);
      return disposable;
    }

    addRibbonIcon(icon, title, callback) {
      if (surface) {
        const element = document.createElement('button');
        element.title = title || ''; element.dataset.icon = icon || '';
        element.addEventListener('click', callback);
        ribbonActions.push({ element, callback });
        return element;
      }
      throw createError(ERROR_CODES.UNSUPPORTED_API, 'addRibbonIcon 不可用：宿主没有 Obsidian 功能区图标 API');
    }

    addStatusBarItem() {
      if (surface) { return surface.root.createDiv('status-bar-item'); }
      throw createError(ERROR_CODES.UNSUPPORTED_API, 'addStatusBarItem 不可用：宿主没有 Obsidian 状态栏');
    }

    addSettingTab(tab) {
      if (surface) { settingTabs.push(tab); return; }
      throw createError(ERROR_CODES.UNSUPPORTED_API, 'addSettingTab 不可用：插件设置页由 LexiNote 宿主统一提供');
    }

    registerView(type, factory) {
      if (surface) { viewFactories.set(type, factory); return; }
      throw createError(ERROR_CODES.UNSUPPORTED_API, 'registerView 不可用：宿主不支持插件自定义视图');
    }

    registerMarkdownPostProcessor() {
      throw createError(
        ERROR_CODES.UNSUPPORTED_API,
        'registerMarkdownPostProcessor 不可用：宿主渲染管线不开放插件后处理'
      );
    }

    registerEditorExtension() {
      throw createError(ERROR_CODES.UNSUPPORTED_API, 'registerEditorExtension 不可用：宿主编辑器不加载 CodeMirror 扩展');
    }

    async onload() {}

    async onunload() {}
  }

  // ---------------------------------------------------------------------------
  // Notice / UI
  // ---------------------------------------------------------------------------

  class Notice {
    constructor(message, timeout) {
      this.message = typeof message === 'string' ? message : String(message === undefined ? '' : message);
      this.timeout = typeof timeout === 'number' && isFinite(timeout) && timeout >= 0 ? timeout : null;
      notices.push(this.message);
      try {
        const pending = context.ui.notice(this.message, this.timeout === null ? undefined : this.timeout);
        if (pending && typeof pending.catch === 'function') {
          pending.catch((error) => log('error', `通知发送失败：${rawErrorMessage(error)}`));
        }
      } catch (error) {
        log('error', `通知发送失败：${rawErrorMessage(error)}`);
      }
    }

    hide() {
      // The host owns notice lifetime; there is no DOM element to remove.
    }
  }

  function unsupportedUi(name, reason) {
    return class UnsupportedUiSurface {
      constructor() {
        throw createError(ERROR_CODES.UNSUPPORTED_API, `${name} 不可用：${reason}`);
      }
    };
  }

  const Modal = surface ? surface.Modal : unsupportedUi('Modal', '插件运行时没有 Obsidian 弹窗容器');
  Object.defineProperty(Modal, 'name', { value: 'Modal' });
  const Setting = surface ? surface.Setting : unsupportedUi('Setting', '插件运行时没有 Obsidian 设置界面容器');
  Object.defineProperty(Setting, 'name', { value: 'Setting' });
  const PluginSettingTab = surface ? surface.PluginSettingTab : unsupportedUi('PluginSettingTab', '插件设置页不是二级 UI 的一部分');
  Object.defineProperty(PluginSettingTab, 'name', { value: 'PluginSettingTab' });

  function requestUrl() {
    throw createError(ERROR_CODES.UNSUPPORTED_API, 'requestUrl 不可用：插件没有联网能力');
  }

  const Platform = Object.freeze({
    isDesktopApp: false,
    isMobile: true,
    isAndroidApp: false,
    isIosApp: false,
    isMacOS: false,
    isWin: false,
    isLinux: false,
    isPhone: true,
    isTablet: false,
    isDesktop: false,
    /** LexiNote extension (not part of the upstream Obsidian API). */
    isHarmonyOS: true
  });

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------

  const vault = new Vault();
  const metadataCache = new MetadataCache(vault);
  const workspace = new Workspace(vault);

  const app = Object.freeze({
    get vault() {
      return vault;
    },
    get workspace() {
      return workspace;
    },
    get metadataCache() {
      return metadataCache;
    }
  });

  function fileForRef(ref) {
    return vault._fileFor(ref);
  }

  async function releasePlugin() {
    await Promise.all(pluginLeaves.slice().map(leaf => leaf.detach()));
    if (surface) { surface.dispose(); }
    disposeHostEvents();
    const instance = pluginState.instance;
    if (instance) {
      for (let index = 0; index < instance._commandDisposables.length; index += 1) {
        try {
          instance._commandDisposables[index].dispose();
        } catch (error) {
          // ignore
        }
      }
      instance._commandDisposables.length = 0;
      try {
        instance._release();
      } catch (error) {
        log('error', `Obsidian 插件资源释放失败：${rawErrorMessage(error)}`);
      }
      pluginState.instance = null;
    }
  }

  const internal = {
    setStyles(css) { if (surface) { surface.setStyles(css); } },
    async present() {
      if (!surface) { return; }
      if (pluginLeaves.length) { await workspace.revealLeaf(pluginLeaves[0]); return; }
      if (viewFactories.size) {
        const leaf = workspace.getRightLeaf(false);
        await leaf.setViewState({ type: viewFactories.keys().next().value, active: true });
        return;
      }
      if (ribbonActions.length) { await ribbonActions[0].callback(); if (pluginLeaves.length) { return; } }
      // Command-only plugins expose their actual registered actions in their own pane.
      surface.root.replaceChildren();
      surface.root.createEl('h3', { text: manifest.name || pluginId });
      const commands = context.__internal.commandMap;
      if (commands && commands.forEach) {
        commands.forEach((command, id) => {
          surface.root.createEl('button', { text: command.title || id }).onclick = async () => {
            try { await context.__internal.runCommand(id); }
            catch (error) { new Notice(rawErrorMessage(error)); }
          };
        });
      }
      for (const tab of settingTabs) {
        surface.root.appendChild(tab.containerEl);
        await tab.display();
      }
      if ((!commands || commands.size === 0) && !settingTabs.length) { surface.root.createEl('p', { text: '此插件未提供侧栏视图或命令。' }); }
    },
    context,
    mirror,
    pluginId,
    vaultId,
    vault,
    workspace,
    metadataCache,
    app,
    notices,
    getPlugin() {
      return pluginState.instance;
    },
    setPlugin(instance) {
      pluginState.instance = instance;
    },
    releasePlugin,
    fileForRef,
    syncVault() {
      vault._sync();
    },
    emitVaultEvent(name) {
      const args = Array.prototype.slice.call(arguments, 1);
      return vault._events.trigger.apply(vault._events, [name].concat(args));
    },
    invalidateContent(ref) {
      if (!ref) {
        return;
      }
      const file = (ref.id ? vault._byId.get(ref.id) : null) ||
        (ref.path ? vault._files.get(normalizeVaultPath(ref.path)) : null);
      if (file) {
        vault._contents.delete(file.path);
      }
    },
    emitWorkspaceEvent(name) {
      const args = Array.prototype.slice.call(arguments, 1);
      return workspace._events.trigger.apply(workspace._events, [name].concat(args));
    },
    getActiveView() {
      return workspace._activeViewForCurrentState();
    }
  };

  return {
    // Real classes/functions, created once per runtime instance.
    TAbstractFile,
    TFile,
    TFolder,
    Events,
    EventRef,
    Component,
    Plugin,
    Notice,
    Platform,
    Vault,
    MetadataCache,
    Workspace,
    Editor,
    MarkdownView,
    ItemView,
    WorkspaceLeaf,
    Modal,
    PluginSettingTab,
    Setting,
    normalizePath,
    requestUrl,
    // Obsidian exposes the singleton app (and so do we); private members such as
    // `vault.adapter` still throw E_UNSUPPORTED_API.
    app,
    // Test-visible records.
    __notices: notices,
    __internal: internal
  };
}

module.exports = {
  createObsidianApi,
  normalizePath,
  positionToOffset,
  offsetToPosition,
  linesOf
};
  });

  // ---- module: runtime ----
  __define('runtime', function (module, exports, require) {
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
  });

  __require('runtime');
})();
