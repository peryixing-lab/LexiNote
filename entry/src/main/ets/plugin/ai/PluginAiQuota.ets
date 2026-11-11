/** Provider quota wire formats, adapted from LaoYueHanNi/dsh-token-usage (MIT).
 * See plugins/harness/THIRD_PARTY_NOTICES.txt for attribution. */
export class PluginAiQuotaWindow {
  label: string = '';
  unit: string = '';
  remainingValue?: number;
  maxValue?: number;
  usedPercent?: number;
  resetAt?: number;
}

export class PluginAiBalance {
  supported: boolean = false;
  provider: string = '';
  updatedAt: number = 0;
  windows: PluginAiQuotaWindow[] = [];
}

export class PluginAiQuota {
  static provider(baseUrl: string): string {
    // Match the authority, never a provider name appearing in a proxy path/query.
    const match = /^https:\/\/([^\/:?#@]+)(?::443)?(?:\/|$)/i.exec(baseUrl);
    const host = match ? match[1].toLowerCase() : '';
    if (host === 'api.deepseek.com') { return 'DeepSeek'; }
    if (host === 'openrouter.ai') { return 'OpenRouter'; }
    if (host === 'open.bigmodel.cn' || host === 'api.z.ai') { return 'GLM Coding Plan'; }
    if (host === 'api.kimi.com') { return 'Kimi For Coding'; }
    if (host === 'api.minimaxi.com' || host === 'api.minimax.io') { return 'MiniMax Coding Plan'; }
    return '';
  }

  static endpoint(baseUrl: string): string {
    const provider = PluginAiQuota.provider(baseUrl);
    if (provider === 'DeepSeek') { return 'https://api.deepseek.com/user/balance'; }
    if (provider === 'OpenRouter') { return 'https://openrouter.ai/api/v1/credits'; }
    if (provider === 'GLM Coding Plan') {
      const origin = /^https:\/\/api\.z\.ai(?::443)?(?:\/|$)/i.test(baseUrl)
        ? 'https://api.z.ai' : 'https://open.bigmodel.cn';
      return `${origin}/api/monitor/usage/quota/limit`;
    }
    if (provider === 'Kimi For Coding') { return 'https://api.kimi.com/coding/v1/usages'; }
    if (provider === 'MiniMax Coding Plan') {
      const origin = /^https:\/\/api\.minimax\.io(?::443)?(?:\/|$)/i.test(baseUrl)
        ? 'https://api.minimax.io' : 'https://api.minimaxi.com';
      return `${origin}/v1/api/openplatform/coding_plan/remains`;
    }
    return '';
  }

  private static record(raw: Object | undefined): Record<string, Object> {
    return raw !== null && typeof raw === 'object' && !Array.isArray(raw)
      ? raw as Record<string, Object> : {};
  }

  private static number(raw: Object | undefined): number {
    if (typeof raw !== 'number' && (typeof raw !== 'string' || raw.trim().length === 0)) { return NaN; }
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : NaN;
  }

  private static reset(raw: Object | undefined): number | undefined {
    const numeric = PluginAiQuota.number(raw);
    if (Number.isFinite(numeric) && numeric > 0) { return numeric < 1e12 ? numeric * 1000 : numeric; }
    const parsed = typeof raw === 'string' ? Date.parse(raw) : NaN;
    return Number.isFinite(parsed) ? parsed : undefined;
  }

  private static percent(label: string, used: number, reset: Object | undefined): PluginAiQuotaWindow {
    const window = new PluginAiQuotaWindow();
    window.label = label;
    window.usedPercent = Math.max(0, Math.min(100, used));
    window.resetAt = PluginAiQuota.reset(reset);
    return window;
  }

  private static legacy(label: string, raw: Object | undefined): PluginAiQuotaWindow | undefined {
    const record = PluginAiQuota.record(raw);
    const total = PluginAiQuota.number(record['limit']);
    const remaining = PluginAiQuota.number(record['remaining']);
    const used = PluginAiQuota.number(record['used']);
    if (!(total > 0) || (!Number.isFinite(remaining) && !Number.isFinite(used))) { return undefined; }
    return PluginAiQuota.percent(label, (Number.isFinite(remaining) ? total - remaining : used) / total * 100,
      record['resetTime']);
  }

  static parse(provider: string, raw: string): PluginAiBalance {
    const body = PluginAiQuota.record(JSON.parse(raw) as Object);
    const result = new PluginAiBalance();
    result.supported = true;
    result.provider = provider;
    result.updatedAt = Date.now();
    if (body['success'] === false) { throw new Error('套餐接口拒绝查询，请检查 API Key 与套餐权限'); }
    if (provider === 'DeepSeek') {
      const entries = body['balance_infos'] as Record<string, Object>[];
      if (Array.isArray(entries)) {
        for (const entry of entries) {
          const remaining = PluginAiQuota.number(entry['total_balance']);
          if (!Number.isFinite(remaining)) { continue; }
          const window = new PluginAiQuotaWindow();
          window.label = '账户余额';
          window.unit = typeof entry['currency'] === 'string' ? entry['currency'] as string : '';
          window.remainingValue = remaining;
          result.windows.push(window);
        }
      }
    } else if (provider === 'OpenRouter') {
      const data = body['data'] ? PluginAiQuota.record(body['data']) : body;
      const total = PluginAiQuota.number(data['total_credits']);
      const used = PluginAiQuota.number(data['total_usage']);
      if (Number.isFinite(total) && Number.isFinite(used)) {
        const window = new PluginAiQuotaWindow();
        window.label = '剩余额度';
        window.unit = 'USD';
        window.remainingValue = total - used;
        window.maxValue = total;
        result.windows.push(window);
      }
    } else if (provider === 'GLM Coding Plan') {
      const data = PluginAiQuota.record(body['data']);
      const limits = data['limits'] as Record<string, Object>[];
      if (Array.isArray(limits)) {
        for (const limit of limits) {
          const type = typeof limit['type'] === 'string' ? (limit['type'] as string).toUpperCase() : '';
          if (type && type !== 'TOKENS_LIMIT' && type !== 'CREDIT_LIMIT') { continue; }
          const total = PluginAiQuota.number(limit['usage']);
          const remaining = PluginAiQuota.number(limit['remaining']);
          const current = PluginAiQuota.number(limit['currentValue']);
          let used = PluginAiQuota.number(limit['percentage']);
          if (total > 0 && (Number.isFinite(remaining) || Number.isFinite(current))) {
            used = Math.max(Number.isFinite(remaining) ? total - remaining : 0,
              Number.isFinite(current) ? current : 0) / total * 100;
          }
          if (!Number.isFinite(used)) { continue; }
          const unit = PluginAiQuota.number(limit['unit']);
          const count = PluginAiQuota.number(limit['number']);
          const minutes = unit === 5 ? count : (unit === 3 ? count * 60 : (unit === 1 ? count * 1440 : NaN));
          const label = minutes > 0 && minutes <= 360 ? '5 小时额度'
            : (unit === 6 ? '每周额度' : (minutes > 18720 ? '每月额度'
              : (minutes > 360 ? '每周额度' : (unit === 3 ? '5 小时额度' : '套餐额度'))));
          result.windows.push(PluginAiQuota.percent(label, used, limit['nextResetTime']));
        }
      }
    } else if (provider === 'Kimi For Coding') {
      const usages = PluginAiQuota.record(body['usages']);
      const keys: string[] = ['limit_5h', 'limit_month_code', 'limit_month_total'];
      for (let index = 0; index < keys.length; index++) {
        if (index === 2 && result.windows.some((item: PluginAiQuotaWindow): boolean => item.label === '每月额度')) { continue; }
        const bucket = PluginAiQuota.record(usages[keys[index]]);
        const ratio = PluginAiQuota.number(bucket['used_ratio'] !== undefined ? bucket['used_ratio'] : bucket['usedRatio']);
        if (Number.isFinite(ratio) && ratio >= 0) {
          result.windows.push(PluginAiQuota.percent(index === 0 ? '5 小时额度' : '每月额度', ratio * 100,
            bucket['reset_time'] !== undefined ? bucket['reset_time'] : bucket['resetTime']));
        }
      }
      if (!result.windows.some((item: PluginAiQuotaWindow): boolean => item.label === '5 小时额度')) {
        const limits = body['limits'] as Record<string, Object>[];
        let latest: PluginAiQuotaWindow | undefined = undefined;
        if (Array.isArray(limits)) {
          for (const limit of limits) {
            const window = PluginAiQuota.legacy('5 小时额度', limit['detail']);
            if (window && (!latest || (window.resetAt || 0) >= (latest.resetAt || 0))) { latest = window; }
          }
        }
        if (latest) { result.windows.unshift(latest); }
      }
      const weekly = PluginAiQuota.legacy('每周额度', body['usage']);
      if (weekly) { result.windows.push(weekly); }
    } else if (provider === 'MiniMax Coding Plan') {
      const code = PluginAiQuota.number(PluginAiQuota.record(body['base_resp'])['status_code']);
      if (Number.isFinite(code) && code !== 0) { throw new Error('MiniMax 拒绝查询，请检查 Coding Plan Key'); }
      const remains = body['model_remains'] as Record<string, Object>[];
      const general = Array.isArray(remains) ? remains.find((item: Record<string, Object>): boolean => item['model_name'] === 'general') : undefined;
      if (general) {
        const prefixes: string[] = ['current_interval', 'current_weekly'];
        for (let index = 0; index < prefixes.length; index++) {
          const remaining = PluginAiQuota.number(general[`${prefixes[index]}_remaining_percent`]);
          const state = PluginAiQuota.number(general[`${prefixes[index]}_status`]);
          if (!Number.isFinite(remaining) || (state === 3 && remaining >= 100)) { continue; }
          result.windows.push(PluginAiQuota.percent(index === 0 ? '5 小时额度' : '每周额度', 100 - remaining,
            general[index === 0 ? 'end_time' : 'weekly_end_time']));
        }
      }
    }
    if (result.windows.length === 0) { throw new Error('接口未返回可识别的余额或套餐额度'); }
    return result;
  }
}
