import { LexiI18n } from './LexiI18n';

class LexiReservedShortcut {
  binding: string = '';
  reason: string = '';

  constructor(binding: string, reason: string) {
    this.binding = binding;
    this.reason = reason;
  }
}

/**
 * Combinations the operating system (or the focused text field) consumes before the app sees them.
 * Binding one of these silently would produce a shortcut that never fires, so the recorder warns.
 */
export class LexiSystemShortcuts {
  private static readonly RESERVED: LexiReservedShortcut[] = [
    new LexiReservedShortcut('Alt+F4', '关闭窗口'),
    new LexiReservedShortcut('Alt+TAB', '切换窗口'),
    new LexiReservedShortcut('Alt+Shift+TAB', '切换窗口'),
    new LexiReservedShortcut('Alt+SPACE', '窗口菜单'),
    new LexiReservedShortcut('Ctrl+Alt+DELETE', '系统安全'),
    new LexiReservedShortcut('Ctrl+Shift+ESCAPE', '任务管理器'),
    new LexiReservedShortcut('Ctrl+SPACE', '输入法切换'),
    new LexiReservedShortcut('PRINTSCREEN', '屏幕截图'),
    new LexiReservedShortcut('Ctrl+C', '复制'),
    new LexiReservedShortcut('Ctrl+V', '粘贴'),
    new LexiReservedShortcut('Ctrl+X', '剪切'),
    new LexiReservedShortcut('Ctrl+Z', '撤销'),
    new LexiReservedShortcut('Ctrl+Shift+Z', '重做'),
    new LexiReservedShortcut('Ctrl+Y', '重做'),
    new LexiReservedShortcut('Ctrl+A', '全选')
  ];

  /** Raw (untranslated) reason for a reserved combination, or '' when the combination is free. */
  static reason(binding: string): string {
    if (!binding) { return ''; }
    if (binding.startsWith('Meta+')) { return '系统按键'; }
    for (const item of LexiSystemShortcuts.RESERVED) {
      if (item.binding === binding) { return item.reason; }
    }
    return '';
  }

  static translatedReason(binding: string, language: string = ''): string {
    const reason = LexiSystemShortcuts.reason(binding);
    return reason ? LexiI18n.text(reason, language) : '';
  }

  /** First reserved combination used by the given bindings, or '' when none of them is reserved. */
  static firstConflict(bindings: string[]): string {
    for (const binding of bindings) {
      if (LexiSystemShortcuts.reason(binding)) { return binding; }
    }
    return '';
  }
}
