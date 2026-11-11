import { PluginWorkspaceSnapshot } from '../model/PluginModels';

/**
 * Window/workspace snapshot published by the UI (P08).
 *
 * The host must never guess which tab has focus by looking at the database: only the page
 * that owns the tab strip knows. Multiple windows are supported by keying on `windowId`.
 */
export class LexiWorkspaceBridge {
  private static snapshots: Map<string, PluginWorkspaceSnapshot> = new Map();
  private static activeWindow: string = '';
  private static revision: number = 0;

  static publish(snapshot: PluginWorkspaceSnapshot): void {
    LexiWorkspaceBridge.revision++;
    snapshot.revision = LexiWorkspaceBridge.revision;
    LexiWorkspaceBridge.snapshots.set(snapshot.windowId || 'main', snapshot);
    if (!LexiWorkspaceBridge.activeWindow || snapshot.windowId === LexiWorkspaceBridge.activeWindow) {
      LexiWorkspaceBridge.activeWindow = snapshot.windowId || 'main';
    }
  }

  static setActiveWindow(windowId: string): void {
    if (LexiWorkspaceBridge.snapshots.has(windowId)) {
      LexiWorkspaceBridge.activeWindow = windowId;
      LexiWorkspaceBridge.revision++;
    }
  }

  static current(): PluginWorkspaceSnapshot {
    const snapshot = LexiWorkspaceBridge.snapshots.get(LexiWorkspaceBridge.activeWindow);
    if (snapshot) { return snapshot; }
    for (const candidate of LexiWorkspaceBridge.snapshots.values()) { return candidate; }
    return new PluginWorkspaceSnapshot();
  }

  static of(windowId: string): PluginWorkspaceSnapshot | undefined {
    return LexiWorkspaceBridge.snapshots.get(windowId);
  }

  static clear(windowId: string): void {
    LexiWorkspaceBridge.snapshots.delete(windowId);
    if (LexiWorkspaceBridge.activeWindow === windowId) {
      LexiWorkspaceBridge.activeWindow = '';
      LexiWorkspaceBridge.revision++;
    }
  }

  static revisionOf(): number {
    return LexiWorkspaceBridge.revision;
  }

  static reset(): void {
    LexiWorkspaceBridge.snapshots = new Map<string, PluginWorkspaceSnapshot>();
    LexiWorkspaceBridge.activeWindow = '';
    LexiWorkspaceBridge.revision = 0;
  }
}
