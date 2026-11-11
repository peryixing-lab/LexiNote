import { PluginEditorDraft, PluginLimits, PluginSelectionRange } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

/**
 * A page-owned handle. Components register closures; no plugin ever touches a page's
 * private `@State`, and the host never keeps a reference to a component after unmount.
 */
export class PluginEditorHandle {
  editorId: string = '';
  noteId: string = '';
  vaultId: string = '';
  windowId: string = '';
  ownerId: string = '';

  isDirty: () => boolean = (): boolean => false;
  isReadOnly: () => boolean = (): boolean => false;
  isVisible: () => boolean = (): boolean => true;
  isFocused: () => boolean = (): boolean => false;
  getContent: () => string = (): string => '';
  getBaseContent: () => string = (): string => '';
  getRevision: () => number = (): number => 0;
  getSelection: () => PluginSelectionRange = (): PluginSelectionRange => new PluginSelectionRange();
  replaceRange: (start: number, end: number, text: string) => boolean =
    (_start: number, _end: number, _text: string): boolean => false;
  flush: () => Promise<void> = async (): Promise<void> => {};
  focus: () => void = (): void => {};

  draft(): PluginEditorDraft {
    const draft = new PluginEditorDraft();
    draft.editorId = this.editorId;
    draft.noteId = this.noteId;
    draft.vaultId = this.vaultId;
    draft.windowId = this.windowId;
    draft.revision = this.getRevision();
    draft.baseContent = this.getBaseContent();
    draft.content = this.getContent();
    draft.dirty = this.isDirty();
    draft.readOnly = this.isReadOnly();
    draft.focused = this.isFocused();
    return draft;
  }
}

/**
 * Registry of the live editors of this window (P07).
 *
 * The desktop workspace registers one handle per open tab, the standalone note page
 * registers its own. `active()` only ever returns the focused, visible, non-read-only
 * handle — never "the last note id we happened to load".
 */
export class LexiEditorBridge {
  private static handles: Map<string, PluginEditorHandle> = new Map();
  private static order: string[] = [];
  private static activeId: string = '';
  private static sequence: number = 0;

  static register(handle: PluginEditorHandle): string {
    LexiEditorBridge.sequence++;
    if (!handle.editorId) {
      handle.editorId = `editor-${LexiEditorBridge.sequence}`;
    }
    if (LexiEditorBridge.handles.size >= 64) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, '同时打开的编辑器过多');
    }
    LexiEditorBridge.handles.set(handle.editorId, handle);
    if (!LexiEditorBridge.order.includes(handle.editorId)) {
      LexiEditorBridge.order.push(handle.editorId);
    }
    return handle.editorId;
  }

  static unregister(editorId: string): void {
    LexiEditorBridge.handles.delete(editorId);
    LexiEditorBridge.order = LexiEditorBridge.order.filter((id: string): boolean => id !== editorId);
    if (LexiEditorBridge.activeId === editorId) { LexiEditorBridge.activeId = ''; }
  }

  static setActive(editorId: string): void {
    LexiEditorBridge.activeId = LexiEditorBridge.handles.has(editorId) ? editorId : '';
  }

  static byId(editorId: string): PluginEditorHandle | undefined {
    return LexiEditorBridge.handles.get(editorId);
  }

  static list(): PluginEditorHandle[] {
    const result: PluginEditorHandle[] = [];
    for (const id of LexiEditorBridge.order) {
      const handle = LexiEditorBridge.handles.get(id);
      if (handle) { result.push(handle); }
    }
    return result;
  }

  static handlesForNote(noteId: string): PluginEditorHandle[] {
    return LexiEditorBridge.list().filter((handle: PluginEditorHandle): boolean => handle.noteId === noteId);
  }

  /** Any registered editor holding an unsaved draft for this note. */
  static hasUnsavedDraft(noteId: string): boolean {
    if (!noteId) { return false; }
    return LexiEditorBridge.list().some((handle: PluginEditorHandle): boolean =>
      handle.noteId === noteId && handle.isVisible() && handle.isDirty());
  }

  static dirtyNoteIds(): string[] {
    const ids: string[] = [];
    for (const handle of LexiEditorBridge.list()) {
      if (handle.isDirty() && handle.noteId && !ids.includes(handle.noteId)) { ids.push(handle.noteId); }
    }
    return ids;
  }

  /**
   * Active editor resolution: explicit focus wins, otherwise the single visible dirty
   * editor, otherwise the single visible editor. Ambiguity returns undefined instead of
   * silently picking one.
   */
  static active(): PluginEditorHandle | undefined {
    const explicit = LexiEditorBridge.handles.get(LexiEditorBridge.activeId);
    if (explicit && explicit.isVisible() && !explicit.isReadOnly()) { return explicit; }
    const focused = LexiEditorBridge.list().filter((handle: PluginEditorHandle): boolean =>
      handle.isFocused() && handle.isVisible() && !handle.isReadOnly());
    if (focused.length === 1) { return focused[0]; }
    const dirty = LexiEditorBridge.list().filter((handle: PluginEditorHandle): boolean =>
      handle.isDirty() && handle.isVisible() && !handle.isReadOnly());
    if (dirty.length === 1) { return dirty[0]; }
    const visible = LexiEditorBridge.list().filter((handle: PluginEditorHandle): boolean =>
      handle.isVisible() && !handle.isReadOnly());
    return visible.length === 1 ? visible[0] : undefined;
  }

  /**
   * Applies an explicit range replacement to the active editor.
   * Returns the new document text; the caller is responsible for flushing.
   */
  static replaceRange(start: number, end: number, text: string): string {
    const handle = LexiEditorBridge.active();
    if (!handle) { throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '当前没有可写编辑器'); }
    const content = handle.getContent();
    const from = Math.max(0, Math.min(content.length, Math.min(start, end)));
    const to = Math.max(from, Math.min(content.length, Math.max(start, end)));
    if (!handle.replaceRange(from, to, text)) {
      throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
    }
    return content.substring(0, from) + text + content.substring(to);
  }

  static reset(): void {
    LexiEditorBridge.handles = new Map<string, PluginEditorHandle>();
    LexiEditorBridge.order = [];
    LexiEditorBridge.activeId = '';
    LexiEditorBridge.sequence = 0;
  }

  static get maxSubscribe(): number { return PluginLimits.MAX_SUBSCRIPTIONS_PER_PLUGIN; }
}
