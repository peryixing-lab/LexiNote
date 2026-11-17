import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiI18n } from '../core/LexiI18n';
import { LexiHighlightSpan, LexiLinkTargetPreview, NoteItem, NoteLink } from '../core/LexiModels';
import { LexiSearch } from '../core/LexiSearch';
import { MarkdownEngine } from '../core/MarkdownEngine';

export interface LexiPreviewPopupState {
  isVisible: boolean;
}

@Component
export struct LexiHighlightText {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop sourceText: string = '';
  @Prop queryText: string = '';
  @Prop textSize: number = 14;
  @Prop textLineHeight: number = 20;
  @Prop textWeight: FontWeight = FontWeight.Normal;
  @Prop customTextColor: string = '';
  @Prop lineLimit: number = 1;
  @Prop hitBackground: string = '#59FACC15';
  @Prop customHitColor: string = '';

  private segments(): LexiHighlightSpan[] {
    return LexiSearch.highlightSegments(this.sourceText, this.queryText);
  }

  private resolvedTextColor(): ResourceColor {
    return this.customTextColor.length > 0 ? this.customTextColor : this.palette.text_primary;
  }

  private resolvedHitColor(): ResourceColor {
    return this.customHitColor.length > 0 ? this.customHitColor : this.palette.brand_ink;
  }

  build() {
    Text() {
      ForEach(
        this.segments(),
        (span: LexiHighlightSpan) => {
          Span(span.text)
            .fontColor(span.hit ? this.resolvedHitColor() : this.resolvedTextColor())
            .fontWeight(span.hit ? FontWeight.Bold : this.textWeight)
            .textBackgroundStyle({
              color: span.hit ? this.hitBackground : Color.Transparent,
              radius: 3
            })
        },
        (span: LexiHighlightSpan): string => `${span.id}-${span.hit ? '1' : '0'}-${span.text}`
      )
    }
    .fontSize(this.textSize)
    .lineHeight(this.textLineHeight)
    .maxLines(this.lineLimit)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct LexiLinkPreviewPopupCard {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @Prop preview: LexiLinkTargetPreview = new LexiLinkTargetPreview();
  onOpen: () => void = (): void => {};
  onClose: () => void = (): void => {};

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.preview.title || this.preview.targetName || this.tr('无标题笔记'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text_primary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            Text(this.preview.exists ? (this.preview.notebook || this.tr('笔记')) : this.tr('未创建笔记'))
              .fontSize(11)
              .fontColor(this.preview.exists ? this.palette.brand_ink : this.palette.text_secondary)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.preview.exists ? this.palette.brand_soft : this.palette.soft_surface)
              .borderRadius(6)
            if (this.preview.anchor) {
              Text(`#${this.preview.anchor}`)
                .fontSize(11)
                .fontColor(this.palette.brand)
                .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                .backgroundColor(this.palette.soft_surface)
                .borderRadius(6)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Text(this.preview.snippet || this.tr('这篇笔记还没有正文内容。'))
        .fontSize(12)
        .lineHeight(19)
        .fontColor(this.palette.text_secondary)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.preview.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(
            this.preview.tags,
            (tag: string) => {
              Text(`#${tag}`)
                .fontSize(10)
                .fontColor(this.palette.brand_ink)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ right: 6, bottom: 4 })
                .backgroundColor(this.palette.soft_surface)
                .borderRadius(5)
            },
            (tag: string): string => tag
          )
        }
        .width('100%')
      }

      Row({ space: 8 }) {
        if (this.preview.exists) {
          Text(this.tr('{0} 出链 · {1} 反链', [
            this.preview.outgoingCount.toString(),
            this.preview.backlinkCount.toString()
          ]))
            .fontSize(11)
            .fontColor(this.palette.text_secondary)
            .layoutWeight(1)
        } else {
          Text(this.tr('目标尚未创建'))
            .fontSize(11)
            .fontColor(this.palette.text_secondary)
            .layoutWeight(1)
        }
        Button(this.tr('关闭'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(30)
          .fontSize(12)
          .fontColor(this.palette.text_secondary)
          .onClick((): void => {
            this.onClose();
          })
        Button(this.preview.exists ? this.tr('打开笔记') : this.tr('创建并打开'), { type: ButtonType.Normal })
          .height(30)
          .padding({ left: 12, right: 12 })
          .fontSize(12)
          .borderRadius(8)
          .backgroundColor(this.palette.brand)
          .fontColor(this.palette.inverse_text)
          .onClick((): void => {
            this.onOpen();
          })
      }
      .width('100%')
    }
    .width(292)
    .padding(14)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct LexiLinkPreviewButton {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @Prop label: string = '预览';
  @Prop rawTarget: string = '';
  @Prop availableNotes: NoteItem[] = [];
  @Prop allLinks: NoteLink[] = [];
  @Prop buttonHeight: number = 28;
  @Prop compact: boolean = false;
  @Prop popupPlacement: Placement = Placement.Top;
  @State private showPopup: boolean = false;
  @State private previewData: LexiLinkTargetPreview = new LexiLinkTargetPreview();
  onOpenTarget: (target: string) => void = (_target: string): void => {};

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  private refreshPreview(): void {
    this.previewData = MarkdownEngine.linkTargetPreview(this.rawTarget, this.availableNotes, this.allLinks);
  }

  @Builder
  private popupContent() {
    LexiLinkPreviewPopupCard({
      preview: this.previewData,
      onOpen: (): void => {
        const target = this.previewData.noteId.length > 0
          ? `${this.previewData.noteId}${this.previewData.anchor ? '#' + this.previewData.anchor : ''}`
          : this.rawTarget;
        this.showPopup = false;
        this.onOpenTarget(target);
      },
      onClose: (): void => {
        this.showPopup = false;
      }
    })
  }

  build() {
    Button(this.tr(this.label), { type: ButtonType.Normal })
      .height(this.buttonHeight)
      .padding({ left: this.compact ? 8 : 10, right: this.compact ? 8 : 10 })
      .fontSize(this.compact ? 11 : 12)
      .borderRadius(8)
      .fontColor(this.palette.brand)
      .backgroundColor(this.palette.brand_soft)
      .onHover((hovered: boolean): void => {
        if (hovered) {
          this.refreshPreview();
          this.showPopup = true;
        }
      })
      .onClick((): void => {
        if (!this.showPopup) {
          this.refreshPreview();
        }
        this.showPopup = !this.showPopup;
      })
      .bindPopup(this.showPopup, {
        builder: this.popupContent,
        placement: this.popupPlacement,
        popupColor: this.palette.surface,
        enableArrow: true,
        autoCancel: true,
        onStateChange: (event: LexiPreviewPopupState): void => {
          this.showPopup = event.isVisible;
        }
      })
  }
}
