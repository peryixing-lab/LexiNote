import Foundation
import AppKit

// MARK: - Path & Vault Adapter

enum LexiPathValidator {
    private static let forbiddenSegments: Set<String> = [".", "..", ".plugins", ".lexi", ".git", ".obsidian", ".trash"]

    static func sanitizeVaultPath(_ raw: String) -> String? {
        var path = raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var cleaned: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || forbiddenSegments.contains(trimmed.lowercased()) {
                return nil
            }
            cleaned.append(trimmed)
        }
        return cleaned.joined(separator: "/")
    }

    static func virtualPath(for note: Note) -> String {
        if !note.path.isEmpty, let clean = sanitizeVaultPath(note.path) {
            return clean
        }
        let folder = note.notebook.isEmpty ? "笔记" : note.notebook
        return "\(folder)/\(note.displayTitle).md"
    }

    static func fileRefDictionary(for note: Note) -> [String: Any] {
        let path = virtualPath(for: note)
        let name = (path as NSString).lastPathComponent
        let ctime = Int64(note.createdAt.timeIntervalSince1970 * 1000)
        let mtime = Int64(note.updatedAt.timeIntervalSince1970 * 1000)
        return [
            "id": note.id,
            "vaultId": note.vaultID,
            "projectId": "",
            "path": path,
            "name": name,
            "extension": (name as NSString).pathExtension.isEmpty ? "md" : (name as NSString).pathExtension,
            "kind": "file",
            "size": note.content.utf8.count,
            "ctime": ctime,
            "mtime": mtime,
            "title": note.displayTitle
        ]
    }
}

@MainActor
enum LexiVaultBridge {
    private static func resolveVaultId(_ requested: String?, model: AppModel) throws -> String {
        let target = (requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = target.isEmpty ? model.activeVaultID : target
        guard scope == model.activeVaultID, model.vault(scope) != nil else {
            throw PluginHostError(PluginErrorCode.vaultForbidden, "禁止访问未授权工作区：\(scope)")
        }
        return scope
    }

    private static func activeNotes(in vaultId: String, model: AppModel) -> [Note] {
        model.notes.filter { !$0.isTrashed && $0.vaultID == vaultId }
    }

    static func filesListJson(model: AppModel) -> String {
        let refs = activeNotes(in: model.activeVaultID, model: model).map { LexiPathValidator.fileRefDictionary(for: $0) }
        guard let data = try? JSONSerialization.data(withJSONObject: refs),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    static func activeFileJson(model: AppModel) -> String {
        guard let note = model.currentNote, note.vaultID == model.activeVaultID else {
            return "null"
        }
        let dict = LexiPathValidator.fileRefDictionary(for: note)
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return str
    }

    static func listMarkdown(vaultId: String?, model: AppModel) throws -> [[String: Any]] {
        let scope = try resolveVaultId(vaultId, model: model)
        return activeNotes(in: scope, model: model).map { LexiPathValidator.fileRefDictionary(for: $0) }
    }

    static func getByPath(vaultId: String?, path rawPath: String, model: AppModel) throws -> [String: Any]? {
        let scope = try resolveVaultId(vaultId, model: model)
        guard let target = LexiPathValidator.sanitizeVaultPath(rawPath) else {
            throw PluginHostError(PluginErrorCode.invalidPath, "路径格式无效：\(rawPath)")
        }
        guard let found = activeNotes(in: scope, model: model).first(where: {
            LexiPathValidator.virtualPath(for: $0).caseInsensitiveCompare(target) == .orderedSame
        }) else {
            return nil
        }
        return LexiPathValidator.fileRefDictionary(for: found)
    }

    static func getById(vaultId: String?, fileId: String, model: AppModel) throws -> [String: Any]? {
        let scope = try resolveVaultId(vaultId, model: model)
        guard let found = activeNotes(in: scope, model: model).first(where: { $0.id == fileId }) else {
            return nil
        }
        return LexiPathValidator.fileRefDictionary(for: found)
    }

    static func readText(vaultId: String?, fileId: String, model: AppModel) throws -> String {
        let scope = try resolveVaultId(vaultId, model: model)
        guard let note = activeNotes(in: scope, model: model).first(where: { $0.id == fileId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
        }
        return note.content
    }

    static func createText(vaultId: String?, path rawPath: String, content: String, model: AppModel) throws -> [String: Any] {
        let scope = try resolveVaultId(vaultId, model: model)
        guard var clean = LexiPathValidator.sanitizeVaultPath(rawPath) else {
            throw PluginHostError(PluginErrorCode.invalidPath, "文件路径不合法：\(rawPath)")
        }
        if !clean.lowercased().hasSuffix(".md") {
            clean += ".md"
        }
        guard content.utf8.count <= PluginLimits.maxFileBytes else {
            throw PluginHostError(PluginErrorCode.quotaExceeded, "写入内容超过 5 MB 上限")
        }
        if activeNotes(in: scope, model: model).contains(where: {
            LexiPathValidator.virtualPath(for: $0).caseInsensitiveCompare(clean) == .orderedSame
        }) {
            throw PluginHostError(PluginErrorCode.pathExists, "文件已存在：\(clean)")
        }

        let parts = clean.split(separator: "/").map(String.init)
        let notebook = parts.count > 1 ? parts.dropLast().joined(separator: "/") : model.settings.newNoteNotebook
        let fileName = parts.last ?? "未命名"
        let title = fileName.lowercased().hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
        let created = model.createNote(title: title, content: content, type: .markdown, notebook: notebook, open: false)
        return LexiPathValidator.fileRefDictionary(for: created)
    }

    static func writeText(vaultId: String?, fileId: String, content: String, expectedUpdatedAt: Int64, model: AppModel) throws -> [String: Any] {
        let scope = try resolveVaultId(vaultId, model: model)
        guard let note = activeNotes(in: scope, model: model).first(where: { $0.id == fileId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
        }
        guard content.utf8.count <= PluginLimits.maxFileBytes else {
            throw PluginHostError(PluginErrorCode.quotaExceeded, "写入内容超过 5 MB 上限")
        }
        let currentMs = Int64(note.updatedAt.timeIntervalSince1970 * 1000)
        if expectedUpdatedAt > 0 && abs(currentMs - expectedUpdatedAt) > 1000 {
            throw PluginHostError(PluginErrorCode.conflict, "文件在写入前已被修改，请刷新后重试")
        }
        model.updateNoteContent(note.id, content: content)
        _ = model.saveNoteNow(note.id)
        if let updated = model.note(note.id) {
            return LexiPathValidator.fileRefDictionary(for: updated)
        }
        return LexiPathValidator.fileRefDictionary(for: note)
    }

    static func renameText(vaultId: String?, fileId: String, newPath rawPath: String, model: AppModel) throws -> [String: Any] {
        let scope = try resolveVaultId(vaultId, model: model)
        guard let note = activeNotes(in: scope, model: model).first(where: { $0.id == fileId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
        }
        guard var clean = LexiPathValidator.sanitizeVaultPath(rawPath) else {
            throw PluginHostError(PluginErrorCode.invalidPath, "目标路径无效：\(rawPath)")
        }
        if !clean.lowercased().hasSuffix(".md") { clean += ".md" }
        if activeNotes(in: scope, model: model).contains(where: {
            $0.id != fileId && LexiPathValidator.virtualPath(for: $0).caseInsensitiveCompare(clean) == .orderedSame
        }) {
            throw PluginHostError(PluginErrorCode.pathExists, "目标路径已存在：\(clean)")
        }
        let parts = clean.split(separator: "/").map(String.init)
        let notebook = parts.count > 1 ? parts.dropLast().joined(separator: "/") : note.notebook
        let fileName = parts.last ?? note.displayTitle
        let newTitle = fileName.lowercased().hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
        if notebook != note.notebook {
            model.updateNoteNotebook(note.id, notebook: notebook)
        }
        model.updateNoteTitle(note.id, title: newTitle)
        if let updated = model.note(note.id) {
            return LexiPathValidator.fileRefDictionary(for: updated)
        }
        return LexiPathValidator.fileRefDictionary(for: note)
    }

    static func deleteText(vaultId: String?, fileId: String, model: AppModel) throws -> Bool {
        let scope = try resolveVaultId(vaultId, model: model)
        guard activeNotes(in: scope, model: model).contains(where: { $0.id == fileId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
        }
        model.trashNote(fileId)
        return true
    }

    static func openFile(vaultId: String?, fileId: String?, path: String?, model: AppModel) throws -> Bool {
        let scope = try resolveVaultId(vaultId, model: model)
        if let fileId, !fileId.isEmpty {
            guard activeNotes(in: scope, model: model).contains(where: { $0.id == fileId }) else {
                throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
            }
            model.openNote(fileId)
            return true
        }
        if let path, !path.isEmpty {
            guard let ref = try getByPath(vaultId: scope, path: path, model: model),
                  let resolvedId = ref["id"] as? String else {
                throw PluginHostError(PluginErrorCode.notFound, "找不到路径对应的笔记：\(path)")
            }
            model.openNote(resolvedId)
            return true
        }
        throw PluginHostError(PluginErrorCode.invalidArgument, "openFile 需要 fileId 或 path")
    }
}

// MARK: - Metadata Adapter

@MainActor
enum LexiMetadataBridge {
    static func metadataDictionary(for note: Note) -> [String: Any] {
        let headings: [[String: Any]] = note.outline.map { h in
            [
                "heading": h.title,
                "level": h.level,
                "line": h.line
            ]
        }
        let links: [[String: Any]] = note.wikiLinks.map { link in
            [
                "link": link.target,
                "original": "[[\(link.target)]]",
                "displayText": link.label
            ]
        }
        let tags: [[String: Any]] = note.tags.map { tag in
            ["tag": tag.hasPrefix("#") ? tag : "#\(tag)"]
        }
        var frontmatter: [String: Any] = [
            "title": note.displayTitle,
            "notebook": note.notebook
        ]
        if !note.tags.isEmpty {
            frontmatter["tags"] = note.tags
        }
        for prop in note.properties {
            frontmatter[prop.key] = prop.value
        }
        return [
            "headings": headings,
            "links": links,
            "embeds": [],
            "tags": tags,
            "frontmatter": frontmatter
        ]
    }
}

// MARK: - Live Editor Bridge

@MainActor
final class LexiEditorBridge {
    static let shared = LexiEditorBridge()
    var isCurrentNoteReading: Bool = false
    private(set) var revisionCounter: Int = 1

    func bumpRevision() {
        revisionCounter += 1
    }

    func snapshotJson(model: AppModel) -> String {
        guard let dict = snapshotDictionary(model: model),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return str
    }

    func snapshotDictionary(model: AppModel) -> [String: Any]? {
        guard let note = model.currentNote else { return nil }
        let content = EditorController.active?.textView?.string ?? note.content
        let sel = EditorController.active?.selectedRange() ?? NSRange(location: 0, length: 0)
        let cursor = lineAndColumn(in: content, utf16Offset: sel.location)
        return [
            "fileId": note.id,
            "vaultId": note.vaultID,
            "content": content,
            "selection": ["from": sel.location, "to": sel.location + sel.length],
            "cursor": ["line": cursor.line, "ch": cursor.ch],
            "revision": revisionCounter,
            "version": revisionCounter,
            "readOnly": isCurrentNoteReading,
            "dirty": model.saveState == .unsaved || model.saveState == .saving
        ]
    }

    func replaceSelection(model: AppModel, text: String, from: Int?, to: Int?, expectedRevision: Int?) throws -> [String: Any] {
        guard let note = model.currentNote else {
            throw PluginHostError(PluginErrorCode.notFound, "当前没有打开的笔记")
        }
        if isCurrentNoteReading {
            throw PluginHostError(PluginErrorCode.editorReadonly, "当前处于阅读视图，无法修改正文")
        }
        if let expectedRevision, expectedRevision > 0, expectedRevision != revisionCounter {
            throw PluginHostError(PluginErrorCode.editorConflict, "编辑器内容已变化，请刷新后再试")
        }
        if let controller = EditorController.active, let tv = controller.textView {
            let current = tv.string as NSString
            let range: NSRange
            if let from, let to, from >= 0, to >= from, to <= current.length {
                range = NSRange(location: from, length: to - from)
            } else {
                range = tv.selectedRange()
            }
            controller.replace(range: range, with: text)
            let updated = tv.string
            model.updateNoteContent(note.id, content: updated)
            bumpRevision()
            return ["revision": revisionCounter, "version": revisionCounter, "content": updated]
        }
        // Fallback when TextView isn't mounted (e.g. headless test)
        let ns = note.content as NSString
        let safeFrom = max(0, min(from ?? ns.length, ns.length))
        let safeTo = max(safeFrom, min(to ?? safeFrom, ns.length))
        let updated = ns.replacingCharacters(in: NSRange(location: safeFrom, length: safeTo - safeFrom), with: text)
        model.updateNoteContent(note.id, content: updated)
        bumpRevision()
        return ["revision": revisionCounter, "version": revisionCounter, "content": updated]
    }

    func replaceAll(model: AppModel, content: String, expectedRevision: Int?) throws -> [String: Any] {
        guard let note = model.currentNote else {
            throw PluginHostError(PluginErrorCode.notFound, "当前没有打开的笔记")
        }
        if isCurrentNoteReading {
            throw PluginHostError(PluginErrorCode.editorReadonly, "当前处于阅读视图，无法修改正文")
        }
        if let expectedRevision, expectedRevision > 0, expectedRevision != revisionCounter {
            throw PluginHostError(PluginErrorCode.editorConflict, "编辑器内容已变化，请刷新后再试")
        }
        if let controller = EditorController.active, let tv = controller.textView {
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            controller.replace(range: full, with: content)
        }
        model.updateNoteContent(note.id, content: content)
        _ = model.saveNoteNow(note.id)
        bumpRevision()
        return ["revision": revisionCounter, "version": revisionCounter, "content": content]
    }

    private func lineAndColumn(in text: String, utf16Offset: Int) -> (line: Int, ch: Int) {
        let ns = text as NSString
        let safe = max(0, min(utf16Offset, ns.length))
        let prefix = ns.substring(to: safe)
        let lines = prefix.components(separatedBy: "\n")
        return (max(0, lines.count - 1), (lines.last ?? "").utf16.count)
    }
}

// MARK: - Command & View Registries

@MainActor
final class PluginCommandRegistry: ObservableObject {
    static let shared = PluginCommandRegistry()
    @Published private(set) var commands: [PluginRegisteredCommand] = []

    func register(pluginId: String, pluginName: String, commandId: String, name: String, hotkeys: [String]) {
        let qualified = "\(pluginId):\(commandId)"
        let item = PluginRegisteredCommand(
            pluginId: pluginId,
            pluginName: pluginName,
            commandId: commandId,
            qualifiedId: qualified,
            name: name,
            hotkeys: hotkeys
        )
        if let idx = commands.firstIndex(where: { $0.qualifiedId == qualified }) {
            commands[idx] = item
        } else {
            commands.append(item)
        }
    }

    func unregister(qualifiedId: String) {
        commands.removeAll { $0.qualifiedId == qualifiedId }
    }

    func clear(pluginId: String) {
        commands.removeAll { $0.pluginId == pluginId }
    }

    func clearAll() {
        commands.removeAll()
    }
}

@MainActor
final class PluginViewRegistry: ObservableObject {
    static let shared = PluginViewRegistry()
    @Published private(set) var views: [PluginRegisteredView] = []
    @Published private(set) var ribbonActions: [PluginRibbonAction] = []

    func register(pluginId: String, pluginName: String, viewId: String, title: String, icon: String?, location: String?, entry: String?) {
        let qualified = "\(pluginId):\(viewId)"
        let item = PluginRegisteredView(
            pluginId: pluginId,
            pluginName: pluginName,
            viewId: viewId,
            qualifiedId: qualified,
            title: title.isEmpty ? pluginName : title,
            icon: Self.sfSymbol(from: icon ?? ""),
            location: location ?? "right-sidebar",
            entry: entry
        )
        if let idx = views.firstIndex(where: { $0.qualifiedId == qualified }) {
            views[idx] = item
        } else {
            views.append(item)
        }
    }

    func unregister(qualifiedId: String) {
        views.removeAll { $0.qualifiedId == qualifiedId }
    }

    func registerRibbon(pluginId: String, pluginName: String, actionId: String, title: String, icon: String?) {
        let id = "\(pluginId):ribbon:\(actionId)"
        let item = PluginRibbonAction(
            id: id,
            pluginId: pluginId,
            pluginName: pluginName,
            title: title.isEmpty ? pluginName : title,
            icon: Self.sfSymbol(from: icon ?? ""),
            actionId: actionId
        )
        if let idx = ribbonActions.firstIndex(where: { $0.id == id }) {
            ribbonActions[idx] = item
        } else {
            ribbonActions.append(item)
        }
    }

    func clear(pluginId: String) {
        views.removeAll { $0.pluginId == pluginId }
        ribbonActions.removeAll { $0.pluginId == pluginId }
    }

    func clearAll() {
        views.removeAll()
        ribbonActions.removeAll()
    }

    static func sfSymbol(from raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "", "spark", "sparkles", "ai": return "sparkles"
        case "star", "harness": return "star"
        case "puzzle", "plugin", "blocks": return "puzzlepiece.extension"
        case "bot", "message", "chat", "bubble": return "bubble.left.and.bubble.right"
        case "search": return "magnifyingglass"
        case "graph", "network": return "point.3.connected.trianglepath.dotted"
        case "calendar", "date": return "calendar"
        case "book", "doc", "note", "file-text": return "doc.text"
        case "folder": return "folder"
        case "settings", "gear": return "gearshape"
        case "dice": return "dice"
        case "bookmark": return "bookmark"
        default:
            return "square.stack.3d.up"
        }
    }
}
