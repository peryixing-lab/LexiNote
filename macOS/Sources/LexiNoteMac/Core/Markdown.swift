import Foundation
import SwiftUI

// MARK: - Markdown AST

indirect enum MDInline: Hashable {
    case text(String)
    case bold([MDInline])
    case italic([MDInline])
    case strike([MDInline])
    case highlight([MDInline])
    case code(String)
    case link(label: [MDInline], url: String)
    case wiki(target: String, anchor: String?, label: String)
    case math(String)
    case tag(String)
    case lineBreak
}

struct MDListItem: Identifiable, Hashable {
    enum Marker: Hashable {
        case bullet
        case ordered(String)
        case todo(checked: Bool, line: Int)
    }
    let id: String
    let depth: Int
    let marker: Marker
    let content: [MDInline]
}

struct Callout: Hashable {
    enum Kind: String, Hashable {
        case note, tip, warning, important, caution, question, quote, example
        var label: String {
            switch self {
            case .note: return "笔记"
            case .tip: return "提示"
            case .warning: return "注意"
            case .important: return "重要"
            case .caution: return "警告"
            case .question: return "问题"
            case .quote: return "引用"
            case .example: return "示例"
            }
        }
        var symbol: String {
            switch self {
            case .note: return "note.text"
            case .tip: return "lightbulb"
            case .warning: return "exclamationmark.triangle"
            case .important: return "exclamationmark.circle"
            case .caution: return "exclamationmark.octagon"
            case .question: return "questionmark.circle"
            case .quote: return "quote.opening"
            case .example: return "text.book.closed"
            }
        }
    }
    let kind: Kind
    let title: String
}

struct MDBlock: Identifiable, Hashable {
    enum Kind: Hashable {
        case heading(level: Int, content: [MDInline], line: Int)
        case paragraph([MDInline])
        case list([MDListItem])
        case quote([MDBlock], Callout?)
        case code(language: String, code: String)
        case table(headers: [String], rows: [[String]])
        case math(String)
        case image(alt: String, source: String)
        case divider
    }
    let id: String
    let kind: Kind
    var line: Int = 0
}

// MARK: - Parser

enum MarkdownParser {
    static func parse(_ source: String) -> [MDBlock] {
        var parser = BlockParser(source: stripFrontmatter(source))
        return parser.parse()
    }

    static func stripFrontmatter(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return source }
        if let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return lines.dropFirst(end + 1).joined(separator: "\n")
        }
        return source
    }

    static func outline(_ source: String) -> [OutlineHeading] {
        var headings: [OutlineHeading] = []
        let lines = stripFrontmatter(source).components(separatedBy: "\n")
        var inFence = false
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if let match = headingMatch(line) {
                headings.append(OutlineHeading(id: "h-\(index)-\(match.level)",
                                               level: match.level,
                                               title: inlinePlain(parseInline(match.text)).trimmingCharacters(in: .whitespaces),
                                               line: index))
            }
        }
        return headings
    }

    static func wikiLinks(_ source: String) -> [WikiLink] {
        let content = stripFrontmatter(source)
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]+)(?:#([^\\]|]+))?(?:\\|([^\\]]+))?\\]\\]") else { return [] }
        let ns = content as NSString
        var results: [WikiLink] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: content, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let anchor = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces) : nil
            let label = match.range(at: 3).location != NSNotFound ? ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces) : target
            let key = "\(target)#\(anchor ?? "")"
            if seen.contains(key) { return }
            seen.insert(key)
            results.append(WikiLink(target: target, anchor: anchor, label: label))
        }
        return results
    }

    static func plainText(_ source: String) -> String {
        parse(source).map { plain(block: $0) }.joined(separator: "\n\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func inlinePlain(_ inlines: [MDInline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let value): return value
            case .bold(let children), .italic(let children), .strike(let children), .highlight(let children):
                return inlinePlain(children)
            case .code(let value): return value
            case .link(let label, _): return inlinePlain(label)
            case .wiki(_, _, let label): return label
            case .math(let value): return value
            case .tag(let value): return "#\(value)"
            case .lineBreak: return " "
            }
        }.joined()
    }

    static func parseInline(_ source: String) -> [MDInline] {
        InlineParser.parse(source)
    }

    static func firstImage(_ source: String) -> String? {
        for block in parse(source) {
            if case .image(_, let source) = block.kind { return source }
        }
        return nil
    }

    private static func plain(block: MDBlock) -> String {
        switch block.kind {
        case .heading(_, let content, _), .paragraph(let content):
            return inlinePlain(content)
        case .list(let items):
            return items.map { inlinePlain($0.content) }.joined(separator: "\n")
        case .quote(let blocks, _):
            return blocks.map { plain(block: $0) }.joined(separator: "\n")
        case .code(_, let code): return code
        case .table(let headers, let rows):
            return ([headers.joined(separator: " ")] + rows.map { $0.joined(separator: " ") }).joined(separator: "\n")
        case .math(let value): return value
        case .image(let alt, _): return alt
        case .divider: return ""
        }
    }

    static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return (level, rest.dropFirst().trimmingCharacters(in: .whitespaces))
    }
}

private struct BlockParser {
    let lines: [String]
    var index: Int = 0
    var counter: Int = 0
    var blockStart: Int = 0

    init(source: String) {
        self.lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    mutating func parse() -> [MDBlock] {
        var blocks: [MDBlock] = []
        while index < lines.count {
            blockStart = index
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                blocks.append(parseFence(open: line))
                continue
            }
            if line == "$$" || (line.hasPrefix("$$") && line.hasSuffix("$$") && line.count > 4) {
                blocks.append(parseMath(line: line))
                continue
            }
            if let heading = MarkdownParser.headingMatch(line) {
                let headingLine = index
                index += 1
                blocks.append(make(.heading(level: heading.level, content: MarkdownParser.parseInline(heading.text), line: headingLine)))
                continue
            }
            if isDivider(line) {
                index += 1
                blocks.append(make(.divider))
                continue
            }
            if line.hasPrefix(">") {
                blocks.append(parseQuote())
                continue
            }
            if line.hasPrefix("|") && index + 1 < lines.count && isTableDivider(lines[index + 1]) {
                blocks.append(parseTable())
                continue
            }
            if isListLine(raw) {
                blocks.append(parseList())
                continue
            }
            if let image = imageMatch(line) {
                index += 1
                blocks.append(make(.image(alt: image.alt, source: image.source)))
                continue
            }
            blocks.append(parseParagraph())
        }
        return blocks
    }

    private mutating func make(_ kind: MDBlock.Kind) -> MDBlock {
        counter += 1
        return MDBlock(id: "b-\(index)-\(counter)", kind: kind, line: blockStart)
    }

    private func isDivider(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" } || stripped.allSatisfy { $0 == "_" }
    }

    private func isListLine(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, ["-", "*", "+"].contains(first) {
            return trimmed.dropFirst().hasPrefix(" ")
        }
        if let dot = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[..<dot]
            return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && trimmed[trimmed.index(after: dot)...].hasPrefix(" ")
        }
        return false
    }

    private func isTableDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let stripped = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    private func imageMatch(_ line: String) -> (alt: String, source: String)? {
        guard line.hasPrefix("!["), let close = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let source = String(line[close.upperBound..<line.index(before: line.endIndex)])
        return (alt, source)
    }

    private mutating func parseFence(open: String) -> MDBlock {
        let marker = open.hasPrefix("```") ? "```" : "~~~"
        let language = String(open.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        index += 1
        var code: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                index += 1
                break
            }
            code.append(line)
            index += 1
        }
        return make(.code(language: language, code: code.joined(separator: "\n")))
    }

    private mutating func parseMath(line: String) -> MDBlock {
        if line.hasPrefix("$$") && line.hasSuffix("$$") && line.count > 4 {
            index += 1
            return make(.math(String(line.dropFirst(2).dropLast(2))))
        }
        index += 1
        var formula: [String] = []
        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            if current == "$$" {
                index += 1
                break
            }
            formula.append(lines[index])
            index += 1
        }
        return make(.math(formula.joined(separator: "\n")))
    }

    private mutating func parseParagraph() -> MDBlock {
        var parts: [String] = []
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") || trimmed.hasPrefix("$$") { break }
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("|") || isDivider(trimmed) { break }
            if MarkdownParser.headingMatch(trimmed) != nil || isListLine(raw) { break }
            parts.append(trimmed)
            index += 1
        }
        if parts.isEmpty { index += 1 }
        var inlines: [MDInline] = []
        for (offset, part) in parts.enumerated() {
            if offset > 0 { inlines.append(.lineBreak) }
            inlines.append(contentsOf: MarkdownParser.parseInline(part))
        }
        return make(.paragraph(inlines))
    }

    private mutating func parseList() -> MDBlock {
        var items: [MDListItem] = []
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard isListLine(raw) else { break }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
            var marker: MDListItem.Marker = .bullet
            var text = trimmed
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let checked = !trimmed.hasPrefix("- [ ] ")
                text = String(trimmed.dropFirst(6))
                marker = .todo(checked: checked, line: index)
            } else if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber) {
                let number = String(trimmed[..<dot])
                text = String(trimmed[trimmed.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                marker = .ordered(number)
            } else {
                text = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            }
            items.append(MDListItem(id: "li-\(index)-\(items.count)",
                                    depth: min(4, indent / 2),
                                    marker: marker,
                                    content: MarkdownParser.parseInline(text)))
            index += 1
            // Consume indented continuations as part of the item.
            while index < lines.count {
                let next = lines[index]
                if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if isListLine(next) { break }
                let nextIndent = next.prefix { $0 == " " || $0 == "\t" }.count
                if nextIndent > indent {
                    if let last = items.popLast() {
                        let extra = next.trimmingCharacters(in: .whitespaces)
                        items.append(MDListItem(id: last.id, depth: last.depth, marker: last.marker,
                                                content: last.content + [.lineBreak] + MarkdownParser.parseInline(extra)))
                    }
                    index += 1
                } else {
                    break
                }
            }
        }
        return make(.list(items))
    }

    private mutating func parseQuote() -> MDBlock {
        var quoteLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var body = line.trimmingCharacters(in: .whitespaces)
                body.removeFirst()
                if body.hasPrefix(" ") { body.removeFirst() }
                quoteLines.append(body)
                index += 1
            } else if quoteLines.isEmpty {
                break
            } else {
                break
            }
        }
        var callout: Callout?
        if let first = quoteLines.first {
            let pattern = "^\\[!(\\w+)\\]\\s*(.*)$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = first as NSString
                if let match = regex.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)) {
                    let rawKind = ns.substring(with: match.range(at: 1)).lowercased()
                    let title = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    let kind = Callout.Kind(rawValue: rawKind) ?? .note
                    callout = Callout(kind: kind, title: title.isEmpty ? kind.label : title)
                    quoteLines.removeFirst()
                }
            }
        }
        var inner = BlockParser(source: quoteLines.joined(separator: "\n"))
        let blocks = inner.parse()
        return make(.quote(blocks, callout))
    }

    private mutating func parseTable() -> MDBlock {
        func cells(_ line: String) -> [String] {
            var value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("|") { value.removeFirst() }
            if value.hasSuffix("|") { value.removeLast() }
            return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let headers = cells(lines[index])
        index += 2
        var rows: [[String]] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }
            rows.append(cells(line))
            index += 1
        }
        return make(.table(headers: headers, rows: rows))
    }
}

private struct InlineParser {
    let characters: [Character]
    var index: Int = 0
    var buffer: String = ""
    var output: [MDInline] = []

    init(source: String) {
        self.characters = Array(source)
    }

    static func parse(_ source: String) -> [MDInline] {
        var parser = InlineParser(source: source)
        return parser.parse()
    }

    mutating func parse() -> [MDInline] {
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, isEscapable(characters[index + 1]) {
                buffer.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "`" {
                if consumeCode() { continue }
            }
            if character == "[", peek(1) == "[" {
                if consumeWiki() { continue }
            }
            if character == "[", peek(1) != "[" && peek(1) != "(" {
                if consumeLink() { continue }
            }
            if character == "!" , peek(1) == "[" {
                if consumeImage() { continue }
            }
            if character == "$" {
                if consumeMath() { continue }
            }
            if character == "*" || character == "_" {
                if consumeEmphasis(character: character) { continue }
            }
            if character == "~", peek(1) == "~" {
                if consumeDelimited(open: "~~", close: "~~", wrap: { .strike($0) }) { continue }
            }
            if character == "=", peek(1) == "=" {
                if consumeDelimited(open: "==", close: "==", wrap: { .highlight($0) }) { continue }
            }
            if character == "#" {
                if consumeTag() { continue }
            }
            buffer.append(character)
            index += 1
        }
        flush()
        return output
    }

    private func peek(_ offset: Int) -> Character? {
        let target = index + offset
        return target < characters.count ? characters[target] : nil
    }

    private func isEscapable(_ character: Character) -> Bool {
        "\\`*_{}[]()#+-.!|~=$<>".contains(character)
    }

    private mutating func flush() {
        if !buffer.isEmpty {
            output.append(.text(buffer))
            buffer = ""
        }
    }

    private mutating func find(_ needle: String, from start: Int) -> Int? {
        let needleChars = Array(needle)
        guard !needleChars.isEmpty, start + needleChars.count <= characters.count else { return nil }
        var cursor = start
        while cursor <= characters.count - needleChars.count {
            if Array(characters[cursor..<(cursor + needleChars.count)]) == needleChars { return cursor }
            cursor += 1
        }
        return nil
    }

    private mutating func consumeCode() -> Bool {
        var run = 0
        while index + run < characters.count && characters[index + run] == "`" { run += 1 }
        let fence = String(repeating: "`", count: run)
        guard let end = find(fence, from: index + run) else { return false }
        let content = String(characters[(index + run)..<end])
        flush()
        output.append(.code(content.trimmingCharacters(in: CharacterSet(charactersIn: " "))))
        index = end + run
        return true
    }

    private mutating func consumeWiki() -> Bool {
        guard let end = find("]]", from: index + 2) else { return false }
        let inner = String(characters[(index + 2)..<end])
        let parts = inner.components(separatedBy: "|")
        var targetPart = parts.first ?? inner
        let label = parts.count > 1 ? parts[1] : ""
        var anchor: String?
        if let hash = targetPart.firstIndex(of: "#") {
            anchor = String(targetPart[targetPart.index(after: hash)...])
            targetPart = String(targetPart[..<hash])
        }
        flush()
        output.append(.wiki(target: targetPart.trimmingCharacters(in: .whitespaces),
                            anchor: anchor,
                            label: (label.isEmpty ? targetPart : label).trimmingCharacters(in: .whitespaces)))
        index = end + 2
        return true
    }

    private mutating func consumeLink() -> Bool {
        guard let close = find("]", from: index + 1), close + 1 < characters.count, characters[close + 1] == "(" else { return false }
        guard let end = find(")", from: close + 2) else { return false }
        let label = String(characters[(index + 1)..<close])
        let url = String(characters[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)
        flush()
        output.append(.link(label: InlineParser.parse(label), url: url))
        index = end + 1
        return true
    }

    private mutating func consumeImage() -> Bool {
        guard let close = find("](", from: index + 2), let end = find(")", from: close + 2) else { return false }
        let alt = String(characters[(index + 2)..<close])
        let source = String(characters[(close + 2)..<end])
        flush()
        output.append(.link(label: [.text(alt.isEmpty ? "图片" : alt)], url: source))
        index = end + 1
        return true
    }

    private mutating func consumeMath() -> Bool {
        if index + 1 < characters.count, characters[index + 1] == "$" { return false }
        guard let end = find("$", from: index + 1) else { return false }
        let content = String(characters[(index + 1)..<end])
        guard !content.isEmpty, !content.contains("\n") else { return false }
        flush()
        output.append(.math(content))
        index = end + 1
        return true
    }

    private mutating func consumeEmphasis(character: Character) -> Bool {
        let double = String(repeating: String(character), count: 2)
        if peek(1) == character, let end = find(double, from: index + 2) {
            let inner = String(characters[(index + 2)..<end])
            guard !inner.isEmpty else { return false }
            flush()
            output.append(.bold(InlineParser.parse(inner)))
            index = end + 2
            return true
        }
        guard let end = find(String(character), from: index + 1) else { return false }
        let inner = String(characters[(index + 1)..<end])
        guard !inner.isEmpty, !inner.hasPrefix(" ") else { return false }
        flush()
        output.append(.italic(InlineParser.parse(inner)))
        index = end + 1
        return true
    }

    private mutating func consumeDelimited(open: String, close: String,
                                           wrap: ([MDInline]) -> MDInline) -> Bool {
        guard let end = find(close, from: index + open.count) else { return false }
        let inner = String(characters[(index + open.count)..<end])
        guard !inner.isEmpty else { return false }
        flush()
        output.append(wrap(InlineParser.parse(inner)))
        index = end + close.count
        return true
    }

    private mutating func consumeTag() -> Bool {
        let previous: Character? = index > 0 ? characters[index - 1] : nil
        if let previous, !previous.isWhitespace && !"([{\"'，。；：".contains(previous) { return false }
        var cursor = index + 1
        var tag = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character.isLetter || character.isNumber || character == "/" || character == "-" || character == "_" {
                tag.append(character)
                cursor += 1
            } else if character == " " && cursor + 1 < characters.count && cursor - index > 1 {
                break
            } else {
                break
            }
        }
        guard tag.count >= 2 else { return false }
        flush()
        output.append(.tag(tag))
        index = cursor
        return true
    }
}

// MARK: - LaTeX → readable Unicode

enum LatexRenderer {
    private static let commands: [(String, String)] = [
        ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"), ("\\epsilon", "ε"),
        ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"), ("\\theta", "θ"), ("\\lambda", "λ"),
        ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"), ("\\pi", "π"), ("\\rho", "ρ"), ("\\sigma", "σ"),
        ("\\tau", "τ"), ("\\phi", "φ"), ("\\varphi", "φ"), ("\\chi", "χ"), ("\\psi", "ψ"), ("\\omega", "ω"),
        ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"), ("\\Xi", "Ξ"), ("\\Pi", "Π"),
        ("\\Sigma", "Σ"), ("\\Phi", "Φ"), ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
        ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"), ("\\iint", "∬"), ("\\oint", "∮"),
        ("\\infty", "∞"), ("\\partial", "∂"), ("\\nabla", "∇"), ("\\forall", "∀"), ("\\exists", "∃"),
        ("\\in", "∈"), ("\\notin", "∉"), ("\\subset", "⊂"), ("\\subseteq", "⊆"), ("\\cup", "∪"), ("\\cap", "∩"),
        ("\\emptyset", "∅"), ("\\varnothing", "∅"), ("\\to", "→"), ("\\rightarrow", "→"), ("\\leftarrow", "←"),
        ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"), ("\\mapsto", "↦"),
        ("\\le", "≤"), ("\\leq", "≤"), ("\\ge", "≥"), ("\\geq", "≥"), ("\\ne", "≠"), ("\\neq", "≠"),
        ("\\approx", "≈"), ("\\equiv", "≡"), ("\\sim", "∼"), ("\\propto", "∝"), ("\\pm", "±"), ("\\mp", "∓"),
        ("\\cdot", "·"), ("\\times", "×"), ("\\div", "÷"), ("\\ast", "∗"), ("\\star", "⋆"),
        ("\\cdots", "⋯"), ("\\ldots", "…"), ("\\dots", "…"), ("\\prime", "′"), ("\\degree", "°"),
        ("\\angle", "∠"), ("\\perp", "⊥"), ("\\parallel", "∥"), ("\\therefore", "∴"), ("\\because", "∵"),
        ("\\log", "log"), ("\\ln", "ln"), ("\\lg", "lg"), ("\\exp", "exp"),
        ("\\sin", "sin"), ("\\cos", "cos"), ("\\tan", "tan"), ("\\cot", "cot"), ("\\sec", "sec"), ("\\csc", "csc"),
        ("\\arcsin", "arcsin"), ("\\arccos", "arccos"), ("\\arctan", "arctan"),
        ("\\max", "max"), ("\\min", "min"), ("\\lim", "lim"), ("\\det", "det"), ("\\gcd", "gcd"),
        ("\\lfloor", "⌊"), ("\\rfloor", "⌋"), ("\\lceil", "⌈"), ("\\rceil", "⌉"),
        ("\\langle", "⟨"), ("\\rangle", "⟩"), ("\\{", "{"), ("\\}", "}"), ("\\%", "%"),
        ("\\quad", "  "), ("\\qquad", "    "), ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\ ", " "),
        ("\\left", ""), ("\\right", ""), ("\\displaystyle", ""), ("\\limits", ""), ("\\nolimits", ""),
        ("\\big", ""), ("\\Big", ""), ("\\bigl", ""), ("\\bigr", ""), ("\\textstyle", ""), ("\\mathrm", ""),
        ("\\mathbf", ""), ("\\mathit", ""), ("\\mathsf", ""), ("\\mathtt", ""), ("\\mathcal", "")
    ]

    static func unicode(_ latex: String) -> String {
        var text = latex
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = replaceCommandArguments(text)
        for (command, symbol) in commands.sorted(by: { $0.0.count > $1.0.count }) {
            text = text.replacingOccurrences(of: command, with: symbol)
        }
        text = replaceScripts(text)
        text = text.replacingOccurrences(of: "&", with: "   ")
        text = text.replacingOccurrences(of: "\\\\", with: "   ")
        text = text.replacingOccurrences(of: "\\begin{matrix}", with: "[")
        text = text.replacingOccurrences(of: "\\end{matrix}", with: "]")
        text = text.replacingOccurrences(of: "\\begin{pmatrix}", with: "(")
        text = text.replacingOccurrences(of: "\\end{pmatrix}", with: ")")
        text = text.replacingOccurrences(of: "\\begin{bmatrix}", with: "[")
        text = text.replacingOccurrences(of: "\\end{bmatrix}", with: "]")
        text = text.replacingOccurrences(of: "\\begin{cases}", with: "{ ")
        text = text.replacingOccurrences(of: "\\end{cases}", with: " }")
        text = text.replacingOccurrences(of: "\\begin{aligned}", with: "")
        text = text.replacingOccurrences(of: "\\end{aligned}", with: "")
        text = text.replacingOccurrences(of: "\\begin{align}", with: "")
        text = text.replacingOccurrences(of: "\\end{align}", with: "")
        text = text.replacingOccurrences(of: "{", with: "")
        text = text.replacingOccurrences(of: "}", with: "")
        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func replaceCommandArguments(_ source: String) -> String {
        var text = source
        // \text{...}, \mathrm{...} etc. keep their argument only.
        if let regex = try? NSRegularExpression(pattern: "\\\\(?:text|mathrm|mathbf|mathit|operatorname|textrm)\\s*\\{([^{}]*)\\}") {
            var guardCount = 0
            while guardCount < 20 {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let full = Range(match.range, in: text),
                      let inner = Range(match.range(at: 1), in: text) else { break }
                text.replaceSubrange(full, with: String(text[inner]))
                guardCount += 1
            }
        }
        // \frac{a}{b}, \dfrac, \tfrac
        if let regex = try? NSRegularExpression(pattern: "\\\\(?:frac|dfrac|tfrac|tfrac)\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}") {
            var guardCount = 0
            while guardCount < 20 {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let full = Range(match.range, in: text),
                      let numerator = Range(match.range(at: 1), in: text),
                      let denominator = Range(match.range(at: 2), in: text) else { break }
                let top = String(text[numerator])
                let bottom = String(text[denominator])
                let needsParens = top.rangeOfCharacter(from: CharacterSet(charactersIn: "+- ")) != nil
                let replacement = "\(needsParens ? "(\(top))" : top)⁄\(bottom)"
                text.replaceSubrange(full, with: replacement)
                guardCount += 1
            }
        }
        // Accents: \bar{x}, \overline{x}, \hat{x}, \tilde{x}, \vec{x}
        let accents: [(String, String)] = [
            ("\\overline", "\u{0305}"), ("\\bar", "\u{0304}"), ("\\hat", "\u{0302}"),
            ("\\tilde", "\u{0303}"), ("\\vec", "\u{20D7}"), ("\\dot", "\u{0307}"), ("\\ddot", "\u{0308}")
        ]
        for (command, mark) in accents {
            if let regex = try? NSRegularExpression(pattern: command + "\\s*\\{([^{}]*)\\}") {
                var guardCount = 0
                while guardCount < 20 {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    guard let match = regex.firstMatch(in: text, range: range),
                          let full = Range(match.range, in: text),
                          let inner = Range(match.range(at: 1), in: text) else { break }
                    let body = String(text[inner])
                    text.replaceSubrange(full, with: body + mark)
                    guardCount += 1
                }
            }
        }

        // \sqrt[n]{x}
        if let regex = try? NSRegularExpression(pattern: "\\\\sqrt\\s*(?:\\[([^\\]]*)\\])?\\s*\\{([^{}]*)\\}") {
            var guardCount = 0
            while guardCount < 20 {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let full = Range(match.range, in: text),
                      let body = Range(match.range(at: 2), in: text) else { break }
                let index = match.range(at: 1).location != NSNotFound ? Range(match.range(at: 1), in: text).map { String(text[$0]) } : nil
                let prefix = index.map { superscript($0) } ?? ""
                text.replaceSubrange(full, with: "\(prefix)√(\(String(text[body])))")
                guardCount += 1
            }
        }
        return text
    }

    private static func replaceScripts(_ source: String) -> String {
        var text = source
        if let regex = try? NSRegularExpression(pattern: "\\^\\s*(?:\\{([^{}]*)\\}|([A-Za-z0-9]))") {
            var guardCount = 0
            while guardCount < 50 {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let full = Range(match.range, in: text) else { break }
                let content: String
                if match.range(at: 1).location != NSNotFound, let r = Range(match.range(at: 1), in: text) {
                    content = String(text[r])
                } else if let r = Range(match.range(at: 2), in: text) {
                    content = String(text[r])
                } else { break }
                let converted = superscript(content)
                text.replaceSubrange(full, with: converted)
                guardCount += 1
            }
        }
        if let regex = try? NSRegularExpression(pattern: "_\\s*(?:\\{([^{}]*)\\}|([A-Za-z0-9]))") {
            var guardCount = 0
            while guardCount < 50 {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let full = Range(match.range, in: text) else { break }
                let content: String
                if match.range(at: 1).location != NSNotFound, let r = Range(match.range(at: 1), in: text) {
                    content = String(text[r])
                } else if let r = Range(match.range(at: 2), in: text) {
                    content = String(text[r])
                } else { break }
                text.replaceSubrange(full, with: subscriptText(content))
                guardCount += 1
            }
        }
        return text
    }

    private static func superscript(_ value: String) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                                           "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
                                           "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
                                           "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ",
                                           "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ",
                                           "l": "ˡ", "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ",
                                           "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ"]
        var result = ""
        for character in value {
            if let mapped = map[character] { result.append(mapped) } else { return "^(" + value + ")" }
        }
        return result
    }

    private static func subscriptText(_ value: String) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
                                           "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
                                           "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
                                           "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ",
                                           "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ",
                                           "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ"]
        var result = ""
        for character in value {
            if let mapped = map[character] { result.append(mapped) } else { return "_(" + value + ")" }
        }
        return result
    }
}
