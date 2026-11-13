import Foundation
import SwiftUI
import AppKit
import WebKit

struct PluginLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let pluginId: String
    let level: String
    let message: String
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) {
        self.target = target
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Hosts one sandboxed `WKWebView` running `plugin-runtime/index.html` + `runtime.bundle.js`
/// for a single enabled plugin.
@MainActor
final class PluginRuntimeSession: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let pluginId: String
    let token: String
    let webView: WKWebView

    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isPageLoaded = false
    private var hiddenWindow: NSWindow?

    var onRpcRequest: ((String) -> Void)?
    var onLog: ((String, String) -> Void)?
    var onProcessCrash: ((String) -> Void)?

    init(pluginId: String, token: String) {
        self.pluginId = pluginId
        self.token = token

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let userContent = WKUserContentController()
        // Synchronous host bridge expected by `packages/plugin-runtime-js/src/bridge.js`
        let shimSource = """
        (function() {
          window.lexiPluginBridge = {
            request: function(raw) {
              try {
                if (typeof raw !== 'string' || raw.length === 0) {
                  return JSON.stringify({ accepted: false, code: 'E_PROTOCOL', message: 'empty rpc request' });
                }
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lexiPluginRpc) {
                  window.webkit.messageHandlers.lexiPluginRpc.postMessage(raw);
                  return JSON.stringify({ accepted: true, code: '', message: '' });
                }
                return JSON.stringify({ accepted: false, code: 'E_RUNTIME_UNAVAILABLE', message: 'bridge unavailable' });
              } catch (err) {
                return JSON.stringify({ accepted: false, code: 'E_UNKNOWN', message: String(err) });
              }
            },
            log: function(level, message) {
              try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lexiPluginLog) {
                  window.webkit.messageHandlers.lexiPluginLog.postMessage({
                    level: String(level || 'info'),
                    message: String(message || '')
                  });
                }
              } catch (_) {}
            }
          };
        })();
        """
        userContent.addUserScript(WKUserScript(source: shimSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = userContent

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 340, height: 520), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()

        let weakProxy = WeakScriptMessageHandler(target: self)
        userContent.add(weakProxy, name: "lexiPluginRpc")
        userContent.add(weakProxy, name: "lexiPluginLog")
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func ensureHostedOffscreenIfNeeded() {
        guard webView.window == nil else { return }
        if hiddenWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 520),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.alphaValue = 0
            win.ignoresMouseEvents = true
            hiddenWindow = win
        }
        if let contentView = hiddenWindow?.contentView, webView.superview !== contentView {
            webView.frame = contentView.bounds
            webView.autoresizingMask = [.width, .height]
            contentView.addSubview(webView)
        }
    }

    func attach(to container: NSView) {
        if webView.superview !== container {
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
        hiddenWindow?.orderOut(nil)
    }

    func detachToAnchorIfNeeded(from view: NSView) {
        guard webView.superview === view else { return }
        ensureHostedOffscreenIfNeeded()
    }

    func loadRuntimeIfNeeded() async throws {
        ensureHostedOffscreenIfNeeded()
        if isPageLoaded { return }
        guard let htmlURL = Self.locateRuntimeHTML() else {
            throw PluginHostError(PluginErrorCode.runtimeUnavailable, "找不到内置插件运行时资源 plugin-runtime/index.html")
        }
        let dirURL = htmlURL.deletingLastPathComponent()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            self.webView.loadFileURL(htmlURL, allowingReadAccessTo: dirURL)
        }
    }

    static func locateRuntimeHTML() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "plugin-runtime") {
            return url
        }
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            return url
        }
        // Fallback for unbundled swift test / development runs
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/plugin-runtime/index.html"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/plugin-runtime/index.html")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Runtime Calls

    func boot(_ bootPayload: PluginRuntimeBoot) async throws {
        try await loadRuntimeIfNeeded()
        let encoder = JSONEncoder()
        let data = try encoder.encode(bootPayload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw PluginHostError(PluginErrorCode.protocolError, "无法编码插件启动载荷")
        }
        let rawResult = try await webView.callAsyncJavaScript(
            "if (!window.__lexiRuntime) { throw new Error('plugin runtime missing'); } return await window.__lexiRuntime.boot(raw);",
            arguments: ["raw": jsonString],
            in: nil,
            contentWorld: .page
        )
        if let dict = rawResult as? [String: Any], (dict["ok"] as? Bool) == false {
            let code = dict["code"] as? String ?? PluginErrorCode.pluginFailed
            let msg = dict["error"] as? String ?? "插件启动失败"
            throw PluginHostError(code, msg)
        }
    }

    func applyTheme(palette: ThemePalette) async {
        guard isPageLoaded else { return }
        let css = """
        :root {
          --background-primary: \(palette.workspacePageHex);
          --background-secondary: \(palette.workspaceInspectorHex);
          --text-normal: \(palette.textPrimaryHex);
          --text-muted: \(palette.textSecondaryHex);
          --interactive-accent: \(palette.brandHex);
          --interactive-accent-hover: \(palette.brandInkHex);
          --background-modifier-border: \(palette.workspaceLineHex);
          color-scheme: \(palette.isDark ? "dark" : "light");
        }
        body {
          background: transparent;
          color: \(palette.textPrimaryHex);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
          margin: 0;
        }
        """
        _ = try? await webView.callAsyncJavaScript(
            """
            let el = document.getElementById('lexi-host-theme');
            if (!el) { el = document.createElement('style'); el.id = 'lexi-host-theme'; document.head.appendChild(el); }
            el.textContent = cssText;
            """,
            arguments: ["cssText": css],
            in: nil,
            contentWorld: .page
        )
    }

    func sendResponse(_ responseJson: String) async {
        guard isPageLoaded else { return }
        _ = try? await webView.callAsyncJavaScript(
            "if (window.__lexiRuntime && window.__lexiRuntime.receiveResponse) { return window.__lexiRuntime.receiveResponse(raw); } return false;",
            arguments: ["raw": responseJson],
            in: nil,
            contentWorld: .page
        )
    }

    func sendEvent(_ event: PluginRpcEvent) async {
        guard isPageLoaded,
              let data = try? JSONEncoder().encode(event),
              let raw = String(data: data, encoding: .utf8) else { return }
        _ = try? await webView.callAsyncJavaScript(
            "if (window.__lexiRuntime && window.__lexiRuntime.receiveEvent) { return window.__lexiRuntime.receiveEvent(raw); } return false;",
            arguments: ["raw": raw],
            in: nil,
            contentWorld: .page
        )
    }

    @discardableResult
    func runCommand(qualifiedId: String) async -> Bool {
        guard isPageLoaded else { return false }
        let res = try? await webView.callAsyncJavaScript(
            "if (window.__lexiRuntime && window.__lexiRuntime.runCommand) { return Boolean(window.__lexiRuntime.runCommand(id)); } return false;",
            arguments: ["id": qualifiedId],
            in: nil,
            contentWorld: .page
        )
        return (res as? Bool) ?? false
    }

    func present(viewId: String) async throws {
        guard isPageLoaded else {
            throw PluginHostError(PluginErrorCode.runtimeUnavailable, "插件运行时尚未就绪")
        }
        let res = try await webView.callAsyncJavaScript(
            "if (window.__lexiRuntime && window.__lexiRuntime.present) { return await window.__lexiRuntime.present(viewId); } return { ok: false, error: 'present unavailable' };",
            arguments: ["viewId": viewId],
            in: nil,
            contentWorld: .page
        )
        if let dict = res as? [String: Any], (dict["ok"] as? Bool) == false {
            throw PluginHostError(PluginErrorCode.pluginFailed, dict["error"] as? String ?? "无法渲染插件视图")
        }
    }

    func unload() async {
        if isPageLoaded {
            _ = try? await webView.callAsyncJavaScript(
                "if (window.__lexiRuntime && window.__lexiRuntime.unload) { return await window.__lexiRuntime.unload(); } return true;",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lexiPluginRpc")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lexiPluginLog")
        webView.stopLoading()
        webView.removeFromSuperview()
        hiddenWindow?.close()
        hiddenWindow = nil
        isPageLoaded = false
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "lexiPluginRpc", let raw = message.body as? String {
            onRpcRequest?(raw)
        } else if message.name == "lexiPluginLog", let dict = message.body as? [String: Any] {
            let level = dict["level"] as? String ?? "info"
            let text = dict["message"] as? String ?? ""
            onLog?(level, text)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: PluginHostError(PluginErrorCode.runtimeUnavailable, error.localizedDescription))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: PluginHostError(PluginErrorCode.runtimeUnavailable, error.localizedDescription))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL, let htmlURL = Self.locateRuntimeHTML(),
           url.deletingLastPathComponent().standardizedFileURL == htmlURL.deletingLastPathComponent().standardizedFileURL {
            decisionHandler(.allow)
            return
        }
        // Strictly block any external network or foreign URL navigation inside the plugin sandbox.
        onLog?("warn", "沙盒拦截了未授权导航：\(url.absoluteString)")
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageLoaded = false
        onProcessCrash?("插件渲染进程意外终止")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}

// MARK: - SwiftUI Reparenting Host View

struct PluginWebHostView: NSViewRepresentable {
    @ObservedObject var manager: PluginManager
    let pluginId: String
    let viewId: String

    func makeNSView(context: Context) -> PluginContainerNSView {
        let view = PluginContainerNSView()
        context.coordinator.bind(container: view, manager: manager, pluginId: pluginId, viewId: viewId)
        return view
    }

    func updateNSView(_ nsView: PluginContainerNSView, context: Context) {
        context.coordinator.bind(container: nsView, manager: manager, pluginId: pluginId, viewId: viewId)
    }

    static func dismantleNSView(_ nsView: PluginContainerNSView, coordinator: Coordinator) {
        coordinator.unbind(container: nsView)
    }

    final class Coordinator {
        private var currentPluginId: String = ""
        private var currentViewId: String = ""
        private weak var manager: PluginManager?

        @MainActor
        func bind(container: PluginContainerNSView, manager: PluginManager, pluginId: String, viewId: String) {
            self.manager = manager
            container.attach(session: manager.session(for: pluginId))
            if currentPluginId != pluginId || currentViewId != viewId {
                currentPluginId = pluginId
                currentViewId = viewId
                Task { @MainActor in
                    await manager.presentView(pluginId: pluginId, viewId: viewId)
                }
            }
        }

        @MainActor
        func unbind(container: PluginContainerNSView) {
            if let session = manager?.session(for: currentPluginId) {
                session.detachToAnchorIfNeeded(from: container)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

final class PluginContainerNSView: NSView {
    private weak var attachedSession: PluginRuntimeSession?

    @MainActor
    func attach(session: PluginRuntimeSession?) {
        if let attachedSession, attachedSession !== session {
            attachedSession.detachToAnchorIfNeeded(from: self)
        }
        attachedSession = session
        session?.attach(to: self)
    }
}
