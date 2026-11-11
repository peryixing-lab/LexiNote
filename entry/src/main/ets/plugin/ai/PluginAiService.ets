import { http } from '@kit.NetworkKit';
import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginAiChatParams, PluginAiConfigureParams } from '../model/PluginContracts';
import { PluginLimits } from '../model/PluginModels';
import { PluginAiQuota, PluginAiBalance } from './PluginAiQuota';

/**
 * Host-brokered model inference for plugins (capability `ai.inference`).
 *
 * Design rules:
 *  - Plugin code never opens a socket: the plugin runtime WebView keeps
 *    `blockNetwork(true)` and the CSP keeps `connect-src 'none'`.
 *  - The API key lives in the host's preference store and is never returned to a plugin;
 *    `ai.status` only says whether a key exists.
 *  - The request body is built and validated here, so a plugin cannot smuggle arbitrary
 *    headers, URLs (base URL is user-owned configuration) or native handles.
 *  - Both OpenAI-compatible and Anthropic-compatible wires are supported, matching the
 *    model profiles the built-in Harness used to offer.
 *
 * The call is intentionally non-streaming: one RPC round-trip with a 120 s host budget
 * (see `PluginLimits.AI_TIMEOUT_MS`). Streaming is listed as future work in
 * docs/plugin-system/07-harness-plugin.md.
 */

const AI_CONFIG_KEY: string = 'pluginAiConfig.v1';
const DEFAULT_BASE_URL: string = 'https://api.deepseek.com';
const DEFAULT_MODEL: string = 'deepseek-chat';

export class PluginAiConfig {
  provider: string = 'openai-compatible';
  baseUrl: string = DEFAULT_BASE_URL;
  model: string = DEFAULT_MODEL;
  apiKey: string = '';
  maxTokens: number = 8192;
  temperature: number = 0.3;

  static of(raw: string): PluginAiConfig {
    const config = new PluginAiConfig();
    if (!raw || raw.length === 0) { return config; }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      if (typeof parsed['provider'] === 'string') { config.provider = parsed['provider'] as string; }
      if (typeof parsed['baseUrl'] === 'string') { config.baseUrl = parsed['baseUrl'] as string; }
      if (typeof parsed['model'] === 'string') { config.model = parsed['model'] as string; }
      if (typeof parsed['apiKey'] === 'string') { config.apiKey = parsed['apiKey'] as string; }
      if (typeof parsed['maxTokens'] === 'number') { config.maxTokens = parsed['maxTokens'] as number; }
      if (typeof parsed['temperature'] === 'number') { config.temperature = parsed['temperature'] as number; }
    } catch (error) {
      // A corrupt preference must fall back to defaults, not block plugin boot.
    }
    return config;
  }
}

export class PluginAiStatus {
  configured: boolean = false;
  provider: string = '';
  model: string = '';
  baseUrl: string = '';
  maxTokens: number = 0;
  temperature: number = 0;
  balanceProvider: string = '';
}

export class PluginAiToolCall {
  id: string = '';
  name: string = '';
  arguments: string = '{}';
}

export class PluginAiUsage {
  inputTokens: number = 0;
  outputTokens: number = 0;
}

export class PluginAiReply {
  text: string = '';
  reasoning: string = '';
  toolCalls: PluginAiToolCall[] = [];
  finishReason: string = 'stop';
  model: string = '';
  usage: PluginAiUsage = new PluginAiUsage();
}

export class PluginAiService {
  private static cached: PluginAiConfig | undefined = undefined;
  private static balanceCache: PluginAiBalance | undefined = undefined;
  private static balanceConfig: PluginAiConfig | undefined = undefined;

  /** Test hook: forget the cached configuration. */
  static resetForTests(): void {
    PluginAiService.cached = undefined;
    PluginAiService.balanceCache = undefined;
    PluginAiService.balanceConfig = undefined;
  }

  private static async load(): Promise<PluginAiConfig> {
    if (PluginAiService.cached) { return PluginAiService.cached; }
    const raw = await LexiStorageService.getSetting(AI_CONFIG_KEY, '{}');
    const config = PluginAiConfig.of(raw);
    PluginAiService.cached = config;
    return config;
  }

  private static async persist(config: PluginAiConfig): Promise<void> {
    await LexiStorageService.setSetting(AI_CONFIG_KEY, JSON.stringify(config));
    PluginAiService.cached = config;
    PluginAiService.balanceCache = undefined;
  }

  private static normalizeProvider(raw: string): string {
    const value = raw.trim().toLowerCase();
    if (value === 'openai-compatible' || value === 'deepseek-openai' || value === 'openai') {
      return 'openai-compatible';
    }
    if (value === 'anthropic-compatible' || value === 'deepseek-anthropic' || value === 'anthropic') {
      return 'anthropic-compatible';
    }
    return '';
  }

  private static isAnthropic(config: PluginAiConfig): boolean {
    if (config.provider === 'anthropic-compatible') { return true; }
    const url = config.baseUrl.toLowerCase();
    return url.includes('/anthropic') || url.endsWith('/v1/messages');
  }

  private static endpointUrl(config: PluginAiConfig): string {
    const base = (config.baseUrl.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
    if (PluginAiService.isAnthropic(config)) {
      if (base.endsWith('/v1/messages')) { return base; }
      if (/\/v\d+$/.test(base)) { return `${base}/messages`; }
      return `${base}/v1/messages`;
    }
    if (base.endsWith('/chat/completions')) { return base; }
    if (/\/v\d+$/.test(base)) { return `${base}/chat/completions`; }
    return `${base}/v1/chat/completions`;
  }

  private static statusOf(config: PluginAiConfig): PluginAiStatus {
    const status = new PluginAiStatus();
    status.configured = config.apiKey.trim().length > 0 && config.model.trim().length > 0;
    status.provider = config.provider;
    status.model = config.model;
    status.baseUrl = config.baseUrl;
    status.maxTokens = config.maxTokens;
    status.temperature = config.temperature;
    status.balanceProvider = PluginAiQuota.provider(config.baseUrl);
    return status;
  }

  static async status(): Promise<string> {
    const config = await PluginAiService.load();
    return JSON.stringify(PluginAiService.statusOf(config));
  }

  /**
   * Binds or updates the model service. `apiKey` is optional: an empty value keeps the
   * stored key so the plugin settings UI never has to read it back. `clear: true`
   * resets the whole binding.
   */
  static async configure(paramsJson: string): Promise<string> {
    const params = PluginAiConfigureParams.from(paramsJson);
    // Validate a copy: a rejected patch must not mutate the active cached binding.
    const config = params.clear ? new PluginAiConfig()
      : PluginAiConfig.of(JSON.stringify(await PluginAiService.load()));
    if (params.clear) {
      await PluginAiService.persist(config);
      return JSON.stringify(PluginAiService.statusOf(config));
    }
    if (params.provider.length > 0) {
      const provider = PluginAiService.normalizeProvider(params.provider);
      if (provider.length === 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT,
          '模型服务类型只能是 openai-compatible 或 anthropic-compatible');
      }
      config.provider = provider;
    }
    if (params.baseUrl.length > 0) {
      const baseUrl = params.baseUrl.trim();
      if (!/^https?:\/\/[^\s\/?#@]+(?:\/[^\s?#]*)?$/i.test(baseUrl)) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'Base URL 需为完整的 http(s) 地址，不含账号、查询参数或片段');
      }
      if (baseUrl.length > 8192) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'Base URL 最多支持 8192 字符');
      }
      if (config.apiKey.length > 0 && baseUrl.replace(/\/+$/, '') !== config.baseUrl && params.apiKey.trim().length === 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '更换 Base URL 时请重新填写 API Key');
      }
      config.baseUrl = baseUrl.replace(/\/+$/, '');
    }
    if (params.model.length > 0) {
      const model = params.model.trim();
      if (model.length === 0 || model.length > 128) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '模型名称长度必须在 1-128 之间');
      }
      config.model = model;
    }
    if (params.apiKey.length > 0) {
      if (params.apiKey.length > 8192) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'API Key 过长');
      }
      config.apiKey = params.apiKey.trim();
    }
    if (params.maxTokens > 0) {
      config.maxTokens = Math.max(512, Math.min(32768, Math.floor(params.maxTokens)));
    }
    if (params.temperature >= 0) {
      config.temperature = Math.max(0, Math.min(2, params.temperature));
    }
    if (config.apiKey.trim().length === 0) {
      // A binding without a key cannot chat; refusing here keeps the store honest even if
      // a plugin UI forgets its own validation.
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '首次绑定需要提供 API Key');
    }
    await PluginAiService.persist(config);
    return JSON.stringify(PluginAiService.statusOf(config));
  }

  private static emptySchema(): Record<string, Object> {
    const properties: Record<string, Object> = {};
    const required: string[] = [];
    const schema: Record<string, Object> = {
      'type': 'object',
      'properties': properties,
      'required': required
    };
    return schema;
  }

  private static openAiTools(tools: Record<string, Object>[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < tools.length; index++) {
      const tool = tools[index];
      const name = typeof tool['name'] === 'string' ? (tool['name'] as string) : '';
      if (name.length === 0) { continue; }
      const description = typeof tool['description'] === 'string' ? (tool['description'] as string) : '';
      const schema = tool['parameters'] !== undefined && tool['parameters'] !== null
        ? tool['parameters'] as Object : PluginAiService.emptySchema();
      const fn: Record<string, Object> = {
        'name': name,
        'description': description,
        'parameters': schema
      };
      list.push({ 'type': 'function', 'function': fn });
    }
    return list;
  }

  private static toolCallsOf(message: Record<string, Object>): Record<string, Object>[] {
    const raw = message['toolCalls'];
    if (!Array.isArray(raw)) { return []; }
    const calls: Record<string, Object>[] = [];
    const source = raw as Record<string, Object>[];
    for (let index = 0; index < source.length; index++) {
      const call = source[index];
      const id = typeof call['id'] === 'string' ? (call['id'] as string) : `call_${index}`;
      const name = typeof call['name'] === 'string' ? (call['name'] as string) : '';
      if (name.length === 0) { continue; }
      const args = typeof call['arguments'] === 'string' ? (call['arguments'] as string) : '{}';
      const wire: Record<string, Object> = { 'name': name, 'arguments': args.length > 0 ? args : '{}' };
      calls.push({ 'id': id, 'type': 'function', 'function': wire });
    }
    return calls;
  }

  private static openAiMessages(messages: Record<string, Object>[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < messages.length; index++) {
      const message = messages[index];
      const role = typeof message['role'] === 'string' ? (message['role'] as string) : 'user';
      const content = typeof message['content'] === 'string' ? (message['content'] as string) : '';
      if (role === 'assistant') {
        const entry: Record<string, Object> = { 'role': 'assistant', 'content': content };
        const calls = PluginAiService.toolCallsOf(message);
        if (calls.length > 0) { entry['tool_calls'] = calls; }
        list.push(entry);
      } else if (role === 'tool') {
        const toolCallId = typeof message['toolCallId'] === 'string'
          ? (message['toolCallId'] as string) : '';
        list.push({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': content.length > 0 ? content : 'Done'
        });
      } else {
        list.push({ 'role': role === 'system' ? 'system' : 'user', 'content': content });
      }
    }
    return list;
  }

  private static anthropicTools(tools: Record<string, Object>[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < tools.length; index++) {
      const tool = tools[index];
      const name = typeof tool['name'] === 'string' ? (tool['name'] as string) : '';
      if (name.length === 0) { continue; }
      const description = typeof tool['description'] === 'string' ? (tool['description'] as string) : '';
      const schema = tool['parameters'] !== undefined && tool['parameters'] !== null
        ? tool['parameters'] as Object : PluginAiService.emptySchema();
      list.push({ 'name': name, 'description': description, 'input_schema': schema });
    }
    return list;
  }

  private static anthropicMessages(messages: Record<string, Object>[],
    systemParts: string[]): Record<string, Object>[] {
    const list: Record<string, Object>[] = [];
    for (let index = 0; index < messages.length; index++) {
      const message = messages[index];
      const role = typeof message['role'] === 'string' ? (message['role'] as string) : 'user';
      const content = typeof message['content'] === 'string' ? (message['content'] as string) : '';
      if (role === 'system') {
        if (content.trim().length > 0) { systemParts.push(content); }
        continue;
      }
      if (role === 'assistant') {
        const blocks: Record<string, Object>[] = [];
        if (content.length > 0) { blocks.push({ 'type': 'text', 'text': content }); }
        const rawCalls = message['toolCalls'];
        if (Array.isArray(rawCalls)) {
          const calls = rawCalls as Record<string, Object>[];
          for (let callIndex = 0; callIndex < calls.length; callIndex++) {
            const call = calls[callIndex];
            const id = typeof call['id'] === 'string' ? (call['id'] as string) : `toolu_${callIndex}`;
            const name = typeof call['name'] === 'string' ? (call['name'] as string) : '';
            if (name.length === 0) { continue; }
            const argsText = typeof call['arguments'] === 'string' ? (call['arguments'] as string) : '{}';
            let input: Record<string, Object> = {};
            try {
              input = JSON.parse(argsText.length > 0 ? argsText : '{}') as Record<string, Object>;
            } catch (error) {
              input = {};
            }
            blocks.push({ 'type': 'tool_use', 'id': id, 'name': name, 'input': input });
          }
        }
        if (blocks.length > 0) { list.push({ 'role': 'assistant', 'content': blocks }); }
        continue;
      }
      const block: Record<string, Object> = role === 'tool'
        ? {
            'type': 'tool_result',
            'tool_use_id': typeof message['toolCallId'] === 'string' ? (message['toolCallId'] as string) : '',
            'content': content.length > 0 ? content : 'OK',
            'is_error': message['isError'] === true
          }
        : { 'type': 'text', 'text': content };
      const previous = list.length > 0 ? list[list.length - 1] : undefined;
      if (previous !== undefined && previous['role'] === 'user' && Array.isArray(previous['content'])) {
        const merged = previous['content'] as Record<string, Object>[];
        if (role === 'tool') {
          merged.unshift(block);
        } else {
          merged.push(block);
        }
      } else {
        list.push({ 'role': 'user', 'content': [block] });
      }
    }
    return list;
  }

  private static buildBody(config: PluginAiConfig, params: PluginAiChatParams): string {
    const anthropic = PluginAiService.isAnthropic(config);
    const systemParts: string[] = [];
    const messages = anthropic
      ? PluginAiService.anthropicMessages(params.messages, systemParts)
      : PluginAiService.openAiMessages(params.messages);
    const maxTokens = params.maxTokens > 0
      ? Math.max(512, Math.min(config.maxTokens, Math.floor(params.maxTokens)))
      : config.maxTokens;
    const temperature = params.temperature >= 0 ? params.temperature : config.temperature;
    if (anthropic) {
      const payload: Record<string, Object> = {
        'model': config.model,
        'max_tokens': Math.max(1024, Math.min(64000, maxTokens)),
        'messages': messages
      };
      if (systemParts.length > 0) { payload['system'] = systemParts.join('\n\n'); }
      if (temperature >= 0) { payload['temperature'] = temperature; }
      const tools = PluginAiService.anthropicTools(params.tools);
      if (tools.length > 0) { payload['tools'] = tools; }
      return JSON.stringify(payload);
    }
    const payload: Record<string, Object> = {
      'model': config.model,
      'messages': messages,
      'stream': false,
      'max_tokens': Math.max(512, Math.min(32768, maxTokens)),
      'temperature': temperature
    };
    const tools = PluginAiService.openAiTools(params.tools);
    if (tools.length > 0) { payload['tools'] = tools; }
    return JSON.stringify(payload);
  }

  private static parseOpenAi(raw: string, config: PluginAiConfig): PluginAiReply {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const choices = parsed['choices'] as Record<string, Object>[] | undefined;
    if (!Array.isArray(choices) || choices.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, '模型返回为空（choices 缺失）');
    }
    const choice = choices[0];
    const reply = new PluginAiReply();
    reply.model = config.model;
    const message = choice['message'] as Record<string, Object> | undefined;
    if (message) {
      if (typeof message['content'] === 'string') { reply.text = message['content'] as string; }
      if (typeof message['reasoning_content'] === 'string') {
        reply.reasoning = message['reasoning_content'] as string;
      }
      const calls = message['tool_calls'] as Record<string, Object>[] | undefined;
      if (Array.isArray(calls)) {
        for (let index = 0; index < calls.length; index++) {
          const call = calls[index];
          const fn = call['function'] as Record<string, Object> | undefined;
          if (!fn) { continue; }
          const toolCall = new PluginAiToolCall();
          toolCall.id = typeof call['id'] === 'string' ? (call['id'] as string) : `call_${index}`;
          toolCall.name = typeof fn['name'] === 'string' ? (fn['name'] as string) : '';
          toolCall.arguments = typeof fn['arguments'] === 'string' ? (fn['arguments'] as string) : '{}';
          if (toolCall.name.length > 0) { reply.toolCalls.push(toolCall); }
        }
      }
    }
    const finish = choice['finish_reason'];
    if (typeof finish === 'string') {
      reply.finishReason = finish === 'length' ? 'max-tokens' : finish;
    }
    const usage = parsed['usage'] as Record<string, Object> | undefined;
    if (usage) {
      if (typeof usage['prompt_tokens'] === 'number') { reply.usage.inputTokens = usage['prompt_tokens'] as number; }
      if (typeof usage['completion_tokens'] === 'number') { reply.usage.outputTokens = usage['completion_tokens'] as number; }
    }
    return reply;
  }

  private static parseAnthropic(raw: string, config: PluginAiConfig): PluginAiReply {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const reply = new PluginAiReply();
    reply.model = config.model;
    const content = parsed['content'] as Record<string, Object>[] | undefined;
    if (Array.isArray(content)) {
      for (let index = 0; index < content.length; index++) {
        const block = content[index];
        const type = typeof block['type'] === 'string' ? (block['type'] as string) : '';
        if (type === 'text' && typeof block['text'] === 'string') {
          const text = block['text'] as string;
          reply.text = reply.text.length > 0 ? `${reply.text}\n${text}` : text;
        } else if (type === 'thinking' && typeof block['thinking'] === 'string') {
          reply.reasoning = block['thinking'] as string;
        } else if (type === 'tool_use') {
          const call = new PluginAiToolCall();
          call.id = typeof block['id'] === 'string' ? (block['id'] as string) : `toolu_${index}`;
          call.name = typeof block['name'] === 'string' ? (block['name'] as string) : '';
          call.arguments = JSON.stringify(block['input'] !== undefined ? block['input'] : {});
          if (call.name.length > 0) { reply.toolCalls.push(call); }
        }
      }
    }
    const stop = parsed['stop_reason'];
    if (typeof stop === 'string') {
      reply.finishReason = stop === 'tool_use' ? 'tool_calls' : (stop === 'max_tokens' ? 'max-tokens' : stop);
    }
    const usage = parsed['usage'] as Record<string, Object> | undefined;
    if (usage) {
      if (typeof usage['input_tokens'] === 'number') { reply.usage.inputTokens = usage['input_tokens'] as number; }
      if (typeof usage['output_tokens'] === 'number') { reply.usage.outputTokens = usage['output_tokens'] as number; }
    }
    return reply;
  }

  private static errorDetail(raw: string): string {
    if (!raw || raw.length === 0) { return '模型服务返回空响应'; }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const error = parsed['error'] as Record<string, Object> | undefined;
      if (error && typeof error['message'] === 'string') {
        return (error['message'] as string).substring(0, 300);
      }
      if (typeof parsed['message'] === 'string') {
        return (parsed['message'] as string).substring(0, 300);
      }
    } catch (error) {
      // Fall through to the raw prefix.
    }
    return raw.substring(0, 300);
  }

  /** Runs one model turn. Returns a `PluginAiReply` JSON document. */
  static async chat(paramsJson: string): Promise<string> {
    const params = PluginAiChatParams.from(paramsJson);
    if (params.messages.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, 'ai.chat 需要至少一条消息');
    }
    if (params.messages.length > PluginLimits.MAX_AI_MESSAGES) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_MESSAGES} 条消息`);
    }
    if (params.tools.length > PluginLimits.MAX_AI_TOOLS) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, `单次对话最多 ${PluginLimits.MAX_AI_TOOLS} 个工具`);
    }
    const config = await PluginAiService.load();
    if (config.apiKey.trim().length === 0) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
        '尚未绑定模型服务：请在 Harness 面板中填写模型服务、模型名称与 API Key');
    }
    const anthropic = PluginAiService.isAnthropic(config);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (anthropic) {
      headers['x-api-key'] = config.apiKey;
      headers['anthropic-version'] = '2023-06-01';
      headers['Authorization'] = `Bearer ${config.apiKey}`;
    } else {
      headers['Authorization'] = `Bearer ${config.apiKey}`;
    }
    const request = http.createHttp();
    let rawText = '';
    try {
      const response = await request.request(PluginAiService.endpointUrl(config), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: PluginAiService.buildBody(config, params),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 120000
      });
      rawText = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
          `模型接口返回 HTTP ${response.responseCode}：${PluginAiService.errorDetail(rawText)}`);
      }
      const reply = anthropic
        ? PluginAiService.parseAnthropic(rawText, config)
        : PluginAiService.parseOpenAi(rawText, config);
      return JSON.stringify(reply);
    } catch (error) {
      const code = PluginErrors.codeOf(error);
      if (code !== PluginErrorCode.UNKNOWN) {
        if (error instanceof Error) { throw error; }
        throw PluginErrors.raise(code, PluginErrors.messageOf(error));
      }
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE,
        `访问模型服务失败：${PluginErrors.rawOf(error)}`);
    } finally {
      try { request.destroy(); } catch (error) { /* teardown must not throw */ }
    }
  }

  /** Bounded GET using the active binding only; no plugin-supplied URL or headers. */
  private static async readJson(config: PluginAiConfig, endpoint: string, quota: boolean): Promise<string> {
    if (!config.apiKey.trim()) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, '请先绑定模型服务');
    }
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    headers['Authorization'] = quota && PluginAiQuota.provider(config.baseUrl) === 'GLM Coding Plan'
      ? config.apiKey : `Bearer ${config.apiKey}`;
    if (!quota && PluginAiService.isAnthropic(config)) {
      headers['x-api-key'] = config.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    }
    const request = http.createHttp();
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.GET, header: headers,
        expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        // Never reflect a credential-bearing provider response into the plugin UI.
        throw new Error(`HTTP ${response.responseCode}，请检查服务地址、API Key 和套餐权限`);
      }
      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (raw.length > 2 * 1024 * 1024) { throw new Error('服务响应过大'); }
      return raw;
    } catch (error) {
      const detail = PluginErrors.rawOf(error).split(config.apiKey).join('[redacted]');
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, `查询失败：${detail.substring(0, 240)}`);
    } finally {
      try { request.destroy(); } catch (error) { /* teardown must not mask the result */ }
    }
  }

  static async models(): Promise<string> {
    const config = await PluginAiService.load();
    const endpoint = PluginAiService.endpointUrl(config).replace(/\/(?:chat\/completions|messages)$/, '/models');
    const raw = await PluginAiService.readJson(config, endpoint, false);
    try {
      const body = JSON.parse(raw) as Record<string, Object>;
      const data = body['data'] as Record<string, Object>[];
      if (!Array.isArray(data)) { throw new Error('模型列表缺少 data'); }
      const models: string[] = [];
      for (const item of data) {
        const id = item['id'];
        if (typeof id === 'string' && id.trim().length > 0 && id.length <= 128 && !models.includes(id)) {
          models.push(id);
        }
        if (models.length >= 300) { break; }
      }
      return JSON.stringify(models);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, '无法读取模型列表；可在模型设置中手动添加常用模型');
    }
  }

  static async balance(): Promise<string> {
    const config = await PluginAiService.load();
    const provider = PluginAiQuota.provider(config.baseUrl);
    if (!provider) { return JSON.stringify(new PluginAiBalance()); }
    const cached = PluginAiService.balanceCache;
    if (cached && PluginAiService.balanceConfig === config && Date.now() - cached.updatedAt < 60000) {
      return JSON.stringify(cached);
    }
    const raw = await PluginAiService.readJson(config, PluginAiQuota.endpoint(config.baseUrl), true);
    try {
      const balance = PluginAiQuota.parse(provider, raw);
      // A delayed response belongs to its original binding, never the newly selected one.
      if (PluginAiService.cached === config) {
        PluginAiService.balanceCache = balance;
        PluginAiService.balanceConfig = config;
      }
      return JSON.stringify(balance);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.MODEL_UNAVAILABLE, '未能读取余额或套餐额度，请检查 Key 类型和套餐权限');
    }
  }
}
