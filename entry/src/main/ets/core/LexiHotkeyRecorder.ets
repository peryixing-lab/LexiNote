import { LEXI_COMMANDS } from './LexiCommands';
import { LexiHotkeySettings } from './LexiHotkeySettings';
import { LexiSystemShortcuts } from './LexiSystemShortcuts';
import { LexiI18n } from './LexiI18n';

/**
 * Shortcut recording state. The settings surface is an overlay that does not receive key events,
 * so the app root (Index) forwards keys here while a recording is active.
 */
export class LexiHotkeyRecorder {
  static readonly RECORDING_KEY: string = 'lexiHotkeyRecording';
  static readonly FEEDBACK_KEY: string = 'lexiHotkeyFeedback';

  private static language(): string {
    return AppStorage.get<string>('lexiLanguage') || LexiI18n.language();
  }

  private static text(source: string): string {
    return LexiI18n.text(source, LexiHotkeyRecorder.language());
  }

  static active(): string {
    return AppStorage.get<string>(LexiHotkeyRecorder.RECORDING_KEY) || '';
  }

  static begin(rowId: string): void {
    AppStorage.setOrCreate(LexiHotkeyRecorder.FEEDBACK_KEY, LexiHotkeyRecorder.text('请按下要绑定的组合键，Esc 取消。'));
    AppStorage.setOrCreate(LexiHotkeyRecorder.RECORDING_KEY, rowId);
  }

  static cancel(): void {
    AppStorage.setOrCreate(LexiHotkeyRecorder.RECORDING_KEY, '');
    AppStorage.setOrCreate(LexiHotkeyRecorder.FEEDBACK_KEY, '');
  }

  static notify(message: string): void {
    AppStorage.setOrCreate(LexiHotkeyRecorder.FEEDBACK_KEY, message);
  }

  /** Returns true when the event belongs to the recorder and must not reach the rest of the app. */
  static async handle(event: KeyEvent): Promise<boolean> {
    const rowId = LexiHotkeyRecorder.active();
    if (!rowId) { return false; }
    if (event.type !== KeyType.Down) { return true; }
    if (event.keyCode === 2070) { LexiHotkeyRecorder.cancel(); return true; }
    if (LexiHotkeySettings.isModifierCode(event.keyCode)) { return true; }
    const binding = LexiHotkeySettings.fromEvent(event);
    if (!binding) {
      LexiHotkeyRecorder.notify(LexiHotkeyRecorder.text('请同时按下修饰键（Ctrl / Alt / Shift）与按键，或直接按 F1–F12。'));
      return true;
    }
    const reserved = LexiSystemShortcuts.reason(binding);
    if (reserved) {
      LexiHotkeyRecorder.notify(LexiI18n.text('与系统快捷键冲突：{0}（{1}），请换一个组合键。',
        LexiHotkeyRecorder.language(), [binding, LexiI18n.text(reserved, LexiHotkeyRecorder.language())]));
      return true;
    }
    const raw = AppStorage.get<string>('lexiHotkeyOverrides') || '[]';
    for (const command of LEXI_COMMANDS) {
      if (command.id === rowId) { continue; }
      const occupied = LexiHotkeySettings.bindings(raw, command.id, LexiHotkeySettings.defaults(command.id));
      if (occupied.includes(binding)) {
        LexiHotkeyRecorder.notify(LexiHotkeyRecorder.text('快捷键已被占用：') +
          LexiI18n.text(command.title, LexiHotkeyRecorder.language()) + ' · ' + binding);
        return true;
      }
    }
    const current = LexiHotkeySettings.bindings(raw, rowId, LexiHotkeySettings.defaults(rowId));
    if (current.includes(binding)) { LexiHotkeyRecorder.cancel(); return true; }
    const next = current.slice();
    next.push(binding);
    try {
      await LexiHotkeySettings.set(rowId, next);
      AppStorage.setOrCreate(LexiHotkeyRecorder.RECORDING_KEY, '');
      LexiHotkeyRecorder.notify(LexiHotkeyRecorder.text('已绑定') + ' ' + binding);
    } catch {
      LexiHotkeyRecorder.notify(LexiHotkeyRecorder.text('快捷键保存失败，请重试。'));
    }
    return true;
  }
}
