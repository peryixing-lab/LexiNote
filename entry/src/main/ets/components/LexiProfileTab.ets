import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { LexiTokens } from '../core/LexiTokens';
import { LexiMotion } from '../core/LexiMotion';
import { LexiI18n } from '../core/LexiI18n';
import { LexiHeroHeading } from './LexiNoteCard';

/**
 * Phone "Me" page. Deliberately separate from the desktop settings window:
 * it offers only the two destinations that make sense on a phone and leaves
 * the dense preferences UI behind the gear entry.
 */
@Component
export struct LexiProfileTab {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();
  @State private pressedCard: string = '';

  private tr(source: string, args: string[] = []): string {
    return LexiI18n.text(source, this.interfaceLanguage, args);
  }

  @Prop isWide: boolean = false;
  @Prop pagePadding: number = 24;
  @Prop bottomInset: number = 0;
  @Prop titleCollapsed: boolean = false;
  @Prop deletedCount: number = 0;
  @Prop noteCount: number = 0;
  @Prop activeVaultName: string = '';
  onOpenSettings: () => void = (): void => {};
  onOpenTrash: () => void = (): void => {};

  private vaultSubtitle(): string {
    return this.activeVaultName.length > 0 ? this.activeVaultName : this.tr('本地优先的个人知识库');
  }

  @Builder
  private identityCard() {
    Row({ space: 14 }) {
      Image($r('app.media.lexi_logo'))
        .width(50)
        .height(50)
        .borderRadius(15)
        .draggable(false)
      Column({ space: 4 }) {
        Text('知萤 LexiNote')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text_primary)
        Text(this.vaultSubtitle())
          .fontSize(12)
          .fontColor(this.palette.text_secondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.tr('{0} 篇笔记', [this.noteCount.toString()]))
        .fontSize(LexiTokens.TYPE_CAPTION)
        .fontFeature('"tnum" 1')
        .fontColor(this.palette.brand_ink)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.palette.brand_soft)
        .borderRadius(LexiTokens.RADIUS_FULL)
    }
    .width('100%')
    .padding(LexiTokens.SPACE_5)
    .backgroundColor(this.palette.surface)
    .border({ width: 0.5, color: this.palette.workspace_line })
    .borderRadius(LexiTokens.RADIUS_LG)
    .shadow(LexiTokens.elev1(this.palette))
  }

  @Builder
  private settingsCard() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([this.palette.brand])
        }
        .width(44)
        .height(44)
        .borderRadius(LexiTokens.RADIUS_MD)
        .backgroundColor(this.palette.brand_soft)

        Column({ space: 4 }) {
          Text(this.tr('设置'))
            .fontSize(LexiTokens.TYPE_PHONE_UI)
            .lineHeight(LexiTokens.LH_PHONE_UI)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
          Text(this.tr('外观、编辑器、插件与数据'))
            .fontSize(LexiTokens.TYPE_PHONE_CAPTION)
            .lineHeight(LexiTokens.LH_PHONE_CAPTION)
            .fontColor(this.palette.text_secondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.palette.text_secondary])
      }
      .width('100%')
      .padding({ left: LexiTokens.SPACE_5, right: 14, top: 14, bottom: 14 })
    }
    .id('profile-settings')
    .width('100%')
    .constraintSize({ minHeight: 80 })
    .padding(0)
    .borderRadius(LexiTokens.RADIUS_LG)
    .backgroundColor(this.pressedCard === 'settings' ? LexiTokens.pressedSurface(this.palette) : this.palette.surface)
    .border({ width: 0.5, color: this.palette.workspace_line })
    .shadow(LexiTokens.elev1(this.palette))
    .scale({
      x: LexiMotion.pressScale(this.pressedCard === 'settings'),
      y: LexiMotion.pressScale(this.pressedCard === 'settings')
    })
    .animation(LexiMotion.param(LexiMotion.DUR_MICRO, LexiMotion.easeOut()))
    .accessibilityText(this.tr('设置'))
    .accessibilityDescription(this.tr('外观、编辑器、插件与数据'))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedCard = 'settings';
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedCard === 'settings') { this.pressedCard = ''; }
      }
    })
    .onClick((): void => { this.onOpenSettings(); })
  }

  @Builder
  private trashCard() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(21)
            .fontColor([this.palette.brand_ink])
        }
        .width(44)
        .height(44)
        .borderRadius(LexiTokens.RADIUS_MD)
        .backgroundColor(this.palette.soft_surface)

        Column({ space: 4 }) {
          Text(this.tr('回收站'))
            .fontSize(LexiTokens.TYPE_PHONE_UI)
            .lineHeight(LexiTokens.LH_PHONE_UI)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text_primary)
          Text(this.tr('恢复已删除的笔记，或永久删除'))
            .fontSize(LexiTokens.TYPE_PHONE_CAPTION)
            .lineHeight(LexiTokens.LH_PHONE_CAPTION)
            .fontColor(this.palette.text_secondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.deletedCount > 0) {
          Text(`${this.deletedCount}`)
            .fontSize(LexiTokens.TYPE_CAPTION)
            .fontFeature('"tnum" 1')
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.brand_ink)
            .constraintSize({ minWidth: 22 })
            .height(22)
            .padding({ left: 7, right: 7 })
            .textAlign(TextAlign.Center)
            .backgroundColor(this.palette.brand_soft)
            .borderRadius(LexiTokens.RADIUS_FULL)
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.palette.text_secondary])
      }
      .width('100%')
      .padding({ left: LexiTokens.SPACE_5, right: 14, top: 14, bottom: 14 })
    }
    .id('profile-trash')
    .width('100%')
    .constraintSize({ minHeight: 80 })
    .padding(0)
    .borderRadius(LexiTokens.RADIUS_LG)
    .backgroundColor(this.pressedCard === 'trash' ? LexiTokens.pressedSurface(this.palette) : this.palette.surface)
    .border({ width: 0.5, color: this.palette.workspace_line })
    .shadow(LexiTokens.elev1(this.palette))
    .scale({
      x: LexiMotion.pressScale(this.pressedCard === 'trash'),
      y: LexiMotion.pressScale(this.pressedCard === 'trash')
    })
    .animation(LexiMotion.param(LexiMotion.DUR_MICRO, LexiMotion.easeOut()))
    .accessibilityText(this.tr('回收站'))
    .accessibilityDescription(this.tr('恢复已删除的笔记，或永久删除'))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedCard = 'trash';
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedCard === 'trash') { this.pressedCard = ''; }
      }
    })
    .onClick((): void => { this.onOpenTrash(); })
  }

  build() {
    Column({ space: 16 }) {
      LexiHeroHeading({
        headingId: 'primary-heading-3',
        title: this.tr('我的'),
        subtitle: '',
        isWide: this.isWide,
        collapsed: this.titleCollapsed
      })

      this.identityCard()

      Text(this.tr('管理'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text_secondary)
        .width('100%')
        .padding({ left: 4 })

      this.settingsCard()
      this.trashCard()

      Text(this.tr('笔记保存在本机，可随时在设置中导出备份。'))
        .fontSize(12)
        .lineHeight(20)
        .fontColor(this.palette.text_secondary)
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: this.pagePadding, right: this.pagePadding, bottom: (this.isWide ? 36 : 88) + this.bottomInset })
  }
}
