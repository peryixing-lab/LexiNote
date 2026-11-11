import { PluginLimits } from '../model/PluginModels';

class PluginResource {
  token: string = '';
  pluginId: string = '';
  label: string = '';
  dispose: () => void = (): void => {};
}

/**
 * Tracks everything a plugin acquired so `disable` can release it even when the plugin's
 * own `onunload` throws (P05). Release is idempotent, so a repeated disable is a no-op.
 */
export class PluginResourceTracker {
  private static resources: Map<string, PluginResource> = new Map();
  private static order: string[] = [];
  private static counter: number = 0;
  private static released: number = 0;
  private static failures: number = 0;

  static add(pluginId: string, label: string, dispose: () => void): string {
    if (PluginResourceTracker.resources.size >= 1024) {
      const oldest = PluginResourceTracker.order.shift();
      if (oldest) { PluginResourceTracker.resources.delete(oldest); }
    }
    PluginResourceTracker.counter++;
    const token = `${pluginId}::${PluginResourceTracker.counter}`;
    const resource = new PluginResource();
    resource.token = token;
    resource.pluginId = pluginId;
    resource.label = label;
    resource.dispose = dispose;
    PluginResourceTracker.resources.set(token, resource);
    PluginResourceTracker.order.push(token);
    return token;
  }

  static releaseToken(token: string): boolean {
    const resource = PluginResourceTracker.resources.get(token);
    if (!resource) { return false; }
    PluginResourceTracker.resources.delete(token);
    PluginResourceTracker.order = PluginResourceTracker.order.filter((item: string): boolean => item !== token);
    PluginResourceTracker.released++;
    try {
      resource.dispose();
    } catch (error) {
      // A throwing cleanup never aborts the remaining cleanup.
      PluginResourceTracker.failures++;
    }
    return true;
  }

  /** Releases in reverse acquisition order; returns how many resources were released. */
  static releaseAll(pluginId: string): number {
    let count = 0;
    const tokens = PluginResourceTracker.order.slice(0).reverse();
    for (const token of tokens) {
      const resource = PluginResourceTracker.resources.get(token);
      if (!resource) { continue; }
      if (resource.pluginId !== pluginId) { continue; }
      PluginResourceTracker.releaseToken(token);
      count++;
    }
    return count;
  }

  static count(pluginId: string): number {
    let count = 0;
    for (const token of PluginResourceTracker.order) {
      const resource = PluginResourceTracker.resources.get(token);
      if (resource && resource.pluginId === pluginId) { count++; }
    }
    return count;
  }

  static total(): number {
    return PluginResourceTracker.resources.size;
  }

  static releasedCount(): number {
    return PluginResourceTracker.released;
  }

  static failureCount(): number {
    return PluginResourceTracker.failures;
  }

  static limit(): number {
    return PluginLimits.MAX_SUBSCRIPTIONS_PER_PLUGIN;
  }

  static reset(): void {
    PluginResourceTracker.resources = new Map<string, PluginResource>();
    PluginResourceTracker.order = [];
    PluginResourceTracker.counter = 0;
    PluginResourceTracker.released = 0;
    PluginResourceTracker.failures = 0;
  }
}
