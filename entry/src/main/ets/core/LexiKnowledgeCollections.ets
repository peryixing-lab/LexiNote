import { LexiStorageService } from './LexiStorageService';

export class LexiBookmark {
  id: string = '';
  title: string = '';
  noteId: string = '';
  excerpt: string = '';
  query: string = '';
}
export class LexiDatabaseRecord {
  id: string = '';
  cells: string[] = [];
}
export class LexiDatabaseView {
  id: string = '';
  name: string = '';
  layout: string = 'table';
}
export class LexiDatabaseCollection {
  id: string = '';
  title: string = '';
  columns: string[] = ['名称', '状态', '备注'];
  records: LexiDatabaseRecord[] = [];
  views: LexiDatabaseView[] = [];
  activeView: string = '';
}
export class LexiKnowledgeCollections {
  private static pending: Promise<void> = Promise.resolve();
  static async bookmarks(vault: string): Promise<LexiBookmark[]> {
    const parsed = JSON.parse(await LexiStorageService.getRawValue('bookmarks:' + vault, '[]')) as LexiBookmark[];
    if (!Array.isArray(parsed)) { throw new Error('书签数据格式损坏'); }
    return parsed;
  }
  static async databases(vault: string): Promise<LexiDatabaseCollection[]> {
    const parsed = JSON.parse(await LexiStorageService.getRawValue('databases:' + vault, '[]')) as LexiDatabaseCollection[];
    if (!Array.isArray(parsed)) { throw new Error('数据库格式损坏'); }
    return parsed;
  }
  static async changeBookmarks(vault: string, mutate: (rows: LexiBookmark[]) => LexiBookmark[]): Promise<void> {
    const write = LexiKnowledgeCollections.pending.catch((): void => {}).then(async (): Promise<void> => {
      const next = mutate(await LexiKnowledgeCollections.bookmarks(vault));
      await LexiStorageService.setRawValue('bookmarks:' + vault, JSON.stringify(next));
    });
    LexiKnowledgeCollections.pending = write; await write;
  }
  static async saveDatabase(vault: string, database: LexiDatabaseCollection): Promise<void> {
    const snapshot = JSON.stringify(database);
    const write = LexiKnowledgeCollections.pending.catch((): void => {}).then(async (): Promise<void> => {
      const rows = await LexiKnowledgeCollections.databases(vault);
      const saved = JSON.parse(snapshot) as LexiDatabaseCollection;
      const index = rows.findIndex((row: LexiDatabaseCollection): boolean => row.id === saved.id);
      if (index >= 0) { rows[index] = saved; } else { rows.push(saved); }
      await LexiStorageService.setRawValue('databases:' + vault, JSON.stringify(rows));
    });
    LexiKnowledgeCollections.pending = write; await write;
  }
  static markdown(database: LexiDatabaseCollection): string {
    const escape = (cell: string): string => cell.replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
    return '| ' + database.columns.map(escape).join(' | ') + ' |\n| ' + database.columns.map((): string => '---').join(' | ') + ' |\n' +
      database.records.map((row: LexiDatabaseRecord): string => '| ' + row.cells.map(escape).join(' | ') + ' |').join('\n');
  }
}
