import { LexiHotkeySettings } from '../core/LexiHotkeySettings';
import { LexiHotkeyRecorder } from '../core/LexiHotkeyRecorder';
import { LexiSystemShortcuts } from '../core/LexiSystemShortcuts';
import { LEXI_COMMANDS, LexiCommand } from '../core/LexiCommands';
import { LexiI18n } from '../core/LexiI18n';
// Obsidian-style settings window: one surface, left category rail, right content pane.
// Appearance, editor, data and about all live here.

import { bundleManager } from '@kit.AbilityKit';
import { LexiAppearancePicker } from './LexiAppearancePicker';
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
  @StorageProp('lexiAccent') private accent: string = '#6E44D9';
  @StorageProp('lexiFontSize') private noteFontSize: number = 16;
  @StorageProp('lexiQuickZoom') private quickZoom: boolean = false;
  @StorageProp('lexiCssSnippets') private snippetsJson: string = '[]';
  @StorageProp('lexiTabHeaders') private showTabHeaders: boolean = true;
  @StorageProp('lexiShowRibbon') private showRibbon: boolean = true;
  @StorageProp('lexiHiddenRibbonCommands') private hiddenRibbonCommands: string = '[]';
  @StorageProp('lexiInterfaceZoom') private interfaceZoom: number = 100;
  @State private accentInput: string = '#6E44D9';
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
  @Prop lastBackup: string = '';
  onSelectTheme: (theme: string) => void = (_theme: string): void => {};
  onSelectTier: (tier: string) => void = (_tier: string): void => {};
  onExportBackup: () => void = (): void => {};
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

  private optionCategories: LexiSettingsCategory[] = [
    { id: 'about', label: '关于', icon: 'profile', glyph: '◎' },
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
    this.accentInput = this.accent;
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

  @Builder
  private categoryItem(item: LexiSettingsCategory) {
    Row({ space: 8 }) {
      LexiIcon({ name: item.icon, iconSize: 15, muted: this.category !== item.id })
      Text(this.tr(item.label))
        .fontSize(13)
        .fontColor(this.category === item.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .fontWeight(this.category === item.id ? FontWeight.Medium : FontWeight.Regular)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(`settings-category-${item.id}`)
    .width('100%')
    .height(this.settingsWidth < 560 && this.interfaceLanguage === 'en' ? 44 : 32)
    .padding({ left: 10, right: 8 })
    .borderRadius(6)
    .backgroundColor(this.category === item.id ? $r('app.color.workspace_selection') : Color.Transparent)
    .onClick((): void => { this.category = item.id; })
  }

  private appearanceError(): void {
    this.getUIContext().getPromptAction().showToast({ message: this.tr('外观设置保存失败') });
  }

  private saveAccent(): void {
    const color = this.accentInput.trim();
    if (!LexiAppearanceSettings.validAccent(color)) {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('请输入 6 位十六进制颜色，如 #6E44D9') });
      return;
    }
    LexiAppearanceSettings.setAccent(color).catch((): void => { this.appearanceError(); });
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
    Column({ space: 16 }) {
      if (!this.phoneLayout()) {
        Text(this.tr('外观')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
      Column({ space: 10 }) {
        Text(this.tr('基础颜色')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Text(this.tr('设置应用的明暗外观。')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        LexiAppearancePicker({ theme: this.theme, onSelect: (value: string): void => { this.onSelectTheme(value); } })
        Divider().color($r('app.color.divider')).margin({ top: 4, bottom: 4 })
        Text(this.tr('主题色')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Text(this.tr('用于笔记链接、编辑器控件和增强编辑器中的强调色。')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 8 }) {
          Text(' ').width(28).height(28).borderRadius(14).backgroundColor(this.accent)
          TextInput({ text: this.accentInput, placeholder: '#6E44D9' }).id('appearance-accent').layoutWeight(1).height(38)
            .onChange((text: string): void => { this.accentInput = text; })
          Button(this.tr('应用'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.saveAccent(); })
          Button(this.tr('重置'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
            this.accentInput = LexiAppearanceSettings.DEFAULT_ACCENT; this.saveAccent();
          })
        }.width('100%')
        Row({ space: 10 }) {
          ForEach(['#6E44D9', '#D94B73', '#DC8137', '#308F70', '#3688CD', '#68738A'], (color: string) => {
            Button({ type: ButtonType.Circle }) {
              Text(this.accent.toLowerCase() === color.toLowerCase() ? '✓' : '').fontSize(13).fontColor(Color.White)
            }.width(28).height(28).backgroundColor(color).accessibilityText(`主题色 ${color}`)
              .onClick((): void => { this.accentInput = color; this.saveAccent(); })
          }, (color: string): string => color)
        }.width('100%')
        Divider().color($r('app.color.divider')).margin({ top: 4, bottom: 4 })
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(this.tr('CSS 样式代码片段')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.tr('已启用 {0} 个 · 应用于增强编辑器', [this.snippets().filter((item: LexiCssSnippet): boolean => item.enabled).length.toString()]))
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button(this.showSnippets ? this.tr('收起') : this.tr('管理'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('appearance-snippets').onClick((): void => { this.showSnippets = !this.showSnippets; })
        }.width('100%')
        if (this.showSnippets) {
          ForEach(this.snippets(), (item: LexiCssSnippet) => {
            Row({ space: 6 }) {
              Text(item.name).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(1)
              Toggle({ type: ToggleType.Switch, isOn: item.enabled }).selectedColor(this.accent)
                .onChange((on: boolean): void => { this.toggleSnippet(item.id, on); })
              Button(this.tr('编辑'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
                this.snippetId = item.id; this.snippetName = item.name; this.snippetCss = item.css;
              })
              Button(this.tr('删除'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
                LexiAppearanceSettings.setSnippets(this.snippets().filter((entry: LexiCssSnippet): boolean => entry.id !== item.id))
                  .catch((): void => { this.appearanceError(); });
                if (this.snippetId === item.id) { this.snippetId = ''; this.snippetName = ''; this.snippetCss = ''; }
              })
            }.width('100%')
          }, (item: LexiCssSnippet): string => item.id)
          TextInput({ text: this.snippetName, placeholder: this.tr('片段名称') }).width('100%').height(38)
            .onChange((text: string): void => { this.snippetName = text; })
          TextArea({ text: this.snippetCss, placeholder: this.tr('输入 CSS，例如：.markdown-preview-view { line-height: 1.8; }') })
            .width('100%').height(140).fontFamily('monospace').fontSize(12)
            .onChange((text: string): void => { this.snippetCss = text; })
          Row({ space: 8 }) {
            Button(this.snippetId ? this.tr('保存修改') : this.tr('添加片段'), { type: ButtonType.Normal })
              .backgroundColor(this.accent).onClick((): void => { this.saveSnippet(); })
            if (this.snippetId) {
              Button(this.tr('取消'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
                this.snippetId = ''; this.snippetName = ''; this.snippetCss = '';
              })
            }
          }.width('100%')
        }
      }.width('100%').padding(16).backgroundColor($r('app.color.soft_surface')).borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      Text(this.tr('字体')).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(this.tr('字体大小')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.tr('调整笔记编辑与预览中的文字大小。')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button(this.tr('重置'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
            LexiAppearanceSettings.setFontSize(16).catch((): void => { this.appearanceError(); });
          })
          Text(`${this.noteFontSize}`).fontSize(13).fontColor($r('app.color.text_primary'))
        }.width('100%')
        Slider({ value: this.noteFontSize, min: 10, max: 32, step: 1, style: SliderStyle.OutSet })
          .id('appearance-font-size').width('100%').selectedColor(this.accent)
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              LexiAppearanceSettings.setFontSize(value).catch((): void => { this.appearanceError(); });
            }
          })
        Divider().color($r('app.color.divider'))
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(this.tr('快速调整字体大小')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.tr('开启后，在笔记中使用 Ctrl 与鼠标滚轮调整字号。')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.quickZoom }).id('appearance-quick-zoom').selectedColor(this.accent)
            .onChange((on: boolean): void => { LexiAppearanceSettings.setQuickZoom(on).catch((): void => { this.appearanceError(); }); })
        }.width('100%')
      }.width('100%').padding(16).backgroundColor($r('app.color.soft_surface')).borderRadius(12)
        .alignItems(HorizontalAlign.Start)
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
    Column({ space: 18 }) {
      if (!this.phoneLayout()) {
        Text(this.tr('界面')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
      if (!this.phoneLayout()) {
        Column() {
          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text(this.tr('显示标签页标题栏')).fontSize(14).fontColor($r('app.color.text_primary'))
              Text(this.tr('在每个标签页上方显示标题栏。')).fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.showTabHeaders }).id('interface-tab-headers')
              .selectedColor(this.accent).accessibilityText(this.tr('显示标签页标题栏'))
              .onChange((on: boolean): void => { LexiInterfaceSettings.setTabHeaders(on).catch((): void => { this.interfaceError(); }); })
          }.width('100%').padding({ top: 16, bottom: 16 })
          Divider().color($r('app.color.divider'))
          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text(this.tr('显示功能区')).fontSize(14).fontColor($r('app.color.text_primary'))
              Text(this.tr('显示窗口最左侧的功能区，以便快速执行命令。')).fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.showRibbon }).id('interface-show-ribbon')
              .selectedColor(this.accent).accessibilityText(this.tr('显示功能区'))
              .onChange((on: boolean): void => { LexiInterfaceSettings.setRibbon(on).catch((): void => { this.interfaceError(); }); })
          }.width('100%').padding({ top: 16, bottom: 16 })
          Divider().color($r('app.color.divider'))
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text(this.tr('功能区')).fontSize(14).fontColor($r('app.color.text_primary'))
                Text(this.tr('设置哪些命令需要显示在功能区上。')).fontSize(12).fontColor($r('app.color.text_secondary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('app.color.text_secondary')])
            }.width('100%')
          }.id('interface-ribbon-settings').width('100%').height(72).padding(0)
            .backgroundColor(Color.Transparent).onClick((): void => { this.category = 'ribbon-settings'; })
        }.width('100%').padding({ left: 20, right: 20 }).backgroundColor($r('app.color.soft_surface')).borderRadius(12)
      }
      Text(this.tr('高级')).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Column({ space: 8 }) {
        if (this.settingsWidth < 700) {
          Column({ space: 4 }) {
            Text(this.tr('缩放比例')).fontSize(14).fontColor($r('app.color.text_primary'))
            Text(this.tr('控制应用程序的整体缩放比例')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.width('100%').alignItems(HorizontalAlign.Start)
          this.zoomControls()
        } else {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.tr('缩放比例')).fontSize(14).fontColor($r('app.color.text_primary'))
              Text(this.tr('控制应用程序的整体缩放比例')).fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            this.zoomControls()
          }.width('100%')
        }
      }.width('100%').padding(this.settingsWidth < 560 ? 12 : 20)
        .backgroundColor($r('app.color.soft_surface')).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private zoomControls() {
    Row({ space: 4 }) {
      Button('↺', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('interface-zoom-reset').width(28).height(40).padding(0).fontSize(20)
        .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
        .accessibilityText(this.tr('重置缩放比例'))
        .onClick((): void => { LexiInterfaceSettings.setZoom(100).catch((): void => { this.interfaceError(); }); })
      Text(`${this.interfaceZoom}%`).fontSize(13).fontColor($r('app.color.text_primary'))
      Slider({ value: this.interfaceZoom, min: 75, max: 150, step: 1, style: SliderStyle.OutSet })
        .id('interface-zoom').width(this.settingsWidth < 560 ? 68 : 120).selectedColor(this.accent)
        .accessibilityText(this.tr('缩放比例'))
        .onChange((amount: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            LexiInterfaceSettings.setZoom(amount).catch((): void => { this.interfaceError(); });
          }
        })
    }
  }

  @Builder
  private ribbonSettingsSection() {
    Column({ space: 16 }) {
      Button(this.tr('‹  界面'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('ribbon-settings-back').fontSize(13).fontColor($r('app.color.brand')).backgroundColor(Color.Transparent)
        .onClick((): void => { this.category = 'interface'; })
      if (!this.phoneLayout()) {
        Text(this.tr('功能区')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
      Text(this.tr('选择要显示在功能区上的命令。设置入口始终可用。'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Column() {
        ForEach(this.ribbonCommands(), (item: LexiRibbonCommandOption) => {
          Row({ space: 12 }) {
            Text(item.title).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: LexiInterfaceSettings.isVisible(this.hiddenRibbonCommands, item.id) })
              .id(`ribbon-command-${item.id}`).selectedColor(this.accent).accessibilityText(item.title)
              .onChange((on: boolean): void => {
                LexiInterfaceSettings.setCommandVisible(item.id, on).catch((): void => { this.interfaceError(); });
              })
          }.width('100%').padding({ top: 14, bottom: 14 })
        }, (item: LexiRibbonCommandOption): string => item.id)
      }.width('100%').padding({ left: 20, right: 20 }).backgroundColor($r('app.color.soft_surface')).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private editorSettingError(): void {
    this.getUIContext().getPromptAction().showToast({ message: this.tr('编辑器设置保存失败，请重试。') });
  }

  @Builder
  private editorToggle($$: LexiEditorToggleParams) {
    Row({ space: 16 }) {
      Column({ space: 5 }) {
        Text(this.tr($$.label)).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.tr($$.description)).fontSize(12).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: $$.checked })
        .id(`settings-${$$.key}`).selectedColor(this.accent).accessibilityText(this.tr($$.label))
        .onChange((on: boolean): void => {
          LexiEditorSettings.setBool($$.key, $$.storageKey, on).catch((): void => { this.editorSettingError(); });
        })
    }.width('100%').padding({ top: 16, bottom: 16 })
  }

  @Builder
  private editorSection() {
    Column({ space: 20 }) {
      Text(this.tr('以下视图和显示选项适用于标准编辑器。'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(this.tr('编辑器设置仅应用于工作区「{0}」。', [this.workspaceName]))
        .id('settings-workspace-scope').fontSize(12).fontColor($r('app.color.text_secondary'))
      if (!this.phoneLayout()) {
        Column({ space: 10 }) {
          Text(this.tr('工作区打开方式（全局）')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.tr('所有工作区共用此打开方式；选择“每次询问”可恢复提示。'))
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Select([{ value: this.tr('每次询问') }, { value: this.tr('在当前窗口打开') }, { value: this.tr('在新窗口打开') }])
            .id('settings-workspace-open-mode').width('100%')
            .selected(this.workspaceOpenMode === 'current' ? 1 : this.workspaceOpenMode === 'new' ? 2 : 0)
            .value(this.workspaceOpenMode === 'current' ? this.tr('在当前窗口打开') :
              this.workspaceOpenMode === 'new' ? this.tr('在新窗口打开') : this.tr('每次询问'))
            .onSelect((index: number): void => { this.selectWorkspaceOpenMode(index); })
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.soft_surface')).borderRadius(12)
      }
      Column() {
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(this.tr('新标签页的默认视图')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.tr('设置新打开笔记的默认视图。')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Select([{ value: this.tr('编辑视图') }, { value: this.tr('阅读视图') }])
            .id('settings-editor-default-view').selected(this.editorDefaultView === 'preview' ? 1 : 0)
            .value(this.editorDefaultView === 'preview' ? this.tr('阅读视图') : this.tr('编辑视图'))
            .onSelect((index: number): void => {
              LexiEditorSettings.setString('editorDefaultView', 'lexiEditorDefaultView', index === 1 ? 'preview' : 'edit')
                .catch((): void => { this.editorSettingError(); });
            })
        }.width('100%').padding({ top: 16, bottom: 16 })
        Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(this.tr('默认编辑模式')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.tr('编辑视图中，新打开笔记采用的编辑模式。')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Select([{ value: this.tr('实时预览') }, { value: this.tr('源码模式') }])
            .id('settings-editor-default-mode').selected(this.editorDefaultMode === 'source' ? 1 : 0)
            .value(this.editorDefaultMode === 'source' ? this.tr('源码模式') : this.tr('实时预览'))
            .onSelect((index: number): void => {
              LexiEditorSettings.setString('editorDefaultMode', 'lexiEditorDefaultMode', index === 1 ? 'source' : 'live')
                .catch((): void => { this.editorSettingError(); });
            })
        }.width('100%').padding({ top: 16, bottom: 16 })
        Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)
        this.editorToggle({ label: '视图状态', description: '在状态栏显示当前视图，并点击切换阅读和编辑。',
          checked: this.editorViewStatus, key: 'editorViewStatus', storageKey: 'lexiEditorViewStatus' })
      }.width('100%').padding({ left: 20, right: 20 }).backgroundColor($r('app.color.soft_surface')).borderRadius(12)

      Text(this.tr('显示')).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Column() {
        this.editorToggle({ label: '页面内标题', description: '在正文上方显示可编辑的笔记标题。',
          checked: this.editorShowTitle, key: 'editorShowTitle', storageKey: 'lexiEditorShowTitle' })
        Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)
        this.editorToggle({ label: '限制行宽', description: '限制正文宽度，让较长的段落更易阅读。',
          checked: this.editorLimitWidth, key: 'editorLimitWidth', storageKey: 'lexiEditorLimitWidth' })
      }.width('100%').padding({ left: 20, right: 20 }).backgroundColor($r('app.color.soft_surface')).borderRadius(12)

      Text(this.tr('编辑器类型')).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Column({ space: 12 }) {
        Text(this.tr('默认编辑工具')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Row({ space: 8 }) {
          ForEach([['simple', this.tr('简洁')], ['study', this.tr('学习')], ['pro', this.tr('专业')]], (item: string[]) => {
            Button(item[1], { type: ButtonType.Normal }).layoutWeight(1).height(40).fontSize(13).borderRadius(12)
              .backgroundColor(this.defaultTier === item[0] ? $r('app.color.brand') : $r('app.color.workspace_page'))
              .fontColor(this.defaultTier === item[0] ? $r('app.color.inverse_text') : $r('app.color.text_primary'))
              .onClick((): void => { this.onSelectTier(item[0]); })
          }, (item: string[]): string => item[0])
        }.width('100%')
      }.width('100%').padding(20).backgroundColor($r('app.color.soft_surface')).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private storageSection() {
    Column({ space: 12 }) {
      Text(this.storageLocation === 'external' ? this.tr('保存位置：文档目录') : this.tr('保存位置：应用内部'))
        .id('settings-storage-location').fontSize(13).fontColor($r('app.color.text_primary'))
      Text(this.storageLocation === 'external' ? this.tr('笔记以 Markdown 文件保存在文档目录；如授权失效，可重新授权。') :
        this.tr('未授权文档目录，笔记仍可正常保存。卸载应用前请先导出备份。'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      if (!LexiFolderStore.canChooseStorageFolder()) {
        Text(this.tr('此设备使用系统提供的应用文档目录，无需手动选择文件夹。'))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Button(this.storageAccessBusy ? this.tr('正在设置保存位置…') :
        this.storageLocation === 'external' ?
          (LexiFolderStore.canChooseStorageFolder() ? this.tr('更改文档目录') : this.tr('重新授权文档目录')) :
          this.tr('授权文档目录'), { type: ButtonType.Normal })
        .id('settings-storage-authorize').width('100%').height(42).fontSize(13).borderRadius(12)
        .enabled(!this.busy && !this.storageAccessBusy)
        .backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand'))
        .onClick((): void => { this.onChooseStorage(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private dataSection() {
    Column({ space: 12 }) {
      if (!this.phoneLayout()) {
        Text(this.tr('数据与备份')).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
      this.storageSection()
      if (this.lastBackup.length > 0) {
        Text(this.tr('最近备份：{0}', [this.lastBackup])).fontSize(12).fontColor($r('app.color.brand'))
      }
      if (this.dataStatus.length > 0) {
        Text(this.dataStatus)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
          .padding(10).width('100%')
          .backgroundColor($r('app.color.soft_surface')).borderRadius(10)
      }
      Button(this.tr('导出完整备份 (.json)'), { type: ButtonType.Normal })
        .width('100%').height(42).fontSize(13).borderRadius(12)
        .enabled(!this.busy)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.inverse_text'))
        .onClick((): void => { this.onExportBackup(); })
      Button(this.tr('导出 Markdown 合集 (.md)'), { type: ButtonType.Normal })
        .width('100%').height(42).fontSize(13).borderRadius(12)
        .enabled(!this.busy)
        .backgroundColor($r('app.color.brand_soft'))
        .fontColor($r('app.color.brand'))
        .onClick((): void => { this.onExportMarkdown(); })
      Row({ space: 8 }) {
        Button(this.tr('导入 / 恢复备份'), { type: ButtonType.Normal })
          .layoutWeight(1).height(40).fontSize(12).borderRadius(10)
          .enabled(!this.busy)
          .backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.text_primary'))
          .onClick((): void => { this.onImportFiles(); })
        Button(this.tr('重建索引'), { type: ButtonType.Normal })
          .layoutWeight(1).height(40).fontSize(12).borderRadius(10)
          .enabled(!this.busy)
          .backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.text_primary'))
          .onClick((): void => { this.onRebuildIndex(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private aboutSection() {
    Column({ space: 0 }) {
      Row({ space: 16 }) {
        Text(this.tr('版本'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.appVersion.length > 0 ? this.appVersion : '—')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })

      Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)

      Column() {
        this.storageSection()
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })

      Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)

      Column({ space: 8 }) {
        Text(this.tr('语言'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Select([{ value: '简体中文' }, { value: 'English' }])
          .id('settings-language-select')
          .selected(this.interfaceLanguage === 'en' ? 1 : 0)
          .value(this.interfaceLanguage === 'en' ? 'English' : '简体中文')
          .font({ size: 13 })
          .fontColor($r('app.color.text_secondary'))
          .onSelect((index: number): void => {
            LexiI18n.select(index === 1 ? 'en' : 'zh-Hans').catch((): void => {
              this.getUIContext().getPromptAction().showToast({ message: this.tr('语言切换失败，请重试。') });
            });
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 16, bottom: 16 })

      Divider().color($r('app.color.workspace_line')).strokeWidth(0.5)

      Row({ space: 16 }) {
        Text(this.tr('使用帮助'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button(this.tr('打开'), { type: ButtonType.Normal })
          .height(32)
          .fontSize(12)
          .padding({ left: 16, right: 16 })
          .borderRadius(7)
          .backgroundColor($r('app.color.workspace_selection'))
          .fontColor($r('app.color.text_primary'))
          .onClick((): void => { this.onOpenHelp(); })
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.soft_surface'))
    .borderRadius(12)
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
        Text(this.tr('快捷键')).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      }
      Text(this.tr('搜索命令，点击「+」后按下组合键；Esc 取消录制。'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.hotkeyQuery, placeholder: this.tr('搜索命令或快捷键') })
        .id('hotkeys-search').height(36).fontSize(13).onChange((text: string): void => { this.hotkeyQuery = text; })
      if (this.hotkeyMessage) {
        Text(this.hotkeyMessage).fontSize(12).fontColor($r('app.color.brand')).width('100%')
      }
      ForEach(this.hotkeyRows(), (row: LexiHotkeyRow) => {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(row.title).fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
            if (row.source !== this.tr('知萤')) {
              Text(row.source).fontSize(10).fontColor($r('app.color.text_secondary')).width('100%')
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.hotkeyConflict(row)) {
            Text(this.tr('冲突')).fontSize(11).fontColor($r('app.color.brand'))
          }
          if (this.hotkeySystemConflict(row)) {
            Text(this.tr('系统冲突')).fontSize(11).fontColor($r('app.color.brand'))
              .accessibilityText(this.tr('系统冲突') + ' ' + this.hotkeySystemConflict(row))
          }
          if (LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults).length === 0) {
            Text(this.tr('未设置')).fontSize(11).fontColor($r('app.color.text_secondary'))
          }
          ForEach(LexiHotkeySettings.bindings(this.hotkeyOverrides, row.id, row.defaults), (binding: string) => {
            Button(binding + ' ×', { type: ButtonType.Normal })
              .fontSize(11).height(28).padding({ left: 7, right: 7 }).borderRadius(14)
              .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
              .accessibilityText(this.tr('移除快捷键') + ' ' + binding)
              .onClick((): void => { this.removeHotkey(row, binding); })
          }, (binding: string): string => binding)
          Button(this.recordingHotkey === row.id ? this.tr('按下快捷键…') : '+', { type: ButtonType.Normal })
            .id(`hotkey-record-${row.id}`).height(30).fontSize(12).padding({ left: 9, right: 9 })
            .backgroundColor(this.recordingHotkey === row.id ? $r('app.color.workspace_selection') : $r('app.color.soft_surface'))
            .fontColor($r('app.color.text_primary'))
            .accessibilityText(this.tr('添加快捷键') + ' ' + row.title)
            .onClick((): void => {
              if (this.recordingHotkey === row.id) { this.cancelHotkeyRecording(); return; }
              this.beginHotkeyRecording(row.id);
            })
          Button(this.tr('重置'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontSize(11).height(30).onClick((): void => {
              this.resetHotkey(row);
            })
        }.width('100%').padding({ left: 6, right: 6, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(this.recordingHotkey === row.id ? $r('app.color.workspace_selection') : Color.Transparent)
          .border({ width: { bottom: 0.5 }, color: $r('app.color.workspace_line') })
      }, (row: LexiHotkeyRow): string => row.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private placeholderCategorySection(title: string) {
    Column({ space: 16 }) {
      if (!this.phoneLayout()) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      Column({ space: 0 }) {
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text(this.tr('{0}选项', [title]))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.tr('配置与管理「{0}」相关偏好设置。', [title]))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button(this.tr('配置'), { type: ButtonType.Normal })
            .height(32)
            .fontSize(12)
            .padding({ left: 14, right: 14 })
            .borderRadius(7)
            .backgroundColor($r('app.color.workspace_selection'))
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .backgroundColor($r('app.color.soft_surface'))
      .borderRadius(12)
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
            .fontColor([$r('app.color.text_primary')])
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
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .hitTestBehavior(HitTestMode.None)
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(17)
          .fontColor([$r('app.color.text_secondary')])
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
    .backgroundColor($r('app.color.workspace_sidebar'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.workspace_line') })
  }

  @Builder
  private phoneCategoryItem(item: LexiSettingsCategory) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        Stack() {
          LexiIcon({ name: item.icon, iconSize: 18 })
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor($r('app.color.brand_soft'))
        Text(this.tr(item.label))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .id(`settings-category-${item.id}`)
    .width('100%')
    .padding(0)
    .borderRadius(14)
    .backgroundColor($r('app.color.surface'))
    .onClick((): void => { this.openPhoneCategory(item.id); })
  }

  @Builder
  private phoneCategoryList() {
    Scroll() {
      Column({ space: 8 }) {
        Text(this.tr('选项'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 4, top: 2, bottom: 2 })
        ForEach(this.phoneCategories(), (item: LexiSettingsCategory) => {
          this.phoneCategoryItem(item)
        }, (item: LexiSettingsCategory): string => item.id)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 24 + this.bottomInset })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor($r('app.color.background'))
    .onAppear((): void => { this.phoneMotionReady = true; })
    .transition(this.phoneMotionReady
      ? TransitionEffect.move(TransitionEdge.START)
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 220, curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY)
  }

  @Builder
  private categoryContent() {
    Column({ space: 16 }) {
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
        Text(this.tr('插件启用状态与插件设置仅应用于工作区「{0}」。', [this.workspaceName]))
          .id('settings-plugin-workspace-scope').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        LexiPluginSettingsPanel()
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
      left: this.phoneLayout() ? 16 : 28,
      right: this.phoneLayout() ? 16 : 28,
      top: this.phoneLayout() ? 18 : 22,
      bottom: this.phoneLayout() ? 24 + this.bottomInset : 28
    })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 0 }) {
      if (this.phoneLayout()) {
        if (this.pageMode) {
          Stack() {
            LexiBackHeader({
              title: this.phoneRoot ? this.tr('设置') : this.categoryLabel(this.category),
              subtitle: this.phoneRoot ? this.tr('外观、编辑器、插件与数据') : '',
              tintedBack: true,
              onBack: (): void => { this.phoneBack(); }
            })
          }
          .width('100%')
          .height(56 + this.topInset)
        } else {
          this.phoneHeader()
        }
        if (this.phoneRoot) {
          this.phoneCategoryList()
        } else {
          Scroll() {
            this.categoryContent()
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .backgroundColor($r('app.color.workspace_page'))
          .onAppear((): void => { this.phoneMotionReady = true; })
          .transition(this.phoneMotionReady
            ? TransitionEffect.move(TransitionEdge.END)
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 240, curve: Curve.FastOutSlowIn })
            : TransitionEffect.IDENTITY)
        }
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Row({ space: 8 }) {
            Blank()
            Button(this.tr('关闭'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('settings-window-close')
              .height(26)
              .padding({ left: 8, right: 8 })
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
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
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(38)
        .backgroundColor($r('app.color.workspace_sidebar'))
        .border({ width: { bottom: 0.5 }, color: $r('app.color.workspace_line') })

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
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_secondary'))
                .caretColor($r('app.color.brand'))
                .backgroundColor(Color.Transparent)
                .onChange((val: string): void => { this.searchQuery = val; })
            }
            .width('100%')
            .height(32)
            .padding({ left: 10, right: 10 })
            .borderRadius(16)
            .backgroundColor($r('app.color.workspace_page'))
            .border({ width: 1, color: $r('app.color.workspace_line') })

            Scroll() {
              Column({ space: 2 }) {
                Text(this.tr('选项'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
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
          .backgroundColor($r('app.color.workspace_sidebar'))
          .border({ width: { right: 0.5 }, color: $r('app.color.workspace_line') })

          // Right content pane
          Scroll() {
            this.categoryContent()
          }
          .layoutWeight(1)
          .height('100%')
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .backgroundColor($r('app.color.workspace_page'))
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
    .backgroundColor(this.phoneLayout() ? $r('app.color.background') : $r('app.color.workspace_page'))
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
