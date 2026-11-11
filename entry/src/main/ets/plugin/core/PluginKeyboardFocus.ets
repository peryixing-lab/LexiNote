/** Keeps native workspace shortcuts out of the active plugin's keyboard/IME path. */
export class PluginKeyboardFocus {
  private static owner: Object | undefined = undefined;
  private static visible: boolean = false;
  private static focused: boolean = false;

  static attach(owner: Object, visible: boolean): void {
    PluginKeyboardFocus.owner = owner;
    PluginKeyboardFocus.visible = visible;
    PluginKeyboardFocus.focused = false;
  }

  static setVisible(owner: Object, visible: boolean): void {
    if (PluginKeyboardFocus.owner !== owner) { return; }
    PluginKeyboardFocus.visible = visible;
    if (!visible) { PluginKeyboardFocus.focused = false; }
  }

  static setFocused(owner: Object, focused: boolean): void {
    if (PluginKeyboardFocus.owner !== owner) { return; }
    PluginKeyboardFocus.focused = PluginKeyboardFocus.visible && focused;
  }

  static active(): boolean {
    return PluginKeyboardFocus.visible && PluginKeyboardFocus.focused;
  }

  static detach(owner: Object): void {
    if (PluginKeyboardFocus.owner !== owner) { return; }
    PluginKeyboardFocus.owner = undefined;
    PluginKeyboardFocus.visible = false;
    PluginKeyboardFocus.focused = false;
  }
}
