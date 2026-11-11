import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginRecord, PluginState } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

/**
 * Installed plugin catalogue + explicit state machine (P05).
 *
 * `NOT_INSTALLED -> VALIDATING -> INSTALLED_DISABLED -> STARTING -> ACTIVE -> STOPPING
 *  -> INSTALLED_DISABLED -> UNINSTALLING -> NOT_INSTALLED`; any failure lands in `FAILED`
 * and keeps its diagnostic so it can be retried safely.
 */
export class PluginRegistry {
  private static readonly STORAGE_KEY: string = 'plugin.records';
  private static records: Map<string, PluginRecord> = new Map();
  private static order: string[] = [];
  private static loaded: boolean = false;
  private static listeners: Array<() => void> = [];
  private static changeRevision: number = 0;
  private static lastError: string = '';

  private static transitions: Map<string, string[]> = new Map<string, string[]>([
    [PluginState.NOT_INSTALLED, [PluginState.VALIDATING]],
    [PluginState.VALIDATING, [PluginState.INSTALLED_DISABLED, PluginState.FAILED, PluginState.NOT_INSTALLED]],
    [PluginState.INSTALLED_DISABLED, [PluginState.STARTING, PluginState.UNINSTALLING, PluginState.VALIDATING]],
    [PluginState.STARTING, [PluginState.ACTIVE, PluginState.FAILED, PluginState.INSTALLED_DISABLED]],
    [PluginState.ACTIVE, [PluginState.STOPPING, PluginState.FAILED]],
    [PluginState.STOPPING, [PluginState.INSTALLED_DISABLED, PluginState.FAILED]],
    [PluginState.FAILED, [PluginState.STARTING, PluginState.UNINSTALLING, PluginState.INSTALLED_DISABLED]],
    [PluginState.UNINSTALLING, [PluginState.NOT_INSTALLED, PluginState.FAILED]]
  ]);

  static canTransition(from: string, to: string): boolean {
    const allowed = PluginRegistry.transitions.get(from);
    return allowed === undefined ? false : allowed.includes(to);
  }

  static async load(refresh: boolean = false): Promise<void> {
    if (PluginRegistry.loaded && !refresh) { return; }
    const raw = await LexiStorageService.getRawValue(PluginRegistry.STORAGE_KEY, '[]');
    const previous = PluginRegistry.records;
    const nextRecords = new Map<string, PluginRecord>();
    const nextOrder: string[] = [];
    try {
      const parsed = JSON.parse(raw) as PluginRecord[];
      if (!Array.isArray(parsed)) { throw new Error('插件清单格式错误'); }
      if (Array.isArray(parsed)) {
        for (const record of parsed) {
          if (!record || typeof record.id !== 'string' || record.id.length === 0) { continue; }
          const normalized = PluginRegistry.normalize(record);
          const local = previous.get(normalized.id);
          if (refresh && local && local.version === normalized.version && local.directory === normalized.directory &&
            local.main === normalized.main) {
            normalized.state = local.state;
            normalized.enabled = local.enabled;
            normalized.lastError = local.lastError;
          }
          nextRecords.set(normalized.id, normalized);
          nextOrder.push(normalized.id);
        }
      }
    } catch (error) {
      PluginRegistry.lastError = `插件清单读取失败：${PluginErrors.messageOf(error)}`;
      if (refresh) { throw new Error(PluginRegistry.lastError); }
    }
    PluginRegistry.records = nextRecords;
    PluginRegistry.order = nextOrder;
    PluginRegistry.loaded = true;
  }

  private static normalize(record: PluginRecord): PluginRecord {
    const copy = PluginRecord.clone(record);
    if (!copy.state) { copy.state = PluginState.INSTALLED_DISABLED; }
    if (!Array.isArray(copy.requestedCapabilities)) { copy.requestedCapabilities = []; }
    if (!Array.isArray(copy.grantedCapabilities)) { copy.grantedCapabilities = []; }
    if (!Array.isArray(copy.vaultScopes)) { copy.vaultScopes = []; }
    // A record restored from disk is never assumed to be running.
    if (copy.state === PluginState.ACTIVE || copy.state === PluginState.STARTING || copy.state === PluginState.STOPPING) {
      copy.state = PluginState.INSTALLED_DISABLED;
      copy.enabled = false;
    }
    return copy;
  }

  static async persist(): Promise<void> {
    for (const id of PluginRegistry.order) {
      const record = PluginRegistry.records.get(id);
      if (record) {
        await PluginRegistry.persistRecord(record);
      }
    }
  }

  private static async persistRecord(record: PluginRecord): Promise<void> {
    const saved = PluginRecord.clone(record);
    // Installed files are global. Runtime state and saved switches belong to a workspace.
    if (saved.state === PluginState.ACTIVE || saved.state === PluginState.STARTING || saved.state === PluginState.STOPPING) {
      saved.state = PluginState.INSTALLED_DISABLED;
    }
    saved.enabled = false;
    await LexiStorageService.updateInstalledPlugin(saved.id, JSON.stringify(saved));
  }

  static list(): PluginRecord[] {
    const result: PluginRecord[] = [];
    for (const id of PluginRegistry.order) {
      const record = PluginRegistry.records.get(id);
      if (record) { result.push(PluginRecord.clone(record)); }
    }
    return result;
  }

  static get(pluginId: string): PluginRecord | undefined {
    const record = PluginRegistry.records.get(pluginId);
    return record ? PluginRecord.clone(record) : undefined;
  }

  /** Mutable accessor reserved for the manager; never handed to plugins. */
  static mutable(pluginId: string): PluginRecord | undefined {
    return PluginRegistry.records.get(pluginId);
  }

  static async upsert(record: PluginRecord): Promise<PluginRecord> {
    const copy = PluginRecord.clone(record);
    await PluginRegistry.persistRecord(copy);
    if (!PluginRegistry.records.has(copy.id)) { PluginRegistry.order.push(copy.id); }
    PluginRegistry.records.set(copy.id, copy);
    PluginRegistry.notify();
    return PluginRecord.clone(copy);
  }

  static async remove(pluginId: string): Promise<void> {
    await LexiStorageService.updateInstalledPlugin(pluginId, '');
    PluginRegistry.records.delete(pluginId);
    PluginRegistry.order = PluginRegistry.order.filter((id: string): boolean => id !== pluginId);
    PluginRegistry.notify();
  }

  /** Runtime transitions stay local to this window and cannot overwrite the installed catalogue. */
  static async setState(pluginId: string, state: string, error: string = ''): Promise<void> {
    const record = PluginRegistry.records.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    if (record.state !== state && !PluginRegistry.canTransition(record.state, state)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
        `非法状态迁移 ${record.state} -> ${state}`);
    }
    record.state = state;
    record.lastError = error;
    record.updatedAt = Date.now();
    record.enabled = state === PluginState.ACTIVE;
    PluginRegistry.notify();
  }

  static async setEnabled(pluginId: string, enabled: boolean): Promise<void> {
    const record = PluginRegistry.records.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    record.enabled = enabled;
    record.updatedAt = Date.now();
    await LexiStorageService.setPluginEnabled(pluginId, enabled);
    PluginRegistry.notify();
  }

  static async setCapabilities(pluginId: string, granted: string[]): Promise<void> {
    const record = PluginRegistry.records.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    record.grantedCapabilities = granted.slice(0);
    record.updatedAt = Date.now();
    await PluginRegistry.persistRecord(record);
    PluginRegistry.notify();
  }

  static async setError(pluginId: string, error: string): Promise<void> {
    const record = PluginRegistry.records.get(pluginId);
    if (!record) { return; }
    record.lastError = error;
    record.updatedAt = Date.now();
    PluginRegistry.notify();
  }

  static onChange(listener: () => void): number {
    PluginRegistry.listeners.push(listener);
    return PluginRegistry.listeners.length;
  }

  static offChange(listener: () => void): void {
    PluginRegistry.listeners = PluginRegistry.listeners.filter((item: () => void): boolean => item !== listener);
  }

  static notify(): void {
    PluginRegistry.changeRevision++;
    for (const listener of PluginRegistry.listeners.slice(0)) {
      try {
        listener();
      } catch (error) {
        // UI listeners must not break the registry.
      }
    }
  }

  static revision(): number {
    return PluginRegistry.changeRevision;
  }

  static error(): string {
    return PluginRegistry.lastError;
  }

  static reset(): void {
    PluginRegistry.records = new Map<string, PluginRecord>();
    PluginRegistry.order = [];
    PluginRegistry.loaded = false;
    PluginRegistry.listeners = [];
    PluginRegistry.changeRevision = 0;
    PluginRegistry.lastError = '';
  }
}
