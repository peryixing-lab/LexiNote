export const PLUGIN_PROTOCOL_VERSION = 1;
export const PLUGIN_RUNTIME_VERSION = '1';

export const PluginKind = {
  LEXINOTE: 'lexinote',
  OBSIDIAN: 'obsidian'
} as const;

export type PluginKindValue = (typeof PluginKind)[keyof typeof PluginKind];

export const PluginLifecycleState = {
  NOT_INSTALLED: 'not-installed',
  VALIDATING: 'validating',
  INSTALLED_DISABLED: 'installed-disabled',
  STARTING: 'starting',
  ACTIVE: 'active',
  STOPPING: 'stopping',
  UNINSTALLING: 'uninstalling',
  FAILED: 'failed'
} as const;

export type PluginLifecycleStateValue =
  (typeof PluginLifecycleState)[keyof typeof PluginLifecycleState];

export const PluginCapability = {
  VAULT_READ: 'vault.read',
  VAULT_WRITE: 'vault.write',
  METADATA_READ: 'notes.metadata.read',
  EDITOR_READ: 'editor.read',
  EDITOR_WRITE: 'editor.write',
  WORKSPACE_VIEWS: 'workspace.views',
  UI_NOTICE: 'ui.notice',
  UI_MODAL: 'ui.modal',
  UI_COMMANDS: 'ui.commands',
  AI_INFERENCE: 'ai.inference',
  UI_VIEWS: 'ui.views',
  PLUGIN_STORAGE: 'plugin.storage',
  NETWORK: 'network'
} as const;

export type PluginCapabilityValue =
  (typeof PluginCapability)[keyof typeof PluginCapability];

export const ALL_PLUGIN_CAPABILITIES: readonly PluginCapabilityValue[] = [
  PluginCapability.VAULT_READ,
  PluginCapability.VAULT_WRITE,
  PluginCapability.METADATA_READ,
  PluginCapability.EDITOR_READ,
  PluginCapability.EDITOR_WRITE,
  PluginCapability.WORKSPACE_VIEWS,
  PluginCapability.UI_NOTICE,
  PluginCapability.UI_MODAL,
  PluginCapability.UI_COMMANDS,
  PluginCapability.AI_INFERENCE,
  PluginCapability.UI_VIEWS,
  PluginCapability.PLUGIN_STORAGE,
  PluginCapability.NETWORK
];

export const OBSIDIAN_BASELINE_CAPABILITIES: readonly PluginCapabilityValue[] = [
  PluginCapability.VAULT_READ,
  PluginCapability.VAULT_WRITE,
  PluginCapability.METADATA_READ,
  PluginCapability.EDITOR_READ,
  PluginCapability.EDITOR_WRITE,
  PluginCapability.WORKSPACE_VIEWS,
  PluginCapability.UI_NOTICE,
  PluginCapability.UI_COMMANDS,
  PluginCapability.PLUGIN_STORAGE
];

export const PluginEventType = {
  VAULT_CREATED: 'vault.created',
  VAULT_MODIFIED: 'vault.modified',
  VAULT_RENAMED: 'vault.renamed',
  VAULT_DELETED: 'vault.deleted',
  EDITOR_CHANGED: 'editor.changed',
  WORKSPACE_ACTIVE_FILE_CHANGED: 'workspace.active-file-changed',
  METADATA_RESOLVED: 'metadata.resolved',
  PLUGIN_STATE_CHANGED: 'plugin.state-changed'
} as const;

export const PluginRpcMethod = {
  PING: 'plugin.ping',
  VAULT_LIST: 'vault.listMarkdown',
  VAULT_GET_BY_PATH: 'vault.getByPath',
  VAULT_GET_BY_ID: 'vault.getById',
  VAULT_READ: 'vault.readText',
  VAULT_CREATE: 'vault.createText',
  VAULT_WRITE: 'vault.writeText',
  VAULT_RENAME: 'vault.renameText',
  VAULT_DELETE: 'vault.deleteText',
  METADATA_GET: 'metadata.get',
  WORKSPACE_ACTIVE_FILE: 'workspace.activeFile',
  WORKSPACE_OPEN_FILE: 'workspace.openFile',
  WORKSPACE_SNAPSHOT: 'workspace.snapshot',
  EDITOR_ACTIVE: 'editor.active',
  EDITOR_REPLACE_SELECTION: 'editor.replaceSelection',
  EDITOR_REPLACE_ALL: 'editor.replaceAll',
  COMMANDS_REGISTER: 'commands.register',
  COMMANDS_UNREGISTER: 'commands.unregister',
  EVENTS_ON: 'events.on',
  EVENTS_OFF: 'events.off',
  UI_NOTICE: 'ui.notice',
  UI_CONFIRM: 'ui.confirm',
  AI_STATUS: 'ai.status',
  AI_CHAT: 'ai.chat',
  AI_CONFIGURE: 'ai.configure',
  AI_MODELS: 'ai.models',
  AI_BALANCE: 'ai.balance',
  VIEWS_REGISTER: 'views.register',
  VIEWS_UNREGISTER: 'views.unregister',
  VIEWS_OPEN: 'views.open',
  STORAGE_GET: 'storage.get',
  STORAGE_SET: 'storage.set',
  STORAGE_REMOVE: 'storage.remove'
} as const;

export const ALL_PLUGIN_RPC_METHODS: readonly string[] = Object.values(PluginRpcMethod);

export const PluginLimits = {
  MAX_RPC_BYTES: 512 * 1024,
  MAX_RESULT_BYTES: 2 * 1024 * 1024,
  MAX_RPC_IN_FLIGHT: 16,
  RPC_TIMEOUT_MS: 15000,
  AI_TIMEOUT_MS: 120000,
  MAX_AI_MESSAGES: 128,
  MAX_AI_TOOLS: 32,
  MAX_VIEWS_PER_PLUGIN: 8,
  MAX_COMMANDS_PER_PLUGIN: 64,
  MAX_SUBSCRIPTIONS_PER_PLUGIN: 128,
  MAX_STORAGE_BYTES: 128 * 1024,
  MAX_STORAGE_KEYS: 128,
  MAX_ZIP_ENTRIES: 4096,
  MAX_ZIP_BYTES: 32 * 1024 * 1024,
  MAX_PATH_LENGTH: 512,
  MAX_RELATIVE_DEPTH: 8,
  MAX_LIST_RESULT: 5000
} as const;

export const PluginErrorCode = {
  INVALID_ARGUMENT: 'E_INVALID_ARGUMENT',
  INVALID_PATH: 'E_INVALID_PATH',
  PATH_EXISTS: 'E_PATH_EXISTS',
  NOT_FOUND: 'E_NOT_FOUND',
  VAULT_FORBIDDEN: 'E_VAULT_FORBIDDEN',
  PERMISSION_DENIED: 'E_PERMISSION_DENIED',
  CONFLICT: 'E_CONFLICT',
  EDITOR_CONFLICT: 'E_EDITOR_CONFLICT',
  EDITOR_READONLY: 'E_EDITOR_READONLY',
  UNSUPPORTED_API: 'E_UNSUPPORTED_API',
  UNSUPPORTED_MODULE: 'E_UNSUPPORTED_MODULE',
  PLUGIN_DISABLED: 'E_PLUGIN_DISABLED',
  PLUGIN_FAILED: 'E_PLUGIN_FAILED',
  QUOTA_EXCEEDED: 'E_QUOTA_EXCEEDED',
  TIMEOUT: 'E_TIMEOUT',
  CANCELLED: 'E_CANCELLED',
  RUNTIME_UNAVAILABLE: 'E_RUNTIME_UNAVAILABLE',
  RATE_LIMITED: 'E_RATE_LIMITED',
  INSTALL_REJECTED: 'E_INSTALL_REJECTED',
  DESKTOP_ONLY: 'E_DESKTOP_ONLY',
  DUPLICATE_PLUGIN: 'E_DUPLICATE_PLUGIN',
  PROTOCOL: 'E_PROTOCOL',
  IO: 'E_IO',
  MISSING_CREDENTIAL: 'E_MISSING_CREDENTIAL',
  INVALID_CREDENTIAL: 'E_INVALID_CREDENTIAL',
  MODEL_UNAVAILABLE: 'E_MODEL_UNAVAILABLE',
  UNKNOWN: 'E_UNKNOWN'
} as const;

export type PluginErrorCodeValue =
  (typeof PluginErrorCode)[keyof typeof PluginErrorCode];

export class PluginTaggedError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message.startsWith(`${code}: `) ? message : `${code}: ${message}`);
    this.name = 'PluginTaggedError';
    this.code = code;
  }
}

export function raisePluginError(code: string, message: string): never {
  throw new PluginTaggedError(code, message);
}

export function codeOfPluginError(error: unknown): string {
  if (error && typeof error === 'object' && typeof (error as { code?: unknown }).code === 'string') {
    const c = (error as { code: string }).code;
    if (/^E_[A-Z_]+$/.test(c)) { return c; }
  }
  const raw = rawPluginErrorText(error);
  const match = /^(E_[A-Z_]+):\s*(.*)$/.exec(raw);
  return match ? match[1] : PluginErrorCode.UNKNOWN;
}

export function messageOfPluginError(error: unknown): string {
  const raw = rawPluginErrorText(error);
  const match = /^E_[A-Z_]+:\s*(.*)$/.exec(raw);
  return match ? match[1] : raw;
}

export function rawPluginErrorText(error: unknown): string {
  if (error instanceof Error) { return error.message || error.name; }
  if (typeof error === 'string') { return error; }
  if (error && typeof error === 'object' && typeof (error as { message?: unknown }).message === 'string') {
    return (error as { message: string }).message;
  }
  return String(error ?? '');
}

export function isKnownCapability(capability: string): capability is PluginCapabilityValue {
  return (ALL_PLUGIN_CAPABILITIES as readonly string[]).includes(capability);
}

export function isKnownRpcMethod(method: string): boolean {
  return ALL_PLUGIN_RPC_METHODS.includes(method);
}

export function capabilityOfRpcMethod(method: string): string {
  if (
    method === PluginRpcMethod.VAULT_LIST ||
    method === PluginRpcMethod.VAULT_GET_BY_PATH ||
    method === PluginRpcMethod.VAULT_GET_BY_ID ||
    method === PluginRpcMethod.VAULT_READ
  ) {
    return PluginCapability.VAULT_READ;
  }
  if (
    method === PluginRpcMethod.VAULT_CREATE ||
    method === PluginRpcMethod.VAULT_WRITE ||
    method === PluginRpcMethod.VAULT_RENAME ||
    method === PluginRpcMethod.VAULT_DELETE
  ) {
    return PluginCapability.VAULT_WRITE;
  }
  if (method === PluginRpcMethod.METADATA_GET) {
    return PluginCapability.METADATA_READ;
  }
  if (method === PluginRpcMethod.EDITOR_ACTIVE) {
    return PluginCapability.EDITOR_READ;
  }
  if (
    method === PluginRpcMethod.EDITOR_REPLACE_SELECTION ||
    method === PluginRpcMethod.EDITOR_REPLACE_ALL
  ) {
    return PluginCapability.EDITOR_WRITE;
  }
  if (method.startsWith('workspace.')) {
    return PluginCapability.WORKSPACE_VIEWS;
  }
  if (method === PluginRpcMethod.UI_NOTICE) {
    return PluginCapability.UI_NOTICE;
  }
  if (method === PluginRpcMethod.UI_CONFIRM) {
    return PluginCapability.UI_MODAL;
  }
  if (method === PluginRpcMethod.COMMANDS_REGISTER) {
    return PluginCapability.UI_COMMANDS;
  }
  if (method.startsWith('ai.')) {
    return PluginCapability.AI_INFERENCE;
  }
  if (method === PluginRpcMethod.VIEWS_REGISTER || method === PluginRpcMethod.VIEWS_OPEN) {
    return PluginCapability.UI_VIEWS;
  }
  if (method === PluginRpcMethod.STORAGE_GET || method === PluginRpcMethod.STORAGE_SET || method === PluginRpcMethod.STORAGE_REMOVE) {
    return PluginCapability.PLUGIN_STORAGE;
  }
  return '';
}

export interface PluginManifest {
  format: string;
  formatVersion: number;
  id: string;
  name: string;
  version: string;
  apiVersion: string;
  main: string;
  description: string;
  author: string;
  capabilities: string[];
  targets: string[];
  minHostVersion: string;
  minAppVersion: string;
  isDesktopOnly: boolean;
}

export interface PluginRecord {
  id: string;
  name: string;
  kind: PluginKindValue;
  version: string;
  apiVersion: string;
  runtimeVersion: string;
  main: string;
  description: string;
  author: string;
  requestedCapabilities: string[];
  grantedCapabilities: string[];
  vaultScopes: string[];
  installedAt: number;
  updatedAt: number;
  sha256: string;
  source: string;
  isDesktopOnly: boolean;
  directory: string;
}

export interface PluginCatalogSnapshot {
  records: PluginRecord[];
  enabledByVault: Record<string, string[]>;
  pluginsDir: string;
}

export interface PluginInstallResult {
  ok: boolean;
  cancelled?: boolean;
  pluginId: string;
  record: PluginRecord | null;
  error: string;
  warnings: string[];
}

export interface PluginBootAssets {
  manifestJson: string;
  sourceCode: string;
  stylesCss: string;
  sourceName: string;
  dataJson: string;
  settingsJson: string;
  platform: string;
}

export interface PluginFileRef {
  id: string;
  vaultId: string;
  projectId: string;
  path: string;
  name: string;
  extension: string;
  kind: 'file' | 'folder';
  size: number;
  ctime: number;
  mtime: number;
}

export interface PluginEditorDraft {
  editorId: string;
  noteId: string;
  vaultId: string;
  windowId: string;
  revision: number;
  baseContent: string;
  content: string;
  dirty: boolean;
  readOnly: boolean;
  focused: boolean;
  selection: { from: number; to: number };
  cursor: { line: number; ch: number };
}

export interface PluginWorkspaceSnapshot {
  windowId: string;
  vaultId: string;
  activeFileId: string;
  activeEditorId: string;
  openFileIds: string[];
  revision: number;
}

export interface PluginHeadingCache {
  heading: string;
  level: number;
  line: number;
  offset: number;
}

export interface PluginLinkCache {
  link: string;
  original: string;
  displayText: string;
  line: number;
}

export interface PluginMetadataSnapshot {
  fileId: string;
  path: string;
  version: number;
  mtime: number;
  hash: string;
  headings: PluginHeadingCache[];
  links: PluginLinkCache[];
  embeds: string[];
  tags: string[];
  frontmatter: string;
  properties: Record<string, string>;
  supportedFields: string[];
  unsupportedFields: string[];
  rawContent: string;
}

export interface PluginCommandEntry {
  pluginId: string;
  localId: string;
  qualifiedId: string;
  title: string;
  available: boolean;
}

export interface PluginViewDeclaration {
  pluginId: string;
  id: string;
  title: string;
  createdAt: number;
}

export interface PluginNoticeItem {
  id: string;
  pluginId: string;
  message: string;
  at: number;
  timeoutMs: number;
}

export interface PluginConfirmRequest {
  id: string;
  pluginId: string;
  title: string;
  body: string;
  resolve: (accepted: boolean) => void;
}

export interface PluginRibbonAction {
  pluginId: string;
  id: string;
  icon: string;
  title: string;
}

export interface PluginStatusBarItem {
  pluginId: string;
  id: string;
  text: string;
}

export interface PluginRuntimeInfo {
  state: PluginLifecycleStateValue;
  lastError: string;
  warnings: string[];
  diagnostics: string[];
  hasViews: boolean;
  presentRequested: boolean;
}

export interface PluginAiStatus {
  configured: boolean;
  profileId: string;
  name: string;
  provider: string;
  baseUrl: string;
  model: string;
  maxTokens: number;
  temperature: number;
  balanceProvider: string;
  needsApiKey: boolean;
}

export interface PluginAiQuotaWindow {
  label: string;
  unit: string;
  remainingValue?: number;
  maxValue?: number;
  usedPercent?: number;
  resetAt?: number;
}

export interface PluginAiBalance {
  supported: boolean;
  provider: string;
  updatedAt: number;
  windows: PluginAiQuotaWindow[];
}
