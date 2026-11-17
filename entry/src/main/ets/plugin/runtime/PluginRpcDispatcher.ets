import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CanvasBoard,
  CanvasCard,
  CanvasEdge,
  MindMapDoc,
  MindMapNode,
  NoteItem
} from '../../core/LexiModels';
import { LexiStorageService } from '../../core/LexiStorageService';
import { MarkdownEngine } from '../../core/MarkdownEngine';
import { LexiAppearanceSettings } from '../../core/LexiAppearanceSettings';
import { LexiEditorSettings } from '../../core/LexiEditorSettings';
import { LexiInterfaceSettings } from '../../core/LexiInterfaceSettings';
import { LexiI18n } from '../../core/LexiI18n';
import { LEXI_COMMANDS, LexiCommand } from '../../core/LexiCommands';
import { LexiWorkspacePreferences } from '../../core/LexiWorkspacePreferences';
import { PluginCoreEvent, PluginEventType, PluginFileRef } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import {
  PluginCanvasParams,
  PluginCommandParams,
  PluginConfirmParams,
  PluginCreateParams,
  PluginEditorWriteParams,
  PluginEventParams,
  PluginFileParams,
  PluginMindMapParams,
  PluginNoticeParams,
  PluginPathParams,
  PluginRenameParams,
  PluginRpcMethod,
  PluginRpcRequest,
  PluginSettingsParams,
  PluginStorageParams,
  PluginViewParams,
  PluginWriteParams
} from '../model/PluginContracts';
import { PluginAiService } from '../ai/PluginAiService';
import { PluginViewRegistry } from '../core/PluginViewRegistry';
import { LexiEditorBridge, PluginEditorHandle } from '../adapters/LexiEditorBridge';
import { LexiMetadataAdapter } from '../adapters/LexiMetadataAdapter';
import { LexiPathRegistry } from '../adapters/LexiPathRegistry';
import { LexiVaultAdapter } from '../adapters/LexiVaultAdapter';
import { LexiWorkspaceBridge } from '../adapters/LexiWorkspaceBridge';
import { PluginCommandRegistry } from '../core/PluginCommandRegistry';
import { PluginDataStore } from '../core/PluginDataStore';
import { PluginEventBus } from '../core/PluginEventBus';
import { PluginPermissionService } from '../core/PluginPermissionService';

/** Callbacks the runtime host exposes to the dispatcher. */
export class PluginHostUi {
  notice: (message: string, timeoutMs: number) => void = (_message: string, _timeout: number): void => {};
  confirm: (title: string, body: string) => Promise<boolean> = async (_title: string, _body: string): Promise<boolean> => false;
  openFile: (noteId: string) => void = (_noteId: string): void => {};
  invokeCommand: (qualifiedId: string) => void = (_qualifiedId: string): void => {};
  refreshWorkspace: () => void = (): void => {};
  applyTheme: (theme: string) => void = (_theme: string): void => {};
  executeHostCommand: (commandId: string) => Promise<boolean> = async (_commandId: string): Promise<boolean> => false;
}

/** One logical plugin session; created when a plugin becomes ACTIVE. */
export class PluginSession {
  pluginId: string = '';
  kind: string = 'lexinote';
  vaultId: string = '';
  token: string = '';
  capabilities: string[] = [];
  vaultScopes: string[] = [];
  ui: PluginHostUi = new PluginHostUi();
  emitToRuntime: (eventJson: string) => void = (_json: string): void => {};
}

/**
 * The single native entry point for plugin requests (P10/P14).
 *
 * Order of checks is fixed: protocol (already parsed) -> session/identity -> method
 * whitelist (already parsed) -> capability + vault scope -> core service. Anything that
 * fails is reported with an explicit code; nothing is silently ignored.
 */
export class PluginRpcDispatcher {
  private static context: common.Context | undefined = undefined;

  static setContext(context: common.Context): void {
    PluginRpcDispatcher.context = context;
  }

  private static appContext(): common.Context {
    if (!PluginRpcDispatcher.context) {
      throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件宿主尚未初始化');
    }
    return PluginRpcDispatcher.context;
  }

  /** Resolves the vault for this call and enforces the plugin's scope. */
  private static resolveVault(session: PluginSession, requested: string): string {
    const vaultId = requested && requested.length > 0 ? requested : session.vaultId;
    if (!vaultId) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少知识库标识');
    }
    if (session.vaultScopes.length > 0 && !session.vaultScopes.includes(vaultId)) {
      throw PluginErrors.raise(PluginErrorCode.VAULT_FORBIDDEN, '该知识库不在插件授权范围内');
    }
    return vaultId;
  }

  private static async guard(session: PluginSession, method: string): Promise<void> {
    const capability = PluginRpcMethod.capabilityOf(method);
    if (capability) {
      if (!session.capabilities.includes(capability)) {
        throw PluginErrors.raise(PluginErrorCode.PERMISSION_DENIED, `插件未获得能力 ${capability}`);
      }
      await PluginPermissionService.require(session.pluginId, capability);
    }
  }

  private static requireActiveEditor(): PluginEditorHandle {
    const handle = LexiEditorBridge.active();
    if (!handle) { throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '当前没有活动编辑器'); }
    if (handle.isReadOnly()) { throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '编辑器处于只读状态'); }
    return handle;
  }

  private static fileRefJson(ref: PluginFileRef | undefined): string {
    return ref ? JSON.stringify(ref) : 'null';
  }

  private static editorJson(handle: PluginEditorHandle | undefined): string {
    if (!handle) { return 'null'; }
    const draft = handle.draft();
    const selection = handle.getSelection();
    const content = draft.content;
    const cursorOffset = Math.max(0, Math.min(content.length, selection.to));
    let line = 0;
    let lineStart = 0;
    for (let index = 0; index < cursorOffset; index++) {
      if (content[index] === '\n') { line++; lineStart = index + 1; }
    }
    const payload = new Map<string, string>();
    payload.set('editorId', JSON.stringify(draft.editorId));
    payload.set('noteId', JSON.stringify(draft.noteId));
    payload.set('vaultId', JSON.stringify(draft.vaultId));
    payload.set('windowId', JSON.stringify(draft.windowId));
    payload.set('revision', `${draft.revision}`);
    payload.set('baseContent', JSON.stringify(draft.baseContent));
    payload.set('content', JSON.stringify(draft.content));
    payload.set('dirty', draft.dirty ? 'true' : 'false');
    payload.set('readOnly', draft.readOnly ? 'true' : 'false');
    payload.set('focused', draft.focused ? 'true' : 'false');
    payload.set('selection', JSON.stringify({ from: selection.from, to: selection.to }));
    payload.set('cursor', JSON.stringify({ line: line, ch: cursorOffset - lineStart }));
    return PluginRpcDispatcher.objectOf(payload);
  }

  private static objectOf(fields: Map<string, string>): string {
    const parts: string[] = [];
    for (const entry of fields.entries()) {
      parts.push(`${JSON.stringify(entry[0])}:${entry[1]}`);
    }
    return `{${parts.join(',')}}`;
  }

  private static async dispatchVault(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const context = PluginRpcDispatcher.appContext();
    if (request.method === PluginRpcMethod.VAULT_LIST) {
      const params = PluginPathParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      return JSON.stringify(await LexiVaultAdapter.listMarkdown(vaultId));
    }
    if (request.method === PluginRpcMethod.VAULT_GET_BY_PATH) {
      const params = PluginPathParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      return PluginRpcDispatcher.fileRefJson(await LexiVaultAdapter.getByPath(vaultId, params.path));
    }
    if (request.method === PluginRpcMethod.VAULT_GET_BY_ID) {
      const params = PluginFileParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      return PluginRpcDispatcher.fileRefJson(await LexiVaultAdapter.getById(vaultId, params.fileId));
    }
    if (request.method === PluginRpcMethod.VAULT_READ) {
      const params = PluginFileParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      return JSON.stringify(await LexiVaultAdapter.readText(vaultId, params.fileId));
    }
    if (request.method === PluginRpcMethod.VAULT_CREATE) {
      const params = PluginCreateParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const ref = await LexiVaultAdapter.createText(context, vaultId, params.path, params.content);
      PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_CREATED, vaultId, ref, '');
      session.ui.refreshWorkspace();
      return JSON.stringify(ref);
    }
    if (request.method === PluginRpcMethod.VAULT_WRITE) {
      const params = PluginWriteParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const ref = await LexiVaultAdapter.writeText(context, vaultId, params.fileId, params.content,
        params.expectedUpdatedAt);
      const handles = LexiEditorBridge.handlesForNote(params.fileId);
      for (const h of handles) {
        if (!h.isDirty() && h.isVisible() && !h.isReadOnly()) {
          const cur = h.getContent();
          if (cur !== params.content) {
            h.replaceRange(0, cur.length, params.content);
            await h.flush();
          }
        }
      }
      PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_MODIFIED, vaultId, ref, '');
      session.ui.refreshWorkspace();
      return JSON.stringify(ref);
    }
    if (request.method === PluginRpcMethod.VAULT_RENAME) {
      const params = PluginRenameParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const before = LexiPathRegistry.entry(vaultId, params.fileId);
      const oldPath = before ? before.logicalPath : '';
      const ref = await LexiVaultAdapter.renameText(context, vaultId, params.fileId, params.newPath);
      PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_RENAMED, vaultId, ref, oldPath);
      session.ui.refreshWorkspace();
      return JSON.stringify(ref);
    }
    if (request.method === PluginRpcMethod.VAULT_DELETE) {
      const params = PluginFileParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const before = LexiPathRegistry.entry(vaultId, params.fileId);
      await LexiVaultAdapter.deleteText(context, vaultId, params.fileId);
      if (before) {
        const deleted = new PluginFileRef();
        deleted.id = before.noteId; deleted.vaultId = before.vaultId; deleted.projectId = before.projectId;
        deleted.path = before.logicalPath; deleted.name = before.logicalPath;
        PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_DELETED, vaultId, deleted, '');
      }
      session.ui.refreshWorkspace();
      return 'null';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  private static publishVaultEvent(type: string, vaultId: string, ref: PluginFileRef, oldPath: string): void {
    const event = PluginCoreEvent.create(type, vaultId);
    event.fileId = ref.id;
    event.path = ref.path;
    event.oldPath = oldPath;
    event.projectId = ref.projectId;
    event.revision = LexiPathRegistry.revisionOf(vaultId);
    PluginEventBus.publish(event);
  }

  private static async dispatchEditor(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    if (request.method === PluginRpcMethod.EDITOR_ACTIVE) {
      return PluginRpcDispatcher.editorJson(LexiEditorBridge.active());
    }
    const params = PluginEditorWriteParams.from(request.params);
    const handle = PluginRpcDispatcher.requireActiveEditor();
    if (request.method === PluginRpcMethod.EDITOR_REPLACE_ALL) {
      if (params.expectedVersion > 0 && params.expectedVersion !== handle.getRevision()) {
        throw PluginErrors.raise(PluginErrorCode.CONFLICT, '编辑器内容已变化，请重新读取');
      }
      const content = handle.getContent();
      if (!handle.replaceRange(0, content.length, params.text)) {
        throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
      }
    } else if (request.method === PluginRpcMethod.EDITOR_REPLACE_SELECTION) {
      const selection = handle.getSelection();
      if (!handle.replaceRange(selection.from, selection.to, params.text)) {
        throw PluginErrors.raise(PluginErrorCode.EDITOR_READONLY, '编辑器拒绝写入');
      }
    } else {
      throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
    }
    await handle.flush();
    const result = new Map<string, string>();
    result.set('content', JSON.stringify(handle.getContent()));
    result.set('version', `${handle.getRevision()}`);
    return PluginRpcDispatcher.objectOf(result);
  }

  private static async dispatchWorkspace(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    if (request.method === PluginRpcMethod.WORKSPACE_SNAPSHOT) {
      return JSON.stringify(LexiWorkspaceBridge.current());
    }
    if (request.method === PluginRpcMethod.WORKSPACE_ACTIVE_FILE) {
      const handle = LexiEditorBridge.active();
      if (handle && handle.noteId) {
        const ref = await LexiVaultAdapter.getById(handle.vaultId, handle.noteId);
        return PluginRpcDispatcher.fileRefJson(ref);
      }
      const vaultId = session.vaultId;
      const snapshot = LexiWorkspaceBridge.current();
      if (vaultId && snapshot.activeFileId) {
        const ref = await LexiVaultAdapter.getById(vaultId, snapshot.activeFileId);
        return PluginRpcDispatcher.fileRefJson(ref);
      }
      return 'null';
    }
    if (request.method === PluginRpcMethod.WORKSPACE_OPEN_FILE) {
      const params = PluginFileParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      if (params.fileId.startsWith('map:') || params.fileId.startsWith('canvas:')) {
        session.ui.openFile(params.fileId);
        return 'null';
      }
      await LexiVaultAdapter.getById(vaultId, params.fileId);
      session.ui.openFile(params.fileId);
      return 'null';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  /**
   * Accepts both the local command id ('today') and an already qualified one
   * ('lexinote.harness:today'); Obsidian shims tend to pass the qualified form.
   */
  static localCommandId(pluginId: string, rawId: string): string {
    const prefix = `${pluginId}:`;
    return rawId.startsWith(prefix) ? rawId.substring(prefix.length) : rawId;
  }

  private static async dispatchCommand(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    if (request.method === PluginRpcMethod.COMMANDS_LIST_HOST) {
      return JSON.stringify(LEXI_COMMANDS);
    }
    const params = PluginCommandParams.from(request.params);
    if (request.method === PluginRpcMethod.COMMANDS_EXECUTE_HOST) {
      const cmdId = params.id.trim();
      if (!cmdId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少命令 id');
      }
      const found = LEXI_COMMANDS.find((c: LexiCommand): boolean => c.id === cmdId || c.title === cmdId);
      const targetId = found ? found.id : cmdId;
      const handledByUi = await session.ui.executeHostCommand(targetId);
      if (!handledByUi) {
        await PluginRpcDispatcher.executeFallbackHostCommand(session, targetId, params.title);
      }
      return JSON.stringify({ ok: true, id: targetId, title: found ? found.title : targetId });
    }
    const localId = PluginRpcDispatcher.localCommandId(session.pluginId, params.id);
    if (request.method === PluginRpcMethod.COMMANDS_REGISTER) {
      const qualifiedId = PluginCommandRegistry.register(session.pluginId, localId, params.title,
        async (): Promise<void> => {
          session.ui.invokeCommand(PluginCommandRegistry.qualify(session.pluginId, localId));
        });
      hilog.info(0x0A11, 'LexiPluginRuntime', 'command registered: %{public}s', qualifiedId);
      return JSON.stringify({ id: qualifiedId });
    }
    PluginCommandRegistry.unregister(PluginCommandRegistry.qualify(session.pluginId, localId));
    return 'null';
  }

  private static async executeFallbackHostCommand(session: PluginSession, cmdId: string, title: string): Promise<void> {
    const context = PluginRpcDispatcher.appContext();
    const vaultId = PluginRpcDispatcher.resolveVault(session, '');
    if (cmdId === 'light' || cmdId === 'dark' || cmdId === 'system') {
      await LexiStorageService.setSetting('theme', cmdId);
      session.ui.applyTheme(cmdId);
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'theme-toggle') {
      const cur = await LexiStorageService.getSetting('theme', 'system');
      const next = cur === 'dark' ? 'light' : 'dark';
      await LexiStorageService.setSetting('theme', next);
      session.ui.applyTheme(next);
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'font-increase' || cmdId === 'font-decrease') {
      const curSize = LexiAppearanceSettings.clampSize(Number(await LexiStorageService.getSetting('appearanceFontSize', '16')));
      await LexiAppearanceSettings.setFontSize(curSize + (cmdId === 'font-increase' ? 1 : -1));
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'zoom-in' || cmdId === 'zoom-out' || cmdId === 'zoom-reset') {
      const curZoom = AppStorage.get<number>('lexiInterfaceZoom') || 100;
      const nextZoom = cmdId === 'zoom-reset' ? 100 : curZoom + (cmdId === 'zoom-in' ? 10 : -10);
      await LexiInterfaceSettings.setZoom(nextZoom);
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'width-toggle') {
      const curLimit = (await LexiStorageService.getSetting('editorLimitWidth', 'true')) !== 'false';
      await LexiEditorSettings.setBool('editorLimitWidth', 'lexiEditorLimitWidth', !curLimit);
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'default-view-toggle') {
      const curView = (await LexiStorageService.getSetting('editorDefaultView', 'edit')) === 'preview' ? 'preview' : 'edit';
      await LexiEditorSettings.setString('editorDefaultView', 'lexiEditorDefaultView', curView === 'preview' ? 'edit' : 'preview');
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'source-toggle') {
      const curMode = (await LexiStorageService.getSetting('editorDefaultMode', 'live')) === 'source' ? 'source' : 'live';
      await LexiEditorSettings.setString('editorDefaultMode', 'lexiEditorDefaultMode', curMode === 'source' ? 'live' : 'source');
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'ribbon-toggle') {
      const curRibbon = AppStorage.get<boolean>('lexiShowRibbon') ?? true;
      await LexiInterfaceSettings.setRibbon(!curRibbon);
      session.ui.refreshWorkspace();
      return;
    }
    if (cmdId === 'daily') {
      const projectId = await LexiStorageService.getActiveProjectId(vaultId);
      const daily = await LexiStorageService.openOrCreateDailyNote(context, vaultId, projectId);
      session.ui.refreshWorkspace();
      session.ui.openFile(daily.id);
      return;
    }
    if (cmdId === 'new' || cmdId === 'quick' || cmdId === 'study') {
      const projectId = await LexiStorageService.getActiveProjectId(vaultId);
      const note = new NoteItem();
      note.vaultId = vaultId;
      note.projectId = projectId;
      note.title = title.trim() || '未命名笔记';
      note.noteType = cmdId === 'new' ? 'markdown' : cmdId;
      note.editorLevel = cmdId === 'new' ? 'pro' : (cmdId === 'study' ? 'study' : 'simple');
      note.notebook = cmdId === 'quick' ? '速记收件箱' : '笔记';
      const saved = await LexiStorageService.saveNote(context, note);
      session.ui.refreshWorkspace();
      session.ui.openFile(saved.id);
      return;
    }
    if (cmdId === 'map' || cmdId === 'convert') {
      const projectId = await LexiStorageService.getActiveProjectId(vaultId);
      const doc = new MindMapDoc();
      doc.vaultId = vaultId;
      doc.projectId = projectId;
      doc.layoutKind = 'right';
      doc.rootNodeId = 'root';
      const activeHandle = LexiEditorBridge.active();
      if (cmdId === 'convert' && activeHandle && activeHandle.noteId) {
        const srcNote = await LexiStorageService.getNoteById(activeHandle.noteId);
        if (srcNote) {
          doc.title = `${MarkdownEngine.displayTitle(srcNote)} · 导图`;
          doc.nodes = MarkdownEngine.markdownToMindMapNodes(MarkdownEngine.displayTitle(srcNote), srcNote.content, srcNote.id);
        }
      }
      if (doc.nodes.length === 0) {
        doc.title = title.trim() || '新建思维导图';
        doc.nodes = MarkdownEngine.markdownToMindMapNodes(doc.title, '');
      }
      const savedMap = await LexiStorageService.saveMindMap(context, doc);
      session.ui.refreshWorkspace();
      session.ui.openFile(`map:${savedMap.id}`);
      return;
    }
    if (cmdId === 'canvas') {
      const projectId = await LexiStorageService.getActiveProjectId(vaultId);
      const board = new CanvasBoard();
      board.vaultId = vaultId;
      board.projectId = projectId;
      board.title = title.trim() || '新建自由白板';
      const savedBoard = await LexiStorageService.saveCanvas(context, board);
      session.ui.refreshWorkspace();
      session.ui.openFile(`canvas:${savedBoard.id}`);
      return;
    }
  }

  private static async allowEvent(session: PluginSession, event: PluginCoreEvent): Promise<boolean> {
    if (event.vaultId.length > 0 && session.vaultScopes.length > 0 &&
      !session.vaultScopes.includes(event.vaultId)) {
      return false;
    }
    const required = PluginRpcMethod.capabilityOfEvent(event.type);
    if (required.length === 0) {
      return true;
    }
    if (!session.capabilities.includes(required)) {
      return false;
    }
    return PluginPermissionService.has(session.pluginId, required);
  }

  private static async forwardEvent(session: PluginSession, event: PluginCoreEvent): Promise<void> {
    if (!(await PluginRpcDispatcher.allowEvent(session, event))) {
      return;
    }
    // Documented envelope: payload is JSON text, sequence stays per vault.
    session.emitToRuntime(JSON.stringify({
      protocol: 1,
      type: 'event',
      pluginId: session.pluginId,
      event: event.type,
      seq: event.seq,
      payload: JSON.stringify({
        fileId: event.fileId,
        path: event.path,
        oldPath: event.oldPath,
        vaultId: event.vaultId,
        revision: event.revision,
        at: event.at
      })
    }));
  }

  private static async dispatchEvent(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const params = PluginEventParams.from(request.params);
    if (request.method === PluginRpcMethod.EVENTS_ON) {
      const eventName = params.event.trim();
      const requiredCapability = PluginRpcMethod.capabilityOfEvent(eventName);
      if (requiredCapability.length > 0) {
        if (!session.capabilities.includes(requiredCapability)) {
          throw PluginErrors.raise(PluginErrorCode.PERMISSION_DENIED, `插件未获得能力 ${requiredCapability}`);
        }
        await PluginPermissionService.require(session.pluginId, requiredCapability);
      }
      const subscriptionId = PluginEventBus.subscribe(session.pluginId, eventName,
        (event: PluginCoreEvent): void => {
          void PluginRpcDispatcher.forwardEvent(session, event);
        });
      return JSON.stringify({ subscriptionId: subscriptionId });
    }
    PluginEventBus.unsubscribe(params.subscriptionId);
    return 'null';
  }

  private static async dispatchStorage(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const params = PluginStorageParams.from(request.params);
    if (request.method === PluginRpcMethod.STORAGE_GET) {
      return JSON.stringify(await PluginDataStore.get(session.pluginId, params.key, session.vaultId));
    }
    if (request.method === PluginRpcMethod.STORAGE_SET) {
      await PluginDataStore.set(session.pluginId, params.key, params.value, session.vaultId);
      return 'null';
    }
    await PluginDataStore.remove(session.pluginId, params.key, session.vaultId);
    return 'null';
  }

  private static async dispatchMetadata(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const params = PluginFileParams.from(request.params);
    const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
    const note: NoteItem | undefined = await LexiStorageService.getNoteById(params.fileId);
    if (!note || note.vaultId !== vaultId || note.trashedAt > 0) {
      throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '文件不存在');
    }
    await LexiPathRegistry.ensureFresh(vaultId);
    const entry = LexiPathRegistry.entry(vaultId, params.fileId);
    const path = entry ? entry.logicalPath : '';
    return JSON.stringify(LexiMetadataAdapter.build(note, path, LexiPathRegistry.revisionOf(vaultId)));
  }

  private static dispatchUi(session: PluginSession, request: PluginRpcRequest): string {
    if (request.method === PluginRpcMethod.UI_NOTICE) {
      const params = PluginNoticeParams.from(request.params);
      const message = params.message.trim();
      if (message.length === 0) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '通知内容为空');
      }
      session.ui.notice(message.substring(0, 400), params.timeoutMs);
      return 'null';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  /** `ai.*`: host-brokered inference; the plugin still has no socket of its own. */
  private static async dispatchAi(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    // Bindings are per plugin: one plugin can never spend or reconfigure another's credential.
    const pluginId = session.pluginId;
    if (request.method === PluginRpcMethod.AI_MODELS) { return PluginAiService.modelsFor(pluginId); }
    if (request.method === PluginRpcMethod.AI_BALANCE) { return PluginAiService.balanceFor(pluginId); }
    if (request.method === PluginRpcMethod.AI_STATUS) {
      return PluginAiService.statusFor(pluginId);
    }
    if (request.method === PluginRpcMethod.AI_CONFIGURE) {
      return PluginAiService.configureFor(pluginId, request.params);
    }
    return PluginAiService.chatFor(pluginId, request.params);
  }

  /** `views.*`: declarations only; the DOM is rendered by the plugin runtime. */
  private static dispatchViews(session: PluginSession, request: PluginRpcRequest): string {
    const params = PluginViewParams.from(request.params);
    if (request.method === PluginRpcMethod.VIEWS_REGISTER) {
      const record = PluginViewRegistry.register(session.pluginId, params.id, params.title);
      return JSON.stringify({ id: record.id, title: record.title });
    }
    if (request.method === PluginRpcMethod.VIEWS_UNREGISTER) {
      PluginViewRegistry.unregister(session.pluginId, params.id);
      return 'null';
    }
    if (request.method === PluginRpcMethod.VIEWS_OPEN) {
      if (!PluginViewRegistry.requestOpen(session.pluginId, params.id)) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `插件未注册视图 ${params.id}`);
      }
      return 'null';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  private static parseMindMapNodes(rawNodes: Record<string, Object>[], fallbackTitle: string): MindMapNode[] {
    const colors: string[] = ['purple', 'indigo', 'teal', 'amber', 'rose'];
    const result: MindMapNode[] = [];
    let counter = 0;

    const addTree = (item: Record<string, Object>, parentId: string): void => {
      const node = new MindMapNode();
      const rawId = typeof item['id'] === 'string' ? (item['id'] as string).trim() : '';
      if (parentId === '' && result.length === 0) {
        node.id = rawId || 'root';
      } else {
        counter++;
        node.id = rawId && rawId !== 'root' ? rawId : `node-${counter}`;
      }
      node.parentId = parentId;
      const rawText = typeof item['text'] === 'string' ? (item['text'] as string).trim() :
        (typeof item['title'] === 'string' ? (item['title'] as string).trim() : '');
      node.text = rawText || (parentId === '' ? (fallbackTitle || '核心主题') : `分支 ${counter}`);
      if (typeof item['note'] === 'string') { node.note = item['note'] as string; }
      if (typeof item['colorTag'] === 'string' && (item['colorTag'] as string).length > 0) {
        node.colorTag = item['colorTag'] as string;
      } else {
        node.colorTag = colors[result.length % colors.length];
      }
      node.order = typeof item['order'] === 'number' ? (item['order'] as number) : result.length;
      node.collapsed = item['collapsed'] === true;
      if (typeof item['x'] === 'number') { node.x = item['x'] as number; }
      if (typeof item['y'] === 'number') { node.y = item['y'] as number; }
      if (typeof item['noteRefId'] === 'string') { node.noteRefId = item['noteRefId'] as string; }
      if (typeof item['noteRefTitle'] === 'string') { node.noteRefTitle = item['noteRefTitle'] as string; }
      result.push(node);

      const children = item['children'];
      if (Array.isArray(children)) {
        const childArr = children as Record<string, Object>[];
        for (let i = 0; i < childArr.length; i++) {
          const childObj = childArr[i];
          if (childObj && typeof childObj === 'object') {
            addTree(childObj, node.id);
          }
        }
      }
    };

    const hasNested = rawNodes.some((item: Record<string, Object>): boolean =>
      !!item && typeof item === 'object' && Array.isArray(item['children']));
    if (hasNested) {
      if (rawNodes.length === 1) {
        addTree(rawNodes[0], '');
      } else {
        const root = new MindMapNode();
        root.id = 'root';
        root.parentId = '';
        root.text = fallbackTitle || '核心主题';
        root.colorTag = 'purple';
        root.order = 0;
        result.push(root);
        for (let i = 0; i < rawNodes.length; i++) {
          if (rawNodes[i] && typeof rawNodes[i] === 'object') {
            addTree(rawNodes[i], 'root');
          }
        }
      }
      return result;
    }

    for (let i = 0; i < rawNodes.length; i++) {
      const item = rawNodes[i];
      if (!item || typeof item !== 'object') { continue; }
      const node = new MindMapNode();
      const rawId = typeof item['id'] === 'string' ? (item['id'] as string).trim() : '';
      const rawParent = typeof item['parentId'] === 'string' ? (item['parentId'] as string).trim() : '';
      if (i === 0 && rawParent === '') {
        node.id = rawId || 'root';
        node.parentId = '';
      } else {
        counter++;
        node.id = rawId || `node-${counter}`;
        node.parentId = rawParent || 'root';
      }
      const rawText = typeof item['text'] === 'string' ? (item['text'] as string).trim() :
        (typeof item['title'] === 'string' ? (item['title'] as string).trim() : '');
      node.text = rawText || (node.parentId === '' ? (fallbackTitle || '核心主题') : `节点 ${counter}`);
      if (typeof item['note'] === 'string') { node.note = item['note'] as string; }
      node.colorTag = typeof item['colorTag'] === 'string' && (item['colorTag'] as string).length > 0
        ? (item['colorTag'] as string)
        : colors[i % colors.length];
      node.order = typeof item['order'] === 'number' ? (item['order'] as number) : i;
      node.collapsed = item['collapsed'] === true;
      if (typeof item['x'] === 'number') { node.x = item['x'] as number; }
      if (typeof item['y'] === 'number') { node.y = item['y'] as number; }
      if (typeof item['noteRefId'] === 'string') { node.noteRefId = item['noteRefId'] as string; }
      if (typeof item['noteRefTitle'] === 'string') { node.noteRefTitle = item['noteRefTitle'] as string; }
      result.push(node);
    }

    if (result.length > 0 && !result.some((n: MindMapNode): boolean => n.parentId === '')) {
      const root = new MindMapNode();
      root.id = 'root';
      root.parentId = '';
      root.text = fallbackTitle || '核心主题';
      root.colorTag = 'purple';
      root.order = 0;
      result.unshift(root);
    }
    return result;
  }

  private static async dispatchMindMap(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const context = PluginRpcDispatcher.appContext();
    const params = PluginMindMapParams.from(request.params);
    const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);

    if (request.method === PluginRpcMethod.MINDMAP_LIST) {
      const maps = (await LexiStorageService.getMindMaps(vaultId)).filter((m: MindMapDoc): boolean => m.trashedAt === 0);
      return JSON.stringify(maps);
    }
    if (request.method === PluginRpcMethod.MINDMAP_GET) {
      const maps = (await LexiStorageService.getMindMaps(vaultId)).filter((m: MindMapDoc): boolean => m.trashedAt === 0);
      const targetId = params.id.trim();
      const targetTitle = params.title.trim().toLowerCase();
      const found = maps.find((m: MindMapDoc): boolean =>
        (targetId.length > 0 && m.id === targetId) ||
        (targetTitle.length > 0 && m.title.trim().toLowerCase() === targetTitle)
      );
      return found ? JSON.stringify(found) : 'null';
    }
    if (request.method === PluginRpcMethod.MINDMAP_CREATE) {
      const doc = new MindMapDoc();
      doc.vaultId = vaultId;
      doc.projectId = await LexiStorageService.getActiveProjectId(vaultId);
      const layout = params.layoutKind.trim();
      doc.layoutKind = (layout === 'balanced' || layout === 'both') ? 'balanced' :
        ((layout === 'org' || layout === 'down') ? 'org' : 'right');
      doc.title = params.title.trim() || '新建思维导图';
      doc.rootNodeId = 'root';

      if (params.nodes.length > 0) {
        doc.nodes = PluginRpcDispatcher.parseMindMapNodes(params.nodes, doc.title);
      } else if (params.fromNoteId.trim().length > 0) {
        const srcNote = await LexiStorageService.getNoteById(params.fromNoteId.trim());
        if (!srcNote || srcNote.vaultId !== vaultId || srcNote.trashedAt > 0) {
          throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, '来源笔记不存在');
        }
        doc.projectId = srcNote.projectId || doc.projectId;
        if (!params.title.trim()) {
          doc.title = `${MarkdownEngine.displayTitle(srcNote)} · 导图`;
        }
        doc.nodes = MarkdownEngine.markdownToMindMapNodes(
          params.title.trim() || MarkdownEngine.displayTitle(srcNote),
          srcNote.content,
          srcNote.id
        );
      } else if (params.markdown.trim().length > 0) {
        doc.nodes = MarkdownEngine.markdownToMindMapNodes(doc.title, params.markdown);
      } else {
        doc.nodes = MarkdownEngine.markdownToMindMapNodes(doc.title, '');
      }
      const rootNode = doc.nodes.find((n: MindMapNode): boolean => n.parentId === '') || doc.nodes[0];
      if (rootNode) { doc.rootNodeId = rootNode.id; }

      const saved = await LexiStorageService.saveMindMap(context, doc);
      session.ui.refreshWorkspace();
      if (!params.hasOpen || params.open) {
        session.ui.openFile(`map:${saved.id}`);
      }
      return JSON.stringify(saved);
    }
    if (request.method === PluginRpcMethod.MINDMAP_UPDATE) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少思维导图 id');
      }
      const existing = await LexiStorageService.getMindMapById(targetId);
      if (!existing || existing.vaultId !== vaultId || existing.trashedAt > 0) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `思维导图不存在：${targetId}`);
      }
      const doc = JSON.parse(JSON.stringify(existing)) as MindMapDoc;
      if (params.title.trim().length > 0) { doc.title = params.title.trim(); }
      const layout = params.layoutKind.trim();
      if (layout === 'right' || layout === 'balanced' || layout === 'both' || layout === 'org' || layout === 'down') {
        doc.layoutKind = (layout === 'balanced' || layout === 'both') ? 'balanced' :
          ((layout === 'org' || layout === 'down') ? 'org' : 'right');
      }
      if (params.nodes.length > 0) {
        doc.nodes = PluginRpcDispatcher.parseMindMapNodes(params.nodes, doc.title);
      } else if (params.markdown.trim().length > 0) {
        doc.nodes = MarkdownEngine.markdownToMindMapNodes(doc.title, params.markdown);
      }
      const rootNode = doc.nodes.find((n: MindMapNode): boolean => n.parentId === '') || doc.nodes[0];
      if (rootNode) { doc.rootNodeId = rootNode.id; }

      const saved = await LexiStorageService.saveMindMap(context, doc);
      session.ui.refreshWorkspace();
      if (params.hasOpen && params.open) {
        session.ui.openFile(`map:${saved.id}`);
      }
      return JSON.stringify(saved);
    }
    if (request.method === PluginRpcMethod.MINDMAP_DELETE) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少思维导图 id');
      }
      const existing = await LexiStorageService.getMindMapById(targetId);
      if (!existing || existing.vaultId !== vaultId) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `思维导图不存在：${targetId}`);
      }
      await LexiStorageService.deleteMindMap(targetId);
      session.ui.refreshWorkspace();
      return 'true';
    }
    if (request.method === PluginRpcMethod.MINDMAP_OPEN) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少思维导图 id');
      }
      const existing = await LexiStorageService.getMindMapById(targetId);
      if (!existing || existing.vaultId !== vaultId || existing.trashedAt > 0) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `思维导图不存在：${targetId}`);
      }
      session.ui.openFile(`map:${existing.id}`);
      return 'true';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  private static parseCanvasCards(rawCards: Record<string, Object>[]): CanvasCard[] {
    const colors: string[] = ['purple', 'indigo', 'teal', 'amber', 'rose'];
    const cards: CanvasCard[] = [];
    for (let i = 0; i < rawCards.length; i++) {
      const item = rawCards[i];
      if (!item || typeof item !== 'object') { continue; }
      const card = new CanvasCard();
      card.id = typeof item['id'] === 'string' && (item['id'] as string).trim().length > 0
        ? (item['id'] as string).trim()
        : `card-${i + 1}`;
      card.title = typeof item['title'] === 'string' ? (item['title'] as string) : `卡片 ${i + 1}`;
      card.content = typeof item['content'] === 'string' ? (item['content'] as string) :
        (typeof item['body'] === 'string' ? (item['body'] as string) : '');
      card.colorTag = typeof item['colorTag'] === 'string' && (item['colorTag'] as string).length > 0
        ? (item['colorTag'] as string)
        : colors[i % colors.length];
      card.x = typeof item['x'] === 'number' ? (item['x'] as number) : (60 + (i % 3) * 260);
      card.y = typeof item['y'] === 'number' ? (item['y'] as number) : (80 + Math.floor(i / 3) * 180);
      if (typeof item['noteRefId'] === 'string') { card.noteRefId = item['noteRefId'] as string; }
      if (typeof item['noteRefTitle'] === 'string') { card.noteRefTitle = item['noteRefTitle'] as string; }
      cards.push(card);
    }
    return cards;
  }

  private static parseCanvasEdges(rawEdges: Record<string, Object>[]): CanvasEdge[] {
    const edges: CanvasEdge[] = [];
    for (let i = 0; i < rawEdges.length; i++) {
      const item = rawEdges[i];
      if (!item || typeof item !== 'object') { continue; }
      const fromId = typeof item['fromId'] === 'string' ? (item['fromId'] as string).trim() :
        (typeof item['fromCardId'] === 'string' ? (item['fromCardId'] as string).trim() :
          (typeof item['from'] === 'string' ? (item['from'] as string).trim() : ''));
      const toId = typeof item['toId'] === 'string' ? (item['toId'] as string).trim() :
        (typeof item['toCardId'] === 'string' ? (item['toCardId'] as string).trim() :
          (typeof item['to'] === 'string' ? (item['to'] as string).trim() : ''));
      if (!fromId || !toId) { continue; }
      const edge = new CanvasEdge();
      edge.id = typeof item['id'] === 'string' && (item['id'] as string).trim().length > 0
        ? (item['id'] as string).trim()
        : `edge-${i + 1}`;
      edge.fromId = fromId;
      edge.toId = toId;
      edge.label = typeof item['label'] === 'string' ? (item['label'] as string) : '';
      edges.push(edge);
    }
    return edges;
  }

  private static async dispatchCanvas(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    const context = PluginRpcDispatcher.appContext();
    const params = PluginCanvasParams.from(request.params);
    const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);

    if (request.method === PluginRpcMethod.CANVAS_LIST) {
      const boards = await LexiStorageService.getCanvases(vaultId);
      return JSON.stringify(boards);
    }
    if (request.method === PluginRpcMethod.CANVAS_GET) {
      const boards = await LexiStorageService.getCanvases(vaultId);
      const targetId = params.id.trim();
      const targetTitle = params.title.trim().toLowerCase();
      const found = boards.find((c: CanvasBoard): boolean =>
        (targetId.length > 0 && c.id === targetId) ||
        (targetTitle.length > 0 && c.title.trim().toLowerCase() === targetTitle)
      );
      return found ? JSON.stringify(found) : 'null';
    }
    if (request.method === PluginRpcMethod.CANVAS_CREATE) {
      const board = new CanvasBoard();
      board.vaultId = vaultId;
      board.projectId = await LexiStorageService.getActiveProjectId(vaultId);
      board.title = params.title.trim() || '新建自由白板';
      board.cards = PluginRpcDispatcher.parseCanvasCards(params.cards);
      board.edges = PluginRpcDispatcher.parseCanvasEdges(params.edges);
      const saved = await LexiStorageService.saveCanvas(context, board);
      session.ui.refreshWorkspace();
      if (!params.hasOpen || params.open) {
        session.ui.openFile(`canvas:${saved.id}`);
      }
      return JSON.stringify(saved);
    }
    if (request.method === PluginRpcMethod.CANVAS_UPDATE) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少白板 id');
      }
      const existing = await LexiStorageService.getCanvasById(targetId);
      if (!existing || existing.vaultId !== vaultId) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `白板不存在：${targetId}`);
      }
      const board = JSON.parse(JSON.stringify(existing)) as CanvasBoard;
      if (params.title.trim().length > 0) { board.title = params.title.trim(); }
      if (params.cards.length > 0) { board.cards = PluginRpcDispatcher.parseCanvasCards(params.cards); }
      if (params.edges.length > 0) { board.edges = PluginRpcDispatcher.parseCanvasEdges(params.edges); }
      const saved = await LexiStorageService.saveCanvas(context, board);
      session.ui.refreshWorkspace();
      if (params.hasOpen && params.open) {
        session.ui.openFile(`canvas:${saved.id}`);
      }
      return JSON.stringify(saved);
    }
    if (request.method === PluginRpcMethod.CANVAS_DELETE) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少白板 id');
      }
      const existing = await LexiStorageService.getCanvasById(targetId);
      if (!existing || existing.vaultId !== vaultId) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `白板不存在：${targetId}`);
      }
      await LexiStorageService.deleteCanvas(targetId);
      session.ui.refreshWorkspace();
      return 'true';
    }
    if (request.method === PluginRpcMethod.CANVAS_OPEN) {
      const targetId = params.id.trim();
      if (!targetId) {
        throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '缺少白板 id');
      }
      const existing = await LexiStorageService.getCanvasById(targetId);
      if (!existing || existing.vaultId !== vaultId) {
        throw PluginErrors.raise(PluginErrorCode.NOT_FOUND, `白板不存在：${targetId}`);
      }
      session.ui.openFile(`canvas:${existing.id}`);
      return 'true';
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  private static resolveAccentHex(raw: string): string {
    const val = raw.trim();
    if (/^#[0-9A-Fa-f]{6}$/.test(val)) { return val.toUpperCase(); }
    const lower = val.toLowerCase();
    if (lower === 'purple' || lower.includes('紫')) { return '#6C5CE7'; }
    if (lower === 'indigo' || lower.includes('靛')) { return '#4F46E5'; }
    if (lower === 'blue' || lower.includes('蓝')) { return '#2563EB'; }
    if (lower === 'teal' || lower.includes('青')) { return '#0D9488'; }
    if (lower === 'green' || lower.includes('绿')) { return '#16A34A'; }
    if (lower === 'amber' || lower === 'orange' || lower.includes('橙') || lower.includes('黄') || lower.includes('琥珀')) { return '#D97706'; }
    if (lower === 'rose' || lower === 'red' || lower === 'pink' || lower.includes('红') || lower.includes('粉') || lower.includes('玫瑰')) { return '#E11D48'; }
    return '';
  }

  private static async readAllSettings(): Promise<string> {
    const theme = await LexiStorageService.getSetting('theme', 'system');
    const language = LexiI18n.language();
    const defaultTier = await LexiStorageService.getSetting('defaultTier', 'simple');
    const vaultViewMode = await LexiStorageService.getSetting('vaultViewMode', 'list');
    const graphShowTags = await LexiStorageService.getSetting('graphShowTags', 'false') === 'true';
    const workspaceOpenMode = LexiWorkspacePreferences.openMode(await LexiStorageService.getSetting('workspaceOpenMode', 'ask'));
    const spellcheck = await LexiStorageService.getSetting('editorSpellcheck', 'false') === 'true';

    const appearance = new Map<string, string>();
    const accent = await LexiStorageService.getSetting('appearanceAccent', LexiAppearanceSettings.DEFAULT_ACCENT);
    const fontSize = LexiAppearanceSettings.clampSize(Number(await LexiStorageService.getSetting('appearanceFontSize', '16')));
    const quickZoom = (await LexiStorageService.getSetting('appearanceQuickZoom', 'false')) === 'true';
    appearance.set('accent', JSON.stringify(accent));
    appearance.set('fontSize', `${fontSize}`);
    appearance.set('quickZoom', quickZoom ? 'true' : 'false');

    const editor = new Map<string, string>();
    const defaultView = (await LexiStorageService.getSetting('editorDefaultView', 'edit')) === 'preview' ? 'preview' : 'edit';
    const defaultMode = (await LexiStorageService.getSetting('editorDefaultMode', 'live')) === 'source' ? 'source' : 'live';
    const showTitle = (await LexiStorageService.getSetting('editorShowTitle', 'true')) !== 'false';
    const limitWidth = (await LexiStorageService.getSetting('editorLimitWidth', 'true')) !== 'false';
    const viewStatus = (await LexiStorageService.getSetting('editorViewStatus', 'true')) !== 'false';
    editor.set('defaultView', JSON.stringify(defaultView));
    editor.set('defaultMode', JSON.stringify(defaultMode));
    editor.set('showTitle', showTitle ? 'true' : 'false');
    editor.set('limitWidth', limitWidth ? 'true' : 'false');
    editor.set('viewStatus', viewStatus ? 'true' : 'false');
    editor.set('spellcheck', spellcheck ? 'true' : 'false');

    const iface = new Map<string, string>();
    const tabHeaders = (await LexiStorageService.getSetting('interfaceTabHeaders', 'true')) !== 'false';
    const showRibbon = (await LexiStorageService.getSetting('interfaceRibbon', 'true')) !== 'false';
    const zoom = LexiInterfaceSettings.clampZoom(Number(await LexiStorageService.getSetting('interfaceZoom', '100')));
    const sidebarWidth = LexiInterfaceSettings.clampSidebarWidth(Number(await LexiStorageService.getSetting('interfaceSidebarWidth', '244')));
    const rightSidebarWidth = LexiInterfaceSettings.clampRightSidebarWidth(Number(await LexiStorageService.getSetting('interfaceRightSidebarWidth', '280')));
    iface.set('tabHeaders', tabHeaders ? 'true' : 'false');
    iface.set('showRibbon', showRibbon ? 'true' : 'false');
    iface.set('zoom', `${zoom}`);
    iface.set('sidebarWidth', `${sidebarWidth}`);
    iface.set('rightSidebarWidth', `${rightSidebarWidth}`);

    const root = new Map<string, string>();
    root.set('theme', JSON.stringify(theme));
    root.set('language', JSON.stringify(language));
    root.set('defaultTier', JSON.stringify(defaultTier));
    root.set('vaultViewMode', JSON.stringify(vaultViewMode));
    root.set('graphShowTags', graphShowTags ? 'true' : 'false');
    root.set('workspaceOpenMode', JSON.stringify(workspaceOpenMode));
    root.set('appearance', PluginRpcDispatcher.objectOf(appearance));
    root.set('editor', PluginRpcDispatcher.objectOf(editor));
    root.set('interface', PluginRpcDispatcher.objectOf(iface));
    return PluginRpcDispatcher.objectOf(root);
  }

  private static async dispatchSettings(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    if (request.method === PluginRpcMethod.SETTINGS_GET) {
      return PluginRpcDispatcher.readAllSettings();
    }
    if (request.method === PluginRpcMethod.SETTINGS_SET) {
      const params = PluginSettingsParams.from(request.params);
      const patch = params.patch;

      if (typeof patch['theme'] === 'string') {
        const t = (patch['theme'] as string).trim();
        if (t === 'light' || t === 'dark' || t === 'system') {
          await LexiStorageService.setSetting('theme', t);
          session.ui.applyTheme(t);
        }
      }
      if (typeof patch['language'] === 'string') {
        const lang = (patch['language'] as string).trim();
        if (lang === 'zh-Hans' || lang === 'en') {
          await LexiI18n.select(lang);
        }
      }
      if (typeof patch['defaultTier'] === 'string') {
        const tier = (patch['defaultTier'] as string).trim();
        if (tier === 'simple' || tier === 'study' || tier === 'pro') {
          await LexiStorageService.setSetting('defaultTier', tier);
        }
      }
      if (typeof patch['vaultViewMode'] === 'string') {
        const vm = (patch['vaultViewMode'] as string).trim();
        if (vm === 'list' || vm === 'card' || vm === 'folder') {
          await LexiStorageService.setSetting('vaultViewMode', vm);
        }
      }
      if (typeof patch['graphShowTags'] === 'boolean') {
        await LexiStorageService.setSetting('graphShowTags', (patch['graphShowTags'] as boolean) ? 'true' : 'false');
      }
      if (typeof patch['workspaceOpenMode'] === 'string') {
        const om = LexiWorkspacePreferences.openMode(patch['workspaceOpenMode'] as string);
        await LexiStorageService.setSetting('workspaceOpenMode', om);
        try { AppStorage.setOrCreate('lexiWorkspaceOpenMode', om); } catch {}
      }
      if (patch['resetColors'] === true) {
        await LexiAppearanceSettings.setOriginalColors();
        await LexiStorageService.setSetting('appearanceAccent', LexiAppearanceSettings.DEFAULT_ACCENT);
      }
      if (typeof patch['accent'] === 'string') {
        const hex = PluginRpcDispatcher.resolveAccentHex(patch['accent'] as string);
        if (hex.length > 0) {
          await LexiStorageService.setSetting('appearanceAccent', hex);
          await LexiAppearanceSettings.setAccent(hex);
        }
      }
      if (typeof patch['fontSize'] === 'number') {
        await LexiAppearanceSettings.setFontSize(patch['fontSize'] as number);
      }
      if (typeof patch['quickZoom'] === 'boolean') {
        await LexiAppearanceSettings.setQuickZoom(patch['quickZoom'] as boolean);
      }
      if (typeof patch['editorDefaultView'] === 'string') {
        const rawView = (patch['editorDefaultView'] as string).trim();
        const nextView = (rawView === 'preview' || rawView === 'read' || rawView === 'reading') ? 'preview' : 'edit';
        await LexiEditorSettings.setString('editorDefaultView', 'lexiEditorDefaultView', nextView);
      }
      if (typeof patch['editorDefaultMode'] === 'string') {
        const rawMode = (patch['editorDefaultMode'] as string).trim();
        const nextMode = rawMode === 'source' ? 'source' : 'live';
        await LexiEditorSettings.setString('editorDefaultMode', 'lexiEditorDefaultMode', nextMode);
      }
      if (typeof patch['editorShowTitle'] === 'boolean') {
        await LexiEditorSettings.setBool('editorShowTitle', 'lexiEditorShowTitle', patch['editorShowTitle'] as boolean);
      }
      if (typeof patch['editorLimitWidth'] === 'boolean') {
        await LexiEditorSettings.setBool('editorLimitWidth', 'lexiEditorLimitWidth', patch['editorLimitWidth'] as boolean);
      }
      if (typeof patch['editorViewStatus'] === 'boolean') {
        await LexiEditorSettings.setBool('editorViewStatus', 'lexiEditorViewStatus', patch['editorViewStatus'] as boolean);
      }
      if (typeof patch['editorSpellcheck'] === 'boolean') {
        const on = patch['editorSpellcheck'] as boolean;
        await LexiStorageService.setSetting('editorSpellcheck', on ? 'true' : 'false');
        try { AppStorage.setOrCreate('lexiEditorSpellcheck', on); } catch {}
      }
      if (typeof patch['interfaceTabHeaders'] === 'boolean') {
        await LexiInterfaceSettings.setTabHeaders(patch['interfaceTabHeaders'] as boolean);
      }
      if (typeof patch['interfaceRibbon'] === 'boolean') {
        await LexiInterfaceSettings.setRibbon(patch['interfaceRibbon'] as boolean);
      }
      if (typeof patch['interfaceZoom'] === 'number') {
        await LexiInterfaceSettings.setZoom(patch['interfaceZoom'] as number);
      }
      if (typeof patch['interfaceSidebarWidth'] === 'number') {
        await LexiInterfaceSettings.setSidebarWidth(patch['interfaceSidebarWidth'] as number);
      }
      if (typeof patch['interfaceRightSidebarWidth'] === 'number') {
        await LexiInterfaceSettings.setRightSidebarWidth(patch['interfaceRightSidebarWidth'] as number);
      }
      session.ui.refreshWorkspace();
      return PluginRpcDispatcher.readAllSettings();
    }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, request.method);
  }

  static async dispatch(session: PluginSession, request: PluginRpcRequest): Promise<string> {
    if (request.pluginId !== session.pluginId) {
      throw PluginErrors.raise(PluginErrorCode.PERMISSION_DENIED, '插件身份与请求不一致');
    }
    await PluginRpcDispatcher.guard(session, request.method);
    const method = request.method;
    if (method === PluginRpcMethod.PING) {
      return JSON.stringify({ ok: true, pluginId: session.pluginId });
    }
    if (method.startsWith('vault.')) { return PluginRpcDispatcher.dispatchVault(session, request); }
    if (method === PluginRpcMethod.METADATA_GET) { return PluginRpcDispatcher.dispatchMetadata(session, request); }
    if (method.startsWith('workspace.')) { return PluginRpcDispatcher.dispatchWorkspace(session, request); }
    if (method.startsWith('editor.')) { return PluginRpcDispatcher.dispatchEditor(session, request); }
    if (method.startsWith('commands.')) { return PluginRpcDispatcher.dispatchCommand(session, request); }
    if (method.startsWith('events.')) { return PluginRpcDispatcher.dispatchEvent(session, request); }
    if (method.startsWith('storage.')) { return PluginRpcDispatcher.dispatchStorage(session, request); }
    if (method === PluginRpcMethod.UI_NOTICE) { return PluginRpcDispatcher.dispatchUi(session, request); }
    if (method === PluginRpcMethod.UI_CONFIRM) {
      const params = PluginConfirmParams.from(request.params);
      const accepted = await session.ui.confirm(params.title, params.body);
      return accepted ? 'true' : 'false';
    }
    if (method.startsWith('ai.')) { return PluginRpcDispatcher.dispatchAi(session, request); }
    if (method.startsWith('views.')) { return PluginRpcDispatcher.dispatchViews(session, request); }
    if (method.startsWith('mindmap.')) { return PluginRpcDispatcher.dispatchMindMap(session, request); }
    if (method.startsWith('canvas.')) { return PluginRpcDispatcher.dispatchCanvas(session, request); }
    if (method.startsWith('settings.')) { return PluginRpcDispatcher.dispatchSettings(session, request); }
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, method);
  }
}
