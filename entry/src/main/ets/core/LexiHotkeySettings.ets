import { LEXI_COMMANDS } from './LexiCommands';
import { LexiStorageService } from './LexiStorageService';

export interface LexiHotkeyOverride {
  id: string;
  bindings: string[];
}

/** Canonical bindings use Ctrl/Meta/Alt/Shift and an uppercase physical key name. */
export class LexiHotkeySettings {
  private static writes: Promise<void> = Promise.resolve();
  private static cachedRaw: string = '';
  private static cachedRows: LexiHotkeyOverride[] = [];
  static async flush(): Promise<void> { await LexiHotkeySettings.writes.catch((): void => {}); }

  static async load(): Promise<void> {
    const raw = await LexiStorageService.getSetting('hotkeyOverrides', '[]');
    AppStorage.setOrCreate('lexiHotkeyOverrides', JSON.stringify(LexiHotkeySettings.parse(raw)));
  }

  static parse(raw: string): LexiHotkeyOverride[] {
    if (raw === LexiHotkeySettings.cachedRaw) { return LexiHotkeySettings.cachedRows; }
    let rows: LexiHotkeyOverride[] = [];
    try {
      const parsed = JSON.parse(raw) as LexiHotkeyOverride[];
      if (Array.isArray(parsed)) {
        rows = parsed.filter((row: LexiHotkeyOverride): boolean => !!row && typeof row.id === 'string' &&
          Array.isArray(row.bindings)).map((row: LexiHotkeyOverride): LexiHotkeyOverride => {
            return { id: row.id, bindings: row.bindings.filter((key: string): boolean => typeof key === 'string') };
          });
      }
    } catch { rows = []; }
    LexiHotkeySettings.cachedRaw = raw;
    LexiHotkeySettings.cachedRows = rows;
    return rows;
  }

  static commandFor(raw: string, binding: string): string {
    let matched = '';
    if (!binding) { return ''; }
    for (const command of LEXI_COMMANDS) {
      if (LexiHotkeySettings.bindings(raw, command.id, LexiHotkeySettings.defaults(command.id)).includes(binding)) {
        if (matched) { return ''; } matched = command.id;
      }
    }
    return matched;
  }

  static defaults(id: string): string[] {
    if (id === 'link-open') { return ['Alt+ENTER']; }
    if (id === 'link-open-tab') { return ['Ctrl+ENTER']; }
    if (id === 'link-open-group') { return ['Ctrl+Alt+ENTER']; }
    if (id === 'link-open-window') { return ['Ctrl+Alt+Shift+ENTER']; }
    if (id === 'rename') { return ['F2']; }
    if (id === 'find') { return ['Ctrl+F']; }
    if (id === 'replace') { return ['Ctrl+Alt+F']; }
    if (id === 'search-all') { return ['Ctrl+Shift+F']; }
    if (id === 'editor-link') { return ['Ctrl+K']; }
    if (id === 'editor-comment') { return ['Ctrl+/']; }
    if (id === 'editor-todo') { return ['Ctrl+L']; }
    if (id === 'editor-delete-paragraph') { return ['Ctrl+D']; }
    if (id === 'property-add') { return ['Ctrl+;']; }
    if (id === 'tab-reopen') { return ['Ctrl+Shift+T']; }
    if (id === 'back') { return ['Ctrl+Alt+ARROWLEFT']; }
    if (id === 'forward') { return ['Ctrl+Alt+ARROWRIGHT']; }
    if (id === 'switcher') { return ['Ctrl+O']; }
    if (id === 'palette') { return ['Ctrl+P']; }
    if (id === 'reading') { return ['Ctrl+E']; }
    if (id === 'editor-bold') { return ['Ctrl+B']; }
    if (id === 'editor-italic') { return ['Ctrl+I']; }
    if (id === 'new') { return ['Ctrl+N']; }
    if (id === 'save') { return ['Ctrl+S']; }
    if (id === 'close-tab') { return ['Ctrl+W']; }
    if (id === 'graph') { return ['Ctrl+G']; }
    if (id === 'settings') { return ['Ctrl+,']; }
    if (id === 'help') { return ['F1']; }
    if (id === 'tab-prev') { return ['Ctrl+Shift+TAB']; }
    if (id === 'tab-next') { return ['Ctrl+TAB']; }
    if (id.startsWith('tab-') && id.length === 5 && id.charAt(4) >= '1' && id.charAt(4) <= '9') {
      return ['Ctrl+' + id.charAt(4)];
    }
    return [];
  }

  static bindings(raw: string, id: string, defaults: string[]): string[] {
    const row = LexiHotkeySettings.parse(raw).find((item: LexiHotkeyOverride): boolean => item.id === id);
    return row ? row.bindings.slice() : defaults;
  }

  static async set(id: string, bindings: string[] | null): Promise<void> {
    const owner = LexiStorageService.settingsOwner();
    const write = LexiHotkeySettings.writes.catch((): void => {}).then(async (): Promise<void> => {
      const raw = await LexiStorageService.getSetting('hotkeyOverrides', '[]', owner);
      const rows = LexiHotkeySettings.parse(raw).filter((item: LexiHotkeyOverride): boolean => item.id !== id);
      if (bindings !== null) { rows.push({ id: id, bindings: bindings }); }
      const next = JSON.stringify(rows);
      await LexiStorageService.setSetting('hotkeyOverrides', next, owner);
      if (LexiStorageService.settingsOwner() === owner) { AppStorage.setOrCreate('lexiHotkeyOverrides', next); }
    });
    LexiHotkeySettings.writes = write;
    await write;
  }

  /** Modifier keys never form a binding on their own. */
  static isModifierCode(code: number): boolean {
    return (code >= 2045 && code <= 2048) || code === 2072 || code === 2073 || code === 2076 || code === 2077;
  }

  static isFunctionKey(code: number): boolean {
    return code >= 2090 && code <= 2101;
  }

  static keyName(code: number): string {
    if (code >= 2017 && code <= 2042) { return String.fromCharCode(65 + code - 2017); }
    if (code >= 2000 && code <= 2009) { return String(code - 2000); }
    if (LexiHotkeySettings.isFunctionKey(code)) { return 'F' + String(code - 2089); }
    if (code === 2012) { return 'ARROWUP'; }
    if (code === 2013) { return 'ARROWDOWN'; }
    if (code === 2014) { return 'ARROWLEFT'; }
    if (code === 2015) { return 'ARROWRIGHT'; }
    if (code === 2043) { return ','; }
    if (code === 2044) { return '.'; }
    if (code === 2056) { return '`'; }
    if (code === 2057) { return '-'; }
    if (code === 2058) { return '='; }
    if (code === 2059) { return '['; }
    if (code === 2060) { return ']'; }
    if (code === 2061) { return '\\'; }
    if (code === 2062) { return ';'; }
    if (code === 2063) { return '\''; }
    if (code === 2064) { return '/'; }
    if (code === 2055) { return 'BACKSPACE'; }
    if (code === 2071) { return 'DELETE'; }
    if (code === 2083) { return 'INSERT'; }
    if (code === 2081) { return 'HOME'; }
    if (code === 2082) { return 'END'; }
    if (code === 2068) { return 'PAGEUP'; }
    if (code === 2069) { return 'PAGEDOWN'; }
    if (code === 2049) { return 'TAB'; }
    if (code === 2054) { return 'ENTER'; }
    if (code === 2050) { return 'SPACE'; }
    if (code === 2070) { return 'ESCAPE'; }
    if (code === 2079) { return 'PRINTSCREEN'; }
    return '';
  }

  static fromEvent(event: KeyEvent): string {
    const code = event.keyCode;
    if (LexiHotkeySettings.isModifierCode(code)) { return ''; }
    const key = LexiHotkeySettings.keyName(code);
    if (!key) { return ''; }
    const parts: string[] = [];
    if (event.getModifierKeyState && event.getModifierKeyState(['Ctrl'])) { parts.push('Ctrl'); }
    if (event.metaKey === 1) { parts.push('Meta'); }
    if (event.getModifierKeyState && event.getModifierKeyState(['Alt'])) { parts.push('Alt'); }
    if (event.getModifierKeyState && event.getModifierKeyState(['Shift'])) { parts.push('Shift'); }
    if (parts.length === 0 && !LexiHotkeySettings.isFunctionKey(code)) { return ''; }
    parts.push(key);
    return parts.join('+');
  }
}
