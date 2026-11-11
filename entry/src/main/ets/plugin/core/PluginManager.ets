import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LexiStorageService } from '../../core/LexiStorageService';
import {
  PluginCoreEvent,
  PluginInstallResult,
  PluginKind,
  PluginRecord,
  PluginState,
  PluginWorkspaceSnapshot
} from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginRuntimeBoot } from '../model/PluginContracts';
import { LexiEditorBridge, PluginEditorHandle } from '../adapters/LexiEditorBridge';
import { LexiPathRegistry } from '../adapters/LexiPathRegistry';
import { LexiVaultAdapter } from '../adapters/LexiVaultAdapter';
import { LexiWorkspaceBridge } from '../adapters/LexiWorkspaceBridge';
import { PluginCommandRegistry } from './PluginCommandRegistry';
import { PluginViewRegistry } from './PluginViewRegistry';
import { PluginDataStore } from './PluginDataStore';
import { PluginEventBus } from './PluginEventBus';
import { PluginPermissionService } from './PluginPermissionService';
import { PluginRegistry } from './PluginRegistry';
import { PluginResourceTracker } from './PluginResourceTracker';
import { PluginInstallService } from '../runtime/PluginInstallService';
import { PluginRpcDispatcher, PluginHostUi, PluginSession } from '../runtime/PluginRpcDispatcher';
import { PluginRuntimeController } from '../runtime/PluginRuntimeHost';
import { PluginRuntimeState } from '../runtime/PluginRuntimeMessages';

/** Optional UI hooks. Without them, plugin UI calls fail loudly instead of pretending. */
export class PluginUiBridge {
  notice: (message: string, timeoutMs: number) => void = (_message: string, _timeout: number): void => {};
  confirm: (title: string, body: string) => Promise<boolean> =
    async (_title: string, _body: string): Promise<boolean> => false;
  openFile: (noteId: string) => void = (_noteId: string): void => {};
  hasConfirm: boolean = false;
}

export class PluginNoticeRecord {
  pluginId: string = '';
  message: string = '';
  at: number = 0;
}

/**
 * Facade used by the UI (P08/P10).
 *
 * Owns the plugin lifecycle, the RPC session, capability checks and diagnostics. Plugin
 * code never sees this class; it only sees the RPC surface.
 */
export class PluginManager {
  private static context: common.Context | undefined = undefined;
  private static initialized: boolean = false;
  private static initializing: Promise<void> | undefined = undefined;
  private static session: PluginSession | undefined = undefined;
  private static activePluginId: string = '';
  private static uiBridge: PluginUiBridge = new PluginUiBridge();
  private static notices: PluginNoticeRecord[] = [];
  private static diagnostics: Map<string, string[]> = new Map<string, string[]>();
  private static changeRevision: number = 0;
  private static workspaceId: string = '';
  private static lifecycle: Promise<void> = Promise.resolve();

  private static serialize<T>(operation: () => Promise<T>): Promise<T> {
    const task = PluginManager.lifecycle.catch((): void => {}).then(operation);
    PluginManager.lifecycle = task.then((): void => {}, (): void => {});
    return task;
  }

  static async init(context: common.Context): Promise<void> {
    if (PluginManager.initialized) { return; }
    if (PluginManager.initializing) { return PluginManager.initializing; }
    PluginManager.initializing = PluginManager.bootstrap(context);
    try {
      await PluginManager.initializing;
    } finally {
      PluginManager.initializing = undefined;
    }
  }

  private static async bootstrap(context: common.Context): Promise<void> {
    PluginManager.context = context;
    PluginManager.workspaceId = await LexiStorageService.getActiveVaultId();
    PluginRpcDispatcher.setContext(context);
    PluginPermissionService.resetCache();
    try {
      await PluginRegistry.load();
    } catch (error) {
      PluginManager.note('boot', `插件清单读取失败：${PluginErrors.messageOf(error)}`);
    }
    PluginManager.initialized = true;
    PluginManager.bump();
  }

  static isInitialized(): boolean {
    return PluginManager.initialized;
  }

  static setUiBridge(bridge: PluginUiBridge): void {
    PluginManager.uiBridge = bridge;
  }

  static runtimeState(): string {
    return PluginRuntimeController.state();
  }

  static requestRuntime(): void {
    try { AppStorage.setOrCreate<boolean>('lexiPluginRuntimeNeeded', true); } catch (error) { /* non UI */ }
  }

  private static note(pluginId: string, message: string): void {
    const list = PluginManager.diagnostics.get(pluginId);
    const entry = `${new Date().toISOString()} ${message}`;
    if (list) {
      list.push(entry);
      if (list.length > 40) { list.shift(); }
    } else {
      PluginManager.diagnostics.set(pluginId, [entry]);
    }
  }

  static diagnosticsOf(pluginId: string): string[] {
    const list = PluginManager.diagnostics.get(pluginId);
    return list ? list.slice(0) : [];
  }

  static recentNotices(): PluginNoticeRecord[] {
    return PluginManager.notices.slice(0);
  }

  static revision(): number {
    return PluginManager.changeRevision;
  }

  private static bump(): void {
    PluginManager.changeRevision++;
    try { AppStorage.setOrCreate<number>('lexiPluginRevision', PluginManager.changeRevision); } catch (error) { /* non UI */ }
  }

  static records(): PluginRecord[] {
    return PluginRegistry.list();
  }

  static async refreshInstalled(): Promise<void> {
    return PluginManager.serialize<void>(async (): Promise<void> => {
      if (!PluginManager.initialized) { return; }
      const active = PluginRegistry.get(PluginManager.activePluginId);
      await PluginRegistry.load(true);
      const refreshed = active ? PluginRegistry.get(active.id) : undefined;
      if (active && (!refreshed || refreshed.version !== active.version || refreshed.directory !== active.directory ||
        refreshed.main !== active.main)) {
        await PluginRuntimeController.unload();
        PluginManager.releasePlugin(active.id);
      }
      PluginPermissionService.resetCache();
      await PluginManager.restoreInWorkspace();
      PluginManager.bump();
    });
  }

  static record(pluginId: string): PluginRecord | undefined {
    return PluginRegistry.get(pluginId);
  }

  static activeId(): string {
    return PluginManager.activePluginId;
  }

  private static requireContext(): common.Context {
    if (!PluginManager.context) {
      throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件系统尚未初始化');
    }
    return PluginManager.context;
  }

  // ---------------------------------------------------------------- installation

  /** Opens the system file picker and installs the selected `.zip`. */
  static async installFromPicker(): Promise<PluginInstallResult> {
    const context = PluginManager.requireContext();
    const result = new PluginInstallResult();
    let uri = '';
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.zip'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const selected = await documentPicker.select(options);
      if (!selected || selected.length === 0) {
        result.error = `${PluginErrorCode.CANCELLED}: 已取消选择`;
        return result;
      }
      uri = selected[0];
    } catch (error) {
      result.error = `${PluginErrorCode.CANCELLED}: ${PluginErrors.messageOf(error)}`;
      return result;
    }
    const installed = await PluginInstallService.installZip(context, uri);
    PluginManager.note(installed.pluginId || 'install', installed.ok
      ? `已安装 ${installed.pluginId}`
      : `安装被拒绝：${installed.error}`);
    PluginManager.bump();
    return installed;
  }

  // ---------------------------------------------------------------- lifecycle

  private static buildHostUi(record: PluginRecord): PluginHostUi {
    const host = new PluginHostUi();
    host.notice = (message: string, timeoutMs: number): void => {
      const notice = new PluginNoticeRecord();
      notice.pluginId = record.id;
      notice.message = message;
      notice.at = Date.now();
      PluginManager.notices.push(notice);
      if (PluginManager.notices.length > 20) { PluginManager.notices.shift(); }
      try { PluginManager.uiBridge.notice(message, timeoutMs); } catch (error) { /* UI optional */ }
      PluginManager.bump();
    };
    host.confirm = async (title: string, body: string): Promise<boolean> => {
      if (!PluginManager.uiBridge.hasConfirm) {
        throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, '当前版本未提供确认对话框');
      }
      return PluginManager.uiBridge.confirm(title, body);
    };
    host.openFile = (noteId: string): void => {
      try { PluginManager.uiBridge.openFile(noteId); } catch (error) { /* UI optional */ }
    };
    host.invokeCommand = (qualifiedId: string): void => {
      PluginRuntimeController.runCommand(qualifiedId).catch((error: Error): void => {
        PluginManager.note(record.id, `命令执行失败：${PluginErrors.messageOf(error)}`);
      });
    };
    return host;
  }

  private static async buildBoot(record: PluginRecord, session: PluginSession): Promise<PluginRuntimeBoot> {
    const context = PluginManager.requireContext();
    const boot = new PluginRuntimeBoot();
    boot.pluginId = record.id;
    boot.kind = record.kind;
    boot.token = session.token;
    boot.capabilities = session.capabilities.slice(0);
    boot.vaultId = session.vaultId;
    boot.manifestJson = await PluginInstallService.readManifestJson(context, record);
    boot.sourceCode = await PluginInstallService.readSource(context, record);
    boot.sourceName = record.main;
    try {
      boot.stylesCss = PluginInstallService.readFileText(`${record.directory}/styles.css`);
    } catch (error) { boot.stylesCss = ''; }
    boot.dataJson = await PluginDataStore.snapshot(record.id, session.vaultId);
    boot.settingsJson = await PluginDataStore.get(record.id, 'plugin-data', session.vaultId);
    if (boot.settingsJson.length === 0) { boot.settingsJson = 'null'; }
    try {
      const files = await LexiVaultAdapter.listMarkdown(session.vaultId);
      boot.filesJson = JSON.stringify(files);
    } catch (error) {
      boot.filesJson = '[]';
      boot.warnings.push(`无法读取知识库文件列表：${PluginErrors.messageOf(error)}`);
    }
    const handle = LexiEditorBridge.active();
    if (handle && handle.noteId.length > 0) {
      try {
        const ref = await LexiVaultAdapter.getById(handle.vaultId, handle.noteId);
        boot.activeFileJson = ref ? JSON.stringify(ref) : 'null';
      } catch (error) {
        boot.activeFileJson = 'null';
      }
      const draft = handle.draft();
      boot.editorJson = JSON.stringify(draft);
    } else {
      boot.activeFileJson = 'null';
      boot.editorJson = 'null';
    }
    boot.runtimeVersion = record.runtimeVersion;
    return boot;
  }

  static async enable(pluginId: string): Promise<PluginRecord> {
    return PluginManager.serialize<PluginRecord>(async (): Promise<PluginRecord> => PluginManager.enableInWorkspace(pluginId));
  }

  private static async enableInWorkspace(pluginId: string): Promise<PluginRecord> {
    const context = PluginManager.requireContext();
    const record = PluginRegistry.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    if (record.state === PluginState.ACTIVE) { return record; }
    if (PluginManager.activePluginId.length > 0 && PluginManager.activePluginId !== pluginId) {
      // One runtime instance per window in the MVP.
      await PluginManager.disableInWorkspace(PluginManager.activePluginId, true);
    }
    await PluginRegistry.setState(pluginId, PluginState.STARTING);
    PluginManager.bump();
    try {
      if (!PluginRuntimeController.isReady()) {
        throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE,
          '插件运行时尚未就绪（请稍后重试）');
      }
      const granted = await PluginPermissionService.granted(pluginId);
      const capabilities = granted.filter((capability: string): boolean =>
        record.requestedCapabilities.includes(capability));
      const session = new PluginSession();
      session.pluginId = pluginId;
      session.kind = record.kind;
      session.token = util.generateRandomUUID(true);
      session.capabilities = capabilities;
      session.vaultScopes = record.vaultScopes.slice(0);
      session.ui = PluginManager.buildHostUi(record);
      session.emitToRuntime = (eventJson: string): void => {
        PluginRuntimeController.sendEvent(eventJson).catch((): void => {});
      };
      let vaultId = await LexiStorageService.getActiveVaultId();
      if (!vaultId) {
        const vaults = await LexiStorageService.getVaults(true);
        vaultId = vaults.length > 0 ? vaults[0].id : '';
      }
      session.vaultId = vaultId;
      if (vaultId) {
        await LexiPathRegistry.ensureFresh(vaultId, 0);
        const snapshot = new PluginWorkspaceSnapshot();
        snapshot.windowId = 'main';
        snapshot.vaultId = vaultId;
        const handle = LexiEditorBridge.active();
        if (handle) {
          snapshot.activeEditorId = handle.editorId;
          snapshot.activeFileId = handle.noteId;
        }
        LexiWorkspaceBridge.publish(snapshot);
      }
      const boot = await PluginManager.buildBoot(record, session);
      await PluginRuntimeController.boot(boot, session);
      PluginManager.session = session;
      PluginManager.activePluginId = pluginId;
      await PluginRegistry.setState(pluginId, PluginState.ACTIVE);
      await LexiStorageService.setPluginEnabled(pluginId, true, PluginManager.workspaceId);
      PluginCommandRegistry.setAvailable(pluginId, true);
      PluginManager.note(pluginId, '已启用');
      PluginManager.bump();
      return PluginRegistry.get(pluginId) as PluginRecord;
    } catch (error) {
      await PluginRuntimeController.unload();
      const message = `${PluginErrors.codeOf(error) === PluginErrorCode.UNKNOWN
        ? PluginErrorCode.PLUGIN_FAILED : PluginErrors.codeOf(error)}: ${PluginErrors.messageOf(error)}`;
      PluginManager.releasePlugin(pluginId);
      try { await PluginRegistry.setState(pluginId, PluginState.FAILED, message); } catch (inner) {
        await PluginRegistry.setError(pluginId, message);
      }
      PluginManager.note(pluginId, `启用失败：${message}`);
      PluginManager.bump();
      throw new Error(message);
    }
  }

  private static releasePlugin(pluginId: string): void {
    PluginEventBus.unsubscribePlugin(pluginId);
    PluginCommandRegistry.unregisterPlugin(pluginId);
    PluginViewRegistry.releasePlugin(pluginId);
    PluginResourceTracker.releaseAll(pluginId);
    if (PluginManager.activePluginId === pluginId) {
      PluginManager.session = undefined;
      PluginManager.activePluginId = '';
    }
  }

  static async disable(pluginId: string): Promise<PluginRecord | undefined> {
    return PluginManager.serialize<PluginRecord | undefined>(async (): Promise<PluginRecord | undefined> =>
      PluginManager.disableInWorkspace(pluginId, true));
  }

  private static async disableInWorkspace(pluginId: string, remember: boolean): Promise<PluginRecord | undefined> {
    const record = PluginRegistry.get(pluginId);
    if (!record) { return undefined; }
    if (remember) { await LexiStorageService.setPluginEnabled(pluginId, false, PluginManager.workspaceId); }
    if (record.state === PluginState.INSTALLED_DISABLED) { return record; }
    if (record.state === PluginState.ACTIVE) {
      await PluginRegistry.setState(pluginId, PluginState.STOPPING);
      try {
        await PluginRuntimeController.unload();
      } catch (error) {
        PluginManager.note(pluginId, `onunload 异常：${PluginErrors.messageOf(error)}`);
      }
    }
    PluginManager.releasePlugin(pluginId);
    try {
      await PluginRegistry.setState(pluginId, PluginState.INSTALLED_DISABLED);
    } catch (error) {
      await PluginRegistry.setError(pluginId, PluginErrors.messageOf(error));
    }
    PluginManager.note(pluginId, '已停用，事件/命令/资源已释放');
    PluginManager.bump();
    return PluginRegistry.get(pluginId);
  }

  /** Stop the previous runtime without changing the workspace's saved switch. */
  static async suspendWorkspace(): Promise<void> {
    return PluginManager.serialize<void>(async (): Promise<void> => {
      if (PluginManager.activePluginId) { await PluginManager.disableInWorkspace(PluginManager.activePluginId, false); }
    });
  }

  static async changeWorkspace(vaultId: string): Promise<void> {
    return PluginManager.serialize<void>(async (): Promise<void> => {
      if (!PluginManager.initialized) { return; }
      if (PluginManager.workspaceId === vaultId) { await PluginManager.restoreInWorkspace(); return; }
      if (PluginManager.activePluginId) { await PluginManager.disableInWorkspace(PluginManager.activePluginId, false); }
      PluginRegistry.reset();
      PluginPermissionService.resetCache();
      await PluginRegistry.load();
      PluginManager.workspaceId = vaultId;
      await PluginManager.restoreInWorkspace();
      PluginManager.bump();
    });
  }

  static async restoreWorkspace(): Promise<void> {
    return PluginManager.serialize<void>(async (): Promise<void> => PluginManager.restoreInWorkspace());
  }

  private static async restoreInWorkspace(): Promise<void> {
    if (!PluginManager.initialized || !PluginRuntimeController.isReady()) { return; }
    const enabled = await LexiStorageService.getEnabledPlugins(PluginManager.workspaceId);
    if (PluginManager.activePluginId && !enabled.includes(PluginManager.activePluginId)) {
      await PluginManager.disableInWorkspace(PluginManager.activePluginId, false);
    }
    for (const id of enabled) {
      const record = PluginRegistry.get(id);
      if (!record || record.state === PluginState.ACTIVE) { continue; }
      try { await PluginManager.enableInWorkspace(id); }
      catch (error) { PluginManager.note(id, `恢复工作区插件失败：${PluginErrors.messageOf(error)}`); }
    }
  }

  static async uninstall(pluginId: string, keepData: boolean = false): Promise<void> {
    const record = PluginRegistry.get(pluginId);
    if (!record) { return; }
    if (record.state === PluginState.ACTIVE) { await PluginManager.disable(pluginId); }
    await PluginInstallService.uninstall(PluginManager.requireContext(), pluginId);
    PluginEventBus.unsubscribePlugin(pluginId);
    PluginCommandRegistry.unregisterPlugin(pluginId);
    PluginResourceTracker.releaseAll(pluginId);
    await PluginPermissionService.clearAll(pluginId);
    if (!keepData) { await PluginDataStore.clear(pluginId); }
    PluginManager.diagnostics.delete(pluginId);
    PluginManager.note(pluginId, keepData ? '已卸载（保留插件设置）' : '已卸载');
    PluginManager.bump();
  }

  // ---------------------------------------------------------------- permissions

  static async grant(pluginId: string, capability: string): Promise<string[]> {
    const record = PluginRegistry.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    const granted = await PluginPermissionService.grant(pluginId, capability, record.requestedCapabilities);
    await PluginRegistry.setCapabilities(pluginId, granted);
    if (PluginManager.session && PluginManager.session.pluginId === pluginId) {
      PluginManager.session.capabilities = granted.slice(0);
    }
    PluginManager.bump();
    return granted;
  }

  static async revoke(pluginId: string, capability: string): Promise<string[]> {
    const granted = await PluginPermissionService.revoke(pluginId, capability);
    await PluginRegistry.setCapabilities(pluginId, granted);
    if (PluginManager.session && PluginManager.session.pluginId === pluginId) {
      PluginManager.session.capabilities = granted.slice(0);
    }
    PluginManager.bump();
    return granted;
  }

  /** Grants the declared set after the per-plugin risk dialog is confirmed. */
  static async grantAll(pluginId: string): Promise<string[]> {
    const record = PluginRegistry.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    const granted = await PluginPermissionService.grantAll(pluginId, record.requestedCapabilities);
    await PluginRegistry.setCapabilities(pluginId, granted);
    if (PluginManager.session && PluginManager.session.pluginId === pluginId) {
      PluginManager.session.capabilities = granted.slice(0);
    }
    PluginManager.bump();
    return granted;
  }

  /** Revocation stops the plugin before removing its persisted and session grants. */
  static async revokeAll(pluginId: string): Promise<void> {
    const record = PluginRegistry.get(pluginId);
    if (!record) { throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`); }
    await PluginManager.disable(pluginId);
    await PluginPermissionService.clearAll(pluginId);
    await PluginRegistry.setCapabilities(pluginId, []);
    PluginManager.note(pluginId, '已撤回全部权限并停用');
    PluginManager.bump();
  }

  static async granted(pluginId: string): Promise<string[]> {
    return PluginPermissionService.granted(pluginId);
  }

  // ---------------------------------------------------------------- workspace

  /** Published by the desktop workspace and the standalone editor page. */
  static publishWorkspace(windowId: string, vaultId: string, activeFileId: string,
    openFileIds: string[]): void {
    const snapshot = new PluginWorkspaceSnapshot();
    snapshot.windowId = windowId;
    snapshot.vaultId = vaultId;
    snapshot.activeFileId = activeFileId;
    snapshot.openFileIds = openFileIds;
    const handle = LexiEditorBridge.active();
    snapshot.activeEditorId = handle ? handle.editorId : '';
    LexiWorkspaceBridge.publish(snapshot);
    if (snapshot.activeFileId) {
      const event = PluginCoreEvent.create('workspace.active-file-changed', vaultId);
      event.fileId = snapshot.activeFileId;
      event.editorId = snapshot.activeEditorId;
      PluginEventBus.publish(event);
    }
  }

  static runtimeLabel(): string {
    const state = PluginRuntimeController.state();
    if (state === PluginRuntimeState.READY) { return '就绪'; }
    if (state === PluginRuntimeState.LOADING) { return '加载中'; }
    if (state === PluginRuntimeState.FAILED) { return '异常'; }
    return '未就绪';
  }

  static editorCount(): number {
    return LexiEditorBridge.list().length;
  }

  static handles(): PluginEditorHandle[] {
    return LexiEditorBridge.list();
  }

  static reset(): void {
    PluginManager.context = undefined;
    PluginManager.initialized = false;
    PluginManager.initializing = undefined;
    PluginManager.session = undefined;
    PluginManager.activePluginId = '';
    PluginManager.workspaceId = '';
    PluginManager.lifecycle = Promise.resolve();
    PluginManager.uiBridge = new PluginUiBridge();
    PluginManager.notices = [];
    PluginManager.diagnostics = new Map<string, string[]>();
    PluginManager.changeRevision = 0;
    PluginRegistry.reset();
    PluginEventBus.reset();
    PluginCommandRegistry.reset();
    PluginResourceTracker.reset();
    PluginPermissionService.resetCache();
    LexiEditorBridge.reset();
    LexiWorkspaceBridge.reset();
    LexiPathRegistry.reset();
    PluginRuntimeController.reset();
    PluginDataStore.clear('reset').catch((): void => {});
  }

  static kindLabel(kind: string): string {
    return kind === PluginKind.OBSIDIAN ? 'Obsidian 兼容' : 'LexiNote 原生';
  }
}
