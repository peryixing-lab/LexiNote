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

/**
 * Strict vault-relative path normalizer for LexiNote native SDK calls:
 * rejects absolute paths, backslashes, URIs/drive colons, control chars, and `.`/`..`
 * traversal segments with `E_INVALID_PATH` instead of silently collapsing them.
 */
function normalizeStrictVaultPath(input) {
  if (typeof input !== 'string' || input.length === 0) {
    throw createError(ERROR_CODES.INVALID_PATH, '路径不能为空');
  }
  if (input.startsWith('/') || input.startsWith('\\') || input.includes('\\')) {
    throw createError(ERROR_CODES.INVALID_PATH, '只允许以 / 分隔的知识库相对路径');
  }
  if (input.includes(':') || /[\u0000-\u001f\u007f]/.test(input)) {
    throw createError(ERROR_CODES.INVALID_PATH, '路径含非法字符');
  }
  const segments = input.split('/');
  for (let index = 0; index < segments.length; index += 1) {
    if (segments[index] === '.' || segments[index] === '..') {
      throw createError(ERROR_CODES.INVALID_PATH, '路径不能包含 . 或 ..');
    }
  }
  return normalizeVaultPath(input);
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
  normalizeStrictVaultPath,
  parentPath,
  baseName,
  extensionOf,
  parseJson,
  parseJsonStrict,
  toJsonText
};
