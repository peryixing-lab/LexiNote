/** Only user preferences belong to a workspace; install/storage bookkeeping stays global. */
export class LexiWorkspacePreferences {
  static readonly keys: string[] = [
    'theme', 'language', 'defaultTier', 'vaultViewMode', 'graphShowTags', 'lastEditedNoteId', 'lastBackup',
    'editorDefaultView', 'editorDefaultMode', 'editorShowTitle', 'editorLimitWidth', 'editorViewStatus',
    'appearanceAccent', 'appearanceThemeColors', 'appearanceFontSize', 'appearanceQuickZoom', 'appearanceSnippets',
    'interfaceTabHeaders', 'interfaceRibbon', 'interfaceHiddenCommands', 'interfaceZoom', 'interfaceSidebarWidth',
    'interfaceRightSidebarWidth', 'hotkeyOverrides', 'lastEditedMapId',
    'enabledPlugins'
  ];

  static contains(key: string): boolean { return LexiWorkspacePreferences.keys.includes(key); }
  static key(vaultId: string, key: string): string { return `workspace:${vaultId}:setting:${key}`; }
  static openMode(raw: string): string { return raw === 'current' || raw === 'new' ? raw : 'ask'; }
  static pluginIds(raw: string): string[] {
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed.filter((id: string): boolean => typeof id === 'string' && id.length > 0) : [];
    } catch { return []; }
  }
}
