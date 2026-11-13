import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { common } from '@kit.AbilityKit';
import { LexiIcon } from './LexiIcon';
import { NoteItem } from '../core/LexiModels';
import { MarkdownEngine } from '../core/MarkdownEngine';
import { LexiStorageService } from '../core/LexiStorageService';

/**
 * Trash contents used by the desktop sheet. The phone keeps the normal
 * route page (TrashPage); this panel only supplies the sheet content.
 */
@Component
export struct LexiTrashPanel {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiBottomInset') private bottomInset: number = 0;
  @State private deletedNotes: NoteItem[] = [];
  @State private working: boolean = false;
  @State private loadError: string = '';
  @Prop showClose: boolean = true;
  onClose: () => void = (): void => {};

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async refresh(): Promise<void> {
    try {
      await LexiStorageService.init(this.context());
      this.deletedNotes = (await LexiStorageService.getNotes(''))
        .filter((note: NoteItem): boolean => note.trashedAt > 0)
        .sort((first: NoteItem, second: NoteItem): number => second.trashedAt - first.trashedAt);
      this.loadError = '';
    } catch {
      this.loadError = '读取回收站失败，请重试';
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private async restore(note: NoteItem): Promise<void> {
    if (this.working) { return; }
    this.working = true;
    try {
      await LexiStorageService.setNoteTrash(this.context(), note.id, false);
      await this.refresh();
      this.toast('笔记已恢复');
    } catch {
      this.toast('恢复失败，请重试');
    } finally {
      this.working = false;
    }
  }

  private async remove(notes: NoteItem[]): Promise<void> {
    if (this.working || notes.length === 0) { return; }
    this.working = true;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: notes.length === 1 ? '永久删除这篇笔记？' : '清空回收站？',
        message: notes.length === 1 ? `「${MarkdownEngine.displayTitle(notes[0])}」将被永久删除，此操作无法撤销。` :
          `${notes.length} 篇笔记将被永久删除，此操作无法撤销。`,
        buttons: [{ text: '取消', color: this.palette.text_secondary },
          { text: '永久删除', color: this.palette.error }]
      });
      if (choice.index !== 1) { return; }
      for (const note of notes) { await LexiStorageService.deleteNotePermanently(note.id); }
      await this.refresh();
      this.toast('已永久删除');
    } catch {
      await this.refresh();
      this.toast('未能完成删除，请重试');
    } finally {
      this.working = false;
    }
  }

  aboutToAppear(): void {
    this.refresh().catch((): void => { this.loadError = '读取回收站失败，请重试'; });
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text('回收站')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text_primary)
        Text(`${this.deletedNotes.length} 篇已删除笔记`)
          .fontSize(11)
          .fontColor(this.palette.text_secondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.deletedNotes.length > 0 && !this.working) {
        Button('清空', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('trash-window-empty')
          .height(38)
          .fontSize(12)
          .fontColor(this.palette.brand)
          .backgroundColor(this.palette.brand_soft)
          .borderRadius(19)
          .padding({ left: 16, right: 16 })
          .onClick((): void => { this.remove(this.deletedNotes.slice()); })
      }
      if (this.showClose) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([this.palette.text_secondary])
        }
        .id('trash-window-close')
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭回收站')
        .onClick((): void => { this.onClose(); })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 18, top: 18, bottom: 14 })
    .backgroundColor(this.palette.workspace_sidebar)
    .border({ width: { bottom: 0.5 }, color: this.palette.workspace_line })
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      LexiIcon({ name: 'trash', iconSize: 36, muted: true })
      Text('回收站是空的').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary)
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      Scroll() {
        Column({ space: 14 }) {
          Text('删除的笔记会保留在这里，可恢复或永久删除。')
            .fontSize(13).lineHeight(22).fontColor(this.palette.text_secondary).width('100%')
          if (this.loadError) {
            Button(this.loadError).id('trash-window-retry').onClick((): void => { this.refresh(); })
          } else if (this.deletedNotes.length === 0) {
            this.emptyState()
          } else {
            ForEach(this.deletedNotes, (note: NoteItem) => {
              Column({ space: 12 }) {
                Text(MarkdownEngine.displayTitle(note)).fontSize(17).fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.text_primary).width('100%').maxLines(2)
                Text(MarkdownEngine.extractSnippet(note)).fontSize(13).lineHeight(21)
                  .fontColor(this.palette.text_secondary).width('100%').maxLines(3)
                Row({ space: 12 }) {
                  Button('恢复', { buttonStyle: ButtonStyleMode.TEXTUAL }).id(`trash-window-restore-${note.id}`)
                    .height(44).fontColor(this.palette.brand).enabled(!this.working)
                    .onClick((): void => { this.restore(note); })
                  Button('永久删除', { buttonStyle: ButtonStyleMode.TEXTUAL }).id(`trash-window-delete-${note.id}`)
                    .height(44).fontColor(this.palette.error).enabled(!this.working)
                    .onClick((): void => { this.remove([note]); })
                }.width('100%')
              }.width('100%').padding(20).borderRadius(20).backgroundColor(this.palette.surface)
            }, (note: NoteItem): string => `${note.id}-${note.trashedAt}`)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 24 + this.bottomInset })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.workspace_page)
  }
}
