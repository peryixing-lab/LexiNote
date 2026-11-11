import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginLimits } from '../model/PluginModels';

/**
 * Registry of native plugin views (capability `ui.views`).
 *
 * A view is only a declaration: id, title and the plugin that owns it. The actual DOM
 * lives inside the plugin runtime WebView and is produced by the plugin's own
 * `ctx.views.register({ render })` callback; this registry exists so the host can
 * enforce the capability, detect duplicates and release declarations on unload.
 *
 * `requestOpen` publishes a small request through AppStorage. The workspace sidebar
 * watches that key, opens itself and asks the runtime to present the plugin view — the
 * host never renders plugin UI in native ArkUI.
 */
export class PluginViewRecord {
  pluginId: string = '';
  id: string = '';
  title: string = '';
  createdAt: number = 0;
}

export class PluginViewOpenRequest {
  pluginId: string = '';
  viewId: string = '';
  at: number = 0;
}

export class PluginViewRegistry {
  private static readonly ID_PATTERN: RegExp = /^[a-z0-9][a-z0-9._-]{0,63}$/;
  private static views: Map<string, PluginViewRecord[]> = new Map<string, PluginViewRecord[]>();

  static register(pluginId: string, id: string, title: string): PluginViewRecord {
    if (!PluginViewRegistry.ID_PATTERN.test(id)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
        '视图 id 必须是小写字母或数字开头、1-64 位的 a-z 0-9 . _ -');
    }
    const normalized = title.trim();
    if (normalized.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '视图标题不能为空');
    }
    const list = PluginViewRegistry.views.get(pluginId) ?? [];
    const existing = list.find((item: PluginViewRecord): boolean => item.id === id);
    if (existing) {
      existing.title = normalized.substring(0, 64);
      return existing;
    }
    if (list.length >= PluginLimits.MAX_VIEWS_PER_PLUGIN) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED,
        `单个插件最多注册 ${PluginLimits.MAX_VIEWS_PER_PLUGIN} 个视图`);
    }
    const record = new PluginViewRecord();
    record.pluginId = pluginId;
    record.id = id;
    record.title = normalized.substring(0, 64);
    record.createdAt = Date.now();
    list.push(record);
    PluginViewRegistry.views.set(pluginId, list);
    return record;
  }

  static unregister(pluginId: string, id: string): void {
    const list = PluginViewRegistry.views.get(pluginId);
    if (!list) { return; }
    const next = list.filter((item: PluginViewRecord): boolean => item.id !== id);
    if (next.length === 0) {
      PluginViewRegistry.views.delete(pluginId);
    } else {
      PluginViewRegistry.views.set(pluginId, next);
    }
  }

  static has(pluginId: string, id: string): boolean {
    const list = PluginViewRegistry.views.get(pluginId);
    return !!list && list.some((item: PluginViewRecord): boolean => item.id === id);
  }

  static list(pluginId: string): PluginViewRecord[] {
    return (PluginViewRegistry.views.get(pluginId) ?? []).slice(0);
  }

  static releasePlugin(pluginId: string): void {
    PluginViewRegistry.views.delete(pluginId);
  }

  static reset(): void {
    PluginViewRegistry.views = new Map<string, PluginViewRecord[]>();
  }

  /** Asks the workspace to surface a registered view. Returns false when unknown. */
  static requestOpen(pluginId: string, viewId: string): boolean {
    if (!PluginViewRegistry.has(pluginId, viewId)) { return false; }
    const request = new PluginViewOpenRequest();
    request.pluginId = pluginId;
    request.viewId = viewId;
    request.at = Date.now();
    try {
      AppStorage.setOrCreate<boolean>('lexiPluginRuntimeNeeded', true);
      AppStorage.setOrCreate<string>('lexiPluginOpenView', JSON.stringify(request));
    } catch (error) {
      // AppStorage is unavailable in unit tests; the registry state is still correct.
    }
    return true;
  }
}
