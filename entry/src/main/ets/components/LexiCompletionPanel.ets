import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiCompletionCandidate } from '../core/LexiCompletion';

@Component
export struct LexiCompletionPanel {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop candidates: LexiCompletionCandidate[] = [];
  @Prop activeIndex: number = 0;
  onSelect: (candidate: LexiCompletionCandidate) => void = (_candidate: LexiCompletionCandidate): void => {};

  build() {
    Column({ space: 2 }) {
      Text('↑↓ 选择 · Enter 插入 · Esc 收起').fontSize(10).fontColor(this.palette.text_secondary)
        .width('100%').padding({ left: 12, top: 7, bottom: 5 })
      ForEach(this.candidates, (candidate: LexiCompletionCandidate, candidateIndex: number) => {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(candidate.label).fontSize(13).fontColor(this.palette.text_primary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.Start)
            Text(candidate.detail).fontSize(10).fontColor(this.palette.text_secondary)
              .maxLines(1).constraintSize({ maxWidth: 140 }).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }.id(`completion-${candidate.id}`).width('100%').height(36).padding({ left: 12, right: 12 })
          .borderRadius(6).backgroundColor(candidateIndex === this.activeIndex ? this.palette.brand_soft : Color.Transparent)
          .onClick((): void => { this.onSelect(candidate); })
      }, (candidate: LexiCompletionCandidate): string => candidate.id)
    }.id('note-inline-completion').width('100%').padding(6).borderRadius(12)
      .backgroundColor(this.palette.surface).border({ width: 1, color: this.palette.divider })
  }
}
