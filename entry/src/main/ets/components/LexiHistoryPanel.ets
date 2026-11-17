import { common } from '@kit.AbilityKit';
import { LexiTheme, LexiThemePalette } from '../core/LexiTheme';
import { NoteItem, NoteRevision } from '../core/LexiModels';
import { LexiStorageService } from '../core/LexiStorageService';
import {
  LexiDiffLine,
  LexiDiffResult,
  LexiHistoryRetentionPolicy,
  LexiNoteHistory
} from '../core/LexiNoteHistory';

export class LexiHistoryCompareTarget {
  key: string = '';
  label: string = '';
  title: string = '';
  content: string = '';
  tags: string[] = [];
  subtitle: string = '';
}

@Component
export struct LexiHistoryPanel {
  @StorageProp('lexiThemePalette') private palette: LexiThemePalette = LexiTheme.current();
  @Prop @Watch('reloadRequested') openSignal: number = 0;
  @Prop @Watch('noteChanged') noteId: string = '';
  @Prop liveTitle: string = '';
  @Prop liveContent: string = '';
  @Prop hasLiveDraft: boolean = false;
  @Prop conflictMode: boolean = false;
  onRestored: (note: NoteItem) => void = (_note: NoteItem): void => {};
  onConflictResolve: (resolution: string) => void = (_resolution: string): void => {};
  onClose: () => void = (): void => {};

  @State private currentNote: NoteItem = new NoteItem();
  @State private revisions: NoteRevision[] = [];
  @State private policy: LexiHistoryRetentionPolicy = LexiNoteHistory.defaultPolicy();
  @State private selectedBaseId: string = '';
  @State private selectedTargetId: string = '__current__';
  @State private diffResult: LexiDiffResult = new LexiDiffResult();
  @State private onlyDiffLines: boolean = false;
  @State private busy: boolean = false;
  @State private feedback: string = '';
  @State private totalHistoryBytes: number = 0;

  aboutToAppear(): void {
    this.loadHistory().catch((): void => {});
  }

  private reloadRequested(): void {
    this.loadHistory().catch((): void => {});
  }

  private noteChanged(): void {
    this.selectedBaseId = '';
    this.selectedTargetId = '__current__';
    this.loadHistory().catch((): void => {});
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadHistory(): Promise<void> {
    if (!this.noteId) {
      this.revisions = [];
      this.diffResult = new LexiDiffResult();
      return;
    }
    const found = await LexiStorageService.getNoteById(this.noteId);
    if (found) {
      this.currentNote = found;
    }
    this.policy = await LexiStorageService.getHistoryPolicy();
    const list = await LexiStorageService.getNoteHistory(this.noteId);
    this.revisions = list;
    let used = 0;
    for (let i = 0; i < list.length; i++) {
      used += list[i].byteSize || LexiNoteHistory.computeRevisionBytes(list[i].snapshot);
    }
    this.totalHistoryBytes = used;
    if (this.conflictMode && this.hasLiveDraft) {
      this.selectedBaseId = '__disk__';
      this.selectedTargetId = '__live__';
    } else {
      if (!this.selectedBaseId || (this.selectedBaseId !== '__disk__' &&
        !list.some((rev: NoteRevision): boolean => rev.id === this.selectedBaseId))) {
        this.selectedBaseId = list.length > 0 ? list[0].id : '__disk__';
      }
      if (this.selectedTargetId !== '__current__' && this.selectedTargetId !== '__live__' &&
        this.selectedTargetId !== '__disk__' &&
        !list.some((rev: NoteRevision): boolean => rev.id === this.selectedTargetId)) {
        this.selectedTargetId = '__current__';
      }
    }
    this.recomputeDiff();
  }

  private resolveVersion(key: string): LexiHistoryCompareTarget {
    const target = new LexiHistoryCompareTarget();
    target.key = key;
    if (key === '__live__' || (key === '__current__' && this.hasLiveDraft)) {
      target.label = '当前编辑版本';
      target.title = this.liveTitle;
      target.content = this.liveContent;
      target.tags = this.currentNote.tags.slice();
      target.subtitle = '未提交草稿 · ' + this.formatTime(Date.now());
      return target;
    }
    if (key === '__disk__' || key === '__current__') {
      target.label = '磁盘最新保存版本';
      target.title = this.currentNote.title;
      target.content = this.currentNote.content;
      target.tags = this.currentNote.tags.slice();
      target.subtitle = this.currentNote.updatedAt > 0 ? this.formatTime(this.currentNote.updatedAt) : '已保存';
      return target;
    }
    const rev = this.revisions.find((item: NoteRevision): boolean => item.id === key);
    if (rev) {
      target.label = LexiNoteHistory.reasonLabel(rev.reason);
      target.title = rev.snapshot.title;
      target.content = rev.snapshot.content;
      target.tags = (rev.snapshot.tags || []).slice();
      target.subtitle = this.formatTime(rev.savedAt);
      return target;
    }
    target.label = '当前版本';
    target.title = this.hasLiveDraft ? this.liveTitle : this.currentNote.title;
    target.content = this.hasLiveDraft ? this.liveContent : this.currentNote.content;
    target.tags = this.currentNote.tags.slice();
    return target;
  }

  private recomputeDiff(): void {
    const base = this.resolveVersion(this.selectedBaseId);
    const target = this.resolveVersion(this.selectedTargetId);
    this.diffResult = LexiNoteHistory.diffVersions(
      base.title,
      base.content,
      target.title,
      target.content,
      base.tags,
      target.tags
    );
  }

  private formatTime(ms: number): string {
    if (!ms || ms <= 0) { return '未知时间'; }
    const d = new Date(ms);
    const yyyy = d.getFullYear().toString();
    const mm = (d.getMonth() + 1).toString().padStart(2, '0');
    const dd = d.getDate().toString().padStart(2, '0');
    const hh = d.getHours().toString().padStart(2, '0');
    const min = d.getMinutes().toString().padStart(2, '0');
    const sec = d.getSeconds().toString().padStart(2, '0');
    return `${yyyy}-${mm}-${dd} ${hh}:${min}:${sec}`;
  }

  private visibleDiffLines(): LexiDiffLine[] {
    if (!this.onlyDiffLines) {
      return this.diffResult.lines;
    }
    return this.diffResult.lines.filter((line: LexiDiffLine): boolean => line.kind !== 'equal');
  }

  private canRestoreSelected(): boolean {
    return !this.busy && this.revisions.some((rev: NoteRevision): boolean => rev.id === this.selectedBaseId);
  }

  private async createManualCheckpoint(): Promise<void> {
    if (this.busy || !this.noteId) { return; }
    this.busy = true;
    this.feedback = '';
    try {
      await LexiStorageService.createNoteSnapshot(
        this.context(),
        this.noteId,
        'manual',
        this.hasLiveDraft ? this.liveTitle : undefined,
        this.hasLiveDraft ? this.liveContent : undefined
      );
      await this.loadHistory();
      this.feedback = '已保存当前版本为历史快照';
    } catch (error) {
      this.feedback = LexiStorageService.friendlySaveError(error as Error);
    } finally {
      this.busy = false;
    }
  }

  private async restoreSelected(): Promise<void> {
    if (!this.canRestoreSelected()) { return; }
    this.busy = true;
    this.feedback = '';
    try {
      const saved = await LexiStorageService.restoreNoteRevision(
        this.context(),
        this.noteId,
        this.selectedBaseId,
        this.hasLiveDraft ? this.liveTitle : undefined,
        this.hasLiveDraft ? this.liveContent : undefined
      );
      this.feedback = '已恢复选中版本，恢复前版本已自动保存在历史记录中';
      this.onRestored(saved);
      await this.loadHistory();
    } catch (error) {
      this.feedback = LexiStorageService.friendlySaveError(error as Error);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.conflictMode ? '版本冲突对比与合并' : '版本历史与差异对比')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette.text_primary)
          Text(`共 ${this.revisions.length} 个快照 · 已用 ${LexiNoteHistory.formatBytes(this.totalHistoryBytes)}（默认保留 ${this.policy.maxAgeDays} 天 / 单篇上限 ${this.policy.maxCountPerNote} 条 · ${LexiNoteHistory.formatBytes(this.policy.maxBytesPerNote)}）`)
            .fontSize(11).fontColor(this.palette.text_secondary).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        if (!this.conflictMode) {
          Button('存快照', { type: ButtonType.Normal })
            .id('history-create-snapshot')
            .height(34).fontSize(12).borderRadius(9).padding({ left: 10, right: 10 })
            .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand_ink)
            .enabled(!this.busy && !!this.noteId)
            .onClick((): void => { this.createManualCheckpoint(); })
        }
      }.width('100%')

      if (this.feedback.length > 0) {
        Text(this.feedback)
          .fontSize(12).lineHeight(18).fontColor(this.palette.brand_ink).width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.palette.brand_soft).borderRadius(10)
      }

      if (this.conflictMode) {
        Column({ space: 8 }) {
          Text('检测到另一窗口保存了较新版本，同时本地保留有未提交草稿。以下操作都会将未选中的版本留存备份：')
            .fontSize(12).lineHeight(18).fontColor(this.palette.text_secondary).width('100%')
          Row({ space: 8 }) {
            Button('使用我的草稿（备份对方）', { type: ButtonType.Normal })
              .id('conflict-use-mine').layoutWeight(1).height(38).fontSize(12).borderRadius(10)
              .backgroundColor(this.palette.brand).fontColor(this.palette.inverse_text)
              .onClick((): void => { this.onConflictResolve('use-mine-backup-theirs'); })
            Button('使用磁盘版本（备份我的）', { type: ButtonType.Normal })
              .id('conflict-use-theirs').layoutWeight(1).height(38).fontSize(12).borderRadius(10)
              .backgroundColor(this.palette.soft_surface).fontColor(this.palette.text_primary)
              .onClick((): void => { this.onConflictResolve('use-theirs-backup-mine'); })
          }.width('100%')
          Button('另存我的草稿为独立冲突副本（完整保留两边）', { type: ButtonType.Normal })
            .id('conflict-save-copy').width('100%').height(36).fontSize(12).borderRadius(10)
            .backgroundColor(this.palette.brand_soft).fontColor(this.palette.brand_ink)
            .onClick((): void => { this.onConflictResolve('save-copy'); })
        }.width('100%').padding(10).backgroundColor(this.palette.soft_surface).borderRadius(12)
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.conflictMode && this.hasLiveDraft) {
            Row({ space: 8 }) {
              Button('对比：磁盘最新 → 我的草稿', { type: ButtonType.Normal })
                .layoutWeight(1).height(34).fontSize(12).borderRadius(9)
                .backgroundColor(this.selectedBaseId === '__disk__' && this.selectedTargetId === '__live__' ?
                  this.palette.brand_soft : this.palette.soft_surface)
                .fontColor(this.palette.text_primary)
                .onClick((): void => {
                  this.selectedBaseId = '__disk__';
                  this.selectedTargetId = '__live__';
                  this.recomputeDiff();
                })
            }.width('100%')
          }

          if (this.revisions.length === 0) {
            Text('暂无历史快照。每次修改保存或点击“存快照”后，历史版本会安全保存在本地并支持对比恢复。')
              .fontSize(13).lineHeight(20).fontColor(this.palette.text_secondary).width('100%')
              .padding(14).backgroundColor(this.palette.soft_surface).borderRadius(12)
          } else {
            Column({ space: 8 }) {
              Text('历史版本列表（点击选为对比基准 A，点“设为对比目标”对比任意两版）')
                .fontSize(12).fontColor(this.palette.text_secondary).width('100%')
              ForEach(this.revisions, (revision: NoteRevision) => {
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(`${this.selectedBaseId === revision.id ? '● 基准 A · ' : ''}${this.formatTime(revision.savedAt)}`)
                        .fontSize(13).fontWeight(FontWeight.Medium)
                        .fontColor(this.selectedBaseId === revision.id ? this.palette.brand_ink : this.palette.text_primary)
                      Text(`${LexiNoteHistory.reasonLabel(revision.reason)} · ${revision.snapshot.title || '无标题'} · ${LexiNoteHistory.formatBytes(revision.byteSize || 0)}`)
                        .fontSize(11).fontColor(this.palette.text_secondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Button(this.selectedTargetId === revision.id ? '目标 B ✓' : '设为 B', { type: ButtonType.Normal })
                      .id(`history-target-${revision.id}`)
                      .height(28).fontSize(11).borderRadius(7).padding({ left: 8, right: 8 })
                      .backgroundColor(this.selectedTargetId === revision.id ? this.palette.brand : this.palette.surface)
                      .fontColor(this.selectedTargetId === revision.id ? this.palette.inverse_text : this.palette.text_primary)
                      .onClick((): void => {
                        this.selectedTargetId = revision.id;
                        this.recomputeDiff();
                      })
                  }.width('100%')

                  Text(revision.snapshot.content || '（空白正文）')
                    .fontSize(12).lineHeight(17).fontColor(this.palette.text_secondary)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }
                .id(`history-item-${revision.id}`)
                .width('100%').padding(12).borderRadius(12)
                .backgroundColor(this.selectedBaseId === revision.id ? this.palette.brand_soft : this.palette.soft_surface)
                .onClick((): void => {
                  this.selectedBaseId = revision.id;
                  this.recomputeDiff();
                })
              }, (revision: NoteRevision): string => revision.id)
            }.width('100%')
          }

          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text(`差异对比：+${this.diffResult.addedCount} 行 / -${this.diffResult.removedCount} 行`)
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette.text_primary).layoutWeight(1)
              Button(this.selectedTargetId === '__current__' ? '目标：当前 ✓' : '对比当前版本', { type: ButtonType.Normal })
                .height(28).fontSize(11).borderRadius(7).padding({ left: 8, right: 8 })
                .backgroundColor(this.selectedTargetId === '__current__' ? this.palette.brand_soft : this.palette.soft_surface)
                .fontColor(this.palette.brand_ink)
                .onClick((): void => {
                  this.selectedTargetId = '__current__';
                  this.recomputeDiff();
                })
              Button(this.onlyDiffLines ? '显示全部行' : '仅看差异行', { type: ButtonType.Normal })
                .id('history-diff-filter')
                .height(28).fontSize(11).borderRadius(7).padding({ left: 8, right: 8 })
                .backgroundColor(this.onlyDiffLines ? this.palette.brand_soft : this.palette.soft_surface)
                .fontColor(this.palette.text_primary)
                .onClick((): void => { this.onlyDiffLines = !this.onlyDiffLines; })
            }.width('100%')

            Text(`${this.resolveVersion(this.selectedBaseId).subtitle} (A)  →  ${this.resolveVersion(this.selectedTargetId).subtitle} (B)`)
              .fontSize(11).fontColor(this.palette.text_secondary).width('100%')

            if (this.diffResult.titleChanged) {
              Column({ space: 2 }) {
                Text(`- 标题：${this.diffResult.oldTitle || '无标题'}`)
                  .fontSize(12).fontColor(this.palette.error).width('100%')
                Text(`+ 标题：${this.diffResult.newTitle || '无标题'}`)
                  .fontSize(12).fontColor(this.palette.success).width('100%')
              }.width('100%').padding(8).backgroundColor(this.palette.soft_surface).borderRadius(8)
            }

            if (this.diffResult.tagsChanged) {
              Text(`标签变化：[${this.diffResult.oldTags.join(', ')}] → [${this.diffResult.newTags.join(', ')}]`)
                .fontSize(11).fontColor(this.palette.text_secondary).width('100%')
            }

            if (this.visibleDiffLines().length === 0) {
              Text('所选两个版本内容完全一致')
                .fontSize(12).fontColor(this.palette.text_secondary).width('100%')
                .padding(12).backgroundColor(this.palette.soft_surface).borderRadius(10)
            } else {
              Column({ space: 2 }) {
                ForEach(this.visibleDiffLines(), (line: LexiDiffLine, index: number) => {
                  Row({ space: 6 }) {
                    Text(line.kind === 'add' ? '+' : line.kind === 'remove' ? '-' : ' ')
                      .fontSize(11).fontWeight(FontWeight.Bold).width(14)
                      .fontColor(line.kind === 'add' ? this.palette.success : line.kind === 'remove' ? this.palette.error : this.palette.text_secondary)
                    Text(line.oldLine > 0 ? String(line.oldLine) : '')
                      .fontSize(10).width(26).fontColor(this.palette.text_secondary).textAlign(TextAlign.End)
                    Text(line.newLine > 0 ? String(line.newLine) : '')
                      .fontSize(10).width(26).fontColor(this.palette.text_secondary).textAlign(TextAlign.End)
                    Text(line.text || ' ')
                      .fontSize(12).lineHeight(18).layoutWeight(1)
                      .fontColor(this.palette.text_primary)
                  }
                  .width('100%').padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(6)
                  .backgroundColor(line.kind === 'add' ? '#1A16A34A' : line.kind === 'remove' ? '#1ADC2626' : Color.Transparent)
                }, (line: LexiDiffLine, index: number): string => `${index}-${line.kind}-${line.oldLine}-${line.newLine}`)
              }.width('100%').padding(8).backgroundColor(this.palette.soft_surface).borderRadius(10)
            }
          }.width('100%')
        }.width('100%')
      }.width('100%').layoutWeight(1).align(Alignment.Top)

      if (!this.conflictMode) {
        Button(this.busy ? '正在恢复…' : '恢复版本 A（恢复前自动保存当前版本）', { type: ButtonType.Normal })
          .id('history-restore-btn')
          .width('100%').height(44).fontSize(14).borderRadius(12)
          .backgroundColor(this.palette.brand).fontColor(this.palette.inverse_text)
          .enabled(this.canRestoreSelected())
          .onClick((): void => { this.restoreSelected(); })
      }
    }.width('100%').height('100%')
  }
}
