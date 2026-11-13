import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiI18n } from '../core/LexiI18n';
import { PluginRuntimeController, PluginRuntimeHost } from '../plugin/runtime/PluginRuntimeHost';
import { PluginManager } from '../plugin/core/PluginManager';
import { PluginRecord } from '../plugin/model/PluginModels';

/** Installed id of the Harness agent plugin. It leads the strip like the desktop sidebar. */
const MOBILE_PLUGIN_HARNESS_ID: string = 'lexinote.harness';
/** Remembers the last plugin opened on this device. It is view state, not a plugin setting. */
const MOBILE_PLUGIN_LAST_ID: string = 'lexiMobilePluginId';

/**
 * Narrow-screen replacement for `LexiWorkspaceRightSidebar`.
 *
 * Phones have no workspace rail, so the installed-plugin surface lives in the half-modal
 * sheet opened from the home page. The outline tab is deliberately absent: its entry moved
 * to the note editor writing bar, next to voice capture, so this panel only carries plugins.
 *
 * The plugin runtime page is mounted here and nowhere else on narrow screens. Closing the
 * sheet tears the ArkWeb page down, so the next visit drops the stale host record and boots
 * the plugin into the fresh page; plugins persist their own state through `plugin.storage`.
 */
@Component
export struct LexiMobilePluginPanel {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @StorageProp('lexiPluginRevision') @Watch('reloadPlugins') private pluginRevision: number = 0;
  @StorageProp('lexiPluginRuntimeNeeded') private runtimeNeeded: boolean = false;
  @State private plugins: PluginRecord[] = [];
  @State private activePluginId: string = '';
  @State private loadedPluginId: string = '';
  @State private busyPluginId: string = '';
  @State private pluginMessage: string = '';
  @State private starting: boolean = false;
  private disposed: boolean = false;
  onManagePlugins: () => void = (): void => {};

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  aboutToAppear(): void {
    this.disposed = false;
    this.reloadPlugins();
    this.start().catch((): void => {});
  }

  aboutToDisappear(): void { this.disposed = true; }

  private reloadPlugins(): void {
    this.plugins = PluginManager.records();
    if (this.activePluginId.length > 0 &&
      !this.plugins.some((record: PluginRecord): boolean => record.id === this.activePluginId)) {
      this.activePluginId = '';
      this.loadedPluginId = '';
      this.pluginMessage = '';
    }
  }

  /** Harness first, then registry order: the same order the desktop sidebar uses. */
  private orderedPlugins(): PluginRecord[] {
    const harness = this.plugins.filter((record: PluginRecord): boolean => record.id === MOBILE_PLUGIN_HARNESS_ID);
    const rest = this.plugins.filter((record: PluginRecord): boolean => record.id !== MOBILE_PLUGIN_HARNESS_ID);
    return harness.concat(rest);
  }

  private preferredPlugin(): PluginRecord | undefined {
    const ordered = this.orderedPlugins();
    if (ordered.length === 0) { return undefined; }
    const rememberedId = AppStorage.get<string>(MOBILE_PLUGIN_LAST_ID) || '';
    const remembered = ordered.find((record: PluginRecord): boolean => record.id === rememberedId);
    return remembered || ordered[0];
  }

  /**
   * The sheet owns the runtime page, so a previous visit can leave a plugin recorded as
   * active while its page is already gone. Drop that record before booting the fresh page.
   */
  private async start(): Promise<void> {
    if (!this.runtimeNeeded) { PluginManager.requestRuntime(); }
    if (this.plugins.length === 0) { return; }
    this.starting = true;
    try {
      if (PluginManager.activeId().length > 0) { await PluginManager.suspendWorkspace(); }
    } catch {
      // A failed suspend only costs a retry; the boot below still runs against the new page.
    }
    if (this.disposed) { return; }
    this.reloadPlugins();
    this.starting = false;
    const target = this.preferredPlugin();
    if (target) { await this.selectPlugin(target); }
  }

  private async selectPlugin(record: PluginRecord): Promise<void> {
    if (this.disposed || this.busyPluginId.length > 0) { return; }
    this.activePluginId = record.id;
    this.busyPluginId = record.id;
    this.loadedPluginId = '';
    this.pluginMessage = '';
    try {
      PluginManager.requestRuntime();
      const deadline = Date.now() + 6000;
      while (!PluginRuntimeController.isReady() && Date.now() < deadline && !this.disposed) {
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 40); });
      }
      if (this.disposed) { return; }
      await PluginManager.enable(record.id);
      if (this.disposed) { return; }
      await PluginRuntimeController.presentPlugin();
      if (this.disposed) { return; }
      this.loadedPluginId = record.id;
      AppStorage.setOrCreate<string>(MOBILE_PLUGIN_LAST_ID, record.id);
    } catch (error) {
      this.pluginMessage = (error as Error).message || this.tr('插件未能启动，请重试');
    } finally {
      if (this.busyPluginId === record.id) { this.busyPluginId = ''; }
      this.reloadPlugins();
    }
  }

  private surfaceVisible(): boolean {
    return this.loadedPluginId.length > 0 && this.loadedPluginId === this.activePluginId &&
      this.busyPluginId.length === 0 && this.pluginMessage.length === 0;
  }

  private pluginIcon(record: PluginRecord): Resource {
    if (record.id.toLowerCase().includes('calendar')) { return $r('app.media.ic_sidebar_calendar'); }
    return $r('app.media.ic_sidebar_plugin');
  }

  private pluginLabel(record: PluginRecord): string {
    return record.name || record.id;
  }

  private pluginSubtitle(record: PluginRecord): string {
    const author = record.author.trim();
    return author.length > 0 ? `${author} · v${record.version}` : `v${record.version}`;
  }

  @Builder
  private tabStrip() {
    Row() {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.orderedPlugins(), (record: PluginRecord) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Row({ space: 6 }) {
                Image(this.pluginIcon(record)).supportSvg2(true).colorFilter(this.palette.text_secondary).width(16).height(16).draggable(false)
                Text(this.pluginLabel(record)).fontSize(13).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(this.activePluginId === record.id ?
                    this.palette.brand_ink : this.palette.text_secondary)
              }
            }
            .id('mobile-plugin-tab-' + record.id).height(36).padding({ left: 12, right: 12 }).borderRadius(10)
            .backgroundColor(this.activePluginId === record.id ? this.palette.brand_soft : this.palette.soft_surface)
            .accessibilityText(this.pluginLabel(record))
            .accessibilitySelected(this.activePluginId === record.id)
            .onClick((): void => { this.selectPlugin(record); })
          }, (record: PluginRecord): string => record.id)
        }.padding({ left: 16, right: 8 })
      }.layoutWeight(1).height('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.gearshape')).fontSize(18).fontColor([this.palette.text_secondary])
      }.id('mobile-plugin-manage').width(40).height(36).padding(0).margin({ right: 7 }).borderRadius(10)
        .backgroundColor(Color.Transparent).accessibilityText(this.tr('管理插件'))
        .onClick((): void => { this.onManagePlugins(); })
    }
    .width('100%').height(54).padding({ left: 0, right: 0 })
    .border({ width: { bottom: 0.5 }, color: this.palette.divider })
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      Column() {
        Image($r('app.media.ic_sidebar_plugin')).supportSvg2(true).colorFilter(this.palette.text_secondary).width(26).height(26).draggable(false)
      }.width(56).height(56).borderRadius(18).backgroundColor(this.palette.soft_surface)
        .justifyContent(FlexAlign.Center)
      Text(this.tr('暂无已安装的插件')).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text_primary)
      Text(this.tr('安装后，插件的视图和命令会出现在这里。')).fontSize(13).lineHeight(21)
        .fontColor(this.palette.text_secondary).textAlign(TextAlign.Center)
      Button(this.tr('管理插件'), { type: ButtonType.Normal })
        .id('mobile-plugin-empty-manage').height(40).padding({ left: 18, right: 18 }).fontSize(14).borderRadius(20)
        .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand_ink)
        .margin({ top: 6 }).onClick((): void => { this.onManagePlugins(); })
    }
    .width('100%').height('100%').padding({ left: 32, right: 32, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private loadingState() {
    Column({ space: 12 }) {
      LoadingProgress().width(30).height(30).color(this.palette.brand)
      Text(this.tr('正在加载插件…')).fontSize(12).fontColor(this.palette.text_secondary)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  private pickerState() {
    Column({ space: 10 }) {
      Text(this.tr('选择一个插件')).fontSize(13).fontColor(this.palette.text_secondary).width('100%')
      ForEach(this.orderedPlugins(), (record: PluginRecord) => {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 10 }) {
            Image(this.pluginIcon(record)).supportSvg2(true).colorFilter(this.palette.text_secondary).width(20).height(20).draggable(false)
            Column({ space: 3 }) {
              Text(this.pluginLabel(record)).fontSize(14).fontColor(this.palette.text_primary).maxLines(1)
              Text(this.pluginSubtitle(record)).fontSize(11)
                .fontColor(this.palette.text_secondary).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([this.palette.text_secondary])
          }.width('100%')
        }
        .id('mobile-plugin-pick-' + record.id).width('100%').height(58).padding({ left: 14, right: 14 }).borderRadius(14)
        .backgroundColor(this.palette.soft_surface).onClick((): void => { this.selectPlugin(record); })
      }, (record: PluginRecord): string => record.id)
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 16 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private errorState() {
    Column({ space: 12 }) {
      Text(this.tr('插件未能启动')).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text_primary)
      Text(this.pluginMessage).fontSize(12).lineHeight(20).fontColor(this.palette.error)
        .textAlign(TextAlign.Center).width('100%')
      Row({ space: 8 }) {
        if (this.pluginMessage.includes('E_PERMISSION_DENIED')) {
          Button(this.tr('设置插件权限'), { type: ButtonType.Normal })
            .id('mobile-plugin-permissions').height(38).padding({ left: 16, right: 16 }).fontSize(13).borderRadius(19)
            .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand_ink)
            .onClick((): void => { this.onManagePlugins(); })
        }
        Button(this.tr('重试'), { type: ButtonType.Normal })
          .id('mobile-plugin-retry').height(38).padding({ left: 18, right: 18 }).fontSize(13).borderRadius(19)
          .backgroundColor(this.palette.soft_surface).fontColor(this.palette.brand_ink)
          .onClick((): void => {
            const record = this.plugins.find((item: PluginRecord): boolean => item.id === this.activePluginId);
            if (record) { this.selectPlugin(record); }
          })
      }.margin({ top: 4 })
    }
    .width('100%').height('100%').padding({ left: 32, right: 32, bottom: 48 }).justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      if (this.plugins.length > 0) { this.tabStrip() }
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.activePluginId.length > 0 && (this.runtimeNeeded || this.busyPluginId.length > 0)) {
          PluginRuntimeHost({ surfaceVisible: this.surfaceVisible(), reserveSurfaceSize: true })
        }
        if (this.plugins.length === 0) {
          this.emptyState()
        } else if (this.starting || this.busyPluginId.length > 0) {
          this.loadingState()
        } else if (this.pluginMessage.length > 0) {
          this.errorState()
        } else if (this.activePluginId.length === 0) {
          this.pickerState()
        }
      }.width('100%').layoutWeight(1)
    }
    .id('mobile-plugin-panel').width('100%').height('100%')
    .backgroundColor(this.palette.surface)
  }
}
