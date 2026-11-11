import { LexiProject, NoteItem, VaultItem } from '../../core/LexiModels';
import { LexiStorageService } from '../../core/LexiStorageService';
import { LexiFolderPolicy } from '../../core/LexiFolderPolicy';
import { PluginFileRef, PluginLimits } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

/**
 * One note as seen by plugins: a vault-relative logical path plus the stable note id.
 * `NoteItem.path` is deliberately absent — it may be a sandbox absolute path or an
 * external `file://` URI depending on how the vault is bound.
 */
export class LexiPathEntry {
  vaultId: string = '';
  noteId: string = '';
  projectId: string = '';
  logicalPath: string = '';
  physicalMode: string = 'private';
  title: string = '';
  updatedAt: number = 0;
  size: number = 0;
  ctime: number = 0;

  static clone(source: LexiPathEntry): LexiPathEntry {
    const copy = new LexiPathEntry();
    copy.vaultId = source.vaultId;
    copy.noteId = source.noteId;
    copy.projectId = source.projectId;
    copy.logicalPath = source.logicalPath;
    copy.physicalMode = source.physicalMode;
    copy.title = source.title;
    copy.updatedAt = source.updatedAt;
    copy.size = source.size;
    copy.ctime = source.ctime;
    return copy;
  }
}

class LexiPathCandidate {
  noteId: string = '';
  projectId: string = '';
  title: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  size: number = 0;
}

/**
 * `(vaultId, logicalPath) <-> noteId` registry (P02).
 *
 * Path policy (see docs/plugin-system/02-path-policy.md):
 *  - a logical path is `<project folder>/<cleaned title>.md`, `<cleaned title>.md` at the root;
 *  - the folder level is the project (LexiProject) name, never `NoteItem.notebook`;
 *  - collisions inside one vault are resolved deterministically by appending `-2`, `-3`, ...
 *    in `(createdAt, id)` order and compared case-insensitively;
 *  - a renamed note changes its logical path; the previous path stays resolvable as an alias
 *    so a plugin holding a stale reference gets the same note id instead of a wrong one.
 */
export class LexiPathRegistry {
  private static readonly SEP: string = '\u0001';
  private static entries: Map<string, LexiPathEntry> = new Map();
  private static byPath: Map<string, string> = new Map();
  private static aliases: Map<string, string> = new Map();
  private static vaultRevisions: Map<string, number> = new Map();
  private static refreshedAt: Map<string, number> = new Map();
  private static projectFolders: Map<string, string> = new Map();

  private static key(vaultId: string, noteId: string): string {
    return `${vaultId}${LexiPathRegistry.SEP}${noteId}`;
  }

  private static pathKey(vaultId: string, relativePath: string): string {
    return `${vaultId}${LexiPathRegistry.SEP}${relativePath.toLowerCase()}`;
  }

  /** UTF-8 byte length without allocating an encoder for every note. */
  static byteLength(text: string): number {
    let bytes = 0;
    for (let index = 0; index < text.length; index++) {
      const code = text.charCodeAt(index);
      if (code < 0x80) { bytes += 1; }
      else if (code < 0x800) { bytes += 2; }
      else if (code >= 0xD800 && code <= 0xDBFF) { bytes += 4; index++; }
      else { bytes += 3; }
    }
    return bytes;
  }

  /**
   * Strict vault-relative path validation. Rejects anything a plugin could use to escape
   * the vault: absolute paths, Windows separators, drive letters, `file://`, `..`, `.`,
   * empty segments (including duplicated `/`), control characters and over-long input.
   */
  static normalize(relativePath: string): string {
    if (typeof relativePath !== 'string') {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径必须是字符串');
    }
    const path = relativePath;
    if (path.length === 0) { throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径不能为空'); }
    if (path.length > PluginLimits.MAX_PATH_LENGTH) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径过长');
    }
    if (path.startsWith('/') || path.startsWith('\\')) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '只允许知识库相对路径');
    }
    if (path.includes('\\')) { throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径分隔符必须是 /'); }
    if (path.includes(':') || path.toLowerCase().startsWith('file:')) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '不允许 URI 或绝对路径');
    }
    if (/[\u0000-\u001f\u007f]/.test(path)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径含控制字符');
    }
    if (path.endsWith('/')) { throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径不能以 / 结尾'); }
    const parts = path.split('/');
    if (parts.length > PluginLimits.MAX_RELATIVE_DEPTH) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '目录层级过深');
    }
    for (const part of parts) {
      if (part.length === 0) { throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径含空目录段'); }
      if (part === '.' || part === '..') {
        throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '路径不能包含 . 或 ..');
      }
      if (part !== part.trim()) { throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '目录段首尾不能是空格'); }
      if (part.endsWith('.') || part.endsWith(' ')) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '目录段不能以点或空格结尾');
      }
    }
    return path;
  }

  static isValidPath(relativePath: string): boolean {
    try {
      LexiPathRegistry.normalize(relativePath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /** The inverse of `normalize`: validates and returns the parent folder, or '' at the root. */
  static folderOf(relativePath: string): string {
    const path = LexiPathRegistry.normalize(relativePath);
    const slash = path.lastIndexOf('/');
    return slash > 0 ? path.substring(0, slash) : '';
  }

  static nameOf(relativePath: string): string {
    const path = LexiPathRegistry.normalize(relativePath);
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  /** Adds `.md` when the caller passed a bare title, rejects other extensions for now. */
  static markdownPath(relativePath: string): string {
    const path = LexiPathRegistry.normalize(relativePath);
    if (!/\.md$/i.test(path)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_PATH, '首版只支持 .md 文件');
    }
    return path;
  }

  static revisionOf(vaultId: string): number {
    const revision = LexiPathRegistry.vaultRevisions.get(vaultId);
    return revision === undefined ? 0 : revision;
  }

  private static bump(vaultId: string): void {
    LexiPathRegistry.vaultRevisions.set(vaultId, LexiPathRegistry.revisionOf(vaultId) + 1);
    LexiPathRegistry.refreshedAt.set(vaultId, Date.now());
  }

  /** Guards against unbounded rescans while still catching changes from another window. */
  static async ensureFresh(vaultId: string, maxAgeMs: number = 3000): Promise<void> {
    const revision = LexiPathRegistry.revisionOf(vaultId);
    if (revision === 0) {
      await LexiPathRegistry.refresh(vaultId);
      return;
    }
    const at = LexiPathRegistry.refreshedAt.get(vaultId);
    const age = at === undefined ? Number.MAX_SAFE_INTEGER : Date.now() - at;
    if (age > maxAgeMs) {
      await LexiPathRegistry.refresh(vaultId);
    }
  }

  /** Rebuilds one vault from the authoritative storage layer. */
  static async refresh(vaultId: string): Promise<void> {
    if (!vaultId) { throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少知识库标识'); }
    const notes = await LexiStorageService.getNotes(vaultId);
    const projects = await LexiStorageService.getProjects(vaultId);
    let boundFolder = false;
    try {
      const vaults = await LexiStorageService.getVaults(true);
      const vault = vaults.find((item: VaultItem): boolean => item.id === vaultId);
      boundFolder = !!vault && !!vault.folderUri;
    } catch (error) {
      boundFolder = false;
    }
    LexiPathRegistry.applyNotes(vaultId, notes, projects, boundFolder);
  }

  /**
   * Pure rebuild used by storage-driven refresh and by regression tests.
   * Trashed and externally-missing notes are excluded from the visible registry.
   */
  static applyNotes(vaultId: string, notes: NoteItem[], projects: LexiProject[], boundFolder: boolean): void {
    for (const key of Array.from(LexiPathRegistry.entries.keys())) {
      if (key.startsWith(`${vaultId}${LexiPathRegistry.SEP}`)) { LexiPathRegistry.entries.delete(key); }
    }
    for (const key of Array.from(LexiPathRegistry.byPath.keys())) {
      if (key.startsWith(`${vaultId}${LexiPathRegistry.SEP}`)) { LexiPathRegistry.byPath.delete(key); }
    }

    const folderNames: Map<string, string> = new Map();
    const usedFolders: Map<string, string> = new Map();
    const orderedProjects = projects.slice(0).sort((a: LexiProject, b: LexiProject): number =>
      a.createdAt !== b.createdAt ? a.createdAt - b.createdAt : a.id.localeCompare(b.id));
    for (const project of orderedProjects) {
      let folder = LexiFolderPolicy.fileName(project.name || '未命名文件夹');
      let candidate = folder;
      let attempt = 2;
      while (usedFolders.has(candidate.toLowerCase()) && usedFolders.get(candidate.toLowerCase()) !== project.id) {
        candidate = `${folder}-${attempt}`;
        attempt++;
      }
      usedFolders.set(candidate.toLowerCase(), project.id);
      folderNames.set(project.id, candidate);
      LexiPathRegistry.projectFolders.set(`${vaultId}${LexiPathRegistry.SEP}${project.id}`, candidate);
    }

    const candidates: LexiPathCandidate[] = [];
    for (const note of notes) {
      if (!note || typeof note.id !== 'string' || note.id.length === 0) { continue; }
      if (note.vaultId !== vaultId) { continue; }
      if (note.trashedAt > 0 || note.sourceMissing) { continue; }
      const candidate = new LexiPathCandidate();
      candidate.noteId = note.id;
      candidate.projectId = note.projectId || '';
      candidate.title = note.title || '';
      candidate.createdAt = note.createdAt;
      candidate.updatedAt = note.updatedAt;
      candidate.size = LexiPathRegistry.byteLength(note.content || '');
      candidates.push(candidate);
    }
    candidates.sort((a: LexiPathCandidate, b: LexiPathCandidate): number =>
      a.createdAt !== b.createdAt ? a.createdAt - b.createdAt : a.noteId.localeCompare(b.noteId));

    const used: Map<string, string> = new Map();
    for (const candidate of candidates) {
      const folder = folderNames.get(candidate.projectId);
      const stem = LexiFolderPolicy.fileName(candidate.title || '未命名笔记');
      let path = folder ? `${folder}/${stem}.md` : `${stem}.md`;
      let attempt = 2;
      while (used.has(path.toLowerCase()) && used.get(path.toLowerCase()) !== candidate.noteId) {
        path = folder ? `${folder}/${stem}-${attempt}.md` : `${stem}-${attempt}.md`;
        attempt++;
      }
      used.set(path.toLowerCase(), candidate.noteId);

      const entry = new LexiPathEntry();
      entry.vaultId = vaultId;
      entry.noteId = candidate.noteId;
      entry.projectId = candidate.projectId;
      entry.logicalPath = path;
      entry.physicalMode = boundFolder ? 'bound-folder' : 'private';
      entry.title = candidate.title;
      entry.updatedAt = candidate.updatedAt;
      entry.size = candidate.size;
      entry.ctime = candidate.createdAt;
      LexiPathRegistry.entries.set(LexiPathRegistry.key(vaultId, candidate.noteId), entry);
      LexiPathRegistry.byPath.set(LexiPathRegistry.pathKey(vaultId, path), candidate.noteId);
      LexiPathRegistry.aliases.delete(LexiPathRegistry.pathKey(vaultId, path));
    }
    LexiPathRegistry.bump(vaultId);
  }

  static entry(vaultId: string, noteId: string): LexiPathEntry | undefined {
    return LexiPathRegistry.entries.get(LexiPathRegistry.key(vaultId, noteId));
  }

  static entriesForVault(vaultId: string): LexiPathEntry[] {
    const result: LexiPathEntry[] = [];
    for (const entry of LexiPathRegistry.entries.values()) {
      if (entry.vaultId === vaultId) { result.push(entry); }
    }
    result.sort((a: LexiPathEntry, b: LexiPathEntry): number => a.logicalPath.localeCompare(b.logicalPath));
    return result;
  }

  /** Resolves a vault-relative path (current or a remembered alias) to a note id. */
  static noteIdForPath(vaultId: string, relativePath: string): string {
    const normalized = LexiPathRegistry.normalize(relativePath);
    const direct = LexiPathRegistry.byPath.get(LexiPathRegistry.pathKey(vaultId, normalized));
    if (direct !== undefined) { return direct; }
    const alias = LexiPathRegistry.aliases.get(LexiPathRegistry.pathKey(vaultId, normalized));
    return alias === undefined ? '' : alias;
  }

  /**
   * Registers a note that was just created through the vault adapter.
   * `preferredPath` is the path the caller asked for; it is used only when it is still free.
   */
  static rememberCreated(vaultId: string, note: NoteItem, boundFolder: boolean,
    preferredPath: string = ''): LexiPathEntry {
    const previous = LexiPathRegistry.entry(vaultId, note.id);
    const entry = new LexiPathEntry();
    entry.vaultId = vaultId;
    entry.noteId = note.id;
    entry.projectId = note.projectId || '';
    entry.physicalMode = boundFolder ? 'bound-folder' : 'private';
    entry.title = note.title || '';
    entry.updatedAt = note.updatedAt;
    entry.size = LexiPathRegistry.byteLength(note.content || '');
    entry.ctime = note.createdAt;
    let path = previous ? previous.logicalPath : '';
    if (!path && preferredPath) {
      const owner = LexiPathRegistry.byPath.get(LexiPathRegistry.pathKey(vaultId, preferredPath));
      if (owner === undefined || owner === note.id) { path = preferredPath; }
    }
    if (!path) {
      const folder = LexiPathRegistry.folderNameForProject(vaultId, entry.projectId);
      const stem = LexiFolderPolicy.fileName(note.title || '未命名笔记');
      path = LexiPathRegistry.uniquePath(vaultId, folder, stem, note.id);
    }
    entry.logicalPath = path;
    if (previous && previous.logicalPath !== path) {
      LexiPathRegistry.rememberAlias(vaultId, previous.logicalPath, note.id);
    }
    LexiPathRegistry.entries.set(LexiPathRegistry.key(vaultId, note.id), entry);
    LexiPathRegistry.byPath.set(LexiPathRegistry.pathKey(vaultId, path), note.id);
    LexiPathRegistry.bump(vaultId);
    return entry;
  }

  /** Applies a title/content change, keeping the previous path as an alias on rename. */
  static applySaved(vaultId: string, note: NoteItem, nextTitle: string): LexiPathEntry {
    const previous = LexiPathRegistry.entry(vaultId, note.id);
    if (!previous) { return LexiPathRegistry.rememberCreated(vaultId, note, false); }
    const entry = LexiPathEntry.clone(previous);
    entry.title = nextTitle;
    entry.updatedAt = note.updatedAt;
    entry.size = LexiPathRegistry.byteLength(note.content || '');
    const folder = LexiPathRegistry.folderNameForProject(vaultId, entry.projectId);
    const stem = LexiFolderPolicy.fileName(nextTitle || '未命名笔记');
    let path = previous.logicalPath;
    const currentStem = LexiPathRegistry.nameOf(previous.logicalPath);
    if (`${stem}.md` !== currentStem) {
      path = LexiPathRegistry.uniquePath(vaultId, folder, stem, note.id);
      LexiPathRegistry.rememberAlias(vaultId, previous.logicalPath, note.id);
      LexiPathRegistry.byPath.delete(LexiPathRegistry.pathKey(vaultId, previous.logicalPath));
    }
    entry.logicalPath = path;
    LexiPathRegistry.entries.set(LexiPathRegistry.key(vaultId, note.id), entry);
    LexiPathRegistry.byPath.set(LexiPathRegistry.pathKey(vaultId, path), note.id);
    LexiPathRegistry.bump(vaultId);
    return entry;
  }

  static forget(vaultId: string, noteId: string): void {
    const entry = LexiPathRegistry.entry(vaultId, noteId);
    if (entry) {
      LexiPathRegistry.byPath.delete(LexiPathRegistry.pathKey(vaultId, entry.logicalPath));
    }
    LexiPathRegistry.entries.delete(LexiPathRegistry.key(vaultId, noteId));
    LexiPathRegistry.bump(vaultId);
  }

  static rememberAlias(vaultId: string, oldPath: string, noteId: string): void {
    if (!oldPath) { return; }
    LexiPathRegistry.aliases.set(LexiPathRegistry.pathKey(vaultId, oldPath), noteId);
  }

  static fileRef(entry: LexiPathEntry): PluginFileRef {
    return PluginFileRef.of(entry.noteId, entry.vaultId, entry.logicalPath, entry.projectId,
      entry.ctime, entry.updatedAt, entry.size);
  }

  private static folderNameForProject(vaultId: string, projectId: string): string {
    if (!projectId) { return ''; }
    const known = LexiPathRegistry.projectFolders.get(`${vaultId}${LexiPathRegistry.SEP}${projectId}`);
    if (known !== undefined) { return known; }
    for (const entry of LexiPathRegistry.entries.values()) {
      if (entry.vaultId === vaultId && entry.projectId === projectId) {
        const slash = entry.logicalPath.indexOf('/');
        if (slash > 0) { return entry.logicalPath.substring(0, slash); }
      }
    }
    return '';
  }

  private static uniquePath(vaultId: string, folder: string, stem: string, noteId: string): string {
    let path = folder ? `${folder}/${stem}.md` : `${stem}.md`;
    let attempt = 2;
    while (true) {
      const owner = LexiPathRegistry.byPath.get(LexiPathRegistry.pathKey(vaultId, path));
      if (owner === undefined || owner === noteId) { return path; }
      path = folder ? `${folder}/${stem}-${attempt}.md` : `${stem}-${attempt}.md`;
      attempt++;
    }
  }

  static reset(): void {
    LexiPathRegistry.entries = new Map<string, LexiPathEntry>();
    LexiPathRegistry.byPath = new Map<string, string>();
    LexiPathRegistry.aliases = new Map<string, string>();
    LexiPathRegistry.vaultRevisions = new Map<string, number>();
    LexiPathRegistry.refreshedAt = new Map<string, number>();
    LexiPathRegistry.projectFolders = new Map<string, string>();
  }
}
