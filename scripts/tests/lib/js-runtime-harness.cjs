'use strict';

/**
 * Test harness for the JavaScript plugin runtime.
 *
 * It creates a `window`-like environment, installs a synchronous fake
 * `lexiPluginBridge`, records every RPC, and can either answer automatically with a
 * simulated host (default) or hand control to the test (`host.autoRespond = false`).
 *
 * `createRuntime()` prefers the source modules over the generated bundle so a stale
 * `runtime.bundle.js` can never hide a bug. Pass `{ mode: 'built' }` to exercise the
 * bundle that actually ships in rawfile.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { installDom, removeDom } = require('./fake-dom.cjs');

const ROOT = path.resolve(__dirname, '../../..');
const SRC_DIR = path.join(ROOT, 'packages/plugin-runtime-js/src');
const BUNDLE_PATH = path.join(ROOT, 'entry/src/main/resources/rawfile/plugin-runtime/runtime.bundle.js');

const MODULE_IDS = ['util', 'mirror', 'bridge', 'loader', 'sdk', 'ui', 'obsidian', 'runtime'];

const METHOD_TABLE = {
  'plugin.ping': {},
  'vault.listMarkdown': { vaultId: 'string' },
  'vault.getByPath': { vaultId: 'string', path: 'string' },
  'vault.getById': { vaultId: 'string', fileId: 'string' },
  'vault.readText': { vaultId: 'string', fileId: 'string' },
  'vault.createText': { vaultId: 'string', path: 'string', content: 'string' },
  'vault.writeText': { vaultId: 'string', fileId: 'string', content: 'string', expectedUpdatedAt: 'number' },
  'vault.renameText': { vaultId: 'string', fileId: 'string', newPath: 'string' },
  'vault.deleteText': { vaultId: 'string', fileId: 'string' },
  'metadata.get': { vaultId: 'string', fileId: 'string' },
  'workspace.activeFile': {},
  'workspace.openFile': { vaultId: 'string', fileId: 'string' },
  'workspace.snapshot': {},
  'editor.active': {},
  'editor.replaceSelection': { text: 'string' },
  'editor.replaceAll': { text: 'string', expectedVersion: 'number' },
  'commands.register': { id: 'string', title: 'string' },
  'commands.unregister': { id: 'string' },
  'events.on': { event: 'string' },
  'events.off': { subscriptionId: 'number' },
  'ui.notice': { message: 'string' },
  'ui.confirm': { title: 'string', body: 'string' },
  'storage.get': { key: 'string' },
  'storage.set': { key: 'string', value: 'string' },
  'storage.remove': { key: 'string' },
  'ai.status': {},
  'ai.chat': { messages: 'array', tools: 'array' },
  'ai.configure': {},
  'ai.models': {},
  'ai.balance': {},
  'views.register': { id: 'string', title: 'string' },
  'views.unregister': { id: 'string' },
  'views.open': { id: 'string' }
};

const DEFAULT_CAPABILITIES = [
  'vault.read',
  'vault.write',
  'notes.metadata.read',
  'workspace.views',
  'editor.read',
  'editor.write',
  'ui.notice',
  'ui.modal',
  'ui.commands',
  'plugin.storage',
  'ai.inference',
  'ui.views'
];

const createdRuntimes = [];

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function basenameOf(vaultPath) {
  const normalized = String(vaultPath === undefined || vaultPath === null ? '' : vaultPath).replace(/\\/g, '/');
  const slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.slice(slash + 1);
}

function extensionOf(name) {
  const dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.slice(dot + 1).toLowerCase();
}

function normalizePath(value) {
  const normalized = String(value === undefined || value === null ? '' : value).replace(/\\/g, '/');
  const parts = [];
  const segments = normalized.split('/');
  for (let index = 0; index < segments.length; index += 1) {
    if (!segments[index] || segments[index] === '.') {
      continue;
    }
    if (segments[index] === '..') {
      parts.pop();
      continue;
    }
    parts.push(segments[index]);
  }
  return parts.join('/');
}

/** Builds a valid FileRef with deterministic timestamps. */
function makeFile(id, vaultPath, extra) {
  const pathValue = normalizePath(vaultPath);
  const name = basenameOf(pathValue);
  return Object.assign({
    id,
    vaultId: 'vault-1',
    projectId: '',
    path: pathValue,
    name,
    extension: extensionOf(name),
    kind: 'file',
    size: 0,
    ctime: 1000,
    mtime: 1000
  }, extra || {});
}

function normalizeRef(raw, vaultId) {
  const pathValue = normalizePath(raw.path);
  const name = typeof raw.name === 'string' && raw.name.length > 0 ? raw.name : basenameOf(pathValue);
  return {
    id: typeof raw.id === 'string' ? raw.id : `file-${Math.random().toString(36).slice(2)}`,
    vaultId: typeof raw.vaultId === 'string' ? raw.vaultId : vaultId,
    projectId: typeof raw.projectId === 'string' ? raw.projectId : '',
    path: pathValue,
    name,
    extension: typeof raw.extension === 'string' && raw.extension.length > 0 ? raw.extension : extensionOf(name),
    kind: typeof raw.kind === 'string' ? raw.kind : 'file',
    size: typeof raw.size === 'number' ? raw.size : 0,
    ctime: typeof raw.ctime === 'number' ? raw.ctime : 1000,
    mtime: typeof raw.mtime === 'number' ? raw.mtime : 1000
  };
}

function createFakeHost(options) {
  const config = options || {};
  const runtime = config.runtime;
  const state = {
    pluginId: '',
    token: '',
    vaultId: '',
    files: [],
    contents: new Map(),
    metadata: new Map(),
    storage: new Map(),
    editor: null,
    editorSelection: { from: 0, to: 0 },
    editorRevision: 0,
    activeFileId: '',
    nextFileId: 0,
    nextSubscriptionId: 0,
    commands: new Map(),
    subscriptions: new Map(),
    notices: [],
    confirmResult: true,
    aiConfig: { provider: 'openai-compatible', baseUrl: 'https://example.test', model: 'fake-model' },
    aiReplies: [],
    aiCalls: [],
    views: new Map(),
    openedViews: [],
    strictWrite: true,
    clock: 1000,
    seq: 0
  };

  const host = {
    state,
    calls: [],
    rawCalls: [],
    logs: [],
    pending: [],
    invalid: [],
    autoRespond: config.autoRespond !== false,
    responder: typeof config.responder === 'function' ? config.responder : null,
    strictPluginId: config.strictPluginId !== false,
    strictToken: config.strictToken !== false
  };

  function tick() {
    state.clock += 1;
    return state.clock;
  }

  function findById(id) {
    for (let index = 0; index < state.files.length; index += 1) {
      if (state.files[index].id === id) {
        return state.files[index];
      }
    }
    return null;
  }

  function findByPath(vaultPath) {
    const target = normalizePath(vaultPath);
    for (let index = 0; index < state.files.length; index += 1) {
      if (state.files[index].path === target) {
        return state.files[index];
      }
    }
    return null;
  }

  function setBoot(payload) {
    state.pluginId = payload.pluginId;
    state.token = payload.token || '';
    state.vaultId = payload.vaultId || '';
    state.files = [];
    state.contents = new Map();
    state.metadata = new Map();
    state.storage = new Map();
    state.commands = new Map();
    state.subscriptions = new Map();
    state.notices = [];
    state.pending = [];
    state.editorSelection = { from: 0, to: 0 };
    state.clock = 1000;

    let files = [];
    try {
      files = JSON.parse(payload.filesJson || '[]');
    } catch (error) {
      files = [];
    }
    state.files = Array.isArray(files) ? files.map((file) => normalizeRef(file, state.vaultId)) : [];

    let active = null;
    try {
      active = JSON.parse(payload.activeFileJson || 'null');
    } catch (error) {
      active = null;
    }
    state.activeFileId = active && typeof active.id === 'string' ? active.id : '';

    let editor = null;
    try {
      editor = JSON.parse(payload.editorJson || 'null');
    } catch (error) {
      editor = null;
    }
    if (editor && typeof editor === 'object') {
      state.editor = {
        editorId: typeof editor.editorId === 'string' ? editor.editorId : 'editor-1',
        noteId: typeof editor.noteId === 'string' ? editor.noteId : state.activeFileId,
        vaultId: typeof editor.vaultId === 'string' ? editor.vaultId : state.vaultId,
        windowId: typeof editor.windowId === 'string' ? editor.windowId : 'window-1',
        revision: typeof editor.revision === 'number' ? editor.revision : 0,
        baseContent: typeof editor.baseContent === 'string' ? editor.baseContent : '',
        content: typeof editor.content === 'string' ? editor.content : '',
        dirty: editor.dirty === true,
        readOnly: editor.readOnly === true,
        focused: editor.focused === true
      };
      state.editorRevision = state.editor.revision;
    } else {
      state.editor = null;
      state.editorRevision = 0;
    }

    let data = {};
    try {
      data = JSON.parse(payload.dataJson || '{}');
    } catch (error) {
      data = {};
    }
    if (data && typeof data === 'object') {
      Object.keys(data).forEach((key) => {
        const value = data[key];
        state.storage.set(key, typeof value === 'string' ? value : JSON.stringify(value));
      });
    }

    if (config.contents && typeof config.contents === 'object') {
      Object.keys(config.contents).forEach((key) => {
        const file = findById(key) || findByPath(key);
        if (file) {
          state.contents.set(file.id, String(config.contents[key]));
          file.size = Buffer.byteLength(String(config.contents[key]), 'utf8');
        }
      });
    }
    return state;
  }

  function metadataFor(ref) {
    if (state.metadata.has(ref.id)) {
      return state.metadata.get(ref.id);
    }
    const content = state.contents.has(ref.id) ? state.contents.get(ref.id) : '';
    const headings = [];
    const links = [];
    const tags = [];
    const lines = content.split(/\r\n|\r|\n/);
    let offset = 0;
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const heading = /^(#{1,6})\s+(.*)$/.exec(line);
      if (heading) {
        headings.push({ heading: heading[2].trim(), level: heading[1].length, line: index, offset });
      }
      const linkPattern = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g;
      let match = linkPattern.exec(line);
      while (match) {
        links.push({
          link: match[1],
          original: match[0],
          displayText: match[2] || match[1],
          line: index
        });
        match = linkPattern.exec(line);
      }
      const tagPattern = /(?:^|\s)#([\w\u4e00-\u9fa5/-]+)/g;
      let tagMatch = tagPattern.exec(line);
      while (tagMatch) {
        if (tags.indexOf(tagMatch[1]) < 0) {
          tags.push(tagMatch[1]);
        }
        tagMatch = tagPattern.exec(line);
      }
      offset += line.length + 1;
    }
    const snapshot = {
      fileId: ref.id,
      path: ref.path,
      version: 1,
      mtime: ref.mtime,
      hash: `hash-${ref.id}`,
      headings,
      links,
      embeds: [],
      tags,
      frontmatter: '',
      properties: {},
      supportedFields: ['headings', 'links', 'tags', 'frontmatter', 'properties'],
      unsupportedFields: ['sections', 'blocks', 'listItems']
    };
    state.metadata.set(ref.id, snapshot);
    return snapshot;
  }

  function defaultOutcome(request) {
    const params = request.params || {};
    switch (request.method) {
      case 'plugin.ping':
        return { result: { ok: true, pluginId: state.pluginId } };
      case 'vault.listMarkdown': {
        const list = state.files.filter((file) => file.extension === 'md' || file.extension === 'markdown');
        return { result: clone(list) };
      }
      case 'vault.getByPath':
        return { result: findByPath(params.path) ? clone(findByPath(params.path)) : null };
      case 'vault.getById':
        return { result: findById(params.fileId) ? clone(findById(params.fileId)) : null };
      case 'vault.readText': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        return { result: state.contents.has(file.id) ? state.contents.get(file.id) : '' };
      }
      case 'vault.createText': {
        const desired = normalizePath(params.path);
        if (findByPath(desired)) {
          return { error: { code: 'E_PATH_EXISTS', message: `文件已存在 ${desired}` } };
        }
        state.nextFileId += 1;
        const content = typeof params.content === 'string' ? params.content : '';
        const ref = normalizeRef({
          id: `file-${state.nextFileId}`,
          vaultId: params.vaultId || state.vaultId,
          path: desired,
          size: Buffer.byteLength(content, 'utf8'),
          ctime: tick(),
          mtime: state.clock
        }, state.vaultId);
        state.files.push(ref);
        state.contents.set(ref.id, content);
        return { result: clone(ref) };
      }
      case 'vault.writeText': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        if (state.strictWrite && typeof params.expectedUpdatedAt === 'number' &&
          params.expectedUpdatedAt !== 0 && params.expectedUpdatedAt !== file.mtime) {
          return {
            error: {
              code: 'E_CONFLICT',
              message: `文件在读取后被修改（${params.expectedUpdatedAt} != ${file.mtime}）`
            }
          };
        }
        const content = typeof params.content === 'string' ? params.content : '';
        file.mtime = tick();
        file.size = Buffer.byteLength(content, 'utf8');
        state.contents.set(file.id, content);
        state.metadata.delete(file.id);
        return { result: clone(file) };
      }
      case 'vault.renameText': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        const desired = normalizePath(params.newPath);
        const existing = findByPath(desired);
        if (existing && existing.id !== file.id) {
          return { error: { code: 'E_PATH_EXISTS', message: `目标路径已存在 ${desired}` } };
        }
        file.path = desired;
        file.name = basenameOf(desired);
        file.extension = extensionOf(file.name);
        file.mtime = tick();
        return { result: clone(file) };
      }
      case 'vault.deleteText': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        state.files = state.files.filter((item) => item.id !== file.id);
        state.contents.delete(file.id);
        state.metadata.delete(file.id);
        if (state.activeFileId === file.id) {
          state.activeFileId = '';
        }
        return { result: null };
      }
      case 'metadata.get': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        return { result: metadataFor(file) };
      }
      case 'workspace.activeFile': {
        const file = state.activeFileId ? findById(state.activeFileId) : null;
        return { result: file ? clone(file) : null };
      }
      case 'workspace.openFile': {
        const file = findById(params.fileId);
        if (!file) {
          return { error: { code: 'E_NOT_FOUND', message: `文件不存在 ${params.fileId}` } };
        }
        state.activeFileId = file.id;
        return { result: null };
      }
      case 'workspace.snapshot':
        return {
          result: {
            windowId: 'window-1',
            vaultId: state.vaultId,
            activeFileId: state.activeFileId,
            activeEditorId: state.editor ? state.editor.editorId : '',
            openFileIds: state.activeFileId ? [state.activeFileId] : [],
            revision: state.editorRevision
          }
        };
      case 'editor.active':
        return { result: state.editor ? clone(state.editor) : null };
      case 'editor.replaceSelection': {
        if (!state.editor) {
          return { error: { code: 'E_UNSUPPORTED_API', message: '当前没有活动编辑器' } };
        }
        const text = typeof params.text === 'string' ? params.text : '';
        const content = state.editor.content;
        const from = Math.max(0, Math.min(state.editorSelection.from, content.length));
        const to = Math.max(from, Math.min(state.editorSelection.to, content.length));
        const next = content.slice(0, from) + text + content.slice(to);
        state.editor.content = next;
        state.editorRevision += 1;
        state.editor.revision = state.editorRevision;
        state.editorSelection = { from: from + text.length, to: from + text.length };
        return { result: { content: next, version: state.editorRevision } };
      }
      case 'editor.replaceAll': {
        if (!state.editor) {
          return { error: { code: 'E_UNSUPPORTED_API', message: '当前没有活动编辑器' } };
        }
        if (typeof params.expectedVersion === 'number' && params.expectedVersion !== state.editorRevision) {
          return {
            error: {
              code: 'E_EDITOR_CONFLICT',
              message: `编辑器版本不匹配（${params.expectedVersion} != ${state.editorRevision}）`
            }
          };
        }
        const text = typeof params.text === 'string' ? params.text : '';
        state.editor.content = text;
        state.editorRevision += 1;
        state.editor.revision = state.editorRevision;
        return { result: { content: text, version: state.editorRevision } };
      }
      case 'commands.register':
        state.commands.set(params.id, params.title);
        return { result: { id: params.id } };
      case 'commands.unregister':
        state.commands.delete(params.id);
        return { result: null };
      case 'events.on': {
        state.nextSubscriptionId += 1;
        state.subscriptions.set(state.nextSubscriptionId, params.event);
        return { result: { subscriptionId: state.nextSubscriptionId } };
      }
      case 'events.off':
        state.subscriptions.delete(params.subscriptionId);
        return { result: null };
      case 'ui.notice':
        state.notices.push({ message: params.message, timeoutMs: params.timeoutMs });
        return { result: null };
      case 'ui.confirm':
        return { result: state.confirmResult === true };
      case 'storage.get':
        return { result: state.storage.has(params.key) ? state.storage.get(params.key) : '' };
      case 'storage.set':
        state.storage.set(params.key, typeof params.value === 'string' ? params.value : String(params.value));
        return { result: null };
      case 'storage.remove':
        state.storage.delete(params.key);
        return { result: null };
      case 'ai.status':
        return {
          result: {
            configured: true,
            provider: state.aiConfig.provider,
            model: state.aiConfig.model,
            baseUrl: state.aiConfig.baseUrl,
            maxTokens: 8192,
            temperature: 0.3
          }
        };
      case 'ai.chat': {
        state.aiCalls.push(clone(params));
        const next = state.aiReplies.length > 0
          ? state.aiReplies.shift()
          : { text: 'ok', reasoning: '', toolCalls: [], finishReason: 'stop', model: 'fake-model',
            usage: { inputTokens: 1, outputTokens: 1 } };
        if (next && next.error) { return { error: next.error }; }
        return { result: clone(next) };
      }
      case 'ai.models':
        return { result: ['fake-model', 'fake-reasoner'] };
      case 'ai.balance':
        return { result: { supported: true, provider: 'DeepSeek', updatedAt: Date.now(),
          windows: [{ label: '账户余额', unit: 'CNY', remainingValue: 12.34 }] } };
      case 'ai.configure':
        state.aiConfig = Object.assign({}, state.aiConfig, params);
        return {
          result: {
            configured: true,
            provider: state.aiConfig.provider,
            model: state.aiConfig.model,
            baseUrl: state.aiConfig.baseUrl,
            maxTokens: 8192,
            temperature: 0.3
          }
        };
      case 'views.register':
        state.views.set(params.id, { id: params.id, title: params.title });
        return { result: { id: params.id, title: params.title } };
      case 'views.unregister':
        state.views.delete(params.id);
        return { result: null };
      case 'views.open':
        state.openedViews.push(params.id);
        return { result: null };
      default:
        return {
          error: {
            code: 'E_UNSUPPORTED_API',
            message: `宿主未实现 ${request.method}`
          }
        };
    }
  }

  function sendResponse(id, outcome) {
    if (!runtime || typeof runtime.receiveResponse !== 'function') {
      return false;
    }
    const message = {
      protocol: 1,
      id,
      ok: !(outcome && outcome.error),
      result: JSON.stringify(outcome && Object.prototype.hasOwnProperty.call(outcome, 'result') ? outcome.result : null),
      error: outcome && outcome.error
        ? { code: outcome.error.code, message: outcome.error.message, details: outcome.error.details || '' }
        : { code: '', message: '', details: '' }
    };
    return runtime.receiveResponse(JSON.stringify(message));
  }

  function validateRequest(request) {
    if (!request || typeof request !== 'object') {
      return '请求不是对象';
    }
    if (request.protocol !== 1) {
      return `协议版本错误 ${String(request.protocol)}`;
    }
    if (typeof request.id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(request.id)) {
      return '请求 id 非法';
    }
    if (!Object.prototype.hasOwnProperty.call(METHOD_TABLE, request.method)) {
      return `未知方法 ${String(request.method)}`;
    }
    if (host.strictPluginId && request.pluginId !== state.pluginId) {
      return `插件 id 不匹配 ${String(request.pluginId)}`;
    }
    if (host.strictToken && request.token !== state.token) {
      return 'token 不匹配';
    }
    if (request.params !== undefined && (typeof request.params !== 'object' || request.params === null || Array.isArray(request.params))) {
      return 'params 必须是 JSON 文本或对象';
    }
    return null;
  }

  function request(json) {
    let parsed = null;
    try {
      parsed = JSON.parse(json);
    } catch (error) {
      host.invalid.push({ raw: json, reason: 'invalid-json' });
      return '{"ack":false}';
    }
    if (!parsed || typeof parsed !== 'object') {
      host.invalid.push({ raw: json, reason: 'not-an-object' });
      return '{"ack":false}';
    }
    const rawRequest = parsed;
    const rawParams = parsed.params;
    // The production ArkTS host parses params as JSON text; accept both an object and a
    // JSON string, then expose the decoded object to tests and default responders.
    let params = parsed.params;
    if (typeof params === 'string') {
      try {
        params = params.length === 0 ? {} : JSON.parse(params);
      } catch (error) {
        host.invalid.push({ raw: json, reason: 'invalid-params' });
        sendResponse(parsed.id, { error: { code: 'E_PROTOCOL', message: 'params 不是合法 JSON' } });
        return '{"ack":false}';
      }
    }
    if (params === undefined || params === null) {
      params = {};
    }
    parsed = Object.assign({}, parsed, { params });
    const failure = validateRequest(parsed);
    if (failure) {
      host.invalid.push({ raw: json, reason: failure });
      sendResponse(parsed.id, { error: { code: 'E_PROTOCOL', message: failure } });
      return '{"ack":false}';
    }
    host.calls.push({
      method: parsed.method,
      params,
      request: parsed
    });
    host.rawCalls.push({
      method: rawRequest.method,
      params: rawParams,
      request: rawRequest
    });
    if (!host.autoRespond) {
      host.pending.push(parsed);
      return '{"ack":true}';
    }
    let outcome = null;
    try {
      outcome = host.responder ? host.responder(parsed, defaultOutcome) : null;
    } catch (error) {
      outcome = { error: { code: 'E_IO', message: error.message } };
    }
    if (outcome && outcome.manual === true) {
      host.pending.push(parsed);
      return '{"ack":true}';
    }
    if (!outcome) {
      outcome = defaultOutcome(parsed);
    }
    sendResponse(parsed.id, outcome);
    return '{"ack":true}';
  }

  const bridge = {
    request,
    log(level, message) {
      host.logs.push({ level, message });
    }
  };

  host.bridge = bridge;
  host.requests = host.calls;
  host.setBoot = setBoot;
  host.respond = function respond(idOrRequest, result, error) {
    const id = typeof idOrRequest === 'string' ? idOrRequest : (idOrRequest && idOrRequest.id);
    return sendResponse(id, error ? { error } : { result });
  };
  host.respondTo = function respondTo(index, result, error) {
    const pending = host.pending[index];
    if (!pending) {
      throw new Error(`no pending request at index ${index}`);
    }
    host.pending.splice(index, 1);
    return sendResponse(pending.id, error ? { error } : { result });
  };
  host.sendResponse = function sendResponseObject(message) {
    return runtime.receiveResponse(typeof message === 'string' ? message : JSON.stringify(message));
  };
  host.emit = function emit(event, payload, seq) {
    state.seq += 1;
    return runtime.receiveEvent(JSON.stringify({
      protocol: 1,
      type: 'event',
      pluginId: state.pluginId,
      event,
      seq: typeof seq === 'number' ? seq : state.seq,
      payload: JSON.stringify(payload === undefined ? {} : payload)
    }));
  };
  host.callsTo = function callsTo(method) {
    return host.calls.filter((call) => call.method === method);
  };
  host.findCall = function findCall(method) {
    return host.calls.find((call) => call.method === method) || null;
  };
  host.setEditorContent = function setEditorContent(content) {
    if (!state.editor) {
      state.editor = {
        editorId: 'editor-1',
        noteId: state.activeFileId,
        vaultId: state.vaultId,
        windowId: 'window-1',
        revision: 0,
        baseContent: '',
        content: '',
        dirty: false,
        readOnly: false,
        focused: true
      };
    }
    state.editor.content = String(content);
    state.editorRevision += 1;
    state.editor.revision = state.editorRevision;
  };
  host.setFileContent = function setFileContent(pathOrId, content) {
    const file = findById(pathOrId) || findByPath(pathOrId);
    if (!file) {
      throw new Error(`unknown test file ${pathOrId}`);
    }
    state.contents.set(file.id, String(content));
    file.size = Buffer.byteLength(String(content), 'utf8');
  };
  host.setActiveFile = function setActiveFile(pathOrId) {
    const file = findById(pathOrId) || findByPath(pathOrId);
    state.activeFileId = file ? file.id : '';
    return file;
  };

  return host;
}

function clearRuntimeModules() {
  for (let index = 0; index < MODULE_IDS.length; index += 1) {
    const file = path.join(SRC_DIR, `${MODULE_IDS[index]}.js`);
    try {
      delete require.cache[require.resolve(file)];
    } catch (error) {
      // ignore
    }
  }
  try {
    delete require.cache[require.resolve(BUNDLE_PATH)];
  } catch (error) {
    // ignore
  }
}

function loadModules() {
  clearRuntimeModules();
  const modules = {};
  for (let index = 0; index < MODULE_IDS.length; index += 1) {
    const id = MODULE_IDS[index];
    modules[id] = require(path.join(SRC_DIR, `${id}.js`));
  }
  return modules;
}

function loadBuiltRuntime() {
  clearRuntimeModules();
  if (!fs.existsSync(BUNDLE_PATH)) {
    throw new Error(`runtime bundle missing: ${path.relative(ROOT, BUNDLE_PATH)} (run node scripts/build-plugin-runtime.cjs)`);
  }
  require(BUNDLE_PATH);
  return globalThis.__lexiRuntime;
}

/**
 * Creates a fresh runtime + fake host pair.
 *
 * @param {object} [options]
 * @param {'src'|'built'} [options.mode='src']
 * @param {number} [options.requestTimeoutMs=15000]
 * @param {number} [options.maxInFlight=16]
 * @param {object} [options.contents] file id/path -> text used by the fake host
 * @param {object} [options.host] extra fake-host options
 */
function createRuntime(options) {
  const config = options || {};
  if (typeof globalThis.window === 'undefined') {
    globalThis.window = globalThis;
  }
  delete globalThis.__lexiRuntime;
  delete globalThis.lexiPluginBridge;

  const mode = config.mode === 'built' ? 'built' : 'src';
  let modules = {};
  let runtime = null;
  if (mode === 'built') {
    runtime = loadBuiltRuntime();
  } else {
    modules = loadModules();
    runtime = modules.runtime;
  }
  const host = createFakeHost({
    runtime,
    contents: config.contents,
    autoRespond: config.host ? config.host.autoRespond : undefined,
    responder: config.host ? config.host.responder : undefined
  });
  if (config.host && config.host.autoRespond === false) {
    host.autoRespond = false;
  }
  globalThis.lexiPluginBridge = host.bridge;

  const requestTimeoutMs = typeof config.requestTimeoutMs === 'number'
    ? config.requestTimeoutMs
    : 15000;

  function boot(overrides) {
    let input = overrides || {};
    if (typeof input === 'string') {
      input = JSON.parse(input);
    }
    // Wire-payload mode: the caller supplied the exact object the host would pass to
    // `window.__lexiRuntime.boot(JSON.stringify(payload))`.
    const wirePayload = input.type === 'boot' ||
      typeof input.filesJson === 'string' ||
      typeof input.manifestJson === 'string' ||
      typeof input.activeFileJson === 'string' ||
      typeof input.editorJson === 'string' ||
      typeof input.dataJson === 'string' ||
      typeof input.settingsJson === 'string';
    if (wirePayload) {
      const payload = Object.assign({
        type: 'boot',
        protocol: 1,
        pluginId: 'example.test',
        kind: 'lexinote',
        token: 'token-1',
        runtimeVersion: '1',
        capabilities: [],
        vaultId: 'vault-1',
        manifestJson: '{}',
        filesJson: '[]',
        activeFileJson: 'null',
        editorJson: 'null',
        settingsJson: 'null',
        dataJson: '{}',
        sourceCode: '',
        sourceName: 'main.js',
        warnings: []
      }, input);
      host.setBoot(payload);
      return runtime.boot(JSON.stringify(payload), {
        requestTimeoutMs,
        maxInFlight: config.maxInFlight
      });
    }
    const kind = input.kind === 'obsidian' ? 'obsidian' : 'lexinote';
    const pluginId = input.pluginId || (kind === 'obsidian' ? 'obsidian.hello' : 'example.test');
    const manifest = input.manifest || (kind === 'obsidian' ? {
      id: pluginId,
      name: 'Obsidian Test Plugin',
      version: '1.0.0',
      minAppVersion: '1.0.0',
      description: 'test',
      author: 'test',
      isDesktopOnly: false
    } : {
      format: 'lexinote-plugin',
      formatVersion: 1,
      id: pluginId,
      name: 'LexiNote Test Plugin',
      version: '1.0.0',
      apiVersion: '1.0',
      main: input.sourceName || 'main.js',
      description: 'test',
      author: 'test',
      capabilities: DEFAULT_CAPABILITIES
    });
    const files = Array.isArray(input.files) ? input.files : [];
    const payload = {
      type: 'boot',
      protocol: 1,
      pluginId,
      kind,
      token: input.token || 'token-1',
      runtimeVersion: '1',
      capabilities: Array.isArray(input.capabilities) ? input.capabilities : DEFAULT_CAPABILITIES.slice(),
      vaultId: input.vaultId || 'vault-1',
      manifestJson: JSON.stringify(manifest),
      filesJson: JSON.stringify(files),
      activeFileJson: JSON.stringify(input.activeFile === undefined ? null : input.activeFile),
      editorJson: JSON.stringify(input.editor === undefined ? null : input.editor),
      settingsJson: JSON.stringify(input.settings === undefined ? null : input.settings),
      dataJson: JSON.stringify(input.data === undefined ? {} : input.data),
      sourceCode: typeof input.sourceCode === 'string' ? input.sourceCode : '',
      sourceName: input.sourceName || 'main.js',
      warnings: Array.isArray(input.warnings) ? input.warnings : []
    };
    host.setBoot(payload);
    return runtime.boot(JSON.stringify(payload), {
      requestTimeoutMs,
      maxInFlight: config.maxInFlight
    });
  }

  const handle = {
    runtime,
    host,
    modules,
    mode,
    boot,
    requestTimeoutMs,
    get obsidian() {
      const status = runtime.__inspect ? runtime.__inspect() : null;
      return status ? status.obsidianApi : null;
    },
    get context() {
      const status = runtime.__inspect ? runtime.__inspect() : null;
      return status ? status.context : null;
    },
    async unload() {
      return runtime.unload();
    },
    /** Installs the minimal DOM used by native view rendering tests. */
    installDom() {
      return installDom();
    },
    removeDom() {
      removeDom();
    }
  };
  createdRuntimes.push(handle);
  return handle;
}

async function cleanupAll() {
  while (createdRuntimes.length > 0) {
    const handle = createdRuntimes.pop();
    try {
      if (handle.runtime && typeof handle.runtime.unload === 'function') {
        await handle.runtime.unload();
      }
    } catch (error) {
      // ignore teardown failures in cleanup
    }
  }
  delete globalThis.lexiPluginBridge;
  removeDom();
}

async function rejectsWith(promise, code) {
  let caught = null;
  try {
    await promise;
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, `expected rejection with ${code}`);
  assert.equal(caught.code, code, `expected ${code}, got ${caught.code || caught.message}`);
  return caught;
}

function createSuite(title) {
  const tests = [];
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    tests.push({ name, fn });
  }

  async function run() {
    console.log(`\n== ${title} ==`);
    for (let index = 0; index < tests.length; index += 1) {
      const item = tests[index];
      try {
        await item.fn();
        passed += 1;
        console.log(`PASS ${item.name}`);
      } catch (error) {
        failed += 1;
        console.error(`FAIL ${item.name}`);
        console.error(error && error.stack ? error.stack : String(error));
      }
    }
    await cleanupAll();
    console.log(`\n${passed} passed, ${failed} failed, ${tests.length} total`);
    return { passed, failed, total: tests.length };
  }

  return { test, run };
}

module.exports = {
  ROOT,
  SRC_DIR,
  BUNDLE_PATH,
  METHOD_TABLE,
  DEFAULT_CAPABILITIES,
  createRuntime,
  createFakeHost,
  createSuite,
  cleanupAll,
  rejectsWith,
  makeFile,
  normalizePath,
  loadModules,
  loadBuiltRuntime
};
