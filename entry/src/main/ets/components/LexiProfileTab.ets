import { LexiI18n } from '../core/LexiI18n';
import { LexiHeroHeading } from './LexiNoteCard';

/**
 * Phone "Me" page. Deliberately separate from the desktop settings window:
 * it offers only the two destinations that make sense on a phone and leaves
 * the dense preferences UI behind the gear entry.
 */
@Component
export struct LexiProfileTab {
  @StorageProp('lexiLanguage') private interfaceLanguage: string = LexiI18n.language();

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
          .fontColor($r('app.color.text_primary'))
        Text(this.vaultSubtitle())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.tr('{0} 篇笔记', [this.noteCount.toString()]))
        .fontSize(11)
        .fontColor($r('app.color.brand_ink'))
        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
        .backgroundColor($r('app.color.brand_soft'))
        .borderRadius(10)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
  }

  @Builder
  private settingsCard() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([$r('app.color.brand')])
        }
        .width(46)
        .height(46)
        .borderRadius(15)
        .backgroundColor($r('app.color.brand_soft'))

        Column({ space: 4 }) {
          Text(this.tr('设置'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.tr('外观、编辑器、插件与数据'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 16, right: 14, top: 14, bottom: 14 })
    }
    .id('profile-settings')
    .width('100%')
    .constraintSize({ minHeight: 84 })
    .padding(0)
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .accessibilityText(this.tr('设置'))
    .accessibilityDescription(this.tr('外观、编辑器、插件与数据'))
    .onClick((): void => { this.onOpenSettings(); })
  }

  @Builder
  private trashCard() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(21)
            .fontColor([$r('app.color.brand_ink')])
        }
        .width(46)
        .height(46)
        .borderRadius(15)
        .backgroundColor($r('app.color.soft_surface'))

        Column({ space: 4 }) {
          Text(this.tr('回收站'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.tr('恢复已删除的笔记，或永久删除'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.deletedCount > 0) {
          Text(`${this.deletedCount}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_ink'))
            .constraintSize({ minWidth: 22 })
            .height(22)
            .padding({ left: 7, right: 7 })
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.brand_soft'))
            .borderRadius(11)
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 16, right: 14, top: 14, bottom: 14 })
    }
    .id('profile-trash')
    .width('100%')
    .constraintSize({ minHeight: 84 })
    .padding(0)
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .accessibilityText(this.tr('回收站'))
    .accessibilityDescription(this.tr('恢复已删除的笔记，或永久删除'))
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
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 4 })

      this.settingsCard()
      this.trashCard()

      Text(this.tr('笔记保存在本机，可随时在设置中导出备份。'))
        .fontSize(12)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: this.pagePadding, right: this.pagePadding, bottom: (this.isWide ? 36 : 88) + this.bottomInset })
  }
}
