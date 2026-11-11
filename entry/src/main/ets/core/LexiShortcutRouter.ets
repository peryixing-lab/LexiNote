import { LexiHotkeySettings } from './LexiHotkeySettings';

/**
 * Global shortcut router. Key events never reach the workspace subtree unless a component there
 * holds focus, so the page root (Index) resolves bindings and hands the command to the registered
 * workspace handler.
 */
export class LexiShortcutRouter {
  private static handler: ((command: string) => void) | null = null;

  static register(handler: (command: string) => void): void {
    LexiShortcutRouter.handler = handler;
  }

  static unregister(): void {
    LexiShortcutRouter.handler = null;
  }

  static resolve(binding: string): string {
    if (!binding) { return ''; }
    const raw = AppStorage.get<string>('lexiHotkeyOverrides') || '[]';
    return LexiHotkeySettings.commandFor(raw, binding);
  }

  /** Returns true when the shortcut was dispatched to the workspace. */
  static dispatch(binding: string): boolean {
    const handler = LexiShortcutRouter.handler;
    if (!handler) { return false; }
    const command = LexiShortcutRouter.resolve(binding);
    if (!command) { return false; }
    try {
      handler(command);
    } catch {
      return false;
    }
    return true;
  }
}
