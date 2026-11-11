import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginLimits, PluginRecord } from '../model/PluginModels';
import { PluginRpcRequest, PluginRpcResponse, PluginRuntimeBoot } from '../model/PluginContracts';
import { PluginRpcDispatcher, PluginSession } from './PluginRpcDispatcher';
import { PluginRuntimeScript, PluginRuntimeState } from './PluginRuntimeMessages';
import { PluginKeyboardFocus } from '../core/PluginKeyboardFocus';

const DOMAIN: number = 0x0A11;
const TAG: string = 'LexiPluginRuntime';

class PluginRuntimeAck {
  accepted: boolean = false;
  code: string = '';
  message: string = '';

  static of(accepted: boolean, code: string, message: string): string {
    const ack = new PluginRuntimeAck();
    ack.accepted = accepted;
    ack.code = code;
    ack.message = message;
    return JSON.stringify(ack);
  }
}

/**
 * ArkWeb bridge object. ArkWeb calls these methods synchronously from the page, so
 * `request` only validates and acknowledges; the real work runs asynchronously and is
 * delivered back through `__lexiRuntime.receiveResponse`.
 */
export class PluginRuntimeBridge {
  request(payload: string): string {
    return PluginRuntimeController.acceptRequest(payload);
  }

  log(level: string, message: string): void {
    PluginRuntimeController.log(level, message);
  }
}

/**
 * The single plugin runtime page (P09).
 *
 * One ArkWeb instance for the whole window, loading a fixed local page from rawfile.
 * It never loads a remote URL, never exposes a generic `invoke`/`readFile`/`eval` bridge,
 * and is destroyed with the page that mounts it.
 */
export class PluginRuntimeController {
  private static controller: webview.WebviewController | undefined = undefined;
  private static bridgeState: string = PluginRuntimeState.ABSENT;
  private static session: PluginSession | undefined = undefined;
  private static inFlight: Set<string> = new Set<string>();
  private static requestCounter: number = 0;
  private static lastError: string = '';
  private static diagnostics: string[] = [];
  private static bootPending: boolean = false;
  private static bootError: string = '';
  private static viewOutcome: string = '';

  static attach(controller: webview.WebviewController): void {
    PluginRuntimeController.controller = controller;
    PluginRuntimeController.bridgeState = PluginRuntimeState.READY;
    PluginRuntimeController.lastError = '';
    try { AppStorage.setOrCreate<string>('lexiPluginRuntimeState', PluginRuntimeState.READY); } catch (error) { /* non UI */ }
    hilog.info(DOMAIN, TAG, 'runtime page attached');
  }

  static detach(controller: webview.WebviewController): void {
    if (PluginRuntimeController.controller !== controller) { return; }
    PluginRuntimeController.controller = undefined;
    PluginRuntimeController.bridgeState = PluginRuntimeState.ABSENT;
    PluginRuntimeController.session = undefined;
    PluginRuntimeController.inFlight = new Set<string>();
    try { AppStorage.setOrCreate<string>('lexiPluginRuntimeState', PluginRuntimeState.ABSENT); } catch (error) { /* non UI */ }
    hilog.info(DOMAIN, TAG, 'runtime page detached');
  }

  static isReady(): boolean {
    return PluginRuntimeController.controller !== undefined && PluginRuntimeController.bridgeState === PluginRuntimeState.READY;
  }

  static state(): string {
    return PluginRuntimeController.bridgeState;
  }

  static reportError(message: string): void {
    PluginRuntimeController.lastError = message;
    if (PluginRuntimeController.diagnostics.length > 32) { PluginRuntimeController.diagnostics.shift(); }
    PluginRuntimeController.diagnostics.push(message);
    try { AppStorage.setOrCreate<string>('lexiPluginRuntimeError', message); } catch (error) { /* non UI */ }
  }

  static error(): string {
    return PluginRuntimeController.lastError;
  }

  static log(level: string, message: string): void {
    if (level === 'view-ready') { PluginRuntimeController.viewOutcome = 'ready'; return; }
    if (level === 'view-error') { PluginRuntimeController.viewOutcome = message || '插件视图加载失败'; return; }
    const text = `${level}: ${message}`.substring(0, 400);
    // While a boot is in flight, an error log from the page means the plugin failed to
    // start. `runJavaScript` cannot return the boot Promise, so this is the visible signal.
    if (level === 'error' && PluginRuntimeController.bootPending && PluginRuntimeController.bootError.length === 0) {
      PluginRuntimeController.bootError = message;
    }
    if (PluginRuntimeController.diagnostics.length > 32) { PluginRuntimeController.diagnostics.shift(); }
    PluginRuntimeController.diagnostics.push(text);
    if (level === 'error') { hilog.error(DOMAIN, TAG, '%{public}s', text); }
    else { hilog.info(DOMAIN, TAG, '%{public}s', text); }
  }

  private static async evaluate(script: string): Promise<void> {
    const controller = PluginRuntimeController.controller;
    if (!controller) {
      throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件运行时尚未就绪');
    }
    await controller.runJavaScript(script);
  }

  /** Boots a plugin into the page. Requires an attached controller and a live session. */
  static async boot(boot: PluginRuntimeBoot, session: PluginSession): Promise<void> {
    if (!PluginRuntimeController.isReady()) {
      throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件运行时尚未就绪');
    }
    PluginRuntimeController.session = session;
    PluginRuntimeController.inFlight = new Set<string>();
    PluginRuntimeController.bootPending = true;
    PluginRuntimeController.bootError = '';
    try {
      await PluginRuntimeController.evaluate(PluginRuntimeScript.bootCall(boot.toJson()));
      await PluginRuntimeController.settleBoot(1200);
    } catch (error) {
      PluginRuntimeController.bootPending = false;
      PluginRuntimeController.reportError(PluginErrors.messageOf(error));
      throw PluginErrors.raise(PluginErrorCode.PLUGIN_FAILED, PluginErrors.messageOf(error));
    }
    PluginRuntimeController.bootPending = false;
    if (PluginRuntimeController.bootError.length > 0) {
      const message = PluginRuntimeController.bootError;
      PluginRuntimeController.reportError(message);
      throw PluginErrors.raise(PluginErrorCode.PLUGIN_FAILED, message);
    }
  }

  /**
   * Waits for the page to report a boot failure. ArkWeb's `runJavaScript` cannot surface the
   * value returned by `__lexiRuntime.boot()`, so the page signals failures through
   * `lexiPluginBridge.log('error', ...)`. Without a failure we optimistically continue after
   * the settle window; a positive handshake is listed as future work in 01-architecture.md.
   */
  private static async settleBoot(timeoutMs: number): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (PluginRuntimeController.bootError.length > 0) { return; }
      await new Promise<void>((resolve: () => void): void => {
        setTimeout((): void => resolve(), 40);
      });
    }
  }

  static async unload(): Promise<void> {
    PluginRuntimeController.session = undefined;
    PluginRuntimeController.inFlight = new Set<string>();
    try {
      await PluginRuntimeController.evaluate(PluginRuntimeScript.unloadCall());
    } catch (error) {
      // A failed unload must not block disabling the plugin; tracked resources are still released.
      PluginRuntimeController.log('warn', `unload failed: ${PluginErrors.messageOf(error)}`);
    }
  }

  static async presentPlugin(): Promise<void> {
    PluginRuntimeController.viewOutcome = '';
    await PluginRuntimeController.evaluate("window.__lexiRuntime.present().then(function(r){window.lexiPluginBridge.log(r.ok?'view-ready':'view-error',r.error||'');});");
    const deadline = Date.now() + 5000;
    while (!PluginRuntimeController.viewOutcome && Date.now() < deadline) {
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 40); });
    }
    if (PluginRuntimeController.viewOutcome !== 'ready') {
      throw new Error(PluginRuntimeController.viewOutcome || '插件视图加载超时');
    }
  }

  static async sendEvent(eventJson: string): Promise<void> {
    if (!PluginRuntimeController.isReady()) { return; }
    try {
      await PluginRuntimeController.evaluate(PluginRuntimeScript.eventCall(eventJson));
    } catch (error) {
      PluginRuntimeController.log('warn', `event delivery failed: ${PluginErrors.messageOf(error)}`);
    }
  }

  static async runCommand(qualifiedId: string): Promise<void> {
    if (!PluginRuntimeController.isReady()) {
      throw PluginErrors.raise(PluginErrorCode.RUNTIME_UNAVAILABLE, '插件运行时尚未就绪');
    }
    await PluginRuntimeController.evaluate(PluginRuntimeScript.commandCall(qualifiedId));
  }

  /**
   * Synchronous acknowledgement for a page request. Rejects instantly when the session is
   * gone, the runtime is not attached, or too many requests are already running.
   */
  static acceptRequest(payload: string): string {
    const session = PluginRuntimeController.session;
    if (!session || !PluginRuntimeController.isReady()) {
      return PluginRuntimeAck.of(false, PluginErrorCode.RUNTIME_UNAVAILABLE, '插件运行时未就绪');
    }
    if (PluginRuntimeController.inFlight.size >= PluginLimits.MAX_RPC_IN_FLIGHT) {
      return PluginRuntimeAck.of(false, PluginErrorCode.RATE_LIMITED, '并发请求过多');
    }
    let request: PluginRpcRequest;
    try {
      request = PluginRpcRequest.parse(payload);
    } catch (error) {
      return PluginRuntimeAck.of(false, PluginErrors.codeOf(error), PluginErrors.messageOf(error));
    }
    if (request.token !== session.token || request.pluginId !== session.pluginId) {
      return PluginRuntimeAck.of(false, PluginErrorCode.PERMISSION_DENIED, '会话令牌或插件标识不匹配');
    }
    PluginRuntimeController.inFlight.add(request.id);
    // Dispatch outside the synchronous bridge call: the page must not block on native work.
    setTimeout((): void => {
      PluginRuntimeController.execute(session, request).catch((): void => {});
    }, 0);
    return PluginRuntimeAck.of(true, '', '');
  }

  private static async execute(session: PluginSession, request: PluginRpcRequest): Promise<void> {
    let response: string;
    try {
      const result = await PluginRpcDispatcher.dispatch(session, request);
      response = PluginRpcResponse.success(request.id, result);
    } catch (error) {
      const code = PluginErrors.codeOf(error);
      const message = PluginErrors.messageOf(error);
      if (code === PluginErrorCode.UNKNOWN) {
        PluginRuntimeController.log('error', `${request.method}: ${message}`);
      }
      response = PluginRpcResponse.failure(request.id, code, message);
    } finally {
      PluginRuntimeController.inFlight.delete(request.id);
    }
    if (PluginRuntimeController.session !== session) { return; }
    try {
      await PluginRuntimeController.evaluate(PluginRuntimeScript.responseCall(response));
    } catch (error) {
      PluginRuntimeController.log('warn', `response delivery failed: ${PluginErrors.messageOf(error)}`);
    }
  }

  static nextRequestId(): string {
    PluginRuntimeController.requestCounter++;
    return `host-${PluginRuntimeController.requestCounter}`;
  }

  static reset(): void {
    PluginRuntimeController.controller = undefined;
    PluginRuntimeController.bridgeState = PluginRuntimeState.ABSENT;
    PluginRuntimeController.session = undefined;
    PluginRuntimeController.inFlight = new Set<string>();
    PluginRuntimeController.requestCounter = 0;
    PluginRuntimeController.lastError = '';
    PluginRuntimeController.diagnostics = [];
  }

  static pendingCount(): number {
    return PluginRuntimeController.inFlight.size;
  }
}

/**
 * Mounts the runtime page. Render it once, hidden, next to the workspace; it is never
 * reused for formula rendering and never receives third-party content from another host.
 */
@Component
export struct PluginRuntimeHost {
  @Prop @Watch('surfaceChanged') surfaceVisible: boolean = false;
  // Visible plugin panels must load at their final size so ArkWeb computes the
  // mobile viewport before a plugin is presented. Background-only hosts remain 1x1.
  @Prop reserveSurfaceSize: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: PluginRuntimeBridge = new PluginRuntimeBridge();
  private declared: boolean = false;

  aboutToAppear(): void {
    PluginKeyboardFocus.attach(this.controller, this.surfaceVisible);
  }

  private surfaceChanged(): void {
    PluginKeyboardFocus.setVisible(this.controller, this.surfaceVisible);
  }

  aboutToDisappear(): void {
    this.declared = false;
    PluginKeyboardFocus.detach(this.controller);
    PluginRuntimeController.detach(this.controller);
  }

  build() {
    Web({ src: $rawfile('plugin-runtime/index.html'), controller: this.controller, renderMode: RenderMode.ASYNC_RENDER })
      .width(this.surfaceVisible || this.reserveSurfaceSize ? '100%' : 1)
      .height(this.surfaceVisible || this.reserveSurfaceSize ? '100%' : 1)
      .opacity(this.surfaceVisible ? 1 : 0.01)
      .hitTestBehavior(this.surfaceVisible ? HitTestMode.Default : HitTestMode.None)
      .javaScriptAccess(true).fileAccess(false).blockNetwork(true).onlineImageAccess(false)
      .domStorageAccess(false).geolocationAccess(false).multiWindowAccess(false)
      .onFocus((): void => { PluginKeyboardFocus.setFocused(this.controller, true); })
      .onBlur((): void => { PluginKeyboardFocus.setFocused(this.controller, false); })
      .javaScriptProxy({
        object: this.bridge,
        name: 'lexiPluginBridge',
        methodList: ['request', 'log'],
        controller: this.controller
      })
      .onPageEnd((): void => {
        this.declared = true;
        PluginRuntimeController.attach(this.controller);
      })
      .onErrorReceive((): void => {
        PluginRuntimeController.reportError('插件运行时页面加载失败');
      })
      .onRenderExited((): void => {
        PluginKeyboardFocus.detach(this.controller);
        PluginRuntimeController.detach(this.controller);
      })
  }
}
