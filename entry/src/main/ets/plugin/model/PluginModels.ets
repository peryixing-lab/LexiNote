/**
 * Neutral, serializable plugin data model.
 *
 * Everything here crosses the ArkTS <-> JavaScript boundary, so the rules are:
 *  - no ArkTS instances, functions, file handles or absolute paths;
 *  - every field is a JSON-safe primitive, list or nested model;
 *  - field names never change inside SDK 1.x.
 */
export class PluginKind {
  static readonly LEXINOTE: string = 'lexinote';
  static readonly OBSIDIAN: string = 'obsidian';
}

/** Host state machine. Mirrors docs/plugin-system/01-architecture.md. */
export class PluginState {
  static readonly NOT_INSTALLED: string = 'not-installed';
  static readonly VALIDATING: string = 'validating';
  static readonly INSTALLED_DISABLED: string = 'installed-disabled';
  static readonly STARTING: string = 'starting';
  static readonly ACTIVE: string = 'active';
  static readonly STOPPING: string = 'stopping';
  static readonly UNINSTALLING: string = 'uninstalling';
  static readonly FAILED: string = 'failed';
}

/** Host-owned capability names. They are NOT HarmonyOS or Obsidian permissions. */
export class PluginCapability {
  static readonly VAULT_READ: string = 'vault.read';
  static readonly VAULT_WRITE: string = 'vault.write';
  static readonly METADATA_READ: string = 'notes.metadata.read';
  static readonly EDITOR_READ: string = 'editor.read';
  static readonly EDITOR_WRITE: string = 'editor.write';
  static readonly WORKSPACE_VIEWS: string = 'workspace.views';
  static readonly UI_NOTICE: string = 'ui.notice';
  static readonly UI_MODAL: string = 'ui.modal';
  static readonly UI_COMMANDS: string = 'ui.commands';
  /** Host-brokered model inference. The plugin still never gets network access. */
  static readonly AI_INFERENCE: string = 'ai.inference';
  /** Registers a native plugin view rendered by the host's plugin WebView surface. */
  static readonly UI_VIEWS: string = 'ui.views';
  static readonly PLUGIN_STORAGE: string = 'plugin.storage';
  static readonly NETWORK: string = 'network';

  static readonly ALL: string[] = [
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

  static known(capability: string): boolean {
    return PluginCapability.ALL.includes(capability);
  }
}

/** Names used by CoreEvent and by the JS-facing event subscriptions. */
export class PluginEventType {
  static readonly VAULT_CREATED: string = 'vault.created';
  static readonly VAULT_MODIFIED: string = 'vault.modified';
  static readonly VAULT_RENAMED: string = 'vault.renamed';
  static readonly VAULT_DELETED: string = 'vault.deleted';
  static readonly EDITOR_CHANGED: string = 'editor.changed';
  static readonly WORKSPACE_ACTIVE_FILE_CHANGED: string = 'workspace.active-file-changed';
  static readonly METADATA_RESOLVED: string = 'metadata.resolved';
  static readonly PLUGIN_STATE_CHANGED: string = 'plugin.state-changed';

  static readonly ALL: string[] = [
    PluginEventType.VAULT_CREATED,
    PluginEventType.VAULT_MODIFIED,
    PluginEventType.VAULT_RENAMED,
    PluginEventType.VAULT_DELETED,
    PluginEventType.EDITOR_CHANGED,
    PluginEventType.WORKSPACE_ACTIVE_FILE_CHANGED,
    PluginEventType.METADATA_RESOLVED,
    PluginEventType.PLUGIN_STATE_CHANGED
  ];
}

/**
 * Knowledge-base relative file reference.
 * `id` is the stable LexiNote note id; `path` is a vault-relative POSIX path and
 * never the on-disk path held by NoteItem.path.
 */
export class PluginFileRef {
  id: string = '';
  vaultId: string = '';
  projectId: string = '';
  path: string = '';
  name: string = '未命名.md';
  extension: string = 'md';
  kind: string = 'file';
  size: number = 0;
  ctime: number = 0;
  mtime: number = 0;

  static of(id: string, vaultId: string, path: string, projectId: string, ctime: number, mtime: number,
    size: number): PluginFileRef {
    const ref = new PluginFileRef();
    ref.id = id;
    ref.vaultId = vaultId;
    ref.projectId = projectId;
    ref.path = path;
    ref.kind = 'file';
    ref.extension = 'md';
    ref.ctime = ctime;
    ref.mtime = mtime;
    ref.size = size;
    const slash = path.lastIndexOf('/');
    ref.name = slash >= 0 ? path.substring(slash + 1) : path;
    return ref;
  }
}

/** Installed plugin record. Persisted verbatim in the host key-value store. */
export class PluginRecord {
  id: string = '';
  name: string = '';
  kind: string = PluginKind.LEXINOTE;
  version: string = '0.0.1';
  apiVersion: string = '1.0';
  runtimeVersion: string = '1';
  main: string = 'main.js';
  description: string = '';
  author: string = '';
  requestedCapabilities: string[] = [];
  grantedCapabilities: string[] = [];
  vaultScopes: string[] = [];
  enabled: boolean = false;
  state: string = PluginState.INSTALLED_DISABLED;
  installedAt: number = 0;
  updatedAt: number = 0;
  sha256: string = '';
  source: string = 'bundled';
  isDesktopOnly: boolean = false;
  lastError: string = '';
  directory: string = '';

  static clone(source: PluginRecord): PluginRecord {
    const copy = new PluginRecord();
    copy.id = source.id;
    copy.name = source.name;
    copy.kind = source.kind;
    copy.version = source.version;
    copy.apiVersion = source.apiVersion;
    copy.runtimeVersion = source.runtimeVersion;
    copy.main = source.main;
    copy.description = source.description;
    copy.author = source.author;
    copy.requestedCapabilities = source.requestedCapabilities.slice(0);
    copy.grantedCapabilities = source.grantedCapabilities.slice(0);
    copy.vaultScopes = source.vaultScopes.slice(0);
    copy.enabled = source.enabled;
    copy.state = source.state;
    copy.installedAt = source.installedAt;
    copy.updatedAt = source.updatedAt;
    copy.sha256 = source.sha256;
    copy.source = source.source;
    copy.isDesktopOnly = source.isDesktopOnly;
    copy.lastError = source.lastError;
    copy.directory = source.directory;
    return copy;
  }
}

/** Manifest as read from `manifest.json` (LexiNote) or Obsidian's plugin manifest. */
export class PluginManifest {
  format: string = 'lexinote-plugin';
  formatVersion: number = 1;
  id: string = '';
  name: string = '';
  version: string = '';
  apiVersion: string = '1.0';
  main: string = 'main.js';
  description: string = '';
  author: string = '';
  capabilities: string[] = [];
  targets: string[] = ['harmonyos'];
  minHostVersion: string = '';
  isDesktopOnly: boolean = false;
  // Obsidian manifests additionally carry `minAppVersion` and `fundingUrl`; both are ignored
  // rather than fabricated.
  minAppVersion: string = '';
}

export class PluginDiagnostic {
  level: string = 'info'; // 'info' | 'warn' | 'error'
  message: string = '';
  at: number = 0;
  detail: string = '';

  constructor(level: string = 'info', message: string = '', detail: string = '') {
    this.level = level;
    this.message = message;
    this.detail = detail;
    this.at = Date.now();
  }
}

/** Install / upgrade result shown to the user. */
export class PluginInstallResult {
  ok: boolean = false;
  pluginId: string = '';
  record: PluginRecord = new PluginRecord();
  error: string = '';
  warnings: string[] = [];
}

/** Editor handle snapshot published to plugins. */
export class PluginEditorDraft {
  editorId: string = '';
  noteId: string = '';
  vaultId: string = '';
  windowId: string = '';
  revision: number = 0;
  baseContent: string = '';
  content: string = '';
  dirty: boolean = false;
  readOnly: boolean = false;
  focused: boolean = false;
}

export class PluginSelectionRange {
  from: number = 0;
  to: number = 0;
}

export class PluginWorkspaceSnapshot {
  windowId: string = '';
  vaultId: string = '';
  activeFileId: string = '';
  activeEditorId: string = '';
  openFileIds: string[] = [];
  revision: number = 0;
}

export class PluginHeadingCache {
  heading: string = '';
  level: number = 1;
  line: number = 0;
  offset: number = 0;
}

export class PluginLinkCache {
  link: string = '';
  original: string = '';
  displayText: string = '';
  line: number = 0;
}

/**
 * Metadata cache entry. Only fields listed in `supportedFields` are real; a plugin
 * must treat everything else as absent instead of guessing.
 */
export class PluginMetadataSnapshot {
  fileId: string = '';
  path: string = '';
  version: number = 0;
  mtime: number = 0;
  hash: string = '';
  headings: PluginHeadingCache[] = [];
  links: PluginLinkCache[] = [];
  embeds: string[] = [];
  tags: string[] = [];
  frontmatter: string = '';
  properties: Map<string, string> = new Map<string, string>();
  supportedFields: string[] = [];
  unsupportedFields: string[] = [];
  rawContent: string = '';
}

/** One delivered core event. `seq` is monotonic per vault, starting at 1. */
export class PluginCoreEvent {
  type: string = '';
  vaultId: string = '';
  seq: number = 0;
  fileId: string = '';
  path: string = '';
  oldPath: string = '';
  projectId: string = '';
  editorId: string = '';
  revision: number = 0;
  at: number = 0;

  static create(type: string, vaultId: string): PluginCoreEvent {
    const event = new PluginCoreEvent();
    event.type = type;
    event.vaultId = vaultId;
    event.at = Date.now();
    return event;
  }
}

/** Limits enforced by the host for every plugin. */
export class PluginLimits {
  static readonly MAX_RPC_BYTES: number = 512 * 1024;
  static readonly MAX_RESULT_BYTES: number = 2 * 1024 * 1024;
  static readonly MAX_RPC_IN_FLIGHT: number = 16;
  static readonly RPC_TIMEOUT_MS: number = 15000;
  /** Model turns routinely take longer than the generic RPC budget. */
  static readonly AI_TIMEOUT_MS: number = 120000;
  static readonly MAX_AI_MESSAGES: number = 128;
  static readonly MAX_AI_TOOLS: number = 32;
  static readonly MAX_VIEWS_PER_PLUGIN: number = 8;
  static readonly MAX_COMMANDS_PER_PLUGIN: number = 64;
  static readonly MAX_SUBSCRIPTIONS_PER_PLUGIN: number = 128;
  static readonly MAX_STORAGE_BYTES: number = 128 * 1024;
  static readonly MAX_STORAGE_KEYS: number = 128;
  // 真实 Obsidian 插件包（构建产物 + 多语言 + 资源）常见上千个条目；512 会把
  // claudian 这类 12 MB 的包直接拒之门外。上限收在"仍能一次性解析"的量级。
  static readonly MAX_ZIP_ENTRIES: number = 4096;
  static readonly MAX_ZIP_BYTES: number = 32 * 1024 * 1024;
  static readonly MAX_PATH_LENGTH: number = 512;
  static readonly MAX_RELATIVE_DEPTH: number = 8;
  static readonly MAX_LIST_RESULT: number = 5000;
}
