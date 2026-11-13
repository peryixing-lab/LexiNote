import { contextBridge, ipcRenderer } from 'electron';
import type { ImportedFile, MarkdownExportFile, PersistedState, RuntimeInfo } from '../shared/types';
import {
  PluginTaggedError,
  type PluginAiBalance,
  type PluginAiStatus,
  type PluginBootAssets,
  type PluginCatalogSnapshot,
  type PluginInstallResult
} from '../shared/pluginTypes';

type PluginOpResult<T> =
  | { ok: true; data: T }
  | { ok: false; code: string; message: string };

async function unwrapPluginOp<T>(promise: Promise<PluginOpResult<T>>): Promise<T> {
  const res = await promise;
  if (res && res.ok) { return res.data; }
  throw new PluginTaggedError(res?.code || 'E_UNKNOWN', res?.message || '未知插件错误');
}

export interface StateEnvelope {
  state: PersistedState | null;
  revision: number;
}

export interface StateSyncPayload {
  state: PersistedState;
  revision: number;
}

const api = {
  runtimeInfo: (): Promise<RuntimeInfo> => ipcRenderer.invoke('runtime:info'),
  loadState: (): Promise<StateEnvelope> => ipcRenderer.invoke('state:load'),
  saveState: (state: PersistedState, baseRevision: number): Promise<{ revision: number }> =>
    ipcRenderer.invoke('state:save', { state, baseRevision }),
  replaceState: (state: PersistedState): Promise<{ revision: number }> =>
    ipcRenderer.invoke('state:replace', state),
  onStateSync: (listener: (payload: StateSyncPayload) => void): (() => void) => {
    const handler = (_event: unknown, payload: StateSyncPayload): void => listener(payload);
    ipcRenderer.on('state:sync', handler);
    return () => ipcRenderer.removeListener('state:sync', handler);
  },

  window: {
    minimize: (): Promise<void> => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: (): Promise<boolean> => ipcRenderer.invoke('window:toggle-maximize'),
    close: (): Promise<void> => ipcRenderer.invoke('window:close'),
    isMaximized: (): Promise<boolean> => ipcRenderer.invoke('window:is-maximized'),
    count: (): Promise<number> => ipcRenderer.invoke('window:count'),
    vaults: (): Promise<string[]> => ipcRenderer.invoke('window:vaults'),
    probe: (): Promise<{ vault: string; notes: number; tabs: number }[]> =>
      ipcRenderer.invoke('window:probe'),
    onMaximized: (listener: (maximized: boolean) => void): (() => void) => {
      const handler = (_event: unknown, maximized: boolean): void => listener(maximized);
      ipcRenderer.on('window:maximized', handler);
      return () => ipcRenderer.removeListener('window:maximized', handler);
    },
    onFlushRequest: (listener: () => void): (() => void) => {
      const handler = (): void => listener();
      ipcRenderer.on('state:flush-request', handler);
      return () => ipcRenderer.removeListener('state:flush-request', handler);
    },
    flushDone: (): void => ipcRenderer.send('state:flush-done')
  },

  openWorkspaceWindow: (vaultId: string): Promise<boolean> =>
    ipcRenderer.invoke('workspace:open-window', vaultId),
  chooseFolder: (): Promise<string | null> => ipcRenderer.invoke('dialog:choose-folder'),
  resolveWorkspaceFolder: (vault: PersistedState['vaults'][number]): Promise<string> =>
    ipcRenderer.invoke('workspace:resolve-folder', vault),
  exportWorkspaceZip: (vault: PersistedState['vaults'][number]): Promise<{ path: string; count: number } | null> =>
    ipcRenderer.invoke('workspace:export-zip', vault),
  importWorkspaceZip: (): Promise<unknown> => ipcRenderer.invoke('workspace:import-zip'),
  scanWorkspaceFolder: (folderPath: string, vaultId: string): Promise<unknown> =>
    ipcRenderer.invoke('workspace:scan-folder', { folderPath, vaultId }),
  exportSettingsPlugins: (settings: Record<string, unknown>): Promise<string | null> =>
    ipcRenderer.invoke('settings:export-json', settings),
  importSettingsPlugins: (): Promise<Record<string, unknown> | null> =>
    ipcRenderer.invoke('settings:import-json'),
  exportMarkdown: (files: MarkdownExportFile[], folder: string): Promise<number> =>
    ipcRenderer.invoke('export:markdown', { files, folder }),
  exportBackup: (content: string, suggestedName: string): Promise<string | null> =>
    ipcRenderer.invoke('export:backup', { content, suggestedName }),
  exportText: (
    content: string,
    suggestedName: string,
    filters: { name: string; extensions: string[] }[]
  ): Promise<string | null> => ipcRenderer.invoke('export:text', { content, suggestedName, filters }),
  importFiles: (): Promise<ImportedFile[]> => ipcRenderer.invoke('import:files', []),
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('shell:open-external', url),
  showItemInFolder: (target: string): Promise<void> => ipcRenderer.invoke('shell:show-item', target),
  writeClipboard: (text: string): Promise<void> => ipcRenderer.invoke('clipboard:write-text', text),

  plugins: {
    list: (): Promise<PluginCatalogSnapshot> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:list')),
    pickInstallZip: (): Promise<PluginInstallResult> =>
      ipcRenderer.invoke('plugin:pick-install-zip'),
    pickInstallFolder: (): Promise<PluginInstallResult> =>
      ipcRenderer.invoke('plugin:pick-install-folder'),
    installZipPath: (zipPath: string): Promise<PluginInstallResult> =>
      ipcRenderer.invoke('plugin:install-zip-path', zipPath),
    installFolderPath: (dirPath: string): Promise<PluginInstallResult> =>
      ipcRenderer.invoke('plugin:install-folder-path', dirPath),
    uninstall: (pluginId: string, keepData = false): Promise<PluginCatalogSnapshot> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:uninstall', { pluginId, keepData })),
    readBootAssets: (pluginId: string, vaultId: string): Promise<PluginBootAssets> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:boot-assets', { pluginId, vaultId })),
    setEnabled: (vaultId: string, pluginId: string, enabled: boolean): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:set-enabled', { vaultId, pluginId, enabled })),
    grantCapability: (pluginId: string, capability: string): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:grant-capability', { pluginId, capability })),
    revokeCapability: (pluginId: string, capability: string): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:revoke-capability', { pluginId, capability })),
    grantAllCapabilities: (pluginId: string): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:grant-all-capabilities', pluginId)),
    revokeAllCapabilities: (pluginId: string): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:revoke-all-capabilities', pluginId)),
    storageGet: (pluginId: string, vaultId: string, key: string): Promise<string> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:storage-get', { pluginId, vaultId, key })),
    storageSet: (pluginId: string, vaultId: string, key: string, value: string): Promise<void> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:storage-set', { pluginId, vaultId, key, value })),
    storageRemove: (pluginId: string, vaultId: string, key: string): Promise<void> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:storage-remove', { pluginId, vaultId, key })),
    aiStatus: (pluginId: string): Promise<PluginAiStatus> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:ai-status', pluginId)),
    aiConfigure: (pluginId: string, params: Record<string, unknown>): Promise<PluginAiStatus> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:ai-configure', { pluginId, params })),
    aiChat: (pluginId: string, params: Record<string, unknown>): Promise<Record<string, unknown>> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:ai-chat', { pluginId, params })),
    aiModels: (pluginId: string): Promise<string[]> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:ai-models', pluginId)),
    aiBalance: (pluginId: string): Promise<PluginAiBalance> =>
      unwrapPluginOp(ipcRenderer.invoke('plugin:ai-balance', pluginId)),
    openFolder: (): Promise<void> =>
      ipcRenderer.invoke('plugin:open-folder'),
    onCatalogChanged: (listener: (snapshot: PluginCatalogSnapshot) => void): (() => void) => {
      const wrapped = (_event: Electron.IpcRendererEvent, snapshot: PluginCatalogSnapshot): void => listener(snapshot);
      ipcRenderer.on('plugin:catalog-changed', wrapped);
      return () => ipcRenderer.removeListener('plugin:catalog-changed', wrapped);
    }
  }
};

contextBridge.exposeInMainWorld('lexi', api);

export type LexiApi = typeof api;
