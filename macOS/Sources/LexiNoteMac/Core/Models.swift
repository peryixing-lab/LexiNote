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

    var isTrashed: Bool { trashedAt != nil }
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentID = try container.decode(String.self, forKey: .parentID)
        text = try container.decode(String.self, forKey: .text)
        order = try container.decode(Int.self, forKey: .order)
        colorTag = try container.decode(NoteColorTag.self, forKey: .colorTag)
        noteRefID = try container.decodeIfPresent(String.self, forKey: .noteRefID)
        noteRefTitle = try container.decodeIfPresent(String.self, forKey: .noteRefTitle)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
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
}

struct CanvasEdge: Identifiable, Codable, Hashable {
    var id: String
    var fromID: String
    var toID: String
    var label: String
}

struct CanvasBoard: Identifiable, Codable, Hashable {
    var id: String
    var vaultID: String
    var title: String
    var cards: [CanvasCard]
    var edges: [CanvasEdge]
    var createdAt: Date
    var updatedAt: Date
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
