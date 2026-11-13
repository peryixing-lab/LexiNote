/**
 * Data shapes shared by the Electron main process and the renderer.
 * They mirror the HarmonyOS LexiNote models (core/LexiModels.ets) so note
 * files, mind maps and canvases keep the same meaning on Windows.
 */

export type WorkspaceOpenMode = 'ask' | 'current' | 'new';

export interface VaultItem {
  id: string;
  name: string;
  description: string;
  createdAt: number;
  archived: boolean;
  favorite: boolean;
  folderUri: string;
  /** Per-workspace open preference; 'ask' means show the open dialog. */
  openMode: WorkspaceOpenMode;
}

export interface LexiProject {
  id: string;
  vaultId: string;
  name: string;
  archived: boolean;
  favorite: boolean;
  createdAt: number;
}

export interface NoteProperty {
  key: string;
  value: string;
}

export type NoteType = 'quick' | 'study' | 'markdown';

export interface NoteItem {
  id: string;
  vaultId: string;
  projectId: string;
  title: string;
  notebook: string;
  content: string;
  noteType: NoteType;
  editorLevel: 'simple' | 'study' | 'pro';
  tags: string[];
  properties: NoteProperty[];
  pinned: boolean;
  favorite: boolean;
  trashedAt: number;
  createdAt: number;
  updatedAt: number;
  path: string;
}

export type MindMapColor = 'purple' | 'indigo' | 'teal' | 'amber' | 'rose';

export interface OutlineHeading {
  id: string;
  level: number;
  title: string;
  lineIndex: number;
}

export interface MindMapNode {
  id: string;
  parentId: string;
  text: string;
  note: string;
  noteRefId: string;
  noteRefTitle: string;
  order: number;
  collapsed: boolean;
  colorTag: MindMapColor;
  level: number;
  x: number;
  y: number;
  boxWidth: number;
  boxHeight: number;
  offsetX: number;
  offsetY: number;
}

export interface MindMapDoc {
  id: string;
  vaultId: string;
  projectId: string;
  title: string;
  layoutKind: 'right' | 'balanced' | 'org';
  rootNodeId: string;
  nodes: MindMapNode[];
  favorite: boolean;
  trashedAt: number;
  createdAt: number;
  updatedAt: number;
}

export interface CanvasCard {
  id: string;
  title: string;
  content: string;
  noteRefId: string;
  noteRefTitle: string;
  x: number;
  y: number;
  colorTag: MindMapColor;
}

export interface CanvasEdge {
  id: string;
  fromId: string;
  toId: string;
  label: string;
}

export interface CanvasBoard {
  id: string;
  vaultId: string;
  projectId: string;
  title: string;
  cards: CanvasCard[];
  edges: CanvasEdge[];
  createdAt: number;
  updatedAt: number;
}

export type ThemeMode = 'light' | 'dark' | 'system';

export interface HotkeyMap {
  [commandId: string]: string;
}

export interface AppSettings {
  theme: ThemeMode;
  accent: string;
  paletteMode: 'original' | 'preset' | 'custom';
  language: 'zh-Hans' | 'en';
  fontSize: number;
  showRibbon: boolean;
  sidebarWidth: number;
  rightSidebarWidth: number;
  showTabHeaders: boolean;
  editorLimitWidth: boolean;
  editorShowTitle: boolean;
  editorViewStatus: boolean;
  editorDefaultView: 'live' | 'source' | 'reading';
  editorDefaultMode: 'live' | 'source';
  zoom: number;
  /** Global "don't ask again" flag; intentionally not stored per workspace. */
  workspacePromptSuppressed: boolean;
  /** Fallback mode used for workspaces still set to 'ask' when prompts are off. */
  workspaceDefaultOpenMode: 'current' | 'new';
  /** Monotonic wall-clock marker used to merge settings across windows. */
  settingsUpdatedAt: number;
  lastVaultId: string;
  lastNoteId: string;
  windowBounds?: { width: number; height: number; x?: number; y?: number; maximized?: boolean };
  hotkeys: HotkeyMap;
}

export interface PersistedState {
  version: number;
  vaults: VaultItem[];
  projects: LexiProject[];
  notes: NoteItem[];
  maps: MindMapDoc[];
  canvases: CanvasBoard[];
  settings: AppSettings;
}

export interface ImportedFile {
  name: string;
  content: string;
}

export interface RuntimeInfo {
  platform: string;
  arch: string;
  appVersion: string;
  electron: string;
  userDataPath: string;
  dataPath: string;
}

export interface MarkdownExportFile {
  name: string;
  content: string;
}
