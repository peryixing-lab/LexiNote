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
