import AppKit
import CryptoKit
import Foundation
import WebKit

struct RenderedMathBitmap {
    let image: NSImage
    let size: CGSize
    let descent: CGFloat
    let engine: String
}

enum MathRenderStatus {
    case pending
    case ready(RenderedMathBitmap)
    case failed(String)
}

private struct MathCacheMeta: Codable {
    var width: Double
    var height: Double
    var descent: Double
    var engine: String
}

/// Renders LaTeX formulas asynchronously using bundled offline KaTeX with MathJax SVG fallback
/// and caches high-DPI transparent bitmaps plus baseline metrics on disk and in memory.
@MainActor
final class LexiMathService: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = LexiMathService()

    @Published private(set) var revision: UInt64 = 0

    private var memoryCache: [String: RenderedMathBitmap] = [:]
    private var failedCache: [String: String] = [:]
    private var inFlightKeys: Set<String> = []
    private var queue: [RenderJob] = []
    private var processing = false

    private var hostWindow: NSWindow?
    private var webView: WKWebView?
    private var rendererReady = false
    private var navigationContinuations: [CheckedContinuation<Void, Never>] = []
    private let cacheFolder: URL?

    private struct RenderJob {
        let key: String
        let latex: String
        let displayMode: Bool
        let fontSize: CGFloat
        let colorHex: String
    }

    private override init() {
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let folder = caches.appendingPathComponent("LexiNote/math-cache-v1", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.cacheFolder = folder
        } else {
            self.cacheFolder = nil
        }
        super.init()
    }

    static func resolveLexiMathDirectory() -> URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("lexi-math", isDirectory: true),
           FileManager.default.fileExists(atPath: url.appendingPathComponent("mac-renderer.html").path) {
            return url
        }
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let sibling = execDir.appendingPathComponent("../Resources/lexi-math", isDirectory: true).standardizedFileURL
            if FileManager.default.fileExists(atPath: sibling.appendingPathComponent("mac-renderer.html").path) {
                return sibling
            }
        }
        let devCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Resources/lexi-math", isDirectory: true)
        if FileManager.default.fileExists(atPath: devCandidate.appendingPathComponent("mac-renderer.html").path) {
            return devCandidate
        }
        return nil
    }

    var isRendererAvailable: Bool {
        Self.resolveLexiMathDirectory() != nil
    }

    func lookup(latex: String, displayMode: Bool, fontSize: CGFloat, colorHex: String) -> MathRenderStatus {
        let normalized = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .failed("Empty formula") }
        let key = Self.cacheKey(latex: normalized, displayMode: displayMode, fontSize: fontSize, colorHex: colorHex)

        if let cached = memoryCache[key] {
            return .ready(cached)
        }
        if let err = failedCache[key] {
            return .failed(err)
        }
        if let disk = loadFromDisk(key: key) {
            memoryCache[key] = disk
            return .ready(disk)
        }

        enqueue(RenderJob(key: key, latex: normalized, displayMode: displayMode, fontSize: fontSize, colorHex: colorHex))
        return .pending
    }

    /// Imperatively renders a formula to a cached bitmap (used by tests and prewarming).
    func renderFormula(latex: String,
                       displayMode: Bool,
                       fontSize: CGFloat,
                       colorHex: String) async -> Result<RenderedMathBitmap, NSError> {
        let normalized = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failure(NSError(domain: "LexiMath", code: 1, userInfo: [NSLocalizedDescriptionKey: "公式内容为空"]))
        }
        let key = Self.cacheKey(latex: normalized, displayMode: displayMode, fontSize: fontSize, colorHex: colorHex)
        if let cached = memoryCache[key] { return .success(cached) }
        if let disk = loadFromDisk(key: key) {
            memoryCache[key] = disk
            return .success(disk)
        }
        if let err = failedCache[key] {
            return .failure(NSError(domain: "LexiMath", code: 2, userInfo: [NSLocalizedDescriptionKey: err]))
        }

        let result = await performSingleRender(
            RenderJob(key: key, latex: normalized, displayMode: displayMode, fontSize: fontSize, colorHex: colorHex)
        )
        switch result {
        case .success(let bitmap):
            memoryCache[key] = bitmap
            saveToDisk(bitmap, key: key)
            revision &+= 1
            return .success(bitmap)
        case .failure(let error):
            failedCache[key] = error.localizedDescription
            revision &+= 1
            return .failure(error)
        }
    }

    func clearCache() {
        memoryCache.removeAll()
        failedCache.removeAll()
        if let cacheFolder {
            try? FileManager.default.removeItem(at: cacheFolder)
            try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        }
        revision &+= 1
    }

    // MARK: Queue

    private func enqueue(_ job: RenderJob) {
        guard !inFlightKeys.contains(job.key) else { return }
        inFlightKeys.insert(job.key)
        queue.append(job)
        guard !processing else { return }
        processing = true
        Task { @MainActor [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        defer { processing = false }
        while !queue.isEmpty {
            let job = queue.removeFirst()
            let outcome = await performSingleRender(job)
            inFlightKeys.remove(job.key)
            switch outcome {
            case .success(let bitmap):
                memoryCache[job.key] = bitmap
                saveToDisk(bitmap, key: job.key)
            case .failure(let error):
                failedCache[job.key] = error.localizedDescription
            }
            revision &+= 1
        }
    }

    // MARK: WebView rendering

    private func ensureWebView() async -> WKWebView? {
        if let webView, rendererReady { return webView }
        guard let dir = Self.resolveLexiMathDirectory() else { return nil }
        let htmlURL = dir.appendingPathComponent("mac-renderer.html")

        if webView == nil {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 2200, height: 1100), configuration: config)
            view.setValue(false, forKey: "drawsBackground")
            view.navigationDelegate = self

            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 2200, height: 1100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
            window.contentView = view
            window.orderFront(nil)

            self.hostWindow = window
            self.webView = view
            view.loadFileURL(htmlURL, allowingReadAccessTo: dir)
        }

        if !rendererReady {
            await withCheckedContinuation { continuation in
                if rendererReady {
                    continuation.resume()
                } else {
                    navigationContinuations.append(continuation)
                }
            }
        }
        return webView
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rendererReady = true
            let waiters = self.navigationContinuations
            self.navigationContinuations.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.resetWebViewOnFailure()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.resetWebViewOnFailure()
        }
    }

    private func resetWebViewOnFailure() {
        rendererReady = false
        webView?.stopLoading()
        webView = nil
        hostWindow?.close()
        hostWindow = nil
        let waiters = navigationContinuations
        navigationContinuations.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func performSingleRender(_ job: RenderJob) async -> Result<RenderedMathBitmap, NSError> {
        guard let webView = await ensureWebView() else {
            return .failure(NSError(domain: "LexiMath", code: 3, userInfo: [NSLocalizedDescriptionKey: "未找到离线 KaTeX/MathJax 资源"]))
        }
        guard rendererReady else {
            return .failure(NSError(domain: "LexiMath", code: 4, userInfo: [NSLocalizedDescriptionKey: "公式渲染器尚未就绪"]))
        }

        do {
            let raw = try await evaluateAsyncJavaScript(
                "return await window.lexiPrepareFormula(payload);",
                arguments: [
                    "payload": [
                        "latex": job.latex,
                        "displayMode": job.displayMode,
                        "fontSize": Double(job.fontSize),
                        "colorHex": job.colorHex
                    ]
                ],
                in: webView
            )
            guard let jsonString = raw as? String,
                  let data = jsonString.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(NSError(domain: "LexiMath", code: 5, userInfo: [NSLocalizedDescriptionKey: "公式渲染返回格式无效"]))
            }
            if (obj["ok"] as? Bool) != true {
                let message = (obj["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(NSError(domain: "LexiMath", code: 6, userInfo: [
                    NSLocalizedDescriptionKey: (message?.isEmpty == false ? message! : "LaTeX 语法错误")
                ]))
            }

            let x = CGFloat((obj["x"] as? Double) ?? 0)
            let y = CGFloat((obj["y"] as? Double) ?? 0)
            let width = max(1, CGFloat((obj["width"] as? Double) ?? 1))
            let height = max(1, CGFloat((obj["height"] as? Double) ?? 1))
            let descent = max(0, CGFloat((obj["descent"] as? Double) ?? 0))
            let engine = (obj["engine"] as? String) ?? "katex"

            let neededW = max(2200, ceil(x + width + 40))
            let neededH = max(1100, ceil(y + height + 40))
            if webView.frame.width < neededW || webView.frame.height < neededH {
                let targetSize = NSSize(width: min(neededW, 4096), height: min(neededH, 4096))
                hostWindow?.setContentSize(targetSize)
                webView.frame = NSRect(origin: .zero, size: targetSize)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: x, y: y, width: width, height: height)
            let scale = max(2.0, hostWindow?.backingScaleFactor ?? 2.0)
            config.snapshotWidth = NSNumber(value: Double(ceil(width * scale)))

            let rawSnapshot = try await webView.takeSnapshot(configuration: config)
            let normalizedImage: NSImage
            if let cgImage = rawSnapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                normalizedImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            } else {
                normalizedImage = rawSnapshot
                normalizedImage.size = NSSize(width: width, height: height)
            }
            return .success(RenderedMathBitmap(
                image: normalizedImage,
                size: CGSize(width: width, height: height),
                descent: descent,
                engine: engine
            ))
        } catch {
            return .failure(NSError(domain: "LexiMath", code: 7, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
        }
    }

    private func evaluateAsyncJavaScript(_ script: String,
                                         arguments: [String: Any],
                                         in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: Disk cache & hashing

    private static func cacheKey(latex: String, displayMode: Bool, fontSize: CGFloat, colorHex: String) -> String {
        let seed = "v1|\(displayMode ? "B" : "I")|\(Int((fontSize * 10).rounded()))|\(colorHex.lowercased())|\(latex)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadFromDisk(key: String) -> RenderedMathBitmap? {
        guard let cacheFolder else { return nil }
        let pngURL = cacheFolder.appendingPathComponent("\(key).png")
        let metaURL = cacheFolder.appendingPathComponent("\(key).json")
        guard let pngData = try? Data(contentsOf: pngURL),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(MathCacheMeta.self, from: metaData),
              let raw = NSImage(data: pngData),
              let cg = raw.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let pointSize = NSSize(width: meta.width, height: meta.height)
        let image = NSImage(cgImage: cg, size: pointSize)
        return RenderedMathBitmap(
            image: image,
            size: pointSize,
            descent: CGFloat(meta.descent),
            engine: meta.engine
        )
    }

    private func saveToDisk(_ bitmap: RenderedMathBitmap, key: String) {
        guard let cacheFolder else { return }
        guard let cgImage = bitmap.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
        let meta = MathCacheMeta(
            width: Double(bitmap.size.width),
            height: Double(bitmap.size.height),
            descent: Double(bitmap.descent),
            engine: bitmap.engine
        )
        guard let metaData = try? JSONEncoder().encode(meta) else { return }
        let pngURL = cacheFolder.appendingPathComponent("\(key).png")
        let metaURL = cacheFolder.appendingPathComponent("\(key).json")
        try? pngData.write(to: pngURL, options: .atomic)
        try? metaData.write(to: metaURL, options: .atomic)
    }
}
