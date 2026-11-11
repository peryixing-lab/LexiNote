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
