import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NoteItem } from '../../core/LexiModels';
import { LexiStorageService } from '../../core/LexiStorageService';
import { PluginCoreEvent, PluginEventType, PluginFileRef } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import {
  PluginCommandParams,
  PluginConfirmParams,
  PluginCreateParams,
  PluginEditorWriteParams,
  PluginEventParams,
  PluginFileParams,
  PluginNoticeParams,
  PluginPathParams,
  PluginRenameParams,
  PluginRpcMethod,
  PluginRpcRequest,
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
      return JSON.stringify(ref);
    }
    if (request.method === PluginRpcMethod.VAULT_WRITE) {
      const params = PluginWriteParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const ref = await LexiVaultAdapter.writeText(context, vaultId, params.fileId, params.content,
        params.expectedUpdatedAt);
      PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_MODIFIED, vaultId, ref, '');
      return JSON.stringify(ref);
    }
    if (request.method === PluginRpcMethod.VAULT_RENAME) {
      const params = PluginRenameParams.from(request.params);
      const vaultId = PluginRpcDispatcher.resolveVault(session, params.vaultId);
      const before = LexiPathRegistry.entry(vaultId, params.fileId);
      const oldPath = before ? before.logicalPath : '';
      const ref = await LexiVaultAdapter.renameText(context, vaultId, params.fileId, params.newPath);
      PluginRpcDispatcher.publishVaultEvent(PluginEventType.VAULT_RENAMED, vaultId, ref, oldPath);
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
    const params = PluginCommandParams.from(request.params);
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

  private static dispatchEvent(session: PluginSession, request: PluginRpcRequest): string {
    const params = PluginEventParams.from(request.params);
    if (request.method === PluginRpcMethod.EVENTS_ON) {
      const subscriptionId = PluginEventBus.subscribe(session.pluginId, params.event,
        (event: PluginCoreEvent): void => {
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
    if (request.method === PluginRpcMethod.AI_MODELS) { return PluginAiService.models(); }
    if (request.method === PluginRpcMethod.AI_BALANCE) { return PluginAiService.balance(); }
    if (request.method === PluginRpcMethod.AI_STATUS) {
      return PluginAiService.status();
    }
    if (request.method === PluginRpcMethod.AI_CONFIGURE) {
      return PluginAiService.configure(request.params);
    }
    return PluginAiService.chat(request.params);
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
    throw PluginErrors.raise(PluginErrorCode.UNSUPPORTED_API, method);
  }
}
