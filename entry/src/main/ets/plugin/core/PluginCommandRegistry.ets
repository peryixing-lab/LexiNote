import { LEXI_COMMANDS, LexiCommand } from '../../core/LexiCommands';
import { PluginLimits } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

export class PluginCommandEntry {
  pluginId: string = '';
  localId: string = '';
  qualifiedId: string = '';
  title: string = '';
  available: boolean = true;
}

class PluginCommandBinding {
  entry: PluginCommandEntry = new PluginCommandEntry();
  run: () => Promise<void> = async (): Promise<void> => {};
}

/**
 * Dynamic plugin commands (P06).
 *
 * `LEXI_COMMANDS` stays a pure static array. The palette merges this registry into its
 * results, and unregistering a plugin makes its commands disappear immediately — no ghost
 * entries survive a disable.
 */
export class PluginCommandRegistry {
  private static bindings: Map<string, PluginCommandBinding> = new Map();
  private static order: string[] = [];
  private static changeRevision: number = 0;
  private static localPattern: RegExp = /^[a-z0-9][a-z0-9._-]{0,63}$/;

  private static notifyChanged(): void {
    PluginCommandRegistry.changeRevision++;
    try {
      AppStorage.setOrCreate<number>('lexiPluginCommandsRevision', PluginCommandRegistry.changeRevision);
    } catch (error) { /* The registry is also used without an ArkUI instance. */ }
  }

  static qualify(pluginId: string, localId: string): string {
    return `${pluginId}:${localId}`;
  }

  static isPluginCommand(commandId: string): boolean {
    return PluginCommandRegistry.bindings.has(commandId);
  }

  static reservedLocalId(localId: string): boolean {
    return LEXI_COMMANDS.some((command: LexiCommand): boolean => command.id === localId);
  }

  static register(pluginId: string, localId: string, title: string, run: () => Promise<void>): string {
    if (!PluginCommandRegistry.localPattern.test(localId)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '命令 id 只能包含小写字母、数字、点、下划线和短横线');
    }
    if (PluginCommandRegistry.reservedLocalId(localId)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `命令 id 与内置命令冲突：${localId}`);
    }
    if (typeof title !== 'string' || title.trim().length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '命令标题不能为空');
    }
    let owned = 0;
    for (const binding of PluginCommandRegistry.bindings.values()) {
      if (binding.entry.pluginId === pluginId) { owned++; }
    }
    if (owned >= PluginLimits.MAX_COMMANDS_PER_PLUGIN) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, '单个插件注册的命令过多');
    }
    const qualifiedId = PluginCommandRegistry.qualify(pluginId, localId);
    if (PluginCommandRegistry.bindings.has(qualifiedId)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `命令已注册：${qualifiedId}`);
    }
    const binding = new PluginCommandBinding();
    binding.entry.pluginId = pluginId;
    binding.entry.localId = localId;
    binding.entry.qualifiedId = qualifiedId;
    binding.entry.title = title.trim();
    binding.entry.available = true;
    binding.run = run;
    PluginCommandRegistry.bindings.set(qualifiedId, binding);
    PluginCommandRegistry.order.push(qualifiedId);
    PluginCommandRegistry.notifyChanged();
    return qualifiedId;
  }

  static unregister(qualifiedId: string): boolean {
    const existed = PluginCommandRegistry.bindings.delete(qualifiedId);
    PluginCommandRegistry.order = PluginCommandRegistry.order.filter((id: string): boolean => id !== qualifiedId);
    if (existed) { PluginCommandRegistry.notifyChanged(); }
    return existed;
  }

  static unregisterPlugin(pluginId: string): number {
    let removed = 0;
    for (const id of PluginCommandRegistry.order.slice(0)) {
      const binding = PluginCommandRegistry.bindings.get(id);
      if (binding && binding.entry.pluginId === pluginId) {
        PluginCommandRegistry.unregister(id);
        removed++;
      }
    }
    return removed;
  }

  static countForPlugin(pluginId: string): number {
    let count = 0;
    for (const binding of PluginCommandRegistry.bindings.values()) {
      if (binding.entry.pluginId === pluginId) { count++; }
    }
    return count;
  }

  static list(): PluginCommandEntry[] {
    const result: PluginCommandEntry[] = [];
    for (const id of PluginCommandRegistry.order) {
      const binding = PluginCommandRegistry.bindings.get(id);
      if (binding) { result.push(binding.entry); }
    }
    return result;
  }

  static visible(): PluginCommandEntry[] {
    return PluginCommandRegistry.list().filter((entry: PluginCommandEntry): boolean => entry.available);
  }

  static titleOf(qualifiedId: string): string {
    const binding = PluginCommandRegistry.bindings.get(qualifiedId);
    return binding ? binding.entry.title : '';
  }

  static async invoke(qualifiedId: string): Promise<void> {
    const binding = PluginCommandRegistry.bindings.get(qualifiedId);
    if (!binding) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `命令不存在：${qualifiedId}`); }
    if (!binding.entry.available) { throw PluginErrors.raise(PluginErrorCode.PLUGIN_DISABLED, '插件已停用'); }
    await binding.run();
  }

  static setAvailable(pluginId: string, available: boolean): void {
    let changed = false;
    for (const binding of PluginCommandRegistry.bindings.values()) {
      if (binding.entry.pluginId === pluginId && binding.entry.available !== available) {
        binding.entry.available = available;
        changed = true;
      }
    }
    if (changed) { PluginCommandRegistry.notifyChanged(); }
  }

  static reset(): void {
    PluginCommandRegistry.bindings = new Map<string, PluginCommandBinding>();
    PluginCommandRegistry.order = [];
    PluginCommandRegistry.notifyChanged();
  }
}
