import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { LexiKnowledgeCollections, LexiBookmark, LexiDatabaseCollection, LexiDatabaseRecord, LexiDatabaseView } from '../core/LexiKnowledgeCollections';
import { LexiStorageService } from '../core/LexiStorageService';
import { NoteItem, NoteProperty, NoteRevision } from '../core/LexiModels';
import { MarkdownEngine } from '../core/MarkdownEngine';

/** Persistent bookmarks and editable collections, opened by the shared command dispatcher. */
@Component
export struct LexiKnowledgePanel {
  @Prop @Watch('openRequested') requestRevision: number = 0;
  @Prop command: string = '';
  @Prop vaultId: string = '';
  @Prop noteId: string = '';
  @Prop excerpt: string = '';
  @Prop selectionStart: number = 0;
  @Prop selectionEnd: number = 0;
  @Prop openNoteIds: string[] = [];
  onSearch: (query: string) => void = (_query: string): void => {};
  onOpen: (id: string) => void = (_id: string): void => {};
  onSaved: (note: NoteItem) => void = (_note: NoteItem): void => {};
  @State private panelOpen: boolean = false;
  @State private panelTitle: string = '';
  @State private panelQuery: string = '';
  @State private inputText: string = '';
  @State private secondaryText: string = '';
  @State private message: string = '';
  @State private bookmarkRows: LexiBookmark[] = [];
  @State private databaseRows: LexiDatabaseCollection[] = [];
  @State private activeDatabase: LexiDatabaseCollection = new LexiDatabaseCollection();
  @State private editingRecord: string = '';
  @State private recordInput: string = '';
  @State private recordCells: string[] = [];
  @State private columnsText: string = '';
  @State private noteRows: NoteItem[] = [];
  @State private revisions: NoteRevision[] = [];
  @State private saving: boolean = false;

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private openRequested(): void { this.loadPanel().catch((error: Error): void => { this.message = error.message; this.panelOpen = true; }); }
  private async loadPanel(): Promise<void> {
    if (!this.command) { return; }
    this.message = ''; this.inputText = ''; this.secondaryText = ''; this.panelQuery = ''; this.editingRecord = '';
    this.panelTitle = this.command.startsWith('bookmark') ? '书签' : this.command.startsWith('database') ? '数据库' : '笔记工具';
    this.noteRows = (await LexiStorageService.getNotes(this.vaultId)).filter((note: NoteItem): boolean => note.trashedAt === 0);
    if (this.command.startsWith('bookmark')) {
      if (this.command === 'bookmark-remove') {
        await LexiKnowledgeCollections.changeBookmarks(this.vaultId, (rows: LexiBookmark[]): LexiBookmark[] => rows.filter((row: LexiBookmark): boolean => row.noteId !== this.noteId));
      } else if (this.command !== 'bookmarks' && this.command !== 'bookmark-search') {
        const ids = this.command === 'bookmark-tabs' ? this.openNoteIds : [this.noteId];
        const additions: LexiBookmark[] = [];
        for (const id of ids) {
          const note = this.noteRows.find((row: NoteItem): boolean => row.id === id);
          if (!note) { continue; }
          const bookmark = new LexiBookmark(); bookmark.id = util.generateRandomUUID(true); bookmark.noteId = id;
          bookmark.title = MarkdownEngine.displayTitle(note); bookmark.excerpt = this.command === 'bookmark-block' || this.command === 'bookmark-heading' ? this.excerpt : '';
          additions.push(bookmark);
        }
        await LexiKnowledgeCollections.changeBookmarks(this.vaultId, (rows: LexiBookmark[]): LexiBookmark[] => rows.concat(additions));
      }
      this.bookmarkRows = await LexiKnowledgeCollections.bookmarks(this.vaultId);
    } else if (this.command.startsWith('database')) {
      this.databaseRows = await LexiKnowledgeCollections.databases(this.vaultId);
      this.activeDatabase = new LexiDatabaseCollection();
    } else if (this.command === 'history') { this.revisions = await LexiStorageService.getNoteHistory(this.noteId); }
    this.panelOpen = true;
  }
  private async removeBookmark(id: string): Promise<void> {
    await LexiKnowledgeCollections.changeBookmarks(this.vaultId, (rows: LexiBookmark[]): LexiBookmark[] => rows.filter((row: LexiBookmark): boolean => row.id !== id));
    this.bookmarkRows = await LexiKnowledgeCollections.bookmarks(this.vaultId);
  }
  private async createDatabase(): Promise<void> {
    const database = new LexiDatabaseCollection(); database.id = util.generateRandomUUID(true); database.title = this.inputText.trim() || '新建数据库';
    const view = new LexiDatabaseView(); view.id = 'table'; view.name = '表格'; database.views = [view]; database.activeView = view.id;
    await LexiKnowledgeCollections.saveDatabase(this.vaultId, database);
    this.databaseRows = await LexiKnowledgeCollections.databases(this.vaultId); this.activeDatabase = database; this.columnsText = database.columns.join(', ');
  }
  private async saveRecord(): Promise<void> {
    const database = JSON.parse(JSON.stringify(this.activeDatabase)) as LexiDatabaseCollection;
    const cells: string[] = database.columns.map((_column: string, index: number): string => this.recordCells[index] || '');
    const row = new LexiDatabaseRecord(); row.id = this.editingRecord || util.generateRandomUUID(true); row.cells = cells.slice(0, database.columns.length);
    const index = database.records.findIndex((item: LexiDatabaseRecord): boolean => item.id === row.id);
    if (index < 0) { database.records.push(row); } else { database.records[index] = row; }
    await LexiKnowledgeCollections.saveDatabase(this.vaultId, database); this.activeDatabase = database;
    this.editingRecord = ''; this.recordInput = ''; this.recordCells = [];
  }
  private async removeRecord(id: string): Promise<void> {
    const database = JSON.parse(JSON.stringify(this.activeDatabase)) as LexiDatabaseCollection;
    database.records = database.records.filter((row: LexiDatabaseRecord): boolean => row.id !== id);
    await LexiKnowledgeCollections.saveDatabase(this.vaultId, database); this.activeDatabase = database;
  }
  private cardView(): boolean {
    return this.activeDatabase.views.some((view: LexiDatabaseView): boolean => view.id === this.activeDatabase.activeView && view.layout === 'cards');
  }
  private async updateColumns(): Promise<void> {
    const columns = this.columnsText.split(/[,，]/).map((column: string): string => column.trim()).filter((column: string): boolean => !!column);
    if (!columns.length || columns.length > 12 || new Set<string>(columns).size !== columns.length) { throw new Error('请输入 1 至 12 个不重复的列名'); }
    const database = JSON.parse(JSON.stringify(this.activeDatabase)) as LexiDatabaseCollection;
    if (columns.length < database.columns.length) { throw new Error('请保留现有列，避免删除项目数据'); }
    database.columns = columns;
    for (const row of database.records) { while (row.cells.length < columns.length) { row.cells.push(''); } }
    await LexiKnowledgeCollections.saveDatabase(this.vaultId, database); this.activeDatabase = database;
  }
  private async addView(): Promise<void> {
    const database = JSON.parse(JSON.stringify(this.activeDatabase)) as LexiDatabaseCollection;
    const view = new LexiDatabaseView(); view.id = util.generateRandomUUID(true); view.name = this.inputText.trim() || '卡片视图'; view.layout = 'cards';
    database.views.push(view); database.activeView = view.id;
    await LexiKnowledgeCollections.saveDatabase(this.vaultId, database); this.activeDatabase = database;
  }
  private async submitNote(): Promise<void> {
    if (this.saving) { return; } this.saving = true;
    try {
      const note = await LexiStorageService.getNoteById(this.noteId);
      if (!note) { throw new Error('请先打开笔记'); }
      if (this.command === 'rename') { const saved = await LexiStorageService.renameNote(this.context(), note.id, this.inputText); this.onSaved(saved); }
      else if (this.command === 'tag-add') { if (this.inputText.trim()) { note.tags = note.tags.concat(this.inputText.trim().split(/\s+/)); } this.onSaved(await LexiStorageService.saveNote(this.context(), note)); }
      else if (this.command === 'property-add' || this.command === 'alias-add') {
        const key = this.command === 'alias-add' ? 'aliases' : this.inputText.trim();
        if (!key) { throw new Error('请输入属性名'); }
        note.properties = note.properties.filter((prop: NoteProperty): boolean => prop.key !== key);
        note.properties.push(new NoteProperty(key, this.secondaryText)); this.onSaved(await LexiStorageService.saveNote(this.context(), note));
      } else if (this.command === 'move-file') { note.notebook = this.inputText.trim() || '笔记'; this.onSaved(await LexiStorageService.saveNote(this.context(), note)); }
      this.message = '已保存';
    } catch (error) { this.message = (error as Error).message; }
    finally { this.saving = false; }
  }
  private async selectTarget(target: NoteItem): Promise<void> {
    try {
      if (this.command === 'compose-merge') { this.onSaved(await LexiStorageService.mergeNotes(this.context(), this.noteId, target.id)); }
      else if (this.command === 'compose-selection' || this.command === 'compose-heading') {
        if (!this.excerpt) { throw new Error('请先选择需要移动的文字'); }
        const saved = await LexiStorageService.moveNoteSelection(this.context(), this.noteId, target.id, this.selectionStart, this.selectionEnd, this.excerpt);
        this.onSaved(saved);
        const source = await LexiStorageService.getNoteById(this.noteId); if (source) { this.onSaved(source); }
      } else { this.onOpen(target.id); }
      this.panelOpen = false;
    } catch (error) { this.message = (error as Error).message; }
  }
  private run(task: () => Promise<void>): void {
    if (this.saving) { return; } this.saving = true;
    task().catch((error: Error): void => { this.message = error.message; }).finally((): void => { this.saving = false; });
  }

  @Builder
  private panelContent() {
    Column({ space: 10 }) {
      Text(this.panelTitle).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      if (this.message) { Text(this.message).fontSize(12).width('100%') }
      TextInput({ text: this.panelQuery, placeholder: '搜索' }).height(36).onChange((text: string): void => { this.panelQuery = text; })
      Scroll() {
        Column({ space: 10 }) {
          if (this.command.startsWith('bookmark')) {
            if (this.command === 'bookmark-search') {
              TextInput({ text: this.inputText, placeholder: '要收藏的搜索条件' }).onChange((text: string): void => { this.inputText = text; })
              Button('收藏搜索').onClick((): void => { this.run(async (): Promise<void> => {
                if (!this.inputText.trim()) { throw new Error('请输入搜索条件'); }
                const bookmark = new LexiBookmark(); bookmark.id = util.generateRandomUUID(true); bookmark.title = this.inputText; bookmark.query = this.inputText;
                await LexiKnowledgeCollections.changeBookmarks(this.vaultId, (rows: LexiBookmark[]): LexiBookmark[] => rows.concat([bookmark]));
                this.bookmarkRows = await LexiKnowledgeCollections.bookmarks(this.vaultId); this.inputText = '';
              }); })
            }
            ForEach(this.bookmarkRows.filter((row: LexiBookmark): boolean => (row.title + row.excerpt).includes(this.panelQuery)), (row: LexiBookmark) => {
              Row({ space: 8 }) {
                Button(row.title + (row.excerpt ? ' · ' + row.excerpt.slice(0, 30) : '')).layoutWeight(1)
                  .onClick((): void => { if (row.query) { this.onSearch(row.query); } else { this.onOpen(row.noteId); } this.panelOpen = false; })
                Button('移除').onClick((): void => { this.run((): Promise<void> => this.removeBookmark(row.id)); })
              }.width('100%')
            }, (row: LexiBookmark): string => row.id)
            if (!this.bookmarkRows.length) { Text('暂无书签') }
          } else if (this.command.startsWith('database')) {
            if (!this.activeDatabase.id) {
              Row({ space: 8 }) {
                TextInput({ text: this.inputText, placeholder: '数据库名称' }).layoutWeight(1).onChange((text: string): void => { this.inputText = text; })
                Button('创建数据库').onClick((): void => { this.run((): Promise<void> => this.createDatabase()); })
              }
              ForEach(this.databaseRows, (database: LexiDatabaseCollection) => {
                Button(database.title).width('100%').onClick((): void => { this.activeDatabase = database; this.columnsText = database.columns.join(', '); this.recordCells = []; })
              }, (database: LexiDatabaseCollection): string => database.id)
            } else {
              Text(this.activeDatabase.title).fontSize(18).width('100%')
              Row({ space: 6 }) {
                ForEach(this.activeDatabase.views, (view: LexiDatabaseView) => {
                  Button(view.name).fontSize(12).onClick((): void => {
                    const database = JSON.parse(JSON.stringify(this.activeDatabase)) as LexiDatabaseCollection; database.activeView = view.id;
                    this.run(async (): Promise<void> => { await LexiKnowledgeCollections.saveDatabase(this.vaultId, database); this.activeDatabase = database; this.columnsText = database.columns.join(', '); this.recordCells = []; });
                  })
                }, (view: LexiDatabaseView): string => view.id)
                Button('+ 视图').fontSize(12).onClick((): void => { this.run((): Promise<void> => this.addView()); })
              }
              Row({ space: 8 }) {
                TextInput({ text: this.columnsText, placeholder: '列名，用逗号分隔' }).layoutWeight(1).onChange((text: string): void => { this.columnsText = text; })
                Button('保存列').fontSize(12).onClick((): void => { this.run((): Promise<void> => this.updateColumns()); })
              }
              Text(this.activeDatabase.columns.join('  /  ')).fontSize(13).width('100%')
              ForEach(this.activeDatabase.records.filter((row: LexiDatabaseRecord): boolean => row.cells.join(' ').includes(this.panelQuery)), (row: LexiDatabaseRecord) => {
                Row({ space: 8 }) {
                  Button(this.cardView() ? row.cells.map((cell: string, index: number): string => this.activeDatabase.columns[index] + ': ' + cell).join('\n') : row.cells.join('  |  '))
                    .layoutWeight(1).onClick((): void => { this.editingRecord = row.id; this.recordCells = row.cells.slice(); })
                  Button('删除').fontSize(12).onClick((): void => { this.run((): Promise<void> => this.removeRecord(row.id)); })
                }.width('100%')
              }, (row: LexiDatabaseRecord): string => row.id)
              ForEach(this.activeDatabase.columns, (column: string, columnIndex: number) => {
                TextInput({ text: this.recordCells[columnIndex] || '', placeholder: column }).height(40).onChange((text: string): void => {
                  const cells = this.recordCells.slice(); cells[columnIndex] = text; this.recordCells = cells;
                })
              }, (column: string): string => column)
              Button(this.editingRecord ? '保存项目' : '添加项目').onClick((): void => { this.run((): Promise<void> => this.saveRecord()); })
              Button('复制表格').onClick((): void => { this.run(async (): Promise<void> => {
                await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, LexiKnowledgeCollections.markdown(this.activeDatabase))); this.message = '已复制';
              }); })
              Button('插入为笔记').onClick((): void => { this.run(async (): Promise<void> => {
                const note = new NoteItem(); note.vaultId = this.vaultId; note.title = this.activeDatabase.title; note.content = LexiKnowledgeCollections.markdown(this.activeDatabase); note.noteType = 'markdown'; note.editorLevel = 'pro';
                const saved = await LexiStorageService.saveNote(this.context(), note); this.onSaved(saved); this.onOpen(saved.id); this.panelOpen = false;
              }); })
              Button('返回数据库列表').onClick((): void => { this.activeDatabase = new LexiDatabaseCollection(); })
            }
          } else if (this.command === 'history') {
            ForEach(this.revisions, (revision: NoteRevision) => {
              Text(new Date(revision.savedAt).toLocaleString()).fontSize(12).width('100%')
              Text(revision.snapshot.content).fontSize(13).width('100%').maxLines(6)
              Button('恢复这个版本').onClick((): void => { this.run(async (): Promise<void> => {
                const saved = await LexiStorageService.restoreNoteRevision(this.context(), this.noteId, revision.id); this.onSaved(saved); this.message = '已恢复，原版本保留在历史记录中';
              }); })
            }, (revision: NoteRevision): string => String(revision.savedAt))
          } else if (this.command.startsWith('compose-') || this.command === 'tags-list' || this.command === 'properties-all') {
            ForEach(this.noteRows.filter((note: NoteItem): boolean => (!this.command.startsWith('compose-') || note.id !== this.noteId) && (note.title + note.tags.join(' ')).includes(this.panelQuery)), (note: NoteItem) => {
              Button(MarkdownEngine.displayTitle(note) + (this.command === 'tags-list' ? ' · ' + note.tags.join(' ') : this.command === 'properties-all' ? ' · ' + note.properties.map((prop: NoteProperty): string => prop.key + ': ' + prop.propValue).join(' ') : ''))
                .width('100%').onClick((): void => { this.selectTarget(note); })
            }, (note: NoteItem): string => note.id)
          } else {
            TextInput({ text: this.inputText, placeholder: this.command === 'property-add' ? '属性名' : '名称或内容' }).onChange((text: string): void => { this.inputText = text; })
            if (this.command === 'property-add' || this.command === 'alias-add') {
              TextInput({ text: this.secondaryText, placeholder: '属性值' }).onChange((text: string): void => { this.secondaryText = text; })
            }
            Button('保存').enabled(!this.saving).onClick((): void => { this.submitNote(); })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding(20).backgroundColor($r('app.color.surface'))
  }
  build() {
    Column() {}.width(0).height(0).bindSheet($$this.panelOpen, this.panelContent, {
      height: SheetSize.LARGE, showClose: true, dragBar: true, backgroundColor: $r('app.color.surface')
    })
  }
}
