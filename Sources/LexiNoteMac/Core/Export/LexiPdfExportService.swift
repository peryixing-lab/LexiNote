import AppKit
import Foundation
import PDFKit
import WebKit

private final class LexiPdfSchemeHandler: NSObject, WKURLSchemeHandler {
    private let htmlData: Data
    private let lexiMathDir: URL?

    init(html: String, lexiMathDir: URL?) {
        self.htmlData = Data(html.utf8)
        self.lexiMathDir = lexiMathDir
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "LexiPdf", code: 400))
            return
        }
        let path = url.path
        if path == "/document.html" || path == "/" {
            respond(urlSchemeTask, url: url, data: htmlData, mimeType: "text/html; charset=utf-8")
            return
        }

        guard let base = lexiMathDir?.standardizedFileURL else {
            urlSchemeTask.didFailWithError(NSError(domain: "LexiPdf", code: 404))
            return
        }
        let relative = String(path.drop(while: { $0 == "/" })).removingPercentEncoding ?? String(path.drop(while: { $0 == "/" }))
        let target = base.appendingPathComponent(relative).standardizedFileURL
        guard target.path == base.path || target.path.hasPrefix(base.path + "/"),
              let data = try? Data(contentsOf: target) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LexiPdf", code: 404))
            return
        }
        respond(urlSchemeTask, url: url, data: data, mimeType: Self.mimeType(for: target.pathExtension))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mimeType: String) {
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: mimeType.contains("utf-8") ? "utf-8" : nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }
}

/// Renders Markdown notes with offline KaTeX/MathJax formulas into paginated A4 PDFs.
@MainActor
final class LexiPdfExportService: NSObject, WKNavigationDelegate {
    static let shared = LexiPdfExportService()

    private var activeContinuations: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]

    private override init() {
        super.init()
    }

    func exportPDF(note: Note, vaultURL: URL?, to outputURL: URL) async throws -> Data {
        let data = try await renderPDFData(note: note, vaultURL: vaultURL)
        try LexiSafeIO.atomicWriteData(data, to: outputURL)
        return data
    }

    func renderPDFData(note: Note, vaultURL: URL?) async throws -> Data {
        let html = buildExportHtml(note: note, vaultURL: vaultURL, inlineAssetsForPdf: true)
        let lexiMathDir = LexiMathService.resolveLexiMathDirectory()
        let schemeHandler = LexiPdfSchemeHandler(html: html, lexiMathDir: lexiMathDir)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "lexi-pdf")

        // A4 printable width is ~595.28pt (1pt = 1 CSS px in WKWebView PDF output).
        let pageWidth: CGFloat = 595.28
        let initialHeight: CGFloat = 841.89
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: initialHeight), configuration: config)
        webView.navigationDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: pageWidth, height: initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .white
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = webView
        window.orderFront(nil)

        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            window.close()
        }

        let entryURL = URL(string: "lexi-pdf://app/document.html")!
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activeContinuations[ObjectIdentifier(webView)] = continuation
            webView.load(URLRequest(url: entryURL))
        }

        // Wait until offline KaTeX/MathJax math rendering, web fonts, and images finish settling.
        let layoutRaw = try? await evaluateAsyncJavaScript("return await window.lexiWaitForPdfReady();", on: webView)
        try? await Task.sleep(nanoseconds: 60_000_000)

        let pdfConfig = WKPDFConfiguration()
        let rawPdfData = try await createVectorPDF(configuration: pdfConfig, on: webView)
        let avoidSpans = Self.parseAvoidSpans(from: layoutRaw)
        return Self.paginateVectorPdfToA4(rawPdfData: rawPdfData, avoidSpans: avoidSpans)
    }

    private func evaluateAsyncJavaScript(_ script: String, on webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func createVectorPDF(configuration: WKPDFConfiguration, on webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func parseAvoidSpans(from raw: Any?) -> [(top: CGFloat, bottom: CGFloat)] {
        guard let jsonString = raw as? String,
              let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["avoidRects"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            guard let top = item["top"] as? Double,
                  let bottom = item["bottom"] as? Double,
                  bottom > top else { return nil }
            return (CGFloat(top), CGFloat(bottom))
        }
    }

    /// Slices the single continuous vector WKWebView PDF into standard A4 vector pages
    /// while avoiding splitting formulas, tables, callouts, and code blocks mid-element.
    private static func paginateVectorPdfToA4(rawPdfData: Data, avoidSpans: [(top: CGFloat, bottom: CGFloat)]) -> Data {
        guard let provider = CGDataProvider(data: rawPdfData as CFData),
              let sourceDoc = CGPDFDocument(provider),
              let sourcePage = sourceDoc.page(at: 1) else {
            return rawPdfData
        }
        let sourceBox = sourcePage.getBoxRect(.mediaBox)
        let a4Width: CGFloat = 595.28
        let a4Height: CGFloat = 841.89
        let totalHeight = sourceBox.height
        guard sourceBox.width > 0, totalHeight > a4Height + 2 else {
            return rawPdfData
        }

        let scale = min(1.0, a4Width / sourceBox.width)
        var slices: [(start: CGFloat, end: CGFloat, topPad: CGFloat)] = []
        var cursor: CGFloat = 0
        var pageIndex = 0
        while cursor < totalHeight - 0.5 && pageIndex < 200 {
            let topPad: CGFloat = pageIndex == 0 ? 0 : 36
            let bottomPad: CGFloat = 36
            let maxContent = (a4Height - topPad - bottomPad) / scale
            var proposedEnd = min(totalHeight, cursor + maxContent)

            if proposedEnd < totalHeight {
                for span in avoidSpans where span.top < proposedEnd && span.bottom > proposedEnd {
                    if span.top - 6 > cursor + 100 / scale {
                        proposedEnd = span.top - 6
                    }
                }
            }
            if proposedEnd <= cursor + 1 {
                proposedEnd = min(totalHeight, cursor + maxContent)
            }
            slices.append((cursor, proposedEnd, topPad))
            cursor = proposedEnd
            pageIndex += 1
        }

        let outputData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: a4Width, height: a4Height)
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
              let pdfCtx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return rawPdfData
        }

        for slice in slices {
            let sliceH = slice.end - slice.start
            let scaledH = sliceH * scale
            let bottomPad = a4Height - slice.topPad - scaledH
            pdfCtx.beginPDFPage(nil)
            pdfCtx.setFillColor(NSColor.white.cgColor)
            pdfCtx.fill(mediaBox)

            pdfCtx.saveGState()
            pdfCtx.clip(to: CGRect(x: 0, y: bottomPad, width: a4Width, height: scaledH))
            let tx = (a4Width - sourceBox.width * scale) / 2.0
            let ty = (a4Height - slice.topPad) - (totalHeight - slice.start) * scale
            pdfCtx.translateBy(x: tx, y: ty)
            pdfCtx.scaleBy(x: scale, y: scale)
            pdfCtx.drawPDFPage(sourcePage)
            pdfCtx.restoreGState()
            pdfCtx.endPDFPage()
        }
        pdfCtx.closePDF()
        return outputData as Data
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(webView)
            if let cont = self.activeContinuations.removeValue(forKey: key) {
                cont.resume()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(webView)
            if let cont = self.activeContinuations.removeValue(forKey: key) {
                cont.resume(throwing: error)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(webView)
            if let cont = self.activeContinuations.removeValue(forKey: key) {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: HTML generation

    func buildExportHtml(note: Note, vaultURL: URL?, inlineAssetsForPdf: Bool) -> String {
        let blocks = MarkdownParser.parse(note.content)
        let title = escapeHtml(note.displayTitle)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var metaItems: [String] = []
        if !note.notebook.isEmpty { metaItems.append("笔记本：\(escapeHtml(note.notebook))") }
        metaItems.append("更新：\(escapeHtml(dateFormatter.string(from: note.updatedAt)))")
        if !note.tags.isEmpty {
            metaItems.append("标签：" + note.tags.map { "#\(escapeHtml($0))" }.joined(separator: " "))
        }

        let bodyHtml = blocks.map { renderBlock($0, vaultURL: vaultURL, noteRelativePath: note.path) }.joined(separator: "\n")
        let mathHead = inlineAssetsForPdf
            ? """
              <link rel="stylesheet" href="lexi-pdf://app/katex/katex.min.css">
              <script src="lexi-pdf://app/katex/katex.min.js"></script>
              <script src="lexi-pdf://app/svg/config.js"></script>
              <script src="lexi-pdf://app/svg/mathjax.js"></script>
              <script src="lexi-pdf://app/svg/bitmap.js"></script>
              """
            : ""

        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          \(mathHead)
          <style>
            @page { size: A4; margin: 16mm 15mm; }
            * { box-sizing: border-box; }
            html, body {
              margin: 0;
              padding: 0;
              background: #ffffff;
              color: #1f1b2d;
              font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
              font-size: 10.5pt;
              line-height: 1.72;
              -webkit-print-color-adjust: exact;
              print-color-adjust: exact;
            }
            main.doc {
              width: 100%;
              max-width: 595px;
              margin: 0 auto;
              padding: 40px 42px 24px;
            }
            header.doc-header {
              padding-bottom: 14px;
              margin-bottom: 18px;
              border-bottom: 1px solid #e6e2f0;
            }
            header.doc-header h1 {
              margin: 0 0 6px;
              font-size: 21pt;
              font-weight: 700;
              line-height: 1.3;
              color: #171324;
            }
            .doc-meta {
              font-size: 9pt;
              color: #6b647d;
              display: flex;
              flex-wrap: wrap;
              gap: 12px;
            }
            h1, h2, h3, h4, h5, h6 {
              color: #171324;
              margin: 18px 0 8px;
              line-height: 1.35;
              break-after: avoid;
            }
            h1 { font-size: 18pt; }
            h2 { font-size: 14.5pt; }
            h3 { font-size: 12pt; }
            h4, h5, h6 { font-size: 10.5pt; }
            p { margin: 8px 0; }
            ul { margin: 8px 0; padding-left: 20px; }
            li { margin: 4px 0; }
            li.todo { list-style: none; margin-left: -18px; }
            li.todo .box {
              display: inline-block;
              width: 13px;
              height: 13px;
              margin-right: 7px;
              border: 1.2px solid #7c5cff;
              border-radius: 3px;
              text-align: center;
              line-height: 11px;
              font-size: 9px;
              vertical-align: -1px;
              color: #ffffff;
            }
            li.todo.done .box { background: #7c5cff; }
            li.todo.done .todo-text { color: #7a738c; text-decoration: line-through; }
            blockquote {
              margin: 12px 0;
              padding: 10px 14px;
              border-left: 3px solid #8b6eff;
              background: #f6f4fc;
              border-radius: 0 8px 8px 0;
              color: #3d3650;
            }
            .callout {
              margin: 12px 0;
              padding: 12px 14px;
              border-radius: 8px;
              background: #f4f1fc;
              border: 1px solid #e3ddf5;
              break-inside: avoid;
            }
            .callout-kind {
              font-size: 8.5pt;
              font-weight: 700;
              letter-spacing: 0.06em;
              color: #6b4ce6;
              margin-bottom: 4px;
            }
            .callout-title { font-weight: 700; margin-bottom: 4px; }
            .code-block {
              margin: 12px 0;
              border-radius: 8px;
              border: 1px solid #e4e0ef;
              overflow: hidden;
              background: #faf9fd;
              break-inside: avoid;
            }
            .code-lang {
              padding: 4px 12px;
              font-size: 8pt;
              font-weight: 600;
              color: #6c657e;
              background: #f1eef9;
              border-bottom: 1px solid #e4e0ef;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            pre {
              margin: 0;
              padding: 10px 12px;
              overflow-x: auto;
              white-space: pre-wrap;
              word-break: break-word;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 9pt;
              line-height: 1.5;
            }
            code.inline-code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.9em;
              padding: 1px 5px;
              border-radius: 4px;
              background: #f1eef9;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 12px 0;
              font-size: 9.5pt;
              break-inside: avoid;
            }
            th, td {
              border: 1px solid #ded8ec;
              padding: 7px 10px;
              text-align: left;
              vertical-align: top;
            }
            th { background: #f3effc; font-weight: 600; }
            .math-block {
              margin: 14px 0;
              padding: 12px 14px;
              border-radius: 8px;
              background: #f8f6fd;
              text-align: center;
              overflow-x: auto;
              break-inside: avoid;
            }
            .math-error {
              color: #c2410c;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 9pt;
            }
            .wiki-link, .tag {
              color: #6b4ce6;
              font-weight: 500;
            }
            mark { background: #ede7fe; padding: 0 3px; border-radius: 3px; }
            a { color: #5b3fd6; text-decoration: underline; }
            hr { border: none; border-top: 1px solid #e6e2f0; margin: 16px 0; }
            figure.note-img {
              margin: 12px 0;
              padding: 8px;
              background: #faf9fd;
              border: 1px solid #e7e3f1;
              border-radius: 8px;
              break-inside: avoid;
            }
            figure.note-img img {
              max-width: 100%;
              max-height: 460px;
              border-radius: 6px;
              display: block;
            }
            figure.note-img figcaption {
              margin-top: 6px;
              font-size: 8.5pt;
              color: #6b647d;
            }
            mjx-container > svg { overflow: visible; }
          </style>
        </head>
        <body>
          <main class="doc">
            <header class="doc-header">
              <h1>\(title)</h1>
              <div class="doc-meta">\(metaItems.map { "<span>\($0)</span>" }.joined())</div>
            </header>
            \(bodyHtml)
          </main>
          <script>
            (function () {
              const KATEX_MACROS = {
                '\\bm': '\\boldsymbol{#1}',
                '\\R': '\\mathbb{R}',
                '\\N': '\\mathbb{N}',
                '\\Z': '\\mathbb{Z}',
                '\\Q': '\\mathbb{Q}',
                '\\C': '\\mathbb{C}',
                '\\E': '\\mathbb{E}',
                '\\P': '\\mathbb{P}',
                '\\argmax': '\\operatorname*{arg\\,max}',
                '\\argmin': '\\operatorname*{arg\\,min}',
                '\\defeq': '\\stackrel{\\mathrm{def}}{=}',
                '\\eqdef': '\\stackrel{\\mathrm{def}}{=}',
                '\\coloneqq': '\\mathrel{:=}',
                '\\eqqcolon': '\\mathrel{=:}',
                '\\llbracket': '[\\![',
                '\\rrbracket': ']\\!]'
              };

              async function renderAllMath() {
                const nodes = document.querySelectorAll('[data-tex]');
                for (let i = 0; i < nodes.length; i++) {
                  const el = nodes[i];
                  const raw = el.getAttribute('data-tex') || '';
                  const display = el.getAttribute('data-display') === '1';
                  const prepared = typeof window.preprocessLatex === 'function'
                    ? window.preprocessLatex(raw, display)
                    : raw;
                  let ok = false;
                  if (window.katex && typeof window.katex.render === 'function') {
                    try {
                      el.innerHTML = '';
                      window.katex.render(prepared, el, {
                        displayMode: display,
                        throwOnError: true,
                        strict: false,
                        trust: false,
                        macros: KATEX_MACROS
                      });
                      ok = true;
                    } catch (_) {
                      ok = false;
                    }
                  }
                  if (!ok && window.MathJax && typeof window.renderFormulaSvg === 'function') {
                    try {
                      if (window.MathJax.startup && window.MathJax.startup.promise) {
                        await window.MathJax.startup.promise;
                      }
                      const mj = window.renderFormulaSvg(raw, display);
                      if (!mj.querySelector('[data-mjx-error]')) {
                        const svg = mj.querySelector('svg');
                        if (svg && typeof window.LEXI_SVG_STYLES === 'string') {
                          const s = document.createElementNS('http://www.w3.org/2000/svg', 'style');
                          s.textContent = window.LEXI_SVG_STYLES;
                          svg.insertBefore(s, svg.firstChild);
                        }
                        el.innerHTML = '';
                        el.appendChild(mj);
                        ok = true;
                      }
                    } catch (_) {}
                  }
                }
              }

              window.lexiWaitForPdfReady = async function () {
                await renderAllMath();
                if (document.fonts && document.fonts.ready) {
                  await Promise.race([
                    document.fonts.ready,
                    new Promise(function (resolve) { setTimeout(resolve, 1200); })
                  ]);
                }
                const imgs = Array.from(document.querySelectorAll('img'));
                await Promise.all(imgs.map(function (img) {
                  if (img.complete) return Promise.resolve();
                  return new Promise(function (resolve) {
                    img.addEventListener('load', resolve, { once: true });
                    img.addEventListener('error', resolve, { once: true });
                    setTimeout(resolve, 2500);
                  });
                }));
                void document.body.offsetHeight;
                await new Promise(function (resolve) {
                  var settled = false;
                  function finish() { if (!settled) { settled = true; resolve(); } }
                  setTimeout(finish, 40);
                  if (typeof requestAnimationFrame === 'function') {
                    requestAnimationFrame(function () { setTimeout(finish, 0); });
                  }
                });
                const avoidSelectors = '.math-block, .code-block, .callout, table, figure.note-img, blockquote, h1, h2, h3, li, p';
                const docRect = document.documentElement.getBoundingClientRect();
                const avoidRects = Array.from(document.querySelectorAll(avoidSelectors)).map(function (node) {
                  const r = node.getBoundingClientRect();
                  return { top: r.top - docRect.top, bottom: r.bottom - docRect.top };
                }).filter(function (r) { return r.bottom > r.top; });
                return JSON.stringify({
                  mathCount: document.querySelectorAll('.katex, mjx-container').length,
                  avoidRects: avoidRects
                });
              };
            })();
          </script>
        </body>
        </html>
        """
    }

    private func renderBlock(_ block: MDBlock, vaultURL: URL?, noteRelativePath: String) -> String {
        switch block.kind {
        case .heading(let level, let content, _):
            let clamped = min(max(level, 1), 6)
            return "<h\(clamped)>\(renderInlines(content))</h\(clamped)>"
        case .paragraph(let content):
            return "<p>\(renderInlines(content))</p>"
        case .list(let items):
            let rows = items.map { item -> String in
                let indent = item.depth > 0 ? " style=\"margin-left: \(item.depth * 18)px\"" : ""
                switch item.marker {
                case .bullet:
                    return "<li\(indent)>\(renderInlines(item.content))</li>"
                case .ordered(let number):
                    return "<li\(indent) style=\"list-style:none;\"><strong>\(escapeHtml(number)).</strong> \(renderInlines(item.content))</li>"
                case .todo(let checked, _):
                    let mark = checked ? "✓" : ""
                    let doneCls = checked ? " done" : ""
                    return "<li class=\"todo\(doneCls)\"\(indent)><span class=\"box\">\(mark)</span><span class=\"todo-text\">\(renderInlines(item.content))</span></li>"
                }
            }
            return "<ul>\(rows.joined())</ul>"
        case .quote(let inner, let callout):
            let innerHtml = inner.map { renderBlock($0, vaultURL: vaultURL, noteRelativePath: noteRelativePath) }.joined(separator: "\n")
            if let callout {
                let kindLabel = escapeHtml(callout.kind.rawValue.uppercased())
                let titleHtml = (!callout.title.isEmpty && callout.title != callout.kind.label)
                    ? "<div class=\"callout-title\">\(escapeHtml(callout.title))</div>"
                    : ""
                return "<div class=\"callout\"><div class=\"callout-kind\">✦ \(kindLabel)</div>\(titleHtml)\(innerHtml)</div>"
            }
            return "<blockquote>\(innerHtml)</blockquote>"
        case .code(let language, let code):
            let label = language.isEmpty ? "TEXT" : language.uppercased()
            return "<div class=\"code-block\"><div class=\"code-lang\">\(escapeHtml(label))</div><pre><code>\(escapeHtml(code))</code></pre></div>"
        case .table(let headers, let rows):
            let headHtml = "<thead><tr>" + headers.map { "<th>\(escapeHtml($0))</th>" }.joined() + "</tr></thead>"
            let bodyHtml = "<tbody>" + rows.map { row in
                let cells = (0..<max(headers.count, row.count)).map { col in
                    "<td>\(escapeHtml(col < row.count ? row[col] : ""))</td>"
                }
                return "<tr>\(cells.joined())</tr>"
            }.joined() + "</tbody>"
            return "<table>\(headHtml)\(bodyHtml)</table>"
        case .math(let formula):
            let fallback = escapeHtml(LatexRenderer.unicode(formula))
            return "<div class=\"math-block\"><div data-tex=\"\(escapeHtmlAttribute(formula))\" data-display=\"1\">\(fallback)</div></div>"
        case .image(let alt, let source):
            guard let imgSrc = resolveImageSource(source, vaultURL: vaultURL, noteRelativePath: noteRelativePath) else {
                return "<p>[图片：\(escapeHtml(alt.isEmpty ? source : alt))]</p>"
            }
            let caption = alt.isEmpty ? "" : "<figcaption>\(escapeHtml(alt))</figcaption>"
            return "<figure class=\"note-img\"><img src=\"\(escapeHtmlAttribute(imgSrc))\" alt=\"\(escapeHtmlAttribute(alt))\">\(caption)</figure>"
        case .divider:
            return "<hr>"
        }
    }

    private func renderInlines(_ inlines: [MDInline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let value):
                return escapeHtml(value)
            case .bold(let inner):
                return "<strong>\(renderInlines(inner))</strong>"
            case .italic(let inner):
                return "<em>\(renderInlines(inner))</em>"
            case .strike(let inner):
                return "<del>\(renderInlines(inner))</del>"
            case .highlight(let inner):
                return "<mark>\(renderInlines(inner))</mark>"
            case .code(let value):
                return "<code class=\"inline-code\">\(escapeHtml(value))</code>"
            case .link(let label, let url):
                if let parsed = URL(string: url),
                   let scheme = parsed.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    return "<a href=\"\(escapeHtmlAttribute(url))\">\(renderInlines(label))</a>"
                }
                return "<span class=\"wiki-link\">\(renderInlines(label))</span>"
            case .wiki(_, _, let label):
                return "<span class=\"wiki-link\">[[\(escapeHtml(label))]]</span>"
            case .math(let formula):
                let fallback = escapeHtml(LatexRenderer.unicode(formula))
                return "<span data-tex=\"\(escapeHtmlAttribute(formula))\" data-display=\"0\">\(fallback)</span>"
            case .tag(let tag):
                return "<span class=\"tag\">#\(escapeHtml(tag))</span>"
            case .lineBreak:
                return "<br>"
            }
        }.joined()
    }

    private func resolveImageSource(_ source: String, vaultURL: URL?, noteRelativePath: String) -> String? {
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "data" {
            return source
        }
        guard let vaultURL else { return nil }
        let root = vaultURL.standardizedFileURL
        let clean = source.removingPercentEncoding ?? source
        var candidates: [URL] = []
        if !noteRelativePath.isEmpty {
            let noteDir = vaultURL.appendingPathComponent(noteRelativePath).deletingLastPathComponent()
            candidates.append(noteDir.appendingPathComponent(clean).standardizedFileURL)
        }
        candidates.append(vaultURL.appendingPathComponent(clean).standardizedFileURL)
        candidates.append(
            vaultURL.appendingPathComponent(clean.replacingOccurrences(of: "^(\\.\\./)+", with: "", options: .regularExpression)).standardizedFileURL
        )
        for candidate in candidates {
            guard candidate.path.hasPrefix(root.path + "/"),
                  let data = try? Data(contentsOf: candidate) else { continue }
            let mime: String
            switch candidate.pathExtension.lowercased() {
            case "png": mime = "image/png"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "webp": mime = "image/webp"
            case "svg": mime = "image/svg+xml"
            default: mime = "application/octet-stream"
            }
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }
        return nil
    }

    private func escapeHtml(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeHtmlAttribute(_ string: String) -> String {
        escapeHtml(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
