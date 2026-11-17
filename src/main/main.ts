import { app, BrowserWindow, Menu, dialog, ipcMain, net, protocol, shell, clipboard, screen } from 'electron';
import { randomUUID } from 'node:crypto';
import { existsSync, promises as fs } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import type { ImportedAttachment, ImportedFile, MarkdownExportFile, NoteItem, PersistedState, RuntimeInfo } from '../shared/types';
import {
  cloneNote,
  type ConflictResolutionMode,
  type CrashRecoveryItem,
  type DraftWalEntry,
  type HistoryRetentionPolicy,
  type HistoryUsageSummary,
  type NoteConflictInfo,
  type NoteRevision
} from '../shared/noteHistory';
import { codeOfPluginError, messageOfPluginError, type PluginInstallResult } from '../shared/pluginTypes';
import { NoteHistoryStore, mergeWithConflictDetection } from './historyStore';
import { PluginService } from './pluginService';
import {
  atomicWriteTextAsync,
  buildZipBuffer,
  collectWorkspaceFilesForZip,
  extractZipToFolder,
  friendlySaveError,
  normalizeCanvasBoard,
  normalizeMindMapDoc,
  parseNoteMarkdown,
  resolveVaultFolder,
  scanWorkspaceFolder,
  syncStateToWorkspaceFolders
} from './workspaceFs';

protocol.registerSchemesAsPrivileged([
  {
    scheme: 'lexi-asset',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true }
  }
]);

const isDev = !!process.env.VITE_DEV_SERVER_URL;
const demoData = process.env.LEXI_DEMO_DATA === '1';

// Tests and screenshots keep all app data inside the workspace.
if (process.env.LEXI_USER_DATA) {
  app.setPath('userData', process.env.LEXI_USER_DATA);
}
app.setName('LexiNote');
app.setAppUserModelId('com.lovexjy.lexinote');
const dataFile = (): string => path.join(app.getPath('userData'), 'lexinote-data.json');
const windowStateFile = (): string => path.join(app.getPath('userData'), 'window-state.json');

let pluginServiceInstance: PluginService | null = null;
function getPluginService(): PluginService {
  if (!pluginServiceInstance) {
    pluginServiceInstance = new PluginService(app.getPath('userData'));
  }
  return pluginServiceInstance;
}

let historyStoreInstance: NoteHistoryStore | null = null;
function getHistoryStore(): NoteHistoryStore {
  if (!historyStoreInstance) {
    historyStoreInstance = new NoteHistoryStore(app.getPath('userData'));
  }
  return historyStoreInstance;
}

function broadcastPluginCatalog(): void {
  const snapshot = getPluginService().snapshot();
  for (const win of windows) {
    if (!win.isDestroyed()) {
      win.webContents.send('plugin:catalog-changed', snapshot);
    }
  }
}

async function runPluginOp<T>(fn: () => Promise<T> | T): Promise<{ ok: true; data: T } | { ok: false; code: string; message: string }> {
  try {
    const data = await fn();
    return { ok: true, data };
  } catch (error) {
    return {
      ok: false,
      code: codeOfPluginError(error),
      message: messageOfPluginError(error)
    };
  }
}

const windows = new Set<BrowserWindow>();
let primaryWindow: BrowserWindow | null = null;
const closeAllowed = new Set<number>();
const closeRequested = new Set<number>();
const pendingPdfDocs = new Map<string, string>();
const pendingExternalPaths: string[] = [];

const OPENABLE_EXT_RE = /\.(md|markdown|txt|json)$/i;

function resolveKatexDir(): string {
  const packaged = path.join(__dirname, 'katex');
  if (existsSync(packaged)) return packaged;
  return path.resolve(__dirname, '../../node_modules/katex/dist');
}

function extractOpenableFileArgs(argv: string[]): string[] {
  const found: string[] = [];
  for (const arg of argv.slice(1)) {
    if (!arg || arg.startsWith('-') || arg === '.') continue;
    const candidate = path.resolve(arg);
    if (OPENABLE_EXT_RE.test(candidate) && existsSync(candidate)) {
      found.push(candidate);
    }
  }
  return found;
}

async function readExternalImportedFiles(filePaths: string[]): Promise<ImportedFile[]> {
  const files: ImportedFile[] = [];
  for (const filePath of filePaths) {
    const name = path.basename(filePath);
    try {
      const content = await fs.readFile(filePath, 'utf8');
      const st = await fs.stat(filePath);
      const entry: ImportedFile = { name, content, sourcePath: filePath };
      if (/\.(md|markdown)$/i.test(name)) {
        entry.parsedNote = parseNoteMarkdown(content, {
          vaultId: '',
          fallbackTitle: name.replace(/\.(md|markdown)$/i, ''),
          fallbackNotebook: '外部导入',
          filePath: '',
          birthtimeMs: st.birthtimeMs,
          mtimeMs: st.mtimeMs
        });
      } else if (/\.json$/i.test(name)) {
        try {
          const parsed = JSON.parse(content) as Record<string, unknown>;
          if (parsed && typeof parsed === 'object') {
            const mapDoc = normalizeMindMapDoc(parsed, '');
            if (mapDoc) entry.parsedMap = mapDoc;
            else {
              const board = normalizeCanvasBoard(parsed, '');
              if (board) entry.parsedCanvas = board;
            }
          }
        } catch {
          // Keep raw content for fallback handling.
        }
      }
      files.push(entry);
    } catch (error) {
      files.push({
        name,
        content: '',
        sourcePath: filePath,
        error: friendlySaveError(error, '无法读取文件内容')
      });
    }
  }
  return files;
}

async function deliverExternalFiles(filePaths: string[]): Promise<void> {
  if (filePaths.length === 0) return;
  const target = primaryWindow && !primaryWindow.isDestroyed()
    ? primaryWindow
    : [...windows].find((candidate) => !candidate.isDestroyed()) ?? null;
  if (!target || target.webContents.isLoading()) {
    pendingExternalPaths.push(...filePaths);
    return;
  }
  const files = await readExternalImportedFiles(filePaths);
  if (files.length > 0 && !target.isDestroyed()) {
    target.webContents.send('files:external-open', files);
  }
}

async function renderHtmlToPdfBuffer(html: string): Promise<Buffer> {
  const token = `${randomUUID()}.html`;
  pendingPdfDocs.set(token, html);
  const win = new BrowserWindow({
    show: false,
    width: 794,
    height: 1123,
    backgroundColor: '#FFFFFF',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false
    }
  });
  try {
    await win.loadURL(`lexi-asset://pdf-doc/${token}`);
    await win.webContents.executeJavaScript(
      `(async () => {
        if (document.fonts && document.fonts.ready) {
          await Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 2500))]);
        }
        const imgs = Array.from(document.images || []);
        await Promise.all(imgs.map((img) => {
          if (img.complete) return Promise.resolve();
          return new Promise((resolve) => {
            const timer = setTimeout(resolve, 2500);
            img.addEventListener('load', () => { clearTimeout(timer); resolve(); }, { once: true });
            img.addEventListener('error', () => { clearTimeout(timer); resolve(); }, { once: true });
          });
        }));
      })()`,
      true
    );
    return await win.webContents.printToPDF({
      printBackground: true,
      pageSize: 'A4',
      preferCSSPageSize: true
    });
  } finally {
    pendingPdfDocs.delete(token);
    if (!win.isDestroyed()) win.destroy();
  }
}

// ---------------------------------------------------------------------------
// Shared library state. Every window saves a full snapshot; the main process
// merges snapshots per entity and broadcasts the result, so two windows can be
// open on different workspaces without overwriting each other.

let masterState: PersistedState | null = null;
let dataRevision = 0;
let saveChain: Promise<unknown> = Promise.resolve();

interface WindowState {
  width: number;
  height: number;
  x?: number;
  y?: number;
  maximized?: boolean;
}

interface StateEnvelope {
  state: PersistedState | null;
  revision: number;
}

function enqueue<T>(task: () => Promise<T>): Promise<T> {
  const next = saveChain.then(task, task);
  saveChain = next.then(
    () => undefined,
    () => undefined
  );
  return next;
}

async function readWindowState(): Promise<WindowState> {
  try {
    const raw = await fs.readFile(windowStateFile(), 'utf8');
    const parsed = JSON.parse(raw) as WindowState;
    if (typeof parsed.width === 'number' && typeof parsed.height === 'number') {
      return parsed;
    }
  } catch {
    // First launch has no saved bounds.
  }
  return { width: 1440, height: 900 };
}

async function writeWindowState(win: BrowserWindow): Promise<void> {
  if (win.isDestroyed() || win !== primaryWindow) return;
  try {
    const maximized = win.isMaximized();
    const bounds = win.getNormalBounds();
    await fs.writeFile(
      windowStateFile(),
      JSON.stringify({ ...bounds, maximized }, null, 2),
      'utf8'
    );
  } catch {
    // Bounds are a convenience, never a hard failure.
  }
}

async function readStateFile(): Promise<PersistedState | null> {
  try {
    const raw = await fs.readFile(dataFile(), 'utf8');
    return JSON.parse(raw) as PersistedState;
  } catch (error) {
    const missing = (error as NodeJS.ErrnoException).code === 'ENOENT';
    if (!missing) {
      // Never overwrite a damaged library silently: keep the original next to it.
      try {
        const backup = `${dataFile()}.corrupt-${Date.now()}`;
        await fs.rename(dataFile(), backup);
        console.error(`LexiNote data could not be parsed; kept a copy at ${backup}`);
      } catch {
        // Reading is allowed to fail; the renderer starts with an empty library.
      }
    }
    return null;
  }
}

let masterBootRecovered = false;
async function ensureMaster(): Promise<void> {
  if (!masterState) {
    const loaded = await readStateFile();
    if (loaded) {
      masterState = loaded;
      dataRevision = 1;
    }
  }
  if (!masterBootRecovered) {
    masterBootRecovered = true;
    if (masterState) {
      try {
        const res = await getHistoryStore().recoverCrashDrafts(masterState, masterState.settings?.historyPolicy);
        if (res.stateChanged) {
          await writeMasterFileState(res.nextState);
          masterState = res.nextState;
          dataRevision += 1;
        }
      } catch (err) {
        console.warn('Crash recovery scan failed', err);
      }
    }
  }
}

async function writeMasterFileState(
  nextState: PersistedState,
  options?: { skipWorkspaceSync?: boolean }
): Promise<{ syncWarning?: string }> {
  const target = dataFile();
  await atomicWriteTextAsync(target, JSON.stringify(nextState));
  if (options?.skipWorkspaceSync) return {};
  let syncWarning: string | undefined;
  try {
    const warnings = syncStateToWorkspaceFolders(app.getPath('userData'), nextState);
    if (warnings.length > 0) syncWarning = warnings[0];
  } catch (error) {
    syncWarning = `主库已保存，外部工作区同步受限：${friendlySaveError(error)}`;
  }
  return { syncWarning };
}

function sanitizeNoteAccessMap(raw: Record<string, number> | undefined): Record<string, number> | undefined {
  if (!raw || typeof raw !== 'object') return undefined;
  const cleaned: Record<string, number> = {};
  for (const [id, val] of Object.entries(raw)) {
    if (id && typeof val === 'number' && Number.isFinite(val) && val > 0) {
      cleaned[id] = val;
    }
  }
  return Object.keys(cleaned).length > 0 ? cleaned : undefined;
}

function normalizeIncoming(value: PersistedState | null | undefined): PersistedState {
  const noteAccessedAt = sanitizeNoteAccessMap(value?.noteAccessedAt ?? masterState?.noteAccessedAt);
  return {
    version: 2,
    vaults: Array.isArray(value?.vaults) ? value!.vaults : [],
    projects: Array.isArray(value?.projects) ? value!.projects : [],
    notes: Array.isArray(value?.notes) ? value!.notes : [],
    maps: Array.isArray(value?.maps) ? value!.maps : [],
    canvases: Array.isArray(value?.canvases) ? value!.canvases : [],
    settings: value?.settings ?? masterState?.settings ?? ({} as PersistedState['settings']),
    ...(noteAccessedAt ? { noteAccessedAt } : {})
  };
}

function mergeUpdated<T extends { id: string }>(
  master: T[],
  incoming: T[],
  updatedAt: (item: T) => number,
  allowDeletes: boolean
): T[] {
  const incomingById = new Map(incoming.map((item) => [item.id, item]));
  const result: T[] = [];
  for (const masterItem of master) {
    const next = incomingById.get(masterItem.id);
    if (!next) {
      if (!allowDeletes) result.push(masterItem);
      continue;
    }
    result.push(updatedAt(next) < updatedAt(masterItem) ? masterItem : next);
  }
  const masterIds = new Set(master.map((item) => item.id));
  for (const item of incoming) {
    if (!masterIds.has(item.id)) result.push(item);
  }
  return result;
}

function mergeSimple<T extends { id: string }>(master: T[], incoming: T[], allowDeletes: boolean): T[] {
  if (allowDeletes) return incoming;
  // A stale snapshot must not rename or remove entries; only brand-new ids are
  // accepted from it.
  const incomingById = new Map(incoming.map((item) => [item.id, item]));
  const result = master.map((item) => incomingById.get(item.id) ?? item);
  const masterIds = new Set(master.map((item) => item.id));
  for (const item of incoming) {
    if (!masterIds.has(item.id)) result.push(item);
  }
  return result;
}

function broadcastState(exceptSenderId?: number): void {
  if (!masterState) return;
  const payload = { state: masterState, revision: dataRevision };
  for (const win of windows) {
    if (win.isDestroyed() || win.webContents.isDestroyed()) continue;
    if (win.webContents.id === exceptSenderId) continue;
    win.webContents.send('state:sync', payload);
  }
}

function sendSyncTo(win: BrowserWindow): void {
  if (!masterState || win.isDestroyed() || win.webContents.isDestroyed()) return;
  win.webContents.send('state:sync', { state: masterState, revision: dataRevision });
}

function senderWindow(event: Electron.IpcMainInvokeEvent | Electron.IpcMainEvent): BrowserWindow | null {
  return BrowserWindow.fromWebContents(event.sender);
}

function sendMaximizeState(win: BrowserWindow): void {
  if (win.isDestroyed()) return;
  win.webContents.send('window:maximized', win.isMaximized());
}

// ---------------------------------------------------------------------------
// Windows

async function createAppWindow(options: { vaultId?: string; cascade?: boolean } = {}): Promise<BrowserWindow> {
  const saved = await readWindowState();
  const parent = primaryWindow && !primaryWindow.isDestroyed() ? primaryWindow : BrowserWindow.getFocusedWindow();
  let bounds = { x: saved.x, y: saved.y, width: saved.width, height: saved.height };
  if (options.cascade && parent) {
    const parentBounds = parent.getBounds();
    const workArea = screen.getDisplayMatching(parentBounds).workArea;
    const width = Math.min(Math.max(980, saved.width), 1320);
    const height = Math.min(Math.max(620, saved.height), 880);
    bounds = {
      width,
      height,
      x: Math.max(workArea.x + 16, Math.min(parentBounds.x + 32, workArea.x + workArea.width - width - 16)),
      y: Math.max(workArea.y + 16, Math.min(parentBounds.y + 32, workArea.y + workArea.height - height - 16))
    };
  }

  const win = new BrowserWindow({
    width: bounds.width,
    height: bounds.height,
    x: bounds.x,
    y: bounds.y,
    minWidth: 980,
    minHeight: 620,
    show: false,
    frame: false,
    backgroundColor: '#F7F8FA',
    title: '知萤 LexiNote',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false
    }
  });

  windows.add(win);
  if (!primaryWindow || primaryWindow.isDestroyed()) primaryWindow = win;
  win.setMenuBarVisibility(false);
  const winId = win.webContents.id;

  win.once('ready-to-show', () => {
    if (!options.cascade && saved.maximized) win.maximize();
    win.show();
    win.focus();
  });

  const notify = (): void => sendMaximizeState(win);
  win.on('maximize', notify);
  win.on('unmaximize', notify);
  win.on('resize', () => {
    void writeWindowState(win);
  });
  win.on('move', () => {
    void writeWindowState(win);
  });

  win.on('close', (event) => {
    if (closeAllowed.has(winId)) return;
    event.preventDefault();
    if (closeRequested.has(winId)) return;
    closeRequested.add(winId);
    win.webContents.send('state:flush-request');
    setTimeout(() => {
      closeAllowed.add(winId);
      if (!win.isDestroyed()) win.close();
    }, 1500);
  });

  win.on('closed', () => {
    closeAllowed.delete(winId);
    closeRequested.delete(winId);
    windows.delete(win);
    if (primaryWindow === win) {
      primaryWindow = [...windows].find((candidate) => !candidate.isDestroyed()) ?? null;
    }
  });

  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) {
      void shell.openExternal(url);
    }
    return { action: 'deny' };
  });

  win.webContents.on('will-navigate', (event, url) => {
    const current = win.webContents.getURL();
    if (url !== current) {
      event.preventDefault();
      if (/^https?:/i.test(url)) void shell.openExternal(url);
    }
  });

  const query: Record<string, string> = {};
  if (options.vaultId) query.vaultId = options.vaultId;
  // Demo fixtures are only used by the regression and screenshot scripts.
  if (demoData) query.demo = '1';
  if (isDev) {
    const url = new URL(process.env.VITE_DEV_SERVER_URL as string);
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
    await win.loadURL(url.toString());
  } else {
    await win.loadFile(
      path.join(__dirname, '../renderer/index.html'),
      Object.keys(query).length > 0 ? { query } : undefined
    );
  }

  return win;
}

/** Keyboard roles live in the application menu even though the menu bar is hidden. */
function installMenu(): void {
  const template: Electron.MenuItemConstructorOptions[] = [
    {
      label: '编辑',
      submenu: [
        { role: 'undo', label: '撤销' },
        { role: 'redo', label: '重做' },
        { type: 'separator' },
        { role: 'cut', label: '剪切' },
        { role: 'copy', label: '复制' },
        { role: 'paste', label: '粘贴' },
        { role: 'selectAll', label: '全选' }
      ]
    }
  ];
  if (isDev) {
    template.push({
      label: '视图',
      submenu: [
        { role: 'reload', label: '重新载入' },
        { role: 'toggleDevTools', label: '开发者工具' },
        { role: 'togglefullscreen', label: '全屏' }
      ]
    });
  }
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ---------------------------------------------------------------------------
// Test / screenshot automation (single primary window)

async function runScriptMode(): Promise<void> {
  const scriptPath = process.env.LEXI_SCRIPT;
  const win = primaryWindow;
  if (!scriptPath || !win) return;
  await new Promise((resolve) => setTimeout(resolve, 1600));
  try {
    const code = await fs.readFile(path.resolve(scriptPath), 'utf8');
    const result = await win.webContents.executeJavaScript(code, true);
    console.log(`SCRIPT_RESULT ${JSON.stringify(result)}`);
  } catch (error) {
    console.error('SCRIPT_ERROR', error);
  }
}

async function runSmokeMode(): Promise<void> {
  const scriptPath = process.env.LEXI_SMOKE_SCRIPT;
  const win = primaryWindow;
  if (!scriptPath || !win) return;
  win.webContents.on('console-message', (_event, level, message) => {
    console.log(`RENDERER[${level}] ${message}`);
  });
  await new Promise((resolve) => setTimeout(resolve, 1600));
  try {
    const snapshot = await win.webContents.executeJavaScript(
      `({ready:document.readyState, root:document.getElementById('root')?.innerHTML.length ?? -1, text:document.body.innerText.slice(0,120)})`
    );
    console.log('RENDERER_SNAPSHOT', JSON.stringify(snapshot));
  } catch (error) {
    console.error('SNAPSHOT_FAILED', error);
  }
  try {
    const code = await fs.readFile(path.resolve(scriptPath), 'utf8');
    const result = await win.webContents.executeJavaScript(code, true);
    try {
      const sampleHtml = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="lexi-asset://katex/katex.min.css"></head><body><h1>PDF Check</h1><p>Formula: \\(\\int_0^1 x^2\\,dx = \\frac{1}{3}\\)</p></body></html>`;
      const pdfBuf = await renderHtmlToPdfBuffer(sampleHtml);
      result.pdfBytes = pdfBuf.length;
      result.pdfHeaderOk = pdfBuf.subarray(0, 5).toString('utf8') === '%PDF-';
    } catch (pdfErr) {
      result.pdfError = String(pdfErr);
      result.pdfHeaderOk = false;
    }
    console.log(`SMOKE_RESULT ${JSON.stringify(result)}`);
  } catch (error) {
    console.error('SMOKE_ERROR', error);
  } finally {
    app.exit(0);
  }
}

async function runScreenshotMode(): Promise<void> {
  const dir = process.env.LEXI_SHOT_DIR;
  const win = primaryWindow;
  if (!dir || !win) return;
  await fs.mkdir(dir, { recursive: true });
  win.webContents.on('console-message', (_event, level, message) => {
    console.log(`RENDERER[${level}] ${message}`);
  });
  await new Promise((resolve) => setTimeout(resolve, 1600));
  try {
    const snapshot = await win.webContents.executeJavaScript(
      `({ready:document.readyState, root:document.getElementById('root')?.innerHTML.length ?? -1, text:document.body.innerText.slice(0,120)})`
    );
    console.log('RENDERER_SNAPSHOT', JSON.stringify(snapshot));
  } catch (error) {
    console.error('SNAPSHOT_FAILED', error);
  }

  const states = (process.env.LEXI_SHOT_STATES || 'workspace').split(',');
  for (const state of states) {
    try {
      await win.webContents.executeJavaScript(
        `window.__lexiShot && window.__lexiShot(${JSON.stringify(state.trim())})`
      );
    } catch (error) {
      console.error('shot state failed', state, error);
    }
    await new Promise((resolve) => setTimeout(resolve, 900));
    await new Promise((resolve) => setTimeout(resolve, 250));
    const image = await win.webContents.capturePage();
    const safeName = state.trim().replace(/[\\/:*?"<>|]/g, '-');
    await fs.writeFile(path.join(dir, `${safeName}.png`), image.toPNG());
  }
  app.exit(0);
}

// ---------------------------------------------------------------------------
// IPC

function registerIpc(): void {
  ipcMain.handle('runtime:info', (): RuntimeInfo => ({
    platform: process.platform,
    arch: process.arch,
    appVersion: app.getVersion(),
    electron: process.versions.electron,
    userDataPath: app.getPath('userData'),
    dataPath: dataFile()
  }));

  ipcMain.handle('state:load', async (): Promise<StateEnvelope> => {
    await ensureMaster();
    return { state: masterState, revision: dataRevision };
  });

  ipcMain.handle(
    'state:save',
    async (
      event,
      payload: {
        state: PersistedState;
        baseRevision: number;
        noteBases?: Record<string, string>;
        dirtyNoteIds?: string[];
      }
    ): Promise<{
      revision: number;
      conflicts?: NoteConflictInfo[];
      historyWarning?: string;
      syncWarning?: string;
    }> => {
      return enqueue(async () => {
        await ensureMaster();
        const incoming = normalizeIncoming(payload?.state);
        const baseRevision = Number(payload?.baseRevision) || 0;
        const historyStore = getHistoryStore();

        if (!masterState) {
          const { syncWarning } = await writeMasterFileState(incoming);
          masterState = incoming;
          dataRevision = Math.max(1, dataRevision);
          await historyStore.clearDraftWal(payload?.dirtyNoteIds ?? incoming.notes.map((n) => n.id)).catch(() => {});
          broadcastState(event.sender.id);
          return { revision: dataRevision, syncWarning };
        }

        const stale = baseRevision < dataRevision;
        const { merged, conflicts, replacedMasterNotes } = mergeWithConflictDetection(
          masterState,
          incoming,
          !stale,
          payload?.noteBases,
          mergeSimple,
          mergeUpdated
        );
        const changed = JSON.stringify(merged) !== JSON.stringify(masterState);
        const workspaceDataChanged =
          changed &&
          (JSON.stringify(merged.notes) !== JSON.stringify(masterState.notes) ||
            JSON.stringify(merged.vaults) !== JSON.stringify(masterState.vaults) ||
            JSON.stringify(merged.projects) !== JSON.stringify(masterState.projects) ||
            JSON.stringify(merged.maps) !== JSON.stringify(masterState.maps) ||
            JSON.stringify(merged.canvases) !== JSON.stringify(masterState.canvases));
        let historyWarning: string | undefined;
        let syncWarning: string | undefined;

        if (changed) {
          try {
            const writeRes = await writeMasterFileState(merged, { skipWorkspaceSync: !workspaceDataChanged });
            syncWarning = writeRes.syncWarning;
          } catch (error) {
            throw new Error(friendlySaveError(error));
          }
          masterState = merged;
          dataRevision += 1;
          const policy = merged.settings?.historyPolicy;
          for (const prevNote of replacedMasterNotes) {
            const res = await historyStore.recordSnapshot(prevNote, 'autosave', policy, false);
            if (res.warning && !historyWarning) historyWarning = res.warning;
          }
          broadcastState(event.sender.id);
        }

        // Preserve conflicting local versions in history so zero user work is lost.
        const policy = masterState.settings?.historyPolicy;
        for (const conflict of conflicts) {
          const res = await historyStore.recordSnapshot(conflict.localNote, 'conflict-backup', policy, true);
          if (res.warning && !historyWarning) historyWarning = res.warning;
        }

        const conflictIds = new Set(conflicts.map((c) => c.noteId));
        const clearIds = (payload?.dirtyNoteIds ?? []).filter((id) => !conflictIds.has(id));
        if (clearIds.length > 0) {
          await historyStore.clearDraftWal(clearIds).catch(() => {});
        }

        if (stale && !event.sender.isDestroyed()) {
          const sender = BrowserWindow.fromWebContents(event.sender);
          if (sender) sendSyncTo(sender);
        }
        return {
          revision: dataRevision,
          conflicts: conflicts.length > 0 ? conflicts : undefined,
          historyWarning,
          syncWarning
        };
      });
    }
  );

  ipcMain.handle('state:replace', async (event, state: PersistedState): Promise<{ revision: number }> => {
    return enqueue(async () => {
      const next = normalizeIncoming(state);
      try {
        await writeMasterFileState(next);
      } catch (error) {
        throw new Error(friendlySaveError(error));
      }
      masterState = next;
      dataRevision += 1;
      broadcastState(event.sender.id);
      return { revision: dataRevision };
    });
  });

  ipcMain.handle('history:list', async (_event, noteId: string): Promise<NoteRevision[]> => {
    return getHistoryStore().getNoteHistory(noteId);
  });

  ipcMain.handle(
    'history:snapshot',
    async (
      _event,
      payload: { note: NoteItem }
    ): Promise<{ revision: NoteRevision | null; revisions: NoteRevision[]; warning?: string }> => {
      await ensureMaster();
      const policy = masterState?.settings?.historyPolicy;
      const store = getHistoryStore();
      const res = await store.recordSnapshot(payload.note, 'manual', policy, true);
      const revisions = await store.getNoteHistory(payload.note.id);
      return { revision: res.revision, revisions, warning: res.warning };
    }
  );

  ipcMain.handle(
    'history:restore',
    async (
      event,
      payload: {
        noteId: string;
        revisionId: string;
        liveDraft?: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'> | null;
      }
    ): Promise<{
      revision: number;
      restoredNote: NoteItem;
      revisions: NoteRevision[];
      warning?: string;
    }> => {
      return enqueue(async () => {
        await ensureMaster();
        if (!masterState) throw new Error('尚未加载知识库数据');
        const idx = masterState.notes.findIndex((n) => n.id === payload.noteId);
        if (idx < 0) throw new Error('笔记不存在');
        const currentSaved = masterState.notes[idx];
        const store = getHistoryStore();
        const result = await store.restoreRevision(
          currentSaved,
          payload.revisionId,
          payload.liveDraft,
          masterState.settings?.historyPolicy
        );
        const nextNotes = masterState.notes.slice();
        nextNotes[idx] = result.restoredNote;
        const nextMaster: PersistedState = { ...masterState, notes: nextNotes };
        try {
          await writeMasterFileState(nextMaster);
        } catch (error) {
          throw new Error(friendlySaveError(error));
        }
        masterState = nextMaster;
        dataRevision += 1;
        await store.clearDraftWal([payload.noteId]).catch(() => {});
        await store.dismissCrashRecovery(payload.noteId).catch(() => {});
        broadcastState(event.sender.id);
        return {
          revision: dataRevision,
          restoredNote: result.restoredNote,
          revisions: result.revisions,
          warning: result.warning
        };
      });
    }
  );

  ipcMain.handle('history:usage', async (): Promise<HistoryUsageSummary> => {
    return getHistoryStore().getUsage();
  });

  ipcMain.handle(
    'history:prune',
    async (_event, policy?: Partial<HistoryRetentionPolicy>): Promise<{ removedCount: number; summary: HistoryUsageSummary }> => {
      await ensureMaster();
      return getHistoryStore().pruneAll(policy ?? masterState?.settings?.historyPolicy);
    }
  );

  ipcMain.handle('history:delete-note', async (_event, noteId: string): Promise<void> => {
    await getHistoryStore().deleteNoteHistory(noteId);
  });

  ipcMain.handle('history:wal-write', async (_event, entry: DraftWalEntry): Promise<void> => {
    await getHistoryStore().writeDraftWal(entry);
  });

  ipcMain.handle('history:wal-clear', async (_event, noteIds: string[]): Promise<void> => {
    await getHistoryStore().clearDraftWal(noteIds);
  });

  ipcMain.handle('history:crash-list', async (): Promise<CrashRecoveryItem[]> => {
    await ensureMaster();
    return getHistoryStore().getPendingCrashRecoveries();
  });

  ipcMain.handle('history:crash-dismiss', async (_event, noteId: string): Promise<void> => {
    await getHistoryStore().dismissCrashRecovery(noteId);
  });

  ipcMain.handle(
    'history:resolve-conflict',
    async (
      event,
      payload: { noteId: string; mode: ConflictResolutionMode; localNote: NoteItem }
    ): Promise<{
      revision: number;
      resolvedNote: NoteItem;
      copyNote?: NoteItem;
    }> => {
      return enqueue(async () => {
        await ensureMaster();
        if (!masterState) throw new Error('尚未加载知识库数据');
        const store = getHistoryStore();
        const policy = masterState.settings?.historyPolicy;
        const idx = masterState.notes.findIndex((n) => n.id === payload.noteId);
        if (idx < 0) throw new Error('原笔记已被删除');
        const remote = masterState.notes[idx];
        const nextNotes = masterState.notes.slice();
        let resolvedNote = remote;
        let copyNote: NoteItem | undefined;

        if (payload.mode === 'use-mine-backup-theirs') {
          await store.recordSnapshot(remote, 'conflict-backup', policy, true);
          resolvedNote = { ...cloneNote(payload.localNote), updatedAt: Date.now() };
          nextNotes[idx] = resolvedNote;
        } else if (payload.mode === 'use-theirs-backup-mine') {
          await store.recordSnapshot(payload.localNote, 'conflict-backup', policy, true);
          resolvedNote = remote;
        } else {
          // 'save-copy': preserve remote on original, save local as standalone copy.
          const copyTitle = `${payload.localNote.title || '未命名笔记'} (冲突副本 ${new Date().toLocaleTimeString('zh-CN', { hour12: false })})`;
          copyNote = {
            ...cloneNote(payload.localNote),
            id: `note-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
            title: copyTitle,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            path: ''
          };
          nextNotes.unshift(copyNote);
          resolvedNote = remote;
        }

        const nextMaster: PersistedState = { ...masterState, notes: nextNotes };
        try {
          await writeMasterFileState(nextMaster);
        } catch (error) {
          throw new Error(friendlySaveError(error));
        }
        masterState = nextMaster;
        dataRevision += 1;
        await store.clearDraftWal([payload.noteId]).catch(() => {});
        broadcastState(event.sender.id);
        return { revision: dataRevision, resolvedNote, copyNote };
      });
    }
  );

  ipcMain.on('state:flush-done', (event) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (!win) return;
    closeAllowed.add(event.sender.id);
    win.close();
  });

  ipcMain.handle('window:minimize', (event) => {
    senderWindow(event)?.minimize();
  });
  ipcMain.handle('window:toggle-maximize', (event) => {
    const win = senderWindow(event);
    if (!win) return false;
    if (win.isMaximized()) win.unmaximize();
    else win.maximize();
    return win.isMaximized();
  });
  ipcMain.handle('window:close', (event) => {
    senderWindow(event)?.close();
  });
  ipcMain.handle('window:is-maximized', (event) => senderWindow(event)?.isMaximized() ?? false);
  ipcMain.handle('window:count', () => windows.size);
  ipcMain.handle('window:probe', async () => {
    const result: { vault: string; notes: number; tabs: number }[] = [];
    for (const win of windows) {
      if (win.isDestroyed()) continue;
      try {
        const probe = await win.webContents.executeJavaScript(
          `({vault: document.querySelector('.vault-name')?.textContent ?? '', notes: document.querySelectorAll('.note-row').length, tabs: document.querySelectorAll('.tab').length})`
        );
        result.push(probe as { vault: string; notes: number; tabs: number });
      } catch {
        // A window that is still loading simply does not report.
      }
    }
    return result;
  });

  ipcMain.handle('window:vaults', async (): Promise<string[]> => {
    // Diagnostic only: lets the smoke test confirm that a new window opened on
    // the requested workspace.
    const names: string[] = [];
    for (const win of windows) {
      if (win.isDestroyed()) continue;
      try {
        const name = await win.webContents.executeJavaScript(
          `document.querySelector('.vault-name')?.textContent ?? ''`
        );
        names.push(String(name));
      } catch {
        names.push('');
      }
    }
    return names;
  });

  ipcMain.handle('workspace:open-window', async (_event, vaultId: string) => {
    await ensureMaster();
    if (masterState && !masterState.vaults.some((vault) => vault.id === vaultId)) return false;
    await createAppWindow({ vaultId, cascade: true });
    return true;
  });

  ipcMain.handle('dialog:choose-folder', async (event): Promise<string | null> => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    const result = await dialog.showOpenDialog(owner, {
      title: '选择文件夹',
      properties: ['openDirectory', 'createDirectory']
    });
    return result.canceled ? null : result.filePaths[0] ?? null;
  });

  ipcMain.handle('export:markdown', async (_event, payload: { files: MarkdownExportFile[]; folder: string }) => {
    const { files, folder } = payload;
    await fs.mkdir(folder, { recursive: true });
    for (const file of files) {
      await fs.writeFile(path.join(folder, file.name), file.content, 'utf8');
    }
    return files.length;
  });

  ipcMain.handle('workspace:resolve-folder', (_event, vault: PersistedState['vaults'][number]) => {
    return resolveVaultFolder(app.getPath('userData'), vault);
  });

  ipcMain.handle('workspace:export-zip', async (event, vault: PersistedState['vaults'][number]) => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    if (masterState) { syncStateToWorkspaceFolders(app.getPath('userData'), masterState); }
    const folderPath = resolveVaultFolder(app.getPath('userData'), vault);
    const files = collectWorkspaceFilesForZip(folderPath);
    const result = await dialog.showSaveDialog(owner, {
      title: '导出工作区压缩包',
      defaultPath: path.join(app.getPath('documents'), `知萤_工作区归档_${new Date().toISOString().slice(0, 10)}.zip`),
      filters: [{ name: 'ZIP 压缩包', extensions: ['zip'] }]
    });
    if (result.canceled || !result.filePath) return null;
    await fs.writeFile(result.filePath, buildZipBuffer(files));
    return { path: result.filePath, count: files.length };
  });

  ipcMain.handle('workspace:import-zip', async (event) => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    const zipPick = await dialog.showOpenDialog(owner, {
      title: '选择工作区压缩包 (.zip)',
      properties: ['openFile'],
      filters: [{ name: 'ZIP 压缩包', extensions: ['zip'] }]
    });
    if (zipPick.canceled || !zipPick.filePaths[0]) return null;
    const dirPick = await dialog.showOpenDialog(owner, {
      title: '选择解压保存文件夹',
      properties: ['openDirectory', 'createDirectory']
    });
    if (dirPick.canceled || !dirPick.filePaths[0]) return null;
    const destFolder = dirPick.filePaths[0];
    const fileCount = extractZipToFolder(zipPick.filePaths[0], destFolder);
    const folderName = path.basename(destFolder) || '工作区';
    const vaultId = `vault-${Date.now()}`;
    const scanned = scanWorkspaceFolder(destFolder, vaultId);
    return {
      folderPath: destFolder,
      folderName: scanned.vaultName || folderName,
      description: scanned.description || '',
      vaultId,
      fileCount,
      notes: scanned.notes,
      maps: scanned.maps,
      canvases: scanned.canvases,
      warnings: scanned.warnings
    };
  });

  ipcMain.handle('workspace:scan-folder', (_event, payload: { folderPath: string; vaultId: string }) => {
    return scanWorkspaceFolder(payload.folderPath, payload.vaultId);
  });

  ipcMain.handle('settings:export-json', async (event, settingsPayload: Record<string, unknown>) => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    const catalog = getPluginService().snapshot();
    const payload = {
      format: 'LexiNote.SettingsPlugins',
      version: 1,
      exportedAt: Date.now(),
      settings: settingsPayload,
      plugins: catalog.records.map((p) => ({
        id: p.id,
        name: p.name,
        version: p.version,
        kind: p.kind,
        grantedCapabilities: p.grantedCapabilities
      })),
      enabledByVault: catalog.enabledByVault
    };
    const result = await dialog.showSaveDialog(owner, {
      title: '导出设置与插件合集',
      defaultPath: path.join(app.getPath('documents'), `知萤_设置与插件_${new Date().toISOString().slice(0, 10)}.json`),
      filters: [{ name: '设置与插件 JSON', extensions: ['json'] }]
    });
    if (result.canceled || !result.filePath) return null;
    await fs.writeFile(result.filePath, JSON.stringify(payload, null, 2), 'utf8');
    return result.filePath;
  });

  ipcMain.handle('settings:import-json', async (event) => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    const pick = await dialog.showOpenDialog(owner, {
      title: '导入设置与插件合集',
      properties: ['openFile'],
      filters: [{ name: '设置与插件 JSON', extensions: ['json'] }]
    });
    if (pick.canceled || !pick.filePaths[0]) return null;
    const raw = await fs.readFile(pick.filePaths[0], 'utf8');
    const parsed = JSON.parse(raw) as { format?: string; settings?: Record<string, unknown> };
    if (!parsed || parsed.format !== 'LexiNote.SettingsPlugins') {
      throw new Error('不是有效的知萤设置与插件备份文件');
    }
    return parsed.settings ?? {};
  });

  ipcMain.handle('export:backup', async (event, payload: { content: string; suggestedName: string }) => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return null;
    const result = await dialog.showSaveDialog(owner, {
      title: '导出完整备份',
      defaultPath: path.join(app.getPath('documents'), payload.suggestedName),
      filters: [{ name: 'LexiNote 备份', extensions: ['json'] }]
    });
    if (result.canceled || !result.filePath) return null;
    await fs.writeFile(result.filePath, payload.content, 'utf8');
    return result.filePath;
  });

  ipcMain.handle(
    'export:text',
    async (event, payload: { content: string; suggestedName: string; filters: Electron.FileFilter[] }) => {
      const owner = senderWindow(event) ?? primaryWindow;
      if (!owner) return null;
      const result = await dialog.showSaveDialog(owner, {
        title: '导出文件',
        defaultPath: path.join(app.getPath('documents'), payload.suggestedName),
        filters: payload.filters
      });
      if (result.canceled || !result.filePath) return null;
      await fs.writeFile(result.filePath, payload.content, 'utf8');
      return result.filePath;
    }
  );

  ipcMain.handle(
    'export:pdf',
    async (event, payload: { html: string; suggestedName: string }) => {
      const owner = senderWindow(event) ?? primaryWindow;
      if (!owner) return { canceled: true };
      const cleanName = (payload.suggestedName || '笔记').replace(/[\\/:*?"<>|]/g, '-');
      const defaultName = cleanName.toLowerCase().endsWith('.pdf') ? cleanName : `${cleanName}.pdf`;
      const result = await dialog.showSaveDialog(owner, {
        title: '导出为 PDF',
        defaultPath: path.join(app.getPath('documents'), defaultName),
        filters: [{ name: 'PDF 文档', extensions: ['pdf'] }]
      });
      if (result.canceled || !result.filePath) return { canceled: true };
      const targetPath = result.filePath.toLowerCase().endsWith('.pdf')
        ? result.filePath
        : `${result.filePath}.pdf`;
      const pdfBuffer = await renderHtmlToPdfBuffer(payload.html);
      await fs.writeFile(targetPath, pdfBuffer);
      return { canceled: false, path: targetPath, fileName: path.basename(targetPath) };
    }
  );

  ipcMain.handle('files:consume-external', async (): Promise<ImportedFile[]> => {
    if (pendingExternalPaths.length === 0) return [];
    const batch = pendingExternalPaths.splice(0, pendingExternalPaths.length);
    return await readExternalImportedFiles(batch);
  });

  ipcMain.handle('import:files', async (event): Promise<ImportedFile[]> => {
    const owner = senderWindow(event) ?? primaryWindow;
    if (!owner) return [];
    const result = await dialog.showOpenDialog(owner, {
      title: '导入或打开文件',
      properties: ['openFile', 'multiSelections'],
      filters: [
        { name: 'Markdown / JSON', extensions: ['md', 'markdown', 'txt', 'json'] }
      ]
    });
    if (result.canceled) return [];
    return await readExternalImportedFiles(result.filePaths);
  });

  ipcMain.handle(
    'attachment:import',
    async (
      event,
      payload: {
        vaultId: string;
        notebook?: string;
        notePath?: string;
        filePath?: string;
        fileName?: string;
        base64?: string;
      }
    ): Promise<ImportedAttachment | null> => {
      const owner = senderWindow(event) ?? primaryWindow;
      const vault = masterState?.vaults.find((v) => v.id === payload.vaultId);
      if (!vault) return null;
      const vaultRoot = resolveVaultFolder(app.getPath('userData'), vault);
      const attachmentsDir = path.join(vaultRoot, 'attachments');
      await fs.mkdir(attachmentsDir, { recursive: true });

      let sourcePath = payload.filePath;
      let rawBuffer: Buffer | null = null;
      let origName = payload.fileName || 'attachment.png';

      if (payload.base64) {
        const cleanB64 = payload.base64.replace(/^data:[^;]+;base64,/, '');
        rawBuffer = Buffer.from(cleanB64, 'base64');
      } else if (!sourcePath) {
        if (!owner) return null;
        const pick = await dialog.showOpenDialog(owner, {
          title: '选择图片或附件',
          properties: ['openFile'],
          filters: [
            { name: '图片与附件', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'pdf', 'txt', 'md', 'zip'] }
          ]
        });
        if (pick.canceled || !pick.filePaths[0]) return null;
        sourcePath = pick.filePaths[0];
        origName = path.basename(sourcePath);
      } else {
        origName = path.basename(sourcePath);
      }

      const ext = path.extname(origName);
      const base = path.basename(origName, ext).replace(/[\\/:*?"<>|]/g, '_').trim() || 'file';
      let targetName = `${base}${ext}`;
      let counter = 1;
      while (existsSync(path.join(attachmentsDir, targetName))) {
        targetName = `${base}-${counter++}${ext}`;
      }
      const destPath = path.join(attachmentsDir, targetName);
      if (rawBuffer) {
        await fs.writeFile(destPath, rawBuffer);
      } else if (sourcePath) {
        await fs.copyFile(sourcePath, destPath);
      } else {
        return null;
      }

      const noteDir = payload.notePath
        ? path.dirname(payload.notePath)
        : payload.notebook && payload.notebook !== '默认'
          ? path.join(vaultRoot, payload.notebook.replace(/[\\/:*?"<>|]/g, '_'))
          : vaultRoot;
      const relPath = path.relative(noteDir, destPath).split(path.sep).join('/');
      const isImage = /\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(targetName);
      return { relativePath: relPath, fileName: targetName, isImage };
    }
  );

  ipcMain.handle('shell:open-external', async (_event, url: string) => {
    if (/^(https?:|mailto:)/i.test(url)) await shell.openExternal(url);
  });

  ipcMain.handle('shell:show-item', async (_event, target: string) => {
    if (!target) {
      shell.showItemInFolder(dataFile());
      return;
    }
    shell.showItemInFolder(target);
  });

  ipcMain.handle('clipboard:write-text', (_event, text: string) => {
    clipboard.writeText(text);
  });

  // Plugin host IPC
  ipcMain.handle('plugin:list', () => runPluginOp(() => getPluginService().snapshot()));

  ipcMain.handle('plugin:pick-install-zip', async (event): Promise<PluginInstallResult> => {
    const win = BrowserWindow.fromWebContents(event.sender) ?? primaryWindow ?? undefined;
    const dialogOpts: Electron.OpenDialogOptions = {
      title: '选择 LexiNote / Obsidian 插件 ZIP 包',
      properties: ['openFile'],
      filters: [{ name: 'ZIP 插件包', extensions: ['zip'] }]
    };
    const picked = win ? await dialog.showOpenDialog(win, dialogOpts) : await dialog.showOpenDialog(dialogOpts);
    if (picked.canceled || !picked.filePaths[0]) {
      return { ok: false, cancelled: true, pluginId: '', record: null, error: '', warnings: [] };
    }
    const result = getPluginService().installFromZip(picked.filePaths[0]);
    if (result.ok) { broadcastPluginCatalog(); }
    return result;
  });

  ipcMain.handle('plugin:pick-install-folder', async (event): Promise<PluginInstallResult> => {
    const win = BrowserWindow.fromWebContents(event.sender) ?? primaryWindow ?? undefined;
    const dialogOpts: Electron.OpenDialogOptions = {
      title: '选择已解压的 LexiNote / Obsidian 插件文件夹',
      properties: ['openDirectory']
    };
    const picked = win ? await dialog.showOpenDialog(win, dialogOpts) : await dialog.showOpenDialog(dialogOpts);
    if (picked.canceled || !picked.filePaths[0]) {
      return { ok: false, cancelled: true, pluginId: '', record: null, error: '', warnings: [] };
    }
    const result = getPluginService().installFromDirectory(picked.filePaths[0]);
    if (result.ok) { broadcastPluginCatalog(); }
    return result;
  });

  ipcMain.handle('plugin:install-zip-path', (_event, zipPath: string): PluginInstallResult => {
    const result = getPluginService().installFromZip(zipPath);
    if (result.ok) { broadcastPluginCatalog(); }
    return result;
  });

  ipcMain.handle('plugin:install-folder-path', (_event, dirPath: string): PluginInstallResult => {
    const result = getPluginService().installFromDirectory(dirPath);
    if (result.ok) { broadcastPluginCatalog(); }
    return result;
  });

  ipcMain.handle('plugin:uninstall', (_event, payload: { pluginId: string; keepData?: boolean }) =>
    runPluginOp(() => {
      const snap = getPluginService().uninstallPlugin(payload.pluginId, payload.keepData === true);
      broadcastPluginCatalog();
      return snap;
    })
  );

  ipcMain.handle('plugin:boot-assets', (_event, payload: { pluginId: string; vaultId: string }) =>
    runPluginOp(() => getPluginService().readBootAssets(payload.pluginId, payload.vaultId))
  );

  ipcMain.handle('plugin:set-enabled', (_event, payload: { vaultId: string; pluginId: string; enabled: boolean }) =>
    runPluginOp(() => {
      const next = getPluginService().setPluginEnabled(payload.vaultId, payload.pluginId, payload.enabled);
      broadcastPluginCatalog();
      return next;
    })
  );

  ipcMain.handle('plugin:grant-capability', (_event, payload: { pluginId: string; capability: string }) =>
    runPluginOp(() => {
      const next = getPluginService().grantCapability(payload.pluginId, payload.capability);
      broadcastPluginCatalog();
      return next;
    })
  );

  ipcMain.handle('plugin:revoke-capability', (_event, payload: { pluginId: string; capability: string }) =>
    runPluginOp(() => {
      const next = getPluginService().revokeCapability(payload.pluginId, payload.capability);
      broadcastPluginCatalog();
      return next;
    })
  );

  ipcMain.handle('plugin:grant-all-capabilities', (_event, pluginId: string) =>
    runPluginOp(() => {
      const next = getPluginService().grantAllCapabilities(pluginId);
      broadcastPluginCatalog();
      return next;
    })
  );

  ipcMain.handle('plugin:revoke-all-capabilities', (_event, pluginId: string) =>
    runPluginOp(() => {
      const next = getPluginService().revokeAllCapabilities(pluginId);
      broadcastPluginCatalog();
      return next;
    })
  );

  ipcMain.handle('plugin:storage-get', (_event, payload: { pluginId: string; vaultId: string; key: string }) =>
    runPluginOp(() => getPluginService().kvGet(payload.pluginId, payload.vaultId, payload.key))
  );

  ipcMain.handle('plugin:storage-set', (_event, payload: { pluginId: string; vaultId: string; key: string; value: string }) =>
    runPluginOp(() => getPluginService().kvSet(payload.pluginId, payload.vaultId, payload.key, payload.value))
  );

  ipcMain.handle('plugin:storage-remove', (_event, payload: { pluginId: string; vaultId: string; key: string }) =>
    runPluginOp(() => getPluginService().kvRemove(payload.pluginId, payload.vaultId, payload.key))
  );

  ipcMain.handle('plugin:ai-status', (_event, pluginId: string) =>
    runPluginOp(() => getPluginService().ai.statusFor(pluginId))
  );

  ipcMain.handle('plugin:ai-configure', (_event, payload: { pluginId: string; params: Record<string, unknown> }) =>
    runPluginOp(() => getPluginService().ai.configureFor(payload.pluginId, payload.params))
  );

  ipcMain.handle('plugin:ai-chat', (_event, payload: { pluginId: string; params: Record<string, unknown> }) =>
    runPluginOp(() => getPluginService().ai.chatFor(payload.pluginId, payload.params))
  );

  ipcMain.handle('plugin:ai-models', (_event, pluginId: string) =>
    runPluginOp(() => getPluginService().ai.modelsFor(pluginId))
  );

  ipcMain.handle('plugin:ai-balance', (_event, pluginId: string) =>
    runPluginOp(() => getPluginService().ai.balanceFor(pluginId))
  );

  ipcMain.handle('plugin:open-folder', async () => {
    const dir = getPluginService().pluginsDir;
    await fs.mkdir(dir, { recursive: true });
    await shell.openPath(dir);
  });
}

// A second instance would race the first one on the same JSON document.
const hasSingleInstanceLock = app.requestSingleInstanceLock();
if (!hasSingleInstanceLock) {
  app.quit();
} else {
  pendingExternalPaths.push(...extractOpenableFileArgs(process.argv));
  app.on('open-file', (event, filePath) => {
    event.preventDefault();
    if (OPENABLE_EXT_RE.test(filePath)) {
      void deliverExternalFiles([filePath]);
    }
  });
  app.on('second-instance', (_event, argv) => {
    const incoming = extractOpenableFileArgs(argv);
    if (incoming.length > 0) void deliverExternalFiles(incoming);
    if (!primaryWindow) return;
    if (primaryWindow.isMinimized()) primaryWindow.restore();
    primaryWindow.show();
    primaryWindow.focus();
  });
}

app.whenReady().then(async () => {
  if (!hasSingleInstanceLock) return;
  protocol.handle('lexi-asset', (request) => {
    try {
      const url = new URL(request.url);
      if (url.hostname === 'katex') {
        const katexRoot = path.resolve(resolveKatexDir());
        const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '');
        const resolved = path.resolve(katexRoot, rel);
        if ((resolved === katexRoot || resolved.startsWith(katexRoot + path.sep)) && existsSync(resolved)) {
          return net.fetch(pathToFileURL(resolved).toString());
        }
        return new Response('Not found', { status: 404 });
      }
      if (url.hostname === 'pdf-doc') {
        const token = url.pathname.replace(/^\/+/, '');
        const docHtml = pendingPdfDocs.get(token);
        if (typeof docHtml === 'string') {
          return new Response(docHtml, { headers: { 'content-type': 'text/html; charset=utf-8' } });
        }
        return new Response('Not found', { status: 404 });
      }
      const vaultId = url.searchParams.get('vaultId') ?? '';
      const src = url.searchParams.get('src') ?? '';
      const notebook = url.searchParams.get('notebook') ?? '默认';
      const notePath = url.searchParams.get('notePath') ?? '';
      const vault = masterState?.vaults.find((v) => v.id === vaultId);
      if (!vault || !src) return new Response('Not found', { status: 404 });

      const vaultRoot = path.resolve(resolveVaultFolder(app.getPath('userData'), vault));
      const cleanSrc = decodeURIComponent(src).replace(/^file:\/\//i, '');
      const noteDir = notePath
        ? path.dirname(notePath)
        : notebook && notebook !== '默认'
          ? path.join(vaultRoot, notebook.replace(/[\\/:*?"<>|]/g, '_'))
          : vaultRoot;

      const candidates = [
        path.resolve(noteDir, cleanSrc),
        path.resolve(vaultRoot, cleanSrc),
        path.resolve(vaultRoot, cleanSrc.replace(/^(\.\.\/)+/, ''))
      ];
      for (const candidate of candidates) {
        if ((candidate === vaultRoot || candidate.startsWith(vaultRoot + path.sep)) && existsSync(candidate)) {
          return net.fetch(pathToFileURL(candidate).toString());
        }
      }
      return new Response('Not found', { status: 404 });
    } catch {
      return new Response('Bad request', { status: 400 });
    }
  });
  installMenu();
  registerIpc();
  await ensureMaster();
  await createAppWindow();
  if (process.env.LEXI_SHOT_DIR) {
    void runScreenshotMode();
  } else if (process.env.LEXI_SMOKE_SCRIPT) {
    void runSmokeMode();
  } else if (process.env.LEXI_SCRIPT) {
    void runScriptMode();
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' || process.env.LEXI_SHOT_DIR || process.env.LEXI_AUTOCLOSE_EXIT) {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    void createAppWindow();
  }
});
