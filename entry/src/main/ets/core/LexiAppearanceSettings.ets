import { KeyCode } from '@kit.InputKit';
import { LexiStorageService } from './LexiStorageService';
import { LexiTheme } from './LexiTheme';

export class LexiCssSnippet {
  id: string = '';
  name: string = '';
  css: string = '';
  enabled: boolean = true;
}

/** Shared appearance state. CSS is applied only in the ArkWeb note workspace. */
export class LexiAppearanceSettings {
  static readonly DEFAULT_ACCENT: string = LexiTheme.DEFAULT_ACCENT;
  /** Scrollers watch this flag: while it is true the wheel is zooming, so the page must not scroll. */
  static readonly WHEEL_ZOOM_LOCK_KEY: string = 'lexiWheelZoomLock';
  private static readonly ZOOM_BURST_MS: number = 400;
  private static readonly CTRL_WATCHDOG_MS: number = 6000;
  private static fontWriteQueue: Promise<void> = Promise.resolve();
  private static accentWriteQueue: Promise<void> = Promise.resolve();
  private static fontRevision: number = 0;
  private static savedFontSize: number = 16;
  private static ctrlHeld: boolean = false;
  private static zoomBurstDeadline: number = 0;
  private static zoomBurstTimer: number = -1;
  private static ctrlWatchdogTimer: number = -1;
  static async flush(): Promise<void> {
    await LexiAppearanceSettings.fontWriteQueue;
    await LexiAppearanceSettings.accentWriteQueue;
  }
  static async load(): Promise<void> {
    const accent = await LexiStorageService.getSetting('appearanceAccent', LexiAppearanceSettings.DEFAULT_ACCENT);
    const colors = LexiTheme.colors(await LexiStorageService.getSetting('appearanceThemeColors', ''), accent);
    const size = Number(await LexiStorageService.getSetting('appearanceFontSize', '16'));
    const quick = await LexiStorageService.getSetting('appearanceQuickZoom', 'false') === 'true';
    const snippets = await LexiStorageService.getSetting('appearanceSnippets', '[]');
    AppStorage.setOrCreate('lexiAccent', colors.accent);
    AppStorage.setOrCreate('lexiThemeColors', JSON.stringify(colors));
    LexiTheme.refresh();
    LexiAppearanceSettings.savedFontSize = LexiAppearanceSettings.clampSize(size);
    AppStorage.setOrCreate('lexiFontSize', LexiAppearanceSettings.savedFontSize);
    AppStorage.setOrCreate('lexiQuickZoom', quick);
    AppStorage.setOrCreate('lexiCssSnippets', JSON.stringify(LexiAppearanceSettings.parseSnippets(snippets)));
    LexiAppearanceSettings.ctrlHeld = false;
    LexiAppearanceSettings.zoomBurstDeadline = 0;
    AppStorage.setOrCreate(LexiAppearanceSettings.WHEEL_ZOOM_LOCK_KEY, false);
  }
  static validAccent(color: string): boolean { return /^#[0-9a-fA-F]{6}$/.test(color); }
  static clampSize(size: number): number { return Number.isFinite(size) ? Math.max(10, Math.min(32, Math.round(size))) : 16; }
  static parseSnippets(raw: string): LexiCssSnippet[] {
    try {
      const list = JSON.parse(raw) as LexiCssSnippet[];
      if (!Array.isArray(list)) { return []; }
      return list.filter((item: LexiCssSnippet): boolean => !!item && typeof item.id === 'string' &&
        typeof item.name === 'string' && typeof item.css === 'string' && typeof item.enabled === 'boolean');
    } catch { return []; }
  }
  static async setAccent(color: string): Promise<void> {
    if (!LexiAppearanceSettings.validAccent(color)) { return; }
    await LexiAppearanceSettings.writeColors('preset', 'accent', color.toUpperCase());
  }
  static async setOriginalColors(): Promise<void> {
    await LexiAppearanceSettings.writeColors('original', '', '');
  }
  static async setCustomColor(kind: string, color: string): Promise<void> {
    if ((kind !== 'accent' && kind !== 'background' && kind !== 'foreground') || !LexiTheme.validAccent(color)) {
      throw new Error('请输入 6 位十六进制颜色，如 #6E44D9');
    }
    await LexiAppearanceSettings.writeColors('custom', kind, color.toUpperCase());
  }
  private static async writeColors(mode: string, kind: string, color: string): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const dark = AppStorage.get<number>('lexiColorMode') === 1;
    const write = LexiAppearanceSettings.accentWriteQueue.then(async (): Promise<void> => {
      let colors = LexiTheme.colors(await LexiStorageService.getSetting('appearanceThemeColors', '', owner),
        await LexiStorageService.getSetting('appearanceAccent', LexiAppearanceSettings.DEFAULT_ACCENT, owner));
      if (mode === 'original') { colors = LexiTheme.colors(); }
      else if (mode === 'preset') { colors = LexiTheme.colors('', color); colors.mode = 'preset'; }
      else {
        if (colors.mode !== 'custom' || !colors.background || !colors.foreground) {
          const current = LexiTheme.resolvePalette(colors, dark);
          colors.background = current.background;
          colors.foreground = current.text_primary;
        }
        colors.mode = 'custom';
        if (kind === 'accent') { colors.accent = color; }
        else if (kind === 'background') { colors.background = color; }
        else { colors.foreground = color; }
        if (LexiTheme.contrast(colors.background, colors.foreground) < 4.5) {
          throw new Error('前景色与背景色对比度不足，请调整颜色');
        }
      }
      const raw = JSON.stringify(colors);
      await LexiStorageService.setSetting('appearanceThemeColors', raw, owner);
      if (LexiStorageService.settingsOwner() === owner) {
        AppStorage.setOrCreate('lexiAccent', colors.accent);
        AppStorage.setOrCreate('lexiThemeColors', raw);
        LexiTheme.refresh();
      }
    });
    LexiAppearanceSettings.accentWriteQueue = write.catch((): void => {});
    await write;
  }
  static async setFontSize(size: number): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const next = LexiAppearanceSettings.clampSize(size);
    const revision = ++LexiAppearanceSettings.fontRevision;
    AppStorage.setOrCreate('lexiFontSize', next);
    const write = LexiAppearanceSettings.fontWriteQueue.then(async (): Promise<void> => {
      await LexiStorageService.setSetting('appearanceFontSize', String(next), owner);
      if (LexiStorageService.settingsOwner() === owner) { LexiAppearanceSettings.savedFontSize = next; }
    });
    LexiAppearanceSettings.fontWriteQueue = write.catch((): void => {});
    try { await write; } catch (error) {
      if (revision === LexiAppearanceSettings.fontRevision && LexiStorageService.settingsOwner() === owner) {
        AppStorage.setOrCreate('lexiFontSize', LexiAppearanceSettings.savedFontSize);
      }
      throw error as Error;
    }
  }
  static async setQuickZoom(enabled: boolean): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    await LexiStorageService.setSetting('appearanceQuickZoom', String(enabled), owner);
    if (LexiStorageService.settingsOwner() !== owner) { return; }
    AppStorage.setOrCreate('lexiQuickZoom', enabled);
    if (!enabled) { LexiAppearanceSettings.releaseWheelZoomLock(); }
  }
  static async setSnippets(snippets: LexiCssSnippet[]): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const raw = JSON.stringify(snippets);
    await LexiStorageService.setSetting('appearanceSnippets', raw, owner);
    if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate('lexiCssSnippets', raw); }
  }
  private static quickZoomEnabled(): boolean { return AppStorage.get<boolean>('lexiQuickZoom') === true; }
  private static modifierDown(event: AxisEvent, key: string): boolean {
    if (!event.getModifierKeyState) { return false; }
    try { return event.getModifierKeyState([key]); } catch { return false; }
  }
  private static publishWheelZoomLock(): void {
    const locked = LexiAppearanceSettings.ctrlHeld ||
      LexiAppearanceSettings.zoomBurstDeadline > Date.now();
    if (AppStorage.get<boolean>(LexiAppearanceSettings.WHEEL_ZOOM_LOCK_KEY) !== locked) {
      AppStorage.setOrCreate(LexiAppearanceSettings.WHEEL_ZOOM_LOCK_KEY, locked);
    }
  }
  private static releaseWheelZoomLock(): void {
    LexiAppearanceSettings.ctrlHeld = false;
    LexiAppearanceSettings.zoomBurstDeadline = 0;
    if (LexiAppearanceSettings.zoomBurstTimer !== -1) {
      clearTimeout(LexiAppearanceSettings.zoomBurstTimer);
      LexiAppearanceSettings.zoomBurstTimer = -1;
    }
    if (LexiAppearanceSettings.ctrlWatchdogTimer !== -1) {
      clearTimeout(LexiAppearanceSettings.ctrlWatchdogTimer);
      LexiAppearanceSettings.ctrlWatchdogTimer = -1;
    }
    LexiAppearanceSettings.publishWheelZoomLock();
  }
  /**
   * Keeps a Ctrl+wheel zoom from scrolling the note at the same time.
   * Ctrl state comes from key events so the very first wheel tick is already blocked.
   */
  static trackModifierKey(event: KeyEvent): void {
    if (!LexiAppearanceSettings.quickZoomEnabled()) { return; }
    if (event.keyCode !== KeyCode.KEYCODE_CTRL_LEFT && event.keyCode !== KeyCode.KEYCODE_CTRL_RIGHT) { return; }
    if (event.type === KeyType.Down) {
      const wasHeld = LexiAppearanceSettings.ctrlHeld;
      LexiAppearanceSettings.ctrlHeld = true;
      LexiAppearanceSettings.publishWheelZoomLock();
      if (!wasHeld && LexiAppearanceSettings.ctrlWatchdogTimer === -1) {
        // A window switch can swallow the key-up; never leave the note unscrollable.
        LexiAppearanceSettings.ctrlWatchdogTimer = setTimeout((): void => {
          LexiAppearanceSettings.ctrlWatchdogTimer = -1;
          LexiAppearanceSettings.ctrlHeld = false;
          LexiAppearanceSettings.publishWheelZoomLock();
        }, LexiAppearanceSettings.CTRL_WATCHDOG_MS);
      }
    } else if (event.type === KeyType.Up) {
      LexiAppearanceSettings.ctrlHeld = false;
      if (LexiAppearanceSettings.ctrlWatchdogTimer !== -1) {
        clearTimeout(LexiAppearanceSettings.ctrlWatchdogTimer);
        LexiAppearanceSettings.ctrlWatchdogTimer = -1;
      }
      LexiAppearanceSettings.publishWheelZoomLock();
    }
  }
  /** @returns true when the wheel event was consumed by quick zoom. */
  static handleAxis(event: AxisEvent): boolean {
    if (!LexiAppearanceSettings.quickZoomEnabled()) { return false; }
    if (!LexiAppearanceSettings.modifierDown(event, 'Ctrl')) {
      // A plain wheel means the reader is scrolling again, so the zoom hold ends right away.
      LexiAppearanceSettings.endZoomBurst();
      return false;
    }
    const delta = event.getVerticalAxisValue();
    if (delta === 0) { return false; }
    LexiAppearanceSettings.beginZoomBurst();
    const current = AppStorage.get<number>('lexiFontSize') || 16;
    LexiAppearanceSettings.setFontSize(current + (delta > 0 ? -1 : 1)).catch((): void => {});
    return true;
  }
  private static endZoomBurst(): void {
    if (LexiAppearanceSettings.zoomBurstDeadline === 0 && LexiAppearanceSettings.zoomBurstTimer === -1) { return; }
    LexiAppearanceSettings.zoomBurstDeadline = 0;
    if (LexiAppearanceSettings.zoomBurstTimer !== -1) {
      clearTimeout(LexiAppearanceSettings.zoomBurstTimer);
      LexiAppearanceSettings.zoomBurstTimer = -1;
    }
    LexiAppearanceSettings.publishWheelZoomLock();
  }
  private static beginZoomBurst(): void {
    LexiAppearanceSettings.zoomBurstDeadline = Date.now() + LexiAppearanceSettings.ZOOM_BURST_MS;
    LexiAppearanceSettings.publishWheelZoomLock();
    if (LexiAppearanceSettings.zoomBurstTimer !== -1) {
      clearTimeout(LexiAppearanceSettings.zoomBurstTimer);
    }
    LexiAppearanceSettings.zoomBurstTimer = setTimeout((): void => {
      LexiAppearanceSettings.zoomBurstTimer = -1;
      LexiAppearanceSettings.publishWheelZoomLock();
    }, LexiAppearanceSettings.ZOOM_BURST_MS);
  }
}
