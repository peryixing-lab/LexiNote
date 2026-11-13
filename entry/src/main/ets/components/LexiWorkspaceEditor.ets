import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiMultiCaret, LexiMultiCaretEdit } from '../core/LexiMultiCaret';
import { LexiSpellcheck, LexiSpellingIssue } from '../core/LexiSpellcheck';
import { LexiEditingActions } from '../core/LexiEditingActions';
import { LexiAppearanceSettings } from '../core/LexiAppearanceSettings';
import { common } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LexiCompletionPanel } from './LexiCompletionPanel';
import { LexiCompletion, LexiCompletionCandidate, LexiCompletionContext } from '../core/LexiCompletion';
import { LexiAnchorNavigation } from '../core/LexiAnchorNavigation';
import { LexiIcon } from './LexiIcon';
import { LexiLiveMarkdownEditor } from './LexiLiveMarkdownEditor';
import { LexiMarkdownPreview } from './LexiEditorPanels';
import { LexiLiveEditorController } from '../core/LexiLiveMarkdown';
import { NoteItem, NoteLink, NoteProperty, OutlineHeading } from '../core/LexiModels';
import { LexiWorkspaceEditorController, LexiWorkspaceInspectorSnapshot, LexiWorkspaceSelection } from '../core/LexiWorkspaceModels';
import { LexiStorageService } from '../core/LexiStorageService';
import { PluginEditorHandle } from '../plugin/adapters/LexiEditorBridge';
import { LexiEditorBridge } from '../plugin/adapters/LexiEditorBridge';
import { PluginSelectionRange } from '../plugin/model/PluginModels';
import { LexiShareService } from '../core/LexiShareService';
import { LexiFileActions } from '../core/LexiFileActions';
import { LexiContextTarget } from '../core/LexiContextModels';
import { MarkdownEngine } from '../core/MarkdownEngine';
import { LexiContinuationData, LexiContinuationDraft } from '../core/LexiContinuationData';
import { LexiContinuationSession } from '../core/LexiContinuationSession';
import { LexiCaptureAssistantPanel } from './LexiCaptureAssistantPanel';

class LexiWorkspaceSourceFrame extends FrameCallback {
  private perform: () => void;
  constructor(perform: () => void) { super(); this.perform = perform; }
  onIdle(_remaining: number): void { this.perform(); }
}

interface LexiWorkspacePopupState {
  isVisible: boolean;
}

interface LexiWorkspaceEditorToolParams {
  iconName: string;
  label: string;
  action: () => void;
  isEnabled?: boolean;
}

@Component
export struct LexiWorkspaceEditor {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiEditorDefaultView') private editorDefaultView: string = 'edit';
  @StorageProp('lexiEditorDefaultMode') private editorDefaultMode: string = 'live';
  @StorageProp('lexiEditorShowTitle') private editorShowTitle: boolean = true;
  @StorageProp('lexiEditorLimitWidth') private editorLimitWidth: boolean = true;
  @StorageProp('lexiEditorViewStatus') private editorViewStatus: boolean = true;
  @State private reading: boolean = false;
  @StorageProp('lexiTabHeaders') private showTabHeaders: boolean = true;
  @StorageProp('lexiFontSize') private noteFontSize: number = 16;
  @StorageProp('lexiWheelZoomLock') private wheelZoomLock: boolean = false;
  @StorageProp('lexiEffectiveAccent') private noteAccent: string = '#6E44D9';
  noteId: string = '';
  @StorageProp('lexiAnchorRequest') @Watch('anchorRequested') anchorRequest: number = 0;
  @State private completionItems: LexiCompletionCandidate[] = [];
  @State private completionIndex: number = 0;
  private completionContext: LexiCompletionContext = new LexiCompletionContext();
  private bodyController: TextAreaController = new TextAreaController();
  private liveController: LexiLiveEditorController = new LexiLiveEditorController();
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  editorController: LexiWorkspaceEditorController = new LexiWorkspaceEditorController();
  @Prop @Watch('vaultNotesChanged') vaultNotes: NoteItem[] = [];
  @Prop paneWidth: number = 900;
  @Prop externalInspector: boolean = false;
  // True only for the tab that is currently selected and visible; the plugin editor bridge
  // uses it to decide which editor is "active" instead of guessing from load order.
  @Prop pluginActive: boolean = false;
  @Prop @Watch('continuationActivityChanged') continuationActive: boolean = true;
  @StorageProp('lexiViewportWidth') windowViewportWidth: number = 900;
  @StorageProp('lexiViewportHeight') windowViewportHeight: number = 800;
  @StorageProp('lexiAbilityForeground') private abilityForeground: boolean = true;
  @State @Watch('syncPluginIdentity') private note: NoteItem = new NoteItem();
  @State private titleText: string = '';
  @State private bodyText: string = '';
  @State private loaded: boolean = false;
  @State private loadFailed: boolean = false;
  @State private editing: boolean = false; // Explicit whole-document source mode; live preview is the default.
  @State private inspectorOpen: boolean = true;
  @State private statusText: string = '正在打开文档…';
  @State private headings: OutlineHeading[] = [];
  @State private outgoing: NoteLink[] = [];
  @State private backlinks: NoteLink[] = [];
  @State private historyCount: number = 0;
  @State private conflictResolving: boolean = false;
  @State private showToolsPopup: boolean = false;
  @State private findOpen: boolean = false;
  @State private findText: string = '';
  @State private replaceText: string = '';
  @State private locked: boolean = false;
  @State private inspectorMode: string = 'outline';
  @State private folded: boolean = false;
  @State private spellingOpen: boolean = false;
  @State private spellingIssues: LexiSpellingIssue[] = [];
  @State private extraCarets: number[] = [];
  @State private toolPage: string = 'format';
  @State private toolLinkQuery: string = '';
  @State private showCaptureAssistant: boolean = false;
  private pendingCaptureOpen: boolean = false;
  private continuationOwner: string = LexiContinuationSession.newOwner();
  private continuationFocused: boolean = false;
  private pendingToolSnippet: string = '';
  private toolSelectionStart: number = 0;
  private toolSelectionEnd: number = 0;
  private toolSelectionBody: string = '';
  private editorAttached: boolean = false;
  private focusRevision: number = 0;
  private conflictVisible: boolean = false;
  private baseTitle: string = '';
  private baseContent: string = '';
  private allNotes: NoteItem[] = [];
  private undoHistory: string[] = [];
  private lastUndoAt: number = 0;
  private saveTimer: number = -1;
  private revision: number = 0;
  private savedRevision: number = 0;
  private pendingSave: Promise<void> | undefined = undefined;
  private pluginHandleId: string = '';
  private loading: Promise<void> | undefined = undefined;
  private documentScroller: Scroller = new Scroller();
  onRequestReadingSpace: () => void = (): void => {};
  onOpenAdvancedNote: (noteId: string) => void = (_id: string): void => {};
  onSaved: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onOpenNote: (noteId: string) => void = (_id: string): void => {};
  onConvertMap: (noteId: string) => void = (_id: string): void => {};
  onInspectorChanged: (snapshot: LexiWorkspaceInspectorSnapshot) => void = (_snapshot: LexiWorkspaceInspectorSnapshot): void => {};
  onRequestInspector: (mode: string) => void = (_mode: string): void => {};

  aboutToAppear(): void {
    this.editorAttached = true; this.editorController.ownerId = this.continuationOwner;
    this.inspectorOpen = !this.externalInspector && this.paneWidth >= 900;
    this.editorController.flush = async (): Promise<void> => {
      if (this.loading) {
        try { await this.loading; } catch {
          // A failed read has no draft to lose; allow the tab to be closed or retried.
          if (this.revision !== this.savedRevision) { throw new Error('文档尚未保存'); }
        }
      }
      await this.flush();
    };
    this.editorController.toggleReading = (): void => { this.liveController.finishEditing(); this.reading = !this.reading; };
    this.editorController.format = (action: string): void => { this.runEditingAction(action); };
    this.editorController.selection = (): string => this.bodyText.substring(this.selectionStart, this.selectionEnd);
    this.editorController.selectionRange = (): LexiWorkspaceSelection => {
      const selection = new LexiWorkspaceSelection(); selection.start = this.selectionStart; selection.end = this.selectionEnd; return selection;
    };
    this.editorController.focus = (): void => { this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true); };
    this.editorController.inspectorSnapshot = (): LexiWorkspaceInspectorSnapshot => this.inspectorSnapshot();
    this.editorController.revealHeading = (heading: OutlineHeading): void => { this.jumpToHeading(heading); };
    this.editorController.openTarget = (target: string): Promise<void> => this.openTarget(target);
    this.registerPluginHandle();
    this.loading = this.load();
    this.loading.catch((): void => { this.loadFailed = true; this.statusText = '文档读取失败'; });
  }

  /**
   * Publishes this editor to the plugin host. Closures read live state; nothing here lets a
   * plugin write a page @State directly.
   */
  private registerPluginHandle(): void {
    const handle = new PluginEditorHandle();
    handle.editorId = `ws-${this.continuationOwner}`;
    handle.noteId = this.noteId;
    handle.vaultId = this.note.vaultId;
    handle.windowId = 'main';
    handle.isDirty = (): boolean => this.revision !== this.savedRevision || this.pendingSave !== undefined;
    handle.isReadOnly = (): boolean => this.locked;
    handle.isVisible = (): boolean => this.editorAttached;
    handle.isFocused = (): boolean => this.pluginActive && this.editorAttached;
    handle.getContent = (): string => this.bodyText;
    handle.getBaseContent = (): string => this.baseContent;
    handle.getRevision = (): number => this.revision;
    handle.getSelection = (): PluginSelectionRange => {
      const range = new PluginSelectionRange();
      range.from = this.selectionStart; range.to = this.selectionEnd; return range;
    };
    handle.replaceRange = (start: number, end: number, text: string): boolean => this.pluginReplaceRange(start, end, text);
    handle.flush = async (): Promise<void> => { await this.flush(); };
    handle.focus = (): void => { this.editorController.focus(); };
    this.pluginHandleId = LexiEditorBridge.register(handle);
  }

  /** Applies a plugin range edit through the same path as user typing (undo + autosave). */
  private pluginReplaceRange(start: number, end: number, text: string): boolean {
    if (this.locked || !this.loaded) { return false; }
    const content = this.bodyText;
    const from = Math.max(0, Math.min(content.length, Math.min(start, end)));
    const to = Math.max(from, Math.min(content.length, Math.max(start, end)));
    const next = content.substring(0, from) + text + content.substring(to);
    if (next === content) { return true; }
    this.liveController.finishEditing();
    this.updateBody(next);
    return true;
  }

  private syncPluginIdentity(): void {
    const handle = LexiEditorBridge.byId(this.pluginHandleId);
    if (!handle) { return; }
    handle.noteId = this.note.id.length > 0 ? this.note.id : this.noteId;
    handle.vaultId = this.note.vaultId;
  }

  aboutToDisappear(): void {
    this.editorAttached = false; this.focusRevision++;
    if (this.pluginHandleId.length > 0) { LexiEditorBridge.unregister(this.pluginHandleId); this.pluginHandleId = ''; }
    this.pendingToolSnippet = ''; this.showToolsPopup = false;
    this.pendingCaptureOpen = false; this.showCaptureAssistant = false;
    this.continuationFocused = false;
    LexiContinuationSession.deactivate(this.context(), this.continuationOwner);
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); }
    this.editorController.toggleReading = (): void => {};
    this.editorController.format = (_action: string): void => {};
    this.editorController.selection = (): string => '';
    this.editorController.focus = (): void => {};
    this.flush().catch((): void => {});
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private continuationActivityChanged(): void {
    if (!this.continuationActive) {
      this.continuationFocused = false;
      LexiContinuationSession.deactivate(this.context(), this.continuationOwner);
      this.pendingCaptureOpen = false; this.pendingToolSnippet = ''; this.showCaptureAssistant = false;
    } else { this.activateContinuation(false); }
  }

  private activateContinuation(focused: boolean): void {
    if (!this.editorAttached || !this.loaded || this.loadFailed || (!this.continuationActive && !focused)) { return; }
    if (focused) {
      try {
        const root = this.getUIContext().getAttachedFrameNodeById(`workspace-editor-${this.noteId}-${this.continuationOwner}`);
        if (!root || !root.isAttached() || !root.isVisible()) { return; }
      } catch { return; }
      this.continuationFocused = true;
      AppStorage.setOrCreate('lexiFocusedEditorOwner', this.continuationOwner);
    }
    LexiContinuationSession.activate(this.context(), this.continuationOwner, (): LexiContinuationDraft => {
      if (!this.editorAttached || !this.loaded || (!this.continuationActive && !this.continuationFocused)) {
        throw new Error('当前笔记已不在前台，请重新打开后接续');
      }
      const root = this.getUIContext().getAttachedFrameNodeById(`workspace-editor-${this.noteId}-${this.continuationOwner}`);
      if (!root || !root.isAttached() || !root.isVisible()) { throw new Error('当前笔记窗口不可见，请重新打开后接续'); }
      return LexiContinuationData.capture(this.note, this.titleText, this.bodyText,
        this.selectionStart, this.selectionEnd, this.editing);
    });
  }

  private toggleSourceMode(): void {
    this.reading = false;
    this.focusRevision++;
    this.pendingToolSnippet = ''; this.showToolsPopup = false;
    this.pendingCaptureOpen = false; this.showCaptureAssistant = false;
    this.liveController.finishEditing();
    if (this.editing) { this.refreshDocument(true); }
    this.editing = !this.editing;
    this.completionItems = [];
  }

  private async load(): Promise<void> {
    this.loadFailed = false;
    const found = await LexiStorageService.getNoteById(this.noteId);
    if (!found) { throw new Error('文档不存在'); }
    this.note = found; this.baseTitle = found.title; this.baseContent = found.content;
    this.titleText = found.title;
    this.bodyText = found.content;
    this.selectionStart = found.content.length; this.selectionEnd = found.content.length;
    this.allNotes = (await LexiStorageService.getNotes(found.vaultId)).filter((n: NoteItem): boolean => n.trashedAt === 0);
    this.editing = this.editorDefaultMode === 'source';
    this.reading = this.editorDefaultView === 'preview';
    this.refreshDocument();
    this.loaded = true;
    this.statusText = '已保存到本机';
    this.activateContinuation(false);
    this.anchorRequested();
  }

  private vaultNotesChanged(): void {
    this.allNotes = this.vaultNotes.filter((n: NoteItem): boolean => n.trashedAt === 0);
    if (this.loaded) {
      const latest = this.allNotes.find((n: NoteItem): boolean => n.id === this.noteId);
      if (latest) {
        if (this.revision === this.savedRevision && !this.pendingSave && latest.updatedAt !== this.note.updatedAt) {
          this.titleText = latest.title; this.baseTitle = latest.title;
          this.bodyText = latest.content; this.baseContent = latest.content;
        }
        this.note = latest;
      }
      this.refreshDocument();
    }
  }

  private inspectorSnapshot(): LexiWorkspaceInspectorSnapshot {
    const snapshot = new LexiWorkspaceInspectorSnapshot();
    snapshot.noteId = this.noteId;
    snapshot.title = this.titleText;
    snapshot.headings = this.headings.slice();
    snapshot.outgoing = this.outgoing.slice();
    snapshot.backlinks = this.backlinks.slice();
    snapshot.properties = this.note.properties.slice();
    return snapshot;
  }

  private refreshDocument(includeLinks: boolean = true): void {
    this.headings = MarkdownEngine.extractOutline(this.bodyText);
    if (!includeLinks) {
      this.onInspectorChanged(this.inspectorSnapshot());
      return;
    }
    const snapshot = new NoteItem();
    snapshot.id = this.note.id;
    snapshot.vaultId = this.note.vaultId;
    snapshot.title = this.titleText;
    snapshot.content = this.bodyText;
    const working = this.allNotes.filter((n: NoteItem): boolean => n.id !== this.noteId);
    working.push(snapshot);
    const links = MarkdownEngine.buildNoteLinks(working);
    this.outgoing = links.filter((link: NoteLink): boolean => link.sourceId === this.noteId);
    this.backlinks = links.filter((link: NoteLink): boolean => link.targetId === this.noteId);
    this.onInspectorChanged(this.inspectorSnapshot());
  }

  private changed(): void {
    this.revision++;
    this.statusText = '正在自动保存…';
    if (!this.editing || this.inspectorOpen || this.externalInspector) {
      this.refreshDocument(false);
    }
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); }
    this.saveTimer = setTimeout((): void => {
      this.flush().then((): void => { if (this.spellingOpen) { this.checkSpelling(); } }).catch((): void => { this.statusText = '保存失败 · 点击重试'; });
    }, 400);
  }

  private async flush(): Promise<void> {
    while (this.pendingSave) { await this.pendingSave; }
    if (!this.loaded || this.savedRevision === this.revision) { return; }
    const savingRevision = this.revision;
    const snapshot = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    snapshot.title = this.titleText.trim();
    snapshot.content = this.bodyText;
    const operation = this.saveSnapshot(snapshot, savingRevision);
    this.pendingSave = operation;
    try { await operation; } finally { this.pendingSave = undefined; }
    if (this.savedRevision !== this.revision) { await this.flush(); }
  }

  private async saveSnapshot(snapshot: NoteItem, savingRevision: number): Promise<void> {
    const savingContent = snapshot.content;
    let saved: NoteItem;
    try { saved = await LexiStorageService.saveNoteIfCurrent(this.context(), snapshot, this.baseTitle, this.baseContent); }
    catch (error) {
      if ((error as Error).message === 'DOCUMENT_CHANGED_ELSEWHERE' && !this.conflictVisible) {
        this.conflictVisible = true;
        this.getUIContext().showAlertDialog({ title: '笔记已在其他位置更新', message: '当前草稿仍然保留，可另存为副本，避免覆盖另一个窗口的修改。',
          primaryButton: { value: '保留草稿', action: (): void => { this.conflictVisible = false; } },
          secondaryButton: { value: '另存为副本', action: (): void => { this.saveConflictCopy(); } } });
      }
      throw error as Error;
    }
    this.note = saved; this.baseTitle = saved.title; this.baseContent = saved.content;
    if (this.revision === savingRevision && this.bodyText === savingContent && saved.content !== savingContent) {
      const selectionStart = this.mapSavedCursor(savingContent, saved.content, this.selectionStart);
      const selectionEnd = this.mapSavedCursor(savingContent, saved.content, this.selectionEnd);
      this.bodyText = saved.content;
      this.selectionStart = selectionStart; this.selectionEnd = selectionEnd;
      this.completionItems = [];
      if (this.editing) {
        this.restoreEditorSelection(selectionStart, selectionEnd, saved.content, false);
      }
    }
    this.savedRevision = savingRevision;
    this.refreshDocument(true);
    this.onSaved(saved);
    if (this.revision === savingRevision) { this.statusText = '已保存到本机'; }
  }

  private async saveConflictCopy(): Promise<void> {
    if (this.conflictResolving) { return; }
    this.conflictResolving = true;
    try {
      const copy = JSON.parse(JSON.stringify(this.note)) as NoteItem;
      copy.id = ''; copy.path = ''; copy.createdAt = 0; copy.updatedAt = 0;
      copy.title = `${this.titleText || '未命名笔记'}（冲突副本）`; copy.content = this.bodyText;
      const saved = await LexiStorageService.saveNote(this.context(), copy);
      const latest = await LexiStorageService.getNoteById(this.noteId);
      if (latest) {
        this.note = latest; this.titleText = latest.title; this.bodyText = latest.content;
        this.baseTitle = latest.title; this.baseContent = latest.content;
      }
      this.savedRevision = this.revision; this.conflictVisible = false;
      this.onSaved(saved); this.onOpenNote(saved.id);
    } catch { this.statusText = '副本保存失败，当前草稿已保留'; }
    finally { this.conflictResolving = false; }
  }

  private updateBody(text: string): void {
    if (text === this.bodyText) { return; }
    const now = Date.now();
    if (now - this.lastUndoAt >= 600 || this.undoHistory.length === 0) {
      this.undoHistory.push(this.bodyText);
      if (this.undoHistory.length > 50) { this.undoHistory.shift(); }
      this.historyCount = this.undoHistory.length;
    }
    this.lastUndoAt = now;
    this.bodyText = text;
    this.changed();
  }

  private undo(): void {
    if (this.locked) { return; }
    this.liveController.finishEditing();
    const previous = this.undoHistory.pop();
    if (previous === undefined) { return; }
    this.lastUndoAt = 0;
    this.bodyText = previous;
    this.historyCount = this.undoHistory.length;
    this.changed();
  }

  private toggleTodo(lineIndex: number): void {
    if (this.locked) { return; }
    const lines = this.bodyText.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) { return; }
    lines[lineIndex] = /^\s*[-*+]\s+\[ \]/.test(lines[lineIndex]) ?
      lines[lineIndex].replace('[ ]', '[x]') : lines[lineIndex].replace(/\[[xX]\]/, '[ ]');
    this.updateBody(lines.join('\n'));
  }

  private async openTarget(rawTarget: string): Promise<void> {
    this.liveController.finishEditing();
    await this.flush();
    const target = LexiCompletion.splitTarget(rawTarget);
    this.allNotes = (await LexiStorageService.getNotes(this.note.vaultId)).filter((n: NoteItem): boolean => n.trashedAt === 0);
    const found = this.allNotes.find((n: NoteItem): boolean =>
      target.noteName ? n.id === target.noteName || n.title.trim().toLowerCase() === target.noteName.toLowerCase() : n.id === this.noteId);
    if (found) {
      if (found.id === this.noteId) { this.jumpToAnchor(target.anchor); return; }
      LexiAnchorNavigation.request(found.id, target.anchor);
      this.onOpenNote(found.id); return;
    }
    if (!target.noteName) { return; }
    const fresh = new NoteItem();
    fresh.vaultId = this.note.vaultId;
    fresh.projectId = this.note.projectId || '';
    fresh.title = target.noteName;
    fresh.notebook = this.note.notebook;
    fresh.noteType = 'markdown';
    fresh.editorLevel = 'pro';
    const saved = await LexiStorageService.saveNote(this.context(), fresh);
    this.onSaved(saved);
    LexiAnchorNavigation.request(saved.id, target.anchor);
    this.onOpenNote(saved.id);
  }

  private anchorRequested(): void {
    if (!this.loaded) { return; }
    const anchor = LexiAnchorNavigation.take(this.noteId);
    if (anchor) { this.jumpToAnchor(anchor); }
  }

  private jumpToAnchor(anchor: string): void {
    this.refreshDocument(false);
    const heading = LexiCompletion.findHeading(this.headings, anchor);
    if (heading) { this.jumpToHeading(heading); }
    else if (anchor) { this.getUIContext().getPromptAction().showToast({ message: `未找到章节「${anchor}」` }); }
  }

  private mapSavedCursor(before: string, after: string, cursor: number): number {
    let prefix = 0;
    while (prefix < before.length && prefix < after.length && before.charAt(prefix) === after.charAt(prefix)) { prefix++; }
    let suffix = 0;
    while (suffix < before.length - prefix && suffix < after.length - prefix &&
      before.charAt(before.length - suffix - 1) === after.charAt(after.length - suffix - 1)) { suffix++; }
    if (cursor <= prefix) { return cursor; }
    if (cursor >= before.length - suffix) { return Math.max(0, Math.min(after.length, cursor + after.length - before.length)); }
    return Math.min(after.length - suffix, prefix);
  }

  private refreshCompletion(start: number, end: number): void {
    this.selectionStart = start; this.selectionEnd = end;
    this.activateContinuation(true);
    this.completionContext = LexiCompletion.context(this.bodyText, start, end);
    const currentDraft = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    currentDraft.title = this.titleText; currentDraft.content = this.bodyText;
    const workingNotes = this.allNotes.filter((n: NoteItem): boolean => n.id !== this.noteId);
    workingNotes.push(currentDraft);
    this.completionItems = LexiCompletion.candidates(this.completionContext, workingNotes, this.noteId);
    this.completionIndex = 0;
  }

  private acceptCompletion(candidate: LexiCompletionCandidate): void {
    const edit = LexiCompletion.apply(this.bodyText, this.completionContext, candidate);
    this.updateBody(edit.text);
    this.completionItems = [];
    this.selectionStart = edit.cursor; this.selectionEnd = edit.cursor;
    this.restoreEditorSelection(edit.cursor, edit.cursor, edit.text, true);
  }

  private completionKey(event: KeyEvent): boolean {
    if (!this.completionItems.length || event.type !== KeyType.Down) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN || event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      const movement = event.keyCode === KeyCode.KEYCODE_DPAD_DOWN ? 1 : -1;
      this.completionIndex = (this.completionIndex + movement + this.completionItems.length) % this.completionItems.length;
      return true;
    } else if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_TAB) {
      this.acceptCompletion(this.completionItems[this.completionIndex]); return true;
    } else if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.completionItems = []; return true;
    }
    return false;
  }

  private jumpToHeading(heading: OutlineHeading): void {
    this.liveController.finishEditing();
    if (this.editing) { this.editing = false; }
    this.folded = false;
    this.completionItems = [];
    if (heading.level === 1 && heading.title.trim() === this.titleText.trim()) {
      this.documentScroller.scrollTo({ xOffset: 0, yOffset: 0 }); return;
    }
    setTimeout((): void => {
      try {
        const utils = this.getUIContext().getComponentUtils();
        const prefix = this.reading ? 'workspace-reading' : 'workspace-block';
        const target = utils.getRectangleById(`${prefix}-${this.noteId}-${this.continuationOwner}-${heading.lineIndex}`);
        const viewport = utils.getRectangleById(`workspace-document-${this.noteId}-${this.continuationOwner}`);
        const delta = this.getUIContext().px2vp(target.windowOffset.y - viewport.windowOffset.y);
        this.documentScroller.scrollTo({ xOffset: 0,
          yOffset: Math.max(0, this.documentScroller.currentOffset().yOffset + delta - 24) });
      } catch {}
    }, 80);
  }

  private async exportDocument(): Promise<void> {
    try {
      await this.flush();
      await LexiStorageService.saveViaDocumentPicker(this.context(), `${MarkdownEngine.displayTitle(this.note)}.md`, this.bodyText);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message || '导出未完成' });
    }
  }

  private async shareDocument(): Promise<void> {
    try {
      await this.flush();
      await LexiShareService.shareDraftNote(
        this.context(),
        this.note,
        this.titleText,
        this.bodyText,
        this.note.notebook,
        'workspace-document-more'
      );
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message || '系统分享未完成' });
    }
  }

  private async revealDocument(): Promise<void> {
    try {
      await this.flush();
      await LexiFileActions.reveal(this.context(), LexiContextTarget.note(this.note));
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message || '无法打开笔记所在文件夹' });
    }
  }

  private restoreEditorSelection(start: number, end: number, expectedBody: string, requestFocus: boolean): void {
    const revision = ++this.focusRevision;
    const sourceMode = this.editing;
    const uiContext = this.getUIContext();
    uiContext.postFrameCallback(new LexiWorkspaceSourceFrame((): void => {
      if (!this.editorAttached || revision !== this.focusRevision || !this.loaded || this.conflictResolving || this.showCaptureAssistant ||
        this.bodyText !== expectedBody || this.editing !== sourceMode) { return; }
      try {
        const root = uiContext.getAttachedFrameNodeById(`workspace-editor-${this.noteId}-${this.continuationOwner}`);
        if (!root || !root.isAttached() || !root.isVisible()) { return; }
        if (sourceMode) {
          const inputId = `workspace-body-input-${this.noteId}-${this.continuationOwner}`;
          const input = uiContext.getAttachedFrameNodeById(inputId);
          if (!input || !input.isAttached() || !input.isVisible()) { return; }
          if (requestFocus) { uiContext.getFocusController().requestFocus(inputId); }
          this.bodyController.setTextSelection(start, end);
        } else { this.liveController.setTextSelection(start, end); }
      } catch {
        // Retained tabs may become hidden between scheduling a frame and restoring the selection.
      }
    }));
  }

  private runEditingAction(action: string): void {
    if (!this.loaded || this.conflictResolving) { return; }
    if (action === 'heading-rename') {
      const first = this.bodyText.lastIndexOf('\n', Math.max(0, this.selectionStart - 1)) + 1;
      const next = this.bodyText.indexOf('\n', this.selectionStart); const last = next < 0 ? this.bodyText.length : next;
      const line = this.bodyText.substring(first, last);
      if (!/^#{1,6} /.test(line)) { throw new Error('请将光标放在需要重命名的标题行'); }
      this.findOpen = true; this.findText = line; this.replaceText = line; this.selectionStart = first; this.selectionEnd = last; return;
    }
    if (action === 'spellcheck') {
      this.spellingOpen = !this.spellingOpen;
      if (this.spellingOpen) { this.checkSpelling(); } return;
    }
    if (action === 'cursor-above' || action === 'cursor-below') { this.addCursor(action === 'cursor-above' ? -1 : 1); return; }
    this.extraCarets = [];
    if (action === 'source-toggle') { this.toggleSourceMode(); return; }
    if (action === 'find' || action === 'replace') { this.findOpen = true; return; }
    if (action === 'lock') { this.locked = !this.locked; return; }
    if (action === 'fold' || action === 'unfold' || action === 'fold-toggle') {
      this.folded = action === 'fold' || (action === 'fold-toggle' && !this.folded); return;
    }
    if (action === 'outline' || action === 'backlinks' || action === 'outgoing' || action === 'properties') {
      if (this.externalInspector) { this.onRequestInspector(action); return; }
      this.inspectorMode = action; this.inspectorOpen = true; return;
    }
    if (action === 'inspector-toggle') {
      if (this.externalInspector) { this.onRequestInspector('toggle'); }
      else { this.inspectorOpen = !this.inspectorOpen; }
      return;
    }
    if (this.locked) { throw new Error('当前笔记已锁定，请先解锁'); }
    if (action === 'date' || action === 'time') {
      const now = new Date();
      const snippet = action === 'date' ? `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}` :
        `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
      const edit = LexiEditingActions.replace(this.bodyText, this.selectionStart, this.selectionEnd, snippet);
      this.lastUndoAt = 0; this.updateBody(edit.content); this.selectionStart = edit.end; this.selectionEnd = edit.end;
    } else {
      const edit = LexiEditingActions.apply(this.bodyText, this.selectionStart, this.selectionEnd, action);
      this.lastUndoAt = 0; this.updateBody(edit.content); this.selectionStart = edit.start; this.selectionEnd = edit.end;
    }
    this.reading = false; this.folded = false;
    this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true);
  }

  private checkSpelling(): void {
    const expected = this.bodyText;
    LexiSpellcheck.check(this.context(), expected).then((issues: LexiSpellingIssue[]): void => {
      if (expected === this.bodyText) { this.spellingIssues = issues; }
    }).catch((error: Error): void => { this.statusText = error.message; });
  }
  private fixSpelling(word: string, suggestion: string): void {
    if (this.locked) { return; }
    this.lastUndoAt = 0; this.updateBody(this.bodyText.replace(new RegExp('\\b' + word + '\\b', 'g'), suggestion)); this.checkSpelling();
  }
  private addCursor(direction: number): void {
    this.liveController.finishEditing(); this.reading = false; this.editing = true;
    const lines = this.bodyText.split('\n'); const primaryLine = this.bodyText.substring(0, this.selectionStart).split('\n').length - 1;
    const starts: number[] = []; let offset = 0;
    for (const line of lines) { starts.push(offset); offset += line.length + 1; }
    const column = this.selectionStart - starts[primaryLine];
    let nextLine = primaryLine + direction;
    while (nextLine >= 0 && nextLine < lines.length) {
      const caret = starts[nextLine] + Math.min(column, lines[nextLine].length);
      if (!this.extraCarets.includes(caret)) { this.extraCarets = this.extraCarets.concat([caret]); break; }
      nextLine += direction;
    }
    this.selectionEnd = this.selectionStart;
    this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true);
  }
  private applyMultiCaret(edit: LexiMultiCaretEdit): void {
    this.lastUndoAt = 0; this.updateBody(edit.content);
    this.selectionStart = edit.carets[0]; this.selectionEnd = this.selectionStart;
    this.extraCarets = edit.carets.slice(1).filter((caret: number): boolean => caret !== this.selectionStart);
    this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true);
  }
  private multiInsert(event: InsertValue): boolean {
    if (!this.extraCarets.length || this.locked) { return true; }
    if (this.selectionStart !== this.selectionEnd) { this.extraCarets = []; return true; }
    this.applyMultiCaret(LexiMultiCaret.insert(this.bodyText, [event.insertOffset].concat(this.extraCarets), event.insertValue));
    return false;
  }
  private multiDelete(event: DeleteValue): boolean {
    if (!this.extraCarets.length || this.locked) { return true; }
    if (this.selectionStart !== this.selectionEnd) { this.extraCarets = []; return true; }
    this.applyMultiCaret(LexiMultiCaret.remove(this.bodyText, [this.selectionStart].concat(this.extraCarets), event.direction === TextDeleteDirection.BACKWARD, event.deleteValue.length));
    return false;
  }

  private findNext(): void {
    if (!this.findText) { return; }
    let index = this.bodyText.indexOf(this.findText, this.selectionEnd);
    if (index < 0) { index = this.bodyText.indexOf(this.findText); }
    if (index < 0) { this.statusText = '没有匹配内容'; return; }
    this.reading = false; this.folded = false;
    this.selectionStart = index; this.selectionEnd = index + this.findText.length;
    this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true);
  }

  private replaceCurrent(): void {
    if (!this.findText || this.locked || this.conflictResolving) { return; }
    if (this.bodyText.substring(this.selectionStart, this.selectionEnd) !== this.findText) { this.findNext(); return; }
    const edit = LexiEditingActions.replace(this.bodyText, this.selectionStart, this.selectionEnd, this.replaceText);
    this.lastUndoAt = 0; this.updateBody(edit.content); this.selectionStart = edit.end; this.selectionEnd = edit.end;
    this.findNext();
  }
  private replaceMatches(): void {
    if (!this.findText || this.locked || this.conflictResolving) { return; }
    const count = this.bodyText.split(this.findText).length - 1;
    this.lastUndoAt = 0;
    this.updateBody(this.bodyText.split(this.findText).join(this.replaceText));
    this.statusText = `已替换 ${count} 处`;
  }

  private openTools(): void {
    if (!this.loaded || this.conflictResolving || this.locked) { return; }
    this.pendingToolSnippet = ''; this.pendingCaptureOpen = false;
    this.toolPage = 'format'; this.toolLinkQuery = '';
    this.toolSelectionStart = this.selectionStart; this.toolSelectionEnd = this.selectionEnd;
    this.toolSelectionBody = this.bodyText;
    this.showToolsPopup = !this.showToolsPopup;
  }

  private selectedToolText(): string {
    const start = Math.max(0, Math.min(this.toolSelectionStart, this.toolSelectionBody.length));
    const end = Math.max(start, Math.min(this.toolSelectionEnd, this.toolSelectionBody.length));
    return this.toolSelectionBody.substring(start, end);
  }

  private queueToolAction(action: string): void {
    if (!this.loaded || this.conflictResolving || this.locked) { return; }
    const selected = this.selectedToolText();
    let snippet = '';
    if (action === 'bold') { snippet = `**${selected || '粗体内容'}**`; }
    else if (action === 'italic') { snippet = `*${selected || '强调内容'}*`; }
    else if (action === 'strike') { snippet = `~~${selected || '待修订内容'}~~`; }
    else if (action === 'highlight') { snippet = `==${selected || '重点内容'}==`; }
    else if (action === 'h1') { snippet = `\n# ${selected || '章节标题'}\n`; }
    else if (action === 'h2') { snippet = `\n## ${selected || '核心小节'}\n`; }
    else if (action === 'todo') { snippet = `\n- [ ] ${selected || '待完成事项'}\n`; }
    else if (action === 'hr') { snippet = '\n\n---\n\n'; }
    else if (action === 'table') { snippet = '\n| 项目 | 内容 |\n| --- | --- |\n|  |  |\n'; }
    else if (action === 'code') { snippet = '\n```\n' + selected + '\n```\n'; }
    else if (action === 'formula') { snippet = `\n$$${selected || 'f(n) = O(n \\log n)'}$$\n`; }
    else if (action === 'callout') { snippet = `\n> [!NOTE] 知识要点\n> ${selected || '在此记录要点'}\n`; }
    else if (action === 'link') { this.toolPage = 'links'; return; }
    else if (action === 'assistant') {
      this.pendingToolSnippet = ''; this.pendingCaptureOpen = true; this.showToolsPopup = false; return;
    }
    this.queueToolSnippet(snippet);
  }

  private queueToolSnippet(snippet: string): void {
    if (!snippet || !this.loaded || this.conflictResolving) { return; }
    this.pendingCaptureOpen = false; this.pendingToolSnippet = snippet;
    this.showToolsPopup = false;
  }

  private insertPendingToolSnippet(): void {
    const snippet = this.pendingToolSnippet;
    this.pendingToolSnippet = '';
    if (!snippet || !this.editorAttached || !this.loaded || this.conflictResolving) { return; }
    try {
      const root = this.getUIContext().getAttachedFrameNodeById(`workspace-editor-${this.noteId}-${this.continuationOwner}`);
      if (!root || !root.isAttached() || !root.isVisible()) { return; }
    } catch { return; }
    const start = this.mapSavedCursor(this.toolSelectionBody, this.bodyText, this.toolSelectionStart);
    const end = Math.max(start, this.mapSavedCursor(this.toolSelectionBody, this.bodyText, this.toolSelectionEnd));
    if (this.editing) {
      this.lastUndoAt = 0;
      this.updateBody(this.bodyText.substring(0, start) + snippet + this.bodyText.substring(end));
      this.selectionStart = start + snippet.length; this.selectionEnd = this.selectionStart;
      this.restoreEditorSelection(this.selectionStart, this.selectionEnd, this.bodyText, true);
    } else {
      this.lastUndoAt = 0;
      this.liveController.setTextSelection(start, end);
      this.liveController.insert(snippet);
    }
  }

  private toolLinkCandidates(): NoteItem[] {
    const query = this.toolLinkQuery.trim().toLowerCase();
    return this.allNotes.filter((note: NoteItem): boolean => note.id !== this.noteId && note.trashedAt === 0 &&
      (!query || MarkdownEngine.displayTitle(note).toLowerCase().includes(query))).slice(0, 8);
  }

  private toolsPopupDidDisappear(): void {
    if (!this.pendingCaptureOpen) { this.insertPendingToolSnippet(); return; }
    this.pendingCaptureOpen = false;
    if (!this.editorAttached || !this.loaded || this.conflictResolving) { return; }
    try {
      const root = this.getUIContext().getAttachedFrameNodeById(`workspace-editor-${this.noteId}-${this.continuationOwner}`);
      if (!root || !root.isAttached() || !root.isVisible()) { return; }
    } catch { return; }
    this.liveController.finishEditing(); this.completionItems = [];
    this.showCaptureAssistant = true;
  }

  private requestVoiceCapture(): void {
    if (!this.editorAttached || !this.loaded || this.loadFailed || this.conflictResolving ||
      this.showCaptureAssistant || this.pendingCaptureOpen) { return; }
    this.toolSelectionStart = this.selectionStart; this.toolSelectionEnd = this.selectionEnd;
    this.toolSelectionBody = this.bodyText;
    this.pendingToolSnippet = ''; this.pendingCaptureOpen = true;
    if (this.showToolsPopup) { this.showToolsPopup = false; }
    else { this.toolsPopupDidDisappear(); }
  }

  private captureSheetHeight(): number {
    const viewport = this.windowViewportHeight > 0 ? this.windowViewportHeight : 800;
    return Math.max(1, Math.min(720, viewport - 96));
  }

  private captureDismissed(): void {
    this.showCaptureAssistant = false;
    this.insertPendingToolSnippet();
  }

  @Builder
  private formatTool(label: string, action: string) {
    Button(label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(`workspace-tool-${this.noteId}-${action}`).width('32%').height(40).fontSize(12)
      .padding(2).borderRadius(8).margin({ right: '1%', bottom: 6 })
      .fontColor(this.palette.brand_ink).backgroundColor(this.palette.soft_surface)
      .onClick((): void => { this.queueToolAction(action); })
  }

  @Builder
  private captureAssistantSheet() {
    LexiCaptureAssistantPanel({ content: this.bodyText,
      availableNotes: this.allNotes.filter((note: NoteItem): boolean => note.id !== this.noteId &&
        note.trashedAt === 0 && note.vaultId === this.note.vaultId),
      onInsert: (text: string): void => {
        if (!text || !this.editorAttached || !this.loaded || this.conflictResolving) { return; }
        this.pendingToolSnippet = text; this.showCaptureAssistant = false;
      },
      onClose: (): void => { this.pendingToolSnippet = ''; this.showCaptureAssistant = false; }
    })
  }

  @Builder
  private toolsPopup() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        if (this.toolPage === 'links') {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 3 }) {
              LexiIcon({ name: 'back', iconSize: 13 })
              Text('返回').fontSize(12).fontColor(this.palette.brand_ink)
            }.width('100%').justifyContent(FlexAlign.Center)
          }.id(`workspace-tools-back-${this.noteId}`).width(62).height(32).padding(0).borderRadius(8)
            .accessibilityText('返回工具列表').onClick((): void => { this.toolPage = 'format'; })
        }
        Text(this.toolPage === 'links' ? '插入笔记链接' : '笔记工具').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text_primary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('关闭', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(30).fontSize(11)
          .fontColor(this.palette.brand_ink).onClick((): void => { this.pendingToolSnippet = ''; this.showToolsPopup = false; })
      }.width('100%')
      Scroll() {
        Column({ space: 7 }) {
          if (this.toolPage === 'links') {
            TextInput({ text: this.toolLinkQuery, placeholder: '搜索笔记或输入新标题' })
              .id(`workspace-tool-link-search-${this.noteId}`).height(36).fontSize(12)
              .fontColor(this.palette.text_primary).backgroundColor(this.palette.soft_surface)
              .onChange((text: string): void => { this.toolLinkQuery = text; })
            ForEach(this.toolLinkCandidates(), (candidate: NoteItem) => {
              Button(MarkdownEngine.displayTitle(candidate), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .id(`workspace-tool-link-${this.noteId}-${candidate.id}`).width('100%').height(34).fontSize(12)
                .fontColor(this.palette.brand_ink).onClick((): void => {
                  this.queueToolSnippet(`[[${MarkdownEngine.displayTitle(candidate)}]]`);
                })
            }, (candidate: NoteItem): string => candidate.id)
            if (this.toolLinkQuery.trim()) {
              Button('插入此标题链接', { buttonStyle: ButtonStyleMode.TEXTUAL }).width('100%').height(34).fontSize(12)
                .fontColor(this.palette.brand_ink).onClick((): void => { this.queueToolSnippet(`[[${this.toolLinkQuery.trim()}]]`); })
            }
          } else {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              this.formatTool('粗体', 'bold')
              this.formatTool('斜体', 'italic')
              this.formatTool('删除线', 'strike')
              this.formatTool('高亮', 'highlight')
              this.formatTool('一级标题', 'h1')
              this.formatTool('二级标题', 'h2')
              this.formatTool('待办清单', 'todo')
              this.formatTool('分割线', 'hr')
              this.formatTool('表格', 'table')
              this.formatTool('代码块', 'code')
              this.formatTool('公式', 'formula')
              this.formatTool('提示框', 'callout')
              this.formatTool('笔记链接', 'link')
              this.formatTool('语音 / 整理', 'assistant')
            }.width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
    }.id(`workspace-tools-popup-${this.noteId}`).width(Math.min(312, Math.max(236, this.paneWidth - 32)))
      .height(320).padding(12).backgroundColor(this.palette.surface).borderRadius(16)
      .onDisAppear((): void => { this.toolsPopupDidDisappear(); })
  }

  @Builder
  private tool($$: LexiWorkspaceEditorToolParams) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      LexiIcon({ name: $$.iconName, iconSize: 17 })
    }
    .width(36).height(36).padding(0).borderRadius(7)
    .backgroundColor(Color.Transparent).enabled($$.isEnabled !== false)
    .accessibilityText($$.label).onClick($$.action)
  }

  @Builder
  private documentMenu() {
    Menu() {
      MenuItem({ content: '撤销正文编辑' }).enabled(this.historyCount > 0)
        .onClick((): void => { this.undo(); })
      MenuItem({ content: '文档属性与高级编辑' }).onClick((): void => {
        this.flush().then((): void => { this.onOpenAdvancedNote(this.noteId); }).catch((): void => {
          this.statusText = '保存失败 · 点击重试';
        });
      })
      MenuItem({ content: '导出 Markdown' }).onClick((): void => { this.exportDocument(); })
      MenuItem({ content: '系统分享文件' }).id('workspace-share-file').onClick((): void => { this.shareDocument(); })
      MenuItem({ content: '在文件管理中显示' }).id('workspace-reveal-file').onClick((): void => { this.revealDocument(); })
      MenuItem({ content: '生成思维导图' }).onClick((): void => {
        this.flush().then((): void => { this.onConvertMap(this.noteId); }).catch((): void => {
          this.statusText = '保存失败 · 点击重试';
        });
      })
    }
  }

  @Builder
  private inspector() {
    Column({ space: 18 }) {
      Row() {
        Text(this.inspectorMode === 'properties' ? '笔记属性' : this.inspectorMode === 'backlinks' ? '反向链接' : this.inspectorMode === 'outgoing' ? '出链' : '文档大纲').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
        Blank()
        Text(`${this.headings.length}`).fontSize(11).fontColor(this.palette.text_secondary)
      }.width('100%')
      Scroll() {
        Column({ space: 4 }) {
          if (this.inspectorMode === 'properties') {
            ForEach(this.note.properties, (prop: NoteProperty) => {
              Text(prop.key + ': ' + prop.propValue).fontSize(12).width('100%')
            }, (prop: NoteProperty): string => prop.key)
          }
          if (this.inspectorMode === 'outline') {
          if (this.headings.length === 0) {
            Text('用 Markdown 标题梳理思路，大纲会出现在这里。')
              .fontSize(12).lineHeight(21).fontColor(this.palette.text_secondary).width('100%')
          }
          ForEach(this.headings, (heading: OutlineHeading) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Text(heading.title).fontSize(12).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.palette.text_secondary).width('100%').textAlign(TextAlign.Start)
            }
            .width('100%').constraintSize({ minHeight: 36 }).padding({ left: (heading.level - 1) * 10, right: 2, top: 7, bottom: 7 })
            .backgroundColor(Color.Transparent).borderRadius(6).onClick((): void => { this.jumpToHeading(heading); })
          }, (heading: OutlineHeading): string => heading.id)
          }
          Divider().color(this.palette.workspace_line).margin({ top: 22, bottom: 16 })
          Text('双向链接').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).width('100%')
          Text(`${this.outgoing.length} 个出链 · ${this.backlinks.length} 个反向链接`)
            .fontSize(11).fontColor(this.palette.text_secondary).width('100%').margin({ top: 6, bottom: 10 })
          if (this.inspectorMode === 'outline' || this.inspectorMode === 'outgoing') {
          ForEach(this.outgoing, (link: NoteLink) => {
            Button(link.targetTitle, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(12).fontColor(this.palette.brand_ink).width('100%').height(34)
              .backgroundColor(Color.Transparent).padding(0)
              .onClick((): void => { this.openTarget(`${link.targetId || link.targetTitle}${link.anchor ? '#' + link.anchor : ''}`).catch((): void => {}); })
          }, (link: NoteLink): string => `${link.sourceId}-${link.targetTitle}`)
          }
          if (this.inspectorMode === 'outline' || this.inspectorMode === 'backlinks') {
          ForEach(this.backlinks, (link: NoteLink) => {
            Button(link.sourceTitle, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(12).fontColor(this.palette.brand_ink).width('100%').height(34)
              .backgroundColor(Color.Transparent).padding(0)
              .onClick((): void => { this.openTarget(link.sourceId).catch((): void => {}); })
          }, (link: NoteLink): string => `back-${link.sourceId}-${link.targetTitle}`)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }
    .width(216).height('100%').padding({ left: 20, right: 20, top: 28, bottom: 24 })
    .backgroundColor(this.palette.workspace_inspector)
    .border({ width: { left: 0.5 }, color: this.palette.workspace_line })
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        if (this.showTabHeaders) {
        LexiIcon({ name: 'folder', iconSize: 15 })
        Text(this.note.notebook || '知识库').fontSize(12).fontColor(this.palette.text_secondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('/').fontSize(12).fontColor(this.palette.text_secondary)
        Text(this.titleText || '无标题笔记').fontSize(12).fontColor(this.palette.text_primary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        } else {
          Blank().layoutWeight(1)
        }
        Button(this.editing ? '实时预览' : '源码', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-edit-toggle').fontSize(12).height(34).padding({ left: 14, right: 14 }).borderRadius(7)
          .backgroundColor(this.editing ? this.palette.workspace_selection : Color.Transparent)
          .fontColor(this.palette.brand_ink)
          .accessibilityText(this.editing ? '当前为整篇源码编辑，切换到实时预览' : '当前为实时预览，切换到整篇源码编辑')
          .onClick((): void => { this.toggleSourceMode(); })
        Button('工具', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id(`workspace-tools-${this.noteId}`).height(34).fontSize(12).padding({ left: 12, right: 12 }).borderRadius(7)
          .fontColor(this.palette.brand_ink).backgroundColor(this.palette.workspace_selection)
          .enabled(this.loaded && !this.conflictResolving).onClick((): void => { this.openTools(); })
          .bindPopup(this.showToolsPopup, {
            builder: this.toolsPopup, placement: Placement.BottomRight, width: Math.min(312, Math.max(236, this.paneWidth - 32)),
            popupColor: this.palette.surface, enableArrow: true, autoCancel: true, focusable: true,
            keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
            onStateChange: (event: LexiWorkspacePopupState): void => { this.showToolsPopup = event.isVisible; }
          })
        Button('更多', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-document-more').height(34).fontSize(12).padding({ left: 10, right: 10 }).borderRadius(7)
          .fontColor(this.palette.text_secondary).backgroundColor(Color.Transparent).bindMenu(this.documentMenu())
        if (!this.externalInspector) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(17).fontColor([this.palette.text_secondary])
        }.id('workspace-outline-toggle').width(36).height(36).padding(0).borderRadius(7)
          .backgroundColor(this.inspectorOpen && this.paneWidth >= 680 ? this.palette.workspace_selection : Color.Transparent)
          .accessibilityText('展开或收起大纲').onClick((): void => {
            if (this.inspectorOpen && this.paneWidth >= 680) { this.inspectorOpen = false; }
            else {
              this.inspectorOpen = true;
              if (this.paneWidth < 900) { this.onRequestReadingSpace(); }
            }
          })
        }
      }
      .id('workspace-editor-toolbar').height(48).width('100%').padding({ left: 28, right: 16 })
      .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
      if (this.spellingOpen) {
        Scroll() {
          Column({ space: 6 }) {
            Row({ space: 8 }) { Text('英文拼写检查').fontSize(12); Button('重新检查').fontSize(12).onClick((): void => { this.checkSpelling(); }) }
            ForEach(this.spellingIssues, (issue: LexiSpellingIssue) => {
              Row({ space: 6 }) {
                Text(issue.word).fontSize(12)
                ForEach(issue.suggestions, (suggestion: string) => {
                  Button(suggestion).fontSize(11).onClick((): void => { this.fixSpelling(issue.word, suggestion); })
                }, (suggestion: string): string => suggestion)
              }
            }, (issue: LexiSpellingIssue): string => issue.word)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').height(140).padding(8)
      }
      if (this.extraCarets.length > 0) {
        Row({ space: 8 }) { Text(`${this.extraCarets.length + 1} 个输入光标`).fontSize(12); Button('取消多光标').fontSize(12).onClick((): void => { this.extraCarets = []; }) }
      }
      if (this.findOpen) {
        Row({ space: 8 }) {
          TextInput({ text: this.findText, placeholder: '查找内容' }).layoutWeight(1).height(36)
            .onChange((text: string): void => { this.findText = text; }).onSubmit((): void => { this.findNext(); })
          TextInput({ text: this.replaceText, placeholder: '替换为' }).layoutWeight(1).height(36)
            .onChange((text: string): void => { this.replaceText = text; })
          Button('下一个').fontSize(12).onClick((): void => { this.findNext(); })
          Button('替换').fontSize(12).onClick((): void => { this.replaceCurrent(); })
          Button('全部替换').fontSize(12).onClick((): void => { this.replaceMatches(); })
          Button('关闭').fontSize(12).onClick((): void => { this.findOpen = false; })
        }.width('100%').padding(8)
      }
      Row() {
        Scroll(this.documentScroller) {
          Column({ space: 18 }) {
            if (this.loadFailed) {
              Text('文档暂时无法打开').fontSize(24).fontColor(this.palette.text_primary)
              Button('重新读取').onClick((): void => {
                this.loading = this.load(); this.loading.catch((): void => { this.loadFailed = true; });
              })
            } else if (this.loaded) {
              if (this.editorShowTitle) {
              TextArea({ text: this.titleText, placeholder: '无标题笔记' })
                .id(`workspace-title-input-${this.noteId}-${this.continuationOwner}`).enabled(!this.conflictResolving && !this.locked)
                .width('100%').constraintSize({ minHeight: 44 }).padding(0)
                .fontSize(30).lineHeight(40).fontWeight(FontWeight.Bold).fontColor(this.palette.text_primary)
                .placeholderColor(this.palette.text_secondary).caretColor(this.noteAccent)
                .backgroundColor(Color.Transparent).borderRadius(0)
                .onFocus((): void => { this.activateContinuation(true); })
                .onChange((text: string): void => {
                  const clean = text.replace(/\r?\n/g, ' ');
                  if (clean !== this.titleText) { this.titleText = clean; this.changed(); }
                })
              }
              Row({ space: 8 }) {
                Text(this.note.noteType === 'study' ? '学习笔记' : this.note.noteType === 'quick' ? '快速笔记' : 'Markdown')
                  .fontSize(11).fontColor(this.palette.brand_ink)
                Text('·').fontSize(11).fontColor(this.palette.text_secondary)
                Text(`${this.bodyText.length} 字符`).fontSize(11).fontColor(this.palette.text_secondary)
                ForEach(this.note.tags.slice(0, 3), (tag: string) => {
                  Text(`#${tag}`).fontSize(11).fontColor(this.palette.brand_ink)
                }, (tag: string): string => tag)
              }.width('100%').margin({ bottom: 14 })
              if (this.folded) {
                ForEach(this.headings, (heading: OutlineHeading) => {
                  Button(heading.title).width('100%').onClick((): void => { this.folded = false; this.jumpToHeading(heading); })
                }, (heading: OutlineHeading): string => heading.id)
                Button('展开当前笔记').onClick((): void => { this.folded = false; })
              } else if (this.reading) {
                LexiMarkdownPreview({ frameless: true, blocks: MarkdownEngine.parseBlocks(this.bodyText),
                  outgoingLinks: this.outgoing, availableNotes: this.allNotes, notePath: this.note.path,
                  anchorPrefix: `workspace-reading-${this.noteId}-${this.continuationOwner}`,
                  onOpenTarget: (target: string): void => { this.openTarget(target).catch((): void => {}); },
                  onToggleTodo: (line: number): void => { this.toggleTodo(line); } })
              } else if (this.editing) {
                TextArea({ text: this.bodyText, controller: this.bodyController, placeholder: '从一个想法开始。支持 Markdown、#标签与 [[双向链接]]。' })
                  .id(`workspace-body-input-${this.noteId}-${this.continuationOwner}`).enabled(!this.conflictResolving && !this.locked).width('100%').constraintSize({ minHeight: 460 })
                  .fontSize(this.noteFontSize).lineHeight(this.noteFontSize * 1.75).fontColor(this.palette.text_primary)
                  .placeholderColor(this.palette.text_secondary).caretColor(this.noteAccent)
                  .backgroundColor(Color.Transparent).borderRadius(0).padding(0)
                  .onFocus((): void => { this.activateContinuation(true); })
                  .onChange((text: string): void => { this.updateBody(text); })
                  .onWillInsert((event: InsertValue): boolean => this.multiInsert(event))
                  .onWillDelete((event: DeleteValue): boolean => this.multiDelete(event))
                  .onTextSelectionChange((start: number, end: number): void => { this.refreshCompletion(start, end); })
                  .onKeyPreIme((event: KeyEvent): boolean => { return this.completionKey(event); })
              } else {
                LexiLiveMarkdownEditor({
                  content: this.bodyText, editorController: this.liveController, editorEnabled: !this.conflictResolving && !this.locked,
                  availableNotes: this.allNotes, notePath: this.note.path,
                  anchorPrefix: `workspace-block-${this.noteId}-${this.continuationOwner}`,
                  placeholder: '点按这里开始记录。支持 Markdown、#标签与 [[双向链接]]。',
                  onChange: (text: string): void => { this.updateBody(text); },
                  onSelectionChange: (start: number, end: number): void => { this.refreshCompletion(start, end); },
                  onSourceKey: (event: KeyEvent): boolean => { return this.completionKey(event); },
                  onOpenTarget: (target: string): void => { this.openTarget(target).catch((): void => {}); },
                  onToggleTodo: (line: number): void => { this.toggleTodo(line); }
                })
              }
              if (this.completionItems.length > 0) {
                LexiCompletionPanel({ candidates: this.completionItems, activeIndex: this.completionIndex,
                  onSelect: (candidate: LexiCompletionCandidate): void => { this.acceptCompletion(candidate); } })
              }
            }
          }
          .width('100%').constraintSize({ maxWidth: this.editorLimitWidth ? 800 : 10000 })
          .padding({ left: 56, right: 56, top: 42, bottom: 80 }).alignItems(HorizontalAlign.Start)
        }
        .id(`workspace-document-${this.noteId}-${this.continuationOwner}`).layoutWeight(1).height('100%')
        .enableScrollInteraction(!this.wheelZoomLock)
        .align(Alignment.Top).scrollBar(BarState.Auto)
        if (!this.externalInspector && this.inspectorOpen && this.paneWidth >= 680) { this.inspector(); }
      }.width('100%').layoutWeight(1)
        .onAxisEvent((event: AxisEvent): void => { LexiAppearanceSettings.handleAxis(event); })
      Row({ space: this.paneWidth >= 600 ? 16 : 8 }) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.mic')).fontSize(15).fontColor([this.palette.brand_ink])
            Text('语音记录').fontSize(12).fontColor(this.palette.brand_ink).maxLines(1)
          }
        }.id(`workspace-voice-record-${this.noteId}`).width(104).height(32).padding({ left: 8, right: 8 }).borderRadius(8)
          .backgroundColor(this.palette.soft_surface).accessibilityText('语音记录，打开离线语音速记')
          .enabled(this.loaded && !this.loadFailed && !this.conflictResolving)
          .onClick((): void => { this.requestVoiceCapture(); })
        if (this.editorViewStatus && this.paneWidth >= 600) {
          Button(this.reading ? '阅读视图' : this.editing ? 'Markdown 源码' : '实时预览',
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-view-status').height(32).fontSize(11).fontColor(this.palette.text_secondary)
            .onClick((): void => { this.liveController.finishEditing(); this.reading = !this.reading; })
        }
        if (this.paneWidth >= 900) {
          Text(`${this.backlinks.length} 个反向链接`).fontSize(11).fontColor(this.palette.text_secondary).maxLines(1)
        }
        if (this.paneWidth >= 480) {
          Text(`${this.bodyText.length} 字符`).fontSize(11).fontColor(this.palette.text_secondary).maxLines(1)
        }
        Text(this.statusText).id('workspace-save-status').fontSize(11).fontColor(this.palette.text_secondary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End)
          .onClick((): void => { this.flush().catch((): void => { this.statusText = '保存失败 · 点击重试'; }); })
      }
      .height(deviceInfo.deviceType === '2in1' ? 40 : 44).width('100%')
      .padding({ left: this.paneWidth >= 600 ? 24 : 12, right: this.paneWidth >= 600 ? 20 : 12,
        bottom: deviceInfo.deviceType === '2in1' ? 0 : 4 })
      .border({ width: { top: 0.5 }, color: this.palette.workspace_line })
    }.id(`workspace-editor-${this.noteId}-${this.continuationOwner}`).width('100%').height('100%').backgroundColor(this.palette.workspace_page)
      .onVisibleAreaChange([0], (visible: boolean, _ratio: number): void => {
        if (!visible) {
          this.continuationFocused = false;
          LexiContinuationSession.deactivate(this.context(), this.continuationOwner);
          this.pendingCaptureOpen = false; this.pendingToolSnippet = ''; this.showCaptureAssistant = false;
        } else if (this.continuationActive) { this.activateContinuation(false); }
      })
      .bindSheet($$this.showCaptureAssistant, this.captureAssistantSheet, {
        height: this.captureSheetHeight(), width: this.windowViewportWidth >= 840 ? 680 : '100%',
        preferType: this.windowViewportWidth >= 840 ? SheetType.CENTER : SheetType.BOTTOM,
        radius: this.windowViewportWidth >= 840 ? LengthMetrics.vp(24) : undefined,
        dragBar: this.windowViewportWidth < 840, showClose: true,
        backgroundColor: this.palette.surface,
        onDisappear: (): void => { this.captureDismissed(); }
      })
  }
}
