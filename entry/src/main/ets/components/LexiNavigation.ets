import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiI18n } from '../core/LexiI18n';
import { uiMaterial } from '@kit.ArkUI';
import { LexiIcon } from './LexiIcon';

@Component
export struct LexiNavigation {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @Prop active: number = 0;
  onSelect: (index: number) => void = () => {};
  @State private immersiveSupported: boolean = false;
  private activeNavMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: this.palette.title_chip_active,
      interactive: true,
      applyShadow: true,
      lightEffect: { color: this.palette.dock_light }
    });
  }
  private inactiveNavMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      applyShadow: false,
      lightEffect: { color: this.palette.dock_light }
    });
  }

  aboutToAppear(): void {
    try {
      this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    } catch {
      this.immersiveSupported = false;
    }
  }

  @Builder
  navigationItem(index: number, title: string, icon: string) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        LexiIcon({ name: icon, iconSize: 20, muted: this.active !== index })
        Text(title)
          .fontSize(15)
          .fontWeight(this.active === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.active === index ? this.palette.brand : this.palette.text_secondary)
      }
      .padding({ left: 16, right: 16 })
    }
    .height(40)
    .borderRadius(20)
    .backgroundColor(
      this.immersiveSupported
        ? Color.Transparent
        : this.active === index
          ? this.palette.brand_soft
          : Color.Transparent
    )
    .systemMaterial(
      this.immersiveSupported
        ? this.active === index
          ? this.activeNavMaterial()
          : this.inactiveNavMaterial()
        : undefined
    )
    .accessibilityText(title)
    .accessibilityDescription(this.active === index ? this.tr('已选中') : this.tr('前往{0}', [title]))
    .onClick(() => {
      this.onSelect(index);
    })
  }

  build() {
    Row({ space: 8 }) {
      Row({ space: 10 }) {
        Image($r('app.media.lexi_logo'))
          .width(34)
          .height(34)
          .borderRadius(10)
        Text('LexiNote')
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text_primary)
      }
      .margin({ right: 28 })

      this.navigationItem(0, this.tr('首页'), 'home')
      this.navigationItem(1, this.tr('知识库'), 'vault')
      this.navigationItem(2, this.tr('关联'), 'explore')
      this.navigationItem(3, this.tr('设置'), 'profile')
    }
    .height(56)
    .width('auto')
  }
}
