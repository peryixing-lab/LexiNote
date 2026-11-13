import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState
} from 'react';
import type { NoteItem } from '../../shared/types';
import {
  ALL_PLUGIN_RPC_METHODS,
  capabilityOfRpcMethod,
  codeOfPluginError,
  isKnownRpcMethod,
  messageOfPluginError,
  PLUGIN_PROTOCOL_VERSION,
  PluginCapability,
  PluginErrorCode,
  PluginEventType,
  PluginLifecycleState,
  PluginLimits,
  PluginRpcMethod,
  raisePluginError,
  type PluginCatalogSnapshot,
  type PluginCommandEntry,
  type PluginConfirmRequest,
  type PluginEditorDraft,
  type PluginFileRef,
  type PluginInstallResult,
  type PluginNoticeItem,
  type PluginRecord,
  type PluginRibbonAction,
  type PluginRuntimeInfo,
  type PluginStatusBarItem,
  type PluginViewDeclaration,
  type PluginWorkspaceSnapshot
} from '../../shared/pluginTypes';
import { buildPalette, DEFAULT_ACCENT } from '../core/theme';
import { useStore } from '../store/AppStore';
import { buildMetadataSnapshot } from './LexiMetadataAdapter';
import {
  cleanFileSegment,
  folderOfRelativePath,
  LexiPathRegistry,
  nameOfRelativePath,
  normalizeMarkdownPath,
  utf8ByteLength
} from './LexiPathRegistry';

export const HARNESS_PLUGIN_ID = 'lexinote.harness';

export interface CapabilityDescriptor {
  id: string;
  label: string;
  risk: 'normal' | 'high';
  summary: string;
}

export const PLUGIN_CAPABILITY_META: Record<string, CapabilityDescriptor> = {
  [PluginCapability.VAULT_READ]: {
    id: PluginCapability.VAULT_READ,
    label: '读取笔记与目录',
    risk: 'normal',
    summary: '列出、检索并读取当前授权工作区内的 Markdown 笔记。'
  },
  [PluginCapability.VAULT_WRITE]: {
    id: PluginCapability.VAULT_WRITE,
    label: '创建与修改笔记',
    risk: 'high',
    summary: '新建、改写、重命名或将当前工作区中的笔记移入回收站。'
  },
  [PluginCapability.METADATA_READ]: {
    id: PluginCapability.METADATA_READ,
    label: '读取大纲与元数据',
    risk: 'normal',
    summary: '获取笔记标题大纲、双链、嵌入与属性标签索引。'
  },
  [PluginCapability.WORKSPACE_VIEWS]: {
    id: PluginCapability.WORKSPACE_VIEWS,
    label: '读取与切换工作区视图',
    risk: 'normal',
    summary: '查询当前打开的笔记标签并请求切换到指定笔记。'
  },
  [PluginCapability.EDITOR_READ]: {
    id: PluginCapability.EDITOR_READ,
    label: '读取当前编辑器内容',
    risk: 'normal',
    summary: '读取正在编辑的文档正文、选区位置与只读状态。'
  },
  [PluginCapability.EDITOR_WRITE]: {
    id: PluginCapability.EDITOR_WRITE,
    label: '改写当前编辑器内容',
    risk: 'high',
    summary: '替换选中文字或替换当前正在编辑的整篇文档正文。'
  },
  [PluginCapability.UI_COMMANDS]: {
    id: PluginCapability.UI_COMMANDS,
    label: '注册命令面板指令',
    risk: 'normal',
    summary: '向命令面板注册可执行动作。'
  },
  [PluginCapability.UI_VIEWS]: {
    id: PluginCapability.UI_VIEWS,
    label: '注册右侧边栏视图',
    risk: 'normal',
    summary: '在右侧边栏展示自定义沙箱界面。'
  },
  [PluginCapability.UI_NOTICE]: {
    id: PluginCapability.UI_NOTICE,
    label: '显示顶部通知',
    risk: 'normal',
    summary: '弹出简短提示条通知操作结果。'
  },
  [PluginCapability.UI_MODAL]: {
    id: PluginCapability.UI_MODAL,
    label: '请求确认弹窗',
    risk: 'normal',
    summary: '弹出宿主确认对话框并等待用户选择。'
  },
  [PluginCapability.PLUGIN_STORAGE]: {
    id: PluginCapability.PLUGIN_STORAGE,
    label: '插件本地存储',
    risk: 'normal',
    summary: '读写仅属于该插件与当前工作区的持久化键值数据。'
  },
  [PluginCapability.AI_INFERENCE]: {
    id: PluginCapability.AI_INFERENCE,
    label: '受控 AI 推理',
    risk: 'high',
    summary: '通过宿主托管凭证发起模型对话、拉取模型列表及余额查询（插件永不读取明文密钥）。'
  },
  [PluginCapability.NETWORK]: {
    id: PluginCapability.NETWORK,
    label: '直接网络访问',
    risk: 'high',
    summary: '首版沙箱已强制禁用直接出网能力。'
  }
};

export interface PluginHostContextValue {
  catalog: PluginCatalogSnapshot;
  enabledIds: string[];
  records: PluginRecord[];
  runtimeInfoById: Record<string, PluginRuntimeInfo>;
  commands: PluginCommandEntry[];
  viewsByPlugin: Record<string, PluginViewDeclaration[]>;
  ribbonActions: PluginRibbonAction[];
  statusBarItems: PluginStatusBarItem[];
  notices: PluginNoticeItem[];
  confirmRequest: PluginConfirmRequest | null;
  modalPluginId: string;
  refreshCatalog: () => Promise<void>;
  installZip: () => Promise<PluginInstallResult>;
  installFolder: () => Promise<PluginInstallResult>;
  uninstallPlugin: (pluginId: string, keepData?: boolean) => Promise<void>;
  enablePlugin: (pluginId: string) => Promise<void>;
  disablePlugin: (pluginId: string) => Promise<void>;
  retryPlugin: (pluginId: string) => Promise<void>;
  grantCapability: (pluginId: string, capability: string) => Promise<void>;
  revokeCapability: (pluginId: string, capability: string) => Promise<void>;
  grantAllCapabilities: (pluginId: string) => Promise<void>;
  revokeAllCapabilities: (pluginId: string) => Promise<void>;
  openPluginsFolder: () => Promise<void>;
  runCommand: (qualifiedId: string) => Promise<void>;
  triggerRibbon: (pluginId: string, ribbonId: string) => Promise<void>;
  presentPluginView: (pluginId: string, viewId?: string) => Promise<void>;
  dismissNotice: (noticeId: string) => void;
  resolveConfirm: (accepted: boolean) => void;
  registerSurfaceSlot: (pluginId: string, element: HTMLElement | null) => void;
}

const PluginHostContext = createContext<PluginHostContextValue | null>(null);

interface LiveSession {
  pluginId: string;
  vaultId: string;
  nonce: number;
  token: string;
  iframe: HTMLIFrameElement | null;
  port: MessagePort | null;
  portReady: boolean;
  booted: boolean;
  booting: boolean;
  disposed: boolean;
  subscriptions: Map<string, string>;
  eventSeq: number;
  hostReplyWaiters: Map<
    string,
    { resolve: (value: unknown) => void; reject: (reason?: unknown) => void; timer: number }
  >;
  pingTimers: number[];
  ribbonItems: PluginRibbonAction[];
  statusItems: PluginStatusBarItem[];
}

interface PendingConfirmItem {
  id: string;
  pluginId: string;
  title: string;
  body: string;
  resolve: (accepted: boolean) => void;
}

interface RpcEnvelope {
  protocol?: number;
  id?: string;
  pluginId?: string;
  token?: string;
  method?: string;
  params?: unknown;
}

function emptyRuntimeInfo(
  state: PluginRuntimeInfo['state'] = PluginLifecycleState.INSTALLED_DISABLED
): PluginRuntimeInfo {
  return {
    state,
    lastError: '',
    warnings: [],
    diagnostics: [],
    hasViews: false,
    presentRequested: false
  };
}

function randomToken(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `tok-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}

function parseJsonSafe(raw: unknown, fallback: Record<string, unknown> = {}): Record<string, unknown> {
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return raw as Record<string, unknown>;
  }
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (!trimmed) { return fallback; }
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      raisePluginError(PluginErrorCode.PROTOCOL, 'RPC params 不是合法 JSON 对象');
    }
  }
  return fallback;
}

function localCommandId(pluginId: string, rawId: string): string {
  const prefix = `${pluginId}:`;
  return rawId.startsWith(prefix) ? rawId.slice(prefix.length) : rawId;
}

function buildThemePayload(
  accent: string,
  isDark: boolean,
  paletteMode: 'original' | 'preset' | 'custom'
): {
  type: 'theme';
  colorScheme: 'dark' | 'light';
  vars: Record<string, string>;
} {
  const palette = buildPalette(accent || DEFAULT_ACCENT, isDark, paletteMode);
  return {
    type: 'theme',
    colorScheme: isDark ? 'dark' : 'light',
    vars: {
      '--text-normal': palette.text_primary,
      '--text-muted': palette.text_secondary,
      '--text-faint': palette.text_secondary,
      '--text-accent': palette.brand_ink,
      '--text-error': palette.error,
      '--background-primary': palette.workspace_page,
      '--background-secondary': palette.soft_surface,
      '--background-modifier-border': palette.divider,
      '--interactive-accent': palette.brand,
      '--interactive-normal': palette.soft_surface,
      '--brand': palette.brand,
      '--brand-soft': palette.brand_soft,
      '--brand-ink': palette.brand_ink,
      '--surface': palette.surface,
      '--soft-surface': palette.soft_surface,
      '--text-primary': palette.text_primary,
      '--text-secondary': palette.text_secondary,
      '--divider': palette.divider,
      '--background': palette.background
    }
  };
}

function noteSignature(note: NoteItem, logicalPath: string): string {
  return `${logicalPath}|${note.updatedAt}|${note.content.length}|${note.projectId}`;
}

export function PluginHostProvider({ children }: { children: React.ReactNode }): JSX.Element {
  const { state, actions, derived } = useStore();
  const [catalog, setCatalog] = useState<PluginCatalogSnapshot>({
    records: [],
    enabledByVault: {},
    pluginsDir: ''
  });
  const [runtimeInfoById, setRuntimeInfoById] = useState<Record<string, PluginRuntimeInfo>>({});
  const [commands, setCommands] = useState<PluginCommandEntry[]>([]);
  const [viewsByPlugin, setViewsByPlugin] = useState<Record<string, PluginViewDeclaration[]>>({});
  const [ribbonActions, setRibbonActions] = useState<PluginRibbonAction[]>([]);
  const [statusBarItems, setStatusBarItems] = useState<PluginStatusBarItem[]>([]);
  const [notices, setNotices] = useState<PluginNoticeItem[]>([]);
  const [confirmRequest, setConfirmRequest] = useState<PluginConfirmRequest | null>(null);
  const [modalPluginId, setModalPluginId] = useState('');
  const [reloadNonces, setReloadNonces] = useState<Record<string, number>>({});
  const [dockedSlot, setDockedSlot] = useState<{
    pluginId: string;
    rect: { top: number; left: number; width: number; height: number } | null;
  }>({ pluginId: '', rect: null });

  const catalogRef = useRef(catalog);
  catalogRef.current = catalog;
  const runtimeInfoRef = useRef(runtimeInfoById);
  runtimeInfoRef.current = runtimeInfoById;
  const stateRef = useRef(state);
  stateRef.current = state;
  const actionsRef = useRef(actions);
  actionsRef.current = actions;
  const derivedRef = useRef(derived);
  derivedRef.current = derived;
  const viewsRef = useRef(viewsByPlugin);
  viewsRef.current = viewsByPlugin;
  const modalPluginRef = useRef(modalPluginId);
  modalPluginRef.current = modalPluginId;

  const pathRegistryRef = useRef(new LexiPathRegistry());
  const pathDigestRef = useRef<Map<string, string>>(new Map());
  const sessionsRef = useRef<Map<string, LiveSession>>(new Map());
  const subCounterRef = useRef(0);
  const hostReqCounterRef = useRef(0);
  const pendingPresentRef = useRef<Map<string, string>>(new Map());
  const bootWaitersRef = useRef<Map<string, Array<(err?: string) => void>>>(new Map());
  const confirmQueueRef = useRef<PendingConfirmItem[]>([]);
  const activeConfirmRef = useRef<PendingConfirmItem | null>(null);
  const noticeTimersRef = useRef<Map<string, number>>(new Map());
  const surfaceSlotRef = useRef<{ pluginId: string; element: HTMLElement | null }>({
    pluginId: '',
    element: null
  });
  const watcherPrevNotesRef = useRef<Map<string, { path: string; sig: string; fileRef: PluginFileRef }>>(new Map());
  const watcherVaultRef = useRef('');
  const watcherActiveNoteRef = useRef('');
  const watcherLayoutRef = useRef('');
  const rpcSuppressedNoteSigsRef = useRef<Set<string>>(new Set());

  const enabledIds = useMemo(() => {
    const raw = catalog.enabledByVault[state.activeVaultId];
    return Array.isArray(raw) ? raw : [];
  }, [catalog.enabledByVault, state.activeVaultId]);

  const activeSessionEntries = useMemo(() => {
    const enabledSet = new Set(enabledIds);
    return catalog.records
      .filter((record) => enabledSet.has(record.id))
      .map((record) => ({
        record,
        vaultId: state.activeVaultId,
        nonce: reloadNonces[record.id] ?? 0
      }));
  }, [catalog.records, enabledIds, state.activeVaultId, reloadNonces]);

  const ensurePathRegistryFresh = useCallback((vaultId: string, force = false): LexiPathRegistry => {
    const latest = actionsRef.current.getLatestState();
    const relevantProjects = latest.projects.filter((project) => project.vaultId === vaultId);
    const relevantNotes = latest.notes.filter((note) => note.vaultId === vaultId && !note.trashedAt);
    const digest = `${relevantProjects.map((p) => `${p.id}:${p.name}`).join(';')}#${relevantNotes
      .map((n) => `${n.id}:${n.projectId}:${n.title}:${n.updatedAt}:${n.content.length}`)
      .join(';')}`;
    if (force || pathDigestRef.current.get(vaultId) !== digest) {
      pathRegistryRef.current.rebuild(vaultId, latest.projects, latest.notes);
      pathDigestRef.current.set(vaultId, digest);
    }
    return pathRegistryRef.current;
  }, []);

  const appendDiagnostic = useCallback((pluginId: string, level: string, message: string): void => {
    const entry = `${new Date().toISOString()} [${level}] ${message}`;
    setRuntimeInfoById((previous) => {
      const base = previous[pluginId] ?? emptyRuntimeInfo();
      const diagnostics = base.diagnostics.concat(entry).slice(-40);
      return { ...previous, [pluginId]: { ...base, diagnostics } };
    });
  }, []);

  const updateRuntimeInfo = useCallback(
    (pluginId: string, updater: (current: PluginRuntimeInfo) => PluginRuntimeInfo): void => {
      setRuntimeInfoById((previous) => {
        const base = previous[pluginId] ?? emptyRuntimeInfo();
        return { ...previous, [pluginId]: updater(base) };
      });
    },
    []
  );

  const settleBootWaiters = useCallback((pluginId: string, errorMessage?: string): void => {
    const list = bootWaitersRef.current.get(pluginId);
    if (!list || list.length === 0) { return; }
    bootWaitersRef.current.delete(pluginId);
    for (const resolve of list) {
      resolve(errorMessage);
    }
  }, []);

  const syncAggregatedUiHooks = useCallback((): void => {
    const ribbons: PluginRibbonAction[] = [];
    const statuses: PluginStatusBarItem[] = [];
    for (const session of sessionsRef.current.values()) {
      if (!session.disposed) {
        ribbons.push(...session.ribbonItems);
        statuses.push(...session.statusItems);
      }
    }
    setRibbonActions(ribbons);
    setStatusBarItems(statuses);
  }, []);

  const clearPluginContributions = useCallback(
    (pluginId: string): void => {
      setCommands((previous) => previous.filter((item) => item.pluginId !== pluginId));
      setViewsByPlugin((previous) => {
        if (!(pluginId in previous)) { return previous; }
        const next = { ...previous };
        delete next[pluginId];
        return next;
      });
      if (modalPluginRef.current === pluginId) {
        setModalPluginId('');
      }
      pendingPresentRef.current.delete(pluginId);
      syncAggregatedUiHooks();
    },
    [syncAggregatedUiHooks]
  );

  const publishEvent = useCallback(
    (eventType: string, vaultId: string, detail: Record<string, unknown>): void => {
      for (const session of sessionsRef.current.values()) {
        if (session.disposed || !session.booted || !session.port || session.vaultId !== vaultId) {
          continue;
        }
        const subscribed = Array.from(session.subscriptions.values()).includes(eventType);
        if (!subscribed) { continue; }
        session.eventSeq += 1;
        const envelope = JSON.stringify({
          protocol: PLUGIN_PROTOCOL_VERSION,
          type: 'event',
          pluginId: session.pluginId,
          event: eventType,
          seq: session.eventSeq,
          payload: JSON.stringify({ ...detail, vaultId, at: Date.now() })
        });
        try {
          session.port.postMessage({ type: 'event', payload: envelope });
        } catch {
          // Ignore closed port during teardown.
        }
      }
    },
    []
  );

  const sendPortCommand = useCallback(
    (session: LiveSession, message: Record<string, unknown>, timeoutMs = 15000): Promise<unknown> => {
      if (!session.port || !session.portReady || session.disposed) {
        return Promise.reject(raisePluginError(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件运行时未就绪'));
      }
      hostReqCounterRef.current += 1;
      const reqId = `host-${hostReqCounterRef.current}`;
      return new Promise<unknown>((resolve, reject) => {
        const timer = window.setTimeout(() => {
          session.hostReplyWaiters.delete(reqId);
          reject(raisePluginError(PluginErrorCode.TIMEOUT, `${String(message.type)} 超时`));
        }, timeoutMs);
        session.hostReplyWaiters.set(reqId, { resolve, reject, timer });
        try {
          session.port?.postMessage({ ...message, id: reqId });
        } catch (error) {
          window.clearTimeout(timer);
          session.hostReplyWaiters.delete(reqId);
          reject(error);
        }
      });
    },
    []
  );

  const dismissNotice = useCallback((noticeId: string): void => {
    const timer = noticeTimersRef.current.get(noticeId);
    if (timer !== undefined) {
      window.clearTimeout(timer);
      noticeTimersRef.current.delete(noticeId);
    }
    setNotices((previous) => previous.filter((item) => item.id !== noticeId));
  }, []);

  const pushNotice = useCallback(
    (pluginId: string, message: string, timeoutMs = 3500): void => {
      const clampedTimeout = Math.max(1000, Math.min(10000, Number.isFinite(timeoutMs) ? timeoutMs : 3500));
      const id = `notice-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
      const item: PluginNoticeItem = {
        id,
        pluginId,
        message,
        at: Date.now(),
        timeoutMs: clampedTimeout
      };
      setNotices((previous) => previous.slice(-3).concat(item));
      const timer = window.setTimeout(() => dismissNotice(id), clampedTimeout);
      noticeTimersRef.current.set(id, timer);
    },
    [dismissNotice]
  );

  const advanceConfirmQueue = useCallback((): void => {
    if (activeConfirmRef.current || confirmQueueRef.current.length === 0) { return; }
    const next = confirmQueueRef.current.shift()!;
    activeConfirmRef.current = next;
    setConfirmRequest({
      id: next.id,
      pluginId: next.pluginId,
      title: next.title,
      body: next.body,
      resolve: next.resolve
    });
  }, []);

  const resolveConfirm = useCallback(
    (accepted: boolean): void => {
      const active = activeConfirmRef.current;
      if (!active) { return; }
      activeConfirmRef.current = null;
      setConfirmRequest(null);
      active.resolve(accepted);
      advanceConfirmQueue();
    },
    [advanceConfirmQueue]
  );

  const enqueueConfirm = useCallback(
    (pluginId: string, title: string, body: string): Promise<boolean> => {
      return new Promise<boolean>((resolve) => {
        confirmQueueRef.current.push({
          id: `confirm-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
          pluginId,
          title,
          body,
          resolve
        });
        advanceConfirmQueue();
      });
    },
    [advanceConfirmQueue]
  );

  const resolveVault = useCallback(
    (record: PluginRecord, requestedVaultId: string, sessionVaultId: string): string => {
      const vaultId = requestedVaultId || sessionVaultId;
      if (!vaultId) {
        raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '缺少知识库标识');
      }
      if (record.vaultScopes.length > 0 && !record.vaultScopes.includes(vaultId)) {
        raisePluginError(PluginErrorCode.VAULT_FORBIDDEN, '该知识库不在插件授权范围内');
      }
      const latest = actionsRef.current.getLatestState();
      const exists = latest.vaults.some((vault) => vault.id === vaultId);
      if (!exists) {
        raisePluginError(PluginErrorCode.VAULT_FORBIDDEN, '知识库不存在或未授权');
      }
      return vaultId;
    },
    []
  );

  const getAuthorizedNote = useCallback((vaultId: string, noteId: string): NoteItem => {
    if (typeof noteId !== 'string' || !noteId) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '缺少文件标识');
    }
    const latest = actionsRef.current.getLatestState();
    const note = latest.notes.find((item) => item.id === noteId);
    if (!note || note.vaultId !== vaultId) {
      raisePluginError(PluginErrorCode.NOT_FOUND, '文件不存在或不属于当前知识库');
    }
    if (note.trashedAt > 0) {
      raisePluginError(PluginErrorCode.NOT_FOUND, '文件已移入回收站');
    }
    return note;
  }, []);

  const buildWorkspaceSnapshot = useCallback((vaultId: string): PluginWorkspaceSnapshot => {
    const latest = actionsRef.current.getLatestState();
    const registry = ensurePathRegistryFresh(vaultId);
    const activeNote =
      latest.selectedId && !latest.selectedId.includes(':')
        ? latest.notes.find((note) => note.id === latest.selectedId && note.vaultId === vaultId && !note.trashedAt)
        : undefined;
    const editorDraft = actionsRef.current.getEditorApi()?.getDraft?.() ?? null;
    const openFileIds = latest.tabs.filter((tabId) => {
      if (tabId.includes(':')) { return false; }
      const note = latest.notes.find((item) => item.id === tabId && item.vaultId === vaultId && !item.trashedAt);
      return Boolean(note);
    });
    return {
      windowId: 'main',
      vaultId,
      activeFileId: editorDraft?.noteId || activeNote?.id || '',
      activeEditorId: editorDraft?.editorId || '',
      openFileIds,
      revision: registry.revisionOf(vaultId)
    };
  }, [ensurePathRegistryFresh]);

  const dispatchVaultRpc = useCallback(
    async (
      session: LiveSession,
      record: PluginRecord,
      method: string,
      params: Record<string, unknown>
    ): Promise<unknown> => {
      const requestedVaultId = typeof params.vaultId === 'string' ? params.vaultId : '';
      const vaultId = resolveVault(record, requestedVaultId, session.vaultId);
      const registry = ensurePathRegistryFresh(vaultId);

      if (method === PluginRpcMethod.VAULT_LIST) {
        return registry
          .entriesForVault(vaultId)
          .slice(0, PluginLimits.MAX_LIST_RESULT)
          .map((entry) => registry.toFileRef(entry));
      }

      if (method === PluginRpcMethod.VAULT_GET_BY_PATH) {
        const rel = normalizeMarkdownPath(String(params.path ?? ''));
        const noteId = registry.noteIdForPath(vaultId, rel);
        if (!noteId) { return null; }
        const latest = actionsRef.current.getLatestState();
        const note = latest.notes.find((n) => n.id === noteId && n.vaultId === vaultId && !n.trashedAt);
        const entry = note ? registry.entryByNoteId(vaultId, note.id) : undefined;
        return entry ? registry.toFileRef(entry) : null;
      }

      if (method === PluginRpcMethod.VAULT_GET_BY_ID) {
        const fileId = String(params.fileId ?? params.id ?? '');
        const note = getAuthorizedNote(vaultId, fileId);
        const refreshed = ensurePathRegistryFresh(vaultId);
        const entry = refreshed.entryByNoteId(vaultId, note.id);
        return entry ? refreshed.toFileRef(entry) : null;
      }

      if (method === PluginRpcMethod.VAULT_READ) {
        const fileId = String(params.fileId ?? params.id ?? '');
        const note = getAuthorizedNote(vaultId, fileId);
        return note.content;
      }

      if (method === PluginRpcMethod.VAULT_CREATE) {
        const rel = normalizeMarkdownPath(String(params.path ?? ''));
        if (typeof params.content !== 'string' && params.content !== undefined) {
          raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '正文必须是字符串');
        }
        const content = typeof params.content === 'string' ? params.content : '';
        if (utf8ByteLength(content) > PluginLimits.MAX_RESULT_BYTES) {
          raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, '笔记体积超过 2MB 上限');
        }
        if (registry.noteIdForPath(vaultId, rel) !== '') {
          raisePluginError(PluginErrorCode.PATH_EXISTS, `文件已存在：${rel}`);
        }
        const folder = folderOfRelativePath(rel);
        let projectId = '';
        if (folder) {
          if (folder.includes('/')) {
            raisePluginError(PluginErrorCode.INVALID_PATH, '首版只支持一级项目文件夹');
          }
          const latest = actionsRef.current.getLatestState();
          const lowerFolder = folder.toLowerCase();
          const matched = latest.projects.find(
            (proj) =>
              proj.vaultId === vaultId &&
              (proj.name === folder || cleanFileSegment(proj.name || '', '未分组').toLowerCase() === lowerFolder)
          );
          const resolvedProject = matched ?? actionsRef.current.ensureProjectSync(vaultId, folder);
          projectId = resolvedProject ? resolvedProject.id : '';
        }
        const title = nameOfRelativePath(rel).replace(/\.md$/i, '');
        const created = actionsRef.current.createVaultNoteSync({
          vaultId,
          projectId,
          title,
          content
        });
        const rebuilt = ensurePathRegistryFresh(vaultId, true);
        let entry = rebuilt.entryByNoteId(vaultId, created.id);
        if (entry && entry.logicalPath.toLowerCase() !== rel.toLowerCase()) {
          rebuilt.rememberAlias(vaultId, rel, created.id);
          entry = rebuilt.entryByNoteId(vaultId, created.id);
        }
        if (!entry) {
          raisePluginError(PluginErrorCode.IO, '创建笔记后建立路径索引失败');
        }
        const ref = rebuilt.toFileRef(entry);
        rpcSuppressedNoteSigsRef.current.add(noteSignature(created, ref.path));
        publishEvent(PluginEventType.VAULT_CREATED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath: '',
          projectId: ref.projectId,
          revision: rebuilt.revisionOf(vaultId)
        });
        publishEvent(PluginEventType.METADATA_RESOLVED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath: '',
          revision: rebuilt.revisionOf(vaultId)
        });
        return ref;
      }

      if (method === PluginRpcMethod.VAULT_WRITE) {
        const fileId = String(params.fileId ?? params.id ?? '');
        if (typeof params.content !== 'string') {
          raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '正文必须是字符串');
        }
        if (utf8ByteLength(params.content) > PluginLimits.MAX_RESULT_BYTES) {
          raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, '笔记体积超过 2MB 上限');
        }
        const latestNote = getAuthorizedNote(vaultId, fileId);
        const expectedUpdatedAt =
          typeof params.expectedUpdatedAt === 'number' && Number.isFinite(params.expectedUpdatedAt)
            ? params.expectedUpdatedAt
            : 0;
        if (expectedUpdatedAt > 0 && latestNote.updatedAt !== expectedUpdatedAt) {
          raisePluginError(PluginErrorCode.CONFLICT, '文件已被修改，请重新读取后再写入');
        }
        const updated = actionsRef.current.updateVaultNoteSync(fileId, { content: params.content });
        if (!updated) {
          raisePluginError(PluginErrorCode.NOT_FOUND, '文件不存在');
        }
        const rebuilt = ensurePathRegistryFresh(vaultId, true);
        const entry = rebuilt.entryByNoteId(vaultId, updated.id);
        if (!entry) {
          raisePluginError(PluginErrorCode.NOT_FOUND, '路径索引丢失');
        }
        const ref = rebuilt.toFileRef(entry);
        rpcSuppressedNoteSigsRef.current.add(noteSignature(updated, ref.path));
        publishEvent(PluginEventType.VAULT_MODIFIED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath: '',
          projectId: ref.projectId,
          revision: rebuilt.revisionOf(vaultId)
        });
        publishEvent(PluginEventType.METADATA_RESOLVED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath: '',
          revision: rebuilt.revisionOf(vaultId)
        });
        return ref;
      }

      if (method === PluginRpcMethod.VAULT_RENAME) {
        const fileId = String(params.fileId ?? params.id ?? '');
        getAuthorizedNote(vaultId, fileId);
        const target = normalizeMarkdownPath(String(params.newPath ?? ''));
        const beforeEntry = registry.entryByNoteId(vaultId, fileId);
        const oldPath = beforeEntry ? beforeEntry.logicalPath : '';
        const currentFolder = beforeEntry ? folderOfRelativePath(beforeEntry.logicalPath) : '';
        const nextFolder = folderOfRelativePath(target);
        if (currentFolder.toLowerCase() !== nextFolder.toLowerCase()) {
          raisePluginError(PluginErrorCode.UNSUPPORTED_API, '首版不支持插件跨文件夹移动文件');
        }
        const owner = registry.noteIdForPath(vaultId, target);
        if (owner && owner !== fileId) {
          raisePluginError(PluginErrorCode.PATH_EXISTS, `目标路径已存在：${target}`);
        }
        const nextTitle = nameOfRelativePath(target).replace(/\.md$/i, '');
        const updated = actionsRef.current.updateVaultNoteSync(fileId, { title: nextTitle });
        if (!updated) {
          raisePluginError(PluginErrorCode.NOT_FOUND, '文件不存在');
        }
        const rebuilt = ensurePathRegistryFresh(vaultId, true);
        const afterEntry = rebuilt.entryByNoteId(vaultId, fileId);
        if (!afterEntry) {
          raisePluginError(PluginErrorCode.IO, '重命名后路径索引缺失');
        }
        const ref = rebuilt.toFileRef(afterEntry);
        rpcSuppressedNoteSigsRef.current.add(noteSignature(updated, ref.path));
        publishEvent(PluginEventType.VAULT_RENAMED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath,
          projectId: ref.projectId,
          revision: rebuilt.revisionOf(vaultId)
        });
        publishEvent(PluginEventType.METADATA_RESOLVED, vaultId, {
          fileId: ref.id,
          path: ref.path,
          oldPath: '',
          revision: rebuilt.revisionOf(vaultId)
        });
        return ref;
      }

      if (method === PluginRpcMethod.VAULT_DELETE) {
        const fileId = String(params.fileId ?? params.id ?? '');
        getAuthorizedNote(vaultId, fileId);
        const beforeEntry = registry.entryByNoteId(vaultId, fileId);
        const ok = actionsRef.current.trashVaultNoteSync(fileId);
        if (!ok) {
          raisePluginError(PluginErrorCode.NOT_FOUND, '文件不存在');
        }
        const rebuilt = ensurePathRegistryFresh(vaultId, true);
        if (beforeEntry) {
          publishEvent(PluginEventType.VAULT_DELETED, vaultId, {
            fileId: beforeEntry.noteId,
            path: beforeEntry.logicalPath,
            oldPath: '',
            projectId: beforeEntry.projectId,
            revision: rebuilt.revisionOf(vaultId)
          });
        }
        return null;
      }

      raisePluginError(PluginErrorCode.UNSUPPORTED_API, method);
    },
    [ensurePathRegistryFresh, getAuthorizedNote, publishEvent, resolveVault]
  );

  const dispatchEditorRpc = useCallback(
    (session: LiveSession, method: string, params: Record<string, unknown>): unknown => {
      const api = actionsRef.current.getEditorApi();
      const draft: PluginEditorDraft | null = api?.getDraft?.() ?? null;
      if (method === PluginRpcMethod.EDITOR_ACTIVE) {
        if (!draft || draft.vaultId !== session.vaultId || draft.readOnly) {
          return null;
        }
        return draft;
      }
      if (!api || !draft || draft.vaultId !== session.vaultId) {
        raisePluginError(PluginErrorCode.EDITOR_READONLY, '当前没有活动编辑器');
      }
      if (draft.readOnly) {
        raisePluginError(PluginErrorCode.EDITOR_READONLY, '编辑器处于只读状态');
      }
      const text = typeof params.text === 'string' ? params.text : '';
      if (utf8ByteLength(text) > PluginLimits.MAX_RESULT_BYTES) {
        raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, '写入内容超过上限');
      }
      if (method === PluginRpcMethod.EDITOR_REPLACE_SELECTION) {
        const nextDraft = api.replaceSelectionText?.(text) ?? null;
        if (!nextDraft) {
          raisePluginError(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
        }
        return { content: nextDraft.content, version: nextDraft.revision };
      }
      if (method === PluginRpcMethod.EDITOR_REPLACE_ALL) {
        const expectedVersion =
          typeof params.expectedVersion === 'number' && Number.isFinite(params.expectedVersion)
            ? params.expectedVersion
            : 0;
        const outcome = api.replaceAllText?.(text, expectedVersion);
        if (!outcome) {
          raisePluginError(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
        }
        if (outcome.conflict) {
          raisePluginError(PluginErrorCode.CONFLICT, '编辑器内容已变化，请重新读取');
        }
        if (!outcome.ok || !outcome.draft) {
          raisePluginError(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
        }
        return { content: outcome.draft.content, version: outcome.draft.revision };
      }
      raisePluginError(PluginErrorCode.UNSUPPORTED_API, method);
    },
    []
  );

  const dispatchWorkspaceRpc = useCallback(
    (session: LiveSession, record: PluginRecord, method: string, params: Record<string, unknown>): unknown => {
      if (method === PluginRpcMethod.WORKSPACE_SNAPSHOT) {
        return buildWorkspaceSnapshot(session.vaultId);
      }
      if (method === PluginRpcMethod.WORKSPACE_ACTIVE_FILE) {
        const editorDraft = actionsRef.current.getEditorApi()?.getDraft?.() ?? null;
        if (editorDraft && editorDraft.noteId && editorDraft.vaultId === session.vaultId) {
          const registry = ensurePathRegistryFresh(session.vaultId);
          const entry = registry.entryByNoteId(session.vaultId, editorDraft.noteId);
          if (entry) { return registry.toFileRef(entry); }
        }
        const snap = buildWorkspaceSnapshot(session.vaultId);
        if (!snap.activeFileId) { return null; }
        const registry = ensurePathRegistryFresh(session.vaultId);
        const entry = registry.entryByNoteId(session.vaultId, snap.activeFileId);
        return entry ? registry.toFileRef(entry) : null;
      }
      if (method === PluginRpcMethod.WORKSPACE_OPEN_FILE) {
        const requestedVaultId = typeof params.vaultId === 'string' ? params.vaultId : '';
        const vaultId = resolveVault(record, requestedVaultId, session.vaultId);
        const fileId = String(params.fileId ?? params.id ?? '');
        getAuthorizedNote(vaultId, fileId);
        actionsRef.current.openDocument(fileId);
        return null;
      }
      raisePluginError(PluginErrorCode.UNSUPPORTED_API, method);
    },
    [buildWorkspaceSnapshot, ensurePathRegistryFresh, getAuthorizedNote, resolveVault]
  );

  const presentPluginView = useCallback(
    async (pluginId: string, viewId = ''): Promise<void> => {
      const session = sessionsRef.current.get(pluginId);
      if (!session || session.disposed) { return; }
      if (!session.booted) {
        pendingPresentRef.current.set(pluginId, viewId);
        return;
      }
      try {
        await sendPortCommand(session, { type: 'present', viewId });
      } catch (error) {
        appendDiagnostic(pluginId, 'error', `呈现视图失败：${messageOfPluginError(error)}`);
      }
    },
    [appendDiagnostic, sendPortCommand]
  );

  const runCommand = useCallback(
    async (qualifiedId: string): Promise<void> => {
      const colon = qualifiedId.indexOf(':');
      if (colon <= 0) { return; }
      const pluginId = qualifiedId.slice(0, colon);
      const session = sessionsRef.current.get(pluginId);
      if (!session || !session.booted || session.disposed) {
        actionsRef.current.showToast('插件当前未激活');
        return;
      }
      try {
        await sendPortCommand(session, { type: 'runCommand', qualifiedId });
      } catch (error) {
        const msg = messageOfPluginError(error);
        appendDiagnostic(pluginId, 'error', `执行命令 ${qualifiedId} 失败：${msg}`);
        actionsRef.current.showToast(msg || '插件命令执行失败');
      }
    },
    [appendDiagnostic, sendPortCommand]
  );

  const triggerRibbon = useCallback(
    async (pluginId: string, ribbonId: string): Promise<void> => {
      const session = sessionsRef.current.get(pluginId);
      if (!session || !session.booted || session.disposed) { return; }
      try {
        await sendPortCommand(session, { type: 'triggerRibbon', ribbonId });
      } catch (error) {
        appendDiagnostic(pluginId, 'error', `功能区按钮执行失败：${messageOfPluginError(error)}`);
      }
    },
    [appendDiagnostic, sendPortCommand]
  );

  const handleRpcRequest = useCallback(
    async (session: LiveSession, rawPayload: unknown): Promise<void> => {
      const respond = (id: string, ok: boolean, resultOrError: unknown): void => {
        if (!session.port || session.disposed) { return; }
        const packet = ok
          ? {
              protocol: PLUGIN_PROTOCOL_VERSION,
              id,
              ok: true,
              result: JSON.stringify(resultOrError === undefined ? null : resultOrError)
            }
          : {
              protocol: PLUGIN_PROTOCOL_VERSION,
              id,
              ok: false,
              error: resultOrError
            };
        try {
          session.port.postMessage({ type: 'response', payload: JSON.stringify(packet) });
        } catch {
          // Ignore closed port.
        }
      };

      let req: RpcEnvelope;
      try {
        req = (typeof rawPayload === 'string' ? JSON.parse(rawPayload) : rawPayload) as RpcEnvelope;
      } catch {
        return;
      }
      if (!req || typeof req !== 'object' || typeof req.id !== 'string' || !req.id) { return; }
      const reqId = req.id;

      try {
        if (req.protocol !== PLUGIN_PROTOCOL_VERSION) {
          raisePluginError(PluginErrorCode.PROTOCOL, '不支持的协议版本');
        }
        if (req.pluginId !== session.pluginId || req.token !== session.token) {
          raisePluginError(PluginErrorCode.PERMISSION_DENIED, '会话令牌或插件标识不匹配');
        }
        const record = catalogRef.current.records.find((item) => item.id === session.pluginId);
        if (!record || session.disposed) {
          raisePluginError(PluginErrorCode.PLUGIN_DISABLED, '插件已停用或卸载');
        }
        const method = typeof req.method === 'string' ? req.method : '';
        if (!isKnownRpcMethod(method)) {
          raisePluginError(PluginErrorCode.UNSUPPORTED_API, `不支持的 API：${method}`);
        }
        const requiredCapability = capabilityOfRpcMethod(method);
        if (requiredCapability) {
          if (!record.requestedCapabilities.includes(requiredCapability)) {
            raisePluginError(PluginErrorCode.PERMISSION_DENIED, `插件清单未声明能力 ${requiredCapability}`);
          }
          if (!record.grantedCapabilities.includes(requiredCapability)) {
            raisePluginError(PluginErrorCode.PERMISSION_DENIED, `插件缺少权限 ${requiredCapability}`);
          }
        }

        const params = parseJsonSafe(req.params, {});

        if (method === PluginRpcMethod.PING) {
          respond(reqId, true, { ok: true, pluginId: session.pluginId });
          return;
        }
        if (method.startsWith('vault.')) {
          respond(reqId, true, await dispatchVaultRpc(session, record, method, params));
          return;
        }
        if (method === PluginRpcMethod.METADATA_GET) {
          const requestedVaultId = typeof params.vaultId === 'string' ? params.vaultId : '';
          const vaultId = resolveVault(record, requestedVaultId, session.vaultId);
          const fileId = String(params.fileId ?? params.id ?? '');
          const note = getAuthorizedNote(vaultId, fileId);
          const registry = ensurePathRegistryFresh(vaultId);
          const entry = registry.entryByNoteId(vaultId, note.id);
          const logicalPath = entry ? entry.logicalPath : '';
          respond(reqId, true, buildMetadataSnapshot(note, logicalPath, registry.revisionOf(vaultId)));
          return;
        }
        if (method.startsWith('workspace.')) {
          respond(reqId, true, dispatchWorkspaceRpc(session, record, method, params));
          return;
        }
        if (method.startsWith('editor.')) {
          respond(reqId, true, dispatchEditorRpc(session, method, params));
          return;
        }
        if (method === PluginRpcMethod.COMMANDS_REGISTER) {
          const localId = localCommandId(session.pluginId, String(params.id ?? ''));
          if (!/^[a-z0-9][a-z0-9._-]{0,63}$/.test(localId)) {
            raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '命令 id 格式非法');
          }
          const qualifiedId = `${session.pluginId}:${localId}`;
          const title = (typeof params.title === 'string' ? params.title.trim() : '') || localId;
          setCommands((previous) => {
            const pluginCount = previous.filter((c) => c.pluginId === session.pluginId).length;
            const exists = previous.some((c) => c.qualifiedId === qualifiedId);
            if (!exists && pluginCount >= PluginLimits.MAX_COMMANDS_PER_PLUGIN) {
              return previous;
            }
            const nextEntry: PluginCommandEntry = {
              pluginId: session.pluginId,
              localId,
              qualifiedId,
              title: title.slice(0, 80),
              available: true
            };
            return exists
              ? previous.map((c) => (c.qualifiedId === qualifiedId ? nextEntry : c))
              : previous.concat(nextEntry);
          });
          respond(reqId, true, { id: qualifiedId });
          return;
        }
        if (method === PluginRpcMethod.COMMANDS_UNREGISTER) {
          const localId = localCommandId(session.pluginId, String(params.id ?? ''));
          const qualifiedId = `${session.pluginId}:${localId}`;
          setCommands((previous) => previous.filter((c) => c.qualifiedId !== qualifiedId));
          respond(reqId, true, null);
          return;
        }
        if (method === PluginRpcMethod.EVENTS_ON) {
          const eventName = typeof params.event === 'string' ? params.event : '';
          if (!(Object.values(PluginEventType) as string[]).includes(eventName)) {
            raisePluginError(PluginErrorCode.INVALID_ARGUMENT, `未知事件 ${eventName}`);
          }
          if (session.subscriptions.size >= PluginLimits.MAX_SUBSCRIPTIONS_PER_PLUGIN) {
            raisePluginError(PluginErrorCode.RATE_LIMITED, '事件订阅数已达上限');
          }
          subCounterRef.current += 1;
          const subscriptionId = `sub-${subCounterRef.current}`;
          session.subscriptions.set(subscriptionId, eventName);
          respond(reqId, true, { subscriptionId });
          return;
        }
        if (method === PluginRpcMethod.EVENTS_OFF) {
          const subscriptionId = String(params.subscriptionId ?? '');
          session.subscriptions.delete(subscriptionId);
          respond(reqId, true, null);
          return;
        }
        if (method.startsWith('storage.')) {
          const bridge = window.lexi?.plugins;
          if (!bridge) {
            raisePluginError(PluginErrorCode.RUNTIME_UNAVAILABLE, '宿主存储桥接不可用');
          }
          const key = String(params.key ?? '');
          if (method === PluginRpcMethod.STORAGE_GET) {
            respond(reqId, true, await bridge.storageGet(session.pluginId, session.vaultId, key));
            return;
          }
          if (method === PluginRpcMethod.STORAGE_SET) {
            const val = typeof params.value === 'string' ? params.value : JSON.stringify(params.value ?? null);
            await bridge.storageSet(session.pluginId, session.vaultId, key, val);
            respond(reqId, true, null);
            return;
          }
          await bridge.storageRemove(session.pluginId, session.vaultId, key);
          respond(reqId, true, null);
          return;
        }
        if (method === PluginRpcMethod.UI_NOTICE) {
          const message = typeof params.message === 'string' ? params.message.trim() : '';
          if (!message) {
            raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '通知内容为空');
          }
          const timeoutMs = typeof params.timeoutMs === 'number' ? params.timeoutMs : 3500;
          pushNotice(session.pluginId, message.slice(0, 400), timeoutMs);
          respond(reqId, true, null);
          return;
        }
        if (method === PluginRpcMethod.UI_CONFIRM) {
          const title = typeof params.title === 'string' && params.title.trim() ? params.title.trim() : '确认';
          const body = typeof params.body === 'string' ? params.body : '';
          const accepted = await enqueueConfirm(session.pluginId, title.slice(0, 120), body.slice(0, 1000));
          respond(reqId, true, accepted);
          return;
        }
        if (method.startsWith('ai.')) {
          const bridge = window.lexi?.plugins;
          if (!bridge) {
            raisePluginError(PluginErrorCode.RUNTIME_UNAVAILABLE, '宿主 AI 桥接不可用');
          }
          if (method === PluginRpcMethod.AI_STATUS) {
            respond(reqId, true, await bridge.aiStatus(session.pluginId));
            return;
          }
          if (method === PluginRpcMethod.AI_CONFIGURE) {
            respond(reqId, true, await bridge.aiConfigure(session.pluginId, params));
            return;
          }
          if (method === PluginRpcMethod.AI_MODELS) {
            respond(reqId, true, await bridge.aiModels(session.pluginId));
            return;
          }
          if (method === PluginRpcMethod.AI_BALANCE) {
            respond(reqId, true, await bridge.aiBalance(session.pluginId));
            return;
          }
          if (method === PluginRpcMethod.AI_CHAT) {
            respond(reqId, true, await bridge.aiChat(session.pluginId, params));
            return;
          }
        }
        if (method === PluginRpcMethod.VIEWS_REGISTER) {
          const id = String(params.id ?? '').trim();
          const title = (typeof params.title === 'string' ? params.title.trim() : '') || id;
          if (!/^[a-z0-9][a-z0-9._-]{0,63}$/.test(id)) {
            raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '视图 id 格式非法');
          }
          setViewsByPlugin((previous) => {
            const list = previous[session.pluginId] ?? [];
            const nextItem: PluginViewDeclaration = {
              pluginId: session.pluginId,
              id,
              title: title.slice(0, 64),
              createdAt: Date.now()
            };
            const filtered = list.filter((item) => item.id !== id);
            return { ...previous, [session.pluginId]: filtered.concat(nextItem) };
          });
          updateRuntimeInfo(session.pluginId, (info) => ({ ...info, hasViews: true }));
          respond(reqId, true, { id, title });
          return;
        }
        if (method === PluginRpcMethod.VIEWS_UNREGISTER) {
          const id = String(params.id ?? '').trim();
          setViewsByPlugin((previous) => {
            const list = (previous[session.pluginId] ?? []).filter((item) => item.id !== id);
            return { ...previous, [session.pluginId]: list };
          });
          respond(reqId, true, null);
          return;
        }
        if (method === PluginRpcMethod.VIEWS_OPEN) {
          const id = String(params.id ?? '').trim();
          const list = viewsRef.current[session.pluginId] ?? [];
          if (!list.some((item) => item.id === id)) {
            raisePluginError(PluginErrorCode.NOT_FOUND, `插件未注册视图 ${id}`);
          }
          updateRuntimeInfo(session.pluginId, (info) => ({ ...info, presentRequested: true }));
          actionsRef.current.setRightSidebar(true, `plugin:${session.pluginId}`);
          void presentPluginView(session.pluginId, id);
          respond(reqId, true, null);
          return;
        }

        raisePluginError(PluginErrorCode.UNSUPPORTED_API, `不支持的 RPC：${method}`);
      } catch (error) {
        respond(reqId, false, {
          code: codeOfPluginError(error),
          message: messageOfPluginError(error)
        });
      }
    },
    [
      dispatchEditorRpc,
      dispatchVaultRpc,
      dispatchWorkspaceRpc,
      enqueueConfirm,
      ensurePathRegistryFresh,
      getAuthorizedNote,
      presentPluginView,
      pushNotice,
      resolveVault,
      updateRuntimeInfo
    ]
  );

  const bootSession = useCallback(
    async (session: LiveSession, record: PluginRecord): Promise<void> => {
      if (session.disposed || session.booting || session.booted) { return; }
      const bridge = window.lexi?.plugins;
      if (!bridge) { return; }
      session.booting = true;
      updateRuntimeInfo(record.id, (info) => ({
        ...info,
        state: 'starting',
        lastError: ''
      }));

      try {
        const assets = await bridge.readBootAssets(record.id, session.vaultId);
        if (session.disposed) { return; }
        const registry = ensurePathRegistryFresh(session.vaultId);
        const files = registry
          .entriesForVault(session.vaultId)
          .slice(0, PluginLimits.MAX_LIST_RESULT)
          .map((entry) => registry.toFileRef(entry));
        const draft = actionsRef.current.getEditorApi()?.getDraft?.() ?? null;
        const activeFile =
          draft && draft.noteId && draft.vaultId === session.vaultId
            ? (() => {
                const entry = registry.entryByNoteId(session.vaultId, draft.noteId);
                return entry ? registry.toFileRef(entry) : null;
              })()
            : null;
        const grantedCapabilities = record.grantedCapabilities.filter((cap) =>
          record.requestedCapabilities.includes(cap)
        );
        const bootPayload = {
          type: 'boot',
          protocol: PLUGIN_PROTOCOL_VERSION,
          pluginId: record.id,
          kind: record.kind,
          token: session.token,
          runtimeVersion: record.runtimeVersion || '1',
          capabilities: grantedCapabilities,
          vaultId: session.vaultId,
          manifestJson: assets.manifestJson,
          filesJson: JSON.stringify(files),
          activeFileJson: activeFile ? JSON.stringify(activeFile) : 'null',
          editorJson: draft && draft.vaultId === session.vaultId ? JSON.stringify(draft) : 'null',
          settingsJson: assets.settingsJson || 'null',
          dataJson: assets.dataJson || '{}',
          sourceCode: assets.sourceCode,
          sourceName: assets.sourceName,
          stylesCss: assets.stylesCss || '',
          platform: assets.platform || 'win32',
          warnings: [] as string[]
        };

        try {
          session.port?.postMessage(
            buildThemePayload(
              stateRef.current.settings.accent,
              derivedRef.current.isDark,
              stateRef.current.settings.paletteMode
            )
          );
        } catch {
          // Ignore theme sync errors.
        }

        const bootResult = (await sendPortCommand(session, { type: 'boot', payload: bootPayload }, 20000)) as {
          ok?: boolean;
          code?: string;
          error?: string;
          warnings?: string[];
        } | null;
        if (session.disposed) { return; }
        if (bootResult && bootResult.ok === false) {
          const failCode =
            typeof bootResult.code === 'string' && bootResult.code.length > 0
              ? bootResult.code
              : PluginErrorCode.PLUGIN_FAILED;
          const rawErr =
            typeof bootResult.error === 'string' && bootResult.error.length > 0
              ? bootResult.error
              : '插件启动失败';
          const prefix = `${failCode}: `;
          const cleanMsg = rawErr.startsWith(prefix) ? rawErr.slice(prefix.length) : rawErr;
          raisePluginError(failCode, cleanMsg);
        }
        session.booted = true;
        session.booting = false;
        const warnings = Array.isArray(bootResult?.warnings) ? bootResult.warnings : [];
        updateRuntimeInfo(record.id, (info) => ({
          ...info,
          state: 'active',
          lastError: '',
          warnings,
          hasViews: info.hasViews || record.kind === 'obsidian'
        }));
        appendDiagnostic(record.id, 'info', '插件已启动');
        settleBootWaiters(record.id);

        const queuedView = pendingPresentRef.current.get(record.id);
        if (queuedView !== undefined || stateRef.current.rightSidebarMode === `plugin:${record.id}`) {
          pendingPresentRef.current.delete(record.id);
          await presentPluginView(record.id, queuedView ?? '');
        }
      } catch (error) {
        if (session.disposed) { return; }
        session.booting = false;
        session.booted = false;
        const code = codeOfPluginError(error);
        const msg = messageOfPluginError(error);
        const formatted = code !== PluginErrorCode.UNKNOWN ? `${code}: ${msg}` : msg;
        updateRuntimeInfo(record.id, (info) => ({
          ...info,
          state: 'failed',
          lastError: formatted
        }));
        appendDiagnostic(record.id, 'error', `启动失败：${formatted}`);
        settleBootWaiters(record.id, formatted);
      }
    },
    [
      appendDiagnostic,
      ensurePathRegistryFresh,
      presentPluginView,
      sendPortCommand,
      settleBootWaiters,
      updateRuntimeInfo
    ]
  );

  const openSessionPort = useCallback(
    (session: LiveSession): void => {
      if (session.disposed || session.port || !session.iframe) { return; }
      const targetWin = session.iframe.contentWindow;
      if (!targetWin) { return; }
      for (const timer of session.pingTimers) {
        window.clearTimeout(timer);
      }
      session.pingTimers = [];

      const channel = new MessageChannel();
      session.port = channel.port1;
      channel.port1.onmessage = (ev) => {
        const msg = ev.data as Record<string, unknown> | null;
        if (!msg || typeof msg !== 'object' || session.disposed) { return; }
        if (msg.type === 'port-ready') {
          session.portReady = true;
          const liveRecord =
            catalogRef.current.records.find((r) => r.id === session.pluginId) ??
            ({ id: session.pluginId } as PluginRecord);
          if (liveRecord.main) {
            void bootSession(session, liveRecord);
          }
          return;
        }
        if (msg.type === 'host-reply') {
          const replyId = typeof msg.id === 'string' ? msg.id : '';
          const waiter = session.hostReplyWaiters.get(replyId);
          if (!waiter) { return; }
          session.hostReplyWaiters.delete(replyId);
          window.clearTimeout(waiter.timer);
          if (msg.ok === true) {
            waiter.resolve(msg.result);
          } else {
            const errMsg = typeof msg.error === 'string' ? msg.error : '插件调用失败';
            waiter.reject(new Error(errMsg));
          }
          return;
        }
        if (msg.type === 'rpc-request') {
          void handleRpcRequest(session, msg.payload);
          return;
        }
        if (msg.type === 'log') {
          appendDiagnostic(session.pluginId, String(msg.level ?? 'info'), String(msg.message ?? ''));
          return;
        }
        if (msg.type === 'ui-hook') {
          const hook = msg.payload as Record<string, unknown> | null;
          if (!hook || typeof hook !== 'object') { return; }
          if (hook.type === 'ribbon-sync' && Array.isArray(hook.items)) {
            session.ribbonItems = hook.items.slice(0, 8).map((item) => {
              const raw = item as Record<string, unknown>;
              return {
                pluginId: session.pluginId,
                id: String(raw.id ?? ''),
                icon: String(raw.icon ?? 'puzzle'),
                title: String(raw.title ?? '')
              };
            });
            syncAggregatedUiHooks();
            return;
          }
          if (hook.type === 'status-bar-sync' && Array.isArray(hook.items)) {
            session.statusItems = hook.items
              .slice(0, 8)
              .map((item) => {
                const raw = item as Record<string, unknown>;
                return {
                  pluginId: session.pluginId,
                  id: String(raw.id ?? ''),
                  text: String(raw.text ?? '')
                };
              })
              .filter((item) => item.text.length > 0);
            syncAggregatedUiHooks();
            return;
          }
          if (hook.type === 'modal-state') {
            const count = typeof hook.openCount === 'number' ? hook.openCount : 0;
            if (count > 0) {
              setModalPluginId(session.pluginId);
            } else if (modalPluginRef.current === session.pluginId) {
              setModalPluginId('');
            }
          }
        }
      };
      channel.port1.start();
      try {
        targetWin.postMessage({ type: 'lexi-init-port' }, '*', [channel.port2]);
      } catch (error) {
        appendDiagnostic(session.pluginId, 'error', `端口握手失败：${messageOfPluginError(error)}`);
      }
    },
    [appendDiagnostic, bootSession, handleRpcRequest, syncAggregatedUiHooks]
  );

  const notifyFrameLoaded = useCallback(
    (pluginId: string, vaultId: string, nonce: number): void => {
      const session = sessionsRef.current.get(pluginId);
      if (!session || session.disposed || session.vaultId !== vaultId || session.nonce !== nonce) {
        return;
      }
      openSessionPort(session);
    },
    [openSessionPort]
  );

  useEffect(() => {
    const onWindowMessage = (ev: MessageEvent): void => {
      const data = ev.data as Record<string, unknown> | null;
      if (!data || typeof data !== 'object' || data.type !== 'lexi-runtime-ready') {
        return;
      }
      for (const session of sessionsRef.current.values()) {
        if (!session.disposed && !session.port && session.iframe?.contentWindow === ev.source) {
          openSessionPort(session);
          return;
        }
      }
    };
    window.addEventListener('message', onWindowMessage);
    return () => {
      window.removeEventListener('message', onWindowMessage);
    };
  }, [openSessionPort]);

  const attachIframe = useCallback(
    (record: PluginRecord, vaultId: string, nonce: number, iframe: HTMLIFrameElement | null): void => {
      const existing = sessionsRef.current.get(record.id);
      if (!iframe) {
        if (existing && existing.vaultId === vaultId && existing.nonce === nonce) {
          existing.disposed = true;
          for (const timer of existing.pingTimers) {
            window.clearTimeout(timer);
          }
          existing.pingTimers = [];
          for (const waiter of existing.hostReplyWaiters.values()) {
            window.clearTimeout(waiter.timer);
            waiter.reject(raisePluginError(PluginErrorCode.CANCELLED, '插件已卸载'));
          }
          existing.hostReplyWaiters.clear();
          try {
            existing.port?.close();
          } catch {
            // Ignore.
          }
          sessionsRef.current.delete(record.id);
          clearPluginContributions(record.id);
        }
        return;
      }

      if (existing && existing.iframe === iframe && existing.vaultId === vaultId && existing.nonce === nonce) {
        return;
      }

      const session: LiveSession = {
        pluginId: record.id,
        vaultId,
        nonce,
        token: randomToken(),
        iframe,
        port: null,
        portReady: false,
        booted: false,
        booting: false,
        disposed: false,
        subscriptions: new Map(),
        eventSeq: 0,
        hostReplyWaiters: new Map(),
        pingTimers: [],
        ribbonItems: [],
        statusItems: []
      };
      sessionsRef.current.set(record.id, session);

      const sendPing = (): void => {
        if (session.disposed || session.port || !session.iframe) { return; }
        try {
          session.iframe.contentWindow?.postMessage({ type: 'lexi-ping-port' }, '*');
        } catch {
          // Ignore while iframe navigates from about:blank.
        }
      };

      iframe.addEventListener('load', () => openSessionPort(session), { once: true });
      sendPing();
      for (const delay of [60, 250, 800]) {
        session.pingTimers.push(window.setTimeout(sendPing, delay));
      }
    },
    [clearPluginContributions, openSessionPort]
  );

  // Boot load & catalog IPC subscription
  const refreshCatalog = useCallback(async (): Promise<void> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    try {
      const next = await bridge.list();
      setCatalog(next);
    } catch (error) {
      actionsRef.current.showToast(messageOfPluginError(error) || '读取插件列表失败');
    }
  }, []);

  useEffect(() => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    void refreshCatalog();
    return bridge.onCatalogChanged((snapshot) => {
      setCatalog(snapshot);
    });
  }, [refreshCatalog]);

  // Keep baseline runtime info entries for installed/disabled plugins
  useEffect(() => {
    const enabledSet = new Set(enabledIds);
    setRuntimeInfoById((previous) => {
      const next: Record<string, PluginRuntimeInfo> = {};
      for (const record of catalog.records) {
        const cur = previous[record.id];
        if (!enabledSet.has(record.id)) {
          next[record.id] = {
            ...(cur ?? emptyRuntimeInfo(PluginLifecycleState.INSTALLED_DISABLED)),
            state: PluginLifecycleState.INSTALLED_DISABLED,
            presentRequested: false
          };
        } else {
          next[record.id] = cur
            ? {
                ...cur,
                state:
                  cur.state === PluginLifecycleState.INSTALLED_DISABLED
                    ? PluginLifecycleState.STARTING
                    : cur.state
              }
            : emptyRuntimeInfo(PluginLifecycleState.STARTING);
        }
      }
      return next;
    });
  }, [catalog.records, enabledIds]);

  // Broadcast live theme changes into active plugin iframes
  useEffect(() => {
    const payload = buildThemePayload(
      state.settings.accent,
      derived.isDark,
      state.settings.paletteMode
    );
    for (const session of sessionsRef.current.values()) {
      if (!session.disposed && session.portReady && session.port) {
        try {
          session.port.postMessage(payload);
        } catch {
          // Ignore closed port.
        }
      }
    }
  }, [state.settings.accent, state.settings.paletteMode, derived.isDark]);

  // Observe main-app note/workspace changes to publish core events to subscribed plugins
  useEffect(() => {
    if (!state.ready || !state.activeVaultId) { return; }
    const vaultId = state.activeVaultId;
    const registry = ensurePathRegistryFresh(vaultId);
    const entries = registry.entriesForVault(vaultId);
    const noteMap = new Map<string, NoteItem>();
    for (const n of state.notes) {
      if (n.vaultId === vaultId && !n.trashedAt) { noteMap.set(n.id, n); }
    }
    const nextPrev = new Map<string, { path: string; sig: string; fileRef: PluginFileRef }>();
    for (const entry of entries) {
      const n = noteMap.get(entry.noteId);
      if (!n) { continue; }
      const ref = registry.toFileRef(entry);
      nextPrev.set(entry.noteId, {
        path: entry.logicalPath,
        sig: noteSignature(n, entry.logicalPath),
        fileRef: ref
      });
    }

    const activeNoteId =
      state.selectedId && !state.selectedId.includes(':') && noteMap.has(state.selectedId) ? state.selectedId : '';
    const layoutKey = `${state.sidebarOpen ? 1 : 0}:${state.rightSidebarOpen ? 1 : 0}:${state.rightSidebarMode}`;

    if (watcherVaultRef.current !== vaultId) {
      watcherVaultRef.current = vaultId;
      watcherPrevNotesRef.current = nextPrev;
      watcherActiveNoteRef.current = activeNoteId;
      watcherLayoutRef.current = layoutKey;
      return;
    }

    const prevMap = watcherPrevNotesRef.current;
    const rev = registry.revisionOf(vaultId);

    for (const [noteId, curr] of nextPrev.entries()) {
      const old = prevMap.get(noteId);
      if (rpcSuppressedNoteSigsRef.current.has(curr.sig)) {
        rpcSuppressedNoteSigsRef.current.delete(curr.sig);
        continue;
      }
      if (!old) {
        publishEvent(PluginEventType.VAULT_CREATED, vaultId, {
          fileId: noteId,
          path: curr.path,
          oldPath: '',
          projectId: curr.fileRef.projectId,
          revision: rev
        });
      } else if (old.path !== curr.path) {
        publishEvent(PluginEventType.VAULT_RENAMED, vaultId, {
          fileId: noteId,
          path: curr.path,
          oldPath: old.path,
          projectId: curr.fileRef.projectId,
          revision: rev
        });
        publishEvent(PluginEventType.METADATA_RESOLVED, vaultId, {
          fileId: noteId,
          path: curr.path,
          oldPath: '',
          revision: rev
        });
      } else if (old.sig !== curr.sig) {
        publishEvent(PluginEventType.VAULT_MODIFIED, vaultId, {
          fileId: noteId,
          path: curr.path,
          oldPath: '',
          projectId: curr.fileRef.projectId,
          revision: rev
        });
        publishEvent(PluginEventType.METADATA_RESOLVED, vaultId, {
          fileId: noteId,
          path: curr.path,
          oldPath: '',
          revision: rev
        });
        if (noteId === activeNoteId) {
          publishEvent(PluginEventType.EDITOR_CHANGED, vaultId, {
            fileId: noteId,
            path: curr.path,
            oldPath: '',
            revision: rev
          });
        }
      }
    }

    for (const [noteId, old] of prevMap.entries()) {
      if (!nextPrev.has(noteId)) {
        publishEvent(PluginEventType.VAULT_DELETED, vaultId, {
          fileId: noteId,
          path: old.path,
          oldPath: '',
          projectId: old.fileRef.projectId,
          revision: rev
        });
      }
    }

    if (watcherActiveNoteRef.current !== activeNoteId) {
      watcherActiveNoteRef.current = activeNoteId;
      const ref = activeNoteId ? nextPrev.get(activeNoteId)?.fileRef : undefined;
      publishEvent(PluginEventType.WORKSPACE_ACTIVE_FILE_CHANGED, vaultId, {
        fileId: activeNoteId,
        path: ref?.path ?? '',
        oldPath: '',
        revision: rev
      });
    }

    watcherLayoutRef.current = layoutKey;

    watcherPrevNotesRef.current = nextPrev;
  }, [
    state.ready,
    state.activeVaultId,
    state.notes,
    state.projects,
    state.selectedId,
    state.sidebarOpen,
    state.rightSidebarOpen,
    state.rightSidebarMode,
    ensurePathRegistryFresh,
    publishEvent
  ]);

  // Present plugin view when rightSidebar switches to `plugin:<id>`
  useEffect(() => {
    if (!state.rightSidebarOpen || !state.rightSidebarMode.startsWith('plugin:')) {
      return;
    }
    const pluginId = state.rightSidebarMode.slice('plugin:'.length);
    void presentPluginView(pluginId, '');
  }, [state.rightSidebarOpen, state.rightSidebarMode, presentPluginView]);

  // Measure RightSidebar plugin surface slot rect with ResizeObserver
  const syncSlotRect = useCallback((): void => {
    const { pluginId, element } = surfaceSlotRef.current;
    if (!pluginId || !element || !document.body.contains(element)) {
      setDockedSlot((prev) => (prev.pluginId === '' && prev.rect === null ? prev : { pluginId: '', rect: null }));
      return;
    }
    const r = element.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) {
      setDockedSlot({ pluginId, rect: null });
      return;
    }
    setDockedSlot({
      pluginId,
      rect: {
        top: Math.round(r.top),
        left: Math.round(r.left),
        width: Math.round(r.width),
        height: Math.round(r.height)
      }
    });
  }, []);

  const slotObserverRef = useRef<ResizeObserver | null>(null);

  const registerSurfaceSlot = useCallback(
    (pluginId: string, element: HTMLElement | null): void => {
      slotObserverRef.current?.disconnect();
      slotObserverRef.current = null;
      surfaceSlotRef.current = element ? { pluginId, element } : { pluginId: '', element: null };
      if (element && typeof ResizeObserver === 'function') {
        const ro = new ResizeObserver(() => syncSlotRect());
        ro.observe(element);
        if (element.parentElement) {
          ro.observe(element.parentElement);
        }
        ro.observe(document.body);
        slotObserverRef.current = ro;
      }
      syncSlotRect();
    },
    [syncSlotRect]
  );

  useEffect(() => {
    const onResize = (): void => syncSlotRect();
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      slotObserverRef.current?.disconnect();
      slotObserverRef.current = null;
    };
  }, [syncSlotRect]);

  // Cleanup all notice timers on unmount
  useEffect(() => {
    return () => {
      for (const timer of noticeTimersRef.current.values()) {
        window.clearTimeout(timer);
      }
      noticeTimersRef.current.clear();
    };
  }, []);

  // Host actions exposed to UI
  const installZip = useCallback(async (): Promise<PluginInstallResult> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) {
      actionsRef.current.showToast('当前环境不支持插件安装');
      return { ok: false, cancelled: true, pluginId: '', record: null, error: '当前环境不支持插件安装', warnings: [] };
    }
    const result = await bridge.pickInstallZip();
    await refreshCatalog();
    if (result.ok && result.record) {
      actionsRef.current.showToast(`已安装插件「${result.record.name}」`);
    } else if (!result.cancelled && result.error) {
      actionsRef.current.showToast(result.error);
    }
    return result;
  }, [refreshCatalog]);

  const installFolder = useCallback(async (): Promise<PluginInstallResult> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) {
      actionsRef.current.showToast('当前环境不支持插件安装');
      return { ok: false, cancelled: true, pluginId: '', record: null, error: '当前环境不支持插件安装', warnings: [] };
    }
    const result = await bridge.pickInstallFolder();
    await refreshCatalog();
    if (result.ok && result.record) {
      actionsRef.current.showToast(`已安装插件「${result.record.name}」`);
    } else if (!result.cancelled && result.error) {
      actionsRef.current.showToast(result.error);
    }
    return result;
  }, [refreshCatalog]);

  const enablePlugin = useCallback(async (pluginId: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    const vaultId = stateRef.current.activeVaultId;
    if (!bridge || !vaultId) { return; }
    const waitBoot = new Promise<void>((resolve) => {
      const list = bootWaitersRef.current.get(pluginId) ?? [];
      list.push(() => resolve());
      bootWaitersRef.current.set(pluginId, list);
      window.setTimeout(() => {
        settleBootWaiters(pluginId);
      }, 22000);
    });
    updateRuntimeInfo(pluginId, (info) => ({ ...info, state: 'starting', lastError: '' }));
    await bridge.setEnabled(vaultId, pluginId, true);
    await refreshCatalog();
    await waitBoot;
  }, [refreshCatalog, settleBootWaiters, updateRuntimeInfo]);

  const disablePlugin = useCallback(async (pluginId: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    const vaultId = stateRef.current.activeVaultId;
    if (!bridge || !vaultId) { return; }
    const session = sessionsRef.current.get(pluginId);
    if (session && session.portReady && !session.disposed) {
      try {
        await sendPortCommand(session, { type: 'unload' }, 1500);
      } catch {
        // Ignore unload timeout.
      }
    }
    clearPluginContributions(pluginId);
    await bridge.setEnabled(vaultId, pluginId, false);
    await refreshCatalog();
  }, [clearPluginContributions, refreshCatalog, sendPortCommand]);

  const retryPlugin = useCallback(async (pluginId: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    const vaultId = stateRef.current.activeVaultId;
    if (!bridge || !vaultId) { return; }
    const session = sessionsRef.current.get(pluginId);
    if (session && session.portReady && !session.disposed) {
      try {
        await sendPortCommand(session, { type: 'unload' }, 1200);
      } catch {
        // Ignore unload error.
      }
    }
    clearPluginContributions(pluginId);
    const waitBoot = new Promise<void>((resolve) => {
      const list = bootWaitersRef.current.get(pluginId) ?? [];
      list.push(() => resolve());
      bootWaitersRef.current.set(pluginId, list);
      window.setTimeout(() => {
        settleBootWaiters(pluginId);
      }, 22000);
    });
    updateRuntimeInfo(pluginId, (info) => ({ ...info, state: 'starting', lastError: '' }));
    if (!(catalogRef.current.enabledByVault[vaultId] ?? []).includes(pluginId)) {
      await bridge.setEnabled(vaultId, pluginId, true);
    }
    await refreshCatalog();
    setReloadNonces((previous) => ({ ...previous, [pluginId]: (previous[pluginId] ?? 0) + 1 }));
    await waitBoot;
  }, [clearPluginContributions, refreshCatalog, sendPortCommand, settleBootWaiters, updateRuntimeInfo]);

  const uninstallPlugin = useCallback(
    async (pluginId: string, keepData = true): Promise<void> => {
      const bridge = window.lexi?.plugins;
      if (!bridge) { return; }
      const session = sessionsRef.current.get(pluginId);
      if (session && session.portReady && !session.disposed) {
        try {
          await sendPortCommand(session, { type: 'unload' }, 1500);
        } catch {
          // Ignore.
        }
      }
      clearPluginContributions(pluginId);
      if (stateRef.current.rightSidebarMode === `plugin:${pluginId}`) {
        actionsRef.current.setRightSidebarMode('outline');
      }
      await bridge.uninstall(pluginId, keepData);
      await refreshCatalog();
      actionsRef.current.showToast('已卸载插件');
    },
    [clearPluginContributions, refreshCatalog, sendPortCommand]
  );

  const grantCapability = useCallback(async (pluginId: string, capability: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    await bridge.grantCapability(pluginId, capability);
    await refreshCatalog();
  }, [refreshCatalog]);

  const revokeCapability = useCallback(async (pluginId: string, capability: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    await bridge.revokeCapability(pluginId, capability);
    await refreshCatalog();
  }, [refreshCatalog]);

  const grantAllCapabilities = useCallback(async (pluginId: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    await bridge.grantAllCapabilities(pluginId);
    await refreshCatalog();
  }, [refreshCatalog]);

  const revokeAllCapabilities = useCallback(async (pluginId: string): Promise<void> => {
    const bridge = window.lexi?.plugins;
    if (!bridge) { return; }
    await bridge.revokeAllCapabilities(pluginId);
    await refreshCatalog();
  }, [refreshCatalog]);

  const openPluginsFolder = useCallback(async (): Promise<void> => {
    await window.lexi?.plugins?.openFolder();
  }, []);

  const contextValue: PluginHostContextValue = {
    catalog,
    enabledIds,
    records: catalog.records,
    runtimeInfoById,
    commands,
    viewsByPlugin,
    ribbonActions,
    statusBarItems,
    notices,
    confirmRequest,
    modalPluginId,
    refreshCatalog,
    installZip,
    installFolder,
    uninstallPlugin,
    enablePlugin,
    disablePlugin,
    retryPlugin,
    grantCapability,
    revokeCapability,
    grantAllCapabilities,
    revokeAllCapabilities,
    openPluginsFolder,
    runCommand,
    triggerRibbon,
    presentPluginView,
    dismissNotice,
    resolveConfirm,
    registerSurfaceSlot
  };

  return (
    <PluginHostContext.Provider value={contextValue}>
      {children}
      {modalPluginId ? (
        <div className="plugin-modal-backdrop" aria-hidden="true" />
      ) : null}
      <div className="plugin-iframe-host">
        {activeSessionEntries.map(({ record, vaultId, nonce }) => {
          const isModal = modalPluginId === record.id;
          const isDocked =
            !isModal &&
            state.rightSidebarOpen &&
            state.rightSidebarMode === `plugin:${record.id}` &&
            dockedSlot.pluginId === record.id &&
            dockedSlot.rect !== null;
          const style: React.CSSProperties = isModal
            ? {}
            : isDocked && dockedSlot.rect
              ? {
                  position: 'fixed',
                  top: `${dockedSlot.rect.top}px`,
                  left: `${dockedSlot.rect.left}px`,
                  width: `${dockedSlot.rect.width}px`,
                  height: `${dockedSlot.rect.height}px`,
                  zIndex: 15,
                  border: 0
                }
              : {
                  position: 'fixed',
                  left: '-9999px',
                  top: 0,
                  width: '320px',
                  height: '480px',
                  visibility: 'hidden',
                  pointerEvents: 'none',
                  border: 0
                };
          return (
            <PluginSandboxFrame
              key={`${vaultId}:${record.id}:${nonce}`}
              record={record}
              vaultId={vaultId}
              nonce={nonce}
              className={isModal ? 'plugin-runtime-iframe plugin-iframe-modal' : 'plugin-runtime-iframe'}
              style={style}
              attachIframe={attachIframe}
              onFrameLoad={notifyFrameLoaded}
            />
          );
        })}
      </div>
    </PluginHostContext.Provider>
  );
}

function PluginSandboxFrame({
  record,
  vaultId,
  nonce,
  className,
  style,
  attachIframe,
  onFrameLoad
}: {
  record: PluginRecord;
  vaultId: string;
  nonce: number;
  className: string;
  style: React.CSSProperties;
  attachIframe: (record: PluginRecord, vaultId: string, nonce: number, iframe: HTMLIFrameElement | null) => void;
  onFrameLoad: (pluginId: string, vaultId: string, nonce: number) => void;
}): JSX.Element {
  const frameRef = useRef<HTMLIFrameElement | null>(null);

  useLayoutEffect(() => {
    const el = frameRef.current;
    if (!el) { return; }
    attachIframe(record, vaultId, nonce, el);
    return () => {
      attachIframe(record, vaultId, nonce, null);
    };
    // Mount/unmount lifecycle only tracks record id, vault id, and explicit reload nonce.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [record.id, vaultId, nonce, attachIframe]);

  return (
    <iframe
      ref={frameRef}
      title={`plugin-runtime-${record.id}`}
      src="./plugin-runtime/index.html"
      sandbox="allow-scripts"
      className={className}
      style={style}
      onLoad={() => onFrameLoad(record.id, vaultId, nonce)}
    />
  );
}

export function usePluginHost(): PluginHostContextValue {
  const ctx = useContext(PluginHostContext);
  if (!ctx) {
    throw new Error('usePluginHost must be used inside PluginHostProvider');
  }
  return ctx;
}

export function useOptionalPluginHost(): PluginHostContextValue | null {
  return useContext(PluginHostContext);
}

export function allSupportedRpcMethods(): string[] {
  return ALL_PLUGIN_RPC_METHODS.slice();
}
