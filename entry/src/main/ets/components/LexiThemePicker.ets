import { LexiAppearanceSettings } from '../core/LexiAppearanceSettings';
import { LexiI18n } from '../core/LexiI18n';
import { LexiTheme, LexiThemeColors, LexiThemePalette, LexiThemePreset } from '../core/LexiTheme';

interface LexiThemeColorRowParams {
  kind: string;
  label: string;
  input: string;
}

@Component
export struct LexiThemePicker {
  @StorageProp('lexiThemePalette') @Watch('syncInputs') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiAccent') private accent: string = LexiTheme.DEFAULT_ACCENT;
  @StorageProp('lexiThemeColors') @Watch('syncInputs') private colorsJson: string = '';
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @State private accentInput: string = LexiTheme.DEFAULT_ACCENT;
  @State private backgroundInput: string = '#FFFFFF';
  @State private foregroundInput: string = '#1A1C1F';
  private editingKind: string = '';

  aboutToAppear(): void { this.syncInputs(); }
  private colors(): LexiThemeColors { return LexiTheme.colors(this.colorsJson, this.accent); }
  private rawColor(kind: string): string {
    const colors = this.colors();
    if (kind === 'accent') { return colors.accent; }
    if (kind === 'background') { return colors.mode === 'custom' && colors.background ? colors.background : this.palette.background; }
    return colors.mode === 'custom' && colors.foreground ? colors.foreground : this.palette.text_primary;
  }
  private syncInputs(): void {
    if (this.editingKind !== 'accent') { this.accentInput = this.rawColor('accent'); }
    if (this.editingKind !== 'background') { this.backgroundInput = this.rawColor('background'); }
    if (this.editingKind !== 'foreground') { this.foregroundInput = this.rawColor('foreground'); }
  }
  private tr(source: string): string { return LexiI18n.text(source, this.interfaceLanguage); }
  private selected(color: string): boolean {
    return this.colors().mode === 'preset' && this.accent.toLowerCase() === color.toLowerCase();
  }
  private activeLabel(): string {
    if (this.colors().mode === 'original') { return this.tr('原配色调'); }
    if (this.colors().mode === 'custom') { return this.tr('自定义'); }
    const preset = LexiTheme.PRESETS.find((item: LexiThemePreset): boolean => this.selected(item.color));
    return this.tr(preset ? preset.label : '自定义');
  }
  private saveError(error: Error): void {
    this.syncInputs();
    const message = error.message === '前景色与背景色对比度不足，请调整颜色' ? error.message : '外观设置保存失败';
    this.getUIContext().getPromptAction().showToast({ message: this.tr(message) });
  }
  private applyColor(color: string): void {
    LexiAppearanceSettings.setAccent(color).then((): void => { this.syncInputs(); })
      .catch((error: Error): void => { this.saveError(error); });
  }
  private applyOriginal(): void {
    LexiAppearanceSettings.setOriginalColors().then((): void => { this.syncInputs(); })
      .catch((error: Error): void => { this.saveError(error); });
  }
  private updateInput(kind: string, text: string): void {
    if (kind === 'accent') { this.accentInput = text; }
    else if (kind === 'background') { this.backgroundInput = text; }
    else { this.foregroundInput = text; }
  }
  private applyCustomInput(kind: string): void {
    const text = kind === 'accent' ? this.accentInput : kind === 'background' ? this.backgroundInput : this.foregroundInput;
    const next = text.trim().toUpperCase();
    if (next === this.rawColor(kind).toUpperCase()) { return; }
    this.applyCustomValue(kind, next);
  }
  private applyCustomValue(kind: string, color: string): void {
    if (!LexiTheme.validAccent(color)) {
      this.syncInputs();
      this.getUIContext().getPromptAction().showToast({ message: this.tr('请输入 6 位十六进制颜色，如 #6E44D9') });
      return;
    }
    LexiAppearanceSettings.setCustomColor(kind, color).then((): void => { this.syncInputs(); })
      .catch((error: Error): void => { this.saveError(error); });
  }

  @Builder
  private accentMenu() {
    Menu() {
      ForEach(LexiTheme.PRESETS, (preset: LexiThemePreset) => {
        MenuItem({ content: this.tr(preset.label) })
          .onClick((): void => { this.applyCustomValue('accent', preset.color); })
      }, (preset: LexiThemePreset): string => preset.color)
    }
  }

  @Builder
  private colorRow($$: LexiThemeColorRowParams) {
    Row({ space: 12 }) {
      Text($$.label).fontSize(13).fontColor(this.palette.text_primary).layoutWeight(1)
      Row({ space: 8 }) {
        Column().width(12).height(12).backgroundColor(this.rawColor($$.kind))
          .border({ width: 0.5, color: this.palette.divider }).borderRadius(6)
          .hitTestBehavior(HitTestMode.None)
        TextInput({ text: $$.input, placeholder: this.rawColor($$.kind) })
          .id('appearance-' + $$.kind).width(92).height(32).maxLength(7).fontSize(12).fontFamily('monospace')
          .fontColor(this.palette.text_primary).backgroundColor(Color.Transparent).caretColor(this.palette.brand).padding(0)
          .accessibilityText($$.label)
          .onChange((text: string): void => { this.updateInput($$.kind, text); })
          .onSubmit((): void => { this.applyCustomInput($$.kind); })
          .onEditChange((editing: boolean): void => {
            this.editingKind = editing ? $$.kind : '';
            if (!editing) { this.applyCustomInput($$.kind); }
          })
        if ($$.kind === 'accent') {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([this.palette.text_secondary])
          }.id('appearance-accent-menu').width(24).height(28).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText(this.tr('选择强调色')).bindMenu(this.accentMenu())
        }
      }.height(34).padding({ left: 10, right: $$.kind === 'accent' ? 5 : 10 })
        .backgroundColor(this.palette.surface).border({ width: 0.5, color: this.palette.divider }).borderRadius(17).clip(true)
    }.width('100%').height(48)
  }

  @Builder
  private preview() {
    Row() {
      Column({ space: 10 }) {
        Text(this.tr('知萤')).fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.palette.brand).width('100%')
        Text(this.tr('笔记')).fontSize(11).fontColor(this.palette.brand).width('100%').padding(6)
          .backgroundColor(this.palette.workspace_selection).borderRadius(5)
        Text(this.tr('文件夹')).fontSize(11).fontColor(this.palette.text_secondary).width('100%').padding({ left: 6 })
      }.width('32%').height('100%').padding(12).alignItems(HorizontalAlign.Start)
        .backgroundColor(this.palette.workspace_sidebar)
      Column({ space: 10 }) {
        Row() {
          Text(this.tr('主题预览')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).layoutWeight(1)
          Text('●').fontSize(12).fontColor(this.palette.brand)
        }.width('100%')
        Divider().color(this.palette.workspace_line)
        Text(this.tr('让灵感拥有你的颜色')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).width('100%')
        Text('[[ ' + this.tr('双向链接') + ' ]]').fontSize(11).fontColor(this.palette.brand).width('100%')
      }.layoutWeight(1).height('100%').padding(14).alignItems(HorizontalAlign.Start)
        .backgroundColor(this.palette.workspace_page)
    }.id('appearance-theme-preview').width('100%').height(132).borderRadius(10).clip(true)
      .border({ width: 1, color: this.palette.workspace_line })
      .accessibilityText(this.tr('主题预览') + ' ' + this.activeLabel())
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(this.tr('全局色调')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).layoutWeight(1)
        Text(this.activeLabel()).fontSize(12).fontColor(this.palette.brand)
      }.width('100%')
      Text(this.tr('统一调整背景、侧栏、按钮和笔记链接，选择后自动保存。'))
        .fontSize(12).fontColor(this.palette.text_secondary).width('100%')
      this.preview()
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 10 }) {
          Column().width(22).height(22).borderRadius(11).backgroundColor(LexiTheme.DEFAULT_ACCENT)
          Text(this.tr('原配色调')).fontSize(13).fontColor(this.palette.text_primary).layoutWeight(1).textAlign(TextAlign.Start)
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([this.palette.brand])
            .opacity(this.colors().mode === 'original' ? 1 : 0)
        }.width('100%')
      }.id('appearance-original').width('100%').height(44).padding({ left: 14, right: 14 })
        .backgroundColor(this.colors().mode === 'original' ? this.palette.workspace_selection : this.palette.surface)
        .border({ width: 1, color: this.colors().mode === 'original' ? this.palette.brand : this.palette.divider })
        .borderRadius(14).clip(true).accessibilityText(this.tr('原配色调'))
        .accessibilitySelected(this.colors().mode === 'original').onClick((): void => { this.applyOriginal(); })
      Grid() {
        ForEach(LexiTheme.PRESETS, (preset: LexiThemePreset) => {
          GridItem() {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Column({ space: 7 }) {
                Stack() {
                  SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12)
                    .fontColor([LexiTheme.contrast('#FFFFFF', preset.color) >= 4.5 ? '#FFFFFF' : '#111318'])
                    .opacity(this.selected(preset.color) ? 1 : 0)
                }.width(26).height(26).borderRadius(13).backgroundColor(preset.color)
                Text(this.tr(preset.label)).fontSize(12).fontColor(this.selected(preset.color) ? this.palette.brand : this.palette.text_secondary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%')
            }.id('appearance-preset-' + preset.color.substring(1)).width('100%').height('100%').padding(8)
              .backgroundColor(this.selected(preset.color) ? this.palette.workspace_selection : this.palette.surface)
              .border({ width: 1, color: this.selected(preset.color) ? this.palette.brand : this.palette.divider })
              .borderRadius(14).clip(true)
              .animation({ duration: 140, curve: Curve.EaseOut })
              .accessibilityText(this.tr('全局色调') + ' ' + this.tr(preset.label))
              .accessibilitySelected(this.selected(preset.color))
              .onClick((): void => { this.applyColor(preset.color); })
          }
        }, (preset: LexiThemePreset): string => preset.color)
      }.width('100%').height(152).columnsTemplate('1fr 1fr 1fr').rowsTemplate('1fr 1fr').columnsGap(10).rowsGap(10)
      Text(this.tr('自定义')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).width('100%').margin({ top: 4 })
      Column() {
        this.colorRow({ kind: 'accent', label: this.tr('强调色'), input: this.accentInput })
        Divider().color(this.palette.divider)
        this.colorRow({ kind: 'background', label: this.tr('背景'), input: this.backgroundInput })
        Divider().color(this.palette.divider)
        this.colorRow({ kind: 'foreground', label: this.tr('前景'), input: this.foregroundInput })
      }.width('100%')
      Text(this.tr('输入颜色后按回车或离开输入框，即可保存。')).fontSize(11).fontColor(this.palette.text_secondary).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
