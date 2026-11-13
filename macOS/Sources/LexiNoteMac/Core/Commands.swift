import Foundation
import SwiftUI
import AppKit

extension Notification.Name {
    static let lexiEditorCommand = Notification.Name("LexiNote.editorCommand")
    static let lexiFindInNote = Notification.Name("LexiNote.findInNote")
    static let lexiOpenSettings = Notification.Name("LexiNote.openSettings")
    static let lexiFocusSidebarSearch = Notification.Name("LexiNote.focusSidebarSearch")
    static let lexiFocusEditor = Notification.Name("LexiNote.focusEditor")
    static let lexiOpenPluginView = Notification.Name("LexiNote.openPluginView")
}

enum EditorCommand: String {
    case bold, italic, strike, highlight
    case h1, h2, h3, h4, h5, h6, headingClear
    case bullet, ordered, indent, outdent, quote
    case todo, table, code, inlineCode, formula, inlineMath, callout, link, embed, footnote
    case comment, clearFormat
    case lineUp, lineDown, deleteParagraph
    case date, time
    case reading, source, split
    case fold, unfold
    case find
    case focus
}

enum CommandAction {
    case palette, quickSwitch
    case newNote, quickNote, studyNote, dailyNote, templates
    case save, exportMarkdown, exportMarkdownBundle, exportBackup, importMarkdown, rebuildIndex
    case closeTab, closeOthers, closeAll, duplicateNote, trashNote, copyPath, revealInFinder
    case bookmarkFile, bookmarkRemove
    case newMap, newCanvas, convertToMap
    case graph, trash
    case toggleSidebar, toggleInspector, toggleRibbon, outline, backlinks, properties
    case zoomIn, zoomOut, zoomReset, fontIncrease, fontDecrease
    case appearanceLight, appearanceDark, appearanceSystem, themeToggle, widthToggle, defaultViewToggle, sourceToggle
    case settings, help, welcome
    case tabPrevious, tabNext, tabIndex(Int)
    case editor(EditorCommand)
    case plugin(String)
}

struct LexiCommand: Identifiable {
    let id: String
    let title: String
    let group: String
    let shortcut: String
    let symbol: String
    let action: CommandAction
    var source: String = "知萤"
    var defaultBindings: [String] {
        let converted = HotkeyCodec.fromDisplayShortcut(shortcut)
        return converted.isEmpty ? [] : [converted]
    }
}

enum HotkeyCodec {
    static func fromDisplayShortcut(_ shortcut: String) -> String {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("+") { return trimmed }
        var parts: [String] = []
        var remainder = trimmed
        if remainder.contains("⌃") {
            parts.append("Ctrl")
            remainder = remainder.replacingOccurrences(of: "⌃", with: "")
        }
        if remainder.contains("⌥") {
            parts.append("Alt")
            remainder = remainder.replacingOccurrences(of: "⌥", with: "")
        }
        if remainder.contains("⇧") {
            parts.append("Shift")
            remainder = remainder.replacingOccurrences(of: "⇧", with: "")
        }
        if remainder.contains("⌘") {
            parts.append("Meta")
            remainder = remainder.replacingOccurrences(of: "⌘", with: "")
        }
        let key = remainder.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return "" }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    static func displayLabel(_ binding: String) -> String {
        binding
    }

    static func canonical(from event: NSEvent) -> String? {
        let keyCode = event.keyCode
        // Ignore standalone modifier key presses
        let modifierCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierCodes.contains(keyCode) { return nil }

        guard let key = keyName(from: event) else { return nil }
        let flags = event.modifierFlags.intersection([.control, .command, .option, .shift])
        var parts: [String] = []
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.command) { parts.append("Meta") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        let isFunction = key.hasPrefix("F") && key.count >= 2 && Int(key.dropFirst()) != nil
        if parts.isEmpty && !isFunction { return nil }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    static func matches(event: NSEvent, binding: String) -> Bool {
        guard let eventCanonical = canonical(from: event) else { return false }
        return eventCanonical.caseInsensitiveCompare(binding) == .orderedSame
    }

    static func keyName(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76: return "ENTER"
        case 48: return "TAB"
        case 49: return "SPACE"
        case 51: return "BACKSPACE"
        case 53: return "ESCAPE"
        case 117: return "DELETE"
        case 115: return "HOME"
        case 119: return "END"
        case 116: return "PAGEUP"
        case 121: return "PAGEDOWN"
        case 123: return "ARROWLEFT"
        case 124: return "ARROWRIGHT"
        case 125: return "ARROWDOWN"
        case 126: return "ARROWUP"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chars.isEmpty else { return nil }
        return chars.uppercased()
    }

    static func bindings(overrides: [String: [String]], commandID: String, defaults: [String]) -> [String] {
        if let custom = overrides[commandID] { return custom }
        return defaults
    }

    static let systemShortcuts: [String: String] = [
        "Meta+Q": "系统退出应用",
        "Meta+H": "系统隐藏窗口",
        "Meta+M": "系统最小化窗口",
        "Meta+SPACE": "Spotlight 搜索",
        "Ctrl+SPACE": "输入法切换",
        "Meta+TAB": "应用切换器",
        "Meta+C": "系统复制",
        "Meta+V": "系统粘贴",
        "Meta+X": "系统剪切",
        "Meta+A": "系统全选",
        "Meta+Z": "系统撤销"
    ]

    static func systemConflictReason(for bindings: [String]) -> String? {
        for binding in bindings {
            let key = binding.uppercased()
            if let reason = systemShortcuts[key] {
                return "\(binding) · \(reason)"
            }
        }
        return nil
    }
}

enum CommandCatalog {
    static let all: [LexiCommand] = [
        LexiCommand(id: "palette", title: "打开命令面板", group: "通用", shortcut: "⌘K", symbol: "command", action: .palette),
        LexiCommand(id: "switcher", title: "快速切换文档", group: "通用", shortcut: "⌘P", symbol: "arrow.left.arrow.right", action: .quickSwitch),
        LexiCommand(id: "save", title: "保存当前文件", group: "文件", shortcut: "⌘S", symbol: "square.and.arrow.down", action: .save),
        LexiCommand(id: "new", title: "新建 Markdown 笔记", group: "文件", shortcut: "⌘N", symbol: "doc.badge.plus", action: .newNote),
        LexiCommand(id: "quick", title: "新建快速笔记", group: "文件", shortcut: "⇧⌘N", symbol: "bolt.badge.plus", action: .quickNote),
        LexiCommand(id: "study", title: "新建学习笔记", group: "文件", shortcut: "", symbol: "book.closed", action: .studyNote),
        LexiCommand(id: "daily", title: "打开今日笔记", group: "文件", shortcut: "⌘D", symbol: "calendar", action: .dailyNote),
        LexiCommand(id: "templates", title: "从模板新建笔记", group: "文件", shortcut: "⇧⌘T", symbol: "doc.on.doc", action: .templates),
        LexiCommand(id: "close-tab", title: "保存并关闭当前标签", group: "文件", shortcut: "⌘W", symbol: "xmark.square", action: .closeTab),
        LexiCommand(id: "close-others", title: "关闭其他标签页", group: "文件", shortcut: "", symbol: "xmark.circle", action: .closeOthers),
        LexiCommand(id: "close-all", title: "关闭所有标签页", group: "文件", shortcut: "", symbol: "xmark.circle.fill", action: .closeAll),
        LexiCommand(id: "duplicate", title: "复制当前文件", group: "文件", shortcut: "⇧⌘D", symbol: "plus.square.on.square", action: .duplicateNote),
        LexiCommand(id: "delete-file", title: "删除当前文件", group: "文件", shortcut: "", symbol: "trash", action: .trashNote),
        LexiCommand(id: "reveal-file", title: "在 Finder 中显示", group: "文件", shortcut: "⇧⌘R", symbol: "folder", action: .revealInFinder),
        LexiCommand(id: "copy-path", title: "复制当前文件绝对路径", group: "文件", shortcut: "", symbol: "doc.on.clipboard", action: .copyPath),
        LexiCommand(id: "export-md", title: "导出当前笔记 Markdown", group: "文件", shortcut: "⇧⌘E", symbol: "square.and.arrow.up", action: .exportMarkdown),
        LexiCommand(id: "export-md-bundle", title: "导出 Markdown 合集", group: "文件", shortcut: "", symbol: "doc.zipper", action: .exportMarkdownBundle),
        LexiCommand(id: "backup", title: "导出工作区压缩包", group: "文件", shortcut: "", symbol: "doc.zipper", action: .exportBackup),
        LexiCommand(id: "import", title: "导入 Markdown 文件", group: "文件", shortcut: "⌘O", symbol: "square.and.arrow.down", action: .importMarkdown),
        LexiCommand(id: "rebuild-index", title: "重建索引", group: "文件", shortcut: "", symbol: "arrow.triangle.2.circlepath", action: .rebuildIndex),
        LexiCommand(id: "bookmark-file", title: "书签：收藏", group: "书签", shortcut: "", symbol: "bookmark", action: .bookmarkFile),
        LexiCommand(id: "bookmark-remove", title: "书签：移除当前文件的书签", group: "书签", shortcut: "", symbol: "bookmark.slash", action: .bookmarkRemove),

        LexiCommand(id: "editor-bold", title: "加粗 / 取消加粗", group: "格式", shortcut: "⌘B", symbol: "bold", action: .editor(.bold)),
        LexiCommand(id: "editor-italic", title: "倾斜 / 取消倾斜", group: "格式", shortcut: "⌘I", symbol: "italic", action: .editor(.italic)),
        LexiCommand(id: "editor-strike", title: "添加删除线", group: "格式", shortcut: "⇧⌘X", symbol: "strikethrough", action: .editor(.strike)),
        LexiCommand(id: "editor-highlight", title: "高亮", group: "格式", shortcut: "⇧⌘H", symbol: "highlighter", action: .editor(.highlight)),
        LexiCommand(id: "editor-h1", title: "设为小标题 1", group: "格式", shortcut: "", symbol: "textformat.size.larger", action: .editor(.h1)),
        LexiCommand(id: "editor-h2", title: "设为小标题 2", group: "格式", shortcut: "", symbol: "textformat.size", action: .editor(.h2)),
        LexiCommand(id: "editor-h3", title: "设为小标题 3", group: "格式", shortcut: "", symbol: "textformat.size.smaller", action: .editor(.h3)),
        LexiCommand(id: "editor-h4", title: "设为小标题 4", group: "格式", shortcut: "", symbol: "textformat", action: .editor(.h4)),
        LexiCommand(id: "editor-h5", title: "设为小标题 5", group: "格式", shortcut: "", symbol: "textformat", action: .editor(.h5)),
        LexiCommand(id: "editor-h6", title: "设为小标题 6", group: "格式", shortcut: "", symbol: "textformat", action: .editor(.h6)),
        LexiCommand(id: "editor-heading-clear", title: "移除小标题格式", group: "格式", shortcut: "", symbol: "textformat.alt", action: .editor(.headingClear)),
        LexiCommand(id: "editor-bullet", title: "无序列表", group: "格式", shortcut: "", symbol: "list.bullet", action: .editor(.bullet)),
        LexiCommand(id: "editor-ordered", title: "有序列表", group: "格式", shortcut: "", symbol: "list.number", action: .editor(.ordered)),
        LexiCommand(id: "editor-indent", title: "缩进列表", group: "格式", shortcut: "", symbol: "increase.indent", action: .editor(.indent)),
        LexiCommand(id: "editor-outdent", title: "取消列表缩进", group: "格式", shortcut: "", symbol: "decrease.indent", action: .editor(.outdent)),
        LexiCommand(id: "editor-quote", title: "引用块", group: "格式", shortcut: "", symbol: "text.quote", action: .editor(.quote)),
        LexiCommand(id: "editor-todo", title: "插入待办事项", group: "格式", shortcut: "", symbol: "checklist", action: .editor(.todo)),
        LexiCommand(id: "editor-table", title: "插入表格", group: "格式", shortcut: "", symbol: "tablecells", action: .editor(.table)),
        LexiCommand(id: "editor-code", title: "插入代码块", group: "格式", shortcut: "", symbol: "chevron.left.forwardslash.chevron.right", action: .editor(.code)),
        LexiCommand(id: "editor-inline-code", title: "行内代码", group: "格式", shortcut: "", symbol: "curlybraces", action: .editor(.inlineCode)),
        LexiCommand(id: "editor-formula", title: "插入数学公式", group: "格式", shortcut: "", symbol: "function", action: .editor(.formula)),
        LexiCommand(id: "editor-inline-math", title: "行内数学公式", group: "格式", shortcut: "", symbol: "x.squareroot", action: .editor(.inlineMath)),
        LexiCommand(id: "editor-callout", title: "插入标注", group: "格式", shortcut: "", symbol: "quote.opening", action: .editor(.callout)),
        LexiCommand(id: "editor-link", title: "插入双向链接", group: "格式", shortcut: "⌘L", symbol: "link", action: .editor(.link)),
        LexiCommand(id: "editor-comment", title: "注释/取消注释", group: "格式", shortcut: "", symbol: "text.bubble", action: .editor(.comment)),
        LexiCommand(id: "editor-footnote", title: "插入脚注", group: "格式", shortcut: "", symbol: "number.circle", action: .editor(.footnote)),
        LexiCommand(id: "editor-clear-format", title: "清除格式", group: "格式", shortcut: "", symbol: "eraser", action: .editor(.clearFormat)),
        LexiCommand(id: "editor-line-up", title: "与上一行互换", group: "编辑", shortcut: "", symbol: "arrow.up.to.line", action: .editor(.lineUp)),
        LexiCommand(id: "editor-line-down", title: "与下一行互换", group: "编辑", shortcut: "", symbol: "arrow.down.to.line", action: .editor(.lineDown)),
        LexiCommand(id: "editor-delete-paragraph", title: "删除段落", group: "编辑", shortcut: "", symbol: "trash", action: .editor(.deleteParagraph)),
        LexiCommand(id: "insert-date", title: "插入当前日期", group: "格式", shortcut: "", symbol: "calendar.badge.clock", action: .editor(.date)),
        LexiCommand(id: "insert-time", title: "插入当前时间", group: "格式", shortcut: "", symbol: "clock", action: .editor(.time)),
        LexiCommand(id: "reading", title: "切换编辑与阅读", group: "格式", shortcut: "⌘E", symbol: "book", action: .editor(.reading)),
        LexiCommand(id: "source-toggle", title: "切换实时预览/源码模式", group: "格式", shortcut: "", symbol: "chevron.left.forwardslash.chevron.right", action: .sourceToggle),
        LexiCommand(id: "default-view-toggle", title: "切换新标签页的默认视图", group: "格式", shortcut: "", symbol: "eye", action: .defaultViewToggle),
        LexiCommand(id: "width-toggle", title: "切换限制行宽", group: "格式", shortcut: "", symbol: "arrow.left.and.right", action: .widthToggle),
        LexiCommand(id: "find", title: "在当前笔记中查找", group: "格式", shortcut: "⌘F", symbol: "magnifyingglass", action: .editor(.find)),
        LexiCommand(id: "focus-editor", title: "将焦点切换至编辑区", group: "格式", shortcut: "", symbol: "text.cursor", action: .editor(.focus)),

        LexiCommand(id: "tab-prev", title: "转到上一个标签页", group: "导航", shortcut: "⌃⇧[", symbol: "chevron.left", action: .tabPrevious),
        LexiCommand(id: "tab-next", title: "转到下一个标签页", group: "导航", shortcut: "⌃⇧]", symbol: "chevron.right", action: .tabNext),
        LexiCommand(id: "tab-1", title: "转到标签页 #1", group: "导航", shortcut: "⌘1", symbol: "1.square", action: .tabIndex(0)),
        LexiCommand(id: "tab-2", title: "转到标签页 #2", group: "导航", shortcut: "⌘2", symbol: "2.square", action: .tabIndex(1)),
        LexiCommand(id: "tab-3", title: "转到标签页 #3", group: "导航", shortcut: "⌘3", symbol: "3.square", action: .tabIndex(2)),
        LexiCommand(id: "tab-4", title: "转到标签页 #4", group: "导航", shortcut: "⌘4", symbol: "4.square", action: .tabIndex(3)),
        LexiCommand(id: "tab-9", title: "转到最后一个标签页", group: "导航", shortcut: "⌘9", symbol: "9.square", action: .tabIndex(8)),

        LexiCommand(id: "sidebar", title: "显示或隐藏侧边栏", group: "视图", shortcut: "⌃⌘S", symbol: "sidebar.leading", action: .toggleSidebar),
        LexiCommand(id: "inspector", title: "折叠/展开右侧边栏", group: "视图", shortcut: "⌥⌘S", symbol: "sidebar.trailing", action: .toggleInspector),
        LexiCommand(id: "ribbon-toggle", title: "显示/隐藏功能区", group: "视图", shortcut: "", symbol: "sidebar.left", action: .toggleRibbon),
        LexiCommand(id: "zoom-in", title: "放大", group: "视图", shortcut: "", symbol: "plus.magnifyingglass", action: .zoomIn),
        LexiCommand(id: "zoom-out", title: "缩小", group: "视图", shortcut: "", symbol: "minus.magnifyingglass", action: .zoomOut),
        LexiCommand(id: "zoom-reset", title: "重置缩放", group: "视图", shortcut: "", symbol: "arrow.counterclockwise", action: .zoomReset),
        LexiCommand(id: "font-increase", title: "增大字体", group: "视图", shortcut: "", symbol: "textformat.size.larger", action: .fontIncrease),
        LexiCommand(id: "font-decrease", title: "缩小字体", group: "视图", shortcut: "", symbol: "textformat.size.smaller", action: .fontDecrease),
        LexiCommand(id: "outline", title: "大纲：打开当前文件的大纲", group: "视图", shortcut: "⇧⌘O", symbol: "list.bullet.indent", action: .outline),
        LexiCommand(id: "backlinks", title: "反向链接：显示反向链接", group: "视图", shortcut: "", symbol: "arrow.uturn.backward", action: .backlinks),
        LexiCommand(id: "properties", title: "属性列表：显示笔记属性", group: "视图", shortcut: "", symbol: "slider.horizontal.3", action: .properties),
        LexiCommand(id: "theme-toggle", title: "切换浅色/深色模式", group: "外观", shortcut: "", symbol: "circle.lefthalf.filled", action: .themeToggle),
        LexiCommand(id: "light", title: "使用浅色外观", group: "外观", shortcut: "", symbol: "sun.max", action: .appearanceLight),
        LexiCommand(id: "dark", title: "使用深色外观", group: "外观", shortcut: "", symbol: "moon", action: .appearanceDark),
        LexiCommand(id: "system", title: "跟随系统外观", group: "外观", shortcut: "", symbol: "circle.lefthalf.filled", action: .appearanceSystem),

        LexiCommand(id: "map", title: "新建思维导图", group: "知识库", shortcut: "", symbol: "point.3.filled.connected.trianglepath.dotted", action: .newMap),
        LexiCommand(id: "canvas", title: "新建白板", group: "知识库", shortcut: "", symbol: "rectangle.3.group", action: .newCanvas),
        LexiCommand(id: "convert", title: "将当前笔记转为思维导图", group: "知识库", shortcut: "", symbol: "arrow.triangle.branch", action: .convertToMap),
        LexiCommand(id: "graph", title: "打开笔记关联图谱", group: "知识库", shortcut: "⌘G", symbol: "circle.hexagongrid", action: .graph),
        LexiCommand(id: "trash", title: "打开回收站", group: "知识库", shortcut: "", symbol: "trash", action: .trash),

        LexiCommand(id: "settings", title: "打开设置", group: "通用", shortcut: "⌘,", symbol: "gearshape", action: .settings),
        LexiCommand(id: "help", title: "打开使用说明", group: "帮助", shortcut: "", symbol: "questionmark.circle", action: .help),
        LexiCommand(id: "welcome", title: "显示欢迎引导", group: "帮助", shortcut: "", symbol: "sparkles", action: .welcome)
    ]

    @MainActor
    static func allWithPlugins() -> [LexiCommand] {
        var combined = all
        for pluginCmd in PluginCommandRegistry.shared.commands {
            let shortcutText = pluginCmd.hotkeys.first ?? ""
            combined.append(LexiCommand(
                id: pluginCmd.qualifiedId,
                title: pluginCmd.name,
                group: "插件 · \(pluginCmd.pluginName)",
                shortcut: shortcutText,
                symbol: "puzzlepiece.extension",
                action: .plugin(pluginCmd.qualifiedId),
                source: pluginCmd.pluginName
            ))
        }
        return combined
    }

    @MainActor
    static func filtered(_ query: String) -> [LexiCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = allWithPlugins()
        let ranked = source.compactMap { command -> (LexiCommand, Int)? in
            guard !trimmed.isEmpty else { return (command, 0) }
            let titleRank = NoteSearch.rank(command.title, trimmed)
            let groupRank = NoteSearch.rank(command.group, trimmed)
            let best = [titleRank, groupRank < 0 ? -1 : groupRank + 40].filter { $0 >= 0 }.min() ?? -1
            guard best >= 0 || command.id.localizedCaseInsensitiveContains(trimmed) else { return nil }
            return (command, best < 0 ? 80 : best)
        }
        return ranked.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}

@MainActor
enum CommandRouter {
    static var isRecordingHotkey = false

    @discardableResult
    static func performCustomHotkey(canonical: String, model: AppModel, settings: SettingsStore) -> Bool {
        let normalized = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let allCommands = CommandCatalog.allWithPlugins()

        if let match = settings.hotkeyOverrides.first(where: { (_, bindings) in
            bindings.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        }),
           let cmd = allCommands.first(where: { $0.id == match.key }) {
            perform(cmd, model: model)
            return true
        }

        for cmd in allCommands where cmd.id.hasPrefix("plugin:") {
            guard settings.hotkeyOverrides[cmd.id] == nil else { continue }
            if cmd.defaultBindings.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                perform(cmd, model: model)
                return true
            }
        }
        return false
    }

    static func perform(_ command: LexiCommand, model: AppModel) {
        perform(command.action, model: model)
    }

    static func perform(_ action: CommandAction, model: AppModel) {
        switch action {
        case .palette:
            model.presentCommandPalette()
        case .quickSwitch:
            model.presentQuickSwitch()
        case .newNote:
            model.createNote(title: "无标题笔记", type: .markdown)
        case .quickNote:
            model.createNote(title: "快速笔记", type: .quick, notebook: "速记收件箱")
        case .studyNote:
            model.createNote(title: "学习笔记", type: .study)
        case .dailyNote:
            model.openDailyNote()
        case .templates:
            model.templatesVisible = true
        case .save:
            if let note = model.currentNote {
                _ = model.saveNoteNow(note.id)
                model.showToast("已保存到本机", symbol: "checkmark.circle")
            }
        case .exportMarkdown:
            model.exportCurrentMarkdown()
        case .exportMarkdownBundle:
            model.exportMarkdownBundle()
        case .exportBackup:
            model.exportWorkspaceZip()
        case .importMarkdown:
            model.importMarkdownFiles()
        case .rebuildIndex:
            model.rebuildIndex()
        case .closeTab:
            if !model.selectedTabID.isEmpty { model.closeTab(model.selectedTabID) }
        case .closeOthers:
            if !model.selectedTabID.isEmpty { model.closeOtherTabs(keeping: model.selectedTabID) }
        case .closeAll:
            model.closeAllTabs()
        case .duplicateNote:
            if let note = model.currentNote { model.duplicateNote(note.id) }
        case .trashNote:
            if let note = model.currentNote { model.trashNote(note.id) }
        case .copyPath:
            if let note = model.currentNote { model.copyNotePath(note.id) }
        case .revealInFinder:
            if let note = model.currentNote { model.revealNoteInFinder(note.id) } else { model.revealStorageInFinder() }
        case .bookmarkFile:
            if let note = model.currentNote, !note.favorite {
                model.toggleFavorite(note.id)
                model.showToast("已收藏到书签", symbol: "bookmark.fill")
            }
        case .bookmarkRemove:
            if let note = model.currentNote, note.favorite {
                model.toggleFavorite(note.id)
                model.showToast("已移除书签", symbol: "bookmark.slash")
            }
        case .newMap:
            model.createMap()
        case .newCanvas:
            model.createCanvas()
        case .convertToMap:
            if let note = model.currentNote { model.convertNoteToMap(note) }
        case .graph:
            model.openGraph(focus: model.currentNote?.id)
        case .trash:
            model.openTrash()
        case .toggleSidebar:
            withAnimation(.easeInOut(duration: 0.18)) { model.settings.showSidebar.toggle() }
        case .toggleInspector:
            withAnimation(.easeInOut(duration: 0.18)) { model.settings.showInspector.toggle() }
        case .toggleRibbon:
            withAnimation(.easeInOut(duration: 0.18)) { model.settings.showRibbon.toggle() }
        case .zoomIn:
            model.settings.interfaceZoom = min(150, model.settings.interfaceZoom + 10)
        case .zoomOut:
            model.settings.interfaceZoom = max(75, model.settings.interfaceZoom - 10)
        case .zoomReset:
            model.settings.interfaceZoom = 100
        case .fontIncrease:
            model.settings.editorFontSize = min(32, model.settings.editorFontSize + 1)
        case .fontDecrease:
            model.settings.editorFontSize = max(10, model.settings.editorFontSize - 1)
        case .outline:
            model.settings.showInspector = true
            model.settings.inspectorMode = "outline"
        case .backlinks:
            model.settings.showInspector = true
            model.settings.inspectorMode = "links"
        case .properties:
            model.settings.showInspector = true
            model.settings.inspectorMode = "properties"
        case .appearanceLight:
            model.settings.appearance = .light
        case .appearanceDark:
            model.settings.appearance = .dark
        case .appearanceSystem:
            model.settings.appearance = .system
        case .themeToggle:
            model.settings.appearance = model.settings.appearance == .dark ? .light : .dark
        case .widthToggle:
            model.settings.limitEditorWidth.toggle()
        case .defaultViewToggle:
            model.settings.editorDefaultView = model.settings.editorDefaultView == "preview" ? "edit" : "preview"
        case .sourceToggle:
            model.settings.editorDefaultMode = model.settings.editorDefaultMode == "source" ? "live" : "source"
        case .settings:
            model.presentSettings()
        case .help, .welcome:
            model.welcomeVisible = true
        case .tabPrevious:
            model.nextTab(offset: -1)
        case .tabNext:
            model.nextTab(offset: 1)
        case .tabIndex(let index):
            if index < model.openTabs.count {
                model.selectTab(model.openTabs[index].id)
            } else if let last = model.openTabs.last {
                model.selectTab(last.id)
            }
        case .editor(let command):
            NotificationCenter.default.post(name: .lexiEditorCommand, object: nil,
                                            userInfo: ["command": command.rawValue])
        case .plugin(let qualifiedId):
            Task { @MainActor in
                await model.plugins.runCommand(qualifiedId: qualifiedId)
            }
        }
    }
}
