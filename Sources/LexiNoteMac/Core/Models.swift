import Foundation

// MARK: - Note model

enum NoteKind: String, Codable, CaseIterable, Identifiable {
    case markdown, study, quick
    var id: String { rawValue }
    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .study: return "学习笔记"
        case .quick: return "快速笔记"
        }
    }
    var symbol: String {
        switch self {
        case .markdown: return "doc.text"
        case .study: return "book.closed"
        case .quick: return "bolt"
        }
    }
}

enum EditorLevel: String, Codable, CaseIterable {
    case simple, study, pro
    var label: String {
        switch self {
        case .simple: return "简洁"
        case .study: return "学习"
        case .pro: return "专业"
        }
    }
}

struct NoteProperty: Codable, Hashable, Identifiable {
    var key: String
    var value: String
    var id: String { key }
}

struct Note: Identifiable, Codable, Hashable {
    var id: String
    var vaultID: String
    var notebook: String
    var type: NoteKind
    var level: EditorLevel
    var title: String
    var content: String
    var tags: [String]
    var properties: [NoteProperty]
    var pinned: Bool
    var favorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastAccessedAt: Date? = nil
    var trashedAt: Date?
    /// Path relative to the vault folder, e.g. "计算机课程/时间复杂度.md".
    var path: String

    init(id: String = "note-\(UUID().uuidString.lowercased())",
         vaultID: String,
         notebook: String = "笔记",
         type: NoteKind = .markdown,
         level: EditorLevel = .study,
         title: String = "",
         content: String = "",
         tags: [String] = [],
         properties: [NoteProperty] = [],
         pinned: Bool = false,
         favorite: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastAccessedAt: Date? = nil,
         trashedAt: Date? = nil,
         path: String = "") {
        self.id = id
        self.vaultID = vaultID
        self.notebook = notebook
        self.type = type
        self.level = level
        self.title = title
        self.content = content
        self.tags = tags
        self.properties = properties
        self.pinned = pinned
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
        self.trashedAt = trashedAt
        self.path = path
    }

    var displayTitle: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "无标题笔记"
    }

    var characterCount: Int { content.count }

    var outline: [OutlineHeading] {
        var headings = MarkdownParser.outline(content)
        if headings.first?.level == 1 { headings.removeFirst() }
        return headings
    }

    var wikiLinks: [WikiLink] { MarkdownParser.wikiLinks(content) }

    var plainText: String { MarkdownParser.plainText(content) }

    var snippet: String {
        let text = plainText.replacingOccurrences(of: "\n", with: " ")
        return String(text.prefix(110))
    }

    func snippet(matching query: String, maxLength: Int = 110) -> String {
        let normalized = plainText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        let terms = NoteSearch.highlightTerms(query)
        guard !terms.isEmpty else {
            return normalized.count > maxLength ? String(normalized.prefix(maxLength)) + "..." : normalized
        }
        var earliestMatch: String.Index?
        for term in terms {
            if let range = normalized.range(of: term, options: [.caseInsensitive]),
               earliestMatch == nil || range.lowerBound < earliestMatch! {
                earliestMatch = range.lowerBound
            }
        }
        guard let hit = earliestMatch else {
            return normalized.count > maxLength ? String(normalized.prefix(maxLength)) + "..." : normalized
        }
        let hitOffset = normalized.distance(from: normalized.startIndex, to: hit)
        if hitOffset <= 24 {
            return normalized.count > maxLength ? String(normalized.prefix(maxLength)) + "..." : normalized
        }
        let startIdx = normalized.index(hit, offsetBy: -24, limitedBy: normalized.startIndex) ?? normalized.startIndex
        let endIdx = normalized.index(startIdx, offsetBy: maxLength, limitedBy: normalized.endIndex) ?? normalized.endIndex
        let prefix = startIdx > normalized.startIndex ? "..." : ""
        let suffix = endIdx < normalized.endIndex ? "..." : ""
        return prefix + String(normalized[startIdx..<endIdx]) + suffix
    }

    var isTrashed: Bool { trashedAt != nil }
}

enum NoteSortMode: String, Codable, CaseIterable, Identifiable {
    case updated
    case accessed
    case created
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updated: return "最近编辑"
        case .accessed: return "最近访问"
        case .created: return "最近创建"
        case .title: return "按标题"
        }
    }
}

struct SearchHighlightSegment: Identifiable, Hashable {
    let id: Int
    let text: String
    let highlighted: Bool
}

struct LinkTargetPreview: Identifiable, Hashable {
    var id: String { noteID ?? "missing:\(targetName)#\(anchor)" }
    let exists: Bool
    let noteID: String?
    let title: String
    let targetName: String
    let anchor: String
    let notebook: String
    let tags: [String]
    let snippet: String
    let outgoingCount: Int
    let backlinkCount: Int
    let updatedAt: Date?
    let lastAccessedAt: Date?
}

struct LinkCandidate: Identifiable, Hashable {
    var id: String { noteID }
    let noteID: String
    let title: String
    let notebook: String
    let reason: String
    let score: Int
}

struct OutlineHeading: Identifiable, Hashable {
    let id: String
    let level: Int
    let title: String
    let line: Int
}

struct WikiLink: Hashable {
    let target: String
    let anchor: String?
    let label: String
}

struct NoteLink: Identifiable, Hashable {
    let id: String
    let sourceID: String
    let sourceTitle: String
    let targetID: String
    let targetTitle: String
    let anchor: String
}

// MARK: - Vaults and projects

struct Vault: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var detail: String
    var createdAt: Date
    var folderPath: String? = nil
}

struct LexiProject: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var vaultID: String
}

// MARK: - Mind map

enum MindMapLayout: String, Codable, CaseIterable, Identifiable {
    case right, balanced, org
    var id: String { rawValue }
    var label: String {
        switch self {
        case .right: return "向右发散"
        case .balanced: return "左右平衡"
        case .org: return "组织架构"
        }
    }
    var shortLabel: String {
        switch self {
        case .right: return "向右"
        case .balanced: return "双向"
        case .org: return "组织"
        }
    }
}

private enum CrossPlatformJSON {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    static func string(_ c: KeyedDecodingContainer<AnyKey>, _ keys: String..., default fallback: String = "") -> String {
        for k in keys {
            if let key = AnyKey(stringValue: k), let v = try? c.decodeIfPresent(String.self, forKey: key) {
                return v
            }
        }
        return fallback
    }

    static func optionalString(_ c: KeyedDecodingContainer<AnyKey>, _ keys: String...) -> String? {
        for k in keys {
            if let key = AnyKey(stringValue: k), let v = try? c.decodeIfPresent(String.self, forKey: key), !v.isEmpty {
                return v
            }
        }
        return nil
    }

    static func date(_ c: KeyedDecodingContainer<AnyKey>, _ keys: String..., default fallback: Date? = nil) -> Date? {
        for k in keys {
            guard let key = AnyKey(stringValue: k) else { continue }
            if let num = try? c.decodeIfPresent(Double.self, forKey: key) {
                if num <= 0 { continue }
                return Date(timeIntervalSince1970: num > 1e11 ? num / 1000.0 : num)
            }
            if let str = try? c.decodeIfPresent(String.self, forKey: key), let d = LexiDate.parse(str) {
                return d
            }
        }
        return fallback
    }
}

struct MindNode: Identifiable, Codable, Hashable {
    var id: String
    var parentID: String
    var text: String
    var order: Int
    var colorTag: NoteColorTag
    var noteRefID: String?
    var noteRefTitle: String?
    var note: String?
    var collapsed: Bool

    init(id: String = "node-\(UUID().uuidString.lowercased())",
         parentID: String = "",
         text: String,
         order: Int = 0,
         colorTag: NoteColorTag = .purple,
         noteRefID: String? = nil,
         noteRefTitle: String? = nil,
         note: String? = nil,
         collapsed: Bool = false) {
        self.id = id
        self.parentID = parentID
        self.text = text
        self.order = order
        self.colorTag = colorTag
        self.noteRefID = noteRefID
        self.noteRefTitle = noteRefTitle
        self.note = note
        self.collapsed = collapsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CrossPlatformJSON.AnyKey.self)
        id = CrossPlatformJSON.string(c, "id", default: "node-\(UUID().uuidString.lowercased())")
        parentID = CrossPlatformJSON.string(c, "parentID", "parentId")
        text = CrossPlatformJSON.string(c, "text")
        if let k = CrossPlatformJSON.AnyKey(stringValue: "order"), let o = try? c.decode(Int.self, forKey: k) {
            order = o
        } else {
            order = 0
        }
        if let k = CrossPlatformJSON.AnyKey(stringValue: "colorTag"), let tag = try? c.decode(NoteColorTag.self, forKey: k) {
            colorTag = tag
        } else {
            colorTag = .purple
        }
        noteRefID = CrossPlatformJSON.optionalString(c, "noteRefID", "noteRefId")
        noteRefTitle = CrossPlatformJSON.optionalString(c, "noteRefTitle")
        note = CrossPlatformJSON.optionalString(c, "note")
        if let k = CrossPlatformJSON.AnyKey(stringValue: "collapsed"), let col = try? c.decodeIfPresent(Bool.self, forKey: k) {
            collapsed = col
        } else {
            collapsed = false
        }
    }
}

struct MindMap: Identifiable, Codable, Hashable {
    var id: String
    var vaultID: String
    var title: String
    var layout: MindMapLayout
    var rootNodeID: String
    var nodes: [MindNode]
    var favorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var trashedAt: Date?

    init(id: String, vaultID: String, title: String, layout: MindMapLayout, rootNodeID: String,
         nodes: [MindNode], favorite: Bool, createdAt: Date, updatedAt: Date, trashedAt: Date? = nil) {
        self.id = id
        self.vaultID = vaultID
        self.title = title
        self.layout = layout
        self.rootNodeID = rootNodeID
        self.nodes = nodes
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CrossPlatformJSON.AnyKey.self)
        id = CrossPlatformJSON.string(c, "id", default: "map-\(UUID().uuidString.lowercased())")
        vaultID = CrossPlatformJSON.string(c, "vaultID", "vaultId")
        title = CrossPlatformJSON.string(c, "title", default: "未命名导图")
        let layoutRaw = CrossPlatformJSON.string(c, "layout", "layoutKind", default: "right")
        layout = MindMapLayout(rawValue: layoutRaw) ?? .right
        if let k = CrossPlatformJSON.AnyKey(stringValue: "nodes"), let decodedNodes = try? c.decode([MindNode].self, forKey: k) {
            nodes = decodedNodes
        } else {
            nodes = []
        }
        rootNodeID = CrossPlatformJSON.string(c, "rootNodeID", "rootNodeId", default: nodes.first?.id ?? "")
        if let k = CrossPlatformJSON.AnyKey(stringValue: "favorite"), let fav = try? c.decodeIfPresent(Bool.self, forKey: k) {
            favorite = fav
        } else {
            favorite = false
        }
        createdAt = CrossPlatformJSON.date(c, "createdAt", default: Date()) ?? Date()
        updatedAt = CrossPlatformJSON.date(c, "updatedAt", default: createdAt) ?? createdAt
        trashedAt = CrossPlatformJSON.date(c, "trashedAt")
    }

    func children(of nodeID: String) -> [MindNode] {
        nodes.filter { $0.parentID == nodeID }.sorted { $0.order < $1.order }
    }
}

// MARK: - Canvas

struct CanvasCard: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var content: String
    var noteRefID: String?
    var noteRefTitle: String?
    var x: Double
    var y: Double
    var colorTag: NoteColorTag

    init(id: String, title: String, content: String, noteRefID: String? = nil, noteRefTitle: String? = nil,
         x: Double, y: Double, colorTag: NoteColorTag = .purple) {
        self.id = id
        self.title = title
        self.content = content
        self.noteRefID = noteRefID
        self.noteRefTitle = noteRefTitle
        self.x = x
        self.y = y
        self.colorTag = colorTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CrossPlatformJSON.AnyKey.self)
        id = CrossPlatformJSON.string(c, "id", default: "card-\(UUID().uuidString.lowercased())")
        title = CrossPlatformJSON.string(c, "title")
        content = CrossPlatformJSON.string(c, "content")
        noteRefID = CrossPlatformJSON.optionalString(c, "noteRefID", "noteRefId")
        noteRefTitle = CrossPlatformJSON.optionalString(c, "noteRefTitle")
        x = (CrossPlatformJSON.AnyKey(stringValue: "x").flatMap { try? c.decode(Double.self, forKey: $0) }) ?? 0
        y = (CrossPlatformJSON.AnyKey(stringValue: "y").flatMap { try? c.decode(Double.self, forKey: $0) }) ?? 0
        colorTag = (CrossPlatformJSON.AnyKey(stringValue: "colorTag").flatMap { try? c.decode(NoteColorTag.self, forKey: $0) }) ?? .purple
    }
}

struct CanvasEdge: Identifiable, Codable, Hashable {
    var id: String
    var fromID: String
    var toID: String
    var label: String

    init(id: String, fromID: String, toID: String, label: String) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CrossPlatformJSON.AnyKey.self)
        id = CrossPlatformJSON.string(c, "id", default: "edge-\(UUID().uuidString.lowercased())")
        fromID = CrossPlatformJSON.string(c, "fromID", "fromId")
        toID = CrossPlatformJSON.string(c, "toID", "toId")
        label = CrossPlatformJSON.string(c, "label")
    }
}

struct CanvasBoard: Identifiable, Codable, Hashable {
    var id: String
    var vaultID: String
    var title: String
    var cards: [CanvasCard]
    var edges: [CanvasEdge]
    var createdAt: Date
    var updatedAt: Date

    init(id: String, vaultID: String, title: String, cards: [CanvasCard], edges: [CanvasEdge], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.vaultID = vaultID
        self.title = title
        self.cards = cards
        self.edges = edges
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CrossPlatformJSON.AnyKey.self)
        id = CrossPlatformJSON.string(c, "id", default: "canvas-\(UUID().uuidString.lowercased())")
        vaultID = CrossPlatformJSON.string(c, "vaultID", "vaultId")
        title = CrossPlatformJSON.string(c, "title", default: "未命名白板")
        cards = (CrossPlatformJSON.AnyKey(stringValue: "cards").flatMap { try? c.decode([CanvasCard].self, forKey: $0) }) ?? []
        edges = (CrossPlatformJSON.AnyKey(stringValue: "edges").flatMap { try? c.decode([CanvasEdge].self, forKey: $0) }) ?? []
        createdAt = CrossPlatformJSON.date(c, "createdAt", default: Date()) ?? Date()
        updatedAt = CrossPlatformJSON.date(c, "updatedAt", default: createdAt) ?? createdAt
    }
}

// MARK: - Tabs

enum TabKind: String, Codable, Hashable {
    case note, map, canvas, graph, trash
}

struct WorkspaceTab: Identifiable, Codable, Hashable {
    var kind: TabKind
    var refID: String
    var id: String { "\(kind.rawValue):\(refID)" }

    init(kind: TabKind, refID: String) {
        self.kind = kind
        self.refID = refID
    }
}

// MARK: - Search (port of LexiSearch)

struct SearchTerm {
    var field: String
    var text: String
    var excluded: Bool
}

enum NoteSearch {
    static func parse(_ query: String) -> [SearchTerm] {
        guard let regex = try? NSRegularExpression(pattern: "(?:[^\\s\"']+|\"[^\"]*\"|'[^']*')+") else { return [] }
        let ns = query as NSString
        let matches = regex.matches(in: query, range: NSRange(location: 0, length: ns.length))
        var terms: [SearchTerm] = []
        for match in matches {
            var text = ns.substring(with: match.range)
            var excluded = false
            if text.hasPrefix("-") && text.count > 1 {
                excluded = true
                text = String(text.dropFirst())
            }
            var field = ""
            if let colon = text.firstIndex(of: ":"), colon != text.startIndex {
                let candidate = String(text[text.startIndex..<colon]).lowercased()
                if ["tag", "type", "notebook", "path"].contains(candidate) || candidate.hasPrefix("[") {
                    field = candidate
                    text = String(text[text.index(after: colon)...])
                }
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
            if !text.isEmpty { terms.append(SearchTerm(field: field, text: text, excluded: excluded)) }
        }
        return terms
    }

    static func matches(_ note: Note, query: String) -> Bool {
        let haystack = "\(note.title)\n\(note.content)\n\(note.notebook)\n\(note.tags.joined(separator: " "))".lowercased()
        for term in parse(query) {
            var found = false
            if term.field == "tag" {
                let tag = term.text.hasPrefix("#") ? String(term.text.dropFirst()) : term.text
                found = note.tags.contains { $0.lowercased() == tag || $0.lowercased().hasPrefix(tag + "/") }
            } else if term.field == "type" {
                found = note.type.rawValue.lowercased() == term.text
            } else if term.field == "notebook" {
                found = note.notebook.lowercased().contains(term.text)
            } else if term.field == "path" {
                found = note.path.lowercased().contains(term.text)
            } else if term.field.hasPrefix("[") && term.field.hasSuffix("]") {
                let key = String(term.field.dropFirst().dropLast())
                found = note.properties.contains { $0.key.lowercased() == key && $0.value.lowercased().contains(term.text) }
            } else {
                found = haystack.contains(term.text)
            }
            if term.excluded ? found : !found { return false }
        }
        return true
    }

    /// Lower is better. A subsequence also matches initials typed in order.
    static func rank(_ title: String, _ query: String) -> Int {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = title.lowercased()
        if needle.isEmpty { return 0 }
        if text == needle { return 0 }
        if let range = text.range(of: needle) {
            return 1 + text.distance(from: text.startIndex, to: range.lowerBound)
        }
        var cursor = text.startIndex
        var gaps = 0
        for character in needle {
            guard let next = text[cursor...].firstIndex(of: character) else { return -1 }
            gaps += text.distance(from: cursor, to: next)
            cursor = text.index(after: next)
        }
        return 100 + gaps
    }

    static func highlightTerms(_ query: String) -> [String] {
        let parsed = parse(query)
        var seen: Set<String> = []
        var result: [String] = []
        for term in parsed {
            guard !term.excluded else { continue }
            var token = term.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.field == "tag" {
                if token.hasPrefix("#") { token = String(token.dropFirst()) }
            } else if term.field.isEmpty {
                if token.hasPrefix("#") && token.count > 1 {
                    token = String(token.dropFirst())
                }
            } else {
                continue
            }
            guard !token.isEmpty else { continue }
            let key = token.lowercased()
            if seen.insert(key).inserted {
                result.append(token)
            }
        }
        return result.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.lowercased() < $1.lowercased()
        }
    }

    static func highlightSegments(_ text: String, query: String) -> [SearchHighlightSegment] {
        guard !text.isEmpty else { return [] }
        let terms = highlightTerms(query)
        guard !terms.isEmpty else {
            return [SearchHighlightSegment(id: 0, text: text, highlighted: false)]
        }
        var segments: [SearchHighlightSegment] = []
        var cursor = text.startIndex
        var nextID = 0
        while cursor < text.endIndex {
            var bestRange: Range<String.Index>?
            for term in terms {
                guard let range = text.range(of: term, options: [.caseInsensitive], range: cursor..<text.endIndex),
                      !range.isEmpty else { continue }
                if let current = bestRange {
                    if range.lowerBound < current.lowerBound ||
                        (range.lowerBound == current.lowerBound &&
                         text.distance(from: range.lowerBound, to: range.upperBound) >
                         text.distance(from: current.lowerBound, to: current.upperBound)) {
                        bestRange = range
                    }
                } else {
                    bestRange = range
                }
            }
            guard let hit = bestRange else {
                segments.append(SearchHighlightSegment(id: nextID, text: String(text[cursor..<text.endIndex]), highlighted: false))
                break
            }
            if hit.lowerBound > cursor {
                segments.append(SearchHighlightSegment(id: nextID, text: String(text[cursor..<hit.lowerBound]), highlighted: false))
                nextID += 1
            }
            segments.append(SearchHighlightSegment(id: nextID, text: String(text[hit]), highlighted: true))
            nextID += 1
            cursor = hit.upperBound
        }
        return segments
    }

    static func accessDate(for note: Note, accessedAt: [String: Date] = [:]) -> Date {
        accessedAt[note.id] ?? note.lastAccessedAt ?? note.updatedAt
    }

    static func sortNotes(_ notes: [Note],
                          mode: NoteSortMode,
                          accessedAt: [String: Date] = [:],
                          pinnedFirst: Bool = true) -> [Note] {
        notes.sorted { lhs, rhs in
            if pinnedFirst && lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            switch mode {
            case .accessed:
                let la = accessDate(for: lhs, accessedAt: accessedAt)
                let ra = accessDate(for: rhs, accessedAt: accessedAt)
                if la != ra { return la > ra }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .updated:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .created:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .title:
                let cmp = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}

// MARK: - Date helpers

enum LexiDate {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func parse(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return fallback.date(from: value)
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func weekdayCN(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 2 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "昨天 HH:mm"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - Templates (port of LexiTemplateLibrary)

struct NoteTemplate: Identifiable, Hashable {
    var id: String
    var title: String
    var category: String
    var content: String
    var tags: [String]
    var properties: [NoteProperty]
    var builtIn: Bool
}

enum TemplateLibrary {
    static let builtins: [NoteTemplate] = [
        NoteTemplate(id: "builtin-daily", title: "每日记录", category: "日常",
                     content: "# {{date}} {{weekday}}\n\n## 今日重点\n\n- [ ] \n\n## 随手记录\n\n\n\n## 今日回顾\n\n- 今天完成了什么：\n- 明天想继续什么：\n",
                     tags: ["日记"], properties: [], builtIn: true),
        NoteTemplate(id: "builtin-schedule", title: "日程计划", category: "计划",
                     content: "# {{title}}\n\n日期：{{date}} {{weekday}}\n\n## 时间安排\n\n| 时间 | 事项 | 备注 |\n| --- | --- | --- |\n| 上午 |  |  |\n| 下午 |  |  |\n| 晚间 |  |  |\n\n## 待办清单\n\n- [ ] \n\n## 调整与提醒\n\n",
                     tags: ["计划"], properties: [], builtIn: true),
        NoteTemplate(id: "builtin-code", title: "代码笔记", category: "代码",
                     content: "# {{title}}\n\n记录时间：{{date}} {{time}}\n\n## 问题与目标\n\n\n\n## 代码\n\n```\n\n```\n\n## 实现说明\n\n\n\n## 验证结果\n\n- 输入与环境：\n- 预期结果：\n- 实际结果：\n\n## 后续改进\n\n- [ ] \n",
                     tags: ["代码"], properties: [], builtIn: true),
        NoteTemplate(id: "builtin-study", title: "学习笔记", category: "学习",
                     content: "# {{title}}\n\n学习日期：{{date}} {{weekday}}\n\n## 学习目标\n\n- [ ] \n\n## 核心概念\n\n\n\n## 示例与理解\n\n\n\n## 疑问与关联\n\n\n\n## 复习清单\n\n- [ ] 用自己的话解释核心概念\n- [ ] 完成一次练习\n",
                     tags: ["学习"], properties: [], builtIn: true),
        NoteTemplate(id: "builtin-meeting", title: "会议纪要", category: "会议",
                     content: "# {{title}}\n\n会议时间：{{date}} {{time}}\n参会人员：\n\n## 议题\n\n1. \n\n## 讨论记录\n\n\n\n## 决定事项\n\n\n\n## 后续行动\n\n| 事项 | 负责人 | 截止时间 | 状态 |\n| --- | --- | --- | --- |\n|  |  |  | 待办 |\n\n## 下次跟进\n\n",
                     tags: ["会议"], properties: [], builtIn: true),
        NoteTemplate(id: "builtin-project", title: "项目规划", category: "项目",
                     content: "# {{title}}\n\n创建日期：{{date}}\n\n## 目标与范围\n\n- 项目目标：\n- 交付内容：\n- 验收标准：\n\n## 里程碑\n\n| 阶段 | 交付物 | 计划完成时间 |\n| --- | --- | --- |\n| 准备 |  |  |\n| 实施 |  |  |\n| 验收 |  |  |\n\n## 当前任务\n\n- [ ] \n\n## 风险与依赖\n\n\n\n## 进展记录\n\n### {{date}} {{time}}\n\n",
                     tags: ["项目"], properties: [], builtIn: true)
    ]

    static func render(_ template: NoteTemplate, title: String, now: Date = Date()) -> (title: String, content: String, tags: [String]) {
        let dateKey = LexiDate.dayKey(now)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: now)
        let weekday = LexiDate.weekdayCN(now)
        let body = template.content
            .replacingOccurrences(of: "{{date}}", with: dateKey)
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{weekday}}", with: weekday)
            .replacingOccurrences(of: "{{title}}", with: title)
        return (title, body, template.tags)
    }
}
