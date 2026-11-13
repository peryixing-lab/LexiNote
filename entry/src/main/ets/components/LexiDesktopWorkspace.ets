import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiExportService } from '../core/LexiExportService';
import { LengthMetrics, window } from '@kit.ArkUI';
import { pointer } from '@kit.InputKit';
import { LexiWorkspacePreferences } from '../core/LexiWorkspacePreferences';
import { LexiKnowledgePanel } from './LexiKnowledgePanel';
import { LexiStorageService } from '../core/LexiStorageService';
import { LexiFileActions } from '../core/LexiFileActions';
import { LexiAppearanceSettings } from '../core/LexiAppearanceSettings';
import { LexiEditorSettings } from '../core/LexiEditorSettings';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { LexiHotkeySettings } from '../core/LexiHotkeySettings';
import { LexiShortcutRouter } from '../core/LexiShortcutRouter';
import { LexiI18n } from '../core/LexiI18n';
import { LexiInterfaceSettings } from '../core/LexiInterfaceSettings';
import { LexiContextSurface } from './LexiContextSurface';
import { LexiContextTarget } from '../core/LexiContextModels';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LexiIcon } from './LexiIcon';
import { LexiWorkspaceEditor } from './LexiWorkspaceEditor';
import { LexiWorkspaceRightSidebar } from './LexiWorkspaceRightSidebar';
import { LexiWorkspaceMindMap } from './LexiWorkspaceMindMap';
import { CanvasBoard, LexiProject, MindMapDoc, NoteItem, OutlineHeading, VaultItem } from '../core/LexiModels';
import { LexiWorkspaceInspectorSnapshot, LexiWorkspaceTab } from '../core/LexiWorkspaceModels';
import { MarkdownEngine } from '../core/MarkdownEngine';
import { LexiSearch } from '../core/LexiSearch';
import { LexiCommandPalette } from './LexiCommandPalette';
import { PluginCommandRegistry } from '../plugin/core/PluginCommandRegistry';
import { PluginManager } from '../plugin/core/PluginManager';
import { PluginKeyboardFocus } from '../plugin/core/PluginKeyboardFocus';
import { LexiEditorBridge } from '../plugin/adapters/LexiEditorBridge';
import { FrameCallback } from '@kit.ArkUI';
import { LexiTabStripLayout } from '../core/LexiTabStripLayout';

class LexiWorkspaceTabFrame extends FrameCallback {
  private perform: () => void;
  constructor(perform: () => void) { super(); this.perform = perform; }
  onIdle(_remaining: number): void { this.perform(); }
}

interface LexiWorkspaceActionParams {
  iconName: string;
  label: string;
  action: () => void;
  selected?: boolean;
}

interface LexiWorkspaceNoteRowParams { note: NoteItem; }

@Builder
function lexiWorkspaceEmptySlot() {}

@Component
export struct LexiDesktopWorkspace {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @StorageProp('lexiTopInset') topInset: number = 0;
  @StorageProp('lexiViewportHeight') private viewportHeight: number = 800;
  @StorageProp('lexiShowRibbon') private showRibbon: boolean = true;
  @StorageProp('lexiSidebarWidth') private preferredSidebarWidth: number = 244;
  @StorageProp('lexiRightSidebarWidth') private preferredRightSidebarWidth: number = 280;
  @StorageProp('lexiTabHeaders') private showTabHeaders: boolean = true;
  @StorageProp('lexiHiddenRibbonCommands') private hiddenRibbonCommands: string = '[]';
  @StorageProp('lexiWindowButtonsInset') windowButtonsInset: number = 0;
  @StorageProp('lexiPluginOpenView') @Watch('pluginViewRequested') private pluginOpenView: string = '';
  @Prop projects: LexiProject[] = [];
  @Prop @Watch('projectChanged') activeProjectId: string = '';
  @Prop activeProjectName: string = '全部项目';
  @Prop viewportWidth: number = 1200;
  @Prop @Watch('documentsChanged') notes: NoteItem[] = [];
  @Prop @Watch('documentsChanged') maps: MindMapDoc[] = [];
  @Prop canvases: CanvasBoard[] = [];
  @Prop vaults: VaultItem[] = [];
  @Prop @Watch('vaultChanged') activeVaultId: string = '';
  @Prop activeVaultName: string = '';
  @Prop activeSection: number = 0;
  @Prop lastEditedNoteId: string = '';
  @Prop requestedOpenMode: string = 'tab';
  @Prop requestedNoteId: string = '';
  @Prop @Watch('requestedChanged') openRevision: number = 0;
  @Prop routeActive: boolean = false;
  @State @Watch('sidebarVisibilityChanged') private sidebarOpen: boolean = true;
  @State private sidebarResizing: boolean = false;
  @State private sidebarResizeHovered: boolean = false;
  @State private sidebarDragWidth: number = 244;
  private sidebarDragStartWidth: number = 244;
  @State private rightSidebarOpen: boolean = false;
  @State private rightSidebarResizing: boolean = false;
  @State private rightSidebarResizeHovered: boolean = false;
  @State private rightSidebarDragWidth: number = 280;
  private rightSidebarDragStartWidth: number = 280;
  @State private rightSidebarMode: string = 'outline';
  @State private measuredWorkspaceWidth: number = 0;
  @State private inspectorSnapshot: LexiWorkspaceInspectorSnapshot = new LexiWorkspaceInspectorSnapshot();
  @State private knowledgeCommand: string = '';
  @State private knowledgeRevision: number = 0;
  @State private knowledgeExcerpt: string = '';
  @State private knowledgeSelectionStart: number = 0;
  @State private knowledgeSelectionEnd: number = 0;
  @State private splitVertical: boolean = false;
  private closedTabIds: string[] = [];
  private navigationIds: string[] = [];
  private navigationCursor: number = -1;
  private navigatingHistory: boolean = false;

  @State private searchText: string = '';
  @State private favoritesOnly: boolean = false;
  @State private closedFolders: string[] = [];
  @State private groupTabs: LexiWorkspaceTab[] = [];
  @State @Watch('scheduleActiveTabReveal') private tabs: LexiWorkspaceTab[] = [];
  @State @Watch('scheduleActiveTabReveal') private selectedId: string = '';
  @State @Watch('scheduleActiveTabReveal') private tabViewportWidth: number = 0;
  private tabScroller: Scroller = new Scroller();
  private tabLayoutRevision: number = 0;
  @State private switchingVault: boolean = false;
  @State private showWorkspaceOpen: boolean = false;
  @State private workspaceOpenTarget: string = '';
  @State private rememberWorkspaceOpen: boolean = false;
  @State private showPalette: boolean = false;
  @State private paletteMode: string = 'commands';
  // T05:固定"插件功能"入口(功能面板 bindSheet)。
  /** 宿主页面回调:按插件 id 打开该插件的设置页(设置窗口承载)。 */
  routingStack: NavPathStack = new NavPathStack();
  @BuilderParam auxiliaryContent: () => void = lexiWorkspaceEmptySlot;
  onSelectProject: (projectId: string) => Promise<void> = async (_id: string): Promise<void> => {};
  onManageWorkspaces: () => void = (): void => {};
  onSelectSection: (index: number) => void = (_index: number): void => {};
  onCreateNote: () => void = (): void => {};
  onSaved: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onMapSaved: (doc: MindMapDoc) => void = (_doc: MindMapDoc): void => {};
  onSwitchVault: (vaultId: string) => Promise<void> = async (_id: string): Promise<void> => {};
  onOpenMap: (mapId: string) => void = (_id: string): void => {};
  onCreateMap: () => void = (): void => {};
  onOpenCanvas: (canvasId: string) => void = (_id: string): void => {};
  onCreateCanvas: () => void = (): void => {};
  onConvertMap: (noteId: string) => void = (_id: string): void => {};
  onOpenAdvancedNote: (noteId: string) => void = (_id: string): void => {};
  onOpenHelp: () => void = (): void => {};
  onOpenSettings: () => void = (): void => {};
  onOpenTrash: () => void = (): void => {};
  onManagePlugins: () => void = (): void => {};
  // 返回 true 表示宿主已接管这次打开(容器路由或询问中),组件不要再就地开标签。
  onNoteOpenRequest: (noteId: string) => boolean = (_noteId: string): boolean => false;
  onExecuteCommand: (command: string, noteId: string, title: string) => Promise<void> =
    async (_command: string, _id: string, _title: string): Promise<void> => {};

  aboutToAppear(): void {
    this.routingStack.disableAnimation(true);
    LexiShortcutRouter.register((command: string): void => {
      if (this.showPalette || this.routeActive) { return; }
      this.executeCommand(command);
    });
    this.openInitialDocument();
  }

  aboutToDisappear(): void {
    this.clearSidebarResize();
    this.clearRightSidebarResize();
    LexiShortcutRouter.unregister();
    this.tabLayoutRevision++;
  }

  private commandVisible(id: string): boolean {
    return LexiInterfaceSettings.isVisible(this.hiddenRibbonCommands, id);
  }

  private sidebarContentWidth(): number {
    return LexiInterfaceSettings.sidebarWidthForWindow(
      this.sidebarResizing ? this.sidebarDragWidth : this.preferredSidebarWidth,
      this.availableWorkspaceWidth(), this.showRibbon ? 56 : 0, this.rightSidebarWidth());
  }

  private sidebarWidth(): number { return (this.sidebarOpen ? this.sidebarContentWidth() : 0) + (this.showRibbon ? 56 : 0); }

  private sidebarVisibilityChanged(): void {
    if (this.sidebarOpen && this.rightSidebarOpen &&
      this.availableWorkspaceWidth() - this.sidebarWidth() - this.rightSidebarWidth() < 420) {
      this.rightSidebarOpen = false;
      this.clearRightSidebarResize();
    }
  }

  private updateSidebarCursor(): void {
    const cursor = this.getUIContext().getCursorController();
    if (this.sidebarResizeHovered || this.sidebarResizing || this.rightSidebarResizeHovered || this.rightSidebarResizing) {
      cursor.setCursor(pointer.PointerStyle.RESIZE_LEFT_RIGHT);
    }
    else { cursor.restoreDefault(); }
  }

  private clearSidebarResize(): void {
    if (this.sidebarResizing || this.sidebarResizeHovered) {
      this.sidebarResizing = false;
      this.sidebarResizeHovered = false;
      this.updateSidebarCursor();
    }
  }

  private finishSidebarResize(): void {
    if (!this.sidebarResizing) { return; }
    // Persist only an explicit resize, preserving the preferred width on window changes.
    LexiInterfaceSettings.setSidebarWidth(this.sidebarContentWidth()).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('侧栏宽度保存失败，请重试。') });
    });
    this.sidebarResizing = false;
    this.updateSidebarCursor();
  }

  private availableWorkspaceWidth(): number {
    return this.measuredWorkspaceWidth > 0 ? this.measuredWorkspaceWidth : this.viewportWidth;
  }

  private rightSidebarWidth(): number {
    return this.rightSidebarOpen ? LexiInterfaceSettings.rightSidebarWidthForWindow(
      this.rightSidebarResizing ? this.rightSidebarDragWidth : this.preferredRightSidebarWidth,
      this.availableWorkspaceWidth(), this.showRibbon ? 56 : 0, this.sidebarOpen) : 0;
  }

  private clearRightSidebarResize(): void {
    if (this.rightSidebarResizing || this.rightSidebarResizeHovered) {
      this.rightSidebarResizing = false;
      this.rightSidebarResizeHovered = false;
      this.updateSidebarCursor();
    }
  }

  private finishRightSidebarResize(): void {
    if (!this.rightSidebarResizing) { return; }
    LexiInterfaceSettings.setRightSidebarWidth(this.rightSidebarWidth()).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('侧栏宽度保存失败，请重试。') });
    });
    this.rightSidebarResizing = false;
    this.updateSidebarCursor();
  }

  private editorPaneWidth(): number {
    return Math.max(0, this.availableWorkspaceWidth() - this.sidebarWidth() - this.rightSidebarWidth()) /
      (this.groupTabs.length > 0 && !this.splitVertical ? 2 : 1);
  }

  private currentInspector(): LexiWorkspaceInspectorSnapshot {
    return this.activeSection <= 1 && this.inspectorSnapshot.noteId === this.selectedId ?
      this.inspectorSnapshot : new LexiWorkspaceInspectorSnapshot();
  }

  /** `ctx.views.open()` asks the workspace to reveal the sidebar for that plugin. */
  private pluginViewRequested(): void {
    if (this.pluginOpenView.length === 0) { return; }
    let pluginId = '';
    try {
      const parsed = JSON.parse(this.pluginOpenView) as Record<string, string>;
      if (typeof parsed.pluginId === 'string') { pluginId = parsed.pluginId; }
    } catch (error) {
      return;
    }
    if (pluginId.length > 0) { this.openRightInspector('plugin:' + pluginId); }
  }

  private openRightInspector(mode: string): void {
    if (mode === 'toggle') { this.rightSidebarOpen = !this.rightSidebarOpen; }
    else { this.rightSidebarMode = mode; this.rightSidebarOpen = true; }
    if (this.rightSidebarOpen && this.availableWorkspaceWidth() - this.sidebarWidth() - this.rightSidebarWidth() < 420) {
      this.sidebarOpen = false;
    }
    this.scheduleActiveTabReveal();
  }

  private inlineContextMenus(): boolean { return deviceInfo.deviceType !== '2in1'; }

  /** Publishes what the plugins are allowed to know about this window. */
  private publishPluginWorkspace(): void {
    const openIds: string[] = [];
    for (const tab of this.tabs) { openIds.push(tab.noteId); }
    const activeFileId = this.selectedId.startsWith('map:') ? '' : this.selectedId;
    PluginManager.publishWorkspace('main', this.activeVaultId, activeFileId, openIds);
    const activeEditor = LexiEditorBridge.active();
    if (activeEditor && activeEditor.editorId.length > 0) { LexiEditorBridge.setActive(activeEditor.editorId); }
  }

  private scheduleActiveTabReveal(): void {
    this.publishPluginWorkspace();
    const editor = this.tabs.find((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
    this.inspectorSnapshot = editor && !editor.noteId.startsWith('map:') ?
      editor.controller.inspectorSnapshot() : new LexiWorkspaceInspectorSnapshot();
    const revision = ++this.tabLayoutRevision;
    const uiContext = this.getUIContext();
    uiContext.postFrameCallback(new LexiWorkspaceTabFrame((): void => {
      if (revision !== this.tabLayoutRevision || this.tabViewportWidth <= 0) { return; }
      const node = uiContext.getAttachedFrameNodeById('workspace-tab-scroll');
      if (!node || !node.isAttached() || !node.isVisible()) { return; }
      try {
        const current = this.tabScroller.currentOffset().xOffset;
        const index = this.tabs.findIndex((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
        const offset = LexiTabStripLayout.revealOffset(this.tabViewportWidth, this.tabs.length, index, current);
        if (Math.abs(offset - current) > 0.5) { this.tabScroller.scrollTo({ xOffset: offset, yOffset: 0 }); }
      } catch {
        // The window can detach between the frame callback and the scroll request.
      }
    }));
  }

  private isTabValid(docId: string): boolean {
    if (docId.startsWith('map:')) {
      const mapId = docId.substring(4);
      return this.maps.some((m: MindMapDoc): boolean => m.id === mapId && m.trashedAt === 0 &&
        (!m.projectId || this.projects.some((project: LexiProject): boolean => project.id === m.projectId)));
    }
    return this.notes.some((n: NoteItem): boolean => n.id === docId && n.trashedAt === 0 &&
      (!n.projectId || this.projects.some((project: LexiProject): boolean => project.id === n.projectId)));
  }

  private openInitialDocument(): void {
    const available = this.notes.filter((n: NoteItem): boolean => n.vaultId === this.activeVaultId && n.trashedAt === 0 &&
      (!this.activeProjectId || n.projectId === this.activeProjectId));
    const availableMaps = this.maps.filter((m: MindMapDoc): boolean => m.vaultId === this.activeVaultId && m.trashedAt === 0 &&
      (!this.activeProjectId || m.projectId === this.activeProjectId));
    if (this.selectedId.startsWith('map:')) {
      const mapId = this.selectedId.substring(4);
      if (availableMaps.some((m: MindMapDoc): boolean => m.id === mapId)) { return; }
    } else if (available.some((note: NoteItem): boolean => note.id === this.selectedId)) {
      return;
    }
    const recent = available.find((n: NoteItem): boolean => n.id === this.lastEditedNoteId);
    if (recent) { this.openDocument(recent.id, false); }
    else if (available.length > 0) { this.openDocument(available[0].id, false); }
    else if (availableMaps.length > 0) { this.openDocument(`map:${availableMaps[0].id}`, false); }
    else { this.selectedId = ''; }
  }

  private projectChanged(): void {
    setTimeout((): void => { this.openInitialDocument(); }, 0);
  }

  private documentsChanged(): void {
    const remaining = this.tabs.filter((tab: LexiWorkspaceTab): boolean => this.isTabValid(tab.noteId));
    this.groupTabs = this.groupTabs.filter((tab: LexiWorkspaceTab): boolean => this.isTabValid(tab.noteId));
    if (remaining.length !== this.tabs.length) {
      this.tabs = remaining;
      if (!remaining.some((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId)) {
        this.selectedId = remaining.length > 0 ? remaining[0].noteId : '';
      }
    }
  }

  private vaultChanged(): void {
    this.clearSidebarResize();
    this.clearRightSidebarResize();
    this.tabs = []; this.groupTabs = [];
    this.selectedId = '';
    this.searchText = '';
    this.closedFolders = [];
    // The parent refresh publishes vault and document props together.
    setTimeout((): void => { this.openInitialDocument(); }, 0);
  }

  private requestedChanged(): void {
    if (this.requestedNoteId) {
      if (this.requestedOpenMode === 'group') { this.openGroup(this.requestedNoteId); } else { this.openDocument(this.requestedNoteId); }
    }
  }

  private openDocument(noteId: string, activatePane: boolean = true): void {
    if (!this.tabs.some((tab: LexiWorkspaceTab): boolean => tab.noteId === noteId)) {
      this.tabs = this.tabs.concat([new LexiWorkspaceTab(noteId)]);
    }
    this.selectedId = noteId;
    if (!this.navigatingHistory && this.navigationIds[this.navigationCursor] !== noteId) {
      this.navigationIds = this.navigationIds.slice(0, this.navigationCursor + 1).concat([noteId]);
      this.navigationCursor = this.navigationIds.length - 1;
    }
    if (activatePane) {
      this.routingStack.clear();
      if (this.activeSection > 1) { this.onSelectSection(1); }
      if (noteId.startsWith('map:')) {
        const mapId = noteId.substring(4);
        const targetMap = this.maps.find((m: MindMapDoc): boolean => m.id === mapId);
        if (targetMap && this.activeProjectId && (targetMap.projectId || '') !== this.activeProjectId) {
          this.onSelectProject(targetMap.projectId || '').catch((): void => {});
        }
      } else {
        const target = this.notes.find((note: NoteItem): boolean => note.id === noteId);
        if (target && this.activeProjectId && (target.projectId || '') !== this.activeProjectId) {
          this.onSelectProject(target.projectId || '').catch((): void => {});
        }
      }
    }
  }

  private async flushAll(): Promise<void> {
    for (const tab of this.tabs.concat(this.groupTabs)) { await tab.controller.flush(); }
  }
  private async openGroup(id: string): Promise<void> {
    await this.flushAll(); this.routingStack.clear(); this.onSelectSection(1);
    this.sidebarOpen = false; this.groupTabs = [new LexiWorkspaceTab(id)];
  }
  private async closeGroup(): Promise<void> {
    await this.flushAll(); this.groupTabs = [];
  }

  private async closeDocument(tab: LexiWorkspaceTab): Promise<void> {
    try { await tab.controller.flush(); } catch {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('保存未完成，文档仍保留在标签页中。') });
      return;
    }
    const index = this.tabs.findIndex((item: LexiWorkspaceTab): boolean => item.noteId === tab.noteId);
    const remaining = this.tabs.filter((item: LexiWorkspaceTab): boolean => item.noteId !== tab.noteId);
    if (this.selectedId === tab.noteId) {
      this.selectedId = remaining.length > 0 ? remaining[Math.min(index, remaining.length - 1)].noteId : '';
    }
    this.closedTabIds.push(tab.noteId);
    this.tabs = remaining;
  }

  private async manageWorkspaces(): Promise<void> {
    try {
      await this.flushAll();
      this.onManageWorkspaces();
    } catch { this.getUIContext().getPromptAction().showToast({ message: this.tr('保存未完成，请重试。') }); }
  }

  private async selectProject(projectId: string): Promise<void> {
    try {
      await this.flushAll();
      await this.onSelectProject(projectId);
      this.routingStack.clear(); this.onSelectSection(1);
    } catch { this.getUIContext().getPromptAction().showToast({ message: this.tr('切换项目失败，文档已保留。') }); }
  }

  private async showAuxiliary(section: number): Promise<void> {
    try {
      await this.flushAll();
      this.routingStack.clear();
      if (section === 4) { this.sidebarOpen = false; }
      this.onSelectSection(section);
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('保存未完成，文档已保留，请重试。') });
    }
  }

  private async requestWorkspace(vaultId: string): Promise<void> {
    if (this.switchingVault) { return; }
    const mode = LexiWorkspacePreferences.openMode(await LexiStorageService.getSetting('workspaceOpenMode', 'ask'));
    this.workspaceOpenTarget = vaultId;
    this.rememberWorkspaceOpen = false;
    if (mode === 'ask') { this.showWorkspaceOpen = true; return; }
    await this.openWorkspace(vaultId, mode, false);
  }

  private async openWorkspace(vaultId: string, mode: string, remember: boolean): Promise<void> {
    if (this.switchingVault) { return; }
    this.switchingVault = true;
    try {
      await this.flushAll();
      const available = await LexiStorageService.getVaults();
      if (!available.some((vault: VaultItem): boolean => vault.id === vaultId)) { throw new Error(this.tr('工作区不存在或已归档')); }
      if (mode === 'new') {
        await this.context().startAbility({ bundleName: 'com.lovexjy.lexinote', abilityName: 'WorkspaceAbility',
          parameters: { vaultId: vaultId, workspaceWindowKey: `workspace_${Date.now()}_${Math.floor(Math.random() * 1000000)}` } });
      } else {
        await this.onSwitchVault(vaultId);
        this.routingStack.clear();
      }
      this.showWorkspaceOpen = false;
      if (remember) {
        try {
          await LexiStorageService.setSetting('workspaceOpenMode', mode);
          AppStorage.setOrCreate('lexiWorkspaceOpenMode', mode);
        } catch {
          this.getUIContext().getPromptAction().showToast({ message: this.tr('工作区已打开，但打开方式未保存，请在设置中重试。') });
        }
      }
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('保存或切换失败，当前文档已保留，请重试。') });
    } finally { this.switchingVault = false; }
  }

  @Builder
  private workspaceOpenSheet() {
    Column({ space: 16 }) {
      Text(this.vaults.find((vault: VaultItem): boolean => vault.id === this.workspaceOpenTarget)?.name || '')
        .fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(this.tr('选择此工作区的打开方式。')).fontSize(13).fontColor(this.palette.text_secondary).width('100%')
      Button(this.tr('在当前窗口打开'), { type: ButtonType.Normal })
        .id('workspace-open-current').width('100%').height(42).borderRadius(10).enabled(!this.switchingVault)
        .onClick((): void => { this.openWorkspace(this.workspaceOpenTarget, 'current', this.rememberWorkspaceOpen); })
      Button(this.tr('在新窗口打开'), { type: ButtonType.Normal })
        .id('workspace-open-new').width('100%').height(42).borderRadius(10).enabled(!this.switchingVault)
        .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand)
        .onClick((): void => { this.openWorkspace(this.workspaceOpenTarget, 'new', this.rememberWorkspaceOpen); })
      Row({ space: 8 }) {
        Checkbox({ name: 'remember-workspace-open' }).id('workspace-open-remember')
          .select(this.rememberWorkspaceOpen).enabled(!this.switchingVault)
          .accessibilityText(this.tr('下次不再提示'))
          .onChange((checked: boolean): void => { this.rememberWorkspaceOpen = checked; })
        Text(this.tr('下次不再提示')).fontSize(13).fontColor(this.palette.text_primary)
      }.width('100%')
      Text(this.tr('所有工作区共用此选择，可在“设置 → 编辑器”中重新选择。'))
        .fontSize(12).fontColor(this.palette.text_secondary).width('100%')
      Button(this.tr('取消'), { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.switchingVault)
        .id('workspace-open-cancel').onClick((): void => { this.showWorkspaceOpen = false; })
    }.width('100%').padding({ left: 24, right: 24, top: 12, bottom: 16 }).alignItems(HorizontalAlign.Start)
  }

  private visibleNotes(): NoteItem[] {
    return this.notes.filter((n: NoteItem): boolean => n.trashedAt === 0 && n.vaultId === this.activeVaultId &&
      (!n.projectId || this.projects.some((project: LexiProject): boolean => project.id === n.projectId)) &&
      (!this.activeProjectId || n.projectId === this.activeProjectId) && (!this.favoritesOnly || n.favorite) && LexiSearch.matches(n, this.searchText));
  }

  private openPalette(mode: string): void {
    if (this.routeActive) { return; }
    this.paletteMode = mode; this.showPalette = true;
    setTimeout((): void => { this.getUIContext().getFocusController().requestFocus('command-palette-input'); }, 180);
  }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private activeEditor(): LexiWorkspaceTab | undefined {
    const owner = AppStorage.get<string>('lexiFocusedEditorOwner') || '';
    const candidates = this.tabs.filter((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId).concat(this.groupTabs);
    return candidates.find((tab: LexiWorkspaceTab): boolean => !!owner && tab.controller.ownerId === owner) ||
      this.tabs.find((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
  }
  private async extraCommand(command: string): Promise<boolean> {
    const editor = this.activeEditor();
    const editorActions: string[] = ['heading-rename', 'spellcheck', 'cursor-above', 'cursor-below', 'find', 'replace', 'lock', 'outline', 'backlinks', 'outgoing', 'properties', 'inspector-toggle', 'fold', 'unfold'];
    if (editorActions.includes(command)) {
      if (!editor) { throw new Error('请先打开笔记'); } editor.controller.format(command); return true;
    }
    if (command.startsWith('canvas-')) { throw new Error('请在白板中使用此命令'); }
    if (command.startsWith('link-open')) {
      if (!editor) { throw new Error('请先打开笔记'); }
      await this.flushAll(); const note = await LexiStorageService.getNoteById(editor.noteId);
      if (!note) { throw new Error('请先打开笔记'); }
      const caret = editor.controller.selectionRange().start;
      const pattern = /\[\[([^\]]+)\]\]|\[([^\]]+)\]\(([^)]+)\)/g;
      let match = pattern.exec(note.content); let target = '';
      while (match) { if (caret >= match.index && caret <= match.index + match[0].length) { target = match[1] ? match[1].split('|')[0].split('#')[0] : match[3]; break; } match = pattern.exec(note.content); }
      if (!target) { throw new Error('请将光标放在链接中'); }
      if (/^https?:\/\//i.test(target)) { await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: target }); return true; }
      const found = this.notes.find((item: NoteItem): boolean => item.vaultId === note.vaultId && item.trashedAt === 0 && (item.id === target || item.title === target));
      if (!found) { throw new Error('链接对应的笔记不存在'); }
      if (command === 'link-open-group') { await this.openGroup(found.id); }
      else if (command === 'link-open-window') { await this.context().startAbility({ bundleName: 'com.lovexjy.lexinote', abilityName: 'DocumentAbility', parameters: { noteId: found.id } }); }
      else { this.openDocument(found.id); } return true;
    }
    if (command === 'export-pdf') {
      await this.flushAll(); const note = await LexiStorageService.getNoteById(this.selectedId);
      if (!note) { throw new Error('请先打开笔记'); } await LexiExportService.pdf(this.context(), note); return true;
    }
    if (command === 'open-window' || command === 'move-window') {
      await this.flushAll();
      await this.context().startAbility({ bundleName: 'com.lovexjy.lexinote', abilityName: 'DocumentAbility', parameters: { noteId: this.selectedId } });
      if (command === 'move-window' && editor) { await this.closeDocument(editor); } return true;
    }
    if (command === 'window-pin') { const win = await window.getLastWindow(this.context()); await win.setWindowTopmost(true); return true; }
    if (command === 'focus-editor') { editor?.controller.focus(); return true; }
    if (command === 'template-date' || command === 'template-time') { editor?.controller.format(command === 'template-date' ? 'date' : 'time'); return true; }
    if (command === 'source-toggle') { editor?.controller.format('source-toggle'); return true; }
    if (command === 'back' || command === 'forward') {
      const next = this.navigationCursor + (command === 'back' ? -1 : 1);
      if (next >= 0 && next < this.navigationIds.length) {
        this.navigationCursor = next; this.navigatingHistory = true;
        try { this.openDocument(this.navigationIds[next]); } finally { this.navigatingHistory = false; }
      } return true;
    }
    if (command === 'tab-reopen') { const id = this.closedTabIds.pop(); if (id && this.isTabValid(id)) { this.openDocument(id); } return true; }
    if (command === 'close-others' || command === 'close-all') {
      await this.flushAll();
      const removed = this.tabs.filter((tab: LexiWorkspaceTab): boolean => command === 'close-all' || tab.noteId !== this.selectedId);
      this.closedTabIds = this.closedTabIds.concat(removed.map((tab: LexiWorkspaceTab): string => tab.noteId));
      this.tabs = command === 'close-all' ? [] : this.tabs.filter((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
      if (command === 'close-all') { this.selectedId = ''; } return true;
    }
    if (command === 'split-vertical' || command === 'split-horizontal') { this.splitVertical = command === 'split-vertical'; await this.openGroup(this.selectedId); return true; }
    if (command === 'search-all') { this.openPalette('switcher'); return true; }
    if (command === 'ribbon-toggle') { await LexiInterfaceSettings.setRibbon(!this.showRibbon); return true; }
    if (command.startsWith('zoom-')) { await LexiInterfaceSettings.setZoom(command === 'zoom-reset' ? 100 : (AppStorage.get<number>('lexiInterfaceZoom') || 100) + (command === 'zoom-in' ? 10 : -10)); return true; }
    if (command === 'font-increase' || command === 'font-decrease') { await LexiAppearanceSettings.setFontSize((AppStorage.get<number>('lexiFontSize') || 16) + (command === 'font-increase' ? 1 : -1)); return true; }
    if (command === 'width-toggle') { await LexiEditorSettings.setBool('editorLimitWidth', 'lexiEditorLimitWidth', !(AppStorage.get<boolean>('lexiEditorLimitWidth') ?? true)); return true; }
    if (command === 'default-view-toggle') { await LexiEditorSettings.setString('editorDefaultView', 'lexiEditorDefaultView', AppStorage.get<string>('lexiEditorDefaultView') === 'preview' ? 'edit' : 'preview'); return true; }
    if (command === 'theme-picker') { this.onOpenSettings(); return true; }
    if (command === 'theme-toggle') { await this.onExecuteCommand((await LexiStorageService.getSetting('theme', 'system')) === 'dark' ? 'light' : 'dark', this.selectedId, ''); return true; }
    const panels: string[] = ['rename', 'move-file', 'tag-add', 'alias-add', 'property-add', 'properties-all', 'tags-list', 'history', 'compose-merge', 'compose-selection', 'compose-heading'];
    if (command.startsWith('bookmark') || command.startsWith('database') || panels.includes(command)) {
      await this.flushAll(); this.knowledgeExcerpt = editor ? editor.controller.selection() : '';
      if ((command === 'bookmark-block' || command === 'bookmark-heading') && !this.knowledgeExcerpt && editor) {
        const note = await LexiStorageService.getNoteById(editor.noteId);
        if (note) {
          const prefix = note.content.substring(0, editor.controller.selectionRange().start);
          this.knowledgeExcerpt = command === 'bookmark-heading' ? prefix.split('\n').filter((line: string): boolean => /^#{1,6} /.test(line)).pop() || note.title : prefix.split('\n').pop() || note.title;
        }
      }
      this.knowledgeSelectionStart = editor ? editor.controller.selectionRange().start : 0;
      this.knowledgeSelectionEnd = editor ? editor.controller.selectionRange().end : 0;
      if (command === 'compose-heading' && editor) {
        const note = await LexiStorageService.getNoteById(editor.noteId);
        if (!note) { throw new Error('请先打开笔记'); }
        const lines = note.content.split('\n'); const caretLine = note.content.substring(0, this.knowledgeSelectionStart).split('\n').length - 1;
        let first = caretLine; while (first >= 0 && !/^#{1,6} /.test(lines[first])) { first--; }
        if (first < 0) { throw new Error('当前光标不在标题章节中'); }
        const heading = /^(#{1,6}) /.exec(lines[first]); const level = heading ? heading[1].length : 6;
        let last = first + 1;
        while (last < lines.length) { const nextHeading = /^(#{1,6}) /.exec(lines[last]); if (nextHeading && nextHeading[1].length <= level) { break; } last++; }
        this.knowledgeSelectionStart = lines.slice(0, first).join('\n').length + (first ? 1 : 0);
        this.knowledgeExcerpt = lines.slice(first, last).join('\n');
        this.knowledgeSelectionEnd = this.knowledgeSelectionStart + this.knowledgeExcerpt.length;
      }
      this.knowledgeCommand = command; this.knowledgeRevision++; return true;
    }
    const fileCommands: string[] = ['duplicate', 'copy-path', 'copy-relative-path', 'copy-uri', 'delete-file', 'open-external', 'reveal-file', 'property-clear'];
    if (fileCommands.includes(command)) {
      await this.flushAll(); const note = await LexiStorageService.getNoteById(this.selectedId);
      if (!note) { throw new Error('请先打开笔记'); }
      const target = LexiContextTarget.note(note);
      if (command === 'duplicate') { const copy = await LexiStorageService.duplicateNote(this.context(), note.id); this.onSaved(copy); this.openDocument(copy.id); }
      else if (command === 'delete-file') { await LexiStorageService.setNoteTrash(this.context(), note.id, true); const tab = this.tabs.find((item: LexiWorkspaceTab): boolean => item.noteId === note.id); if (tab) { await this.closeDocument(tab); } const deleted = await LexiStorageService.getNoteById(note.id); if (deleted) { this.onSaved(deleted); } }
      else if (command === 'copy-path' || command === 'copy-relative-path') { await LexiFileActions.copyPath(this.context(), target, command === 'copy-relative-path'); }
      else if (command === 'copy-uri') { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, 'lexinote://open?noteId=' + encodeURIComponent(note.id))); }
      else if (command === 'open-external') { await LexiFileActions.openExternal(this.context(), target); }
      else if (command === 'reveal-file') { await LexiFileActions.reveal(this.context(), target); }
      else if (command === 'property-clear') { note.properties = []; this.onSaved(await LexiStorageService.saveNote(this.context(), note)); }
      return true;
    }
    return false;
  }

  private async executeCommand(command: string, title: string = ''): Promise<void> {
    this.showPalette = false;
    try {
      // Plugin commands are qualified as "<pluginId>:<commandId>" and never live in LEXI_COMMANDS.
      if (PluginCommandRegistry.isPluginCommand(command)) {
        await PluginCommandRegistry.invoke(command);
        return;
      }
      if (await this.extraCommand(command)) { return; }
      if (command === 'palette') { setTimeout((): void => { this.openPalette('commands'); }, 120); return; }
      if (command === 'switcher') { setTimeout((): void => { this.openPalette('switcher'); }, 120); return; }
      if (command === 'sidebar') { this.sidebarOpen = !this.sidebarOpen; return; }
      if (command.startsWith('tab-') && this.tabs.length > 0) {
        const index = this.tabs.findIndex((item: LexiWorkspaceTab): boolean => item.noteId === this.selectedId);
        let next = -1;
        if (command === 'tab-prev') { next = (Math.max(index, 0) + this.tabs.length - 1) % this.tabs.length; }
        else if (command === 'tab-next') { next = (index + 1) % this.tabs.length; }
        else if (command === 'tab-9') { next = this.tabs.length - 1; }
        else { next = Number(command.substring(4)) - 1; }
        if (next >= 0 && next < this.tabs.length) { await this.openDocument(this.tabs[next].noteId); }
        return;
      }
      if (command.startsWith('editor-')) {
        const tab = this.activeEditor();
        if (tab && !tab.noteId.startsWith('map:') && this.activeSection <= 1) {
          tab.controller.format(command.substring(7));
        }
        return;
      }
      if (command === 'reading') {
        const tab = this.tabs.find((item: LexiWorkspaceTab): boolean => item.noteId === this.selectedId);
        if (tab && !this.selectedId.startsWith('map:') && this.activeSection <= 1) { tab.controller.toggleReading(); }
        return;
      }
      await this.flushAll();
      if (command === 'save') { return; }
      if (command === 'split' && this.selectedId) { await this.openGroup(this.selectedId); }
      else if (command === 'close-split') { await this.closeGroup(); }
      else if (command === 'close-tab') {
        const tab = this.tabs.find((item: LexiWorkspaceTab): boolean => item.noteId === this.selectedId);
        if (tab) { await this.closeDocument(tab); }
      } else if (command === 'map') { this.onCreateMap(); }
      else if (command === 'canvas') { this.onCreateCanvas(); }
      else if (command === 'convert' && this.selectedId && !this.selectedId.startsWith('map:')) { this.onConvertMap(this.selectedId); }
      else if (command === 'graph') { await this.showAuxiliary(2); }
      else if (command === 'library') { await this.showAuxiliary(4); }
      else if (command === 'settings') { this.onOpenSettings(); }
      else if (command === 'workspaces') { await this.manageWorkspaces(); }
      else if (command === 'help') { this.onOpenHelp(); }
      else { await this.onExecuteCommand(command, this.selectedId, title); }
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: (error as Error).message || this.tr('操作未完成，当前文档已保留，请重试。') }); }
  }

  private async openFromPalette(id: string): Promise<void> {
    try {
      await this.flushAll(); this.showPalette = false;
      if (id.startsWith('canvas:')) { this.onOpenCanvas(id.substring(7)); }
      else if (!this.onNoteOpenRequest(id)) { this.openDocument(id); }
    } catch { this.getUIContext().getPromptAction().showToast({ message: this.tr('保存未完成，请重试。') }); }
  }

  @Builder
  private paletteSheet() {
    LexiCommandPalette({ mode: this.paletteMode,
      showClose: true,
      notes: this.notes.filter((note: NoteItem): boolean => note.vaultId === this.activeVaultId &&
        (!note.projectId || this.projects.some((project: LexiProject): boolean => project.id === note.projectId))),
      maps: this.maps, canvases: this.canvases,
      onCommand: (command: string): void => { this.executeCommand(command); },
      onOpen: (id: string): void => { this.openFromPalette(id); },
      onCreate: (title: string): void => { this.executeCommand('new-titled', title); },
      onClose: (): void => { this.showPalette = false; } })
  }

  private folders(): string[] {
    const names: string[] = [];
    for (const note of this.visibleNotes()) {
      if (!this.activeProjectId && !this.searchText && note.projectId) { continue; }
      const name = note.notebook || this.tr('未分类');
      if (!names.includes(name)) { names.push(name); }
    }
    return names;
  }

  private folderNotes(folder: string): NoteItem[] {
    return this.visibleNotes().filter((n: NoteItem): boolean => (n.notebook || this.tr('未分类')) === folder);
  }

  private toggleFolder(folder: string): void {
    this.closedFolders = this.closedFolders.includes(folder) ? this.closedFolders.filter((f: string): boolean => f !== folder) :
      this.closedFolders.concat([folder]);
  }

  private tabTitle(noteId: string): string {
    if (noteId.startsWith('map:')) {
      const mapId = noteId.substring(4);
      const map = this.maps.find((m: MindMapDoc): boolean => m.id === mapId);
      return map ? (map.title || this.tr('未命名导图')) : this.tr('思维导图');
    }
    const note = this.notes.find((n: NoteItem): boolean => n.id === noteId);
    return note ? MarkdownEngine.displayTitle(note) : this.tr('无标题笔记');
  }

  @Builder
  private iconButton($$: LexiWorkspaceActionParams) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      LexiIcon({ name: $$.iconName, iconSize: 19, muted: !$$.selected })
    }
    .id(`workspace-action-${$$.iconName}`).width(40).height(40).padding(0).borderRadius(9)
    .backgroundColor($$.selected ? this.palette.workspace_selection : Color.Transparent)
    .accessibilityText($$.label).onClick($$.action)
  }

  @Builder
  private settingsGearButton() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(19)
        .fontColor([this.palette.text_secondary])
    }
    .id('workspace-settings-gear').width(40).height(40).padding(0).borderRadius(9)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.tr('设置')).onClick((): void => { this.onOpenSettings(); })
  }

  @Builder
  private createMenu() {
    Menu() {
      MenuItem({ content: this.tr('笔记') }).onClick((): void => { this.onCreateNote(); })
      MenuItem({ content: this.tr('思维导图') }).onClick((): void => { this.onCreateMap(); })
      MenuItem({ content: this.tr('白板') }).onClick((): void => { this.onCreateCanvas(); })
    }
  }

  @Builder
  private vaultMenu() {
    Menu() {
      MenuItemGroup({ header: this.tr('选择工作区') }) {
      ForEach(this.vaults, (vault: VaultItem) => {
        MenuItem({ content: vault.id === this.activeVaultId ? this.tr('{0} · 当前', [vault.name]) : vault.name })
          .id(`workspace-select-${vault.id}`).enabled(!this.switchingVault)
          .onClick((): void => { this.requestWorkspace(vault.id).catch((): void => {
            this.getUIContext().getPromptAction().showToast({ message: this.tr('读取工作区打开方式失败，请重试。') });
          }); })
      }, (vault: VaultItem): string => vault.id)
      }
      MenuItemGroup({ header: this.tr('当前工作区的项目') }) {
      MenuItem({ content: this.activeProjectId ? this.tr('全部项目') : this.tr('全部项目 · 当前') })
        .onClick((): void => { this.selectProject(''); })
      ForEach(this.projects, (project: LexiProject) => {
        MenuItem({ content: project.id === this.activeProjectId ? this.tr('{0} · 当前', [project.name]) : project.name })
          .onClick((): void => { this.selectProject(project.id); })
      }, (project: LexiProject): string => project.id)
      }
      MenuItem({ content: this.tr('工作区与项目…') }).id('workspace-manager-entry').onClick((): void => { this.manageWorkspaces(); })
      MenuItem({ content: this.tr('文档管理') }).onClick((): void => { this.showAuxiliary(4); })
    }
  }

  @Builder
  private rail() {
    Column({ space: 8 }) {
      if (this.commandVisible('vault')) { this.iconButton({ iconName: 'dock-vault', label: this.tr('知识库'), action: (): void => { this.routingStack.clear(); this.onSelectSection(1); }, selected: this.activeSection <= 1 }) }
      if (this.commandVisible('switcher')) { Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        LexiIcon({ name: 'search', iconSize: 19 })
      }.id('workspace-quick-switcher').width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('快速切换文档'))
        .onClick((): void => { this.openPalette('switcher'); }) }
      if (this.commandVisible('commands')) { Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Text('⌘').fontSize(22).fontColor(this.palette.text_secondary)
      }.id('workspace-command-palette').width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('命令面板'))
        .onClick((): void => { this.openPalette('commands'); }) }
      if (this.commandVisible('reading')) { Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        LexiIcon({ name: 'note', iconSize: 19 })
      }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('切换编辑与阅读'))
        .onClick((): void => { this.executeCommand('reading'); }) }
      if (this.commandVisible('graph')) { this.iconButton({ iconName: 'graph', label: this.tr('笔记关联'), action: (): void => { this.showAuxiliary(2); }, selected: this.activeSection === 2 }) }
      Blank()
      this.iconButton({ iconName: 'trash', label: this.tr('回收站'),
        action: (): void => { this.onOpenTrash(); }, selected: false })
      this.settingsGearButton()
    }
    .width(56).height('100%').padding({ top: 16, bottom: this.inlineContextMenus() ? 10 : 14 }).backgroundColor(this.palette.workspace_rail)
    .border({ width: { right: 0.5 }, color: this.palette.workspace_line })
  }

  @Builder
  private documentRow($$: LexiWorkspaceNoteRowParams) {
    LexiContextSurface({ target: LexiContextTarget.note($$.note), beforeAction: (): Promise<void> => this.flushAll() }) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        LexiIcon({ name: $$.note.noteType === 'study' ? 'study' : 'note', iconSize: 15, muted: this.selectedId !== $$.note.id })
        Text(MarkdownEngine.displayTitle($$.note)).fontSize(13)
          .fontColor(this.selectedId === $$.note.id ? this.palette.brand_ink : this.palette.text_primary)
          .fontWeight(this.selectedId === $$.note.id ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if ($$.note.favorite) { LexiIcon({ name: 'star', iconSize: 12 }); }
      }.width('100%')
    }
    .id(`workspace-note-${$$.note.id}`).width('100%').height(38).padding({ left: 14, right: this.inlineContextMenus() ? 48 : 10 }).borderRadius(7)
    .backgroundColor(this.selectedId === $$.note.id && this.activeSection <= 1 ? this.palette.workspace_selection : Color.Transparent)
    .onClick((): void => { if (!this.onNoteOpenRequest($$.note.id)) { this.openDocument($$.note.id); } })
    }
  }

  @Builder
  private sidebar() {
    Column() {
      LexiContextSurface({ target: LexiContextTarget.scope('workspace', this.activeVaultId, this.activeVaultId, '', this.activeVaultName, this.vaults.find((vault: VaultItem): boolean => vault.id === this.activeVaultId)?.favorite ?? false),
        beforeAction: (): Promise<void> => this.flushAll() }) {
      Row({ space: 8 }) {
        Text(this.tr('知识库')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).layoutWeight(1)
        Text(`${this.visibleNotes().length}`).fontSize(11).fontColor(this.palette.text_secondary)
      }.height(48).width('100%').padding({ left: 6, right: this.inlineContextMenus() ? 44 : 0 })
      }
      Row({ space: 6 }) {
        LexiIcon({ name: 'search', iconSize: 15 })
        TextInput({ text: this.searchText, placeholder: this.tr('搜索 · tag: type: notebook:') })
          .id('workspace-search').layoutWeight(1).height(34).padding(0).fontSize(12)
          .fontColor(this.palette.text_primary).placeholderColor(this.palette.text_secondary)
          .caretColor(this.palette.brand).backgroundColor(Color.Transparent)
          .onChange((text: string): void => { this.searchText = text; })
        if (this.searchText.length > 0) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(10).fontColor([this.palette.text_secondary])
          }.id('workspace-search-clear').width(28).height(32).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText(this.tr('清空搜索')).onClick((): void => { this.searchText = ''; })
        }
      }.width('100%').padding({ left: 10, right: 8 }).borderRadius(7).backgroundColor(this.palette.workspace_page)
        .border({ width: 0.5, color: this.palette.workspace_line }).margin({ bottom: 14 })
      Row({ space: 6 }) {
        Button(this.tr('今日笔记'), { buttonStyle: ButtonStyleMode.TEXTUAL }).id('workspace-daily-note').height(34).fontSize(12)
          .onClick((): void => { this.executeCommand('daily'); })
        Button(this.tr('模板'), { buttonStyle: ButtonStyleMode.TEXTUAL }).id('workspace-templates').height(34).fontSize(12)
          .onClick((): void => { this.executeCommand('templates'); })
      }.width('100%').margin({ bottom: 8 })
      Row({ space: 6 }) {
        Button(this.tr('全部笔记'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(30).fontSize(12).padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10 }).borderRadius(6)
          .fontColor(!this.favoritesOnly ? this.palette.brand_ink : this.palette.text_secondary)
          .backgroundColor(!this.favoritesOnly ? this.palette.workspace_selection : Color.Transparent)
          .onClick((): void => { this.favoritesOnly = false; })
        Button(this.tr('收藏'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(30).fontSize(12).padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10 }).borderRadius(6)
          .fontColor(this.favoritesOnly ? this.palette.brand_ink : this.palette.text_secondary)
          .backgroundColor(this.favoritesOnly ? this.palette.workspace_selection : Color.Transparent)
          .onClick((): void => { this.favoritesOnly = true; })
      }.width('100%').margin({ bottom: 12 })
      Scroll() {
        Column({ space: 4 }) {
          if (!this.activeProjectId && !this.searchText) {
            ForEach(this.projects, (project: LexiProject) => {
              LexiContextSurface({ target: LexiContextTarget.scope('project', project.id, project.vaultId, project.id, project.name, project.favorite),
                beforeAction: (): Promise<void> => this.flushAll() }) {
                Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  Row({ space: 8 }) {
                    LexiIcon({ name: 'folder', iconSize: 16 })
                    Text(project.name).fontSize(13).fontColor(this.palette.text_primary).layoutWeight(1).maxLines(1)
                    if (project.favorite) { LexiIcon({ name: 'star', iconSize: 12 }); }
                    LexiIcon({ name: 'chevron', iconSize: 12 })
                  }.width('100%')
                }.id(`workspace-project-${project.id}`).width('100%').height(40).padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10 })
                  .backgroundColor(Color.Transparent).borderRadius(7).onClick((): void => { this.selectProject(project.id); })
              }
            }, (project: LexiProject): string => `${project.id}-${project.name}-${project.favorite}`)
          }
          ForEach(this.folders(), (folder: string) => {
            Column({ space: 2 }) {
              LexiContextSurface({ target: LexiContextTarget.scope('folder', folder, this.activeVaultId, this.activeProjectId, folder),
                beforeAction: (): Promise<void> => this.flushAll() }) {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 7 }) {
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(9).fontColor([this.palette.text_secondary])
                    .rotate({ angle: this.closedFolders.includes(folder) ? 0 : 90 })
                    .animation({ duration: 150, curve: Curve.EaseOut })
                  LexiIcon({ name: 'folder', iconSize: 15 })
                  Text(folder).fontSize(12).fontColor(this.palette.text_secondary).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Text(`${this.folderNotes(folder).length}`).fontSize(10).fontColor(this.palette.text_secondary)
                }.width('100%')
              }.width('100%').height(36).padding({ left: 5, right: this.inlineContextMenus() ? 48 : 10 }).backgroundColor(Color.Transparent).borderRadius(6)
                .onClick((): void => { this.toggleFolder(folder); })
              }
              if (!this.closedFolders.includes(folder) || this.searchText.trim()) {
                ForEach(this.folderNotes(folder), (note: NoteItem) => { this.documentRow({ note: note }); }, (note: NoteItem): string => `${note.id}-${note.updatedAt}-${note.favorite}`)
              }
            }.width('100%').margin({ bottom: 8 })
          }, (folder: string): string => folder)
          if (this.visibleNotes().length === 0) {
            Text(this.searchText ? this.tr('没有找到匹配的笔记') : this.favoritesOnly ? this.tr('收藏的笔记会出现在这里') : this.tr('写下第一条笔记'))
              .fontSize(12).lineHeight(22).fontColor(this.palette.text_secondary).width('100%').padding(12)
          }
          if (!this.searchText && !this.favoritesOnly) {
            Divider().color(this.palette.workspace_line).margin({ top: 12, bottom: 12 })
            Text(this.tr('可视化空间')).fontSize(11).fontColor(this.palette.text_secondary).width('100%').padding({ left: 6, bottom: 6 })
            ForEach(this.maps.filter((map: MindMapDoc): boolean => map.trashedAt === 0 && (!this.activeProjectId || map.projectId === this.activeProjectId)), (map: MindMapDoc) => {
              LexiContextSurface({ target: LexiContextTarget.scope('mindmap', map.id, map.vaultId, map.projectId || '', map.title),
                beforeAction: (): Promise<void> => this.flushAll() }) {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 8 }) {
                  LexiIcon({ name: 'mindmap', iconSize: 15, muted: this.selectedId !== `map:${map.id}` })
                  Text(map.title || this.tr('未命名导图')).fontSize(12)
                    .fontColor(this.selectedId === `map:${map.id}` ? this.palette.brand_ink : this.palette.text_primary)
                    .fontWeight(this.selectedId === `map:${map.id}` ? FontWeight.Medium : FontWeight.Regular)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
              }.id(`workspace-map-${map.id}`).height(38).width('100%').padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10 })
                .backgroundColor(this.selectedId === `map:${map.id}` && this.activeSection <= 1 ? this.palette.workspace_selection : Color.Transparent)
                .borderRadius(6)
                .onClick((): void => { this.openDocument(`map:${map.id}`); })
              }
            }, (map: MindMapDoc): string => `${map.id}-${map.updatedAt}-${map.title}`)
            ForEach(this.canvases.filter((board: CanvasBoard): boolean => !this.activeProjectId || board.projectId === this.activeProjectId), (board: CanvasBoard) => {
              LexiContextSurface({ target: LexiContextTarget.scope('canvas', board.id, board.vaultId, board.projectId || '', board.title),
                beforeAction: (): Promise<void> => this.flushAll() }) {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 8 }) {
                  LexiIcon({ name: 'canvas', iconSize: 15 })
                  Text(board.title || this.tr('未命名白板')).fontSize(12).fontColor(this.palette.text_primary).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
              }.height(38).width('100%').padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10 }).backgroundColor(Color.Transparent).borderRadius(6)
                .onClick((): void => { this.onOpenCanvas(board.id); })
              }
            }, (board: CanvasBoard): string => `${board.id}-${board.updatedAt}`)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top)
      LexiContextSurface({ target: LexiContextTarget.scope(this.activeProjectId ? 'project' : 'workspace',
        this.activeProjectId || this.activeVaultId, this.activeVaultId, this.activeProjectId,
        this.activeProjectId ? this.activeProjectName : this.activeVaultName, this.activeProjectId ?
          this.projects.find((project: LexiProject): boolean => project.id === this.activeProjectId)?.favorite ?? false :
          this.vaults.find((vault: VaultItem): boolean => vault.id === this.activeVaultId)?.favorite ?? false), beforeAction: (): Promise<void> => this.flushAll() }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          LexiIcon({ name: 'folder', iconSize: 17 })
          Column({ space: 3 }) {
            Text(this.activeVaultName).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.activeProjectName).fontSize(10).fontColor(this.palette.text_secondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([this.palette.text_secondary])
        }.width('100%')
      }.width('100%').height(this.inlineContextMenus() ? 56 : 62).padding({ left: 10, right: this.inlineContextMenus() ? 48 : 10, bottom: this.inlineContextMenus() ? 4 : 0 }).borderRadius(0)
        .backgroundColor(Color.Transparent).border({ width: { top: 0.5 }, color: this.palette.workspace_line })
        .id('workspace-switcher').accessibilityText(this.tr('工作区与项目')).bindMenu(this.vaultMenu())
        .bindSheet($$this.showWorkspaceOpen, this.workspaceOpenSheet, {
          height: 410, width: 440, preferType: SheetType.CENTER, dragBar: false, showClose: false,
          title: { title: this.tr('打开工作区') }, backgroundColor: this.palette.surface,
          shouldDismiss: (sheetDismiss: SheetDismiss): void => { if (!this.switchingVault) { sheetDismiss.dismiss(); } }
        })
      }
    }
    .width(this.sidebarContentWidth()).height('100%').padding({ left: 12, right: 12 }).backgroundColor(this.palette.workspace_sidebar)
  }

  @Builder
  private sidebarResizeHandle() {
    Stack({ alignContent: Alignment.End }) {
      Column().width(this.sidebarResizeHovered || this.sidebarResizing ? 2 : 0.5).height('100%')
        .backgroundColor(this.sidebarResizeHovered || this.sidebarResizing ? this.palette.brand : this.palette.workspace_line)
        .hitTestBehavior(HitTestMode.None)
    }
    .id('workspace-sidebar-resize').width(10).height('100%').backgroundColor(Color.Transparent)
    .accessibilityText(this.tr('拖动调整知识库侧栏宽度'))
    .onHover((hovered: boolean): void => {
      this.sidebarResizeHovered = hovered;
      this.updateSidebarCursor();
    })
    .onDisAppear((): void => { this.clearSidebarResize(); })
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
      .onActionStart((event: GestureEvent): void => {
        this.sidebarDragStartWidth = this.sidebarContentWidth();
        this.sidebarDragWidth = this.sidebarDragStartWidth + event.offsetX;
        this.sidebarResizing = true;
        this.updateSidebarCursor();
      })
      .onActionUpdate((event: GestureEvent): void => {
        if (this.sidebarResizing) { this.sidebarDragWidth = this.sidebarDragStartWidth + event.offsetX; }
      })
      .onActionEnd((event: GestureEvent): void => {
        if (this.sidebarResizing) { this.sidebarDragWidth = this.sidebarDragStartWidth + event.offsetX; }
        this.finishSidebarResize();
      })
      .onActionCancel((): void => { this.finishSidebarResize(); }))
  }

  @Builder
  private rightSidebarResizeHandle() {
    Stack({ alignContent: Alignment.Start }) {
      Column().width(this.rightSidebarResizeHovered || this.rightSidebarResizing ? 2 : 0.5).height('100%')
        .backgroundColor(this.rightSidebarResizeHovered || this.rightSidebarResizing ? this.palette.brand : this.palette.workspace_line)
        .hitTestBehavior(HitTestMode.None)
    }
    .id('workspace-right-sidebar-resize').width(10).height('100%').backgroundColor(Color.Transparent).zIndex(1)
    .accessibilityText(this.tr('拖动调整右侧栏宽度'))
    .onHover((hovered: boolean): void => {
      this.rightSidebarResizeHovered = hovered;
      this.updateSidebarCursor();
    })
    .onDisAppear((): void => { this.clearRightSidebarResize(); })
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
      .onActionStart((event: GestureEvent): void => {
        this.rightSidebarDragStartWidth = this.rightSidebarWidth();
        this.rightSidebarDragWidth = this.rightSidebarDragStartWidth - event.offsetX;
        this.rightSidebarResizing = true;
        this.updateSidebarCursor();
      })
      .onActionUpdate((event: GestureEvent): void => {
        if (this.rightSidebarResizing) { this.rightSidebarDragWidth = this.rightSidebarDragStartWidth - event.offsetX; }
      })
      .onActionEnd((event: GestureEvent): void => {
        if (this.rightSidebarResizing) { this.rightSidebarDragWidth = this.rightSidebarDragStartWidth - event.offsetX; }
        this.finishRightSidebarResize();
      })
      .onActionCancel((): void => { this.finishRightSidebarResize(); }))
  }

  @Builder
  private tabStrip() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(17).fontColor([this.palette.text_secondary])
      }.id('workspace-sidebar-toggle').width(40).height(40).padding(0).borderRadius(7).backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('展开或收起知识库侧栏')).onClick((): void => { this.sidebarOpen = !this.sidebarOpen; })
      if (!this.showRibbon) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(19).fontColor([this.palette.text_secondary])
        }.id('workspace-settings-without-ribbon').width(40).height(40).padding(0)
          .backgroundColor(Color.Transparent).accessibilityText(this.tr('设置'))
          .onClick((): void => { this.onOpenSettings(); })
      }
      Scroll(this.tabScroller) {
        Row({ space: 3 }) {
          ForEach(this.tabs, (tab: LexiWorkspaceTab) => {
            Row({ space: 0 }) {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 8 }) {
                  LexiIcon({ name: tab.noteId.startsWith('map:') ? 'mindmap' : 'note', iconSize: 14, muted: this.selectedId !== tab.noteId })
                  Text(this.tabTitle(tab.noteId)).fontSize(12).fontColor(this.palette.text_primary).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
              }.id(`workspace-tab-${tab.noteId}`).height(38).layoutWeight(1).padding({ left: 14, right: 4 })
                .backgroundColor(Color.Transparent).borderRadius(0).onClick((): void => { this.openDocument(tab.noteId); })
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                SymbolGlyph($r('sys.symbol.xmark')).fontSize(10).fontColor([this.palette.text_secondary])
              }.id(`workspace-close-${tab.noteId}`).width(30).height(34).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText(this.tr('关闭 {0}', [this.tabTitle(tab.noteId)])).onClick((): void => { this.closeDocument(tab); })
            }
            .width(LexiTabStripLayout.tabWidth(this.tabViewportWidth, this.tabs.length)).height(40).clip(true)
            .borderRadius({ topLeft: 8, topRight: 8 })
            .backgroundColor(this.selectedId === tab.noteId && this.activeSection <= 1 ? this.palette.workspace_page : Color.Transparent)
            .border({ width: { top: this.selectedId === tab.noteId && this.activeSection <= 1 ? 2 : 0 }, color: this.palette.brand })
          }, (tab: LexiWorkspaceTab): string => tab.noteId)
        }.width(LexiTabStripLayout.contentWidth(this.tabViewportWidth, this.tabs.length))
          .height('100%').alignItems(VerticalAlign.Bottom)
      }.id('workspace-tab-scroll').layoutWeight(1).height('100%').clip(true)
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
        .onAreaChange((_old: Area, current: Area): void => {
          const measured = Number(current.width);
          if (measured > 0 && Math.abs(measured - this.tabViewportWidth) > 0.5) { this.tabViewportWidth = measured; }
        })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          LexiIcon({ name: 'plus', iconSize: 17 })
          Text(this.tr('新建')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.brand_ink)
        }
      }.id('workspace-create-menu').width(76).height(36).padding({ left: 8, right: 8 }).borderRadius(7)
        .backgroundColor(this.palette.workspace_selection).accessibilityText(this.tr('新建内容')).bindMenu(this.createMenu())
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image(this.rightSidebarOpen ? $r('app.media.ic_dock_panel_shown') : $r('app.media.ic_dock_panel_hidden')).supportSvg2(true).colorFilter(this.palette.text_secondary)
          .width(22).height(22).draggable(false).accessibilityLevel('no')
      }.id('workspace-right-sidebar-toggle').width(36).height(36).padding(0).borderRadius(7)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.tr(this.rightSidebarOpen ? '收起右侧栏' : '展开右侧栏'))
        .onClick((): void => { this.openRightInspector('toggle'); })
    }
    .width('100%').height(52 + this.topInset)
      .padding({ left: 8, right: this.windowButtonsInset > 0 ? this.windowButtonsInset + 4 : 12, top: this.topInset })
    .backgroundColor(this.palette.workspace_tabs)
    .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
  }

  build() {
    Row() {
      LexiKnowledgePanel({ requestRevision: this.knowledgeRevision, command: this.knowledgeCommand, vaultId: this.activeVaultId,
        noteId: this.selectedId, excerpt: this.knowledgeExcerpt, selectionStart: this.knowledgeSelectionStart, selectionEnd: this.knowledgeSelectionEnd, openNoteIds: this.tabs.map((tab: LexiWorkspaceTab): string => tab.noteId),
        onSaved: (note: NoteItem): void => { this.onSaved(note); }, onOpen: (id: string): void => { this.openDocument(id); },
        onSearch: (query: string): void => { this.searchText = query; this.sidebarOpen = true; this.onSelectSection(1); } })
      Stack({ alignContent: Alignment.End }) {
        Column() {
          Row({ space: 10 }) {
            Image($r('app.media.lexi_logo')).width(28).height(28).borderRadius(7)
            if (this.sidebarOpen) {
              Text(this.tr('知萤')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.text_primary)
              Text('LexiNote').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.brand_ink)
              Blank()
            }
          }.width('100%').height(52 + this.topInset).padding({ left: 14, right: 18, top: this.topInset }).backgroundColor(this.palette.workspace_sidebar)
            .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
          Row() {
            if (this.showRibbon) { this.rail() }
            if (this.sidebarOpen) { this.sidebar(); }
          }.width('100%').layoutWeight(1)
        }.width('100%').height('100%')
        if (this.sidebarOpen) { this.sidebarResizeHandle(); }
      }
      .width(this.sidebarWidth()).height('100%')
      .backgroundColor(this.palette.workspace_sidebar).clip(true).zIndex(2)
      .border({ width: { right: 0.5 }, color: this.palette.workspace_line })
      Column() {
        this.tabStrip()
        Row() {
        Navigation(this.routingStack) {
          Flex({ direction: this.splitVertical ? FlexDirection.Column : FlexDirection.Row }) {
          Stack() {
            // Keep document instances mounted when opening auxiliary sections or switching tabs.
              ForEach(this.tabs, (tab: LexiWorkspaceTab) => {
              Column() {
                if (tab.noteId.startsWith('map:')) {
                  LexiWorkspaceMindMap({
                    mapId: tab.noteId.substring(4),
                    editorController: tab.controller,
                    paneWidth: this.editorPaneWidth(),
                    vaultNotes: this.notes,
                    onRequestReadingSpace: (): void => { this.sidebarOpen = false; },
                    onSaved: (doc: MindMapDoc): void => { this.onMapSaved(doc); },
                    onSavedNote: (note: NoteItem): void => { this.onSaved(note); },
                    onOpenNote: (noteId: string): void => { this.openDocument(noteId); }
                  })
                } else {
                  LexiWorkspaceEditor({ noteId: tab.noteId, editorController: tab.controller,
                    continuationActive: this.selectedId === tab.noteId && this.activeSection <= 1 && !this.routeActive,
                    pluginActive: this.selectedId === tab.noteId && this.activeSection <= 1 && !this.routeActive,
                    paneWidth: this.editorPaneWidth(), vaultNotes: this.notes, externalInspector: true,
                    onInspectorChanged: (snapshot: LexiWorkspaceInspectorSnapshot): void => {
                      if (this.selectedId === tab.noteId) { this.inspectorSnapshot = snapshot; }
                    },
                    onRequestInspector: (mode: string): void => { this.openRightInspector(mode); },
                    onRequestReadingSpace: (): void => { this.sidebarOpen = false; },
                    onSaved: (note: NoteItem): void => { this.onSaved(note); },
                    onOpenNote: (noteId: string): void => { this.openDocument(noteId); },
                    onConvertMap: (noteId: string): void => { this.onConvertMap(noteId); },
                    onOpenAdvancedNote: (noteId: string): void => { this.onOpenAdvancedNote(noteId); }
                  })
                }
              }.width('100%').height('100%').visibility(this.selectedId === tab.noteId && this.activeSection <= 1 ? Visibility.Visible : Visibility.Hidden)
            }, (tab: LexiWorkspaceTab): string => tab.noteId)
            if (this.activeSection > 1) {
              this.auxiliaryContent()
            } else if (this.tabs.length === 0 || !this.selectedId) {
              Column({ space: 12 }) {
                LexiIcon({ name: 'note', iconSize: 32 })
                Text(this.tr('选择或新建一篇笔记')).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
                Text(this.tr('从左侧打开已有笔记，或点击右上角“新建”开始记录。')).fontSize(13).fontColor(this.palette.text_secondary)
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
                .backgroundColor(this.palette.workspace_page)
            }
          }.layoutWeight(1).width('100%').height('100%')
          if (this.groupTabs.length > 0 && this.activeSection <= 1) {
            Column() {
              Row() {
                Text(this.tr('标签组')).fontSize(12).fontColor(this.palette.text_secondary).layoutWeight(1)
                Button(this.tr('关闭分组'), { buttonStyle: ButtonStyleMode.TEXTUAL }).height(40).fontSize(12)
                  .fontColor(this.palette.brand).onClick((): void => { this.closeGroup(); })
              }.width('100%').padding({ left: 16, right: 8 })
              Column() {
              ForEach(this.groupTabs, (groupTab: LexiWorkspaceTab) => {
                if (groupTab.noteId.startsWith('map:')) {
                  LexiWorkspaceMindMap({
                    mapId: groupTab.noteId.substring(4),
                    editorController: groupTab.controller,
                    paneWidth: this.editorPaneWidth(),
                    vaultNotes: this.notes,
                    onSaved: (doc: MindMapDoc): void => { this.onMapSaved(doc); },
                    onSavedNote: (note: NoteItem): void => { this.onSaved(note); },
                    onOpenNote: (id: string): void => { this.openGroup(id); }
                  })
                } else {
                  LexiWorkspaceEditor({ noteId: groupTab.noteId, editorController: groupTab.controller,
                    pluginActive: false,
                    continuationActive: false,
                    paneWidth: this.editorPaneWidth(), vaultNotes: this.notes,
                    onSaved: (note: NoteItem): void => { this.onSaved(note); },
                    onOpenNote: (id: string): void => { this.openGroup(id); },
                    onOpenAdvancedNote: (id: string): void => { this.onOpenAdvancedNote(id); } })
                }
              }, (groupTab: LexiWorkspaceTab): string => groupTab.noteId)
              }.width('100%').layoutWeight(1)
            }.layoutWeight(1).height('100%').border({ width: { left: 1 }, color: this.palette.workspace_line })
          }
          }.width('100%').height('100%').visibility(this.routeActive ? Visibility.Hidden : Visibility.Visible)
        }.mode(NavigationMode.Stack).hideTitleBar(true).height('100%').layoutWeight(1).clip(true)
            Stack({ alignContent: Alignment.Start }) {
              LexiWorkspaceRightSidebar({ snapshot: this.currentInspector(), selectedMode: this.rightSidebarMode, sidebarOpen: this.rightSidebarOpen,
                onSelectMode: (mode: string): void => { this.rightSidebarMode = mode; },
                onRevealHeading: (heading: OutlineHeading): void => {
                  const editor = this.tabs.find((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
                  if (editor && this.activeSection <= 1) { editor.controller.revealHeading(heading); }
                },
                onOpenTarget: (target: string): void => {
                  const editor = this.tabs.find((tab: LexiWorkspaceTab): boolean => tab.noteId === this.selectedId);
                  if (editor && this.activeSection <= 1) {
                    editor.controller.openTarget(target).catch((error: Error): void => {
                      this.getUIContext().getPromptAction().showToast({ message: error.message });
                    });
                  }
                },
                onManagePlugins: (): void => { this.onManagePlugins(); }
              })
              if (this.rightSidebarOpen) { this.rightSidebarResizeHandle(); }
            }.width(this.rightSidebarWidth()).height('100%').clip(true)
        }.width('100%').layoutWeight(1)
      }.layoutWeight(1).height('100%')
        .backgroundColor(this.palette.workspace_page).clip(true).zIndex(1)
    }
    .width('100%').height('100%')
    .backgroundColor(this.palette.workspace_page)
    .onAreaChange((_old: Area, current: Area): void => {
      const measured = Number(current.width);
      if (measured > 0 && Math.abs(measured - this.measuredWorkspaceWidth) > 0.5) {
        this.measuredWorkspaceWidth = measured;
        if (this.rightSidebarOpen && measured - this.sidebarWidth() - this.rightSidebarWidth() < 420) {
          this.sidebarOpen = false;
        }
      }
    })
    .onKeyPreIme((event: KeyEvent): boolean => {
      LexiAppearanceSettings.trackModifierKey(event);
      if (PluginKeyboardFocus.active()) { return false; }
      if (event.type !== KeyType.Down || this.routeActive || this.showPalette) { return false; }
      const binding = LexiHotkeySettings.fromEvent(event);
      if (!binding) { return false; }
      const raw = AppStorage.get<string>('lexiHotkeyOverrides') || '[]';
      const matched = LexiHotkeySettings.commandFor(raw, binding);
      if (!matched) { return false; }
      this.executeCommand(matched);
      return true;
    })
    .bindSheet($$this.showPalette, this.paletteSheet, {
      height: Math.max(280, Math.min(560, this.viewportHeight - 140)),
      width: Math.max(420, Math.min(720, this.viewportWidth - 96)),
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      radius: LengthMetrics.vp(16),
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      backgroundColor: this.palette.workspace_page
    })
  }
}
