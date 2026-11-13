import SwiftUI
import AppKit

// MARK: - Inline rendering

struct InlineStyle {
    var size: CGFloat
    var bold: Bool = false
    var italic: Bool = false
    var strike: Bool = false
    var highlight: Bool = false
    var muted: Bool = false
}

struct MarkdownInlineText: View {
    @Environment(\.lexiPalette) private var palette
    let inlines: [MDInline]
    let size: CGFloat
    var color: Color? = nil
    var bold: Bool = false
    var lineSpacing: CGFloat = 0
    var alignment: TextAlignment = .leading
    var struck: Bool = false

    var body: some View {
        let attributed = MarkdownInlineBuilder.build(inlines, size: size, palette: palette,
                                                    baseColor: color ?? palette.textPrimary, bold: bold, struck: struck)
        Text(attributed)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(alignment)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum MarkdownInlineBuilder {
    static func build(_ inlines: [MDInline], size: CGFloat, palette: ThemePalette,
                      baseColor: Color, bold: Bool = false, struck: Bool = false) -> AttributedString {
        var result = AttributedString()
        var style = InlineStyle(size: size, bold: bold, strike: struck)
        append(inlines, style: &style, palette: palette, baseColor: baseColor, into: &result)
        return result
    }

    private static func font(for style: InlineStyle, design: Font.Design = .default) -> Font {
        var font = Font.system(size: style.size, weight: style.bold ? .bold : .regular, design: design)
        if style.italic { font = font.italic() }
        return font
    }

    private static func append(_ inlines: [MDInline], style: inout InlineStyle, palette: ThemePalette,
                               baseColor: Color, into result: inout AttributedString) {
        for inline in inlines {
            switch inline {
            case .text(let value):
                var run = AttributedString(value)
                run.font = font(for: style)
                run.foregroundColor = style.muted ? palette.textSecondary : baseColor
                if style.strike { run.strikethroughStyle = .single }
                if style.highlight { run.backgroundColor = palette.brandSoft }
                result.append(run)
            case .bold(let children):
                var next = style
                next.bold = true
                append(children, style: &next, palette: palette, baseColor: baseColor, into: &result)
            case .italic(let children):
                var next = style
                next.italic = true
                append(children, style: &next, palette: palette, baseColor: baseColor, into: &result)
            case .strike(let children):
                var next = style
                next.strike = true
                append(children, style: &next, palette: palette, baseColor: baseColor, into: &result)
            case .highlight(let children):
                var next = style
                next.highlight = true
                append(children, style: &next, palette: palette, baseColor: baseColor, into: &result)
            case .code(let value):
                var run = AttributedString(value)
                run.font = .system(size: max(11, style.size - 1.5), design: .monospaced)
                run.foregroundColor = palette.textPrimary
                run.backgroundColor = palette.softSurface
                result.append(run)
            case .link(let label, let url):
                var inner = AttributedString()
                var next = style
                next.bold = style.bold
                append(label, style: &next, palette: palette, baseColor: palette.brandInk, into: &inner)
                if let parsed = URL(string: url) {
                    inner.link = parsed
                }
                inner.foregroundColor = palette.brandInk
                inner.underlineStyle = .single
                result.append(inner)
            case .wiki(let target, let anchor, let label):
                var inner = AttributedString()
                var next = style
                next.bold = style.bold
                append([.text(label)], style: &next, palette: palette, baseColor: palette.brandInk, into: &inner)
                var components = URLComponents()
                components.scheme = "lexi"
                components.host = "note"
                var items = [URLQueryItem(name: "target", value: target)]
                if let anchor { items.append(URLQueryItem(name: "anchor", value: anchor)) }
                components.queryItems = items
                if let url = components.url { inner.link = url }
                inner.foregroundColor = palette.brandInk
                result.append(inner)
            case .math(let value):
                let converted = LatexRenderer.unicode(value)
                var run = AttributedString(" \(converted) ")
                run.font = .system(size: style.size + 1, design: .serif).italic()
                run.foregroundColor = palette.textPrimary
                result.append(run)
            case .tag(let value):
                var run = AttributedString("#\(value)")
                run.font = .system(size: style.size - 0.5, weight: .medium)
                run.foregroundColor = palette.brandInk
                result.append(run)
            case .lineBreak:
                var run = AttributedString("\n")
                run.font = font(for: style)
                result.append(run)
            }
        }
    }
}

// MARK: - Code highlighting

enum CodeHighlighter {
    static func highlight(_ code: String, language: String, palette: ThemePalette, size: CGFloat = 12.5) -> AttributedString {
        let baseFont = Font.system(size: size, design: .monospaced)
        let ns = code as NSString
        let length = ns.length
        var marked = [Bool](repeating: false, count: length)
        var tokens: [(NSRange, Color)] = []

        func add(_ pattern: String, _ color: Color, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: code, range: NSRange(location: 0, length: length)) { match, _, _ in
                guard let match else { return }
                let range = match.range
                guard range.length > 0 else { return }
                let upper = min(NSMaxRange(range), length)
                guard range.location < upper else { return }
                for index in range.location..<upper where marked[index] { return }
                for index in range.location..<upper { marked[index] = true }
                tokens.append((range, color))
            }
        }

        let lang = language.lowercased()
        if ["swift", "ts", "typescript", "js", "javascript", "java", "kt", "c", "cpp", "go", "rust", "rs", "objc", "python", "py", "json", "yaml", "yml", "sh", "bash", "zsh", "sql", "html", "css"].contains(lang) {
            add("//[^\\n]*", palette.textSecondary.opacity(0.85))
            add("/\\*[\\s\\S]*?\\*/", palette.textSecondary.opacity(0.85))
            add("#[^\\n]*", palette.textSecondary.opacity(0.85))
            add("\"(?:[^\"\\\\]|\\\\.)*\"", palette.success)
            add("'(?:[^'\\\\]|\\\\.)*'", palette.success)
            add("`(?:[^`\\\\]|\\\\.)*`", palette.success)
            let keywords = "\\b(func|function|let|var|const|if|else|for|while|return|class|struct|enum|protocol|extension|import|from|export|default|switch|case|break|continue|guard|async|await|try|catch|throw|throws|public|private|internal|static|final|override|init|deinit|self|super|nil|None|NoneType|true|false|True|False|null|undefined|new|this|void|int|float|double|string|boolean|any|type|interface|package|module|where|in|of|as|is|not|and|or|lambda|def|elif|pass|with|yield|raise|except|finally|global|nonlocal|assert|del)\\b"
            add(keywords, palette.brand)
            add("\\b[0-9]+(?:\\.[0-9]+)?\\b", palette.warning)
        } else {
            add("\"[^\"\\n]*\"", palette.success)
            add("'[^'\\n]*'", palette.success)
            add("(?m)^\\s*#[^\\n]*", palette.textSecondary.opacity(0.85))
            add("\\\\[A-Za-z]+", palette.brand)
        }

        var result = AttributedString()
        var cursor = 0
        for token in tokens.sorted(by: { $0.0.location < $1.0.location }) {
            if token.0.location > cursor {
                var run = AttributedString(ns.substring(with: NSRange(location: cursor, length: token.0.location - cursor)))
                run.font = baseFont
                run.foregroundColor = palette.textPrimary
                result.append(run)
            }
            if token.0.location >= cursor {
                var run = AttributedString(ns.substring(with: token.0))
                run.font = baseFont
                run.foregroundColor = token.1
                result.append(run)
                cursor = NSMaxRange(token.0)
            }
        }
        if cursor < length {
            var run = AttributedString(ns.substring(from: cursor))
            run.font = baseFont
            run.foregroundColor = palette.textPrimary
            result.append(run)
        }
        if result.characters.isEmpty {
            var run = AttributedString(code)
            run.font = baseFont
            run.foregroundColor = palette.textPrimary
            result.append(run)
        }
        return result
    }
}

// MARK: - Preview

struct MarkdownPreview: View {
    @Environment(\.lexiPalette) private var palette
    let blocks: [MDBlock]
    let note: Note
    let fontSize: CGFloat
    let vaultURL: URL?
    var jumpTarget: String? = nil
    var showsEmptyHint: Bool = true
    var onOpenTarget: (String) -> Void = { _ in }
    var onToggleTodo: (Int) -> Void = { _ in }
    var onOpenExternal: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var liveEditing: Bool = false
    var onEditBlock: ((Int) -> Void)? = nil

    @State private var copiedBlock: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if blocks.isEmpty {
                        if showsEmptyHint {
                            emptyHint
                        }
                    } else {
                        ForEach(blocks) { block in
                            LiveBlockContainer(palette: palette,
                                               onEdit: liveEditing ? { onEditBlock?(block.line) } : nil) {
                                BlockView(block: block, note: note, fontSize: fontSize, vaultURL: vaultURL,
                                          copiedBlock: $copiedBlock,
                                          onOpenTarget: onOpenTarget, onToggleTodo: onToggleTodo)
                            }
                            .id(blockAnchor(block))
                        }
                    }
                    Color.clear.frame(height: 36)
                }
                .padding(.horizontal, 56)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: 800, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.automatic)
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "lexi" {
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    if let target = components?.queryItems?.first(where: { $0.name == "target" })?.value {
                        onOpenTarget(target)
                    }
                    return .handled
                }
                onOpenExternal(url)
                return .handled
            })
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("从一个想法开始。")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            Text("支持 Markdown、`#标签` 与 [[双向链接]]；用 $公式$ 或 $$块级公式$$ 记录推导。")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.softSurface.opacity(palette.isDark ? 0.55 : 0.7))
        )
    }

    private func blockAnchor(_ block: MDBlock) -> String {
        if case .heading(let level, _, let line) = block.kind {
            return "h-\(line)-\(level)"
        }
        return block.id
    }
}

private struct BlockView: View {
    @Environment(\.lexiPalette) private var palette
    let block: MDBlock
    let note: Note
    let fontSize: CGFloat
    let vaultURL: URL?
    @Binding var copiedBlock: String?
    let onOpenTarget: (String) -> Void
    let onToggleTodo: (Int) -> Void

    private var scale: CGFloat { fontSize / 16 }
    private var bodySize: CGFloat { fontSize }
    private var lineSpacing: CGFloat { fontSize * 0.48 }

    var body: some View {
        switch block.kind {
        case .heading(let level, let content, let line):
            let sizes: [CGFloat] = [30, 23, 18.5, 16, 15, 14]
            let size = sizes[min(max(level - 1, 0), sizes.count - 1)] * max(0.8, scale)
            MarkdownInlineText(inlines: content, size: size, bold: true, lineSpacing: 3)
                .padding(.top, level == 1 ? 12 : 8)
                .padding(.bottom, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("h-\(line)-\(level)")

        case .paragraph(let content):
            MarkdownInlineText(inlines: content, size: bodySize, lineSpacing: lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items) { item in
                    ListRow(item: item, fontSize: bodySize, onToggle: onToggleTodo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .quote(let inner, let callout):
            if let callout {
                CalloutView(callout: callout, blocks: inner, fontSize: bodySize)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(inner) { child in
                        if case .paragraph(let content) = child.kind {
                            MarkdownInlineText(inlines: content, size: max(13, bodySize - 2),
                                               color: palette.textSecondary, lineSpacing: 4.5)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.brandSoft.opacity(palette.isDark ? 0.28 : 0.62))
                )
            }

        case .code(let language, let code):
            CodeBlockView(language: language, code: code, copiedBlock: $copiedBlock, blockID: block.id)

        case .table(let headers, let rows):
            TableBlock(headers: headers, rows: rows, fontSize: max(11.5, bodySize - 3))

        case .math(let formula):
            MathBlock(formula: formula, blockID: block.id, copiedBlock: $copiedBlock)

        case .image(let alt, let source):
            ImageBlock(alt: alt, source: source, vaultURL: vaultURL)

        case .divider:
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
                .padding(.vertical, 8)
        }
    }
}

private struct ListRow: View {
    @Environment(\.lexiPalette) private var palette
    let item: MDListItem
    let fontSize: CGFloat
    let onToggle: (Int) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            marker
            MarkdownInlineText(inlines: item.content, size: fontSize,
                               color: completed ? palette.textSecondary : palette.textPrimary,
                               lineSpacing: fontSize * 0.4, struck: completed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.depth) * 20)
    }

    private var completed: Bool {
        if case .todo(let checked, _) = item.marker, checked { return true }
        return false
    }

    @ViewBuilder private var marker: some View {
        switch item.marker {
        case .bullet:
            Text("•")
                .font(.system(size: fontSize * 0.95, weight: .semibold))
                .foregroundStyle(palette.brand)
                .frame(width: 14, alignment: .center)
        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: fontSize * 0.92, weight: .medium))
                .foregroundStyle(palette.brand)
                .frame(minWidth: 18, alignment: .trailing)
        case .todo(let checked, let line):
            Button {
                onToggle(line)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(checked ? palette.brand : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(checked ? palette.brand : palette.textSecondary.opacity(0.55), lineWidth: 1.2)
                        )
                        .frame(width: 15, height: 15)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.inverseText)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 18)
        }
    }
}

private struct CalloutView: View {
    @Environment(\.lexiPalette) private var palette
    let callout: Callout
    let blocks: [MDBlock]
    let fontSize: CGFloat

    private var tint: Color {
        switch callout.kind {
        case .tip: return palette.success
        case .warning, .caution: return palette.warning
        case .important: return palette.brand
        case .question: return palette.brandInk
        case .quote: return palette.textSecondary
        default: return palette.brand
        }
    }

    private var label: String {
        switch callout.kind {
        case .note: return "NOTE"
        case .tip: return "TIP"
        case .warning: return "WARNING"
        case .important: return "IMPORTANT"
        case .caution: return "CAUTION"
        case .question: return "QUESTION"
        case .quote: return "QUOTE"
        case .example: return "EXAMPLE"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("✦")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.7)
            }
            .foregroundStyle(tint)

            if !callout.title.isEmpty && callout.title != callout.kind.label {
                Text(callout.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(blocks) { block in
                    switch block.kind {
                    case .paragraph(let content):
                        MarkdownInlineText(inlines: content, size: max(13, fontSize - 2),
                                           color: palette.textPrimary, lineSpacing: 4.5)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text("•").foregroundStyle(tint)
                                    MarkdownInlineText(inlines: item.content, size: max(13, fontSize - 2),
                                                       color: palette.textPrimary, lineSpacing: 3)
                                }
                            }
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(callout.kind == .note || callout.kind == .important
                      ? palette.brandSoft.opacity(palette.isDark ? 0.28 : 0.68)
                      : tint.opacity(palette.isDark ? 0.14 : 0.085))
        )
    }
}

private struct CodeBlockView: View {
    @Environment(\.lexiPalette) private var palette
    let language: String
    let code: String
    @Binding var copiedBlock: String?
    let blockID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "TEXT" : language.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedBlock = blockID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if copiedBlock == blockID { copiedBlock = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedBlock == blockID ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(copiedBlock == blockID ? "已复制" : "复制代码")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(palette.softSurface.opacity(palette.isDark ? 0.4 : 0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language, palette: palette))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.softSurface.opacity(palette.isDark ? 0.5 : 0.62))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TableBlock: View {
    @Environment(\.lexiPalette) private var palette
    let headers: [String]
    let rows: [[String]]
    let fontSize: CGFloat
    private let cellWidth: CGFloat = 156

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, row.count), id: \.self) { column in
                            cell(column < row.count ? row[column] : "",
                                 isHeader: false,
                                 alternate: index % 2 == 1)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func cell(_ text: String, isHeader: Bool, alternate: Bool = false) -> some View {
        Text(isHeader ? text : text)
            .font(.system(size: fontSize, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? palette.textPrimary : palette.textSecondary)
            .lineSpacing(3)
            .frame(width: cellWidth, alignment: .leading)
            .frame(minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHeader ? palette.brandSoft.opacity(palette.isDark ? 0.5 : 0.9)
                    : (alternate ? palette.softSurface.opacity(palette.isDark ? 0.2 : 0.28) : palette.surface)
            )
            .overlay(
                Rectangle().fill(palette.divider).frame(height: 0.6),
                alignment: .bottom
            )
    }
}

private struct MathBlock: View {
    @Environment(\.lexiPalette) private var palette
    let formula: String
    let blockID: String
    @Binding var copiedBlock: String?

    var body: some View {
        let converted = LatexRenderer.unicode(formula)
        VStack(spacing: 6) {
            Text(converted)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
            if copiedBlock == blockID {
                Text("LaTeX 已复制")
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.brandSoft.opacity(palette.isDark ? 0.26 : 0.52))
        )
        .help(formula)
        .contextMenu {
            Button("复制 LaTeX") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(formula, forType: .string)
                copiedBlock = blockID
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedBlock == blockID { copiedBlock = nil }
                }
            }
        }
    }
}

private struct ImageBlock: View {
    @Environment(\.lexiPalette) private var palette
    let alt: String
    let source: String
    let vaultURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageContent
            if !alt.isEmpty {
                Text(alt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.softSurface.opacity(palette.isDark ? 0.45 : 0.6))
        )
    }

    @ViewBuilder private var imageContent: some View {
        if let url = URL(string: source), let scheme = url.scheme, scheme.hasPrefix("http") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().frame(maxHeight: 420).clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    placeholder
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        } else if let vaultURL, let image = NSImage(contentsOf: vaultURL.appendingPathComponent(source)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 14))
            Text("图片暂时无法显示")
                .font(.system(size: 12))
            Text(source)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(0.7)
        }
        .foregroundStyle(palette.textSecondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct LiveBlockContainer<Content: View>: View {
    let palette: ThemePalette
    let onEdit: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                if let onEdit, hovering {
                    Button(action: onEdit) {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("编辑")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(palette.brandInk)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Capsule().fill(palette.workspacePage.opacity(0.94)))
                        .overlay(Capsule().stroke(palette.workspaceLine, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                    .help("编辑此段源码")
                    .padding(.top, -2)
                    .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
    }
}
