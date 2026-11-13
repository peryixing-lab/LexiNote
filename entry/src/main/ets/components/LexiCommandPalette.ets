import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiHotkeySettings } from '../core/LexiHotkeySettings';
import { LexiI18n } from '../core/LexiI18n';
import { CanvasBoard, MindMapDoc, NoteItem } from '../core/LexiModels';
import { LEXI_COMMANDS, LexiCommand } from '../core/LexiCommands';
import { LexiSearch } from '../core/LexiSearch';
import { MarkdownEngine } from '../core/MarkdownEngine';
import { PluginCommandRegistry, PluginCommandEntry } from '../plugin/core/PluginCommandRegistry';
import { KeyCode } from '@kit.InputKit';

const PALETTE_ROW_HEIGHT: number = 52;
const PALETTE_ROW_GAP: number = 2;

/**
 * Command palette / quick switcher contents.
 *
 * The host presents this panel inside the same centered sheet as the trash
 * window (see LexiDesktopWorkspace.paletteSheet), so the panel owns its whole
 * chrome: a trash-style header, the query field, and a scrolling result list.
 */
@Component
export struct LexiCommandPalette {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiBottomInset') private bottomInset: number = 0;
  @StorageProp('lexiHotkeyOverrides') private hotkeyOverrides: string = '[]';
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @Prop mode: string = 'commands';
  @Prop notes: NoteItem[] = [];
  @Prop maps: MindMapDoc[] = [];
  @Prop canvases: CanvasBoard[] = [];
  @Prop showClose: boolean = true;
  @State private paletteQuery: string = '';
  @State private selectedResult: number = 0;
  onCommand: (id: string) => void = (_id: string): void => {};
  onOpen: (id: string) => void = (_id: string): void => {};
  onCreate: (title: string) => void = (_title: string): void => {};
  onClose: () => void = (): void => {};
  private resultScroller: Scroller = new Scroller();

  private results(): LexiCommand[] {
    if (this.mode === 'commands') {
      const builtin = LEXI_COMMANDS.filter((command: LexiCommand): boolean =>
        LexiSearch.rank(this.tr(command.title), this.paletteQuery) >= 0 || command.id.includes(this.paletteQuery.toLowerCase())).map((command: LexiCommand): LexiCommand =>
          new LexiCommand(command.id, command.title, LexiHotkeySettings.bindings(this.hotkeyOverrides, command.id, LexiHotkeySettings.defaults(command.id)).join(' / ')));
      // Plugin commands are merged after the static table; the table itself is never mutated.
      const pluginCommands: LexiCommand[] = PluginCommandRegistry.visible()
        .filter((entry: PluginCommandEntry): boolean =>
          LexiSearch.rank(entry.title, this.paletteQuery) >= 0 || entry.qualifiedId.includes(this.paletteQuery.toLowerCase()))
        .map((entry: PluginCommandEntry): LexiCommand => new LexiCommand(entry.qualifiedId, entry.title, '插件'));
      return builtin.concat(pluginCommands);
    }
    const result: LexiCommand[] = [];
    for (const note of this.notes) {
      if (note.trashedAt > 0) { continue; }
      const title = MarkdownEngine.displayTitle(note);
      if (LexiSearch.rank(title, this.paletteQuery) >= 0 || (this.paletteQuery && LexiSearch.matches(note, this.paletteQuery))) {
        result.push(new LexiCommand(note.id, title, this.tr('笔记 · {0}', [note.notebook])));
      }
    }
    for (const map of this.maps) {
      if (map.trashedAt === 0 && LexiSearch.rank(map.title, this.paletteQuery) >= 0) {
        result.push(new LexiCommand(`map:${map.id}`, map.title || this.tr('未命名导图'), this.tr('思维导图')));
      }
    }
    for (const board of this.canvases) {
      if (LexiSearch.rank(board.title, this.paletteQuery) >= 0) {
        result.push(new LexiCommand(`canvas:${board.id}`, board.title || this.tr('未命名白板'), this.tr('白板')));
      }
    }
    return result.sort((a: LexiCommand, b: LexiCommand): number => {
      const ar = LexiSearch.rank(a.title, this.paletteQuery);
      const br = LexiSearch.rank(b.title, this.paletteQuery);
      return (ar < 0 ? 1000 : ar) - (br < 0 ? 1000 : br);
    }).slice(0, 60);
  }

  private choose(id: string): void {
    if (this.mode === 'commands') { this.onCommand(id); } else { this.onOpen(id); }
  }

  private commandTitle(command: LexiCommand): string {
    if (this.mode === 'commands' && LEXI_COMMANDS.some((builtin: LexiCommand): boolean => builtin.id === command.id)) {
      return this.tr(command.title);
    }
    // Plugin command titles are authored by the plugin and are shown verbatim.
    return command.title;
  }

  private windowTitle(): string {
    return this.mode === 'commands' ? this.tr('命令面板') : this.tr('快速切换');
  }

  private resultSummary(): string {
    const count = this.results().length.toString();
    return this.mode === 'commands' ? this.tr('{0} 个命令', [count]) : this.tr('{0} 个文档', [count]);
  }

  private submit(): void {
    const rows = this.results();
    if (rows.length) { this.choose(rows[Math.min(this.selectedResult, rows.length - 1)].id); }
    else if (this.mode !== 'commands' && this.paletteQuery.trim()) { this.onCreate(this.paletteQuery.trim()); }
  }

  private keyPressed(event: KeyEvent): void {
    if (event.type !== KeyType.Down) { return; }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      const count = this.results().length;
      if (count) {
        this.selectedResult = (this.selectedResult + (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN ? 1 : -1) + count) % count;
        this.resultScroller.scrollTo({ xOffset: 0, yOffset: this.selectedResult * (PALETTE_ROW_HEIGHT + PALETTE_ROW_GAP) });
      }
      event.stopPropagation();
    } else if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.onClose(); event.stopPropagation(); }
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(this.windowTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text_primary)
        Text(this.resultSummary())
          .fontSize(11)
          .fontColor(this.palette.text_secondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showClose) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([this.palette.text_secondary])
        }
        .id('command-palette-close')
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('关闭命令面板'))
        .onClick((): void => { this.onClose(); })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 18, top: 18, bottom: 14 })
    .backgroundColor(this.palette.workspace_sidebar)
    .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
  }

  @Builder
  private resultRow(command: LexiCommand, rowIndex: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 3 }) {
        Text(this.commandTitle(command))
          .fontSize(14)
          .fontWeight(rowIndex === this.selectedResult ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.palette.text_primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (command.hint) {
          Text(command.hint)
            .fontSize(11)
            .fontColor(this.palette.text_secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .id(`palette-result-${command.id}`)
    .width('100%')
    .height(PALETTE_ROW_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(rowIndex === this.selectedResult ? this.palette.brand_soft : Color.Transparent)
    .onClick((): void => { this.choose(command.id); })
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Text(this.mode === 'commands' ? this.tr('没有匹配的命令') : this.tr('没有匹配的文档'))
        .fontSize(15)
        .fontColor(this.palette.text_secondary)
        .textAlign(TextAlign.Center)
      if (this.mode !== 'commands' && this.paletteQuery.trim()) {
        Button(this.tr('新建「{0}」', [this.paletteQuery.trim()]))
          .id('palette-create-note')
          .height(44)
          .fontColor(this.palette.brand)
          .backgroundColor(this.palette.brand_soft)
          .onClick((): void => { this.onCreate(this.paletteQuery.trim()); })
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      Column({ space: 12 }) {
        TextInput({
          text: this.paletteQuery,
          placeholder: this.mode === 'commands' ? this.tr('搜索命令…') : this.tr('搜索笔记、导图或白板…')
        })
          .id('command-palette-input')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(this.palette.text_primary)
          .placeholderColor(this.palette.text_secondary)
          .caretColor(this.palette.brand)
          .backgroundColor(this.palette.soft_surface)
          .borderRadius(10)
          .defaultFocus(true)
          .onChange((text: string): void => {
            this.paletteQuery = text;
            this.selectedResult = 0;
            this.resultScroller.scrollEdge(Edge.Top);
          })
          .onSubmit((): void => { this.submit(); })
          .onKeyEvent((event: KeyEvent): void => { this.keyPressed(event); })
        Text(this.mode === 'commands' ? this.tr('↑ ↓ 选择 · Enter 执行 · Esc 关闭') : this.tr('支持 tag:#标签 type:study notebook:分类 · Enter 打开'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.palette.text_secondary)
          .width('100%')
          .maxLines(2)
        Scroll(this.resultScroller) {
          Column({ space: PALETTE_ROW_GAP }) {
            ForEach(this.results(), (command: LexiCommand, rowIndex: number) => {
              this.resultRow(command, rowIndex);
            }, (command: LexiCommand): string => command.id)
            if (this.results().length === 0) {
              this.emptyState()
            }
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 16, bottom: 24 + this.bottomInset })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.workspace_page)
    .clip(true)
  }
}
