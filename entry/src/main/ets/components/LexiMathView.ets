import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { common } from '@kit.AbilityKit';
import { LexiMarkdownInlineSpan, MarkdownEngine } from '../core/MarkdownEngine';
import { LexiMathBitmapCache, LexiMathBitmapResult } from '../core/LexiMathBitmapCache';

class LexiMathVisualSpan {
  renderKey: string = '';
  segment: LexiMarkdownInlineSpan = new LexiMarkdownInlineSpan();
  bitmap: LexiMathBitmapResult | undefined = undefined;
}

/** Renders native text and cached formula bitmaps; the shared renderer runs separately. */
@Component
export struct LexiMathView {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop @Watch('refreshMath') sourceText: string = '';
  @Prop @Watch('refreshMath') displayMode: boolean = false;
  @Prop textSize: number = 16;
  @Prop textLeading: number = 27;
  @Prop strong: boolean = false;
  @Prop muted: boolean = false;
  @Prop checked: boolean = false;
  @Prop cellAlignment: string = 'left';
  @StorageProp('lexiColorMode') @Watch('refreshMath') mathColorMode: number = 0;
  @State private visualSpans: LexiMathVisualSpan[] = [];
  @State private availableWidth: number = 320;
  private revision: number = 0;
  onActivate: (segment: LexiMarkdownInlineSpan) => void = (_segment: LexiMarkdownInlineSpan): void => {};
  onEditText: () => void = (): void => {};
  onInteractiveAction: () => void = (): void => {};

  aboutToAppear(): void { this.refreshMath(); }
  aboutToDisappear(): void { this.revision++; }

  private refreshMath(): void {
    const currentRevision = ++this.revision;
    let segments: LexiMarkdownInlineSpan[];
    if (this.displayMode) {
      const segment = new LexiMarkdownInlineSpan();
      segment.id = 'formula'; segment.kind = 'math-display'; segment.text = this.sourceText;
      segments = [segment];
    } else { segments = MarkdownEngine.inlineSpans(this.sourceText); }
    const visual: LexiMathVisualSpan[] = segments.map((segment: LexiMarkdownInlineSpan): LexiMathVisualSpan => {
      const item = new LexiMathVisualSpan();
      item.renderKey = `${currentRevision}-${segment.id}-source`;
      item.segment = segment; return item;
    });
    this.visualSpans = visual;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      if (segment.kind !== 'math' && segment.kind !== 'math-display') { continue; }
      const itemIndex = i;
      LexiMathBitmapCache.request(context, segment.text, segment.kind === 'math-display', this.mathColorMode === 1,
        (result: LexiMathBitmapResult | undefined): void => {
          if (currentRevision !== this.revision || !result) { return; }
          const next = this.visualSpans.slice();
          if (!next[itemIndex] || next[itemIndex].segment.id !== segment.id) { return; }
          const item = new LexiMathVisualSpan();
          // ForEach reuses children with the same key; recreate this Span as an ImageSpan when ready.
          item.renderKey = `${currentRevision}-${segment.id}-bitmap`;
          item.segment = segment; item.bitmap = result;
          next[itemIndex] = item; this.visualSpans = next;
        });
    }
  }

  private isStandaloneDisplay(): boolean {
    return this.displayMode || (this.visualSpans.length === 1 && this.visualSpans[0].segment.kind === 'math-display');
  }
  private imageWidth(item: LexiMathVisualSpan): number {
    if (!item.bitmap) { return 1; }
    const natural = item.bitmap.width * this.textSize / 16;
    if (!this.isStandaloneDisplay()) {
      return Math.min(natural, Math.max(1, this.availableWidth));
    }
    if (this.availableWidth > 0 && natural > this.availableWidth && natural <= this.availableWidth * 1.65) {
      return this.availableWidth;
    }
    return natural;
  }
  private imageHeight(item: LexiMathVisualSpan): number {
    if (!item.bitmap) { return 1; }
    return item.bitmap.height * this.imageWidth(item) / item.bitmap.width;
  }
  private effectiveLineHeight(): number {
    let maxImgHeight = 0;
    for (let i = 0; i < this.visualSpans.length; i++) {
      const item = this.visualSpans[i];
      if (item.bitmap) {
        const h = this.imageHeight(item);
        if (h > maxImgHeight) { maxImgHeight = h; }
      }
    }
    return maxImgHeight > this.textLeading ? Math.ceil(maxImgHeight + 4) : this.textLeading;
  }
  private activate(segment: LexiMarkdownInlineSpan): void {
    this.onInteractiveAction();
    if (segment.kind === 'link' || segment.kind === 'url') { this.onActivate(segment); }
    else { this.onEditText(); }
  }

  build() {
    Column() {
      if (this.isStandaloneDisplay() && this.visualSpans.length > 0 && this.visualSpans[0].bitmap) {
        Scroll() {
          Row() {
            Image(`data:image/png;base64,${this.visualSpans[0].bitmap?.data || ''}`)
              .width(this.imageWidth(this.visualSpans[0])).height(this.imageHeight(this.visualSpans[0]))
              .objectFit(ImageFit.Contain).accessibilityText(this.sourceText)
              .onClick((): void => { this.onInteractiveAction(); this.onEditText(); })
          }.justifyContent(FlexAlign.Center).constraintSize({ minWidth: this.availableWidth })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%')
      } else {
        Text() {
          ForEach(this.visualSpans, (item: LexiMathVisualSpan) => {
            if (item.bitmap) {
              ImageSpan(`data:image/png;base64,${item.bitmap.data}`)
                .width(this.imageWidth(item)).height(this.imageHeight(item))
                .verticalAlign(ImageSpanAlignment.CENTER).objectFit(ImageFit.Contain)
                .onClick((): void => { this.activate(item.segment); })
            } else {
              Span(item.segment.text)
                .fontWeight(this.strong || item.segment.kind === 'bold' ? FontWeight.Bold : FontWeight.Regular)
                .fontStyle(item.segment.kind === 'italic' ? FontStyle.Italic : FontStyle.Normal)
                .fontFamily(item.segment.kind === 'code' ? 'monospace' : 'HarmonyOS Sans')
                .fontColor(item.segment.kind === 'link' || item.segment.kind === 'url' ? this.palette.brand_ink :
                  (this.muted || this.checked ? this.palette.text_secondary : this.palette.text_primary))
                .textBackgroundStyle({ color: item.segment.kind === 'highlight' ? this.palette.brand_soft :
                  item.segment.kind === 'code' ? this.palette.soft_surface : Color.Transparent, radius: 3 })
                .decoration({ type: item.segment.kind === 'strike' || this.checked ? TextDecorationType.LineThrough :
                  item.segment.kind === 'link' || item.segment.kind === 'url' ? TextDecorationType.Underline : TextDecorationType.None })
                .onClick((): void => { this.activate(item.segment); })
            }
          }, (item: LexiMathVisualSpan): string => item.renderKey)
        }
        .fontSize(this.textSize).lineHeight(this.effectiveLineHeight()).copyOption(CopyOptions.LocalDevice)
        .textAlign(this.cellAlignment === 'center' ? TextAlign.Center : this.cellAlignment === 'right' ? TextAlign.End : TextAlign.Start)
        .width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .onAreaChange((_old: Area, current: Area): void => {
        const next = Number(current.width); if (next > 0 && Math.abs(next - this.availableWidth) > 1) { this.availableWidth = next; }
      })
  }
}
