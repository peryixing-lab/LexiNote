import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
@Component
export struct LexiTitleBackdrop {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiTopInset') titleTopInset: number = 0;

  build() {
    Column()
      .width('100%')
      .height(56 + this.titleTopInset)
      .linearGradient({
        angle: 180,
        colors: [
          [this.palette.title_scrim, 0],
          [this.palette.title_scrim, (48 + this.titleTopInset) / (56 + this.titleTopInset)],
          [Color.Transparent, 1]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}
