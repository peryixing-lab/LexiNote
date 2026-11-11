/**
 * Platform-neutral plugin contracts shared by the ArkTS host design docs and the
 * JavaScript runtime tooling.
 *
 * IMPORTANT: ArkTS never imports this file. The executable contract lives in
 * `entry/src/main/ets/plugin/model/PluginContracts.ets`; this file mirrors it for
 * developer tooling, JSON examples and the regression scripts. Keep the two in sync.
 */

/** Capability names the host can grant. They are not HarmonyOS permissions. */
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

export type PluginKind = 'lexinote' | 'obsidian';

/** Vault-relative file reference; never carries an absolute sandbox path. */
export interface FileRef {
  id: string;
  vaultId: string;
  projectId: string;
  path: string;
  name: string;
  extension: string;
  kind: string;
  size: number;
  ctime: number;
  mtime: number;
}

export interface PluginIdentity {
  pluginId: string;
  kind: PluginKind;
  version: string;
  apiVersion: string;
  runtimeVersion: string;
}

export interface CoreEvent {
  type: string;
  vaultId: string;
  seq: number;
  fileId: string;
  path: string;
  oldPath: string;
  projectId: string;
  editorId: string;
  revision: number;
  at: number;
}

export interface RpcRequest {
  protocol: 1;
  id: string;
  pluginId: string;
  token: string;
  method: string;
  /**
   * JSON text on the wire: the ArkTS host stores `params` as a string and each
   * dispatcher parses it itself (`PluginRpcRequest.params: string`). SDK callers pass
   * plain objects and `packages/plugin-runtime-js/src/bridge.js` serialises them.
   */
  params: string;
}

export interface RpcError {
  code: string;
  message: string;
  details?: string;
}

/** `result` always carries JSON text on the wire, never a raw object. */
export interface RpcResponse {
  protocol: 1;
  id: string;
  ok: boolean;
  result: string;
  error: RpcError;
}

export interface RpcEvent {
  protocol: 1;
  type: 'event';
  pluginId: string;
  event: string;
  seq: number;
  /** JSON text of the event payload. */
  payload: string;
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

/** `manifest.json` of a native LexiNote plugin. */
export interface LexiNoteManifest {
  format: 'lexinote-plugin';
  formatVersion: number;
  id: string;
  name: string;
  version: string;
  apiVersion: string;
  main: string;
  description?: string;
  author?: string;
  capabilities?: Capability[];
  targets?: string[];
  minHostVersion?: string;
  isDesktopOnly?: boolean;
}

/** `manifest.json` of an Obsidian plugin installed through the compatibility path. */
export interface ObsidianManifest {
  id: string;
  name: string;
  version: string;
  minAppVersion: string;
  description: string;
  author: string;
  isDesktopOnly: boolean;
  fundingUrl?: string;
}

export type PluginManifest = LexiNoteManifest | ObsidianManifest;

/** Names of the RPC methods the host implements (the only callable surface). */
export type RpcMethod =
  | 'plugin.ping'
  | 'vault.listMarkdown'
  | 'vault.getByPath'
  | 'vault.getById'
  | 'vault.readText'
  | 'vault.createText'
  | 'vault.writeText'
  | 'vault.renameText'
  | 'vault.deleteText'
  | 'metadata.get'
  | 'workspace.activeFile'
  | 'workspace.openFile'
  | 'workspace.snapshot'
  | 'editor.active'
  | 'editor.replaceSelection'
  | 'editor.replaceAll'
  | 'commands.register'
  | 'commands.unregister'
  | 'events.on'
  | 'events.off'
  | 'ui.notice'
  | 'ui.confirm'
  | 'ai.status'
  | 'ai.chat'
  | 'ai.configure'
  | 'ai.models'
  | 'ai.balance'
  | 'views.register'
  | 'views.unregister'
  | 'views.open'
  | 'storage.get'
  | 'storage.set'
  | 'storage.remove';

export const SUPPORTED_CAPABILITIES: readonly Capability[] = [
  'vault.read',
  'vault.write',
  'notes.metadata.read',
  'editor.read',
  'editor.write',
  'workspace.views',
  'ui.notice',
  'ui.modal',
  'ui.commands',
  'ai.inference',
  'ui.views',
  'plugin.storage',
  'network'
] as const;

export const SUPPORTED_RPC_METHODS: readonly RpcMethod[] = [
  'plugin.ping',
  'vault.listMarkdown',
  'vault.getByPath',
  'vault.getById',
  'vault.readText',
  'vault.createText',
  'vault.writeText',
  'vault.renameText',
  'vault.deleteText',
  'metadata.get',
  'workspace.activeFile',
  'workspace.openFile',
  'workspace.snapshot',
  'editor.active',
  'editor.replaceSelection',
  'editor.replaceAll',
  'commands.register',
  'commands.unregister',
  'events.on',
  'events.off',
  'ui.notice',
  'ui.confirm',
  'ai.status',
  'ai.chat',
  'ai.configure',
  'ai.models',
  'ai.balance',
  'views.register',
  'views.unregister',
  'views.open',
  'storage.get',
  'storage.set',
  'storage.remove'
] as const;
