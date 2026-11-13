import type { LexiProject, NoteItem } from '../../shared/types';
import {
  PluginErrorCode,
  type PluginFileRef,
  PluginLimits,
  raisePluginError
} from '../../shared/pluginTypes';

export interface LexiPathEntry {
  vaultId: string;
  noteId: string;
  projectId: string;
  logicalPath: string;
  title: string;
  updatedAt: number;
  ctime: number;
  size: number;
}

export function cleanFileSegment(raw: string, fallback = '未命名'): string {
  const cleaned = raw
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/[\\/:*?"<>|]/g, '-')
    .trim()
    .replace(/[. ]+$/, '');
  return cleaned.length > 0 ? cleaned : fallback;
}

export function utf8ByteLength(text: string): number {
  if (!text) { return 0; }
  if (typeof TextEncoder === 'function') {
    return new TextEncoder().encode(text).length;
  }
  return text.length;
}

export function normalizeVaultRelativePath(relativePath: string): string {
  if (typeof relativePath !== 'string') {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径必须是字符串');
  }
  const value = relativePath;
  if (!value) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径不能为空');
  }
  if (value.length > PluginLimits.MAX_PATH_LENGTH) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径过长');
  }
  if (value.startsWith('/') || value.startsWith('\\')) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '只允许知识库相对路径');
  }
  if (value.includes('\\')) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径分隔符必须是 /');
  }
  if (value.includes(':') || value.toLowerCase().startsWith('file:')) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '不允许 URI 或绝对路径');
  }
  if (/[\u0000-\u001f\u007f]/.test(value)) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径含控制字符');
  }
  if (value.endsWith('/')) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '路径不能以 / 结尾');
  }
  const parts = value.split('/');
  if (parts.length > PluginLimits.MAX_RELATIVE_DEPTH) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '目录层级过深');
  }
  for (const part of parts) {
    if (!part) {
      raisePluginError(PluginErrorCode.INVALID_PATH, '路径含空目录段');
    }
    if (part === '.' || part === '..') {
      raisePluginError(PluginErrorCode.INVALID_PATH, '路径不能包含 . 或 ..');
    }
    if (part !== part.trim()) {
      raisePluginError(PluginErrorCode.INVALID_PATH, '目录段首尾不能是空格');
    }
    if (part.endsWith('.') || part.endsWith(' ')) {
      raisePluginError(PluginErrorCode.INVALID_PATH, '目录段不能以点或空格结尾');
    }
  }
  return value;
}

export function normalizeMarkdownPath(relativePath: string): string {
  const path = normalizeVaultRelativePath(relativePath);
  if (!/\.md$/i.test(path)) {
    raisePluginError(PluginErrorCode.INVALID_PATH, '首版只支持 .md 文件');
  }
  return path;
}

export function folderOfRelativePath(relativePath: string): string {
  const path = normalizeVaultRelativePath(relativePath);
  const slash = path.lastIndexOf('/');
  return slash > 0 ? path.slice(0, slash) : '';
}

export function nameOfRelativePath(relativePath: string): string {
  const path = normalizeVaultRelativePath(relativePath);
  const slash = path.lastIndexOf('/');
  return slash >= 0 ? path.slice(slash + 1) : path;
}

export class LexiPathRegistry {
  private readonly entriesByVault = new Map<string, Map<string, LexiPathEntry>>();
  private readonly noteIdByPath = new Map<string, Map<string, string>>();
  private readonly aliasesByPath = new Map<string, Map<string, string>>();
  private readonly revisions = new Map<string, number>();

  revisionOf(vaultId: string): number {
    return this.revisions.get(vaultId) ?? 0;
  }

  private bump(vaultId: string): void {
    this.revisions.set(vaultId, this.revisionOf(vaultId) + 1);
  }

  rebuild(vaultId: string, projects: LexiProject[], notes: NoteItem[]): LexiPathEntry[] {
    const projectFolderById = new Map<string, string>();
    for (const proj of projects) {
      if (proj.vaultId !== vaultId) { continue; }
      projectFolderById.set(proj.id, cleanFileSegment(proj.name || '未分组', '未分组'));
    }

    const activeNotes = notes
      .filter((note) => note.vaultId === vaultId && !note.trashedAt)
      .slice()
      .sort((a, b) => (a.createdAt - b.createdAt) || a.id.localeCompare(b.id));

    const entryMap = new Map<string, LexiPathEntry>();
    const pathMap = new Map<string, string>();
    const usedLowerPaths = new Set<string>();
    const list: LexiPathEntry[] = [];

    for (const note of activeNotes) {
      const folder = note.projectId ? projectFolderById.get(note.projectId) ?? '' : '';
      const rawTitle = (note.title || '').replace(/\.md$/i, '').trim() || '未命名';
      const baseTitle = cleanFileSegment(rawTitle, '未命名');
      const prefix = folder ? `${folder}/` : '';

      let candidate = `${prefix}${baseTitle}.md`;
      let suffix = 2;
      while (usedLowerPaths.has(candidate.toLowerCase())) {
        candidate = `${prefix}${baseTitle}-${suffix}.md`;
        suffix += 1;
      }
      usedLowerPaths.add(candidate.toLowerCase());

      const entry: LexiPathEntry = {
        vaultId,
        noteId: note.id,
        projectId: note.projectId || '',
        logicalPath: candidate,
        title: note.title || baseTitle,
        updatedAt: note.updatedAt,
        ctime: note.createdAt,
        size: utf8ByteLength(note.content || '')
      };
      entryMap.set(note.id, entry);
      pathMap.set(candidate.toLowerCase(), note.id);
      list.push(entry);
    }

    const previous = this.entriesByVault.get(vaultId);
    let aliasMap = this.aliasesByPath.get(vaultId);
    if (!aliasMap) {
      aliasMap = new Map<string, string>();
      this.aliasesByPath.set(vaultId, aliasMap);
    }
    if (previous) {
      for (const [noteId, oldEntry] of previous.entries()) {
        const nextEntry = entryMap.get(noteId);
        if (nextEntry && oldEntry.logicalPath.toLowerCase() !== nextEntry.logicalPath.toLowerCase()) {
          aliasMap.set(oldEntry.logicalPath.toLowerCase(), noteId);
        }
      }
    }

    this.entriesByVault.set(vaultId, entryMap);
    this.noteIdByPath.set(vaultId, pathMap);
    this.bump(vaultId);
    return list;
  }

  rememberAlias(vaultId: string, oldPath: string, noteId: string): void {
    let map = this.aliasesByPath.get(vaultId);
    if (!map) {
      map = new Map<string, string>();
      this.aliasesByPath.set(vaultId, map);
    }
    map.set(oldPath.toLowerCase(), noteId);
  }

  entriesForVault(vaultId: string): LexiPathEntry[] {
    const map = this.entriesByVault.get(vaultId);
    return map ? Array.from(map.values()) : [];
  }

  entryByNoteId(vaultId: string, noteId: string): LexiPathEntry | undefined {
    return this.entriesByVault.get(vaultId)?.get(noteId);
  }

  noteIdForPath(vaultId: string, relativePath: string): string {
    const lower = relativePath.toLowerCase();
    const direct = this.noteIdByPath.get(vaultId)?.get(lower);
    if (direct) { return direct; }
    const aliasId = this.aliasesByPath.get(vaultId)?.get(lower);
    if (aliasId && this.entriesByVault.get(vaultId)?.has(aliasId)) {
      return aliasId;
    }
    return '';
  }

  exactNoteIdForPath(vaultId: string, relativePath: string): string {
    return this.noteIdByPath.get(vaultId)?.get(relativePath.toLowerCase()) ?? '';
  }

  toFileRef(entry: LexiPathEntry): PluginFileRef {
    const slash = entry.logicalPath.lastIndexOf('/');
    const name = slash >= 0 ? entry.logicalPath.slice(slash + 1) : entry.logicalPath;
    return {
      id: entry.noteId,
      vaultId: entry.vaultId,
      projectId: entry.projectId,
      path: entry.logicalPath,
      name,
      extension: 'md',
      kind: 'file',
      size: entry.size,
      ctime: entry.ctime,
      mtime: entry.updatedAt
    };
  }
}
