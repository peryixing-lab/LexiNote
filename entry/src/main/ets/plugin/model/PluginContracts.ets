import { PluginFileRef, PluginLimits } from './PluginModels';
import { PluginErrorCode, PluginErrors } from './PluginErrors';

export class PluginProtocol {
  static readonly VERSION: number = 1;
  static readonly MAX_ID_LENGTH: number = 64;
}

/** Fixed method whitelist. A plugin can never name an arbitrary native symbol. */
export class PluginRpcMethod {
  static readonly PING: string = 'plugin.ping';

  static readonly VAULT_LIST: string = 'vault.listMarkdown';
  static readonly VAULT_GET_BY_PATH: string = 'vault.getByPath';
  static readonly VAULT_GET_BY_ID: string = 'vault.getById';
  static readonly VAULT_READ: string = 'vault.readText';
  static readonly VAULT_CREATE: string = 'vault.createText';
  static readonly VAULT_WRITE: string = 'vault.writeText';
  static readonly VAULT_RENAME: string = 'vault.renameText';
  static readonly VAULT_DELETE: string = 'vault.deleteText';

  static readonly METADATA_GET: string = 'metadata.get';

  static readonly WORKSPACE_ACTIVE_FILE: string = 'workspace.activeFile';
  static readonly WORKSPACE_OPEN_FILE: string = 'workspace.openFile';
  static readonly WORKSPACE_SNAPSHOT: string = 'workspace.snapshot';

  static readonly EDITOR_ACTIVE: string = 'editor.active';
  static readonly EDITOR_REPLACE_SELECTION: string = 'editor.replaceSelection';
  static readonly EDITOR_REPLACE_ALL: string = 'editor.replaceAll';

  static readonly COMMANDS_REGISTER: string = 'commands.register';
  static readonly COMMANDS_UNREGISTER: string = 'commands.unregister';

  static readonly EVENTS_ON: string = 'events.on';
  static readonly EVENTS_OFF: string = 'events.off';

  static readonly UI_NOTICE: string = 'ui.notice';
  static readonly UI_CONFIRM: string = 'ui.confirm';

  static readonly AI_STATUS: string = 'ai.status';
  static readonly AI_CHAT: string = 'ai.chat';
  static readonly AI_CONFIGURE: string = 'ai.configure';
  static readonly AI_MODELS: string = 'ai.models';
  static readonly AI_BALANCE: string = 'ai.balance';

  static readonly VIEWS_REGISTER: string = 'views.register';
  static readonly VIEWS_UNREGISTER: string = 'views.unregister';
  static readonly VIEWS_OPEN: string = 'views.open';

  static readonly STORAGE_GET: string = 'storage.get';
  static readonly STORAGE_SET: string = 'storage.set';
  static readonly STORAGE_REMOVE: string = 'storage.remove';

  static readonly ALL: string[] = [
    PluginRpcMethod.PING,
    PluginRpcMethod.VAULT_LIST,
    PluginRpcMethod.VAULT_GET_BY_PATH,
    PluginRpcMethod.VAULT_GET_BY_ID,
    PluginRpcMethod.VAULT_READ,
    PluginRpcMethod.VAULT_CREATE,
    PluginRpcMethod.VAULT_WRITE,
    PluginRpcMethod.VAULT_RENAME,
    PluginRpcMethod.VAULT_DELETE,
    PluginRpcMethod.METADATA_GET,
    PluginRpcMethod.WORKSPACE_ACTIVE_FILE,
    PluginRpcMethod.WORKSPACE_OPEN_FILE,
    PluginRpcMethod.WORKSPACE_SNAPSHOT,
    PluginRpcMethod.EDITOR_ACTIVE,
    PluginRpcMethod.EDITOR_REPLACE_SELECTION,
    PluginRpcMethod.EDITOR_REPLACE_ALL,
    PluginRpcMethod.COMMANDS_REGISTER,
    PluginRpcMethod.COMMANDS_UNREGISTER,
    PluginRpcMethod.EVENTS_ON,
    PluginRpcMethod.EVENTS_OFF,
    PluginRpcMethod.UI_NOTICE,
    PluginRpcMethod.UI_CONFIRM,
    PluginRpcMethod.AI_STATUS,
    PluginRpcMethod.AI_CHAT,
    PluginRpcMethod.AI_CONFIGURE,
    PluginRpcMethod.AI_MODELS,
    PluginRpcMethod.AI_BALANCE,
    PluginRpcMethod.VIEWS_REGISTER,
    PluginRpcMethod.VIEWS_UNREGISTER,
    PluginRpcMethod.VIEWS_OPEN,
    PluginRpcMethod.STORAGE_GET,
    PluginRpcMethod.STORAGE_SET,
    PluginRpcMethod.STORAGE_REMOVE
  ];

  static known(method: string): boolean {
    return PluginRpcMethod.ALL.includes(method);
  }

  /** Capability required to invoke a method, or '' for methods without one. */
  static capabilityOf(method: string): string {
    if (method.startsWith('vault.list') || method === PluginRpcMethod.VAULT_READ ||
      method === PluginRpcMethod.VAULT_GET_BY_PATH || method === PluginRpcMethod.VAULT_GET_BY_ID) { return 'vault.read'; }
    if (method === PluginRpcMethod.VAULT_CREATE || method === PluginRpcMethod.VAULT_WRITE ||
      method === PluginRpcMethod.VAULT_RENAME || method === PluginRpcMethod.VAULT_DELETE ||
      method.startsWith('vault.')) { return 'vault.write'; }
    if (method === PluginRpcMethod.METADATA_GET) { return 'notes.metadata.read'; }
    if (method === PluginRpcMethod.WORKSPACE_ACTIVE_FILE || method === PluginRpcMethod.WORKSPACE_OPEN_FILE ||
      method === PluginRpcMethod.WORKSPACE_SNAPSHOT) { return 'workspace.views'; }
    if (method === PluginRpcMethod.EDITOR_ACTIVE) { return 'editor.read'; }
    if (method === PluginRpcMethod.EDITOR_REPLACE_SELECTION || method === PluginRpcMethod.EDITOR_REPLACE_ALL) { return 'editor.write'; }
    if (method === PluginRpcMethod.COMMANDS_REGISTER || method === PluginRpcMethod.COMMANDS_UNREGISTER) { return 'ui.commands'; }
    if (method === PluginRpcMethod.UI_NOTICE) { return 'ui.notice'; }
    if (method === PluginRpcMethod.UI_CONFIRM) { return 'ui.modal'; }
    if (method.startsWith('ai.')) { return 'ai.inference'; }
    if (method.startsWith('views.')) { return 'ui.views'; }
    if (method.startsWith('storage.')) { return 'plugin.storage'; }
    return '';
  }
}

export class PluginRpcErrorInfo {
  code: string = PluginErrorCode.UNKNOWN;
  message: string = '';
  details: string = '';
}

/**
 * Inbound request. `params` is JSON text rather than an `unknown` value because ArkTS has
 * no `unknown`/`any`; each method parses its own typed parameter object.
 */
export class PluginRpcRequest {
  protocol: number = PluginProtocol.VERSION;
  id: string = '';
  pluginId: string = '';
  token: string = '';
  method: string = '';
  params: string = '{}';

  /**
   * `params` may arrive as JSON text (preferred) or as an inline object; the host normalizes
   * both to text so every method keeps a single parsing path.
   */
  static parse(raw: string): PluginRpcRequest {
    if (typeof raw !== 'string' || raw.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.PROTOCOL, '请求为空');
    }
    if (raw.length > PluginLimits.MAX_RPC_BYTES) {
      throw PluginErrors.raise(PluginErrorCode.RATE_LIMITED, '请求体超过大小上限');
    }
    let parsed: PluginRpcRequest;
    try {
      parsed = JSON.parse(raw) as PluginRpcRequest;
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.PROTOCOL, '请求不是合法 JSON');
    }
    const request = new PluginRpcRequest();
    if (typeof parsed.protocol === 'number') { request.protocol = parsed.protocol; }
    if (typeof parsed.id === 'string') { request.id = parsed.id; }
    if (typeof parsed.pluginId === 'string') { request.pluginId = parsed.pluginId; }
    if (typeof parsed.token === 'string') { request.token = parsed.token; }
    if (typeof parsed.method === 'string') { request.method = parsed.method; }
    if (typeof parsed.params === 'string') { request.params = parsed.params; }
    else if (parsed.params !== undefined && parsed.params !== null) {
      try {
        request.params = JSON.stringify(parsed.params);
      } catch (error) {
        throw PluginErrors.raise(PluginErrorCode.PROTOCOL, 'params 无法序列化');
      }
    }
    if (request.protocol !== PluginProtocol.VERSION) {
      throw PluginErrors.raise(PluginErrorCode.PROTOCOL, `不支持的协议版本 ${request.protocol}`);
    }
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(request.id)) {
      throw PluginErrors.raise(PluginErrorCode.PROTOCOL, '请求 id 非法');
    }
    if (request.method.length === 0 || !PluginRpcMethod.known(request.method)) {
      throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, `未知方法 ${request.method}`);
    }
    return request;
  }
}

/** Outbound response, already serialized for `runJavaScript`. */
export class PluginRpcResponse {
  protocol: number = PluginProtocol.VERSION;
  id: string = '';
  ok: boolean = false;
  result: string = '';
  error: PluginRpcErrorInfo = new PluginRpcErrorInfo();

  static success(id: string, resultJson: string): string {
    const response = new PluginRpcResponse();
    response.id = id;
    response.ok = true;
    response.result = resultJson;
    return JSON.stringify(response);
  }

  static failure(id: string, code: string, message: string): string {
    const response = new PluginRpcResponse();
    response.id = id;
    response.ok = false;
    response.error.code = code;
    response.error.message = message;
    return JSON.stringify(response);
  }
}

export class PluginRpcEvent {
  protocol: number = PluginProtocol.VERSION;
  type: string = 'event';
  pluginId: string = '';
  event: string = '';
  seq: number = 0;
  payload: string = '{}';

  static of(pluginId: string, event: string, seq: number, payloadJson: string): string {
    const message = new PluginRpcEvent();
    message.pluginId = pluginId;
    message.event = event;
    message.seq = seq;
    message.payload = payloadJson;
    return JSON.stringify(message);
  }
}

/** Generic deep copy used before any record leaves the host. */
export class PluginJson {
  static safeParse(raw: string, fallback: string = '{}'): string {
    if (typeof raw !== 'string' || raw.length === 0) { return fallback; }
    try {
      JSON.parse(raw);
      return raw;
    } catch (error) {
      return fallback;
    }
  }

  static stringArray(raw: string): string[] {
    try {
      const parsed = JSON.parse(raw) as string[];
      if (!Array.isArray(parsed)) { return []; }
      return parsed.filter((item: string): boolean => typeof item === 'string');
    } catch (error) {
      return [];
    }
  }

  static fileList(raw: string): PluginFileRef[] {
    try {
      const parsed = JSON.parse(raw) as PluginFileRef[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }
}

/** Per-method parameter classes (tolerant parse, explicit required-field checks). */
export class PluginParams {
  static requireString(value: string, field: string): string {
    if (typeof value !== 'string' || value.length === 0) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, `缺少参数 ${field}`);
    }
    return value;
  }
}

export class PluginPathParams {
  vaultId: string = '';
  path: string = '';

  static from(raw: string): PluginPathParams {
    const parsed = JSON.parse(raw) as PluginPathParams;
    const params = new PluginPathParams();
    if (typeof parsed.vaultId === 'string') { params.vaultId = parsed.vaultId; }
    if (typeof parsed.path === 'string') { params.path = parsed.path; }
    return params;
  }
}

export class PluginFileParams {
  vaultId: string = '';
  fileId: string = '';

  static from(raw: string): PluginFileParams {
    const parsed = JSON.parse(raw) as PluginFileParams;
    const params = new PluginFileParams();
    if (typeof parsed.vaultId === 'string') { params.vaultId = parsed.vaultId; }
    if (typeof parsed.fileId === 'string') { params.fileId = parsed.fileId; }
    return params;
  }
}

export class PluginCreateParams {
  vaultId: string = '';
  path: string = '';
  content: string = '';

  static from(raw: string): PluginCreateParams {
    const parsed = JSON.parse(raw) as PluginCreateParams;
    const params = new PluginCreateParams();
    if (typeof parsed.vaultId === 'string') { params.vaultId = parsed.vaultId; }
    if (typeof parsed.path === 'string') { params.path = parsed.path; }
    if (typeof parsed.content === 'string') { params.content = parsed.content; }
    return params;
  }
}

export class PluginWriteParams {
  vaultId: string = '';
  fileId: string = '';
  content: string = '';
  expectedUpdatedAt: number = 0;

  static from(raw: string): PluginWriteParams {
    const parsed = JSON.parse(raw) as PluginWriteParams;
    const params = new PluginWriteParams();
    if (typeof parsed.vaultId === 'string') { params.vaultId = parsed.vaultId; }
    if (typeof parsed.fileId === 'string') { params.fileId = parsed.fileId; }
    if (typeof parsed.content === 'string') { params.content = parsed.content; }
    if (typeof parsed.expectedUpdatedAt === 'number') { params.expectedUpdatedAt = parsed.expectedUpdatedAt; }
    return params;
  }
}

export class PluginRenameParams {
  vaultId: string = '';
  fileId: string = '';
  newPath: string = '';

  static from(raw: string): PluginRenameParams {
    const parsed = JSON.parse(raw) as PluginRenameParams;
    const params = new PluginRenameParams();
    if (typeof parsed.vaultId === 'string') { params.vaultId = parsed.vaultId; }
    if (typeof parsed.fileId === 'string') { params.fileId = parsed.fileId; }
    if (typeof parsed.newPath === 'string') { params.newPath = parsed.newPath; }
    return params;
  }
}

export class PluginNoticeParams {
  message: string = '';
  timeoutMs: number = 0;
  modifier: string = '';

  static from(raw: string): PluginNoticeParams {
    const parsed = JSON.parse(raw) as PluginNoticeParams;
    const params = new PluginNoticeParams();
    if (typeof parsed.message === 'string') { params.message = parsed.message; }
    if (typeof parsed.timeoutMs === 'number') { params.timeoutMs = parsed.timeoutMs; }
    if (typeof parsed.modifier === 'string') { params.modifier = parsed.modifier; }
    return params;
  }
}

export class PluginConfirmParams {
  title: string = '';
  body: string = '';

  static from(raw: string): PluginConfirmParams {
    const parsed = JSON.parse(raw) as PluginConfirmParams;
    const params = new PluginConfirmParams();
    if (typeof parsed.title === 'string') { params.title = parsed.title; }
    if (typeof parsed.body === 'string') { params.body = parsed.body; }
    return params;
  }
}

export class PluginStorageParams {
  key: string = '';
  value: string = '';

  static from(raw: string): PluginStorageParams {
    const parsed = JSON.parse(raw) as PluginStorageParams;
    const params = new PluginStorageParams();
    if (typeof parsed.key === 'string') { params.key = parsed.key; }
    if (typeof parsed.value === 'string') { params.value = parsed.value; }
    return params;
  }
}

/** One `ai.chat` turn. Messages/tools are JSON-safe records defined by the SDK. */
export class PluginAiChatParams {
  messages: Record<string, Object>[] = [];
  tools: Record<string, Object>[] = [];
  maxTokens: number = 0;
  temperature: number = -1;

  static from(raw: string): PluginAiChatParams {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const params = new PluginAiChatParams();
    if (Array.isArray(parsed['messages'])) {
      params.messages = parsed['messages'] as Record<string, Object>[];
    }
    if (Array.isArray(parsed['tools'])) {
      params.tools = parsed['tools'] as Record<string, Object>[];
    }
    if (typeof parsed['maxTokens'] === 'number') { params.maxTokens = parsed['maxTokens'] as number; }
    if (typeof parsed['temperature'] === 'number') { params.temperature = parsed['temperature'] as number; }
    return params;
  }
}

/** Model binding. The API key is stored on the host and never returned to the plugin. */
export class PluginAiConfigureParams {
  provider: string = '';
  baseUrl: string = '';
  model: string = '';
  apiKey: string = '';
  maxTokens: number = 0;
  temperature: number = -1;
  clear: boolean = false;

  static from(raw: string): PluginAiConfigureParams {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const params = new PluginAiConfigureParams();
    if (typeof parsed['provider'] === 'string') { params.provider = parsed['provider'] as string; }
    if (typeof parsed['baseUrl'] === 'string') { params.baseUrl = parsed['baseUrl'] as string; }
    if (typeof parsed['model'] === 'string') { params.model = parsed['model'] as string; }
    if (typeof parsed['apiKey'] === 'string') { params.apiKey = parsed['apiKey'] as string; }
    if (typeof parsed['maxTokens'] === 'number') { params.maxTokens = parsed['maxTokens'] as number; }
    if (typeof parsed['temperature'] === 'number') { params.temperature = parsed['temperature'] as number; }
    if (parsed['clear'] === true) { params.clear = true; }
    return params;
  }
}

export class PluginViewParams {
  id: string = '';
  title: string = '';

  static from(raw: string): PluginViewParams {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const params = new PluginViewParams();
    if (typeof parsed['id'] === 'string') { params.id = parsed['id'] as string; }
    if (typeof parsed['title'] === 'string') { params.title = parsed['title'] as string; }
    return params;
  }
}

export class PluginCommandParams {
  id: string = '';
  title: string = '';

  static from(raw: string): PluginCommandParams {
    const parsed = JSON.parse(raw) as PluginCommandParams;
    const params = new PluginCommandParams();
    if (typeof parsed.id === 'string') { params.id = parsed.id; }
    if (typeof parsed.title === 'string') { params.title = parsed.title; }
    return params;
  }
}

export class PluginEventParams {
  event: string = '';
  subscriptionId: number = 0;

  static from(raw: string): PluginEventParams {
    const parsed = JSON.parse(raw) as PluginEventParams;
    const params = new PluginEventParams();
    if (typeof parsed.event === 'string') { params.event = parsed.event; }
    if (typeof parsed.subscriptionId === 'number') { params.subscriptionId = parsed.subscriptionId; }
    return params;
  }
}

export class PluginEditorWriteParams {
  text: string = '';
  expectedVersion: number = 0;
  from: number = 0;
  to: number = 0;

  static from(raw: string): PluginEditorWriteParams {
    const parsed = JSON.parse(raw) as PluginEditorWriteParams;
    const params = new PluginEditorWriteParams();
    if (typeof parsed.text === 'string') { params.text = parsed.text; }
    if (typeof parsed.expectedVersion === 'number') { params.expectedVersion = parsed.expectedVersion; }
    if (typeof parsed.from === 'number') { params.from = parsed.from; }
    if (typeof parsed.to === 'number') { params.to = parsed.to; }
    return params;
  }
}

/** Boot payload pushed into the runtime page once the snapshot is ready. */
export class PluginRuntimeBoot {
  type: string = 'boot';
  protocol: number = PluginProtocol.VERSION;
  pluginId: string = '';
  kind: string = 'lexinote';
  token: string = '';
  runtimeVersion: string = '1';
  capabilities: string[] = [];
  vaultId: string = '';
  manifestJson: string = '{}';
  filesJson: string = '[]';
  activeFileJson: string = 'null';
  editorJson: string = 'null';
  settingsJson: string = '{}';
  dataJson: string = '{}';
  sourceCode: string = '';
  sourceName: string = 'main.js';
  stylesCss: string = '';
  warnings: string[] = [];

  toJson(): string {
    return JSON.stringify(this);
  }
}
