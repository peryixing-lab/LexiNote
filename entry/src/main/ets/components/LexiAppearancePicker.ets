import { LexiI18n } from '../core/LexiI18n';
@Component
export struct LexiAppearancePicker {
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @StorageProp('lexiAccent') private accent: string = '#6E44D9';
  @Prop theme: string = 'system';
  onSelect: (theme: string) => void = (_theme: string): void => {};

  build() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Text(this.tr('跟随系统'))
          .fontSize(13)
          .fontWeight(this.theme === 'system' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.theme === 'system' ? this.accent : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .width('100%')
      }
      .id('theme-system')
      .layoutWeight(1)
      .constraintSize({ minHeight: 44 })
      .padding({ left: 4, right: 4, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(this.theme === 'system' ? $r('app.color.brand_soft') : Color.Transparent)
      .accessibilityText(this.tr('外观：跟随系统'))
      .accessibilitySelected(this.theme === 'system')
      .onClick((): void => {
        this.onSelect('system');
      })

      Button({ type: ButtonType.Normal }) {
        Text(this.tr('浅色'))
          .fontSize(13)
          .fontWeight(this.theme === 'light' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.theme === 'light' ? this.accent : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .width('100%')
      }
      .id('theme-light')
      .layoutWeight(1)
      .constraintSize({ minHeight: 44 })
      .padding({ left: 4, right: 4, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(this.theme === 'light' ? $r('app.color.brand_soft') : Color.Transparent)
      .accessibilityText(this.tr('外观：浅色'))
      .accessibilitySelected(this.theme === 'light')
      .onClick((): void => {
        this.onSelect('light');
      })

      Button({ type: ButtonType.Normal }) {
        Text(this.tr('深色'))
          .fontSize(13)
          .fontWeight(this.theme === 'dark' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.theme === 'dark' ? this.accent : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .width('100%')
      }
      .id('theme-dark')
      .layoutWeight(1)
      .constraintSize({ minHeight: 44 })
      .padding({ left: 4, right: 4, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(this.theme === 'dark' ? $r('app.color.brand_soft') : Color.Transparent)
      .accessibilityText(this.tr('外观：深色'))
      .accessibilitySelected(this.theme === 'dark')
      .onClick((): void => {
        this.onSelect('dark');
      })
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('app.color.soft_surface'))
    .borderRadius(16)
  }
}
