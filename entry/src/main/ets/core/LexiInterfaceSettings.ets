import { display, window } from '@kit.ArkUI';
import { LexiStorageService } from './LexiStorageService';

/** Preferences shared by the settings window and the desktop workspace. */
export class LexiInterfaceSettings {
  private static stage: window.WindowStage | undefined;
  private static loaded: boolean = false;
  private static pendingWrites: Promise<void> = Promise.resolve();
  static async flush(): Promise<void> { await LexiInterfaceSettings.pendingWrites.catch((): void => {}); }

  static async load(): Promise<void> {
    const titles = await LexiStorageService.getSetting('interfaceTabHeaders', 'true');
    const ribbon = await LexiStorageService.getSetting('interfaceRibbon', 'true');
    const hidden = await LexiStorageService.getSetting('interfaceHiddenCommands', '[]');
    const zoom = Number(await LexiStorageService.getSetting('interfaceZoom', '100'));
    AppStorage.setOrCreate('lexiTabHeaders', titles !== 'false');
    AppStorage.setOrCreate('lexiShowRibbon', ribbon !== 'false');
    AppStorage.setOrCreate('lexiHiddenRibbonCommands', JSON.stringify(LexiInterfaceSettings.parseHidden(hidden)));
    AppStorage.setOrCreate('lexiInterfaceZoom', LexiInterfaceSettings.clampZoom(zoom));
    LexiInterfaceSettings.loaded = true;
    LexiInterfaceSettings.applyZoom(AppStorage.get<number>('lexiInterfaceZoom') || 100);
  }

  static attachStage(stage: window.WindowStage): void {
    LexiInterfaceSettings.stage = stage;
    if (LexiInterfaceSettings.loaded) {
      LexiInterfaceSettings.applyZoom(AppStorage.get<number>('lexiInterfaceZoom') || 100);
    }
  }
  static detachStage(): void { LexiInterfaceSettings.stage = undefined; }
  static clampZoom(amount: number): number {
    return Number.isFinite(amount) ? Math.max(75, Math.min(150, Math.round(amount))) : 100;
  }
  static parseHidden(raw: string): string[] {
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed.filter((item: string): boolean => typeof item === 'string') : [];
    } catch { return []; }
  }
  static isVisible(raw: string, id: string): boolean { return !LexiInterfaceSettings.parseHidden(raw).includes(id); }
  private static save(key: string, value: string, owner: string): Promise<void> {
    const write = LexiInterfaceSettings.pendingWrites.catch((): void => {}).then(async (): Promise<void> => {
      await LexiStorageService.setSetting(key, value, owner);
    });
    LexiInterfaceSettings.pendingWrites = write;
    return write;
  }
  static async setTabHeaders(on: boolean): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    await LexiInterfaceSettings.save('interfaceTabHeaders', String(on), owner);
    if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate('lexiTabHeaders', on); }
  }
  static async setRibbon(on: boolean): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    await LexiInterfaceSettings.save('interfaceRibbon', String(on), owner);
    if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate('lexiShowRibbon', on); }
  }
  static async setCommandVisible(id: string, visible: boolean): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const write = LexiInterfaceSettings.pendingWrites.catch((): void => {}).then(async (): Promise<void> => {
      const hidden = LexiInterfaceSettings.parseHidden(await LexiStorageService.getSetting('interfaceHiddenCommands', '[]', owner));
      const next = hidden.filter((item: string): boolean => item !== id);
      if (!visible) { next.push(id); }
      const raw = JSON.stringify(next);
      await LexiStorageService.setSetting('interfaceHiddenCommands', raw, owner);
      if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate('lexiHiddenRibbonCommands', raw); }
    });
    LexiInterfaceSettings.pendingWrites = write;
    await write;
  }
  private static applyZoom(amount: number): void {
    if (!LexiInterfaceSettings.stage) { return; }
    const density = display.getDefaultDisplaySync().densityPixels;
    if (density <= 0) { throw new Error('无法获取屏幕密度'); }
    LexiInterfaceSettings.stage.setCustomDensity(density * amount / 100, true);
  }
  static async setZoom(amount: number): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const next = LexiInterfaceSettings.clampZoom(amount);
    LexiInterfaceSettings.applyZoom(next);
    AppStorage.setOrCreate('lexiInterfaceZoom', next);
    await LexiInterfaceSettings.save('interfaceZoom', String(next), owner);
  }
}
