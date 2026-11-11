/**
 * Type declarations for the LexiNote plugin SDK (developer tooling only).
 *
 * The runtime itself is plain CommonJS JavaScript; these types exist so plugin authors
 * get completion and documentation in editors. They are not imported by the ArkTS host
 * and stay free of Node.js types. Only `views.render` references the standard DOM
 * `HTMLElement`, because a native view is rendered inside the plugin WebView.
 */

export interface Disposable {
  readonly disposed?: boolean;
  dispose(): void;
}

export interface FileRef {
  id: string;
  vaultId: string;
  projectId: string;
  /** Vault-relative POSIX path, never an absolute sandbox path. */
  path: string;
  name: string;
  extension: string;
  kind: 'file' | string;
  size: number;
  ctime: number;
  mtime: number;
}

export type FileInput = FileRef | string;

export interface HeadingCache {
  heading: string;
  level: number;
  line: number;
  offset: number;
}

export interface LinkCache {
  link: string;
  original: string;
  displayText: string;
  line: number;
}

export interface MetadataSnapshot {
  fileId: string;
  path: string;
  version: number;
  mtime: number;
  hash: string;
  headings: HeadingCache[];
  links: LinkCache[];
  embeds: string[];
  tags: string[];
  frontmatter: string;
  properties: Record<string, string>;
  supportedFields: string[];
  unsupportedFields: string[];
}

export interface EditorSnapshot {
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
}

export interface WorkspaceSnapshot {
  windowId: string;
  vaultId: string;
  activeFileId: string;
  activeEditorId: string;
  openFileIds: string[];
  revision: number;
}

export interface EditorWriteResult {
  content: string;
  version: number;
}

export type Capability =
  | 'vault.read'
  | 'vault.write'
  | 'notes.metadata.read'
  | 'editor.read'
  | 'editor.write'
  | 'workspace.views'
  | 'ui.notice'
  | 'ui.modal'
  | 'ui.commands'
  | 'ai.inference'
  | 'ui.views'
  | 'plugin.storage'
  | 'network';

export type CoreEventName =
  | 'vault.created'
  | 'vault.modified'
  | 'vault.renamed'
  | 'vault.deleted'
  | 'editor.changed'
  | 'workspace.active-file-changed'
  | 'metadata.resolved'
  | 'plugin.state-changed';

export interface CoreEventPayload {
  type?: string;
  vaultId?: string;
  seq?: number;
  fileId?: string;
  path?: string;
  oldPath?: string;
  projectId?: string;
  editorId?: string;
  revision?: number;
  at?: number;
  [key: string]: unknown;
}

export interface CapabilitySet {
  has(capability: Capability | string): boolean;
  list(): string[];
}

export interface SubscriptionBag {
  add(disposable: Disposable | (() => void)): Disposable;
  readonly size: number;
  list(): Disposable[];
}

export interface CommandDefinition {
  id: string;
  title: string;
  run(): void | Promise<void>;
}

export interface SdkCommand {
  /** Resolves true when the host accepted the registration, false otherwise. */
  ready?: Promise<boolean>;
  dispose(): void;
}

export interface SdkEventSubscription extends Disposable {
  ready?: Promise<boolean>;
}

export interface NoticeOptions {
  title?: string;
  body?: string;
  message?: string;
}

export interface PluginContext {
  readonly pluginId: string;
  /** SDK API version, currently `'1.0'`. */
  readonly apiVersion: '1.1';
  /** Host runtime version, currently `'1'`. */
  readonly runtimeVersion: string;
  readonly vaultId: string;
  readonly capabilities: CapabilitySet;
  readonly subscriptions: SubscriptionBag;
  readonly vault: {
    listMarkdown(): Promise<FileRef[]>;
    get(path: string): Promise<FileRef | null>;
    read(input: FileInput): Promise<string>;
    create(path: string, content: string): Promise<FileRef>;
    write(input: FileInput, content: string): Promise<FileRef>;
    rename(input: FileInput, newPath: string): Promise<FileRef>;
    delete(input: FileInput): Promise<null>;
  };
  readonly metadata: {
    get(input: FileInput): Promise<MetadataSnapshot>;
  };
  readonly workspace: {
    activeFile(): Promise<FileRef | null>;
    openFile(input: FileInput): Promise<null>;
    snapshot(): Promise<WorkspaceSnapshot>;
  };
  readonly editor: {
    active(): Promise<EditorSnapshot | null>;
    /** Synchronous convenience over the runtime mirror. */
    getValue(): string;
    replaceSelection(text: string): Promise<EditorWriteResult>;
    replaceAll(text: string, expectedVersion?: number): Promise<EditorWriteResult>;
  };
  readonly commands: {
    register(command: CommandDefinition): SdkCommand;
  };
  readonly events: {
    on(type: CoreEventName | string, handler: (payload: CoreEventPayload) => void | Promise<void>): SdkEventSubscription;
  };
  readonly ui: {
    notice(message: string, timeoutMs?: number): Promise<null>;
    confirm(options: string | NoticeOptions): Promise<boolean>;
  };
  readonly storage: {
    get<T = unknown>(key: string): Promise<T | null>;
    set(key: string, value: unknown): Promise<null>;
    remove(key: string): Promise<null>;
  };
  /** Host-brokered model inference; the plugin itself has no network access. */
  readonly ai: {
    status(): Promise<AiStatus>;
    /** Model IDs from the bound service; unavailable services may reject. */
    models(): Promise<string[]>;
    /** Supported official account balances / coding-plan windows (cached for 60 s). */
    balance(): Promise<AiBalance>;
    /** Binds/updates the model service. An empty `apiKey` keeps the stored one. */
    configure(patch: AiConfigPatch): Promise<AiStatus>;
    chat(request: AiChatRequest): Promise<AiReply>;
  };
  /** Plugins may declare a DOM surface shown by the workspace sidebar. */
  readonly views: {
    register(definition: PluginViewDefinition): SdkView;
    unregister(id: string): null;
    open(id?: string): Promise<null>;
    list(): string[];
  };
  log(level: 'debug' | 'info' | 'warn' | 'error' | string, message: string): void;
}

export interface AiToolCall {
  id: string;
  name: string;
  arguments: string;
}

export interface AiMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  toolCalls?: AiToolCall[];
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
}

export interface AiToolDefinition {
  name: string;
  description?: string;
  parameters?: Record<string, unknown>;
}

export interface AiChatRequest {
  messages: AiMessage[];
  tools?: AiToolDefinition[];
  maxTokens?: number;
  temperature?: number;
}

export interface AiReply {
  text: string;
  reasoning: string;
  toolCalls: AiToolCall[];
  finishReason: 'stop' | 'tool_calls' | 'max-tokens' | string;
  model: string;
  usage: { inputTokens: number; outputTokens: number };
}

export interface AiStatus {
  configured: boolean;
  provider: string;
  model: string;
  baseUrl: string;
  maxTokens: number;
  temperature: number;
  balanceProvider: string;
}

export interface AiBalance {
  supported: boolean;
  provider: string;
  updatedAt: number;
  windows: {
    label: string;
    unit: string;
    remainingValue?: number;
    maxValue?: number;
    usedPercent?: number;
    resetAt?: number;
  }[];
}

export interface AiConfigPatch {
  provider?: 'openai-compatible' | 'anthropic-compatible' | string;
  baseUrl?: string;
  model?: string;
  apiKey?: string;
  maxTokens?: number;
  temperature?: number;
  clear?: boolean;
}

export interface PluginViewDefinition {
  id: string;
  title: string;
  render(container: HTMLElement, context: PluginContext): void | Promise<void>;
}

export interface SdkView extends Disposable {
  /** Resolves true when the host accepted the view declaration. */
  ready?: Promise<boolean>;
}

export interface LexiNotePluginDefinition {
  activate(context: PluginContext): void | Promise<void>;
  deactivate?(): void | Promise<void>;
}

export interface LexiNotePlugin {
  readonly __lexinote: true;
  activate(context: PluginContext): void | Promise<void>;
  deactivate(): void | Promise<void>;
}

/** Marks a bundle as a LexiNote plugin. */
export function definePlugin(definition: LexiNotePluginDefinition): LexiNotePlugin;

/** Creates a disposable that runs `fn` at most once. */
export function DISPOSABLE(fn: () => void): Disposable;

export const apiVersion: '1.1';
export const runtimeVersion: '1';
