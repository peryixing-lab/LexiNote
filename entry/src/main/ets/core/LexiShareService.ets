import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { LexiContinuationSession } from './LexiContinuationSession';
import { LexiFrontmatter } from './LexiFrontmatter';
import { NoteItem, NoteProperty } from './LexiModels';
import { LexiStorageService } from './LexiStorageService';
import { MarkdownEngine } from './MarkdownEngine';

export class LexiSharableNoteSnapshot {
  noteId: string = '';
  title: string = '';
  content: string = '';
  notebook: string = '';
  tags: string[] = [];
  properties: NoteProperty[] = [];
  filePath: string = '';
  fileUri: string = '';
}

class LexiWindowShareBinding {
  context: common.UIAbilityContext;
  windowId: number;
  is2in1: boolean;
  knockCallback: (target: harmonyShare.SharableTarget) => void;

  constructor(
    context: common.UIAbilityContext,
    windowId: number,
    is2in1: boolean,
    knockCallback: (target: harmonyShare.SharableTarget) => void
  ) {
    this.context = context;
    this.windowId = windowId;
    this.is2in1 = is2in1;
    this.knockCallback = knockCallback;
  }
}

/**
 * System file sharing (ShareController) and Knock Share (harmonyShare) integration.
 */
export class LexiShareService {
  private static activeOwner: string = '';
  private static activeGetter: (() => LexiSharableNoteSnapshot | undefined) | undefined = undefined;
  private static windowBindings: Map<string, LexiWindowShareBinding> = new Map<string, LexiWindowShareBinding>();
  private static lastKnockCoordX: number = -1;
  private static lastKnockCoordY: number = -1;
  private static previewBytes: Uint8Array | undefined = undefined;

  private static async compactPreview(context: common.Context): Promise<Uint8Array | undefined> {
    if (LexiShareService.previewBytes) { return LexiShareService.previewBytes; }
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      const original = context.resourceManager.getMediaContentSync($r('app.media.foreground').id);
      source = image.createImageSource(original.buffer);
      pixels = await source.createPixelMap({ desiredSize: { width: 32, height: 32 } });
      packer = image.createImagePacker();
      const bytes = new Uint8Array(await packer.packToData(pixels, { format: 'image/png', quality: 80 }));
      // Byte-array keys expand significantly when Share Kit serializes to Want.
      if (bytes.length <= 4096) { LexiShareService.previewBytes = bytes; return bytes; }
    } catch { /* Preview is optional; the local note is never copied into IPC. */ }
    finally {
      try { await packer?.release(); } catch {}
      try { await pixels?.release(); } catch {}
      try { await source?.release(); } catch {}
    }
    return undefined;
  }

  static sanitizeFileName(rawTitle: string): string {
    const cleaned = (rawTitle || '')
      .replace(/\.(md|markdown)$/i, '')
      .replace(/[/\\:*?"<>|\r\n\u0000-\u001f]+/g, '_')
      .replace(/^[.\s_]+|[.\s_]+$/g, '')
      .slice(0, 80);
    return `${cleaned || '未命名笔记'}.md`;
  }

  static resolveMarkdownUtd(): string {
    try {
      const resolved = utd.getUniformDataTypeByFilenameExtension('.md');
      if (resolved && resolved.trim().length > 0) {
        return resolved;
      }
    } catch {}
    return 'general.markdown';
  }

  static buildNoteMarkdown(snapshot: LexiSharableNoteSnapshot): string {
    const note = new NoteItem();
    note.id = snapshot.noteId || 'shared-note';
    note.title = snapshot.title.trim() || '未命名笔记';
    note.content = snapshot.content;
    note.notebook = snapshot.notebook || '笔记';
    note.tags = snapshot.tags.slice();
    note.properties = snapshot.properties.map(
      (prop: NoteProperty): NoteProperty => new NoteProperty(prop.key, prop.propValue)
    );
    return LexiFrontmatter.serialize(note);
  }

  static createFileSharedData(context: common.Context, snapshot: LexiSharableNoteSnapshot,
    thumbnail: Uint8Array | undefined = undefined): systemShare.SharedData {
    const displayTitle = snapshot.title.trim() || '未命名笔记';
    const filePath = snapshot.filePath;
    if (!filePath || filePath.startsWith(`${context.filesDir}/`) ||
      (context.cacheDir && filePath.startsWith(`${context.cacheDir}/`)) || !fs.accessSync(filePath)) {
      throw new Error('请先将笔记保存到本地工作区文件夹后再分享');
    }
    // The system share panel cannot parse user-directory file URIs (panel-side
    // getShareData fails with 1003703001 and show() reports 1003702002). Share a
    // fresh app-sandbox copy instead; Share Kit grants receivers temporary read.
    const shareDir = `${context.cacheDir}/lexi-share`;
    if (!fs.accessSync(shareDir)) { fs.mkdirSync(shareDir, true); }
    const sandboxPath = `${shareDir}/${LexiShareService.sanitizeFileName(displayTitle)}`;
    const file = fs.openSync(sandboxPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, LexiShareService.buildNoteMarkdown(snapshot));
      fs.fsyncSync(file.fd);
    } finally { fs.closeSync(file); }
    const record: systemShare.SharedRecord = {
      // MARKDOWN inherits TEXT. A file URI must use the FILE record type.
      utd: utd.UniformDataType.FILE,
      uri: fileUri.getUriFromPath(sandboxPath),
      title: LexiShareService.sanitizeFileName(displayTitle),
      label: 'FILE',
      description: snapshot.notebook ? `知萤笔记 · ${snapshot.notebook}` : '知萤 LexiNote Markdown 笔记'
    };
    if (thumbnail && thumbnail.length > 0 && thumbnail.length <= 4096) { record.thumbnail = thumbnail; }
    return new systemShare.SharedData(record);
  }

  static async showSystemSharePanel(
    context: common.UIAbilityContext,
    snapshot: LexiSharableNoteSnapshot,
    anchorId: string = ''
  ): Promise<void> {
    const shareData = LexiShareService.createFileSharedData(context, snapshot, await LexiShareService.compactPreview(context));
    hilog.info(0x1050, 'LexiShare', 'File share: records=%{public}d', shareData.getRecords().length);
    const controller = new systemShare.ShareController(shareData);
    const options: systemShare.ShareControllerOptions = {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    };
    let fallbackAnchor: systemShare.ShareControllerAnchor = { windowOffset: { x: 100, y: 100 } };
    try {
      const hostWindow = await window.getLastWindow(context);
      const rect = hostWindow.getWindowProperties().windowRect;
      fallbackAnchor = { windowOffset: { x: Math.max(1, rect.width / 2), y: Math.max(1, rect.height / 2) } };
      options.anchor = fallbackAnchor;
      if (anchorId && anchorId.trim().length > 0) {
        const uiContext = hostWindow.getUIContext();
        const node = uiContext.getAttachedFrameNodeById(anchorId.trim());
        if (node && node.isAttached() && node.isVisible()) {
          const position = node.getPositionToWindow(); const size = node.getMeasuredSize();
          options.anchor = { windowOffset: { x: uiContext.vp2px(position.x), y: uiContext.vp2px(position.y) },
            size: { width: size.width, height: size.height } };
        }
      }
    } catch { options.anchor = fallbackAnchor; }
    try { await controller.show(context, options); }
    catch (error) {
      hilog.error(0x1050, 'LexiShare', 'Share panel failed: code=%{public}d, message=%{public}s',
        (error as BusinessError).code || 0, (error as Error).message);
      if (!options.anchor || (error as BusinessError).code !== 401) { throw error as Error; }
      // Desktop panels need an explicit numeric anchor even if a menu detaches.
      await controller.show(context, { previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE, anchor: fallbackAnchor });
    }
  }

  static async shareNoteById(
    context: common.UIAbilityContext,
    noteId: string,
    anchorId: string = ''
  ): Promise<void> {
    await LexiStorageService.init(context);
    const note = await LexiStorageService.getNoteById(noteId);
    if (!note || note.trashedAt > 0) {
      throw new Error('未找到可分享的笔记文件');
    }
    const snapshot = new LexiSharableNoteSnapshot();
    snapshot.noteId = note.id;
    snapshot.title = MarkdownEngine.displayTitle(note);
    snapshot.content = note.content;
    snapshot.notebook = note.notebook;
    snapshot.tags = note.tags.slice();
    snapshot.properties = note.properties.map(
      (prop: NoteProperty): NoteProperty => new NoteProperty(prop.key, prop.propValue)
    );
    snapshot.filePath = note.path;
    snapshot.fileUri = await LexiStorageService.getNoteFileUri(note);
    await LexiShareService.showSystemSharePanel(context, snapshot, anchorId);
  }

  static async shareDraftNote(
    context: common.UIAbilityContext,
    note: NoteItem,
    titleText: string,
    contentText: string,
    notebookText: string,
    anchorId: string = ''
  ): Promise<void> {
    const snapshot = new LexiSharableNoteSnapshot();
    snapshot.noteId = note.id;
    snapshot.title = titleText.trim() || MarkdownEngine.displayTitle(note);
    snapshot.content = contentText;
    snapshot.notebook = notebookText.trim() || note.notebook || '笔记';
    snapshot.tags = note.tags.slice();
    snapshot.properties = note.properties.map(
      (prop: NoteProperty): NoteProperty => new NoteProperty(prop.key, prop.propValue)
    );
    snapshot.filePath = note.path;
    snapshot.fileUri = await LexiStorageService.getNoteFileUri(note);
    await LexiShareService.showSystemSharePanel(context, snapshot, anchorId);
  }

  static activateKnockSource(owner: string, getter: () => LexiSharableNoteSnapshot | undefined): void {
    LexiShareService.activeOwner = owner;
    LexiShareService.activeGetter = getter;
  }

  static deactivateKnockSource(owner: string): void {
    if (LexiShareService.activeOwner !== owner) {
      return;
    }
    LexiShareService.activeOwner = '';
    LexiShareService.activeGetter = undefined;
  }

  static resolveActiveSharable(): LexiSharableNoteSnapshot | undefined {
    if (LexiShareService.activeGetter) {
      try {
        const active = LexiShareService.activeGetter();
        if (active && (active.title.trim().length > 0 || active.content.trim().length > 0)) {
          return active;
        }
      } catch {}
    }
    try {
      const draft = LexiContinuationSession.current();
      if (draft && (draft.title.trim().length > 0 || draft.content.trim().length > 0)) {
        const snapshot = new LexiSharableNoteSnapshot();
        snapshot.noteId = draft.sourceNoteId;
        snapshot.title = draft.title.trim() || '未命名笔记';
        snapshot.content = draft.content;
        snapshot.notebook = draft.notebook || '笔记';
        snapshot.tags = draft.tags.slice();
        snapshot.properties = draft.properties.map(
          (prop: NoteProperty): NoteProperty => new NoteProperty(prop.key, prop.propValue)
        );
        return snapshot;
      }
    } catch {}
    return undefined;
  }

  static async handleKnockShare(context: common.Context, target: harmonyShare.SharableTarget): Promise<void> {
    try {
      if (deviceInfo.deviceType === '2in1' && deviceInfo.apiAvailable('26.0.0')) {
        const info = target.getInfo();
        if (info && info.coordinate) {
          LexiShareService.lastKnockCoordX = info.coordinate.screenX;
          LexiShareService.lastKnockCoordY = info.coordinate.screenY;
        }
      }
    } catch {}

    const active = LexiShareService.resolveActiveSharable();
    if (!active) {
      try {
        target.clarifyNonShare({ message: '请先打开一篇笔记再使用碰一碰分享' }).catch((): void => {});
      } catch {
        try {
          target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((): void => {});
        } catch {}
      }
      return;
    }

    try {
      if (!active.filePath && active.noteId) {
        const saved = await LexiStorageService.getNoteById(active.noteId);
        if (saved) {
          active.filePath = saved.path;
          active.fileUri = await LexiStorageService.getNoteFileUri(saved);
        }
      }
      const shareData = LexiShareService.createFileSharedData(context, active, await LexiShareService.compactPreview(context));
      target.share(shareData).catch((): void => {});
    } catch {
      try {
        target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((): void => {});
      } catch {}
    }
  }

  static registerWindow(key: string, context: common.UIAbilityContext, mainWindow: window.Window | undefined): void {
    if (!mainWindow || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    LexiShareService.unregisterWindow(key);
    try {
      const windowId = mainWindow.getWindowProperties().id;
      const is2in1 = deviceInfo.deviceType === '2in1';
      const knockCallback = (target: harmonyShare.SharableTarget): void => {
        LexiShareService.handleKnockShare(context, target);
      };
      const binding = new LexiWindowShareBinding(context, windowId, is2in1, knockCallback);
      if (is2in1) {
        harmonyShare.on('knockShare', { windowId: windowId }, knockCallback);
        // Let the system receive files into the user's chosen location. The
        // dataReceive takeover API requires an app-sandbox destination.
      } else {
        harmonyShare.on('knockShare', knockCallback);
      }
      LexiShareService.windowBindings.set(key, binding);
    } catch (_error) {
      const err = _error as BusinessError;
      if (err && err.code) {
        // Ignore unsupported device/emulator capability errors gracefully
      }
    }
  }

  static unregisterWindow(key: string): void {
    const binding = LexiShareService.windowBindings.get(key);
    if (!binding) {
      return;
    }
    LexiShareService.windowBindings.delete(key);
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    try {
      if (binding.is2in1) {
        harmonyShare.off('knockShare', { windowId: binding.windowId }, binding.knockCallback);
      } else {
        harmonyShare.off('knockShare', binding.knockCallback);
      }
    } catch {}
  }
}
