/**
 * Host actions for the settings page.
 *
 * Settings can be presented in two different containers: the desktop sheet
 * (owned by Index) and the phone route page (a separate HAP route). Both share
 * the same LexiSettingsWindow, so the page needs a small bridge to the live
 * workspace state instead of duplicating export/import/storage logic.
 */
export class LexiSettingsActions {
  static selectTheme: (theme: string) => void = (_theme: string): void => {};
  static selectTier: (tier: string) => void = (_tier: string): void => {};
  static exportSettingsPlugins: () => void = (): void => {};
  static importSettingsPlugins: () => void = (): void => {};
  static exportWorkspaceZip: () => void = (): void => {};
  static importWorkspaceZip: () => void = (): void => {};
  static exportMarkdown: () => void = (): void => {};
  static importFiles: () => void = (): void => {};
  static rebuildIndex: () => void = (): void => {};
  static chooseStorage: () => void = (): void => {};
  static showInfo: (title: string, message: string) => void = (_title: string, _message: string): void => {};
}
