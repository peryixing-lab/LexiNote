import type { ImportedFile, PersistedState, RuntimeInfo } from '../shared/types';
import type {
  PluginAiBalance,
  PluginAiStatus,
  PluginBootAssets,
  PluginCatalogSnapshot,
  PluginInstallResult
} from '../shared/pluginTypes';

export interface StateEnvelope {
  state: PersistedState | null;
  revision: number;
}

export interface StateSyncPayload {
  state: PersistedState;
  revision: number;
}

export interface LexiBridge {
  runtimeInfo: () => Promise<RuntimeInfo>;
  loadState: () => Promise<StateEnvelope>;
  saveState: (state: PersistedState, baseRevision: number) => Promise<{ revision: number }>;
  replaceState: (state: PersistedState) => Promise<{ revision: number }>;
  onStateSync: (listener: (payload: StateSyncPayload) => void) => () => void;
  openWorkspaceWindow: (vaultId: string) => Promise<boolean>;
  window: {
    minimize: () => Promise<void>;
    toggleMaximize: () => Promise<boolean>;
    close: () => Promise<void>;
    isMaximized: () => Promise<boolean>;
    count: () => Promise<number>;
    vaults: () => Promise<string[]>;
    probe: () => Promise<{ vault: string; notes: number; tabs: number }[]>;
    onMaximized: (listener: (maximized: boolean) => void) => () => void;
    onFlushRequest: (listener: () => void) => () => void;
    flushDone: () => void;
  };
  chooseFolder: () => Promise<string | null>;
  resolveWorkspaceFolder: (vault: PersistedState['vaults'][number]) => Promise<string>;
  exportWorkspaceZip: (vault: PersistedState['vaults'][number]) => Promise<{ path: string; count: number } | null>;
  importWorkspaceZip: () => Promise<{
    folderPath: string;
    folderName: string;
    vaultId: string;
    fileCount: number;
    notes: PersistedState['notes'];
    maps: PersistedState['maps'];
    canvases: PersistedState['canvases'];
  } | null>;
  scanWorkspaceFolder: (folderPath: string, vaultId: string) => Promise<{
    notes: PersistedState['notes'];
    maps: PersistedState['maps'];
    canvases: PersistedState['canvases'];
  }>;
  exportSettingsPlugins: (settings: Record<string, unknown>) => Promise<string | null>;
  importSettingsPlugins: () => Promise<Record<string, unknown> | null>;
  exportMarkdown: (files: { name: string; content: string }[], folder: string) => Promise<number>;
  exportBackup: (content: string, suggestedName: string) => Promise<string | null>;
  exportText: (
    content: string,
    suggestedName: string,
    filters: { name: string; extensions: string[] }[]
  ) => Promise<string | null>;
  importFiles: () => Promise<ImportedFile[]>;
  openExternal: (url: string) => Promise<void>;
  showItemInFolder: (target: string) => Promise<void>;
  writeClipboard: (text: string) => Promise<void>;
  plugins: {
    list: () => Promise<PluginCatalogSnapshot>;
    pickInstallZip: () => Promise<PluginInstallResult>;
    pickInstallFolder: () => Promise<PluginInstallResult>;
    installZipPath: (zipPath: string) => Promise<PluginInstallResult>;
    installFolderPath: (dirPath: string) => Promise<PluginInstallResult>;
    uninstall: (pluginId: string, keepData?: boolean) => Promise<PluginCatalogSnapshot>;
    readBootAssets: (pluginId: string, vaultId: string) => Promise<PluginBootAssets>;
    setEnabled: (vaultId: string, pluginId: string, enabled: boolean) => Promise<string[]>;
    grantCapability: (pluginId: string, capability: string) => Promise<string[]>;
    revokeCapability: (pluginId: string, capability: string) => Promise<string[]>;
    grantAllCapabilities: (pluginId: string) => Promise<string[]>;
    revokeAllCapabilities: (pluginId: string) => Promise<string[]>;
    storageGet: (pluginId: string, vaultId: string, key: string) => Promise<string>;
    storageSet: (pluginId: string, vaultId: string, key: string, value: string) => Promise<void>;
    storageRemove: (pluginId: string, vaultId: string, key: string) => Promise<void>;
    aiStatus: (pluginId: string) => Promise<PluginAiStatus>;
    aiConfigure: (pluginId: string, params: Record<string, unknown>) => Promise<PluginAiStatus>;
    aiChat: (pluginId: string, params: Record<string, unknown>) => Promise<Record<string, unknown>>;
    aiModels: (pluginId: string) => Promise<string[]>;
    aiBalance: (pluginId: string) => Promise<PluginAiBalance>;
    openFolder: () => Promise<void>;
    onCatalogChanged: (listener: (snapshot: PluginCatalogSnapshot) => void) => () => void;
  };
}

declare global {
  interface Window {
    lexi?: LexiBridge;
    __lexiShot?: (state: string) => void;
  }
}

export {};
