import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState
} from 'react';
import type {
  AppSettings,
  CanvasBoard,
  LexiProject,
  MindMapDoc,
  NoteItem,
  PersistedState,
  RuntimeInfo,
  VaultItem,
  WorkspaceOpenMode
} from '../../shared/types';
import { defaultSettings, demoState, initialState } from '../core/seed';
import { buildPalette, resolveDark, applyPalette } from '../core/theme';
import { setActiveLanguage } from '../core/i18n';
import { displayTitle, markdownToMindMapNodes, renameLinksInMarkdown } from '../core/markdown';
import { buildNoteLinks, findUnlinkedMentions } from '../core/markdown';
import type { ExtractedLink, UnlinkedMention } from '../core/markdown';
import { DEFAULT_HOTKEYS } from '../core/commands';
import { matchesSearch } from '../core/search';
import { LEXI_ENGLISH } from '../core/english';
import { UI_ENGLISH } from '../core/ui-english';
import type { PluginEditorDraft } from '../../shared/pluginTypes';
import type { StateSyncPayload } from '../global';

export type EditorMode = 'live' | 'source' | 'reading';
export type Section = 1 | 2 | 4;
export type RightSidebarMode = 'outline' | 'properties' | string;

export interface EditorApi {
  focus: () => void;
  format: (command: string) => void;
  toggleSource: () => void;
  toggleReading: () => void;
  find: (replace: boolean) => void;
  getDraft?: () => PluginEditorDraft | null;
  replaceSelectionText?: (text: string) => PluginEditorDraft | null;
  replaceAllText?: (
    text: string,
    expectedRevision?: number
  ) => { ok: boolean; draft: PluginEditorDraft | null; conflict?: boolean };
}

export interface AppStoreState {
  ready: boolean;
  vaults: VaultItem[];
  projects: LexiProject[];
  notes: NoteItem[];
  maps: MindMapDoc[];
  canvases: CanvasBoard[];
  settings: AppSettings;
  activeVaultId: string;
  activeProjectId: string;
  activeSection: Section;
  tabs: string[];
  groupTabs: string[];
  selectedId: string;
  navIds: string[];
  navIndex: number;
  searchText: string;
  favoritesOnly: boolean;
  closedFolders: string[];
  sidebarOpen: boolean;
  rightSidebarOpen: boolean;
  rightSidebarMode: RightSidebarMode;
  paletteOpen: boolean;
  paletteMode: 'commands' | 'switcher';
  settingsOpen: boolean;
  settingsCategory: string;
  trashOpen: boolean;
  workspacesOpen: boolean;
  templatesOpen: boolean;
  helpOpen: boolean;
  workspacePrompt: { vaultId: string; name: string } | null;
  editorModes: Record<string, EditorMode>;
  saveStatus: 'saved' | 'saving' | 'error';
  toast: { id: number; text: string } | null;
  runtime: RuntimeInfo | null;
}

export interface AppActions {
  openDocument: (id: string) => void;
  closeTab: (id: string) => void;
  selectTab: (id: string) => void;
  setSearchText: (text: string) => void;
  setFavoritesOnly: (value: boolean) => void;
  toggleFolder: (folder: string) => void;
  setSidebarOpen: (open: boolean) => void;
  setRightSidebar: (open: boolean, mode?: RightSidebarMode) => void;
  setRightSidebarMode: (mode: RightSidebarMode) => void;
  setSection: (section: Section) => void;
  setActiveVault: (vaultId: string) => void;
  requestWorkspace: (vaultId: string) => void;
  confirmWorkspaceOpen: (mode: 'current' | 'new', suppress: boolean) => Promise<void>;
  cancelWorkspaceOpen: () => void;
  setVaultOpenMode: (vaultId: string, mode: WorkspaceOpenMode) => void;
  setWorkspacePromptSuppressed: (value: boolean) => void;
  setWorkspaceDefaultOpenMode: (mode: 'current' | 'new') => void;
  setActiveProject: (projectId: string) => void;
  createNote: (type: NoteItem['noteType'], title?: string) => string;
  updateNote: (id: string, patch: Partial<NoteItem>) => void;
  renameNote: (id: string, title: string) => void;
  toggleFavorite: (id: string) => void;
  togglePin: (id: string) => void;
  trashNote: (id: string) => void;
  restoreNote: (id: string) => void;
  deleteForever: (id: string) => void;
  emptyTrash: () => void;
  duplicateNote: (id: string) => void;
  createMap: (sourceNoteId?: string) => string;
  updateMap: (doc: MindMapDoc) => void;
  trashMap: (id: string) => void;
  deleteMapForever: (id: string) => void;
  createCanvas: () => string;
  updateCanvas: (board: CanvasBoard) => void;
  createVault: (name: string) => void;
  renameVault: (id: string, name: string) => void;
  createProject: (name: string) => void;
  renameProject: (id: string, name: string) => void;
  deleteProject: (id: string) => void;
  updateSettings: (patch: Partial<AppSettings>) => void;
  setEditorMode: (id: string, mode: EditorMode) => void;
  openPalette: (mode?: 'commands' | 'switcher') => void;
  closePalette: () => void;
  openSettings: (category?: string) => void;
  closeSettings: () => void;
  setSettingsCategory: (category: string) => void;
  setTrashOpen: (open: boolean) => void;
  setWorkspacesOpen: (open: boolean) => void;
  setTemplatesOpen: (open: boolean) => void;
  setHelpOpen: (open: boolean) => void;
  showToast: (text: string) => void;
  executeCommand: (commandId: string) => Promise<void>;
  saveNow: () => Promise<void>;
  exportVaultMarkdown: () => Promise<void>;
  chooseWorkspaceFolder: () => Promise<void>;
  exportWorkspaceZip: () => Promise<void>;
  importWorkspaceZip: () => Promise<void>;
  exportSettingsPlugins: () => Promise<void>;
  importSettingsPlugins: () => Promise<void>;
  rebuildIndex: () => Promise<void>;
  importFiles: () => Promise<void>;
  exportNote: (format: 'md' | 'txt') => Promise<void>;
  registerEditor: (api: EditorApi | null) => void;
  unregisterEditor: (api: EditorApi) => void;
  getEditorApi: () => EditorApi | null;
  getLatestState: () => AppStoreState;
  ensureProjectSync: (vaultId: string, projectName: string) => LexiProject | null;
  createVaultNoteSync: (input: { vaultId: string; projectId: string; title: string; content: string }) => NoteItem;
  updateVaultNoteSync: (id: string, values: Partial<NoteItem>) => NoteItem | null;
  trashVaultNoteSync: (id: string) => boolean;
  moveTab: (from: number, to: number) => void;
  closeOtherTabs: () => void;
  closeAllTabs: () => void;
}

export interface AppStore {
  state: AppStoreState;
  actions: AppActions;
  derived: {
    activeVault: VaultItem | undefined;
    activeProject: LexiProject | undefined;
    visibleNotes: NoteItem[];
    folderNames: string[];
    currentNote: NoteItem | undefined;
    currentMap: MindMapDoc | undefined;
    currentCanvas: CanvasBoard | undefined;
    tabs: { id: string; title: string; kind: 'note' | 'map' | 'canvas' }[];
    links: ExtractedLink[];
    mentions: UnlinkedMention[];
    trashNotes: NoteItem[];
    trashMaps: MindMapDoc[];
    isDark: boolean;
    tr: (source: string, args?: (string | number)[]) => string;
  };
}

const StoreContext = createContext<AppStore | null>(null);

function newId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

function todayKey(): string {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

const EMPTY_STATE: AppStoreState = {
  ready: false,
  vaults: [],
  projects: [],
  notes: [],
  maps: [],
  canvases: [],
  settings: defaultSettings(),
  activeVaultId: 'default-vault',
  activeProjectId: '',
  activeSection: 1,
  tabs: [],
  groupTabs: [],
  selectedId: '',
  navIds: [],
  navIndex: -1,
  searchText: '',
  favoritesOnly: false,
  closedFolders: [],
  sidebarOpen: true,
  rightSidebarOpen: false,
  rightSidebarMode: 'outline',
  paletteOpen: false,
  paletteMode: 'commands',
  settingsOpen: false,
  settingsCategory: 'about',
  trashOpen: false,
  workspacesOpen: false,
  templatesOpen: false,
  helpOpen: false,
  workspacePrompt: null,
  editorModes: {},
  saveStatus: 'saved',
  toast: null,
  runtime: null
};

function requestedVaultIdFromLocation(): string {
  try {
    return new URLSearchParams(window.location.search).get('vaultId') ?? '';
  } catch {
    return '';
  }
}

function normalizeVault(vault: VaultItem): VaultItem {
  return {
    ...vault,
    openMode:
      vault.openMode === 'current' || vault.openMode === 'new' || vault.openMode === 'ask'
        ? vault.openMode
        : 'ask'
  };
}

function notesForVault(notes: NoteItem[], vaultId: string): NoteItem[] {
  return notes.filter((note) => note.vaultId === vaultId && note.trashedAt === 0);
}

function demoDataRequested(): boolean {
  try {
    return new URLSearchParams(window.location.search).get('demo') === '1';
  } catch {
    return false;
  }
}

function normalizeState(
  raw: PersistedState,
  options: { requestedVaultId?: string } = {}
): AppStoreState {
  const settings: AppSettings = {
    ...defaultSettings(),
    ...raw.settings,
    hotkeys: { ...DEFAULT_HOTKEYS, ...(raw.settings?.hotkeys ?? {}) }
  };
  const vaults = (Array.isArray(raw.vaults) ? raw.vaults : []).map(normalizeVault);
  const notes = (Array.isArray(raw.notes) ? raw.notes : []).map((note) => ({
    ...note,
    tags: Array.isArray(note.tags) ? note.tags : [],
    properties: Array.isArray(note.properties) ? note.properties : [],
    projectId: note.projectId || ''
  }));
  const requestedVault = (options.requestedVaultId ?? '')
    ? vaults.find((vault) => vault.id === options.requestedVaultId)
    : undefined;
  const vaultId =
    requestedVault?.id ??
    (vaults.some((vault) => vault.id === settings.lastVaultId)
      ? settings.lastVaultId
      : vaults[0]?.id ?? 'default-vault');
  const vaultNotes = notesForVault(notes, vaultId);
  const selected = requestedVault
    ? vaultNotes[0]?.id ?? ''
    : vaultNotes.some((note) => note.id === settings.lastNoteId)
      ? settings.lastNoteId
      : vaultNotes[0]?.id ?? '';
  return {
    ...EMPTY_STATE,
    ready: true,
    vaults,
    projects: Array.isArray(raw.projects) ? raw.projects : [],
    notes,
    maps: Array.isArray(raw.maps) ? raw.maps : [],
    canvases: Array.isArray(raw.canvases) ? raw.canvases : [],
    settings,
    activeVaultId: vaultId,
    selectedId: selected,
    tabs: selected ? [selected] : [],
    navIds: selected ? [selected] : [],
    navIndex: 0
  };
}

function persisted(state: AppStoreState): PersistedState {
  return {
    version: 2,
    vaults: state.vaults,
    projects: state.projects,
    notes: state.notes,
    maps: state.maps,
    canvases: state.canvases,
    settings: {
      ...state.settings,
      lastVaultId: state.activeVaultId,
      lastNoteId: state.selectedId
    }
  };
}

interface DirtyFlag {
  at: number;
  deleted: boolean;
}

const DIRTY_TTL_MS = 20_000;

function freshDirty(entry: DirtyFlag | undefined): boolean {
  return !!entry && Date.now() - entry.at < DIRTY_TTL_MS;
}

/** Merge entities from the main-process master with local edits that are not saved yet. */
function mergeMasterCollection<T extends { id: string }>(
  incoming: T[],
  local: T[],
  updatedAt: (item: T) => number,
  dirty: Map<string, DirtyFlag>
): T[] {
  const localById = new Map(local.map((item) => [item.id, item]));
  const incomingIds = new Set(incoming.map((item) => item.id));
  const result: T[] = [];

  for (const item of incoming) {
    const localItem = localById.get(item.id);
    const entry = dirty.get(item.id);
    if (!localItem) {
      // A locally deleted item stays deleted until its save settles.
      if (freshDirty(entry) && entry?.deleted) continue;
      result.push(item);
      continue;
    }
    if (freshDirty(entry)) {
      if (entry?.deleted) continue;
      if (updatedAt(localItem) > updatedAt(item)) {
        result.push(localItem);
        continue;
      }
    }
    result.push(item);
  }

  for (const item of local) {
    if (incomingIds.has(item.id)) continue;
    const entry = dirty.get(item.id);
    if (freshDirty(entry) && !entry?.deleted) result.push(item);
  }
  return result;
}

function mergeMasterSimple<T extends { id: string }>(
  incoming: T[],
  local: T[],
  dirty: Map<string, DirtyFlag>
): T[] {
  const localById = new Map(local.map((item) => [item.id, item]));
  const incomingIds = new Set(incoming.map((item) => item.id));
  const result: T[] = [];

  for (const item of incoming) {
    const localItem = localById.get(item.id);
    const entry = dirty.get(item.id);
    if (localItem && freshDirty(entry)) {
      if (entry?.deleted) continue;
      result.push(localItem);
      continue;
    }
    result.push(item);
  }
  for (const item of local) {
    if (incomingIds.has(item.id)) continue;
    const entry = dirty.get(item.id);
    if (freshDirty(entry) && !entry?.deleted) result.push(item);
  }
  return result;
}

function mergeExternalState(
  current: AppStoreState,
  incoming: PersistedState,
  dirty: Map<string, DirtyFlag>
): Partial<AppStoreState> {
  const vaults = mergeMasterSimple(incoming.vaults, current.vaults, dirty);
  const projects = mergeMasterSimple(incoming.projects, current.projects, dirty);
  const notes = mergeMasterCollection(incoming.notes, current.notes, (note) => note.updatedAt, dirty);
  const maps = mergeMasterCollection(incoming.maps, current.maps, (map) => map.updatedAt, dirty);
  const canvases = mergeMasterCollection(
    incoming.canvases,
    current.canvases,
    (board) => board.updatedAt,
    dirty
  );

  const activeVaultId = vaults.some((vault) => vault.id === current.activeVaultId)
    ? current.activeVaultId
    : vaults[0]?.id ?? '';
  const validIds = new Set<string>([
    ...notes.map((note) => note.id),
    ...maps.map((map) => `map:${map.id}`),
    ...canvases.map((board) => `canvas:${board.id}`)
  ]);
  const tabs = current.tabs.filter((id) => validIds.has(id));
  const groupTabs = current.groupTabs.filter((id) => validIds.has(id));
  let selectedId = validIds.has(current.selectedId) ? current.selectedId : tabs[0] ?? '';
  if (!selectedId && activeVaultId) {
    selectedId =
      notes.find((note) => note.vaultId === activeVaultId && note.trashedAt === 0)?.id ?? '';
  }

  return {
    vaults,
    projects,
    notes,
    maps,
    canvases,
    settings:
      (incoming.settings.settingsUpdatedAt ?? 0) >= (current.settings.settingsUpdatedAt ?? 0)
        ? incoming.settings
        : current.settings,
    activeVaultId,
    tabs,
    groupTabs,
    selectedId,
    navIds: current.navIds.filter((id) => validIds.has(id)),
    workspacePrompt:
      current.workspacePrompt && vaults.some((vault) => vault.id === current.workspacePrompt?.vaultId)
        ? current.workspacePrompt
        : null
  };
}

export function AppProvider({ children }: { children: React.ReactNode }): JSX.Element {
  const [state, setState] = useState<AppStoreState>(EMPTY_STATE);
  const stateRef = useRef(state);
  stateRef.current = state;
  const editorApi = useRef<EditorApi | null>(null);
  const saveTimer = useRef<number | null>(null);
  const toastTimer = useRef<number | null>(null);
  const initialised = useRef(false);
  const revisionRef = useRef(0);
  const dirtyRef = useRef<Map<string, DirtyFlag>>(new Map());

  const patch = useCallback((value: Partial<AppStoreState> | ((current: AppStoreState) => Partial<AppStoreState>)) => {
    setState((current) => ({ ...current, ...(typeof value === 'function' ? value(current) : value) }));
  }, []);

  const markDirty = useCallback((id: string, deleted = false): void => {
    const now = Date.now();
    for (const [key, entry] of dirtyRef.current) {
      if (now - entry.at > DIRTY_TTL_MS) dirtyRef.current.delete(key);
    }
    dirtyRef.current.set(id, { at: now, deleted });
  }, []);

  // Boot: load persisted state (or seed), runtime info, and publish the language.
  useEffect(() => {
    let cancelled = false;
    async function boot(): Promise<void> {
      let loaded: PersistedState | null = null;
      let runtime: RuntimeInfo | null = null;
      let revision = 0;
      try {
        if (window.lexi) {
          const [envelope, info] = await Promise.all([window.lexi.loadState(), window.lexi.runtimeInfo()]);
          loaded = envelope.state;
          revision = envelope.revision;
          runtime = info;
        } else {
          const raw = localStorage.getItem('lexinote-state');
          loaded = raw ? (JSON.parse(raw) as PersistedState) : null;
          revision = loaded ? 1 : 0;
        }
      } catch (error) {
        console.warn('Unable to read LexiNote data', error);
      }
      if (cancelled) return;
      revisionRef.current = revision;
      const base = loaded ?? (demoDataRequested() ? demoState() : initialState());
      const next = normalizeState(base, { requestedVaultId: requestedVaultIdFromLocation() });
      initialised.current = true;
      setState((current) => ({ ...next, runtime, activeSection: current.activeSection }));
    }
    void boot();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const dispose = window.lexi?.onStateSync((payload: StateSyncPayload) => {
      if (!stateRef.current.ready) return;
      revisionRef.current = Math.max(revisionRef.current, payload.revision);
      setState((current) => ({
        ...current,
        ...mergeExternalState(current, payload.state, dirtyRef.current)
      }));
    });
    return () => dispose?.();
  }, []);

  useEffect(() => {
    setActiveLanguage(state.settings.language);
  }, [state.settings.language]);

  // Theme: palette derived from accent + resolved dark mode.
  const isDark = useMemo(() => resolveDark(state.settings.theme), [state.settings.theme]);
  useEffect(() => {
    const palette = buildPalette(state.settings.accent, isDark, state.settings.paletteMode);
    applyPalette(palette, isDark);
  }, [state.settings.accent, state.settings.paletteMode, isDark]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const listener = (): void => {
      if (stateRef.current.settings.theme === 'system') {
        applyPalette(
          buildPalette(stateRef.current.settings.accent, media.matches, stateRef.current.settings.paletteMode),
          media.matches
        );
        setState((current) => ({ ...current }));
      }
    };
    media.addEventListener('change', listener);
    return () => media.removeEventListener('change', listener);
  }, []);

  useEffect(() => {
    const zoom = Math.min(160, Math.max(70, state.settings.zoom)) / 100;
    document.documentElement.style.setProperty('--app-zoom', String(zoom));
  }, [state.settings.zoom]);

  const persist = useCallback(async (showStatus = false): Promise<void> => {
    const snapshot = persisted(stateRef.current);
    try {
      if (window.lexi) {
        const result = await window.lexi.saveState(snapshot, revisionRef.current);
        revisionRef.current = Math.max(revisionRef.current, result.revision);
      } else {
        localStorage.setItem('lexinote-state', JSON.stringify(snapshot));
      }
      if (showStatus || stateRef.current.saveStatus === 'saving') {
        patch({ saveStatus: 'saved' });
      }
    } catch (error) {
      console.error('save failed', error);
      patch({ saveStatus: 'error' });
    }
  }, [patch]);

  const flushSave = useCallback(async (): Promise<void> => {
    if (saveTimer.current !== null) {
      window.clearTimeout(saveTimer.current);
      saveTimer.current = null;
    }
    await persist(true);
  }, [persist]);

  const scheduleSave = useCallback((): void => {
    if (!initialised.current) return;
    patch({ saveStatus: 'saving' });
    if (saveTimer.current !== null) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      saveTimer.current = null;
      void persist();
    }, 350);
  }, [patch, persist]);

  useEffect(() => {
    if (!state.ready) return;
    scheduleSave();
    // Scheduling is keyed on the persisted slice only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    state.notes,
    state.maps,
    state.canvases,
    state.vaults,
    state.projects,
    state.settings,
    state.activeVaultId,
    state.activeProjectId
  ]);

  useEffect(() => {
    const listener = (): void => {
      if (saveTimer.current !== null) {
        window.clearTimeout(saveTimer.current);
        saveTimer.current = null;
        void persist();
      }
    };
    window.addEventListener('blur', listener);
    window.addEventListener('beforeunload', listener);
    return () => {
      window.removeEventListener('blur', listener);
      window.removeEventListener('beforeunload', listener);
    };
  }, [persist]);

  const showToast = useCallback((text: string): void => {
    if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    setState((current) => ({ ...current, toast: { id: Date.now(), text } }));
    toastTimer.current = window.setTimeout(() => {
      setState((current) => ({ ...current, toast: null }));
      toastTimer.current = null;
    }, 3200);
  }, []);

  const updateSettings = useCallback((values: Partial<AppSettings>): void => {
    patch((current) => ({
      settings: { ...current.settings, ...values, settingsUpdatedAt: Date.now() }
    }));
  }, [patch]);

  const noteById = (id: string): NoteItem | undefined => stateRef.current.notes.find((note) => note.id === id);

  const pushNavigation = useCallback((id: string): void => {
    setState((current) => {
      if (current.navIds[current.navIndex] === id) return { ...current, selectedId: id };
      const ids = current.navIds.slice(0, current.navIndex + 1);
      ids.push(id);
      return { ...current, navIds: ids, navIndex: ids.length - 1, selectedId: id };
    });
  }, []);

  const openDocument = useCallback((id: string): void => {
    if (!id) return;
    const current = stateRef.current;
    const known =
      current.notes.some((note) => note.id === id) ||
      current.maps.some((map) => `map:${map.id}` === id) ||
      current.canvases.some((board) => `canvas:${board.id}` === id);
    if (!known) {
      showToast('笔记不存在或已被删除');
      return;
    }
    const existsInVault = current.notes.some((note) => note.id === id && note.vaultId === current.activeVaultId);
    const mapId = id.startsWith('map:') ? id.substring(4) : '';
    const canvasId = id.startsWith('canvas:') ? id.substring(7) : '';
    const targetVault = existsInVault
      ? current.activeVaultId
      : current.notes.find((note) => note.id === id)?.vaultId ??
        current.maps.find((map) => map.id === mapId)?.vaultId ??
        current.canvases.find((board) => board.id === canvasId)?.vaultId;
    setState((previous) => {
      const tabs = previous.tabs.includes(id) ? previous.tabs : previous.tabs.concat(id);
      return {
        ...previous,
        tabs,
        activeSection: 1,
        activeVaultId: targetVault ?? previous.activeVaultId,
        selectedId: id
      };
    });
    pushNavigation(id);
  }, [pushNavigation, showToast]);

  const createNote = useCallback((type: NoteItem['noteType'], title = ''): string => {
    const current = stateRef.current;
    const id = newId('note');
    const now = Date.now();
    const notebook = type === 'study' ? '计算机课程' : type === 'markdown' ? '笔记' : '速记收件箱';
    const note: NoteItem = {
      id,
      vaultId: current.activeVaultId,
      projectId: current.activeProjectId,
      title: title.trim(),
      notebook,
      content:
        type === 'study'
          ? `# ${title.trim() || '学习笔记'}\n\n## 学习目标\n\n- \n\n## 核心概念\n\n\n\n## 自测清单\n\n- [ ] \n`
          : type === 'markdown'
            ? `# ${title.trim() || '新笔记'}\n\n`
            : '',
      noteType: type,
      editorLevel: type === 'study' ? 'study' : type === 'markdown' ? 'pro' : 'simple',
      tags: [],
      properties: [],
      pinned: false,
      favorite: false,
      trashedAt: 0,
      createdAt: now,
      updatedAt: now,
      path: ''
    };
    setState((previous) => ({
      ...previous,
      notes: [note, ...previous.notes],
      tabs: previous.tabs.concat(id),
      activeSection: 1,
      selectedId: id,
      editorModes: { ...previous.editorModes, [id]: type === 'quick' ? 'source' : previous.settings.editorDefaultView }
    }));
    markDirty(id);
    pushNavigation(id);
    return id;
  }, [markDirty, pushNavigation]);

  const updateNote = useCallback((id: string, values: Partial<NoteItem>): void => {
    setState((current) => ({
      ...current,
      notes: current.notes.map((note) =>
        note.id === id ? { ...note, ...values, updatedAt: Date.now() } : note
      )
    }));
    markDirty(id);
  }, [markDirty]);

  const renameNote = useCallback((id: string, title: string): void => {
    const current = stateRef.current;
    const target = current.notes.find((note) => note.id === id);
    if (!target) return;
    const oldTitle = displayTitle(target);
    const clean = title.trim();
    setState((previous) => ({
      ...previous,
      notes: previous.notes.map((note) => {
        if (note.id === id) return { ...note, title: clean, updatedAt: Date.now() };
        if (note.vaultId === target.vaultId && note.content.includes('[[')) {
          const nextContent = renameLinksInMarkdown(note.content, oldTitle, clean || '未命名笔记');
          return nextContent === note.content ? note : { ...note, content: nextContent, updatedAt: Date.now() };
        }
        return note;
      })
    }));
    markDirty(id);
  }, [markDirty]);

  const toggleNoteFlag = useCallback((id: string, flag: 'favorite' | 'pinned'): void => {
    setState((current) => ({
      ...current,
      notes: current.notes.map((note) =>
        note.id === id ? { ...note, [flag]: !note[flag], updatedAt: Date.now() } : note
      )
    }));
    markDirty(id);
  }, [markDirty]);

  const trashNote = useCallback((id: string): void => {
    const current = stateRef.current;
    const closingTabs = current.tabs.filter((tabId) => tabId === id);
    setState((previous) => {
      const now = Date.now();
      const notes = previous.notes.map((note) =>
        note.id === id ? { ...note, trashedAt: now, updatedAt: now } : note
      );
      const tabs = previous.tabs.filter((tabId) => tabId !== id);
      const groupTabs = previous.groupTabs.filter((tabId) => tabId !== id);
      return {
        ...previous,
        notes,
        tabs,
        groupTabs,
        selectedId: previous.selectedId === id ? tabs[tabs.length - 1] ?? '' : previous.selectedId
      };
    });
    markDirty(id);
    if (closingTabs.length > 0) showToast('已移到回收站');
  }, [markDirty, showToast]);

  const restoreNote = useCallback((id: string): void => {
    setState((current) => ({
      ...current,
      notes: current.notes.map((note) =>
        note.id === id ? { ...note, trashedAt: 0, updatedAt: Date.now() } : note
      )
    }));
    markDirty(id);
    showToast('已恢复笔记');
  }, [markDirty, showToast]);

  const deleteForever = useCallback((id: string): void => {
    setState((current) => ({ ...current, notes: current.notes.filter((note) => note.id !== id) }));
    markDirty(id, true);
    showToast('已永久删除');
  }, [markDirty, showToast]);

  const emptyTrash = useCallback((): void => {
    const current = stateRef.current;
    for (const note of current.notes) if (note.trashedAt > 0) markDirty(note.id, true);
    for (const map of current.maps) if (map.trashedAt > 0) markDirty(map.id, true);
    setState((previous) => ({
      ...previous,
      notes: previous.notes.filter((note) => note.trashedAt === 0),
      maps: previous.maps.filter((map) => map.trashedAt === 0)
    }));
    showToast('回收站已清空');
  }, [markDirty, showToast]);

  const duplicateNote = useCallback((id: string): void => {
    const source = noteById(id);
    if (!source) return;
    const copy: NoteItem = {
      ...source,
      id: newId('note'),
      title: `${displayTitle(source)} 副本`,
      favorite: false,
      pinned: false,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
    setState((current) => ({
      ...current,
      notes: [copy, ...current.notes],
      tabs: current.tabs.concat(copy.id),
      selectedId: copy.id
    }));
    markDirty(copy.id);
    showToast('已创建副本');
  }, [markDirty, showToast]);

  const createMap = useCallback((sourceNoteId?: string): string => {
    const current = stateRef.current;
    const source = sourceNoteId ? current.notes.find((note) => note.id === sourceNoteId) : undefined;
    const id = newId('map');
    const now = Date.now();
    const doc: MindMapDoc = {
      id,
      vaultId: current.activeVaultId,
      projectId: current.activeProjectId,
      title: source ? `${displayTitle(source)}导图` : '未命名导图',
      layoutKind: 'right',
      rootNodeId: 'root',
      nodes: source
        ? markdownToMindMapNodes(displayTitle(source), source.content, source.id)
        : markdownToMindMapNodes('核心主题', '', ''),
      favorite: false,
      trashedAt: 0,
      createdAt: now,
      updatedAt: now
    };
    setState((previous) => ({
      ...previous,
      maps: [doc, ...previous.maps],
      tabs: previous.tabs.concat(`map:${id}`),
      activeSection: 1,
      selectedId: `map:${id}`
    }));
    markDirty(id);
    pushNavigation(`map:${id}`);
    return id;
  }, [markDirty, pushNavigation]);

  const updateMap = useCallback((doc: MindMapDoc): void => {
    setState((current) => ({
      ...current,
      maps: current.maps.map((map) => (map.id === doc.id ? { ...doc, updatedAt: Date.now() } : map))
    }));
    markDirty(doc.id);
  }, [markDirty]);

  const trashMap = useCallback((id: string): void => {
    setState((current) => ({
      ...current,
      maps: current.maps.map((map) =>
        map.id === id ? { ...map, trashedAt: Date.now(), updatedAt: Date.now() } : map
      ),
      tabs: current.tabs.filter((tab) => tab !== `map:${id}`),
      groupTabs: current.groupTabs.filter((tab) => tab !== `map:${id}`),
      selectedId: current.selectedId === `map:${id}` ? '' : current.selectedId
    }));
    markDirty(id);
    showToast('导图已移到回收站');
  }, [markDirty, showToast]);

  const deleteMapForever = useCallback((id: string): void => {
    setState((current) => ({
      ...current,
      maps: current.maps.filter((map) => map.id !== id),
      tabs: current.tabs.filter((tab) => tab !== `map:${id}`),
      groupTabs: current.groupTabs.filter((tab) => tab !== `map:${id}`),
      selectedId: current.selectedId === `map:${id}` ? '' : current.selectedId
    }));
    markDirty(id, true);
    showToast('已永久删除导图');
  }, [markDirty, showToast]);

  const createCanvas = useCallback((): string => {
    const current = stateRef.current;
    const id = newId('canvas');
    const now = Date.now();
    const board: CanvasBoard = {
      id,
      vaultId: current.activeVaultId,
      projectId: current.activeProjectId,
      title: '未命名白板',
      cards: [],
      edges: [],
      createdAt: now,
      updatedAt: now
    };
    setState((previous) => ({
      ...previous,
      canvases: [board, ...previous.canvases],
      tabs: previous.tabs.concat(`canvas:${id}`),
      activeSection: 1,
      selectedId: `canvas:${id}`
    }));
    markDirty(id);
    pushNavigation(`canvas:${id}`);
    return id;
  }, [markDirty, pushNavigation]);

  const updateCanvas = useCallback((board: CanvasBoard): void => {
    setState((current) => ({
      ...current,
      canvases: current.canvases.map((item) =>
        item.id === board.id ? { ...board, updatedAt: Date.now() } : item
      )
    }));
    markDirty(board.id);
  }, [markDirty]);

  const setActiveVault = useCallback((vaultId: string): void => {
    const current = stateRef.current;
    if (vaultId === current.activeVaultId) return;
    const next = current.notes.find(
      (note) => note.vaultId === vaultId && note.trashedAt === 0
    );
    setState((previous) => ({
      ...previous,
      activeVaultId: vaultId,
      activeProjectId: '',
      tabs: [],
      groupTabs: [],
      selectedId: '',
      searchText: ''
    }));
    if (next) openDocument(next.id);
    showToast(`已切换到 ${current.vaults.find((vault) => vault.id === vaultId)?.name ?? '工作区'}`);
    void flushSave();
  }, [openDocument, showToast, flushSave]);

  const openWorkspaceNow = useCallback(
    async (vaultId: string, mode: 'current' | 'new', suppress: boolean): Promise<void> => {
      const current = stateRef.current;
      const vault = current.vaults.find((item) => item.id === vaultId);
      if (!vault) {
        showToast('工作区不存在或已归档');
        return;
      }
      // Make sure the new window sees the latest edits from this one.
      await flushSave();
      if (mode === 'new') {
        if (!window.lexi?.openWorkspaceWindow) {
          showToast('当前环境不支持打开新窗口');
          return;
        }
        const opened = await window.lexi.openWorkspaceWindow(vaultId);
        if (!opened) {
          showToast('无法打开新窗口');
          return;
        }
        showToast(`已在新窗口打开「${vault.name}」`);
      } else {
        setActiveVault(vaultId);
      }
      if (suppress) {
        updateSettings({
          workspacePromptSuppressed: true,
          workspaceDefaultOpenMode: mode
        });
      }
      patch({ workspacePrompt: null, workspacesOpen: false });
    },
    [flushSave, patch, setActiveVault, showToast, updateSettings]
  );

  /** Panel entry point for the workspace switcher: honour the per-workspace mode. */
  const requestWorkspace = useCallback(
    (vaultId: string): void => {
      const current = stateRef.current;
      if (!vaultId || vaultId === current.activeVaultId) return;
      const vault = current.vaults.find((item) => item.id === vaultId);
      if (!vault) {
        showToast('工作区不存在或已归档');
        return;
      }
      const mode = vault.openMode;
      if (current.settings.workspacePromptSuppressed) {
        void openWorkspaceNow(
          vaultId,
          mode === 'ask' ? current.settings.workspaceDefaultOpenMode : mode,
          false
        );
        return;
      }
      if (mode === 'ask') {
        patch({ workspacePrompt: { vaultId, name: vault.name }, workspacesOpen: false });
        return;
      }
      void openWorkspaceNow(vaultId, mode, false);
    },
    [openWorkspaceNow, patch, showToast]
  );

  const confirmWorkspaceOpen = useCallback(
    async (mode: 'current' | 'new', suppress: boolean): Promise<void> => {
      const prompt = stateRef.current.workspacePrompt;
      if (!prompt) return;
      await openWorkspaceNow(prompt.vaultId, mode, suppress);
    },
    [openWorkspaceNow]
  );

  const cancelWorkspaceOpen = useCallback((): void => {
    patch({ workspacePrompt: null });
  }, [patch]);

  const setVaultOpenMode = useCallback(
    (vaultId: string, mode: WorkspaceOpenMode): void => {
      setState((current) => ({
        ...current,
        vaults: current.vaults.map((vault) =>
          vault.id === vaultId ? { ...vault, openMode: mode } : vault
        )
      }));
      markDirty(vaultId);
    },
    [markDirty]
  );

  const setWorkspacePromptSuppressed = useCallback(
    (value: boolean): void => {
      updateSettings({ workspacePromptSuppressed: value });
    },
    [updateSettings]
  );

  const setWorkspaceDefaultOpenMode = useCallback(
    (mode: 'current' | 'new'): void => {
      updateSettings({ workspaceDefaultOpenMode: mode });
    },
    [updateSettings]
  );

  const createVault = useCallback((name: string): void => {
    const clean = name.trim();
    if (!clean) return;
    const vault: VaultItem = {
      id: newId('vault'),
      name: clean,
      description: '',
      createdAt: Date.now(),
      archived: false,
      favorite: false,
      folderUri: '',
      openMode: 'ask'
    };
    setState((current) => ({ ...current, vaults: current.vaults.concat(vault) }));
    markDirty(vault.id);
    showToast('已创建工作区');
  }, [markDirty, showToast]);

  const renameVault = useCallback((id: string, name: string): void => {
    const clean = name.trim();
    if (!clean) return;
    setState((current) => ({
      ...current,
      vaults: current.vaults.map((vault) => (vault.id === id ? { ...vault, name: clean } : vault))
    }));
    markDirty(id);
  }, [markDirty]);

  const createProject = useCallback((name: string): void => {
    const clean = name.trim();
    if (!clean) return;
    const project: LexiProject = {
      id: newId('project'),
      vaultId: stateRef.current.activeVaultId,
      name: clean,
      archived: false,
      favorite: false,
      createdAt: Date.now()
    };
    setState((current) => ({ ...current, projects: current.projects.concat(project) }));
    markDirty(project.id);
    showToast('已创建项目');
  }, [markDirty, showToast]);

  const renameProject = useCallback((id: string, name: string): void => {
    const clean = name.trim();
    if (!clean) return;
    setState((current) => ({
      ...current,
      projects: current.projects.map((project) => (project.id === id ? { ...project, name: clean } : project))
    }));
    markDirty(id);
  }, [markDirty]);

  const deleteProject = useCallback((id: string): void => {
    const affected = stateRef.current.notes.filter((note) => note.projectId === id);
    setState((current) => ({
      ...current,
      projects: current.projects.filter((project) => project.id !== id),
      notes: current.notes.map((note) =>
        note.projectId === id ? { ...note, projectId: '', updatedAt: Date.now() } : note
      ),
      activeProjectId: current.activeProjectId === id ? '' : current.activeProjectId
    }));
    markDirty(id, true);
    for (const note of affected) markDirty(note.id);
    showToast('已删除项目，笔记保留在工作区');
  }, [markDirty, showToast]);

  const ensureProjectSync = useCallback((vaultId: string, projectName: string): LexiProject | null => {
    const clean = projectName.trim();
    if (!clean) return null;
    const current = stateRef.current;
    const existing = current.projects.find(
      (project) => project.vaultId === vaultId && project.name.toLowerCase() === clean.toLowerCase()
    );
    if (existing) return existing;
    const project: LexiProject = {
      id: newId('project'),
      vaultId,
      name: clean,
      archived: false,
      favorite: false,
      createdAt: Date.now()
    };
    stateRef.current = { ...current, projects: current.projects.concat(project) };
    setState((previous) =>
      previous.projects.some((item) => item.id === project.id)
        ? previous
        : { ...previous, projects: previous.projects.concat(project) }
    );
    markDirty(project.id);
    return project;
  }, [markDirty]);

  const createVaultNoteSync = useCallback(
    (input: { vaultId: string; projectId: string; title: string; content: string }): NoteItem => {
      const current = stateRef.current;
      const now = Date.now();
      const projectName = input.projectId
        ? current.projects.find((item) => item.id === input.projectId)?.name ?? ''
        : '';
      const note: NoteItem = {
        id: newId('note'),
        vaultId: input.vaultId,
        projectId: input.projectId,
        title: input.title.trim() || '新笔记',
        notebook: projectName || '笔记',
        content: input.content,
        noteType: 'markdown',
        editorLevel: 'pro',
        tags: [],
        properties: [],
        pinned: false,
        favorite: false,
        trashedAt: 0,
        createdAt: now,
        updatedAt: now,
        path: ''
      };
      stateRef.current = { ...current, notes: [note, ...current.notes] };
      setState((previous) =>
        previous.notes.some((item) => item.id === note.id)
          ? previous
          : { ...previous, notes: [note, ...previous.notes] }
      );
      markDirty(note.id);
      return note;
    },
    [markDirty]
  );

  const updateVaultNoteSync = useCallback(
    (id: string, values: Partial<NoteItem>): NoteItem | null => {
      const current = stateRef.current;
      const existing = current.notes.find((note) => note.id === id);
      if (!existing) return null;
      const updated: NoteItem = {
        ...existing,
        ...values,
        updatedAt: values.updatedAt ?? Date.now()
      };
      stateRef.current = {
        ...current,
        notes: current.notes.map((note) => (note.id === id ? updated : note))
      };
      setState((previous) => ({
        ...previous,
        notes: previous.notes.map((note) => (note.id === id ? { ...note, ...values, updatedAt: updated.updatedAt } : note))
      }));
      markDirty(id);
      return updated;
    },
    [markDirty]
  );

  const trashVaultNoteSync = useCallback(
    (id: string): boolean => {
      const current = stateRef.current;
      const existing = current.notes.find((note) => note.id === id && note.trashedAt === 0);
      if (!existing) return false;
      const now = Date.now();
      const nextNotes = current.notes.map((note) =>
        note.id === id ? { ...note, trashedAt: now, updatedAt: now } : note
      );
      const nextTabs = current.tabs.filter((tabId) => tabId !== id);
      const nextGroupTabs = current.groupTabs.filter((tabId) => tabId !== id);
      const nextSelected = current.selectedId === id ? nextTabs[nextTabs.length - 1] ?? '' : current.selectedId;
      stateRef.current = {
        ...current,
        notes: nextNotes,
        tabs: nextTabs,
        groupTabs: nextGroupTabs,
        selectedId: nextSelected
      };
      setState((previous) => {
        const tabs = previous.tabs.filter((tabId) => tabId !== id);
        return {
          ...previous,
          notes: previous.notes.map((note) =>
            note.id === id ? { ...note, trashedAt: now, updatedAt: now } : note
          ),
          tabs,
          groupTabs: previous.groupTabs.filter((tabId) => tabId !== id),
          selectedId: previous.selectedId === id ? tabs[tabs.length - 1] ?? '' : previous.selectedId
        };
      });
      markDirty(id);
      return true;
    },
    [markDirty]
  );

  const closeTab = useCallback((id: string): void => {
    setState((current) => {
      const index = current.tabs.indexOf(id);
      const tabs = current.tabs.filter((tab) => tab !== id);
      return {
        ...current,
        tabs,
        selectedId:
          current.selectedId === id
            ? tabs[Math.min(index, Math.max(0, tabs.length - 1))] ?? ''
            : current.selectedId
      };
    });
  }, []);

  const moveTab = useCallback((from: number, to: number): void => {
    setState((current) => {
      if (from === to || from < 0 || to < 0 || from >= current.tabs.length || to >= current.tabs.length) return current;
      const tabs = current.tabs.slice();
      const [item] = tabs.splice(from, 1);
      tabs.splice(to, 0, item);
      return { ...current, tabs };
    });
  }, []);

  const openPalette = useCallback((mode: 'commands' | 'switcher' = 'commands'): void => {
    setState((current) => ({ ...current, paletteOpen: true, paletteMode: mode, activeSection: 1 }));
  }, []);

  const exportVaultMarkdown = useCallback(async (): Promise<void> => {
    const current = stateRef.current;
    if (!window.lexi) {
      showToast('浏览器预览中不支持导出到文件夹');
      return;
    }
    const folder = await window.lexi.chooseFolder();
    if (!folder) return;
    const vaultNotes = current.notes.filter((note) => note.vaultId === current.activeVaultId && note.trashedAt === 0);
    const files = vaultNotes.map((note) => ({
      name: `${displayTitle(note).replace(/[\\/:*?"<>|]/g, '-')}.md`,
      content: note.content
    }));
    const maps = current.maps.filter((map) => map.vaultId === current.activeVaultId && map.trashedAt === 0);
    const mapFolder = `${folder}/思维导图`;
    const count = await window.lexi.exportMarkdown(files, folder);
    if (maps.length > 0) {
      await window.lexi.exportMarkdown(
        maps.map((map) => ({ name: `${map.title.replace(/[\\/:*?"<>|]/g, '-')}.mindmap.json`, content: JSON.stringify(map, null, 2) })),
        mapFolder
      );
    }
    showToast(`已导出 ${count} 篇笔记`);
  }, [showToast]);

  const chooseWorkspaceFolder = useCallback(async (): Promise<void> => {
    if (!window.lexi) return;
    const folder = await window.lexi.chooseFolder();
    if (!folder) return;
    const vaultId = stateRef.current.activeVaultId;
    setState((previous) => ({
      ...previous,
      vaults: previous.vaults.map((v) => (v.id === vaultId ? { ...v, folderUri: folder } : v))
    }));
    showToast(`工作区文件夹已设为 ${folder}`);
  }, [showToast]);

  const exportWorkspaceZip = useCallback(async (): Promise<void> => {
    if (!window.lexi) {
      showToast('浏览器预览中不支持导出压缩包');
      return;
    }
    const vault = stateRef.current.vaults.find((v) => v.id === stateRef.current.activeVaultId);
    if (!vault) return;
    const res = await window.lexi.exportWorkspaceZip(vault);
    if (res) showToast(`已导出工作区压缩包（${res.count} 个文件）`);
  }, [showToast]);

  const importWorkspaceZip = useCallback(async (): Promise<void> => {
    if (!window.lexi) return;
    try {
      const res = await window.lexi.importWorkspaceZip();
      if (!res) return;
      const newVault: VaultItem = {
        id: res.vaultId,
        name: res.folderName,
        description: '本地文件夹工作区',
        createdAt: Date.now(),
        archived: false,
        favorite: false,
        folderUri: res.folderPath,
        openMode: 'ask'
      };
      setState((previous) => ({
        ...previous,
        vaults: [...previous.vaults, newVault],
        activeVaultId: newVault.id,
        notes: [...res.notes, ...previous.notes],
        maps: [...res.maps, ...previous.maps],
        canvases: [...res.canvases, ...previous.canvases],
        tabs: [],
        activeTabId: ''
      }));
      showToast(`已解压 ${res.fileCount} 个文件到「${res.folderName}」`);
    } catch (error) {
      showToast((error as Error).message || '解压失败');
    }
  }, [showToast]);

  const exportSettingsPlugins = useCallback(async (): Promise<void> => {
    if (!window.lexi) return;
    const target = await window.lexi.exportSettingsPlugins(stateRef.current.settings as unknown as Record<string, unknown>);
    if (target) showToast('设置与插件合集已导出');
  }, [showToast]);

  const importSettingsPlugins = useCallback(async (): Promise<void> => {
    if (!window.lexi) return;
    try {
      const imported = await window.lexi.importSettingsPlugins();
      if (!imported) return;
      setState((previous) => ({
        ...previous,
        settings: { ...previous.settings, ...imported, settingsUpdatedAt: Date.now() }
      }));
      showToast('设置与插件配置已导入');
    } catch (error) {
      showToast((error as Error).message || '导入失败');
    }
  }, [showToast]);

  const rebuildIndex = useCallback(async (): Promise<void> => {
    if (!window.lexi) return;
    const vault = stateRef.current.vaults.find((v) => v.id === stateRef.current.activeVaultId);
    if (!vault) return;
    const folderPath = await window.lexi.resolveWorkspaceFolder(vault);
    const scanned = await window.lexi.scanWorkspaceFolder(folderPath, vault.id);
    setState((previous) => ({
      ...previous,
      notes: [...previous.notes.filter((n) => n.vaultId !== vault.id), ...scanned.notes],
      maps: [...previous.maps.filter((m) => m.vaultId !== vault.id), ...scanned.maps],
      canvases: [...previous.canvases.filter((c) => c.vaultId !== vault.id), ...scanned.canvases]
    }));
    showToast(`已重建 ${scanned.notes.length} 篇笔记索引`);
  }, [showToast]);

  const importFiles = useCallback(async (): Promise<void> => {
    if (!window.lexi) {
      showToast('浏览器预览中不支持导入文件');
      return;
    }
    const files = await window.lexi.importFiles();
    if (!files.length) return;
    const current = stateRef.current;
    const created: NoteItem[] = [];
    for (const file of files) {
      if (file.name.toLowerCase().endsWith('.json')) {
        try {
          const parsed = JSON.parse(file.content) as PersistedState;
          if (Array.isArray(parsed.notes)) {
            const ids = new Set(current.notes.map((note) => note.id));
            const restored = parsed.notes
              .filter((note) => !ids.has(note.id))
              .map((note) => ({ ...note, vaultId: current.activeVaultId }));
            created.push(...restored);
            continue;
          }
        } catch {
          // Not a LexiNote backup; import it as a note below.
        }
      }
      const title = file.name.replace(/\.(md|markdown|txt)$/i, '');
      created.push({
        id: newId('note'),
        vaultId: current.activeVaultId,
        projectId: current.activeProjectId,
        title,
        notebook: '外部导入',
        content: file.content,
        noteType: 'markdown',
        editorLevel: 'pro',
        tags: [],
        properties: [],
        pinned: false,
        favorite: false,
        trashedAt: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        path: ''
      });
    }
    if (created.length === 0) {
      showToast('没有可导入的笔记');
      return;
    }
    setState((previous) => ({ ...previous, notes: created.concat(previous.notes) }));
    showToast(`已导入 ${created.length} 篇笔记`);
    openDocument(created[0].id);
  }, [openDocument, showToast]);

  const exportNote = useCallback(async (format: 'md' | 'txt'): Promise<void> => {
    const note = noteById(stateRef.current.selectedId);
    if (!note) {
      showToast('请先打开一篇笔记');
      return;
    }
    if (!window.lexi) return;
    const name = `${displayTitle(note).replace(/[\\/:*?"<>|]/g, '-')}.${format}`;
    const content = format === 'md' ? note.content : note.content.replace(/```[\s\S]*?```/g, '');
    const target = await window.lexi.exportText(content, name, [
      { name: format === 'md' ? 'Markdown' : '纯文本', extensions: [format] }
    ]);
    if (target) showToast('已导出');
  }, [showToast]);

  const saveNow = useCallback(async (): Promise<void> => {
    await flushSave();
    showToast('已保存到本机');
  }, [flushSave, showToast]);

  const executeCommand = useCallback(async (commandId: string): Promise<void> => {
    const current = stateRef.current;
    if (commandId.startsWith('editor-')) {
      editorApi.current?.format(commandId.substring(7));
      return;
    }
    switch (commandId) {
      case 'palette':
        openPalette('commands');
        return;
      case 'switcher':
        openPalette('switcher');
        return;
      case 'save':
        await saveNow();
        return;
      case 'new':
        createNote('markdown');
        return;
      case 'quick':
        createNote('quick');
        return;
      case 'study':
        createNote('study');
        return;
      case 'daily': {
        const key = todayKey();
        const existing = current.notes.find(
          (note) => note.vaultId === current.activeVaultId && note.trashedAt === 0 && note.title.includes(key)
        );
        if (existing) openDocument(existing.id);
        else {
          const id = createNote('markdown', key);
          updateNote(id, {
            title: key,
            notebook: '日记',
            content: `# ${key}\n\n## 今天做了什么\n\n\n\n## 明天的重点\n\n- \n`
          });
        }
        return;
      }
      case 'templates':
        patch({ templatesOpen: true });
        return;
      case 'save-template': {
        const note = noteById(current.selectedId);
        if (!note) {
          showToast('请先打开一篇笔记');
          return;
        }
        const templates = JSON.parse(localStorage.getItem('lexinote-templates') || '[]') as { title: string; content: string }[];
        templates.unshift({ title: displayTitle(note), content: note.content });
        localStorage.setItem('lexinote-templates', JSON.stringify(templates.slice(0, 24)));
        showToast('已保存为模板');
        return;
      }
      case 'split':
        if (!current.selectedId) return;
        setState((previous) => ({ ...previous, groupTabs: [previous.selectedId] }));
        return;
      case 'close-split':
        setState((previous) => ({ ...previous, groupTabs: [] }));
        return;
      case 'sidebar':
        patch({ sidebarOpen: !current.sidebarOpen });
        return;
      case 'close-tab':
        if (current.selectedId) closeTab(current.selectedId);
        return;
      case 'close-others':
        setState((previous) => ({ ...previous, tabs: previous.tabs.filter((tab) => tab === previous.selectedId) }));
        return;
      case 'close-all':
        setState((previous) => ({ ...previous, tabs: [], selectedId: '' }));
        return;
      case 'tab-prev':
      case 'tab-next': {
        if (current.tabs.length < 2) return;
        const index = current.tabs.indexOf(current.selectedId);
        const next =
          commandId === 'tab-next'
            ? (Math.max(0, index) + 1) % current.tabs.length
            : (Math.max(0, index) + current.tabs.length - 1) % current.tabs.length;
        openDocument(current.tabs[next]);
        return;
      }
      case 'map':
        createMap();
        return;
      case 'canvas':
        createCanvas();
        return;
      case 'convert':
        if (current.selectedId && !current.selectedId.includes(':')) createMap(current.selectedId);
        else showToast('请先打开一篇笔记');
        return;
      case 'graph':
        patch({ activeSection: 2, sidebarOpen: true });
        return;
      case 'library':
        patch({ activeSection: 4 });
        return;
      case 'workspaces':
        patch({ workspacesOpen: true });
        return;
      case 'trash':
        patch({ trashOpen: true });
        return;
      case 'light':
      case 'dark':
      case 'system':
        updateSettings({ theme: commandId as AppSettings['theme'] });
        return;
      case 'theme-picker':
        patch({ settingsOpen: true, settingsCategory: 'appearance' });
        return;
      case 'zoom-in':
        updateSettings({ zoom: Math.min(160, current.settings.zoom + 10) });
        return;
      case 'zoom-out':
        updateSettings({ zoom: Math.max(70, current.settings.zoom - 10) });
        return;
      case 'zoom-reset':
        updateSettings({ zoom: 100 });
        return;
      case 'font-increase':
        updateSettings({ fontSize: Math.min(26, current.settings.fontSize + 1) });
        return;
      case 'font-decrease':
        updateSettings({ fontSize: Math.max(12, current.settings.fontSize - 1) });
        return;
      case 'width-toggle':
        updateSettings({ editorLimitWidth: !current.settings.editorLimitWidth });
        return;
      case 'ribbon-toggle':
        updateSettings({ showRibbon: !current.settings.showRibbon });
        return;
      case 'reading':
        editorApi.current?.toggleReading();
        return;
      case 'source-toggle':
        editorApi.current?.toggleSource();
        return;
      case 'find':
        editorApi.current?.find(false);
        return;
      case 'replace':
        editorApi.current?.find(true);
        return;
      case 'focus-editor':
        editorApi.current?.focus();
        return;
      case 'outline':
        patch({ rightSidebarOpen: true, rightSidebarMode: 'outline' });
        return;
      case 'backlinks':
      case 'outgoing':
        patch({ rightSidebarOpen: true, rightSidebarMode: 'outline' });
        return;
      case 'properties':
        patch({ rightSidebarOpen: true, rightSidebarMode: 'properties' });
        return;
      case 'rename': {
        const note = noteById(current.selectedId);
        if (note) {
          patch({ settingsOpen: false });
          window.dispatchEvent(new CustomEvent('lexi:rename-title'));
        }
        return;
      }
      case 'duplicate':
        duplicateNote(current.selectedId);
        return;
      case 'copy-uri':
        if (window.lexi && current.selectedId) {
          await window.lexi.writeClipboard(`lexinote://open?noteId=${encodeURIComponent(current.selectedId)}`);
          showToast('已复制知萤 URI');
        }
        return;
      case 'copy-path':
        if (window.lexi && current.selectedId) {
          await window.lexi.writeClipboard(
            `${current.runtime?.dataPath ?? 'lexinote-data.json'}#${current.selectedId}`
          );
          showToast('已复制笔记位置');
        }
        return;
      case 'delete-file':
        if (current.selectedId && !current.selectedId.includes(':')) trashNote(current.selectedId);
        return;
      case 'move-file':
        showToast('可在左侧文件夹或工作区中整理笔记');
        return;
      case 'export-md':
        await exportVaultMarkdown();
        return;
      case 'backup':
        await exportWorkspaceZip();
        return;
      case 'import':
        await importFiles();
        return;
      case 'restore':
        await importWorkspaceZip();
        return;
      case 'export-pdf': {
        const note = noteById(current.selectedId);
        if (!note) {
          showToast('请先打开一篇笔记');
          return;
        }
        if (!window.lexi) return;
        const html = `<!doctype html><html><head><meta charset="utf-8"><title>${displayTitle(note)}</title>
<style>body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;max-width:760px;margin:48px auto;padding:0 24px;line-height:1.75;color:#1A1D24}h1{font-size:30px}h2{font-size:22px}pre{background:#F4F5F7;padding:12px;border-radius:8px;overflow:auto}blockquote{border-left:3px solid #6E44D9;margin:0;padding-left:14px;color:#535863}code{background:#F4F5F7;padding:2px 5px;border-radius:4px}</style>
</head><body><pre style="white-space:pre-wrap;background:none;padding:0">${note.content
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')}</pre></body></html>`;
        const target = await window.lexi.exportText(html, `${displayTitle(note).replace(/[\\/:*?"<>|]/g, '-')}.html`, [
          { name: 'HTML', extensions: ['html'] }
        ]);
        if (target) showToast('已导出可打印的 HTML，可在浏览器中另存为 PDF');
        return;
      }
      case 'back':
      case 'forward': {
        const next = current.navIndex + (commandId === 'back' ? -1 : 1);
        if (next >= 0 && next < current.navIds.length) {
          setState((previous) => ({ ...previous, navIndex: next, selectedId: previous.navIds[next] }));
        }
        return;
      }
      case 'settings':
        patch({ settingsOpen: true, settingsCategory: 'about' });
        return;
      case 'help':
        patch({ helpOpen: true });
        return;
      case 'about':
        patch({ settingsOpen: true, settingsCategory: 'about' });
        return;
      default:
        showToast(`命令「${commandId}」暂未在 Windows 版开放`);
    }
  }, [
    createCanvas,
    createMap,
    createNote,
    closeTab,
    duplicateNote,
    exportWorkspaceZip,
    exportNote,
    exportVaultMarkdown,
    importFiles,
    importWorkspaceZip,
    noteById,
    openDocument,
    openPalette,
    patch,
    saveNow,
    showToast,
    trashNote,
    updateNote,
    updateSettings
  ]);

  // Application shortcuts. Ctrl+Tab and Ctrl+W are handled here, not by the OS menu.
  useEffect(() => {
    const handler = (event: KeyboardEvent): void => {
      const mod = event.ctrlKey || event.metaKey;
      if (event.key === 'Escape') {
        if (stateRef.current.paletteOpen) patch({ paletteOpen: false });
        else if (stateRef.current.settingsOpen) patch({ settingsOpen: false });
        else if (stateRef.current.trashOpen) patch({ trashOpen: false });
        return;
      }
      if (!mod) return;
      const key = event.key.toLowerCase();
      if (key === 'p' && !event.shiftKey) {
        event.preventDefault();
        openPalette('commands');
      } else if (key === 'o') {
        event.preventDefault();
        openPalette('switcher');
      } else if (key === 's') {
        event.preventDefault();
        void saveNow();
      } else if (key === 'n' && event.shiftKey) {
        event.preventDefault();
        createNote('quick');
      } else if (key === 'n') {
        event.preventDefault();
        createNote('markdown');
      } else if (key === 'e') {
        event.preventDefault();
        editorApi.current?.toggleReading();
      } else if (key === 'w') {
        event.preventDefault();
        if (stateRef.current.selectedId) closeTab(stateRef.current.selectedId);
      } else if (key === 'tab') {
        event.preventDefault();
        void executeCommand(event.shiftKey ? 'tab-prev' : 'tab-next');
      } else if (key === 'f' && !event.shiftKey) {
        event.preventDefault();
        editorApi.current?.find(false);
      } else if (key === 'h') {
        event.preventDefault();
        editorApi.current?.find(true);
      } else if (key === '\\') {
        event.preventDefault();
        patch({ sidebarOpen: !stateRef.current.sidebarOpen });
      } else if (key === ',') {
        event.preventDefault();
        patch({ settingsOpen: true, settingsCategory: 'about' });
      } else if (key === '=' || key === '+') {
        event.preventDefault();
        updateSettings({ zoom: Math.min(160, stateRef.current.settings.zoom + 10) });
      } else if (key === '-') {
        event.preventDefault();
        updateSettings({ zoom: Math.max(70, stateRef.current.settings.zoom - 10) });
      } else if (key === '0') {
        event.preventDefault();
        updateSettings({ zoom: 100 });
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [closeTab, createNote, executeCommand, openPalette, patch, saveNow, updateSettings]);

  const links = useMemo(() => buildNoteLinks(state.notes), [state.notes]);
  const mentions = useMemo(() => findUnlinkedMentions(state.notes, links), [state.notes, links]);
  const activeVault = state.vaults.find((vault) => vault.id === state.activeVaultId);
  const activeProject = state.projects.find((project) => project.id === state.activeProjectId);
  const visibleNotes = useMemo(
    () =>
      state.notes.filter(
        (note) =>
          note.trashedAt === 0 &&
          note.vaultId === state.activeVaultId &&
          (!note.projectId || state.projects.some((project) => project.id === note.projectId)) &&
          (!state.activeProjectId || note.projectId === state.activeProjectId) &&
          (!state.favoritesOnly || note.favorite) &&
          matchesSearch(note, state.searchText)
      ),
    [state.notes, state.activeVaultId, state.activeProjectId, state.projects, state.favoritesOnly, state.searchText]
  );
  const folderNames = useMemo(() => {
    const names: string[] = [];
    for (const note of visibleNotes) {
      if (!state.activeProjectId && !state.searchText && note.projectId) continue;
      const name = note.notebook || '未分类';
      if (!names.includes(name)) names.push(name);
    }
    return names;
  }, [visibleNotes, state.activeProjectId, state.searchText]);

  const tabs = useMemo(
    () =>
      state.tabs.map((id) => {
        if (id.startsWith('map:')) {
          const map = state.maps.find((item) => item.id === id.substring(4));
          return { id, title: map?.title || '思维导图', kind: 'map' as const };
        }
        if (id.startsWith('canvas:')) {
          const board = state.canvases.find((item) => item.id === id.substring(7));
          return { id, title: board?.title || '白板', kind: 'canvas' as const };
        }
        const note = state.notes.find((item) => item.id === id);
        return { id, title: note ? displayTitle(note) : '无标题笔记', kind: 'note' as const };
      }),
    [state.tabs, state.notes, state.maps, state.canvases]
  );

  const tr = useCallback(
    (source: string, args: (string | number)[] = []): string => {
      let translated =
        state.settings.language === 'en' ? LEXI_ENGLISH[source] ?? UI_ENGLISH[source] ?? source : source;
      for (let index = 0; index < args.length; index++) {
        translated = translated.split(`{${index}}`).join(String(args[index]));
      }
      return translated;
    },
    [state.settings.language]
  );

  const actions: AppActions = {
    openDocument,
    closeTab,
    selectTab: openDocument,
    setSearchText: (text) => patch({ searchText: text }),
    setFavoritesOnly: (value) => patch({ favoritesOnly: value }),
    toggleFolder: (folder) =>
      patch((current) => ({
        closedFolders: current.closedFolders.includes(folder)
          ? current.closedFolders.filter((item) => item !== folder)
          : current.closedFolders.concat(folder)
      })),
    setSidebarOpen: (open) => patch({ sidebarOpen: open }),
    setRightSidebar: (open, mode) =>
      patch((current) => ({
        rightSidebarOpen: open,
        rightSidebarMode: mode ?? current.rightSidebarMode
      })),
    setRightSidebarMode: (mode) => patch({ rightSidebarMode: mode }),
    setSection: (section) => patch({ activeSection: section }),
    setActiveVault,
    requestWorkspace,
    confirmWorkspaceOpen,
    cancelWorkspaceOpen,
    setVaultOpenMode,
    setWorkspacePromptSuppressed,
    setWorkspaceDefaultOpenMode,
    setActiveProject: (projectId) => patch({ activeProjectId: projectId, searchText: '' }),
    createNote,
    updateNote,
    renameNote,
    toggleFavorite: (id) => toggleNoteFlag(id, 'favorite'),
    togglePin: (id) => toggleNoteFlag(id, 'pinned'),
    trashNote,
    restoreNote,
    deleteForever,
    emptyTrash,
    duplicateNote,
    createMap,
    updateMap,
    trashMap,
    deleteMapForever,
    createCanvas,
    updateCanvas,
    createVault,
    renameVault,
    createProject,
    renameProject,
    deleteProject,
    updateSettings,
    setEditorMode: (id, mode) => patch((current) => ({ editorModes: { ...current.editorModes, [id]: mode } })),
    openPalette,
    closePalette: () => patch({ paletteOpen: false }),
    openSettings: (category = 'about') => patch({ settingsOpen: true, settingsCategory: category }),
    closeSettings: () => patch({ settingsOpen: false }),
    setSettingsCategory: (category) => patch({ settingsCategory: category }),
    setTrashOpen: (open) => patch({ trashOpen: open }),
    setWorkspacesOpen: (open) => patch({ workspacesOpen: open }),
    setTemplatesOpen: (open) => patch({ templatesOpen: open }),
    setHelpOpen: (open) => patch({ helpOpen: open }),
    showToast,
    executeCommand,
    saveNow,
    exportVaultMarkdown,
    exportWorkspaceZip,
    importWorkspaceZip,
    exportSettingsPlugins,
    importSettingsPlugins,
    chooseWorkspaceFolder,
    rebuildIndex,
    importFiles,
    exportNote,
    registerEditor: (api) => {
      editorApi.current = api;
    },
    unregisterEditor: (api) => {
      if (editorApi.current === api) editorApi.current = null;
    },
    getEditorApi: () => editorApi.current,
    getLatestState: () => stateRef.current,
    ensureProjectSync,
    createVaultNoteSync,
    updateVaultNoteSync,
    trashVaultNoteSync,
    moveTab,
    closeOtherTabs: () =>
      setState((current) => ({ ...current, tabs: current.tabs.filter((tab) => tab === current.selectedId) })),
    closeAllTabs: () => setState((current) => ({ ...current, tabs: [], selectedId: '' }))
  };

  const selectedNote = state.notes.find((note) => note.id === state.selectedId);
  const currentMap = state.maps.find((map) => `map:${map.id}` === state.selectedId);
  const currentCanvas = state.canvases.find((board) => `canvas:${board.id}` === state.selectedId);

  const value: AppStore = {
    state,
    actions,
    derived: {
      activeVault,
      activeProject,
      visibleNotes,
      folderNames,
      currentNote: selectedNote,
      currentMap,
      currentCanvas,
      tabs,
      links,
      mentions,
      trashNotes: state.notes.filter((note) => note.trashedAt > 0),
      trashMaps: state.maps.filter((map) => map.trashedAt > 0),
      isDark,
      tr
    }
  };

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore(): AppStore {
  const store = useContext(StoreContext);
  if (!store) throw new Error('useStore must be used inside AppProvider');
  return store;
}
