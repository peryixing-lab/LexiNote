import { LexiHotkeySettings } from '../core/LexiHotkeySettings';
import { LexiI18n } from '../core/LexiI18n';
import { CanvasBoard, MindMapDoc, NoteItem } from '../core/LexiModels';
import { LEXI_COMMANDS, LexiCommand } from '../core/LexiCommands';
import { LexiSearch } from '../core/LexiSearch';
import { MarkdownEngine } from '../core/MarkdownEngine';
import { PluginCommandRegistry, PluginCommandEntry } from '../plugin/core/PluginCommandRegistry';
import { KeyCode } from '@kit.InputKit';

@Component
export struct LexiCommandPalette {
  @StorageProp('lexiHotkeyOverrides') private hotkeyOverrides: string = '[]';
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @Prop mode: string = 'commands';
  @Prop notes: NoteItem[] = [];
  @Prop maps: MindMapDoc[] = [];
  @Prop canvases: CanvasBoard[] = [];
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
        this.resultScroller.scrollTo({ xOffset: 0, yOffset: this.selectedResult * 56 });
      }
      event.stopPropagation();
    } else if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.onClose(); event.stopPropagation(); }
  }

  build() {
    Column({ space: 12 }) {
      TextInput({ text: this.paletteQuery, placeholder: this.mode === 'commands' ? this.tr('搜索命令…') : this.tr('搜索笔记、导图或白板…') })
        .id('command-palette-input').height(48).fontSize(16)
        .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.soft_surface')).borderRadius(12).defaultFocus(true)
        .onChange((text: string): void => { this.paletteQuery = text; this.selectedResult = 0; this.resultScroller.scrollEdge(Edge.Top); })
        .onSubmit((): void => { this.submit(); }).onKeyEvent((event: KeyEvent): void => { this.keyPressed(event); })
      Text(this.mode === 'commands' ? this.tr('↑ ↓ 选择 · Enter 执行 · Esc 关闭') : this.tr('支持 tag:#标签 type:study notebook:分类 · Enter 打开'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Scroll(this.resultScroller) {
        Column({ space: 2 }) {
          ForEach(this.results(), (command: LexiCommand, rowIndex: number) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Column({ space: 4 }) {
                Text(this.commandTitle(command)).fontSize(14).fontColor($r('app.color.text_primary')).maxLines(1).width('100%')
                if (command.hint) { Text(command.hint).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(1).width('100%'); }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.id(`palette-result-${command.id}`).width('100%').height(54).padding({ left: 12, right: 12 }).borderRadius(8)
              .backgroundColor(rowIndex === this.selectedResult ? $r('app.color.brand_soft') : Color.Transparent)
              .onClick((): void => { this.choose(command.id); })
          }, (command: LexiCommand): string => command.id)
          if (this.results().length === 0) {
            Text(this.mode === 'commands' ? this.tr('没有匹配的命令') : this.tr('没有匹配的文档')).fontSize(14)
              .fontColor($r('app.color.text_secondary')).padding(20)
            if (this.mode !== 'commands' && this.paletteQuery.trim()) {
              Button(this.tr('新建「{0}」', [this.paletteQuery.trim()])).id('palette-create-note')
                .onClick((): void => { this.onCreate(this.paletteQuery.trim()); })
            }
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 12, bottom: 24 })
  }
}
