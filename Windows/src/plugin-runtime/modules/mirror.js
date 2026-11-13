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
