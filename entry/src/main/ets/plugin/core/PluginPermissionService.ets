import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginCapability } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginJson } from '../model/PluginContracts';

/**
 * Capability grants (P14).
 *
 * Default deny: a manifest only *requests* capabilities, the user grants them, and every
 * RPC still re-checks the grant at call time so revoking takes effect immediately.
 */
export class PluginPermissionService {
  private static prefix: string = 'plugin.permissions.';
  private static cache: Map<string, string[]> = new Map();

  private static key(pluginId: string): string {
    return `${PluginPermissionService.prefix}${pluginId}`;
  }

  static async load(pluginId: string): Promise<string[]> {
    const raw = await LexiStorageService.getRawValue(PluginPermissionService.key(pluginId), '[]');
    const granted = PluginJson.stringArray(raw).filter((item: string): boolean => PluginCapability.known(item));
    PluginPermissionService.cache.set(pluginId, granted);
    return granted;
  }

  static async granted(pluginId: string): Promise<string[]> {
    const cached = PluginPermissionService.cache.get(pluginId);
    if (cached) { return cached.slice(0); }
    return PluginPermissionService.load(pluginId);
  }

  static async has(pluginId: string, capability: string): Promise<boolean> {
    if (!capability) { return true; }
    if (!PluginCapability.known(capability)) { return false; }
    const granted = await PluginPermissionService.granted(pluginId);
    return granted.includes(capability);
  }

  static async require(pluginId: string, capability: string): Promise<void> {
    if (!capability) { return; }
    if (!(await PluginPermissionService.has(pluginId, capability))) {
      throw PluginErrors.raise(PluginErrorCode.PERMISSION_DENIED,
        `插件 ${pluginId} 未获得能力 ${capability}`);
    }
  }

  /** Grants only capabilities the manifest actually requested. */
  static async grant(pluginId: string, capability: string, requested: string[]): Promise<string[]> {
    if (!PluginCapability.known(capability)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `未知能力 ${capability}`);
    }
    if (!requested.includes(capability)) {
      throw PluginErrors.raise(PluginErrorCode.PERMISSION_DENIED, '插件清单未声明该能力');
    }
    const current = await PluginPermissionService.granted(pluginId);
    if (!current.includes(capability)) { current.push(capability); }
    await PluginPermissionService.save(pluginId, current);
    return current;
  }

  static async revoke(pluginId: string, capability: string): Promise<string[]> {
    const current = await PluginPermissionService.granted(pluginId);
    const next = current.filter((item: string): boolean => item !== capability);
    await PluginPermissionService.save(pluginId, next);
    return next;
  }

  /** One explicit per-plugin consent saves the complete declared set atomically. */
  static async grantAll(pluginId: string, requested: string[]): Promise<string[]> {
    const capabilities: string[] = [];
    for (const capability of requested) {
      if (!PluginCapability.known(capability)) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `未知能力 ${capability}`);
      }
      if (!capabilities.includes(capability)) { capabilities.push(capability); }
    }
    await PluginPermissionService.save(pluginId, capabilities);
    return capabilities.slice(0);
  }

  private static async save(pluginId: string, capabilities: string[]): Promise<void> {
    await LexiStorageService.setRawValue(PluginPermissionService.key(pluginId), JSON.stringify(capabilities));
    PluginPermissionService.cache.set(pluginId, capabilities.slice(0));
  }

  static async reset(pluginId: string, requested: string[]): Promise<void> {
    PluginPermissionService.cache.delete(pluginId);
    await LexiStorageService.setRawValue(PluginPermissionService.key(pluginId), '[]');
    // A fresh grant never exceeds the manifest: nothing is granted implicitly.
    if (requested.length > 0) { await PluginPermissionService.load(pluginId); }
  }

  static async clearAll(pluginId: string): Promise<void> {
    PluginPermissionService.cache.delete(pluginId);
    await LexiStorageService.setRawValue(PluginPermissionService.key(pluginId), '[]');
  }

  static resetCache(): void {
    PluginPermissionService.cache = new Map<string, string[]>();
  }
}
