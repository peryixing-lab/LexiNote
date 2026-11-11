import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginLimits } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

/**
 * Private key/value storage per workspace and plugin (P10).
 *
 * One namespaced record per plugin in the application key-value store, never inside the
 * user's knowledge base and never shared with notes. Persisted as `[[key, value], ...]`
 * pairs because ArkTS cannot index arbitrary JSON objects.
 */
export class PluginDataStore {
  private static prefix: string = 'plugin.data.';
  private static keyPattern: RegExp = /^[A-Za-z0-9_.-]{1,64}$/;

  private static recordKey(pluginId: string, vaultId: string): string {
    return `${PluginDataStore.prefix}${vaultId}:${pluginId}`;
  }

  private static async readAll(pluginId: string, vaultId: string = ''): Promise<Map<string, string>> {
    const owner = vaultId || await LexiStorageService.getActiveVaultId();
    const key = PluginDataStore.recordKey(pluginId, owner);
    let raw = await LexiStorageService.getRawValue(key, '');
    if (raw === '') {
      // Preserve old plugin preferences only in their original workspace, including an explicit empty record.
      raw = await LexiStorageService.getSetting('workspacePreferencesLegacyOwner:v1', '') === owner ?
        await LexiStorageService.getRawValue(`${PluginDataStore.prefix}${pluginId}`, '[]') : '[]';
      await LexiStorageService.setRawValue(key, raw);
    }
    const result = new Map<string, string>();
    try {
      const pairs = JSON.parse(raw) as string[][];
      if (Array.isArray(pairs)) {
        for (const pair of pairs) {
          if (Array.isArray(pair) && pair.length >= 2 && typeof pair[0] === 'string' && typeof pair[1] === 'string') {
            result.set(pair[0], pair[1]);
          }
        }
      }
    } catch (error) {
      // A corrupted record degrades to empty storage instead of blocking the plugin.
    }
    return result;
  }

  private static async writeAll(pluginId: string, values: Map<string, string>, vaultId: string): Promise<void> {
    const pairs: string[][] = [];
    for (const entry of values.entries()) { pairs.push([entry[0], entry[1]]); }
    await LexiStorageService.setRawValue(PluginDataStore.recordKey(pluginId, vaultId), JSON.stringify(pairs));
  }

  static async get(pluginId: string, key: string, vaultId: string = ''): Promise<string> {
    PluginDataStore.assertKey(key);
    const values = await PluginDataStore.readAll(pluginId, vaultId);
    const value = values.get(key);
    return value === undefined ? '' : value;
  }

  /** Stores a string value. The caller decides the JSON shape; the host enforces size. */
  static async set(pluginId: string, key: string, value: string, vaultId: string = ''): Promise<void> {
    PluginDataStore.assertKey(key);
    if (typeof value !== 'string') {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '值必须是字符串');
    }
    const owner = vaultId || await LexiStorageService.getActiveVaultId();
    const values = await PluginDataStore.readAll(pluginId, owner);
    if (!values.has(key) && values.size >= PluginLimits.MAX_STORAGE_KEYS) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, '插件存储键数量超过上限');
    }
    values.set(key, value);
    let total = 0;
    for (const entry of values.entries()) { total += entry[0].length + entry[1].length; }
    if (total > PluginLimits.MAX_STORAGE_BYTES) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, '插件存储空间超过上限');
    }
    await PluginDataStore.writeAll(pluginId, values, owner);
  }

  static async remove(pluginId: string, key: string, vaultId: string = ''): Promise<void> {
    PluginDataStore.assertKey(key);
    const owner = vaultId || await LexiStorageService.getActiveVaultId();
    const values = await PluginDataStore.readAll(pluginId, owner);
    if (!values.has(key)) { return; }
    values.delete(key);
    await PluginDataStore.writeAll(pluginId, values, owner);
  }

  /** Serialized `{ key: value }` object handed to the runtime at boot. */
  static async snapshot(pluginId: string, vaultId: string = ''): Promise<string> {
    const values = await PluginDataStore.readAll(pluginId, vaultId);
    const parts: string[] = [];
    for (const entry of values.entries()) {
      parts.push(`${JSON.stringify(entry[0])}:${JSON.stringify(entry[1])}`);
    }
    return `{${parts.join(',')}}`;
  }

  static async keys(pluginId: string): Promise<string[]> {
    const values = await PluginDataStore.readAll(pluginId);
    return Array.from(values.keys());
  }

  static async clear(pluginId: string): Promise<void> {
    await LexiStorageService.setRawValue(PluginDataStore.recordKey(pluginId, await LexiStorageService.getActiveVaultId()), '[]');
  }

  static async usage(pluginId: string): Promise<number> {
    const raw = await LexiStorageService.getRawValue(PluginDataStore.recordKey(pluginId, await LexiStorageService.getActiveVaultId()), '[]');
    return raw.length;
  }

  private static assertKey(key: string): void {
    if (typeof key !== 'string' || !PluginDataStore.keyPattern.test(key)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '存储键名非法');
    }
  }
}
