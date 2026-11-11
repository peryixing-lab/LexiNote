import { PluginCoreEvent, PluginEventType, PluginLimits } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';

class PluginEventListener {
  id: number = 0;
  pluginId: string = '';
  type: string = '';
  handler: (event: PluginCoreEvent) => void = (_event: PluginCoreEvent): void => {};
}

/**
 * Ordered core event bus (P05).
 *
 * Events are only published after the storage layer committed. `seq` is monotonic per
 * vault so a plugin that misses a number knows its mirror is stale and must resynchronise
 * instead of trusting an outdated cache.
 */
export class PluginEventBus {
  private static nextId: number = 0;
  private static listeners: Map<number, PluginEventListener> = new Map();
  private static order: number[] = [];
  private static sequence: Map<string, number> = new Map();
  private static recent: PluginCoreEvent[] = [];
  private static errors: string[] = [];

  static subscribe(pluginId: string, type: string, handler: (event: PluginCoreEvent) => void): number {
    if (!PluginEventType.ALL.includes(type)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `未知事件 ${type}`);
    }
    if (PluginEventBus.countForPlugin(pluginId) >= PluginLimits.MAX_SUBSCRIPTIONS_PER_PLUGIN) {
      throw PluginErrors.raise(PluginErrorCode.QUOTA_EXCEEDED, '事件订阅数量超过上限');
    }
    PluginEventBus.nextId++;
    const listener = new PluginEventListener();
    listener.id = PluginEventBus.nextId;
    listener.pluginId = pluginId;
    listener.type = type;
    listener.handler = handler;
    PluginEventBus.listeners.set(listener.id, listener);
    PluginEventBus.order.push(listener.id);
    return listener.id;
  }

  static unsubscribe(subscriptionId: number): boolean {
    const existed = PluginEventBus.listeners.delete(subscriptionId);
    PluginEventBus.order = PluginEventBus.order.filter((id: number): boolean => id !== subscriptionId);
    return existed;
  }

  static unsubscribePlugin(pluginId: string): number {
    let removed = 0;
    for (const listener of Array.from(PluginEventBus.listeners.values())) {
      if (listener.pluginId === pluginId) {
        PluginEventBus.unsubscribe(listener.id);
        removed++;
      }
    }
    return removed;
  }

  static countForPlugin(pluginId: string): number {
    let count = 0;
    for (const listener of PluginEventBus.listeners.values()) {
      if (listener.pluginId === pluginId) { count++; }
    }
    return count;
  }

  static totalSubscriptions(): number {
    return PluginEventBus.listeners.size;
  }

  /** Assigns the next per-vault sequence number and returns it. */
  static nextSeq(vaultId: string): number {
    const current = PluginEventBus.sequence.get(vaultId);
    const next = (current === undefined ? 0 : current) + 1;
    PluginEventBus.sequence.set(vaultId, next);
    return next;
  }

  static lastSeq(vaultId: string): number {
    const current = PluginEventBus.sequence.get(vaultId);
    return current === undefined ? 0 : current;
  }

  /** Publishes an already built event. Returns the number of handlers invoked. */
  static publish(event: PluginCoreEvent): number {
    if (event.seq === 0) { event.seq = PluginEventBus.nextSeq(event.vaultId); }
    PluginEventBus.recent.push(event);
    if (PluginEventBus.recent.length > 64) { PluginEventBus.recent.shift(); }
    let delivered = 0;
    for (const id of PluginEventBus.order.slice(0)) {
      const listener = PluginEventBus.listeners.get(id);
      if (!listener) { continue; }
      if (listener.type !== event.type && listener.type !== '*') { continue; }
      delivered++;
      try {
        listener.handler(event);
      } catch (error) {
        // A failing plugin listener must never break the host or other plugins.
        PluginEventBus.errors.push(`${listener.pluginId}: ${PluginErrors.messageOf(error)}`);
        if (PluginEventBus.errors.length > 32) { PluginEventBus.errors.shift(); }
      }
    }
    return delivered;
  }

  static describe(event: PluginCoreEvent): PluginCoreEvent {
    return event;
  }

  static recentEvents(): PluginCoreEvent[] {
    return PluginEventBus.recent.slice(0);
  }

  static lastError(): string {
    return PluginEventBus.errors.length === 0 ? '' : PluginEventBus.errors[PluginEventBus.errors.length - 1];
  }

  static reset(): void {
    PluginEventBus.nextId = 0;
    PluginEventBus.listeners = new Map<number, PluginEventListener>();
    PluginEventBus.order = [];
    PluginEventBus.sequence = new Map<string, number>();
    PluginEventBus.recent = [];
    PluginEventBus.errors = [];
  }
}
