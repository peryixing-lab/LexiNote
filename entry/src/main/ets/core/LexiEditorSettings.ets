import { LexiStorageService } from './LexiStorageService';

/** Editor preferences shared by the settings window and native note surfaces. */
export class LexiEditorSettings {
  private static pending: Promise<void> = Promise.resolve();
  static async flush(): Promise<void> { await LexiEditorSettings.pending.catch((): void => {}); }

  static async load(): Promise<void> {
    const defaultView = await LexiStorageService.getSetting('editorDefaultView', 'edit');
    const defaultMode = await LexiStorageService.getSetting('editorDefaultMode', 'live');
    const showTitle = await LexiStorageService.getSetting('editorShowTitle', 'true');
    const limitWidth = await LexiStorageService.getSetting('editorLimitWidth', 'true');
    const viewStatus = await LexiStorageService.getSetting('editorViewStatus', 'true');
    AppStorage.setOrCreate('lexiEditorDefaultView', defaultView === 'preview' ? 'preview' : 'edit');
    AppStorage.setOrCreate('lexiEditorDefaultMode', defaultMode === 'source' ? 'source' : 'live');
    AppStorage.setOrCreate('lexiEditorShowTitle', showTitle !== 'false');
    AppStorage.setOrCreate('lexiEditorLimitWidth', limitWidth !== 'false');
    AppStorage.setOrCreate('lexiEditorViewStatus', viewStatus !== 'false');
  }

  static async setString(key: string, storageKey: string, next: string): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const write = LexiEditorSettings.pending.catch((): void => {}).then(async (): Promise<void> => {
      await LexiStorageService.setSetting(key, next, owner);
      if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate(storageKey, next); }
    });
    LexiEditorSettings.pending = write;
    await write;
  }

  static async setBool(key: string, storageKey: string, next: boolean): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const write = LexiEditorSettings.pending.catch((): void => {}).then(async (): Promise<void> => {
      await LexiStorageService.setSetting(key, String(next), owner);
      if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate(storageKey, next); }
    });
    LexiEditorSettings.pending = write;
    await write;
  }
}
