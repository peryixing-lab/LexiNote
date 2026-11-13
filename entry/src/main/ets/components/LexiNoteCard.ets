import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiI18n } from '../core/LexiI18n';
import { deviceInfo } from '@kit.BasicServicesKit';
import { NoteItem } from '../core/LexiModels';
import { MarkdownEngine, LexiMarkdownInlineSpan } from '../core/MarkdownEngine';
import { LexiContextSurface } from './LexiContextSurface';
import { LexiContextBridge, LexiContextTarget, LexiContextAction } from '../core/LexiContextModels';
import { LexiIcon } from './LexiIcon';

@Component
export struct LexiFilterChip {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop selected: boolean = false;
  @Prop label: string = '';
  action: () => void = () => {};

  build() {
    Button(this.label, { type: ButtonType.Normal })
      .height(36)
      .padding({ left: 15, right: 15 })
      .fontSize(12)
      .borderRadius(13)
      .backgroundColor(this.selected ? this.palette.brand : this.palette.surface)
      .fontColor(this.selected ? this.palette.inverse_text : this.palette.text_secondary)
      .accessibilitySelected(this.selected)
      .onClick(() => {
        this.action();
      })
  }
}

@Component
export struct LexiHeroHeading {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop headingId: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop isWide: boolean = false;
  @Prop collapsed: boolean = false;

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(this.isWide ? 30 : 26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text_primary)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(13)
          .lineHeight(20)
          .fontColor(this.palette.text_secondary)
      }
    }
    .id(this.headingId)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, bottom: 4 })
    .opacity(this.collapsed ? 0 : 1)
    .animation({ duration: 160, curve: Curve.EaseOut })
  }
}

@Component
export struct LexiNoteCard {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @Prop note: NoteItem = new NoteItem();
  @Prop query: string = '';
  @Prop outgoingCount: number = 0;
  @Prop backlinkCount: number = 0;
  onOpen: (noteId: string) => void = (_noteId: string): void => {};
  onFilterTag: (tag: string) => void = (_tag: string): void => {};
  onTogglePin: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onToggleFavorite: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onMoveToTrash: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onRestore: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onDeleteForever: (note: NoteItem) => void = (_note: NoteItem): void => {};

  private typeLabel(type: string): string {
    return type === 'study' ? this.tr('学习') : type === 'markdown' ? 'Markdown' : this.tr('速记');
  }

  private typeIcon(type: string): string {
    return type === 'study' ? 'study' : type === 'markdown' ? 'markdown' : 'note';
  }

  private dateLabel(time: number): string {
    const date = new Date(time);
    const now = new Date();
    const hm = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    if (date.toDateString() === now.toDateString()) {
      return this.tr('今天 {0}', [hm]);
    }
    const yesterday = new Date(now.getTime() - 86400000);
    if (date.toDateString() === yesterday.toDateString()) {
      return this.tr('昨天 {0}', [hm]);
    }
    return this.tr('{0}月{1}日', [(date.getMonth() + 1).toString(), date.getDate().toString()]);
  }

  private buildMenu(): MenuElement[] {
    if (this.note.trashedAt > 0) {
      return [
        {
          value: this.tr('恢复笔记'),
          action: (): void => {
            this.onRestore(this.note);
          }
        },
        {
          value: this.tr('永久删除'),
          action: (): void => {
            this.onDeleteForever(this.note);
          }
        }
      ];
    }
    return LexiContextBridge.actions(LexiContextTarget.note(this.note), false).map((entry: LexiContextAction): MenuElement => {
      return { value: entry.label, action: (): void => { LexiContextBridge.send(entry.id, LexiContextTarget.note(this.note)); } };
    });
  }

  build() {
    LexiContextSurface({ target: LexiContextTarget.note(this.note), contextEnabled: this.note.trashedAt === 0, tabletCard: true }) {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        LexiIcon({ name: this.typeIcon(this.note.noteType), iconSize: 16 })
        Text(this.typeLabel(this.note.noteType))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.brand)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.palette.brand_soft)
          .borderRadius(8)

        Text(this.note.notebook)
          .fontSize(11)
          .fontColor(this.palette.text_secondary)
          .maxLines(1)

        Blank()

        if (this.note.pinned) {
          LexiIcon({ name: 'pin', iconSize: 14 })
        }
        if (this.note.favorite) {
          LexiIcon({ name: 'star', iconSize: 14 })
        }
        Text(this.dateLabel(this.note.updatedAt))
          .fontSize(11)
          .fontColor(this.palette.text_secondary)

        if (deviceInfo.deviceType === 'tablet' && this.note.trashedAt === 0) { Blank().width(28); } else {
        Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .width(28)
          .height(26)
          .padding(0)
          .fontSize(14)
          .fontColor(this.palette.text_secondary)
          .bindMenu(this.buildMenu())
        }
      }
      .width('100%')

      Text(MarkdownEngine.displayTitle(this.note))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text_primary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text() {
        ForEach(MarkdownEngine.previewSpans(this.note, this.query), (span: LexiMarkdownInlineSpan) => {
          Span(span.text)
            .fontWeight(span.kind === 'bold' ? FontWeight.Bold : FontWeight.Regular)
            .fontStyle(span.kind === 'italic' ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(span.kind === 'code' ? 'monospace' : 'HarmonyOS Sans')
            .fontColor(span.kind === 'link' || span.kind === 'url' ? this.palette.brand_ink : this.palette.text_secondary)
            .textBackgroundStyle({ color: span.kind === 'highlight' ? this.palette.brand_soft : Color.Transparent, radius: 3 })
            .decoration({ type: span.kind === 'strike' ? TextDecorationType.LineThrough : TextDecorationType.None })
        }, (span: LexiMarkdownInlineSpan): string => span.id)
      }
        .fontSize(14)
        .lineHeight(22)
        .fontColor(this.palette.text_secondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 6 }) {
        ForEach(
          this.note.tags.slice(0, 3),
          (tag: string) => {
            Text(`#${tag}`)
              .fontSize(11)
              .fontColor(this.palette.brand_ink)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.palette.soft_surface)
              .borderRadius(7)
              .onClick(() => {
                this.onFilterTag(tag);
              })
          },
          (tag: string): string => `${this.note.id}-tag-${tag}`
        )

        Blank()

        if (this.outgoingCount > 0 || this.backlinkCount > 0) {
          Text(this.tr('🔗 {0} 出 · {1} 反', [this.outgoingCount.toString(), this.backlinkCount.toString()]))
            .fontSize(11)
            .fontColor(this.palette.brand)
        }
      }
      .width('100%')

      if (this.note.trashedAt > 0) {
        Row({ space: 8 }) {
          Button(this.tr('恢复笔记'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .borderRadius(10)
            .backgroundColor(this.palette.brand_soft)
            .fontColor(this.palette.brand)
            .onClick(() => {
              this.onRestore(this.note);
            })
          Button(this.tr('永久删除'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .borderRadius(10)
            .backgroundColor(this.palette.soft_surface)
            .fontColor(this.palette.error)
            .onClick(() => {
              this.onDeleteForever(this.note);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.palette.surface)
    .borderRadius(20)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.note.trashedAt === 0) {
        this.onOpen(this.note.id);
      }
    })
    }
  }
}
