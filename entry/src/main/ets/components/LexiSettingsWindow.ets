import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiHotkeySettings } from '../core/LexiHotkeySettings';
import { LexiHotkeyRecorder } from '../core/LexiHotkeyRecorder';
import { LexiSystemShortcuts } from '../core/LexiSystemShortcuts';
import { LEXI_COMMANDS, LexiCommand } from '../core/LexiCommands';
import { LexiI18n } from '../core/LexiI18n';
// Obsidian-style settings window: one surface, left category rail, right content pane.
// Appearance, editor, data and about all live here.

import { bundleManager } from '@kit.AbilityKit';
import { CustomTheme } from '@kit.ArkUI';
import { LexiAppearancePicker } from './LexiAppearancePicker';
import { LexiThemePicker } from './LexiThemePicker';
import { LexiAppearanceSettings, LexiCssSnippet } from '../core/LexiAppearanceSettings';
import { LexiInterfaceSettings } from '../core/LexiInterfaceSettings';
import { LexiEditorSettings } from '../core/LexiEditorSettings';
import { LexiStorageService } from '../core/LexiStorageService';
import { LexiFolderStore } from '../core/LexiFolderStore';
import { LexiWorkspacePreferences } from '../core/LexiWorkspacePreferences';
import { LexiIcon } from './LexiIcon';
import { LexiBackHeader } from './LexiBackHeader';
import { LexiPluginSettingsPanel } from '../plugin/ui/LexiPluginSettingsPanel';

class LexiSettingsCategory {
  id: string = '';
  label: string = '';
  icon: string = '';
  glyph: string = '';
}

interface LexiEditorToggleParams {
  label: string;
  description: string;
  checked: boolean;
  key: string;
  storageKey: string;
}

interface LexiSettingTextParams {
  title: string;
  description: string;
}

interface LexiSettingHeaderParams {
  text: string;
}

class LexiRibbonCommandOption {
  id: string = '';
  title: string = '';
  constructor(id: string, title: string) { this.id = id; this.title = title; }
}


class LexiHotkeyRow {
  id: string = '';
  title: string = '';
  source: string = '';
  defaults: string[] = [];
}

@Component
export struct LexiSettingsWindow {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @StorageProp('lexiTopInset') private topInset: number = 0;
  @StorageProp('lexiBottomInset') private bottomInset: number = 0;
  @StorageProp('lexiViewportWidth') private viewportWidth: number = 1200;
  @StorageProp('lexiSettingsStorageAccessBusy') private storageAccessBusy: boolean = false;

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @StorageProp('lexiHotkeyOverrides') private hotkeyOverrides: string = '[]';
  @State private hotkeyQuery: string = '';
  @StorageProp('lexiHotkeyRecording') private recordingHotkey: string = '';
  @StorageProp('lexiHotkeyFeedback') private hotkeyMessage: string = '';
  @StorageProp('lexiEditorDefaultView') private editorDefaultView: string = 'edit';
  @StorageProp('lexiEditorDefaultMode') private editorDefaultMode: string = 'live';
  @StorageProp('lexiEditorShowTitle') private editorShowTitle: boolean = true;
  @StorageProp('lexiEditorLimitWidth') private editorLimitWidth: boolean = true;
  @StorageProp('lexiEditorViewStatus') private editorViewStatus: boolean = true;
  @StorageProp('lexiWorkspaceOpenMode') private workspaceOpenMode: string = 'ask';
  @StorageProp('lexiFontSize') private noteFontSize: number = 16;
  @StorageProp('lexiQuickZoom') private quickZoom: boolean = false;
  @StorageProp('lexiCssSnippets') private snippetsJson: string = '[]';
  @StorageProp('lexiTabHeaders') private showTabHeaders: boolean = true;
  @StorageProp('lexiShowRibbon') private showRibbon: boolean = true;
  @StorageProp('lexiHiddenRibbonCommands') private hiddenRibbonCommands: string = '[]';
  @StorageProp('lexiInterfaceZoom') private interfaceZoom: number = 100;
  @State private showSnippets: boolean = false;
  @State private snippetId: string = '';
  @State private snippetName: string = '';
  @State private snippetCss: string = '';
  @Prop initialCategory: string = 'about';
  @Prop pageMode: boolean = false;
  @Prop workspaceName: string = '';
  @Prop storageLocation: string = 'internal';
  @Prop theme: string = 'system';
  @Prop defaultTier: string = 'simple';
  @Prop busy: boolean = false;
  @Prop dataStatus: string = '';
  onSelectTheme: (theme: string) => void = (_theme: string): void => {};
  onSelectTier: (tier: string) => void = (_tier: string): void => {};
  onExportSettingsPlugins: () => void = (): void => {};
  onImportSettingsPlugins: () => void = (): void => {};
  onExportWorkspaceZip: () => void = (): void => {};
  onImportWorkspaceZip: () => void = (): void => {};
  onExportMarkdown: () => void = (): void => {};
  onImportFiles: () => void = (): void => {};
  onRebuildIndex: () => void = (): void => {};
  onChooseStorage: () => void = (): void => {};
  onOpenHelp: () => void = (): void => {};
  onOpenTrash: () => void = (): void => {};
  onShowInfo: (title: string, message: string) => void = (_title: string, _message: string): void => {};
  onClose: () => void = (): void => {};

  @State private category: string = 'about';
  @State private searchQuery: string = '';
  @State private appVersion: string = '';
  @State private settingsWidth: number = 900;
  @State private phoneRoot: boolean = true;
  @State private phoneMotionReady: boolean = false;
  private phoneTitleTheme(): CustomTheme {
    return {
      colors: { compBackgroundGray: this.palette.background }
    };
  }

  private optionCategories: LexiSettingsCategory[] = [
    { id: 'about', label: '关于', icon: 'info', glyph: '◎' },
    { id: 'appearance', label: '外观', icon: 'sun', glyph: '◐' },
    { id: 'interface', label: '界面', icon: 'canvas', glyph: '▭' },
    { id: 'editor', label: '编辑器', icon: 'note', glyph: '✎' },
    { id: 'data', label: '文件与链接', icon: 'folder', glyph: '❐' },
    { id: 'plugins', label: '插件', icon: 'spark', glyph: '⧉' },
    { id: 'hotkeys', label: '快捷键', icon: 'spark', glyph: '⌘' }
  ];

  aboutToAppear(): void {
    this.category = this.initialCategory.length > 0 ? this.initialCategory : 'about';
    this.phoneRoot = this.initialCategory.length === 0 || this.initialCategory === 'about';
    LexiStorageService.getSetting('workspaceOpenMode', 'ask').then((raw: string): void => {
      AppStorage.setOrCreate('lexiWorkspaceOpenMode', LexiWorkspacePreferences.openMode(raw));
    }).catch((): void => { this.editorSettingError(); });
    try {
      this.appVersion = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch {
      this.appVersion = '';
    }
  }

  aboutToDisappear(): void {
    LexiHotkeyRecorder.cancel();
  }

  private visibleCategories(list: LexiSettingsCategory[]): LexiSettingsCategory[] {    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) {
      return list;
    }
    return list.filter((item: LexiSettingsCategory): boolean => this.tr(item.label).toLowerCase().includes(q));
  }

  private categoryLabel(id: string): string {
    for (const item of this.optionCategories) {
      if (item.id === id) { return this.tr(item.label); }
    }
    if (id === 'ribbon-settings') { return this.tr('功能区'); }
    return this.tr('设置');
  }

  private phoneLayout(): boolean {
    return Math.min(this.settingsWidth, this.viewportWidth) < 560;
  }

  private phoneTitleHeight(): number { return (this.pageMode ? 56 : 48) + this.topInset; }

  private openPhoneCategory(id: string): void {
    this.category = id;
    this.phoneRoot = false;
  }

  private phoneBack(): void {
    if (this.phoneRoot) { this.onClose(); return; }
    this.phoneRoot = true;
  }

  private phoneCategories(): LexiSettingsCategory[] {
    return this.optionCategories.filter((item: LexiSettingsCategory): boolean =>
      item.id !== 'hotkeys' && item.id !== 'interface');
  }

  // Shared visual tokens: phones put white cards on the tinted page background,
  // desktop puts soft cards on the white content pane. Controls nested inside a
  // card use the "inset" colour so they never vanish into the card itself.
  private cardColor(): string { return this.phoneLayout() ? this.palette.surface : this.palette.soft_surface; }

  private insetColor(): string { return this.phoneLayout() ? this.palette.soft_surface : this.palette.workspace_page; }

  private cardRadius(): number { return this.phoneLayout() ? 16 : 12; }

  private cardInset(): number { return this.phoneLayout() ? 16 : 20; }

  @Builder
  private pageTitle($$: LexiSettingHeaderParams) {
    Text($$.text)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.palette.text_primary)
      .width('100%')
      .margin({ bottom: 4 })
  }

  @Builder
  private groupHeader($$: LexiSettingHeaderParams) {
    Text($$.text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette.text_secondary)
      .width('100%')
      .padding({ left: 4, right: 4 })
      .margin({ top: 12 })
  }

  @Builder
  private settingText($$: LexiSettingTextParams) {
    Column({ space: 3 }) {
      Text($$.title)
        .fontSize(this.phoneLayout() ? 15 : 14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text_primary)
      if ($$.description.length > 0) {
        Text($$.description)
          .fontSize(12)
          .lineHeight(17)
          .fontColor(this.palette.text_secondary)
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private rowDivider() {
    Divider().color(this.palette.divider).strokeWidth(0.5)
  }

  @Builder
  private categoryItem(item: LexiSettingsCategory) {
    Row({ space: 10 }) {
      LexiIcon({ name: item.icon, iconSize: 15, muted: this.category !== item.id })
      Text(this.tr(item.label))
        .fontSize(13)
        .fontColor(this.category === item.id ? this.palette.text_primary : this.palette.text_secondary)
        .fontWeight(this.category === item.id ? FontWeight.Medium : FontWeight.Regular)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(`settings-category-${item.id}`)
    .width('100%')
    .height(this.settingsWidth < 560 && this.interfaceLanguage === 'en' ? 44 : 34)
    .padding({ left: 10, right: 8 })
    .borderRadius(8)
    .backgroundColor(this.category === item.id ? this.palette.workspace_selection : Color.Transparent)
    .onClick((): void => { this.category = item.id; })
  }

  private appearanceError(): void {
    this.getUIContext().getPromptAction().showToast({ message: this.tr('外观设置保存失败') });
  }

  private snippets(): LexiCssSnippet[] { return LexiAppearanceSettings.parseSnippets(this.snippetsJson); }

  private saveSnippet(): void {
    const name = this.snippetName.trim();
    if (!name || !this.snippetCss.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('请填写片段名称和 CSS 代码') });
      return;
    }
    const snippets = this.snippets();
    const existing = snippets.find((item: LexiCssSnippet): boolean => item.id === this.snippetId);
    if (existing) { existing.name = name; existing.css = this.snippetCss; }
    else {
      const item = new LexiCssSnippet();
      item.id = `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
      item.name = name; item.css = this.snippetCss; snippets.push(item);
    }
    LexiAppearanceSettings.setSnippets(snippets).then((): void => {
      this.snippetId = ''; this.snippetName = ''; this.snippetCss = '';
    }).catch((): void => { this.appearanceError(); });
  }

  private toggleSnippet(id: string, enabled: boolean): void {
    const snippets = this.snippets();
    const item = snippets.find((entry: LexiCssSnippet): boolean => entry.id === id);
    if (!item) { return; }
    item.enabled = enabled;
    LexiAppearanceSettings.setSnippets(snippets).catch((): void => { this.appearanceError(); });
  }

  @Builder
  private appearanceSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('外观') })
      }
      Column({ space: 14 }) {
        Column({ space: 3 }) {
          Text(this.tr('基础颜色'))
            .fontSize(this.phoneLayout() ? 15 : 14).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
          Text(this.tr('设置应用的明暗外观。')).fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
        }.width('100%').alignItems(HorizontalAlign.Start)
        LexiAppearancePicker({ theme: this.theme, onSelect: (value: string): void => { this.onSelectTheme(value); } })
        this.rowDivider()
        LexiThemePicker()
        this.rowDivider()
        Row({ space: 8 }) {
          this.settingText({
            title: this.tr('CSS 样式代码片段'),
            description: this.tr('已启用 {0} 个 · 应用于增强编辑器',
              [this.snippets().filter((item: LexiCssSnippet): boolean => item.enabled).length.toString()])
          })
          Button(this.showSnippets ? this.tr('收起') : this.tr('管理'), { type: ButtonType.Capsule })
            .id('appearance-snippets').height(30).fontSize(12).fontWeight(FontWeight.Medium)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand)
            .onClick((): void => { this.showSnippets = !this.showSnippets; })
        }.width('100%')
        if (this.showSnippets) {
          ForEach(this.snippets(), (item: LexiCssSnippet) => {
            Row({ space: 6 }) {
              Text(item.name).fontSize(13).fontColor(this.palette.text_primary).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Toggle({ type: ToggleType.Switch, isOn: item.enabled }).selectedColor(this.palette.brand)
                .onChange((on: boolean): void => { this.toggleSnippet(item.id, on); })
              Button(this.tr('编辑'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick((): void => {
                this.snippetId = item.id; this.snippetName = item.name; this.snippetCss = item.css;
              })
              Button(this.tr('删除'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12)
                .fontColor(this.palette.error).onClick((): void => {
                  LexiAppearanceSettings.setSnippets(this.snippets().filter((entry: LexiCssSnippet): boolean => entry.id !== item.id))
                    .catch((): void => { this.appearanceError(); });
                  if (this.snippetId === item.id) { this.snippetId = ''; this.snippetName = ''; this.snippetCss = ''; }
                })
            }.width('100%').padding({ left: 12, right: 4, top: 4, bottom: 4 })
              .backgroundColor(this.insetColor()).borderRadius(10)
          }, (item: LexiCssSnippet): string => item.id)
          TextInput({ text: this.snippetName, placeholder: this.tr('片段名称') }).width('100%').height(40)
            .fontSize(13).borderRadius(10).backgroundColor(this.insetColor()).caretColor(this.palette.brand)
            .onChange((text: string): void => { this.snippetName = text; })
          TextArea({ text: this.snippetCss, placeholder: this.tr('输入 CSS，例如：.markdown-preview-view { line-height: 1.8; }') })
            .width('100%').height(140).fontFamily('monospace').fontSize(12)
            .borderRadius(10).backgroundColor(this.insetColor()).caretColor(this.palette.brand)
            .onChange((text: string): void => { this.snippetCss = text; })
          Row({ space: 8 }) {
            Button(this.snippetId ? this.tr('保存修改') : this.tr('添加片段'), { type: ButtonType.Capsule })
              .height(34).fontSize(13).fontWeight(FontWeight.Medium).padding({ left: 18, right: 18 })
              .backgroundColor(this.palette.brand).fontColor(this.palette.inverse_text)
              .onClick((): void => { this.saveSnippet(); })
            if (this.snippetId) {
              Button(this.tr('取消'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(13).onClick((): void => {
                this.snippetId = ''; this.snippetName = ''; this.snippetCss = '';
              })
            }
          }.width('100%')
        }
      }.width('100%').padding(this.cardInset()).backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
        .alignItems(HorizontalAlign.Start)

      this.groupHeader({ text: this.tr('字体') })
      Column({ space: 0 }) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            this.settingText({ title: this.tr('字体大小'), description: this.tr('调整笔记编辑与预览中的文字大小。') })
            Button(this.tr('重置'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12)
              .onClick((): void => {
                LexiAppearanceSettings.setFontSize(16).catch((): void => { this.appearanceError(); });
              })
            Text(`${this.noteFontSize}`)
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.brand)
              .textAlign(TextAlign.Center).constraintSize({ minWidth: 36 })
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.palette.brand_soft).borderRadius(10)
          }.width('100%')
          Row({ space: 8 }) {
            Text('A').fontSize(12).fontColor(this.palette.text_secondary)
            Slider({ value: this.noteFontSize, min: 10, max: 32, step: 1, style: SliderStyle.OutSet })
              .id('appearance-font-size').layoutWeight(1).selectedColor(this.palette.brand)
              .onChange((value: number, mode: SliderChangeMode): void => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  LexiAppearanceSettings.setFontSize(value).catch((): void => { this.appearanceError(); });
                }
              })
            Text('A').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette.text_secondary)
          }.width('100%')
        }.width('100%').padding({ top: 14, bottom: 10 })
        this.rowDivider()
        Row({ space: 12 }) {
          this.settingText({ title: this.tr('快速调整字体大小'), description: this.tr('开启后，在笔记中使用 Ctrl 与鼠标滚轮调整字号。') })
          Toggle({ type: ToggleType.Switch, isOn: this.quickZoom }).id('appearance-quick-zoom').selectedColor(this.palette.brand)
            .onChange((on: boolean): void => { LexiAppearanceSettings.setQuickZoom(on).catch((): void => { this.appearanceError(); }); })
        }.width('100%').padding({ top: 14, bottom: 14 })
      }.width('100%').padding({ left: this.cardInset(), right: this.cardInset() })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private interfaceError(): void {
    this.getUIContext().getPromptAction().showToast({ message: this.tr('界面设置保存失败，请重试。') });
  }

  private async selectWorkspaceOpenMode(index: number): Promise<void> {
    const mode = LexiWorkspacePreferences.openMode(index === 1 ? 'current' : index === 2 ? 'new' : 'ask');
    try {
      await LexiStorageService.setSetting('workspaceOpenMode', mode);
      AppStorage.setOrCreate('lexiWorkspaceOpenMode', mode);
    } catch { this.editorSettingError(); }
  }

  private ribbonCommands(): LexiRibbonCommandOption[] {
    const commands: LexiRibbonCommandOption[] = [
      new LexiRibbonCommandOption('vault', this.tr('知识库')),
      new LexiRibbonCommandOption('switcher', this.tr('快速切换文档')),
      new LexiRibbonCommandOption('commands', this.tr('命令面板')),
      new LexiRibbonCommandOption('reading', this.tr('切换编辑与阅读')),
      new LexiRibbonCommandOption('graph', this.tr('笔记关联'))
    ];
    return commands;
  }

  @Builder
  private interfaceSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('界面') })
      }
      if (!this.phoneLayout()) {
        Column() {
          Row({ space: 16 }) {
            this.settingText({ title: this.tr('显示标签页标题栏'), description: this.tr('在每个标签页上方显示标题栏。') })
            Toggle({ type: ToggleType.Switch, isOn: this.showTabHeaders }).id('interface-tab-headers')
              .selectedColor(this.palette.brand).accessibilityText(this.tr('显示标签页标题栏'))
              .onChange((on: boolean): void => { LexiInterfaceSettings.setTabHeaders(on).catch((): void => { this.interfaceError(); }); })
          }.width('100%').padding({ top: 14, bottom: 14 })
          this.rowDivider()
          Row({ space: 16 }) {
            this.settingText({ title: this.tr('显示功能区'), description: this.tr('显示窗口最左侧的功能区，以便快速执行命令。') })
            Toggle({ type: ToggleType.Switch, isOn: this.showRibbon }).id('interface-show-ribbon')
              .selectedColor(this.palette.brand).accessibilityText(this.tr('显示功能区'))
              .onChange((on: boolean): void => { LexiInterfaceSettings.setRibbon(on).catch((): void => { this.interfaceError(); }); })
          }.width('100%').padding({ top: 14, bottom: 14 })
          this.rowDivider()
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 16 }) {
              this.settingText({ title: this.tr('功能区'), description: this.tr('设置哪些命令需要显示在功能区上。') })
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([this.palette.text_secondary])
            }.width('100%')
          }.id('interface-ribbon-settings').width('100%').height(68).padding(0)
            .backgroundColor(Color.Transparent).onClick((): void => { this.category = 'ribbon-settings'; })
        }.width('100%').padding({ left: this.cardInset(), right: this.cardInset() })
          .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
      }
      this.groupHeader({ text: this.tr('高级') })
      Column({ space: 8 }) {
        if (this.settingsWidth < 700) {
          Column({ space: 3 }) {
            Text(this.tr('缩放比例')).fontSize(this.phoneLayout() ? 15 : 14).fontWeight(FontWeight.Medium)
              .fontColor(this.palette.text_primary)
            Text(this.tr('控制应用程序的整体缩放比例')).fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
          }.width('100%').alignItems(HorizontalAlign.Start)
          this.zoomControls()
        } else {
          Row({ space: 12 }) {
            this.settingText({ title: this.tr('缩放比例'), description: this.tr('控制应用程序的整体缩放比例') })
            this.zoomControls()
          }.width('100%')
        }
      }.width('100%').padding({ left: this.cardInset(), right: this.cardInset(), top: 14, bottom: 14 })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private zoomControls() {
    Row({ space: 6 }) {
      Button('↺', { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('interface-zoom-reset').width(30).height(30).padding(0).fontSize(16)
        .backgroundColor(this.insetColor()).fontColor(this.palette.text_secondary)
        .accessibilityText(this.tr('重置缩放比例'))
        .onClick((): void => { LexiInterfaceSettings.setZoom(100).catch((): void => { this.interfaceError(); }); })
      Text(`${this.interfaceZoom}%`).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.brand)
        .constraintSize({ minWidth: 44 }).textAlign(TextAlign.Center)
      Slider({ value: this.interfaceZoom, min: 75, max: 150, step: 1, style: SliderStyle.OutSet })
        .id('interface-zoom').width(this.settingsWidth < 560 ? 68 : 140).selectedColor(this.palette.brand)
        .accessibilityText(this.tr('缩放比例'))
        .onChange((amount: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            LexiInterfaceSettings.setZoom(amount).catch((): void => { this.interfaceError(); });
          }
        })
    }.alignItems(VerticalAlign.Center)
  }

  @Builder
  private ribbonSettingsSection() {
    Column({ space: 12 }) {
      Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(14).fontColor([this.palette.brand])
          Text(this.tr('界面')).fontSize(13).fontColor(this.palette.brand)
        }
      }
      .id('ribbon-settings-back').height(30).padding({ left: 8, right: 12 })
      .backgroundColor(this.palette.brand_soft)
      .onClick((): void => { this.category = 'interface'; })
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('功能区') })
      }
      Text(this.tr('选择要显示在功能区上的命令。设置入口始终可用。'))
        .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary).padding({ left: 4, right: 4 })
      Column() {
        ForEach(this.ribbonCommands(), (item: LexiRibbonCommandOption, index: number) => {
          Column() {
            if (index > 0) {
              this.rowDivider()
            }
            Row({ space: 12 }) {
              Text(item.title).fontSize(this.phoneLayout() ? 15 : 14).fontColor(this.palette.text_primary).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: LexiInterfaceSettings.isVisible(this.hiddenRibbonCommands, item.id) })
                .id(`ribbon-command-${item.id}`).selectedColor(this.palette.brand).accessibilityText(item.title)
                .onChange((on: boolean): void => {
                  LexiInterfaceSettings.setCommandVisible(item.id, on).catch((): void => { this.interfaceError(); });
                })
            }.width('100%').padding({ top: 14, bottom: 14 })
          }.width('100%')
        }, (item: LexiRibbonCommandOption): string => item.id)
      }.width('100%').padding({ left: this.cardInset(), right: this.cardInset() })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private editorSettingError(): void {
    this.getUIContext().getPromptAction().showToast({ message: this.tr('编辑器设置保存失败，请重试。') });
  }

  @Builder
  private editorToggle($$: LexiEditorToggleParams) {
    Row({ space: 16 }) {
      this.settingText({ title: this.tr($$.label), description: this.tr($$.description) })
      Toggle({ type: ToggleType.Switch, isOn: $$.checked })
        .id(`settings-${$$.key}`).selectedColor(this.palette.brand).accessibilityText(this.tr($$.label))
        .onChange((on: boolean): void => {
          LexiEditorSettings.setBool($$.key, $$.storageKey, on).catch((): void => { this.editorSettingError(); });
        })
    }.width('100%').padding({ top: 14, bottom: 14 })
  }

  @Builder
  private editorSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('编辑器') })
      }
      Row({ space: 8 }) {
        LexiIcon({ name: 'info', iconSize: 14 }).margin({ top: 1 })
        Column({ space: 2 }) {
          Text(this.tr('以下视图和显示选项适用于标准编辑器。'))
            .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
          Text(this.tr('编辑器设置仅应用于工作区「{0}」。', [this.workspaceName]))
            .id('settings-workspace-scope').fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.palette.brand_soft)
      .borderRadius(12)

      if (!this.phoneLayout()) {
        Column({ space: 10 }) {
          Row() {
            this.settingText({ title: this.tr('工作区打开方式（全局）'),
              description: this.tr('所有工作区共用此打开方式；选择“每次询问”可恢复提示。') })
          }.width('100%')
          Select([{ value: this.tr('每次询问') }, { value: this.tr('在当前窗口打开') }, { value: this.tr('在新窗口打开') }])
            .id('settings-workspace-open-mode').width('100%')
            .font({ size: 13 })
            .selected(this.workspaceOpenMode === 'current' ? 1 : this.workspaceOpenMode === 'new' ? 2 : 0)
            .value(this.workspaceOpenMode === 'current' ? this.tr('在当前窗口打开') :
              this.workspaceOpenMode === 'new' ? this.tr('在新窗口打开') : this.tr('每次询问'))
            .onSelect((index: number): void => { this.selectWorkspaceOpenMode(index); })
        }.width('100%').padding(this.cardInset()).alignItems(HorizontalAlign.Start)
          .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
      }

      Column() {
        Row({ space: 12 }) {
          this.settingText({ title: this.tr('新标签页的默认视图'), description: this.tr('设置新打开笔记的默认视图。') })
          Select([{ value: this.tr('编辑视图') }, { value: this.tr('阅读视图') }])
            .id('settings-editor-default-view').font({ size: 13 })
            .selected(this.editorDefaultView === 'preview' ? 1 : 0)
            .value(this.editorDefaultView === 'preview' ? this.tr('阅读视图') : this.tr('编辑视图'))
            .onSelect((index: number): void => {
              LexiEditorSettings.setString('editorDefaultView', 'lexiEditorDefaultView', index === 1 ? 'preview' : 'edit')
                .catch((): void => { this.editorSettingError(); });
            })
        }.width('100%').padding({ top: 14, bottom: 14 })
        this.rowDivider()
        Row({ space: 12 }) {
          this.settingText({ title: this.tr('默认编辑模式'), description: this.tr('编辑视图中，新打开笔记采用的编辑模式。') })
          Select([{ value: this.tr('实时预览') }, { value: this.tr('源码模式') }])
            .id('settings-editor-default-mode').font({ size: 13 })
            .selected(this.editorDefaultMode === 'source' ? 1 : 0)
            .value(this.editorDefaultMode === 'source' ? this.tr('源码模式') : this.tr('实时预览'))
            .onSelect((index: number): void => {
              LexiEditorSettings.setString('editorDefaultMode', 'lexiEditorDefaultMode', index === 1 ? 'source' : 'live')
                .catch((): void => { this.editorSettingError(); });
            })
        }.width('100%').padding({ top: 14, bottom: 14 })
        this.rowDivider()
        this.editorToggle({ label: '视图状态', description: '在状态栏显示当前视图，并点击切换阅读和编辑。',
          checked: this.editorViewStatus, key: 'editorViewStatus', storageKey: 'lexiEditorViewStatus' })
      }.width('100%').padding({ left: this.cardInset(), right: this.cardInset() })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())

      this.groupHeader({ text: this.tr('显示') })
      Column() {
        this.editorToggle({ label: '页面内标题', description: '在正文上方显示可编辑的笔记标题。',
          checked: this.editorShowTitle, key: 'editorShowTitle', storageKey: 'lexiEditorShowTitle' })
        this.rowDivider()
        this.editorToggle({ label: '限制行宽', description: '限制正文宽度，让较长的段落更易阅读。',
          checked: this.editorLimitWidth, key: 'editorLimitWidth', storageKey: 'lexiEditorLimitWidth' })
      }.width('100%').padding({ left: this.cardInset(), right: this.cardInset() })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())

      this.groupHeader({ text: this.tr('编辑器类型') })
      Column({ space: 12 }) {
        Text(this.tr('默认编辑工具')).fontSize(this.phoneLayout() ? 15 : 14).fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text_primary)
        Row({ space: 4 }) {
          ForEach([['simple', this.tr('简洁')], ['study', this.tr('学习')], ['pro', this.tr('专业')]], (item: string[]) => {
            Button(item[1], { type: ButtonType.Normal }).layoutWeight(1).height(34).fontSize(13).borderRadius(9)
              .fontWeight(this.defaultTier === item[0] ? FontWeight.Medium : FontWeight.Regular)
              .backgroundColor(this.defaultTier === item[0] ? this.palette.brand : Color.Transparent)
              .fontColor(this.defaultTier === item[0] ? this.palette.inverse_text : this.palette.text_primary)
              .onClick((): void => { this.onSelectTier(item[0]); })
          }, (item: string[]): string => item[0])
        }.width('100%').padding(3).backgroundColor(this.insetColor()).borderRadius(12)
      }.width('100%').padding(this.cardInset()).alignItems(HorizontalAlign.Start)
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private storageSection() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Stack() {
          LexiIcon({ name: 'folder', iconSize: 18 })
        }
        .width(36).height(36).borderRadius(10).backgroundColor(this.palette.brand_soft)
        Column({ space: 3 }) {
          Text(this.storageLocation === 'external' ? this.tr('保存位置：文档目录') : this.tr('保存位置：应用内部'))
            .id('settings-storage-location').fontSize(this.phoneLayout() ? 15 : 14).fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
          Text(this.storageLocation === 'external' ? this.tr('笔记以 Markdown 文件保存在文档目录；如授权失效，可重新授权。') :
            this.tr('未授权文档目录，笔记仍可正常保存。卸载应用前请先导出备份。'))
            .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)
      if (!LexiFolderStore.canChooseStorageFolder()) {
        Text(this.tr('此设备使用系统提供的应用文档目录，无需手动选择文件夹。'))
          .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
      }
      Button(this.storageAccessBusy ? this.tr('正在设置保存位置…') :
        this.storageLocation === 'external' ?
          (LexiFolderStore.canChooseStorageFolder() ? this.tr('更改文档目录') : this.tr('重新授权文档目录')) :
          this.tr('授权文档目录'), { type: ButtonType.Normal })
        .id('settings-storage-authorize').width('100%').height(40).fontSize(13).fontWeight(FontWeight.Medium)
        .borderRadius(12)
        .enabled(!this.busy && !this.storageAccessBusy)
        .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand)
        .onClick((): void => { this.onChooseStorage(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private dataSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('数据与备份') })
      }
      Column() {
        this.storageSection()
      }.width('100%').padding(this.cardInset()).backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
      if (this.dataStatus.length > 0) {
        Text(this.dataStatus)
          .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 }).width('100%')
          .backgroundColor(this.palette.brand_soft).borderRadius(12)
      }
      this.groupHeader({ text: this.tr('工作区归档 (.zip)') })
      Column({ space: 10 }) {
        Button(this.tr('导出工作区压缩包 (.zip)'), { type: ButtonType.Normal })
          .id('settings-export-workspace-zip')
          .width('100%').height(44).fontSize(14).fontWeight(FontWeight.Medium).borderRadius(12)
          .enabled(!this.busy)
          .backgroundColor(this.palette.brand)
          .fontColor(this.palette.inverse_text)
          .onClick((): void => { this.onExportWorkspaceZip(); })
        Button(this.tr('导入压缩包到指定文件夹 (.zip)'), { type: ButtonType.Normal })
          .id('settings-import-workspace-zip')
          .width('100%').height(44).fontSize(14).fontWeight(FontWeight.Medium).borderRadius(12)
          .enabled(!this.busy)
          .backgroundColor(this.palette.brand_soft)
          .fontColor(this.palette.brand)
          .onClick((): void => { this.onImportWorkspaceZip(); })
        Row({ space: 10 }) {
          Button(this.tr('导出 Markdown (.md)'), { type: ButtonType.Normal })
            .layoutWeight(1).height(40).fontSize(12).borderRadius(12)
            .enabled(!this.busy)
            .backgroundColor(this.insetColor())
            .fontColor(this.palette.text_primary)
            .onClick((): void => { this.onExportMarkdown(); })
          Button(this.tr('导入笔记'), { type: ButtonType.Normal })
            .layoutWeight(1).height(40).fontSize(12).borderRadius(12)
            .enabled(!this.busy)
            .backgroundColor(this.insetColor())
            .fontColor(this.palette.text_primary)
            .onClick((): void => { this.onImportFiles(); })
          Button(this.tr('重建索引'), { type: ButtonType.Normal })
            .layoutWeight(1).height(40).fontSize(12).borderRadius(12)
            .enabled(!this.busy)
            .backgroundColor(this.insetColor())
            .fontColor(this.palette.text_primary)
            .onClick((): void => { this.onRebuildIndex(); })
        }
        .width('100%')
      }
      .width('100%')
      .padding(this.cardInset())
      .backgroundColor(this.cardColor())
      .borderRadius(this.cardRadius())

      this.groupHeader({ text: this.tr('设置与插件备份 (.json)') })
      Row({ space: 10 }) {
        Button(this.tr('导出设置与插件 (.json)'), { type: ButtonType.Normal })
          .id('settings-export-json')
          .layoutWeight(1).height(40).fontSize(13).borderRadius(12)
          .enabled(!this.busy)
          .backgroundColor(this.palette.brand_soft)
          .fontColor(this.palette.brand)
          .onClick((): void => { this.onExportSettingsPlugins(); })
        Button(this.tr('导入设置与插件 (.json)'), { type: ButtonType.Normal })
          .id('settings-import-json')
          .layoutWeight(1).height(40).fontSize(13).borderRadius(12)
          .enabled(!this.busy)
          .backgroundColor(this.insetColor())
          .fontColor(this.palette.text_primary)
          .onClick((): void => { this.onImportSettingsPlugins(); })
      }
      .width('100%')
      .padding(this.cardInset())
      .backgroundColor(this.cardColor())
      .borderRadius(this.cardRadius())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private aboutSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('关于') })
      }
      Column({ space: 0 }) {
        Row({ space: 16 }) {
          Text(this.tr('版本'))
            .fontSize(this.phoneLayout() ? 15 : 14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
            .layoutWeight(1)
          Text(this.appVersion.length > 0 ? this.appVersion : '—')
            .fontSize(13)
            .fontColor(this.palette.text_secondary)
        }
        .width('100%')
        .height(52)

        this.rowDivider()

        Row({ space: 16 }) {
          Text(this.tr('语言'))
            .fontSize(this.phoneLayout() ? 15 : 14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
            .layoutWeight(1)
          Select([{ value: '简体中文' }, { value: 'English' }])
            .id('settings-language-select')
            .selected(this.interfaceLanguage === 'en' ? 1 : 0)
            .value(this.interfaceLanguage === 'en' ? 'English' : '简体中文')
            .font({ size: 13 })
            .fontColor(this.palette.text_secondary)
            .onSelect((index: number): void => {
              LexiI18n.select(index === 1 ? 'en' : 'zh-Hans').catch((): void => {
                this.getUIContext().getPromptAction().showToast({ message: this.tr('语言切换失败，请重试。') });
              });
            })
        }
        .width('100%')
        .height(56)

        this.rowDivider()

        Row({ space: 16 }) {
          Text(this.tr('使用帮助'))
            .fontSize(this.phoneLayout() ? 15 : 14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
            .layoutWeight(1)
          Button(this.tr('打开'), { type: ButtonType.Capsule })
            .height(30)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.palette.brand_soft)
            .fontColor(this.palette.brand)
            .onClick((): void => { this.onOpenHelp(); })
        }
        .width('100%')
        .height(56)
      }
      .width('100%')
      .padding({ left: this.cardInset(), right: this.cardInset() })
      .backgroundColor(this.cardColor())
      .borderRadius(this.cardRadius())

      this.groupHeader({ text: this.tr('数据与备份') })
      Column() {
        this.storageSection()
      }
      .width('100%')
      .padding(this.cardInset())
      .backgroundColor(this.cardColor())
      .borderRadius(this.cardRadius())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private hotkeyRows(queryText: string = this.hotkeyQuery): LexiHotkeyRow[] {
    const rows: LexiHotkeyRow[] = LEXI_COMMANDS.map((command: LexiCommand): LexiHotkeyRow => {
      return { id: command.id, title: this.tr(command.title), source: this.tr('知萤'),
        defaults: LexiHotkeySettings.defaults(command.id) };
    });
    const query = queryText.trim().toLowerCase();
    return rows.filter((row: LexiHotkeyRow): boolean => !query ||
      (row.title + ' ' + row.source + ' ' + row.id + ' ' +
        LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults).join(' ')).toLowerCase().includes(query))
      .sort((a: LexiHotkeyRow, b: LexiHotkeyRow): number => a.title.localeCompare(b.title));
  }

  private hotkeySystemConflict(row: LexiHotkeyRow): string {
    const binding = LexiSystemShortcuts.firstConflict(
      LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults));
    if (!binding) { return ''; }
    return binding + ' · ' + LexiSystemShortcuts.translatedReason(binding, this.interfaceLanguage);
  }

  private hotkeyConflict(row: LexiHotkeyRow): boolean {
    const bindings = LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults);
    if (bindings.length === 0) { return false; }
    for (const other of this.hotkeyRows('')) {
      if (other.id === row.id) { continue; }
      const occupied = LexiHotkeySettings.bindings(this.hotkeyOverrides, other.id, other.defaults);
      if (bindings.some((binding: string): boolean => occupied.includes(binding))) { return true; }
    }
    return false;
  }

  private beginHotkeyRecording(rowId: string): void {
    LexiHotkeyRecorder.begin(rowId);
  }

  private cancelHotkeyRecording(): void {
    LexiHotkeyRecorder.cancel();
  }

  private async removeHotkey(row: LexiHotkeyRow, binding: string): Promise<void> {
    const next = LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults)
      .filter((item: string): boolean => item !== binding);
    try { await LexiHotkeySettings.set(row.id, next); LexiHotkeyRecorder.notify(''); }
    catch { LexiHotkeyRecorder.notify(this.tr('快捷键保存失败，请重试。')); }
  }

  private async resetHotkey(row: LexiHotkeyRow): Promise<void> {
    for (const other of this.hotkeyRows('')) {
      if (other.id === row.id) { continue; }
      const occupied = LexiHotkeySettings.bindings(this.hotkeyOverrides, other.id, other.defaults);
      if (row.defaults.some((binding: string): boolean => occupied.includes(binding))) {
        LexiHotkeyRecorder.notify(this.tr('快捷键已被占用：') + other.title);
        return;
      }
    }
    try { await LexiHotkeySettings.set(row.id, null); LexiHotkeyRecorder.notify(''); }
    catch { LexiHotkeyRecorder.notify(this.tr('快捷键保存失败，请重试。')); }
  }

  @Builder
  private hotkeySection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: this.tr('快捷键') })
      }
      Text(this.tr('搜索命令，点击「+」后按下组合键；Esc 取消录制。'))
        .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary).width('100%').padding({ left: 4, right: 4 })
      Row({ space: 8 }) {
        LexiIcon({ name: 'search', iconSize: 14, muted: true })
        TextInput({ text: this.hotkeyQuery, placeholder: this.tr('搜索命令或快捷键') })
          .id('hotkeys-search').layoutWeight(1).height(36).padding(0).fontSize(13)
          .fontColor(this.palette.text_primary).placeholderColor(this.palette.text_secondary)
          .caretColor(this.palette.brand).backgroundColor(Color.Transparent)
          .onChange((text: string): void => { this.hotkeyQuery = text; })
      }
      .width('100%').height(38).padding({ left: 12, right: 12 })
      .borderRadius(19).backgroundColor(this.cardColor())
      if (this.hotkeyMessage) {
        Text(this.hotkeyMessage).fontSize(12).fontColor(this.palette.brand).width('100%').padding({ left: 4, right: 4 })
      }
      Column() {
        ForEach(this.hotkeyRows(), (row: LexiHotkeyRow, index: number) => {
          Column() {
            if (index > 0) {
              this.rowDivider()
            }
            Row({ space: 8 }) {
              Column({ space: 3 }) {
                Text(row.title).fontSize(13).fontColor(this.palette.text_primary).width('100%')
                if (row.source !== this.tr('知萤')) {
                  Text(row.source).fontSize(10).fontColor(this.palette.text_secondary).width('100%')
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (this.hotkeyConflict(row)) {
                Text(this.tr('冲突')).fontSize(11).fontColor(this.palette.warning)
              }
              if (this.hotkeySystemConflict(row)) {
                Text(this.tr('系统冲突')).fontSize(11).fontColor(this.palette.warning)
                  .accessibilityText(this.tr('系统冲突') + ' ' + this.hotkeySystemConflict(row))
              }
              if (LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults).length === 0) {
                Text(this.tr('未设置')).fontSize(11).fontColor(this.palette.text_secondary)
              }
              ForEach(LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults), (binding: string) => {
                Button(binding + ' ×', { type: ButtonType.Normal })
                  .fontSize(11).fontFamily('monospace').height(26).padding({ left: 8, right: 8 }).borderRadius(6)
                  .backgroundColor(this.insetColor()).fontColor(this.palette.text_primary)
                  .border({ width: 0.5, color: this.palette.divider })
                  .accessibilityText(this.tr('移除快捷键') + ' ' + binding)
                  .onClick((): void => { this.removeHotkey(row, binding); })
              }, (binding: string): string => binding)
              Button(this.recordingHotkey === row.id ? this.tr('按下快捷键…') : '+', { type: ButtonType.Normal })
                .id(`hotkey-record-${row.id}`).height(26).fontSize(12).padding({ left: 9, right: 9 }).borderRadius(6)
                .backgroundColor(this.recordingHotkey === row.id ? this.palette.brand : this.palette.brand_soft)
                .fontColor(this.recordingHotkey === row.id ? this.palette.inverse_text : this.palette.brand)
                .accessibilityText(this.tr('添加快捷键') + ' ' + row.title)
                .onClick((): void => {
                  if (this.recordingHotkey === row.id) { this.cancelHotkeyRecording(); return; }
                  this.beginHotkeyRecording(row.id);
                })
              Button(this.tr('重置'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
                .fontSize(11).height(26).onClick((): void => {
                  this.resetHotkey(row);
                })
            }.width('100%').padding({ left: 8, right: 4, top: 9, bottom: 9 })
              .borderRadius(8)
              .backgroundColor(this.recordingHotkey === row.id ? this.palette.workspace_selection : Color.Transparent)
          }.width('100%')
        }, (row: LexiHotkeyRow): string => row.id)
      }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.cardColor()).borderRadius(this.cardRadius())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private placeholderCategorySection(title: string) {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        this.pageTitle({ text: title })
      }
      Row({ space: 16 }) {
        this.settingText({ title: this.tr('{0}选项', [title]), description: this.tr('配置与管理「{0}」相关偏好设置。', [title]) })
        Button(this.tr('配置'), { type: ButtonType.Capsule })
          .height(30)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.palette.brand_soft)
          .fontColor(this.palette.brand)
      }
      .width('100%')
      .padding({ left: this.cardInset(), right: this.cardInset(), top: 14, bottom: 14 })
      .backgroundColor(this.cardColor())
      .borderRadius(this.cardRadius())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private phoneHeader() {
    Row({ space: 4 }) {
      if (!this.phoneRoot) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.palette.text_primary])
        }
        .id('settings-phone-back')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('返回设置'))
        .onClick((): void => { this.phoneBack(); })
      } else {
        Blank().width(40).height(40).hitTestBehavior(HitTestMode.None)
      }
      Text(this.phoneRoot ? this.tr('设置') : this.categoryLabel(this.category))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text_primary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .hitTestBehavior(HitTestMode.None)
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(17)
          .fontColor([this.palette.text_secondary])
      }
      .id('settings-phone-close')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.tr('关闭'))
      .onClick((): void => { this.onClose(); })
    }
    .width('100%')
    .height(48 + this.topInset)
    .padding({ left: 6, right: 6, top: this.topInset })
    .backgroundColor(this.palette.workspace_sidebar)
    .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
  }

  @Builder
  private phoneCategoryItem(item: LexiSettingsCategory) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          LexiIcon({ name: item.icon, iconSize: 18 })
        }
        .width(34)
        .height(34)
        .borderRadius(10)
        .backgroundColor(this.palette.brand_soft)
        Text(this.tr(item.label))
          .fontSize(16)
          .fontColor(this.palette.text_primary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.id === 'about' && this.appVersion.length > 0) {
          Text(this.appVersion)
            .fontSize(13)
            .fontColor(this.palette.text_secondary)
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.palette.text_secondary])
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })
    }
    .id(`settings-category-${item.id}`)
    .width('100%')
    .height(60)
    .padding(0)
    .borderRadius(0)
    .backgroundColor(Color.Transparent)
    .onClick((): void => { this.openPhoneCategory(item.id); })
  }

  @Builder
  private phoneCategoryGroup(items: LexiSettingsCategory[]) {
    Column() {
      ForEach(items, (item: LexiSettingsCategory, index: number) => {
        Column() {
          if (index > 0) {
            // Inset divider aligned with the label, like the system settings list.
            Column() {
              this.rowDivider()
            }.width('100%').padding({ left: 62 })
          }
          this.phoneCategoryItem(item)
        }.width('100%')
      }, (item: LexiSettingsCategory): string => item.id)
    }
    .width('100%')
    .backgroundColor(this.palette.surface)
    .borderRadius(16)
    .clip(true)
  }

  @Builder
  private phoneCategoryList() {
    Scroll() {
      Column({ space: 8 }) {
        Text(this.tr('选项'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text_secondary)
          .width('100%')
          .padding({ left: 4, top: 2, bottom: 2 })
        this.phoneCategoryGroup(this.phoneCategories().filter((item: LexiSettingsCategory): boolean => item.id !== 'about'))
        Blank().height(8)
        this.phoneCategoryGroup(this.phoneCategories().filter((item: LexiSettingsCategory): boolean => item.id === 'about'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 24 + this.bottomInset })
      .alignItems(HorizontalAlign.Start)
    }
    .id('settings-phone-category-scroll')
    .width('100%')
    .height('100%')
    .contentStartOffset(this.phoneTitleHeight())
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor(this.palette.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAppear((): void => { this.phoneMotionReady = true; })
    .transition(this.phoneMotionReady
      ? TransitionEffect.move(TransitionEdge.START)
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 220, curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY)
  }

  @Builder
  private categoryContent() {
    Column({ space: 12 }) {
      if (this.category === 'about') {
        this.aboutSection()
      } else if (this.category === 'appearance') {
        this.appearanceSection()
      } else if (this.category === 'interface') {
        this.interfaceSection()
      } else if (this.category === 'ribbon-settings') {
        this.ribbonSettingsSection()
      } else if (this.category === 'editor') {
        this.editorSection()
      } else if (this.category === 'plugins') {
        Row({ space: 8 }) {
          LexiIcon({ name: 'info', iconSize: 14 }).margin({ top: 1 })
          Text(this.tr('插件启用状态与插件设置仅应用于工作区「{0}」。', [this.workspaceName]))
            .id('settings-plugin-workspace-scope').fontSize(12).lineHeight(17)
            .fontColor(this.palette.text_secondary).layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.palette.brand_soft)
        .borderRadius(12)
        LexiPluginSettingsPanel({ cardBackground: this.cardColor(), insetBackground: this.insetColor() })
      } else if (this.category === 'hotkeys') {
        this.hotkeySection()
      } else if (this.category === 'data') {
        this.dataSection()
      } else {
        this.placeholderCategorySection(this.categoryLabel(this.category))
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 820 })
    .padding({
      left: this.phoneLayout() ? 16 : 32,
      right: this.phoneLayout() ? 16 : 32,
      top: this.phoneLayout() ? 16 : 26,
      bottom: this.phoneLayout() ? 28 + this.bottomInset : 32
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private phoneTitleBar() {
    if (this.pageMode) {
      LexiBackHeader({
        title: this.phoneRoot ? this.tr('设置') : this.categoryLabel(this.category),
        subtitle: this.phoneRoot ? this.tr('外观、编辑器、插件与数据') : '',
        tintedBack: true,
        onBack: (): void => { this.phoneBack(); }
      })
    } else {
      this.phoneHeader()
    }
  }

  @Builder
  private phoneSettings() {
    WithTheme({ theme: this.phoneTitleTheme() }) {
      Navigation() {
        if (this.phoneRoot) {
          this.phoneCategoryList()
        } else {
          Scroll() {
            this.categoryContent()
          }
          .id('settings-phone-content-scroll')
          .width('100%')
          .height('100%')
          .contentStartOffset(this.phoneTitleHeight())
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .backgroundColor(this.palette.background)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onAppear((): void => { this.phoneMotionReady = true; })
          .transition(this.phoneMotionReady
            ? TransitionEffect.move(TransitionEdge.END)
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 240, curve: Curve.FastOutSlowIn })
            : TransitionEffect.IDENTITY)
        }
      }
      .id('settings-phone-navigation')
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .titleMode(NavigationTitleMode.Mini)
      .title({ builder: (): void => { this.phoneTitleBar(); }, height: this.phoneTitleHeight() }, {
        backgroundColor: Color.Transparent,
        barStyle: BarStyle.STACK,
        scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
      })
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  build() {
    Column({ space: 0 }) {
      if (this.phoneLayout()) {
        this.phoneSettings()
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Row({ space: 8 }) {
            Blank()
            Button(this.tr('关闭'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('settings-window-close')
              .height(26)
              .padding({ left: 8, right: 8 })
              .fontSize(12)
              .fontColor(this.palette.text_secondary)
              .borderRadius(6)
              .onClick((): void => { this.onClose(); })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 10 })
          .alignItems(VerticalAlign.Center)

          Text(this.tr('设置'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(38)
        .backgroundColor(this.palette.workspace_sidebar)
        .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })

        Row({ space: 0 }) {
          // Left navigation sidebar
          Column({ space: 10 }) {
            Row({ space: 6 }) {
              LexiIcon({ name: 'search', iconSize: 14, muted: true })
              TextInput({ text: this.searchQuery, placeholder: this.tr('搜索设置...') })
                .id('settings-search-input')
                .layoutWeight(1)
                .height(30)
                .padding(0)
                .fontSize(12)
                .fontColor(this.palette.text_primary)
                .placeholderColor(this.palette.text_secondary)
                .caretColor(this.palette.brand)
                .backgroundColor(Color.Transparent)
                .onChange((val: string): void => { this.searchQuery = val; })
            }
            .width('100%')
            .height(32)
            .padding({ left: 10, right: 10 })
            .borderRadius(16)
            .backgroundColor(this.palette.workspace_page)
            .border({ width: 1, color: this.palette.workspace_line })

            Scroll() {
              Column({ space: 2 }) {
                Text(this.tr('选项'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.text_secondary)
                  .padding({ left: 8, top: 6, bottom: 4 })
                  .width('100%')

                ForEach(this.visibleCategories(this.optionCategories), (item: LexiSettingsCategory) => {
                  this.categoryItem(item)
                }, (item: LexiSettingsCategory): string => item.id)

              }
              .width('100%')
              .padding({ bottom: 16 })
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
          }
          .width(216)
          .height('100%')
          .padding({ left: 12, right: 10, top: 12, bottom: 8 })
          .backgroundColor(this.palette.workspace_sidebar)
          .border({ width: { right: 0.5 }, color: this.palette.workspace_line })

          // Right content pane
          Scroll() {
            this.categoryContent()
          }
          .layoutWeight(1)
          .height('100%')
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .backgroundColor(this.palette.workspace_page)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .id('settings-window-root')
    .width('100%')
    .height('100%')
    .clip(true)
    .focusable(true)
    .defaultFocus(true)
    .borderRadius(this.phoneLayout() ? 0 : 12)
    .backgroundColor(this.phoneLayout() ? this.palette.background : this.palette.workspace_page)
    .onAppear((): void => {
      // The full-screen phone sheet cannot host a keyboard focus scope; requesting
      // focus there throws "unfocusable ancestor" and would kill the process.
      if (this.phoneLayout()) { return; }
      try { this.getUIContext().getFocusController().requestFocus('settings-window-root'); } catch { }
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.recordingHotkey) { this.cancelHotkeyRecording(); }
    })
    .onAreaChange((_before: Area, current: Area): void => { this.settingsWidth = Number(current.width); })
  }
}
