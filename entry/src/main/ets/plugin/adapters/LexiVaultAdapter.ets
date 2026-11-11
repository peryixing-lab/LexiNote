import { common } from '@kit.AbilityKit';
import { LexiProject, NoteItem, VaultItem } from '../../core/LexiModels';
import { LexiStorageService } from '../../core/LexiStorageService';
import { LexiFolderPolicy } from '../../core/LexiFolderPolicy';
import { PluginFileRef, PluginLimits } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { LexiPathEntry, LexiPathRegistry } from './LexiPathRegistry';
import { LexiEditorBridge } from './LexiEditorBridge';

/**
 * The only door between a plugin and note storage (P03 read / P04 write).
 *
 * Reads go through LexiStorageService + LexiPathRegistry; writes go through
 * `saveNote` for creation and `saveNoteIfCurrent` for modification so the existing
 * cross-process lock, `DOCUMENT_CHANGED_ELSEWHERE` guard and Markdown serialization all
 * keep working. There is no second note database and no direct RDB/file access here.
 */
export class LexiVaultAdapter {
  static async assertVault(vaultId: string): Promise<VaultItem> {
    if (typeof vaultId !== 'string' || vaultId.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少知识库标识');
    }
    const vaults = await LexiStorageService.getVaults(true);
    const vault = vaults.find((item: VaultItem): boolean => item.id === vaultId);
    if (!vault) { throw PluginErrors.raise(PluginErrorCode.VAULT_FORBIDDEN, '知识库不存在或未授权'); }
    return vault;
  }

  private static async authorizedNote(vaultId: string, noteId: string): Promise<NoteItem> {
    await LexiVaultAdapter.assertVault(vaultId);
    if (typeof noteId !== 'string' || noteId.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少文件标识');
    }
    const note = await LexiStorageService.getNoteById(noteId);
    if (!note || note.vaultId !== vaultId) {
      throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '文件不存在或不属于当前知识库');
    }
    if (note.trashedAt > 0) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '文件已移入回收站'); }
    if (note.sourceMissing) { throw PluginErrors.raise(PluginErrorCode.IO, '文件在磁盘上已丢失'); }
    return note;
  }

  static async listMarkdown(vaultId: string): Promise<PluginFileRef[]> {
    await LexiVaultAdapter.assertVault(vaultId);
    await LexiPathRegistry.ensureFresh(vaultId);
    const entries = LexiPathRegistry.entriesForVault(vaultId);
    const result: PluginFileRef[] = [];
    const limit = Math.min(entries.length, PluginLimits.MAX_LIST_RESULT);
    for (let index = 0; index < limit; index++) {
      result.push(LexiPathRegistry.fileRef(entries[index]));
    }
    return result;
  }

  static async getByPath(vaultId: string, relativePath: string): Promise<PluginFileRef | undefined> {
    await LexiVaultAdapter.assertVault(vaultId);
    const path = LexiPathRegistry.markdownPath(relativePath);
    await LexiPathRegistry.ensureFresh(vaultId);
    let noteId = LexiPathRegistry.noteIdForPath(vaultId, path);
    if (!noteId) { return undefined; }
    let entry = LexiPathRegistry.entry(vaultId, noteId);
    if (!entry) { return undefined; }
    // A file may have been trashed between two scans; trust the storage layer.
    const note = await LexiStorageService.getNoteById(noteId);
    if (!note || note.trashedAt > 0 || note.sourceMissing || note.vaultId !== vaultId) {
      LexiPathRegistry.forget(vaultId, noteId);
      return undefined;
    }
    entry = LexiPathRegistry.entry(vaultId, noteId);
    return entry ? LexiPathRegistry.fileRef(entry) : undefined;
  }

  static async getById(vaultId: string, noteId: string): Promise<PluginFileRef | undefined> {
    const note = await LexiVaultAdapter.authorizedNote(vaultId, noteId);
    await LexiPathRegistry.ensureFresh(vaultId);
    let entry = LexiPathRegistry.entry(vaultId, note.id);
    if (!entry) {
      const saved = LexiPathRegistry.rememberCreated(vaultId, note, false);
      entry = saved;
    }
    return LexiPathRegistry.fileRef(entry);
  }

  static async readText(vaultId: string, noteId: string): Promise<string> {
    const note = await LexiVaultAdapter.authorizedNote(vaultId, noteId);
    return note.content;
  }

  private static async projectForFolder(vaultId: string, folder: string): Promise<string> {
    if (!folder) { return ''; }
    const projects = await LexiStorageService.getProjects(vaultId);
    const target = folder.toLowerCase();
    const exact = projects.find((project: LexiProject): boolean =>
      project.name === folder);
    if (exact) { return exact.id; }
    const cleaned = projects.find((project: LexiProject): boolean =>
      LexiFolderPolicy.fileName(project.name || '').toLowerCase() === target);
    if (cleaned) { return cleaned.id; }
    throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `知识库中不存在文件夹 ${folder}`);
  }

  static async createText(context: common.Context, vaultId: string, relativePath: string,
    content: string): Promise<PluginFileRef> {
    await LexiVaultAdapter.assertVault(vaultId);
    const path = LexiPathRegistry.markdownPath(relativePath);
    if (typeof content !== 'string') {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '正文必须是字符串');
    }
    await LexiPathRegistry.ensureFresh(vaultId);
    if (LexiPathRegistry.noteIdForPath(vaultId, path) !== '') {
      throw PluginErrors.raise(PluginErrorCode.PATH_EXISTS, `文件已存在：${path}`);
    }
    const folder = LexiPathRegistry.folderOf(path);
    const projectId = await LexiVaultAdapter.projectForFolder(vaultId, folder);
    const title = LexiPathRegistry.nameOf(path).replace(/\.md$/i, '');
    const note = new NoteItem();
    note.id = '';
    note.vaultId = vaultId;
    note.projectId = projectId;
    note.title = title;
    note.content = content;
    note.noteType = 'markdown';
    note.editorLevel = 'pro';
    note.notebook = folder || '笔记';
    let saved: NoteItem;
    try {
      saved = await LexiStorageService.saveNote(context, note);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.IO, PluginErrors.messageOf(error));
    }
    const canonical = await LexiStorageService.getNoteById(saved.id);
    const finalNote = canonical ? canonical : saved;
    const entry = LexiPathRegistry.rememberCreated(vaultId, finalNote, false, path);
    if (entry.logicalPath !== path) {
      // Two plugins created the same title at the same time: the second one gets a suffix
      // instead of silently overwriting the first.
      LexiPathRegistry.rememberAlias(vaultId, path, finalNote.id);
    }
    return LexiPathRegistry.fileRef(entry);
  }

  /**
   * Conditional write. `expectedUpdatedAt` (0 = last read wins) plus the note's current
   * title/content form the atomic expectation passed to `saveNoteIfCurrent`, so a concurrent
   * user edit surfaces as E_CONFLICT instead of being overwritten.
   */
  static async writeText(context: common.Context, vaultId: string, noteId: string, content: string,
    expectedUpdatedAt: number): Promise<PluginFileRef> {
    if (typeof content !== 'string') {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '正文必须是字符串');
    }
    const latest = await LexiVaultAdapter.authorizedNote(vaultId, noteId);
    if (expectedUpdatedAt > 0 && latest.updatedAt !== expectedUpdatedAt) {
      throw PluginErrors.raise(PluginErrorCode.CONFLICT, '文件已被修改，请重新读取后再写入');
    }
    if (LexiEditorBridge.hasUnsavedDraft(noteId)) {
      throw PluginErrors.raise(PluginErrorCode.EDITOR_CONFLICT, '当前文件有未保存的编辑草稿，请先保存或关闭编辑器');
    }
    const snapshot = JSON.parse(JSON.stringify(latest)) as NoteItem;
    snapshot.content = content;
    let saved: NoteItem;
    try {
      saved = await LexiStorageService.saveNoteIfCurrent(context, snapshot, latest.title, latest.content);
    } catch (error) {
      throw new Error(PluginErrors.normalize(error));
    }
    const canonical = await LexiStorageService.getNoteById(saved.id);
    const finalNote = canonical ? canonical : saved;
    await LexiPathRegistry.ensureFresh(vaultId);
    const entry = LexiPathRegistry.applySaved(vaultId, finalNote, finalNote.title);
    return LexiPathRegistry.fileRef(entry);
  }

  /** Title rename only. Moving between vaults/folders is explicitly unsupported in v1. */
  static async renameText(context: common.Context, vaultId: string, noteId: string,
    newRelativePath: string): Promise<PluginFileRef> {
    const note = await LexiVaultAdapter.authorizedNote(vaultId, noteId);
    const target = LexiPathRegistry.markdownPath(newRelativePath);
    await LexiPathRegistry.ensureFresh(vaultId);
    const current = LexiPathRegistry.entry(vaultId, noteId);
    const currentFolder = current ? LexiPathRegistry.folderOf(current.logicalPath) : '';
    const nextFolder = LexiPathRegistry.folderOf(target);
    if (currentFolder !== nextFolder) {
      throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, '首版不支持插件跨文件夹移动文件');
    }
    const owner = LexiPathRegistry.noteIdForPath(vaultId, target);
    if (owner !== '' && owner !== noteId) {
      throw PluginErrors.raise(PluginErrorCode.PATH_EXISTS, `目标路径已存在：${target}`);
    }
    const title = LexiPathRegistry.nameOf(target).replace(/\.md$/i, '');
    if (title === note.title) {
      return LexiPathRegistry.fileRef(current ? current : LexiPathRegistry.rememberCreated(vaultId, note, false));
    }
    let saved: NoteItem;
    try {
      saved = await LexiStorageService.renameNote(context, noteId, title);
    } catch (error) {
      throw new Error(PluginErrors.normalize(error));
    }
    const canonical = await LexiStorageService.getNoteById(saved.id);
    const finalNote = canonical ? canonical : saved;
    const entry = LexiPathRegistry.applySaved(vaultId, finalNote, finalNote.title);
    return LexiPathRegistry.fileRef(entry);
  }

  /** Soft delete: matches the application's recycle bin, not Obsidian's permanent delete. */
  static async deleteText(context: common.Context, vaultId: string, noteId: string): Promise<void> {
    await LexiVaultAdapter.authorizedNote(vaultId, noteId);
    if (LexiEditorBridge.hasUnsavedDraft(noteId)) {
      throw PluginErrors.raise(PluginErrorCode.EDITOR_CONFLICT, '当前文件有未保存的编辑草稿');
    }
    try {
      await LexiStorageService.setNoteTrash(context, noteId, true);
    } catch (error) {
      throw new Error(PluginErrors.normalize(error));
    }
    LexiPathRegistry.forget(vaultId, noteId);
  }

  /** Used by the dispatcher to resolve `FileRef | path` style arguments. */
  static async resolveRef(vaultId: string, noteId: string, relativePath: string): Promise<PluginFileRef> {
    if (noteId) {
      const ref = await LexiVaultAdapter.getById(vaultId, noteId);
      if (ref) { return ref; }
      throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '文件不存在');
    }
    const ref = await LexiVaultAdapter.getByPath(vaultId, relativePath);
    if (ref) { return ref; }
    throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `文件不存在：${relativePath}`);
  }
}
