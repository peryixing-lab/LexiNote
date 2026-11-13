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
    const sidebarWidth = Number(await LexiStorageService.getSetting('interfaceSidebarWidth', '244'));
    const rightSidebarWidth = Number(await LexiStorageService.getSetting('interfaceRightSidebarWidth', '280'));
    AppStorage.setOrCreate('lexiTabHeaders', titles !== 'false');
    AppStorage.setOrCreate('lexiShowRibbon', ribbon !== 'false');
    AppStorage.setOrCreate('lexiHiddenRibbonCommands', JSON.stringify(LexiInterfaceSettings.parseHidden(hidden)));
    AppStorage.setOrCreate('lexiInterfaceZoom', LexiInterfaceSettings.clampZoom(zoom));
    AppStorage.setOrCreate('lexiSidebarWidth', LexiInterfaceSettings.clampSidebarWidth(sidebarWidth));
    AppStorage.setOrCreate('lexiRightSidebarWidth', LexiInterfaceSettings.clampRightSidebarWidth(rightSidebarWidth));
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
  static clampSidebarWidth(amount: number): number {
    return Number.isFinite(amount) ? Math.max(200, Math.min(480, amount)) : 244;
  }
  static sidebarWidthForWindow(amount: number, workspaceWidth: number, ribbonWidth: number, inspectorWidth: number): number {
    const limit = Math.max(200, workspaceWidth - ribbonWidth - inspectorWidth - 420);
    return Math.min(LexiInterfaceSettings.clampSidebarWidth(amount), limit);
  }
  static clampRightSidebarWidth(amount: number): number {
    return Number.isFinite(amount) ? Math.max(232, Math.min(560, amount)) : 280;
  }
  static rightSidebarWidthForWindow(amount: number, workspaceWidth: number, ribbonWidth: number, sidebarOpen: boolean): number {
    // Reserve the library's minimum width without depending on its computed width.
    const limit = Math.max(232, workspaceWidth - ribbonWidth - (sidebarOpen ? 200 : 0) - 420);
    return Math.min(LexiInterfaceSettings.clampRightSidebarWidth(amount), limit);
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
  static async setSidebarWidth(amount: number): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const next = LexiInterfaceSettings.clampSidebarWidth(amount);
    AppStorage.setOrCreate('lexiSidebarWidth', next);
    await LexiInterfaceSettings.save('interfaceSidebarWidth', String(next), owner);
  }
  static async setRightSidebarWidth(amount: number): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const next = LexiInterfaceSettings.clampRightSidebarWidth(amount);
    AppStorage.setOrCreate('lexiRightSidebarWidth', next);
    await LexiInterfaceSettings.save('interfaceRightSidebarWidth', String(next), owner);
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
