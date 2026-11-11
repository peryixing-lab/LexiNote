import { LexiI18n } from '../core/LexiI18n';
import { LexiWorkspaceInspectorSnapshot } from '../core/LexiWorkspaceModels';
import { NoteLink, NoteProperty, OutlineHeading } from '../core/LexiModels';
import { PluginRuntimeController, PluginRuntimeHost } from '../plugin/runtime/PluginRuntimeHost';
import { PluginManager } from '../plugin/core/PluginManager';
import { PluginRecord, PluginState } from '../plugin/model/PluginModels';

/** Installed id of the Harness agent plugin. The entry point only exists after installation. */
const HARNESS_PLUGIN_ID: string = 'lexinote.harness';

/** One workspace sidebar follows the selected document, including unsaved headings. */
@Component
export struct LexiWorkspaceRightSidebar {
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @StorageProp('lexiPluginRevision') @Watch('reloadPlugins') private pluginRevision: number = 0;
  @StorageProp('lexiPluginRuntimeNeeded') private runtimeNeeded: boolean = false;
  @StorageProp('lexiPluginOpenView') @Watch('onOpenViewRequest') private openViewRequest: string = '';
  @Prop sidebarOpen: boolean = false;
  @Prop snapshot: LexiWorkspaceInspectorSnapshot = new LexiWorkspaceInspectorSnapshot();
  @Prop selectedMode: string = 'outline';
  @State private plugins: PluginRecord[] = [];
  @State private loadedPluginId: string = '';
  private requestedPluginId: string = '';
  private disposed: boolean = false;
  @State private busyPluginId: string = '';
  @State private pluginMessage: string = '';
  onSelectMode: (mode: string) => void = (_mode: string): void => {};
  onRevealHeading: (heading: OutlineHeading) => void = (_heading: OutlineHeading): void => {};
  onOpenTarget: (target: string) => void = (_target: string): void => {};
  onManagePlugins: () => void = (): void => {};

  private tr(source: string): string { return LexiI18n.text(source, this.interfaceLanguage); }

  aboutToAppear(): void {
    this.disposed = false;
    this.reloadPlugins();
    this.consumeOpenRequest();
  }

  private reloadPlugins(): void {
    this.plugins = PluginManager.records();
  }

  /** Harness appears only when its plugin is installed; no built-in agent ships in the host. */
  private harnessRecord(): PluginRecord | undefined {
    return this.plugins.find((record: PluginRecord): boolean => record.id === HARNESS_PLUGIN_ID);
  }

  private otherPlugins(): PluginRecord[] {
    return this.plugins.filter((record: PluginRecord): boolean => record.id !== HARNESS_PLUGIN_ID);
  }

  /**
   * A plugin can ask the host to surface its view (`ctx.views.open`). We only react when
   * the plugin is installed, so a request can never open a view that does not exist.
   */
  private consumeOpenRequest(): void {
    if (this.openViewRequest.length === 0 || this.disposed) { return; }
    let pluginId = '';
    try {
      const parsed = JSON.parse(this.openViewRequest) as Record<string, string>;
      if (typeof parsed.pluginId === 'string') { pluginId = parsed.pluginId; }
    } catch (error) {
      return;
    }
    if (pluginId.length === 0) { return; }
    const record = this.plugins.find((item: PluginRecord): boolean => item.id === pluginId);
    if (!record) { return; }
    this.onSelectMode('plugin:' + pluginId);
    this.selectPlugin(record);
  }

  private onOpenViewRequest(): void {
    this.consumeOpenRequest();
  }

  aboutToDisappear(): void { this.disposed = true; this.requestedPluginId = ''; }

  private pluginIcon(record: PluginRecord): Resource {
    if (record.id.toLowerCase().includes('calendar')) { return $r('app.media.ic_sidebar_calendar'); }
    if (record.id.toLowerCase().includes('agent')) { return $r('app.media.ic_star_muted'); }
    return $r('app.media.ic_sidebar_plugin');
  }

  private async selectPlugin(record: PluginRecord): Promise<void> {
    this.onSelectMode('plugin:' + record.id);
    if (!this.busyPluginId && this.loadedPluginId === record.id && record.state === PluginState.ACTIVE) { return; }
    this.requestedPluginId = record.id;
    if (this.busyPluginId) { return; }
    while (this.requestedPluginId && !this.disposed) {
      const pluginId = this.requestedPluginId;
      this.requestedPluginId = '';
      this.busyPluginId = pluginId;
      this.pluginMessage = '';
      this.loadedPluginId = '';
      try {
        PluginManager.requestRuntime();
        const deadline = Date.now() + 5000;
        while (!PluginRuntimeController.isReady() && Date.now() < deadline && !this.disposed) {
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 40); });
        }
        if (this.disposed) { return; }
        await PluginManager.enable(pluginId);
        await PluginRuntimeController.presentPlugin();
        this.loadedPluginId = pluginId;
      } catch (error) {
        this.pluginMessage = (error as Error).message;
      } finally {
        this.busyPluginId = '';
        this.reloadPlugins();
      }
    }
  }

  private selectedPlugin(): PluginRecord | undefined {
    return this.plugins.find((record: PluginRecord): boolean => this.selectedMode === 'plugin:' + record.id);
  }

  private showPluginSurface(): boolean {
    const record = this.selectedPlugin();
    return this.sidebarOpen && !!record && record.state === PluginState.ACTIVE &&
      record.id === this.loadedPluginId && !this.busyPluginId;
  }

  @Builder
  private documentContent() {
    Column({ space: 6 }) {
      if (!this.snapshot.noteId) {
        Text(this.tr('打开一篇笔记以查看大纲。')).fontSize(12).lineHeight(21)
          .fontColor($r('app.color.text_secondary')).width('100%')
      } else {
        Text(this.snapshot.title || this.tr('未命名笔记')).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%').maxLines(2).margin({ bottom: 12 })
        if (this.selectedMode === 'properties') {
          Text(this.tr('笔记属性')).fontSize(12).fontWeight(FontWeight.Medium).width('100%')
            .fontColor($r('app.color.text_primary'))
          if (!this.snapshot.properties.length) {
            Text(this.tr('暂无属性')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
          ForEach(this.snapshot.properties, (prop: NoteProperty) => {
            Text(prop.key + ': ' + prop.propValue).fontSize(12).lineHeight(20).width('100%')
              .fontColor($r('app.color.text_secondary'))
          }, (prop: NoteProperty): string => `${prop.key}-${prop.propValue}`)
        } else if (this.selectedMode === 'outline') {
          if (!this.snapshot.headings.length) {
            Text(this.tr('用 Markdown 标题梳理思路，大纲会出现在这里。')).fontSize(12).lineHeight(21)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }
          ForEach(this.snapshot.headings, (heading: OutlineHeading) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Text(heading.title).fontSize(12).lineHeight(19).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start).width('100%')
                .fontColor($r('app.color.text_primary'))
            }.id(`workspace-right-heading-${heading.id}`).width('100%').constraintSize({ minHeight: 34 })
              .padding({ left: 8 + (heading.level - 1) * 12, right: 8, top: 7, bottom: 7 })
              .backgroundColor(Color.Transparent).borderRadius(6)
              .onClick((): void => { this.onRevealHeading(heading); })
          }, (heading: OutlineHeading): string => `${this.snapshot.noteId}-${heading.id}-${heading.level}-${heading.title}`)
        }
        if (this.selectedMode === 'outline' || this.selectedMode === 'outgoing') {
          Text(this.tr('出链') + ` · ${this.snapshot.outgoing.length}`).fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 22, bottom: 4 })
          ForEach(this.snapshot.outgoing, (link: NoteLink) => {
            Button(link.targetTitle, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(12).fontColor($r('app.color.brand_ink')).width('100%').constraintSize({ minHeight: 34 })
              .padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.onOpenTarget(`${link.targetId || link.targetTitle}${link.anchor ? '#' + link.anchor : ''}`);
              })
          }, (link: NoteLink): string => `${link.sourceId}-${link.targetTitle}-${link.anchor}`)
        }
        if (this.selectedMode === 'outline' || this.selectedMode === 'backlinks') {
          Text(this.tr('反向链接') + ` · ${this.snapshot.backlinks.length}`).fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 22, bottom: 4 })
          ForEach(this.snapshot.backlinks, (link: NoteLink) => {
            Button(link.sourceTitle, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(12).fontColor($r('app.color.brand_ink')).width('100%').constraintSize({ minHeight: 34 })
              .padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent)
              .onClick((): void => { this.onOpenTarget(link.sourceId); })
          }, (link: NoteLink): string => `${link.sourceId}-${link.targetTitle}-${link.anchor}`)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Scroll() {
        Row({ space: 4 }) {
          if (this.harnessRecord()) {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image($r('app.media.ic_star_muted')).width(18).height(18).draggable(false)
            }.id('workspace-right-harness-tab').width(30).height(30).padding(6).borderRadius(5)
              .accessibilityText('Harness')
              .backgroundColor(this.selectedMode === 'plugin:' + HARNESS_PLUGIN_ID
                ? $r('app.color.workspace_selection') : Color.Transparent)
              .onClick((): void => {
                const record = this.harnessRecord();
                if (record) { this.selectPlugin(record); }
              })
          }
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.ic_sidebar_outline')).width(18).height(18).draggable(false)
          }.id('workspace-right-outline-tab').width(30).height(30).padding(6).borderRadius(5)
            .accessibilityText(this.tr('大纲'))
            .backgroundColor(this.selectedMode.indexOf('plugin:') !== 0 ? $r('app.color.workspace_selection') : Color.Transparent)
            .onClick((): void => { this.onSelectMode('outline'); })
          ForEach(this.otherPlugins(), (record: PluginRecord) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image(this.pluginIcon(record)).width(18).height(18).draggable(false)
            }.id('workspace-right-plugin-' + record.id).width(30).height(30).padding(6).borderRadius(5)
              .accessibilityText(record.name || record.id)
              .backgroundColor(this.selectedMode === 'plugin:' + record.id ? $r('app.color.workspace_selection') : Color.Transparent)
              .onClick((): void => { this.selectPlugin(record); })
          }, (record: PluginRecord): string => record.id)
        }.padding({ left: 8, right: 8 })
      }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .border({ width: { bottom: 0.5 }, color: $r('app.color.workspace_line') })
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.runtimeNeeded) {
          PluginRuntimeHost({ surfaceVisible: this.showPluginSurface(), reserveSurfaceSize: true })
        }
        if (this.selectedMode.indexOf('plugin:') !== 0) {
          Scroll() {
            Column() { this.documentContent(); }
              .width('100%').padding({ left: 16, right: 16, top: 20, bottom: 24 })
          }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
            .backgroundColor($r('app.color.workspace_inspector'))
        } else if (!this.showPluginSurface()) {
          Column({ space: 12 }) {
            if (this.busyPluginId) {
              Text(this.tr('正在加载插件…')).fontSize(12).fontColor($r('app.color.text_secondary'))
            } else if (this.pluginMessage) {
              Text(this.pluginMessage).fontSize(12).lineHeight(20).fontColor($r('app.color.error')).width('100%')
              if (this.pluginMessage.includes('E_PERMISSION_DENIED')) {
                Button(this.tr('设置插件权限'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12)
                  .onClick((): void => { this.onManagePlugins(); })
              }
              Button(this.tr('重试'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12)
                .onClick((): void => {
                  const record = this.selectedPlugin();
                  if (record) { this.selectPlugin(record); }
                })
            }
          }.width('100%').height('100%').padding(16).justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.workspace_inspector'))
        }
      }.width('100%').layoutWeight(1)
    }.id('workspace-right-sidebar').width('100%').height('100%')
      .backgroundColor($r('app.color.workspace_inspector'))
      .border({ width: { left: 0.5 }, color: $r('app.color.workspace_line') })
  }
}
