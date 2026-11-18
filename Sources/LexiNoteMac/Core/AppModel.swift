import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - View models

struct NotebookGroup: Identifiable {
    let name: String
    let notes: [Note]
    var id: String { name }
}

struct QuickResult: Identifiable {
    enum Kind { case note, map, canvas, create }
    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
    let symbol: String
    var score: Int = 0
}

struct GraphNode: Identifiable, Hashable {
    let id: String
    let title: String
    let notebook: String
    let colorTag: NoteColorTag
    var degree: Int
}

struct GraphEdge: Identifiable, Hashable {
    let id: String
    let source: String
    let target: String
}

struct GraphData {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []
}

struct JumpRequest: Equatable {
    let noteID: String
    let line: Int
    let headingID: String
    let token: UUID
}

struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let message: String
    let symbol: String
}

enum SaveState: Equatable {
    case saved(Date)
    case saving
    case unsaved
    case failed(String)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var formattedTime: String? {
        if case .saved(let date) = self {
            return Self.timeFormatter.string(from: date)
        }
        return nil
    }

    var label: String {
        switch self {
        case .saved(let date):
            return "已保存到本机 \(Self.timeFormatter.string(from: date))"
        case .saving:
            return "正在自动保存…"
        case .unsaved:
            return "尚未保存 · ⌘S"
        case .failed:
            return "保存失败 · 点击重试"
        }
    }
}

enum RailItem: String, CaseIterable, Identifiable {
    case library, search, graph, templates, links, trash
    var id: String { rawValue }
    var label: String {
        switch self {
        case .library: return "知识库"
        case .search: return "搜索"
        case .graph: return "关系图谱"
        case .templates: return "模板"
        case .links: return "关系"
        case .trash: return "回收站"
        }
    }
    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .search: return "magnifyingglass"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .templates: return "doc.on.doc"
        case .links: return "link"
        case .trash: return "trash"
        }
    }
}

enum PaletteMode: String {
    case commands, quickSwitch
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let library: LibraryStore
    let isPrimaryWindow: Bool

    var storageRoot: URL { library.storageRoot }
    var isSnapshot: Bool { library.isSnapshot }

    var vaults: [Vault] {
        get { library.vaults }
        set { library.vaults = newValue }
    }
    var notes: [Note] {
        get { library.notes }
        set { library.notes = newValue }
    }
    var maps: [MindMap] {
        get { library.maps }
        set { library.maps = newValue }
    }
    var canvases: [CanvasBoard] {
        get { library.canvases }
        set { library.canvases = newValue }
    }
    var saveState: SaveState {
        get { library.saveState }
        set { library.saveState = newValue }
    }

    @Published var openTabs: [WorkspaceTab] = []
    @Published var selectedTabID: String = ""
    @Published var activeVaultID: String = "default-vault"

    @Published var searchText: String = ""
    @Published var favoritesOnly: Bool = false
    @Published var unconnectedOnly: Bool = false
    @Published var collapsedNotebooks: Set<String> = []
    @Published var toast: ToastMessage?
    @Published var paletteVisible: Bool = false
    @Published var paletteMode: PaletteMode = .commands
    @Published var templatesVisible: Bool = false
    @Published var welcomeVisible: Bool = false
    @Published var settingsVisible: Bool = false
    @Published var trashVisible: Bool = false
    @Published var workspacePromptVault: Vault?
    @Published var pendingJump: JumpRequest?
    @Published var graphFocusNoteID: String?
    @Published var quickLookTab: WorkspaceTab?
    @Published var dataStatusMessage: String = ""
    @Published var historyVisible: Bool = false
    @Published var historyTargetNoteID: String?
    @Published var historyRevisionTick: Int = 0
    /// Used by snapshot rendering and previews to force a presentation for the next editor identity.
    @Published var presentationOverride: EditorPresentation?

    let windowID = UUID()
    let plugins: PluginManager
    var onOpenNewWindow: ((String) -> Void)?

    private var sessionLoaded = false
    private let initialVaultID: String?
    private var paletteTimer: Timer?
    private var libraryCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var windowNoteHashes: [String: String] = [:]
    private var pendingExternalOpenURLs: [URL] = []

    init(settings: SettingsStore,
         storageRoot: URL? = nil,
         inMemory: Bool = false,
         seedDemo: Bool = true,
         sharedLibrary: LibraryStore? = nil,
         initialVaultID: String? = nil,
         isPrimaryWindow: Bool = true,
         plugins: PluginManager? = nil) {
        self.settings = settings
        self.library = sharedLibrary ?? LibraryStore(storageRoot: storageRoot, inMemory: inMemory, seedDemo: seedDemo)
        self.initialVaultID = initialVaultID
        self.isPrimaryWindow = isPrimaryWindow
        self.plugins = plugins ?? (inMemory ? PluginManager(ephemeral: true) : PluginManager.shared)
        self.library.historyPolicy = settings.historyPolicy

        let resolvedVaultID: String
        if let requested = initialVaultID, library.vault(requested) != nil {
            resolvedVaultID = requested
        } else {
            resolvedVaultID = library.defaultVaultID
        }
        self.activeVaultID = resolvedVaultID
        self.settings.bind(to: resolvedVaultID)

        for note in self.library.notes {
            self.windowNoteHashes[note.id] = NoteHistoryHash.computeNoteHash(note)
        }

        self.libraryCancellable = self.library.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.settingsCancellable = Publishers.CombineLatest3(
            self.settings.$historyMaxAgeDays,
            self.settings.$historyMaxCountPerNote,
            self.settings.$historyMaxTotalMB
        ).sink { [weak self] days, count, mb in
            guard let self else { return }
            self.library.historyPolicy = SettingsStore.historyPolicy(days: days, count: count, mb: mb)
        }
        if !inMemory {
            self.plugins.attach(model: self)
        }
    }

    deinit {
        paletteTimer?.invalidate()
    }

    static func defaultStorageRoot() -> URL {
        LibraryStore.defaultStorageRoot()
    }

    func vaultFolder(_ vault: Vault) -> URL {
        library.vaultFolder(vault)
    }

    // MARK: Workspace switching & multi-window prompts

    private func setActiveVault(_ vaultID: String) {
        guard library.vault(vaultID) != nil else { return }
        activeVaultID = vaultID
        settings.bind(to: vaultID)
        if !isSnapshot {
            plugins.switchWorkspace(model: self, vaultID: vaultID)
        }
    }

    func requestOpenWorkspace(_ vault: Vault) {
        switch settings.workspaceOpenMode {
        case .ask:
            workspacePromptVault = vault
        case .current:
            openWorkspaceInCurrentWindow(vault.id)
        case .new:
            openWorkspaceInNewWindow(vault.id)
        }
    }

    func confirmOpenWorkspace(_ vault: Vault, mode: WorkspaceOpenMode, remember: Bool) {
        workspacePromptVault = nil
        if remember, mode == .current || mode == .new {
            settings.workspaceOpenMode = mode
        }
        switch mode {
        case .ask:
            break
        case .current:
            openWorkspaceInCurrentWindow(vault.id)
        case .new:
            openWorkspaceInNewWindow(vault.id)
        }
    }

    func openWorkspaceInCurrentWindow(_ vaultID: String) {
        guard let targetVault = vault(vaultID) else { return }
        if activeVaultID == vaultID {
            searchText = ""
            showToast("当前已在「\(targetVault.name)」", symbol: "folder")
            return
        }

        saveSession()
        setActiveVault(vaultID)
        searchText = ""
        favoritesOnly = false
        collapsedNotebooks = []

        if settings.restoreSession,
           let session = library.readSession(),
           let saved = session.vaultSessions?[vaultID] {
            let validTabs = saved.tabs.filter { tabExists($0) && tabBelongsToVault($0, vaultID: vaultID) }
            if !validTabs.isEmpty {
                openTabs = validTabs
                if let selected = saved.selectedID, validTabs.contains(where: { $0.id == selected }) {
                    selectedTabID = selected
                } else {
                    selectedTabID = validTabs.first?.id ?? ""
                }
                saveSession()
                showToast("已切换到「\(targetVault.name)」", symbol: "folder")
                return
            }
        }

        openTabs = []
        selectedTabID = ""
        if let preferred = notes.filter({ !$0.isTrashed && $0.vaultID == vaultID })
            .sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            openNote(preferred.id)
        } else {
            saveSession()
        }
        showToast("已切换到「\(targetVault.name)」", symbol: "folder")
    }

    func openWorkspaceInNewWindow(_ vaultID: String) {
        guard let targetVault = vault(vaultID) else { return }
        guard let opener = onOpenNewWindow else {
            showToast("无法打开新窗口", symbol: "exclamationmark.triangle")
            return
        }
        opener(targetVault.id)
        showToast("已在新窗口打开「\(targetVault.name)」", symbol: "macwindow.badge.plus")
    }

    @discardableResult
    func createVault(name: String, detail: String = "本地优先的知识库", openInCurrent: Bool = true) -> Vault {
        let vault = library.createVault(name: name, detail: detail)
        if openInCurrent {
            openWorkspaceInCurrentWindow(vault.id)
        }
        showToast("已创建工作区「\(vault.name)」", symbol: "folder.badge.plus")
        return vault
    }

    // MARK: Session

    func bootstrapSession() {
        guard !sessionLoaded else { return }
        sessionLoaded = true
        defer { flushPendingExternalOpensAndWarnings() }

        let session = library.readSession()
        if let requested = initialVaultID, library.vault(requested) != nil {
            setActiveVault(requested)
            if settings.restoreSession, let saved = session?.vaultSessions?[requested] {
                let tabs = saved.tabs.filter { tabExists($0) && tabBelongsToVault($0, vaultID: requested) }
                if !tabs.isEmpty {
                    openTabs = tabs
                    if let selected = saved.selectedID, tabs.contains(where: { $0.id == selected }) {
                        selectedTabID = selected
                    } else {
                        selectedTabID = tabs.first?.id ?? ""
                    }
                    return
                }
            }
            if let preferred = notes.filter({ !$0.isTrashed && $0.vaultID == requested })
                .sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                openNote(preferred.id)
            }
            if settings.showWelcome {
                welcomeVisible = true
            }
            return
        }

        if let session {
            let targetVault = session.activeVaultID.flatMap { vault($0)?.id } ?? activeVaultID
            setActiveVault(targetVault)
            if settings.restoreSession {
                let candidateTabs = session.vaultSessions?[targetVault]?.tabs ?? session.tabs ?? []
                let candidateSelected = session.vaultSessions?[targetVault]?.selectedID ?? session.selectedID
                let tabs = candidateTabs.filter { tabExists($0) && tabBelongsToVault($0, vaultID: targetVault) }
                if !tabs.isEmpty {
                    openTabs = tabs
                    if let selected = candidateSelected, tabs.contains(where: { $0.id == selected }) {
                        selectedTabID = selected
                    } else {
                        selectedTabID = tabs.first?.id ?? ""
                    }
                    if let selectedNote = currentNote {
                        setActiveVault(selectedNote.vaultID)
                    }
                    return
                }
            }
        }

        let preferred = notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID }
            .sorted { $0.updatedAt > $1.updatedAt }.first
            ?? notes.filter { !$0.isTrashed }.sorted { $0.updatedAt > $1.updatedAt }.first
        if let preferred {
            openNote(preferred.id)
        } else if let first = notes.first {
            openNote(first.id)
        }
        if settings.showWelcome {
            welcomeVisible = true
        }
    }

    func saveSession() {
        guard !isSnapshot, sessionLoaded else { return }
        library.writeSession(tabs: openTabs,
                             selectedID: selectedTabID,
                             activeVaultID: activeVaultID,
                             primaryWindow: isPrimaryWindow)
    }

    // MARK: Autosave

    func flushDirty() {
        library.flushDirty()
    }

    func flushAll() {
        library.flushAllNotes(fallbackNotebook: settings.newNoteNotebook)
        saveSession()
    }

    func flushCrashWalNow() {
        library.flushCrashWalNow()
    }

    private func scheduleSave(_ id: String) {
        library.scheduleSave(id,
                             autoSave: settings.autoSave,
                             fallbackNotebook: settings.newNoteNotebook,
                             windowID: windowID)
    }

    @discardableResult
    func saveNoteNow(_ id: String) -> Bool {
        if let current = note(id),
           let conflict = library.checkConcurrentWindowEdit(
               noteID: id,
               windowID: windowID,
               expectedBaseHash: windowNoteHashes[id],
               proposedTitle: current.title,
               proposedContent: current.content,
               proposedTags: current.tags,
               proposedProperties: current.properties
           ) {
            _ = conflict
            showToast("检测到其他窗口并发修改，已保留双方版本等待处理", symbol: "exclamationmark.triangle")
            historyRevisionTick &+= 1
            return false
        }
        let ok = library.saveNoteNow(id, fallbackNotebook: settings.newNoteNotebook)
        if ok {
            syncWindowHash(for: id)
            historyRevisionTick &+= 1
        }
        return ok
    }

    func syncWindowHash(for id: String) {
        if let hash = library.noteHash(for: id) {
            windowNoteHashes[id] = hash
        }
    }

    func acknowledgeExternalEdit(for id: String) {
        syncWindowHash(for: id)
    }

    func hasUnsavedDirty(_ id: String) -> Bool {
        library.hasDirtyNote(id)
    }

    func effectiveSaveState(for noteID: String) -> SaveState {
        if case .failed = saveState { return saveState }
        if saveState == .saving, library.hasDirtyNote(noteID) { return .saving }
        if library.hasDirtyNote(noteID) { return .unsaved }
        if let noteSaved = library.noteLastSavedDate(for: noteID) {
            return .saved(noteSaved)
        }
        if case .saved(let date) = saveState {
            return .saved(date)
        }
        return .saved(library.lastSavedDate)
    }

    @discardableResult
    func saveNoteWithFeedback(_ id: String) -> Bool {
        let ok = saveNoteNow(id)
        if ok {
            let state = effectiveSaveState(for: id)
            showToast(state.label, symbol: "checkmark.circle")
        } else if case .failed(let msg) = saveState {
            showToast(msg, symbol: "exclamationmark.triangle")
        }
        return ok
    }

    // MARK: Lookups

    func vault(_ id: String) -> Vault? { library.vault(id) }
    func note(_ id: String) -> Note? { notes.first { $0.id == id } }
    func map(_ id: String) -> MindMap? { maps.first { $0.id == id } }
    func canvas(_ id: String) -> CanvasBoard? { canvases.first { $0.id == id } }

    var currentTab: WorkspaceTab? {
        openTabs.first { $0.id == selectedTabID }
    }

    var currentNote: Note? {
        guard let tab = currentTab, tab.kind == .note else { return nil }
        return note(tab.refID)
    }

    var currentMap: MindMap? {
        guard let tab = currentTab, tab.kind == .map else { return nil }
        return map(tab.refID)
    }

    var currentCanvas: CanvasBoard? {
        guard let tab = currentTab, tab.kind == .canvas else { return nil }
        return canvas(tab.refID)
    }

    var activeVault: Vault? { vault(activeVaultID) ?? vaults.first }

    func accessDate(for note: Note) -> Date {
        library.accessDate(for: note)
    }

    var visibleNotes: [Note] {
        let connected = unconnectedOnly ? connectedNoteIDs() : []
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = notes.filter { note in
            guard !note.isTrashed, note.vaultID == activeVaultID else { return false }
            if favoritesOnly && !note.favorite { return false }
            if unconnectedOnly && connected.contains(note.id) { return false }
            if !trimmedSearch.isEmpty {
                return NoteSearch.matches(note, query: trimmedSearch)
            }
            return true
        }
        return NoteSearch.sortNotes(filtered,
                                    mode: settings.sidebarSortMode,
                                    accessedAt: library.noteAccessedAt,
                                    pinnedFirst: true)
    }

    var notebookGroups: [NotebookGroup] {
        let grouped = Dictionary(grouping: visibleNotes, by: { $0.notebook })
        return grouped.keys.sorted { first, second in
            first.localizedStandardCompare(second) == .orderedAscending
        }.map { name in
            NotebookGroup(name: name, notes: grouped[name] ?? [])
        }
    }

    var trashedNotes: [Note] {
        notes.filter { $0.isTrashed && $0.vaultID == activeVaultID }
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    var activeVaultNoteCount: Int {
        notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID }.count
    }

    var unconnectedNoteCount: Int {
        unconnectedNotes().count
    }

    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in notes where !note.isTrashed && note.vaultID == activeVaultID {
            for tag in note.tags { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, count: $0.value) }.sorted { $0.tag < $1.tag }
    }

    func recentNotes(limit: Int = 8) -> [Note] {
        let active = notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID }
        return Array(
            NoteSearch.sortNotes(active,
                                 mode: .accessed,
                                 accessedAt: library.noteAccessedAt,
                                 pinnedFirst: false)
                .prefix(limit)
        )
    }

    // MARK: Tabs

    func tabExists(_ tab: WorkspaceTab) -> Bool {
        switch tab.kind {
        case .note: return note(tab.refID) != nil
        case .map: return map(tab.refID) != nil
        case .canvas: return canvas(tab.refID) != nil
        case .graph: return true
        case .trash: return false
        }
    }

    func tabBelongsToVault(_ tab: WorkspaceTab, vaultID: String) -> Bool {
        switch tab.kind {
        case .note: return note(tab.refID)?.vaultID == vaultID
        case .map: return map(tab.refID)?.vaultID == vaultID
        case .canvas: return canvas(tab.refID)?.vaultID == vaultID
        case .graph: return true
        case .trash: return false
        }
    }

    func openNote(_ id: String, revealSidebar: Bool = true) {
        guard let note = note(id) else {
            showToast("无法打开笔记：目标文档不存在或已被移除", symbol: "exclamationmark.triangle")
            return
        }
        if note.vaultID != activeVaultID {
            setActiveVault(note.vaultID)
        }
        syncWindowHash(for: id)
        library.syncBaseFromNote(note, windowID: windowID)
        library.recordNoteOpened(id)
        let tab = WorkspaceTab(kind: .note, refID: id)
        if !openTabs.contains(tab) { openTabs.append(tab) }
        selectedTabID = tab.id
        saveSession()
        plugins.notifyActiveLeafChanged()
        if note.isTrashed {
            showToast("已打开回收站中的笔记「\(note.displayTitle)」", symbol: "trash")
        }
    }

    func openMap(_ id: String) {
        guard let map = map(id) else { return }
        if map.vaultID != activeVaultID {
            setActiveVault(map.vaultID)
        }
        let tab = WorkspaceTab(kind: .map, refID: id)
        if !openTabs.contains(tab) { openTabs.append(tab) }
        selectedTabID = tab.id
        saveSession()
    }

    func openCanvas(_ id: String) {
        guard let board = canvas(id) else { return }
        if board.vaultID != activeVaultID {
            setActiveVault(board.vaultID)
        }
        let tab = WorkspaceTab(kind: .canvas, refID: id)
        if !openTabs.contains(tab) { openTabs.append(tab) }
        selectedTabID = tab.id
        saveSession()
    }

    func openGraph(focus: String? = nil) {
        graphFocusNoteID = focus
        let tab = WorkspaceTab(kind: .graph, refID: "all")
        if !openTabs.contains(tab) { openTabs.append(tab) }
        selectedTabID = tab.id
        searchText = ""
        saveSession()
    }

    func presentSettings() {
        trashVisible = false
        settingsVisible = true
    }

    func openTrash() {
        searchText = ""
        settingsVisible = false
        trashVisible = true
    }

    func selectTab(_ id: String) {
        guard openTabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        if let tab = openTabs.first(where: { $0.id == id }), tab.kind == .note {
            syncWindowHash(for: tab.refID)
        }
        saveSession()
        plugins.notifyActiveLeafChanged()
    }

    func closeAllTabs() {
        flushDirty()
        openTabs.removeAll()
        selectedTabID = ""
        saveSession()
        plugins.notifyActiveLeafChanged()
    }

    func closeTab(_ id: String) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        if let tab = openTabs.first(where: { $0.id == id }), tab.kind == .note {
            _ = saveNoteNow(tab.refID)
        }
        let wasSelected = selectedTabID == id
        openTabs.remove(at: index)
        if wasSelected {
            if openTabs.isEmpty {
                selectedTabID = ""
            } else {
                let next = min(index, openTabs.count - 1)
                selectedTabID = openTabs[next].id
            }
        }
        saveSession()
        plugins.notifyActiveLeafChanged()
    }

    func closeOtherTabs(keeping id: String) {
        openTabs = openTabs.filter { $0.id == id }
        selectedTabID = id
        saveSession()
    }

    func closeTabsToRight(of id: String) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs = Array(openTabs.prefix(index + 1))
        selectedTabID = id
        saveSession()
    }

    func nextTab(offset: Int) {
        guard !openTabs.isEmpty,
              let index = openTabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = (index + offset + openTabs.count) % openTabs.count
        selectedTabID = openTabs[next].id
        saveSession()
    }

    func tabTitle(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .note: return note(tab.refID)?.displayTitle ?? "无标题笔记"
        case .map: return map(tab.refID)?.title ?? "未命名导图"
        case .canvas: return canvas(tab.refID)?.title ?? "未命名白板"
        case .graph: return "关系图谱"
        case .trash: return "回收站"
        }
    }

    func tabSymbol(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .note:
            guard let note = note(tab.refID) else { return "doc.text" }
            return note.type == .quick ? "bolt" : "doc.text"
        case .map: return "point.3.filled.connected.trianglepath.dotted"
        case .canvas: return "rectangle.3.group"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .trash: return "trash"
        }
    }

    // MARK: Notes CRUD

    @discardableResult
    func createNote(title: String, content: String = "", type: NoteKind = .markdown,
                    notebook: String? = nil, tags: [String] = [],
                    properties: [NoteProperty] = [], open: Bool = true) -> Note {
        let note = Note(vaultID: activeVaultID,
                        notebook: notebook ?? settings.newNoteNotebook,
                        type: type,
                        level: type == .quick ? .simple : .study,
                        title: title.isEmpty ? "无标题笔记" : title,
                        content: content,
                        tags: tags,
                        properties: properties)
        notes.insert(note, at: 0)
        _ = saveNoteNow(note.id)
        if open { openNote(note.id) }
        plugins.notifyVaultCreate(note: note)
        showToast("已新建「\(note.displayTitle)」", symbol: "doc.badge.plus")
        return note
    }

    private func applyNoteMutation(_ id: String,
                                   saveImmediately: Bool = false,
                                   mutate: (inout Note) -> Bool) -> Note? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        var candidate = notes[index]
        guard mutate(&candidate) else { return nil }

        if let conflict = library.checkConcurrentWindowEdit(
            noteID: id,
            windowID: windowID,
            expectedBaseHash: windowNoteHashes[id],
            proposedTitle: candidate.title,
            proposedContent: candidate.content,
            proposedTags: candidate.tags,
            proposedProperties: candidate.properties
        ) {
            _ = conflict
            showToast("检测到其他窗口并发修改「\(candidate.displayTitle)」，已保留双方版本", symbol: "exclamationmark.triangle")
            historyRevisionTick &+= 1
            return nil
        }

        candidate.updatedAt = Date()
        notes[index] = candidate
        windowNoteHashes[id] = NoteHistoryHash.computeNoteHash(candidate)
        scheduleSave(id)
        if saveImmediately {
            _ = saveNoteNow(id)
        }
        return notes.first(where: { $0.id == id }) ?? candidate
    }

    func updateNoteContent(_ id: String, content: String) {
        guard let updated = applyNoteMutation(id, mutate: { note in
            guard note.content != content else { return false }
            note.content = content
            return true
        }) else { return }
        plugins.notifyVaultModify(note: updated)
    }

    func updateNoteTitle(_ id: String, title: String, saveImmediately: Bool = true) {
        let oldPath = note(id)?.path ?? ""
        let clean = title.replacingOccurrences(of: "\n", with: " ")
        guard let updated = applyNoteMutation(id, saveImmediately: saveImmediately, mutate: { note in
            guard note.title != clean else { return false }
            note.title = clean
            return true
        }) else { return }
        if oldPath != updated.path {
            plugins.notifyVaultRename(note: updated, oldPath: oldPath)
        } else {
            plugins.notifyVaultModify(note: updated)
        }
    }

    func updateNoteTags(_ id: String, tags: [String]) {
        _ = applyNoteMutation(id, mutate: { note in
            guard note.tags != tags else { return false }
            note.tags = tags
            return true
        })
    }

    func updateNoteProperties(_ id: String, properties: [NoteProperty]) {
        _ = applyNoteMutation(id, mutate: { note in
            guard note.properties != properties else { return false }
            note.properties = properties
            return true
        })
    }

    func updateNoteNotebook(_ id: String, notebook: String) {
        guard !notebook.isEmpty else { return }
        _ = applyNoteMutation(id, saveImmediately: true, mutate: { note in
            guard note.notebook != notebook else { return false }
            note.notebook = notebook
            return true
        })
    }

    func toggleFavorite(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].favorite.toggle()
        scheduleSave(id)
        _ = saveNoteNow(id)
    }

    func togglePin(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].pinned.toggle()
        scheduleSave(id)
        _ = saveNoteNow(id)
    }

    func toggleTodo(noteID: String, line: Int) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var lines = notes[index].content.components(separatedBy: "\n")
        guard line >= 0, line < lines.count else { return }
        let trimmed = lines[line].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") {
            lines[line] = lines[line].replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            lines[line] = lines[line].replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        } else {
            return
        }
        notes[index].content = lines.joined(separator: "\n")
        notes[index].updatedAt = Date()
        scheduleSave(noteID)
    }

    func duplicateNote(_ id: String) {
        guard let source = note(id) else { return }
        _ = createNote(title: source.displayTitle + " 副本", content: source.content,
                       type: source.type, notebook: source.notebook,
                       tags: source.tags, properties: source.properties)
    }

    func moveNote(_ id: String, toNotebook notebook: String) {
        updateNoteNotebook(id, notebook: notebook)
        showToast("已移动到「\(notebook)」", symbol: "folder")
    }

    func trashNote(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let noteCopy = notes[index]
        notes[index].trashedAt = Date()
        notes[index].updatedAt = Date()
        scheduleSave(id)
        _ = saveNoteNow(id)
        openTabs.removeAll { $0.kind == .note && $0.refID == id }
        if selectedTabID.isEmpty || !openTabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = openTabs.last?.id ?? ""
        }
        saveSession()
        plugins.notifyVaultDelete(note: noteCopy)
        plugins.notifyActiveLeafChanged()
        showToast("已移至回收站", symbol: "trash")
    }

    func restoreNote(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].trashedAt = nil
        notes[index].updatedAt = Date()
        scheduleSave(id)
        _ = saveNoteNow(id)
        showToast("已恢复「\(notes[index].displayTitle)」", symbol: "arrow.uturn.backward")
    }

    func deleteNotePermanently(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let vault = vault(notes[index].vaultID) {
            let url = vaultFolder(vault).appendingPathComponent(notes[index].path)
            try? FileManager.default.removeItem(at: url)
        }
        library.deleteHistory(for: id)
        windowNoteHashes.removeValue(forKey: id)
        notes.remove(at: index)
        openTabs.removeAll { $0.kind == .note && $0.refID == id }
        saveSession()
        showToast("已永久删除", symbol: "trash.slash")
    }

    // MARK: Version History, Diff, Conflict & Crash Recovery

    var recoveredCrashDrafts: [CrashRecoveryDraft] { library.recoveredDrafts }
    var pendingNoteConflicts: [String: NoteConflictInfo] { library.pendingConflicts }

    func crashRecoveryDraft(for noteID: String) -> CrashRecoveryDraft? {
        library.recoveredDrafts.first { $0.noteID == noteID }
    }

    func noteConflict(for noteID: String) -> NoteConflictInfo? {
        library.pendingConflicts[noteID]
    }

    func openVersionHistory(for noteID: String? = nil) {
        let targetID = noteID ?? currentNote?.id
        guard let targetID, note(targetID) != nil else {
            showToast("请先打开或选择一篇笔记", symbol: "clock.arrow.circlepath")
            return
        }
        library.historyPolicy = settings.historyPolicy
        historyTargetNoteID = targetID
        historyVisible = true
    }

    func noteRevisions(for noteID: String) -> [NoteRevision] {
        library.revisions(for: noteID)
    }

    @discardableResult
    func createManualSnapshot(for noteID: String) -> Bool {
        library.historyPolicy = settings.historyPolicy
        let (rev, warning) = library.createManualSnapshot(for: noteID)
        historyRevisionTick &+= 1
        if let warning {
            showToast(warning, symbol: "exclamationmark.triangle")
            return false
        }
        if rev != nil {
            showToast("已保存手动快照", symbol: "camera")
            return true
        }
        return false
    }

    @discardableResult
    func restoreNoteVersion(noteID: String, revisionID: String) -> Bool {
        library.historyPolicy = settings.historyPolicy
        let (ok, error) = library.restoreNoteRevision(noteID: noteID,
                                                      revisionID: revisionID,
                                                      fallbackNotebook: settings.newNoteNotebook)
        historyRevisionTick &+= 1
        if ok {
            syncWindowHash(for: noteID)
            if let restored = note(noteID) {
                plugins.notifyVaultModify(note: restored)
            }
            showToast("已自动备份当前内容，并恢复到历史版本", symbol: "clock.arrow.circlepath")
            return true
        }
        showToast(error ?? "恢复版本失败", symbol: "exclamationmark.triangle")
        return false
    }

    @discardableResult
    func resolveNoteConflict(_ noteID: String, mode: ConflictResolutionMode) -> Note? {
        library.historyPolicy = settings.historyPolicy
        let resolved = library.resolveConflict(noteID: noteID,
                                               mode: mode,
                                               fallbackNotebook: settings.newNoteNotebook,
                                               windowID: windowID)
        syncWindowHash(for: noteID)
        historyRevisionTick &+= 1
        if let resolved {
            if mode == .saveConflictCopy {
                openNote(resolved.id)
                showToast("已保存冲突副本「\(resolved.displayTitle)」", symbol: "doc.on.doc")
            } else {
                showToast("冲突已解决并安全写入磁盘", symbol: "checkmark.circle")
            }
        } else {
            showToast("冲突解决时写入失败，请检查磁盘空间或权限", symbol: "exclamationmark.triangle")
        }
        return resolved
    }

    func dismissCrashRecovery(_ noteID: String) {
        library.dismissCrashRecovery(for: noteID)
        _ = saveNoteNow(noteID)
        syncWindowHash(for: noteID)
        showToast("已保留恢复的草稿", symbol: "checkmark.circle")
    }

    func revertCrashRecovery(_ noteID: String) {
        if library.revertCrashRecovery(for: noteID, fallbackNotebook: settings.newNoteNotebook) {
            syncWindowHash(for: noteID)
            historyRevisionTick &+= 1
            showToast("已还原为崩溃前版本，异常草稿已保留在历史中", symbol: "arrow.uturn.backward")
        } else {
            library.dismissCrashRecovery(for: noteID)
            showToast("已保留恢复内容", symbol: "checkmark.circle")
        }
    }

    func historyUsageSummary() -> HistoryUsageSummary {
        library.historyUsage()
    }

    @discardableResult
    func pruneHistoryNow() -> HistoryUsageSummary {
        library.historyPolicy = settings.historyPolicy
        let summary = library.pruneHistoryNow()
        historyRevisionTick &+= 1
        dataStatusMessage = "历史快照已清理，当前保留 \(summary.revisionCount) 条快照（\(NoteHistoryHash.formatBytes(summary.totalBytes))）"
        showToast("已清理过期及超限快照", symbol: "sparkles")
        return summary
    }

    func emptyTrash() {
        for note in trashedNotes { deleteNotePermanently(note.id) }
        showToast("回收站已清空", symbol: "trash")
    }

    // MARK: Daily notes and templates

    func todayTitle() -> String { "\(LexiDate.dayKey()) 每日笔记" }

    func openDailyNote() {
        let title = todayTitle()
        if let existing = notes.first(where: { !$0.isTrashed && $0.vaultID == activeVaultID && $0.displayTitle == title }) {
            openNote(existing.id)
            return
        }
        let template = TemplateLibrary.builtins.first { $0.id == "builtin-daily" } ?? TemplateLibrary.builtins[0]
        let rendered = TemplateLibrary.render(template, title: title)
        createNote(title: title, content: rendered.content, type: .quick,
                   notebook: settings.dailyNotebook, tags: ["日记"])
    }

    func createFromTemplate(_ template: NoteTemplate, title: String) {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.title : title
        let rendered = TemplateLibrary.render(template, title: finalTitle)
        createNote(title: finalTitle, content: rendered.content, type: .markdown,
                   notebook: settings.newNoteNotebook, tags: rendered.tags)
        templatesVisible = false
    }

    // MARK: Links, backlinks, graph

    func resolveNote(target: String, preferredVaultID: String? = nil) -> Note? {
        let clean = target.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let scopeVault = preferredVaultID ?? activeVaultID
        let candidates = notes.filter { !$0.isTrashed && $0.vaultID == scopeVault }
        if let byID = candidates.first(where: { $0.id == clean }) { return byID }
        if let byTitle = candidates.first(where: { $0.displayTitle.caseInsensitiveCompare(clean) == .orderedSame }) {
            return byTitle
        }
        return candidates.first { $0.displayTitle.localizedCaseInsensitiveContains(clean) }
    }

    func outgoingLinks(for note: Note) -> [NoteLink] {
        note.wikiLinks.map { link in
            let resolved = resolveNote(target: link.target, preferredVaultID: note.vaultID)
            return NoteLink(id: "\(note.id)-\(link.target)-\(link.anchor ?? "")",
                            sourceID: note.id, sourceTitle: note.displayTitle,
                            targetID: resolved?.id ?? "",
                            targetTitle: resolved?.displayTitle ?? link.label,
                            anchor: link.anchor ?? "")
        }
    }

    func backlinks(for note: Note) -> [NoteLink] {
        var result: [NoteLink] = []
        for source in notes where !source.isTrashed && source.vaultID == note.vaultID && source.id != note.id {
            for link in source.wikiLinks {
                if let resolved = resolveNote(target: link.target, preferredVaultID: note.vaultID), resolved.id == note.id {
                    result.append(NoteLink(id: "\(source.id)-\(link.target)", sourceID: source.id,
                                           sourceTitle: source.displayTitle, targetID: note.id,
                                           targetTitle: note.displayTitle, anchor: link.anchor ?? ""))
                }
            }
        }
        return result
    }

    func graphData(vaultID: String? = nil) -> GraphData {
        let scope = vaultID ?? activeVaultID
        let scoped = notes.filter { !$0.isTrashed && $0.vaultID == scope }
        var nodes: [String: GraphNode] = [:]
        for note in scoped {
            nodes[note.id] = GraphNode(id: note.id, title: note.displayTitle,
                                       notebook: note.notebook, colorTag: colorTag(for: note), degree: 0)
        }
        var edges: [GraphEdge] = []
        for note in scoped {
            for link in note.wikiLinks {
                guard let target = resolveNote(target: link.target, preferredVaultID: scope),
                      target.vaultID == scope, target.id != note.id else { continue }
                let edge = GraphEdge(id: "\(note.id)->\(target.id)", source: note.id, target: target.id)
                let reverse = "\(target.id)->\(note.id)"
                if !edges.contains(where: { $0.id == edge.id || $0.id == reverse }) {
                    edges.append(edge)
                    nodes[note.id]?.degree += 1
                    nodes[target.id]?.degree += 1
                }
            }
        }
        return GraphData(nodes: Array(nodes.values), edges: edges)
    }

    private func colorTag(for note: Note) -> NoteColorTag {
        let tags = note.tags.map { $0.lowercased() }
        if tags.contains(where: { $0.contains("算法") || $0.contains("系统") }) { return .purple }
        if tags.contains(where: { $0.contains("工程") || $0.contains("桌面") }) { return .indigo }
        if note.type == .quick { return .amber }
        return .green
    }

    func openWikiLink(_ rawTarget: String) {
        let cleanRaw = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleanRaw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let targetName = (parts.first ?? cleanRaw).trimmingCharacters(in: .whitespacesAndNewlines)
        let anchorName = (parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = resolveNote(target: targetName) {
            openNote(existing.id)
            if !anchorName.isEmpty,
               let heading = existing.outline.first(where: { $0.title.caseInsensitiveCompare(anchorName) == .orderedSame }) {
                pendingJump = JumpRequest(noteID: existing.id, line: heading.line, headingID: heading.id, token: UUID())
            }
        } else {
            let title = targetName.isEmpty ? cleanRaw : targetName
            guard !title.isEmpty else { return }
            createNote(title: title, content: "# \(title)\n\n", notebook: settings.newNoteNotebook)
        }
    }

    func connectedNoteIDs(vaultID: String? = nil) -> Set<String> {
        let scope = vaultID ?? activeVaultID
        let scoped = notes.filter { !$0.isTrashed && $0.vaultID == scope }
        var connected: Set<String> = []
        for note in scoped {
            for link in note.wikiLinks {
                guard let target = resolveNote(target: link.target, preferredVaultID: scope),
                      target.vaultID == scope, target.id != note.id else { continue }
                connected.insert(note.id)
                connected.insert(target.id)
            }
        }
        return connected
    }

    func unconnectedNotes(vaultID: String? = nil) -> [Note] {
        let scope = vaultID ?? activeVaultID
        let connected = connectedNoteIDs(vaultID: scope)
        let active = notes.filter { !$0.isTrashed && $0.vaultID == scope && !connected.contains($0.id) }
        return NoteSearch.sortNotes(active, mode: settings.sidebarSortMode, accessedAt: library.noteAccessedAt, pinnedFirst: false)
    }

    func isNoteUnconnected(_ note: Note) -> Bool {
        guard !note.isTrashed else { return false }
        return !connectedNoteIDs(vaultID: note.vaultID).contains(note.id)
    }

    func linkTargetPreview(rawTarget: String, anchor: String? = nil, preferredVaultID: String? = nil) -> LinkTargetPreview {
        let withoutAlias = rawTarget.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawTarget
        let parts = withoutAlias.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let targetName = (parts.first ?? withoutAlias).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAnchor = (anchor ?? (parts.count > 1 ? parts[1] : "")).trimmingCharacters(in: .whitespacesAndNewlines)
        if let target = resolveNote(target: targetName, preferredVaultID: preferredVaultID) {
            let outgoing = outgoingLinks(for: target).filter { !$0.targetID.isEmpty }.count
            let backlinkCount = backlinks(for: target).count
            let snippet = MarkdownParser.previewSnippet(target.content,
                                                        anchor: resolvedAnchor.isEmpty ? nil : resolvedAnchor,
                                                        maxLength: 180)
            return LinkTargetPreview(exists: true,
                                     noteID: target.id,
                                     title: target.displayTitle,
                                     targetName: targetName,
                                     anchor: resolvedAnchor,
                                     notebook: target.notebook,
                                     tags: target.tags,
                                     snippet: snippet.isEmpty ? "（暂无正文摘要）" : snippet,
                                     outgoingCount: outgoing,
                                     backlinkCount: backlinkCount,
                                     updatedAt: target.updatedAt,
                                     lastAccessedAt: accessDate(for: target))
        }
        return LinkTargetPreview(exists: false,
                                 noteID: nil,
                                 title: targetName.isEmpty ? "未命名笔记" : targetName,
                                 targetName: targetName,
                                 anchor: resolvedAnchor,
                                 notebook: settings.newNoteNotebook,
                                 tags: [],
                                 snippet: "当前工作区尚未找到同名笔记，可直接点击下方按钮创建并打开。",
                                 outgoingCount: 0,
                                 backlinkCount: 0,
                                 updatedAt: nil,
                                 lastAccessedAt: nil)
    }

    func suggestLinkCandidates(for note: Note, limit: Int = 5) -> [LinkCandidate] {
        guard !note.isTrashed else { return [] }
        let linkedIDs = Set(
            outgoingLinks(for: note).map(\.targetID).filter { !$0.isEmpty } +
            backlinks(for: note).map(\.sourceID).filter { !$0.isEmpty }
        )
        let noteTags = Set(note.tags)
        let noteBodyLower = note.content.lowercased()
        let noteTitleClean = note.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var candidates: [LinkCandidate] = []
        for other in notes where !other.isTrashed && other.vaultID == note.vaultID && other.id != note.id && !linkedIDs.contains(other.id) {
            var score = 0
            var reason = ""
            let otherTitle = other.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if otherTitle.count >= 2 && noteBodyLower.contains(otherTitle.lowercased()) {
                score += 60
                reason = "正文中提及「\(otherTitle)」"
            } else if noteTitleClean.count >= 2 && other.content.lowercased().contains(noteTitleClean) {
                score += 45
                reason = "对方正文中提及当前笔记"
            }
            let sharedTags = Array(noteTags.intersection(other.tags)).sorted()
            if !sharedTags.isEmpty {
                score += sharedTags.count * 25
                if reason.isEmpty {
                    let previewTags = sharedTags.prefix(2).map { "#\($0)" }.joined(separator: " ")
                    reason = "共同标签 \(previewTags)"
                }
            }
            if !note.notebook.isEmpty && other.notebook == note.notebook {
                score += 15
                if reason.isEmpty {
                    reason = "同一笔记本「\(note.notebook)」"
                }
            }
            if score > 0 {
                candidates.append(LinkCandidate(noteID: other.id,
                                                title: other.displayTitle,
                                                notebook: other.notebook,
                                                reason: reason,
                                                score: score))
            }
        }
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let la = self.note(lhs.noteID).map { accessDate(for: $0) } ?? .distantPast
            let ra = self.note(rhs.noteID).map { accessDate(for: $0) } ?? .distantPast
            if la != ra { return la > ra }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return Array(ordered.prefix(limit))
    }

    func insertWikiLink(_ targetTitle: String, into noteID: String) {
        let cleanTitle = targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, let current = note(noteID) else { return }
        if current.wikiLinks.contains(where: { $0.target.caseInsensitiveCompare(cleanTitle) == .orderedSame }) {
            showToast("已存在到「\(cleanTitle)」的链接", symbol: "link")
            return
        }
        let body = current.content
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = trimmed.isEmpty ? "" : (body.hasSuffix("\n") ? "\n" : "\n\n")
        updateNoteContent(noteID, content: body + separator + "相关笔记：[[\(cleanTitle)]]")
        showToast("已添加双链 [[\(cleanTitle)]]", symbol: "link.badge.plus")
    }

    // MARK: Search

    func quickResults(_ query: String) -> [QuickResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [QuickResult] = []
        let scopedNotes = notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID }
        if trimmed.isEmpty {
            let recent = NoteSearch.sortNotes(scopedNotes,
                                              mode: .accessed,
                                              accessedAt: library.noteAccessedAt,
                                              pinnedFirst: false)
            for (idx, note) in recent.enumerated() {
                results.append(QuickResult(id: note.id,
                                           title: note.displayTitle,
                                           subtitle: "最近访问 · \(note.notebook)",
                                           kind: .note,
                                           symbol: note.type.symbol,
                                           score: min(idx, 499)))
            }
        } else {
            for note in scopedNotes {
                let rank = NoteSearch.rank(note.displayTitle, trimmed)
                let matches = NoteSearch.matches(note, query: trimmed)
                guard rank >= 0 || matches else { continue }
                let snippet = note.snippet(matching: trimmed, maxLength: 58)
                let subtitle = snippet.isEmpty ? "笔记 · \(note.notebook)" : "\(note.notebook) · \(snippet)"
                results.append(QuickResult(id: note.id, title: note.displayTitle,
                                           subtitle: subtitle,
                                           kind: .note, symbol: note.type.symbol,
                                           score: matches ? (rank < 0 ? 60 : rank) : rank))
            }
        }
        for map in maps where map.trashedAt == nil && map.vaultID == activeVaultID {
            let rank = NoteSearch.rank(map.title, trimmed)
            if trimmed.isEmpty || rank >= 0 {
                results.append(QuickResult(id: map.id, title: map.title, subtitle: "思维导图",
                                           kind: .map, symbol: "point.3.filled.connected.trianglepath.dotted",
                                           score: trimmed.isEmpty ? 600 : rank + 10))
            }
        }
        for board in canvases where board.vaultID == activeVaultID {
            let rank = NoteSearch.rank(board.title, trimmed)
            if trimmed.isEmpty || rank >= 0 {
                results.append(QuickResult(id: board.id, title: board.title, subtitle: "白板",
                                           kind: .canvas, symbol: "rectangle.3.group",
                                           score: trimmed.isEmpty ? 600 : rank + 12))
            }
        }
        if !trimmed.isEmpty {
            results.append(QuickResult(id: "create:\(trimmed)", title: "新建「\(trimmed)」",
                                       subtitle: "用这个标题创建一篇新笔记",
                                       kind: .create, symbol: "plus", score: 900))
        }
        return results.sorted { $0.score < $1.score }.prefix(60).map { $0 }
    }

    func searchHits(_ query: String) -> [Note] {
        notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID && NoteSearch.matches($0, query: query) }
            .sorted { NoteSearch.rank($0.displayTitle, query) < NoteSearch.rank($1.displayTitle, query) }
    }

    // MARK: Mind maps

    func createMap(title: String = "未命名导图") {
        let root = MindNode(text: title, order: 0, colorTag: .purple)
        let map = MindMap(id: "map-\(UUID().uuidString.lowercased())", vaultID: activeVaultID,
                          title: title, layout: .right, rootNodeID: root.id,
                          nodes: [root], favorite: false, createdAt: Date(), updatedAt: Date(), trashedAt: nil)
        maps.insert(map, at: 0)
        saveMap(map)
        openMap(map.id)
        showToast("已新建思维导图", symbol: "point.3.filled.connected.trianglepath.dotted")
    }

    func saveMap(_ map: MindMap) {
        library.saveMap(map)
    }

    func updateMap(_ map: MindMap) {
        guard let index = maps.firstIndex(where: { $0.id == map.id }) else { return }
        maps[index] = map
        saveMap(map)
    }

    @discardableResult
    func addMindNode(mapID: String, parentID: String, text: String = "新主题") -> String? {
        guard var map = map(mapID) else { return nil }
        let siblings = map.nodes.filter { $0.parentID == parentID }
        let node = MindNode(parentID: parentID, text: text, order: (siblings.map(\.order).max() ?? 0) + 1,
                            colorTag: map.nodes.first(where: { $0.id == parentID })?.colorTag ?? .purple)
        map.nodes.append(node)
        map.updatedAt = Date()
        updateMap(map)
        return node.id
    }

    func deleteMap(_ id: String) {
        guard let map = map(id) else { return }
        if let vault = vault(map.vaultID) {
            let url = vaultFolder(vault).appendingPathComponent("思维导图").appendingPathComponent("\(map.id).mindmap.json")
            try? FileManager.default.removeItem(at: url)
        }
        maps.removeAll { $0.id == id }
        openTabs.removeAll { $0.kind == .map && $0.refID == id }
        if !openTabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = openTabs.last?.id ?? ""
        }
        saveSession()
        showToast("已删除思维导图", symbol: "trash")
    }

    func updateMindNode(mapID: String, nodeID: String, text: String, noteRef: Note?) {
        guard var map = map(mapID), let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        map.nodes[index].text = text
        map.nodes[index].noteRefID = noteRef?.id
        map.nodes[index].noteRefTitle = noteRef?.displayTitle
        map.updatedAt = Date()
        updateMap(map)
    }

    func updateMindNode(mapID: String, nodeID: String, text: String, note: String?, colorTag: NoteColorTag, noteRef: Note?) {
        guard var map = map(mapID), let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        map.nodes[index].text = text
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        map.nodes[index].note = cleanNote.isEmpty ? nil : cleanNote
        map.nodes[index].colorTag = colorTag
        map.nodes[index].noteRefID = noteRef?.id
        map.nodes[index].noteRefTitle = noteRef?.displayTitle
        if nodeID == map.rootNodeID, !text.isEmpty {
            map.title = text
        }
        map.updatedAt = Date()
        updateMap(map)
    }

    func toggleMindNodeCollapsed(mapID: String, nodeID: String) {
        guard var map = map(mapID), let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        map.nodes[index].collapsed.toggle()
        map.updatedAt = Date()
        updateMap(map)
    }

    func moveMindNodeOrder(mapID: String, nodeID: String, delta: Int) {
        guard var map = map(mapID), let target = map.nodes.first(where: { $0.id == nodeID }) else { return }
        guard !target.parentID.isEmpty else { return }
        var siblings = map.nodes.filter { $0.parentID == target.parentID }.sorted { $0.order < $1.order }
        guard let pos = siblings.firstIndex(where: { $0.id == nodeID }) else { return }
        let nextPos = pos + delta
        guard nextPos >= 0 && nextPos < siblings.count else { return }
        siblings.swapAt(pos, nextPos)
        for (idx, item) in siblings.enumerated() {
            if let mapIdx = map.nodes.firstIndex(where: { $0.id == item.id }) {
                map.nodes[mapIdx].order = idx + 1
            }
        }
        map.updatedAt = Date()
        updateMap(map)
    }

    @discardableResult
    func createNoteFromMindNode(mapID: String, nodeID: String) -> Note? {
        guard var map = map(mapID), let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else { return nil }
        let node = map.nodes[index]
        if let existingID = node.noteRefID, let existing = note(existingID), !existing.isTrashed {
            openNote(existing.id)
            return existing
        }
        let title = node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "导图主题笔记" : node.text
        var body = "# \(title)\n\n"
        if let memo = node.note, !memo.isEmpty {
            body += "\(memo)\n\n"
        }
        let created = createNote(title: title, content: body, notebook: settings.newNoteNotebook, open: true)
        map.nodes[index].noteRefID = created.id
        map.nodes[index].noteRefTitle = created.displayTitle
        map.updatedAt = Date()
        updateMap(map)
        return created
    }

    func exportMindMapOutline(_ map: MindMap) {
        var lines: [String] = []
        func walk(_ id: String, depth: Int) {
            guard let node = map.nodes.first(where: { $0.id == id }) else { return }
            if depth == 0 {
                lines.append("# \(node.text)")
            } else {
                let indent = String(repeating: "  ", count: max(0, depth - 1))
                lines.append("\(indent)- \(node.text)")
            }
            if let memo = node.note, !memo.isEmpty {
                let indent = String(repeating: "  ", count: max(0, depth))
                lines.append("\(indent)> \(memo)")
            }
            for kid in map.children(of: id) {
                walk(kid.id, depth: depth + 1)
            }
        }
        let rootID = map.nodes.contains(where: { $0.id == map.rootNodeID }) ? map.rootNodeID : (map.nodes.first?.id ?? "")
        if !rootID.isEmpty { walk(rootID, depth: 0) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizeFileName(map.title) + "-大纲.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            showToast("已导出导图大纲", symbol: "square.and.arrow.up")
        }
    }

    func exportMindMapJSON(_ map: MindMap) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizeFileName(map.title) + ".mindmap.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(map) {
                try? data.write(to: url, options: .atomic)
                showToast("已导出导图 JSON", symbol: "square.and.arrow.up")
            }
        }
    }

    func deleteMindNode(mapID: String, nodeID: String) {
        guard var map = map(mapID), let node = map.nodes.first(where: { $0.id == nodeID }) else { return }
        guard node.parentID != "" else { return }
        var removed = Set<String>([nodeID])
        var changed = true
        while changed {
            changed = false
            for candidate in map.nodes where removed.contains(candidate.parentID) && !removed.contains(candidate.id) {
                removed.insert(candidate.id)
                changed = true
            }
        }
        map.nodes.removeAll { removed.contains($0.id) }
        map.updatedAt = Date()
        updateMap(map)
    }

    func convertNoteToMap(_ note: Note) {
        let headings = note.outline
        let root = MindNode(text: note.displayTitle, order: 0, colorTag: .purple,
                            noteRefID: note.id, noteRefTitle: note.displayTitle)
        var nodes: [MindNode] = [root]
        var lastByLevel: [Int: MindNode] = [1: root]
        for (index, heading) in headings.enumerated() {
            let parent = (1..<heading.level).reversed().compactMap { lastByLevel[$0] }.first ?? root
            let node = MindNode(parentID: parent.id, text: heading.title, order: index + 1,
                                colorTag: .indigo, noteRefID: note.id, noteRefTitle: note.displayTitle)
            nodes.append(node)
            lastByLevel[heading.level] = node
            for level in (heading.level + 1)...6 { lastByLevel[level] = nil }
        }
        let map = MindMap(id: "map-\(UUID().uuidString.lowercased())", vaultID: note.vaultID,
                          title: note.displayTitle, layout: .right, rootNodeID: root.id,
                          nodes: nodes, favorite: false, createdAt: Date(), updatedAt: Date(), trashedAt: nil)
        maps.insert(map, at: 0)
        saveMap(map)
        openMap(map.id)
        showToast("已从笔记生成思维导图", symbol: "point.3.filled.connected.trianglepath.dotted")
    }

    // MARK: Canvas

    func createCanvas(title: String = "未命名白板") {
        let board = CanvasBoard(id: "canvas-\(UUID().uuidString.lowercased())", vaultID: activeVaultID,
                                title: title, cards: [], edges: [], createdAt: Date(), updatedAt: Date())
        canvases.insert(board, at: 0)
        saveCanvas(board)
        openCanvas(board.id)
        showToast("已新建白板", symbol: "rectangle.3.group")
    }

    func saveCanvas(_ board: CanvasBoard) {
        library.saveCanvas(board)
    }

    func updateCanvas(_ board: CanvasBoard) {
        guard let index = canvases.firstIndex(where: { $0.id == board.id }) else { return }
        canvases[index] = board
        saveCanvas(board)
    }

    // MARK: Import / export

    func exportCurrentMarkdown() {
        guard let note = currentNote else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizeFileName(note.displayTitle) + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try NoteCodec.encode(note).write(to: url, atomically: true, encoding: .utf8)
                dataStatusMessage = "已导出 Markdown 到 \(url.lastPathComponent)"
                showToast("已导出 Markdown：\(url.lastPathComponent)", symbol: "square.and.arrow.up")
            } catch {
                dataStatusMessage = "导出 Markdown 失败：\(error.localizedDescription)"
                showToast("导出失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }

    func exportCurrentPDF() {
        guard let note = currentNote else {
            showToast("请先打开要导出的笔记", symbol: "doc.richtext")
            return
        }
        _ = saveNoteNow(note.id)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizeFileName(note.displayTitle) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let vaultURL = vault(note.vaultID).map { library.vaultFolder($0) }
        showToast("正在生成 PDF…", symbol: "doc.richtext")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await LexiPdfExportService.shared.exportPDF(note: note, vaultURL: vaultURL, to: destURL)
                let sizeKB = max(1, Int((Double(data.count) / 1024.0).rounded()))
                self.dataStatusMessage = "已导出 PDF 到 \(destURL.lastPathComponent)（\(sizeKB) KB）"
                self.showToast("已导出 PDF：\(destURL.lastPathComponent)", symbol: "checkmark.circle")
            } catch {
                self.dataStatusMessage = "导出 PDF 失败：\(error.localizedDescription)"
                self.showToast("导出 PDF 失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }

    var activeWorkspaceFolder: URL {
        if let v = activeVault { return library.vaultFolder(v) }
        return storageRoot
    }

    func chooseActiveWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择工作区文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.bindVaultFolder(vaultID: activeVaultID, folderURL: url)
        if !library.loadWarnings.isEmpty {
            dataStatusMessage = library.loadWarnings.joined(separator: "；")
            showToast("工作区已切换（有 \(library.loadWarnings.count) 条读取提醒）", symbol: "exclamationmark.triangle")
        } else {
            dataStatusMessage = "工作区文件夹已设为 \(url.path)"
            showToast("已绑定工作区文件夹", symbol: "folder")
        }
    }

    func exportSettingsAndPlugins() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "知萤_设置与插件_\(LexiDate.dayKey()).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        struct PluginEntry: Codable {
            var id: String
            var name: String
            var version: String
            var kind: String
            var enabled: Bool
            var grantedCapabilities: [String]
        }
        struct SettingsPluginsPayload: Codable {
            var format: String
            var version: Int
            var exportedAt: Date
            var appearance: String
            var themeMode: String
            var accentHex: String
            var customBackgroundHex: String
            var customForegroundHex: String
            var showTabStrip: Bool
            var showRibbon: Bool
            var hiddenRibbonCommands: [String]
            var interfaceZoom: Double
            var editorFontSize: Double
            var limitEditorWidth: Bool
            var editorDefaultView: String
            var editorDefaultMode: String
            var editorViewStatus: Bool
            var editorShowTitle: Bool
            var editorDefaultTier: String
            var quickZoom: Bool
            var hotkeyOverrides: [String: [String]]
            var plugins: [PluginEntry]
        }

        let pluginEntries = plugins.records.map { rec in
            PluginEntry(
                id: rec.id,
                name: rec.manifest.name,
                version: rec.manifest.version,
                kind: rec.manifest.kind.rawValue,
                enabled: rec.state == .running,
                grantedCapabilities: plugins.capabilityGrant(for: rec.id).granted
            )
        }
        let payload = SettingsPluginsPayload(
            format: "LexiNote.SettingsPlugins",
            version: 1,
            exportedAt: Date(),
            appearance: settings.appearance.rawValue,
            themeMode: settings.themeMode.rawValue,
            accentHex: settings.accentHex,
            customBackgroundHex: settings.customBackgroundHex,
            customForegroundHex: settings.customForegroundHex,
            showTabStrip: settings.showTabStrip,
            showRibbon: settings.showRibbon,
            hiddenRibbonCommands: settings.hiddenRibbonCommands,
            interfaceZoom: settings.interfaceZoom,
            editorFontSize: settings.editorFontSize,
            limitEditorWidth: settings.limitEditorWidth,
            editorDefaultView: settings.editorDefaultView,
            editorDefaultMode: settings.editorDefaultMode,
            editorViewStatus: settings.editorViewStatus,
            editorShowTitle: settings.editorShowTitle,
            editorDefaultTier: settings.editorDefaultTier.rawValue,
            quickZoom: settings.quickZoom,
            hotkeyOverrides: settings.hotkeyOverrides,
            plugins: pluginEntries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(payload).write(to: url, options: .atomic)
            dataStatusMessage = "已导出设置与插件合集到 \(url.lastPathComponent)"
            showToast("设置与插件已导出", symbol: "square.and.arrow.up")
        } catch {
            showToast("导出失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    func importSettingsAndPlugins() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        struct PluginEntry: Codable {
            var id: String
            var enabled: Bool
        }
        struct SettingsPluginsPayload: Codable {
            var format: String?
            var appearance: String?
            var themeMode: String?
            var accentHex: String?
            var customBackgroundHex: String?
            var customForegroundHex: String?
            var showTabStrip: Bool?
            var showRibbon: Bool?
            var hiddenRibbonCommands: [String]?
            var interfaceZoom: Double?
            var editorFontSize: Double?
            var limitEditorWidth: Bool?
            var editorDefaultView: String?
            var editorDefaultMode: String?
            var editorViewStatus: Bool?
            var editorShowTitle: Bool?
            var editorDefaultTier: String?
            var quickZoom: Bool?
            var hotkeyOverrides: [String: [String]]?
            var plugins: [PluginEntry]?
        }
        do {
            let data = try Data(contentsOf: url)
            let p = try JSONDecoder().decode(SettingsPluginsPayload.self, from: data)
            guard p.format == "LexiNote.SettingsPlugins" else {
                showToast("不是有效的知萤设置与插件备份文件", symbol: "exclamationmark.triangle")
                return
            }
            if let v = p.appearance, let m = AppearanceMode(rawValue: v) { settings.appearance = m }
            if let v = p.themeMode, let m = ThemeMode(rawValue: v) { settings.themeMode = m }
            if let v = p.accentHex { settings.accentHex = v }
            if let v = p.customBackgroundHex { settings.customBackgroundHex = v }
            if let v = p.customForegroundHex { settings.customForegroundHex = v }
            if let v = p.showTabStrip { settings.showTabStrip = v }
            if let v = p.showRibbon { settings.showRibbon = v }
            if let v = p.hiddenRibbonCommands { settings.hiddenRibbonCommands = v }
            if let v = p.interfaceZoom { settings.interfaceZoom = v }
            if let v = p.editorFontSize { settings.editorFontSize = v }
            if let v = p.limitEditorWidth { settings.limitEditorWidth = v }
            if let v = p.editorDefaultView { settings.editorDefaultView = v }
            if let v = p.editorDefaultMode { settings.editorDefaultMode = v }
            if let v = p.editorViewStatus { settings.editorViewStatus = v }
            if let v = p.editorShowTitle { settings.editorShowTitle = v }
            if let v = p.editorDefaultTier, let t = EditorLevel(rawValue: v) { settings.editorDefaultTier = t }
            if let v = p.quickZoom { settings.quickZoom = v }
            if let v = p.hotkeyOverrides { settings.hotkeyOverrides = v }
            dataStatusMessage = "已导入设置与插件配置"
            showToast("设置与插件已恢复", symbol: "checkmark.circle")
        } catch {
            showToast("导入失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    func exportWorkspaceZip() {
        library.flushAllNotes(fallbackNotebook: settings.newNoteNotebook)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "知萤_工作区归档_\(LexiDate.dayKey()).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let folder = activeWorkspaceFolder
        if let vault = activeVault {
            let manifest: [String: Any] = [
                "format": "LexiNote.Workspace",
                "version": 1,
                "vaultId": vault.id,
                "vaultName": vault.name,
                "description": vault.detail,
                "exportedAt": LexiDate.iso(Date()),
                "platform": "macos"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]) {
                try? data.write(to: folder.appendingPathComponent("lexinote-manifest.json"), options: .atomic)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", folder.path, destURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                dataStatusMessage = "已导出工作区压缩包到 \(destURL.lastPathComponent)"
                showToast("工作区压缩包已导出", symbol: "doc.zipper")
            } else {
                showToast("压缩导出失败（状态码 \(process.terminationStatus)）", symbol: "exclamationmark.triangle")
            }
        } catch {
            showToast("压缩导出失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    func importWorkspaceZip() {
        let zipPanel = NSOpenPanel()
        zipPanel.allowsMultipleSelection = false
        zipPanel.canChooseDirectories = false
        zipPanel.allowedContentTypes = [.zip]
        zipPanel.prompt = "选择工作区压缩包"
        guard zipPanel.runModal() == .OK, let zipURL = zipPanel.url else { return }

        let dirPanel = NSOpenPanel()
        dirPanel.canChooseFiles = false
        dirPanel.canChooseDirectories = true
        dirPanel.canCreateDirectories = true
        dirPanel.prompt = "选择解压保存文件夹"
        guard dirPanel.runModal() == .OK, let destFolder = dirPanel.url else { return }

        do {
            let entries = try PluginZip.readEntries(from: zipURL)
            let fm = FileManager.default
            let rootPath = destFolder.standardizedFileURL.path
            var written = 0
            for entry in entries {
                let target = destFolder.appendingPathComponent(entry.relativePath).standardizedFileURL
                guard target.path.hasPrefix(rootPath + "/") else { continue }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: target, options: .atomic)
                written += 1
            }
            var vaultName = destFolder.lastPathComponent
            let manifestURL = destFolder.appendingPathComponent("lexinote-manifest.json")
            if let mData = try? Data(contentsOf: manifestURL),
               let mObj = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
               let name = mObj["vaultName"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                vaultName = name
            }
            let registered = library.registerFolderWorkspace(name: vaultName, folderURL: destFolder)
            setActiveVault(registered.id)
            dataStatusMessage = "已解压 \(written) 个文件到「\(vaultName)」"
            showToast("已解压 \(written) 个文件并打开工作区", symbol: "folder.badge.plus")
        } catch {
            showToast("解压失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    func exportMarkdownBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择导出目录"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let dest = dir.appendingPathComponent("LexiNote-Markdown-\(LexiDate.dayKey())", isDirectory: true)
        var exported = 0
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for note in notes where !note.isTrashed && note.vaultID == activeVaultID {
                let nbFolder = dest.appendingPathComponent(sanitizeFolder(note.notebook), isDirectory: true)
                try fm.createDirectory(at: nbFolder, withIntermediateDirectories: true)
                let fileURL = nbFolder.appendingPathComponent(sanitizeFileName(note.displayTitle) + ".md")
                try NoteCodec.encode(note).write(to: fileURL, atomically: true, encoding: .utf8)
                exported += 1
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let vaultMaps = maps.filter { $0.trashedAt == nil && $0.vaultID == activeVaultID }
            if !vaultMaps.isEmpty {
                let mapDir = dest.appendingPathComponent("思维导图", isDirectory: true)
                try fm.createDirectory(at: mapDir, withIntermediateDirectories: true)
                for m in vaultMaps {
                    let url = mapDir.appendingPathComponent("\(m.id).mindmap.json")
                    try encoder.encode(m).write(to: url, options: .atomic)
                }
            }
            let vaultCanvases = canvases.filter { $0.vaultID == activeVaultID }
            if !vaultCanvases.isEmpty {
                let canvasDir = dest.appendingPathComponent("白板", isDirectory: true)
                try fm.createDirectory(at: canvasDir, withIntermediateDirectories: true)
                for board in vaultCanvases {
                    let url = canvasDir.appendingPathComponent("\(board.id).canvas.json")
                    try encoder.encode(board).write(to: url, options: .atomic)
                }
            }
            let attachmentsSrc = activeWorkspaceFolder.appendingPathComponent("attachments", isDirectory: true)
            if fm.fileExists(atPath: attachmentsSrc.path) {
                let attachmentsDst = dest.appendingPathComponent("attachments", isDirectory: true)
                try? fm.copyItem(at: attachmentsSrc, to: attachmentsDst)
            }
            dataStatusMessage = "已导出 \(exported) 篇 Markdown 笔记"
            showToast("已导出 \(exported) 篇 Markdown", symbol: "square.and.arrow.up")
        } catch {
            showToast("导出失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    func openExternalFiles(_ urls: [URL], sourceLabel: String = "打开文件") {
        guard !urls.isEmpty else { return }
        if !sessionLoaded {
            pendingExternalOpenURLs.append(contentsOf: urls)
            return
        }
        _ = ingestExternalFiles(urls, includeJsonBackups: true, sourceLabel: sourceLabel)
    }

    private func flushPendingExternalOpensAndWarnings() {
        if !pendingExternalOpenURLs.isEmpty {
            let queued = pendingExternalOpenURLs
            pendingExternalOpenURLs.removeAll()
            _ = ingestExternalFiles(queued, includeJsonBackups: true, sourceLabel: "打开文件")
            return
        }
        if !library.loadWarnings.isEmpty {
            dataStatusMessage = library.loadWarnings.joined(separator: "；")
            showToast("工作区加载存在 \(library.loadWarnings.count) 条异常，详情见顶部横幅", symbol: "exclamationmark.triangle")
        }
    }

    @discardableResult
    func ingestExternalFiles(_ urls: [URL],
                             includeJsonBackups: Bool,
                             sourceLabel: String) -> (openedNotes: Int, failedCount: Int) {
        var openedNotes = 0
        var reusedNotes = 0
        var openedExtras = 0
        var skippedUnsupported: [String] = []
        var failedFiles: [(name: String, reason: String)] = []
        var firstNoteID: String?
        var firstTitle: String = ""

        let activeFolder = activeWorkspaceFolder.standardizedFileURL

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                failedFiles.append((url.lastPathComponent, "文件不存在或已移动"))
                continue
            }
            if isDir.boolValue {
                skippedUnsupported.append("\(url.lastPathComponent)（文件夹）")
                continue
            }

            let ext = url.pathExtension.lowercased()
            if ext == "json" && includeJsonBackups {
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    failedFiles.append((url.lastPathComponent, friendlyReadError(error)))
                    continue
                }
                struct Backup: Codable {
                    var version: Int?
                    var vaults: [Vault]?
                    var notes: [Note]?
                    var maps: [MindMap]?
                    var canvases: [CanvasBoard]?
                }
                if let backup = try? JSONDecoder().decode(Backup.self, from: data),
                   (backup.notes != nil || backup.vaults != nil || backup.maps != nil || backup.canvases != nil) {
                    var added = 0
                    for v in backup.vaults ?? [] where vault(v.id) == nil {
                        vaults.append(v)
                    }
                    library.saveVaults()
                    for n in backup.notes ?? [] where note(n.id) == nil {
                        var copy = n
                        if vault(copy.vaultID) == nil { copy.vaultID = activeVaultID }
                        notes.append(copy)
                        _ = library.persist(copy, fallbackNotebook: settings.newNoteNotebook)
                        if firstNoteID == nil {
                            firstNoteID = copy.id
                            firstTitle = copy.displayTitle
                        }
                        added += 1
                    }
                    for m in backup.maps ?? [] where map(m.id) == nil {
                        var copy = m
                        if vault(copy.vaultID) == nil { copy.vaultID = activeVaultID }
                        maps.append(copy)
                        saveMap(copy)
                        openedExtras += 1
                    }
                    for c in backup.canvases ?? [] where canvases.first(where: { $0.id == c.id }) == nil {
                        var copy = c
                        if vault(copy.vaultID) == nil { copy.vaultID = activeVaultID }
                        canvases.append(copy)
                        library.saveCanvas(copy)
                        openedExtras += 1
                    }
                    openedNotes += added
                    dataStatusMessage = "已从备份恢复 \(added) 篇笔记"
                    continue
                }
                if var mindMap = try? JSONDecoder().decode(MindMap.self, from: data) {
                    if let existing = map(mindMap.id) {
                        openMap(existing.id)
                    } else {
                        mindMap.vaultID = activeVaultID
                        maps.append(mindMap)
                        saveMap(mindMap)
                        openMap(mindMap.id)
                    }
                    openedExtras += 1
                    if firstTitle.isEmpty { firstTitle = mindMap.title }
                    continue
                }
                if var board = try? JSONDecoder().decode(CanvasBoard.self, from: data) {
                    if let existing = canvas(board.id) {
                        openCanvas(existing.id)
                    } else {
                        board.vaultID = activeVaultID
                        canvases.append(board)
                        library.saveCanvas(board)
                        openCanvas(board.id)
                    }
                    openedExtras += 1
                    if firstTitle.isEmpty { firstTitle = board.title }
                    continue
                }
                failedFiles.append((url.lastPathComponent, "无法识别的 JSON 文件格式"))
                continue
            }

            let supportedTextExts: Set<String> = ["md", "markdown", "txt", "text"]
            guard supportedTextExts.contains(ext) else {
                skippedUnsupported.append(url.lastPathComponent)
                continue
            }

            // If the Markdown file already belongs to the active vault folder, open that note in-place.
            if url.path.hasPrefix(activeFolder.path + "/") {
                let rel = String(url.path.dropFirst(activeFolder.path.count + 1))
                if let existing = notes.first(where: { $0.vaultID == activeVaultID && !$0.isTrashed && $0.path == rel }) {
                    reusedNotes += 1
                    if firstNoteID == nil {
                        firstNoteID = existing.id
                        firstTitle = existing.displayTitle
                    }
                    continue
                }
            }

            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                failedFiles.append((url.lastPathComponent, friendlyReadError(error)))
                continue
            }

            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            if var decoded = NoteCodec.decode(text: text, relativePath: "", vaultID: activeVaultID, fallbackNotebook: "导入", fileDate: Date()) {
                if decoded.title.isEmpty { decoded.title = fallbackTitle }
                if note(decoded.id) != nil { decoded.id = "note-\(UUID().uuidString.lowercased())" }
                decoded.path = ""
                notes.insert(decoded, at: 0)
                let saved = library.persist(decoded, fallbackNotebook: settings.newNoteNotebook)
                if let idx = notes.firstIndex(where: { $0.id == saved.id }) {
                    notes[idx] = saved
                }
                if firstNoteID == nil {
                    firstNoteID = saved.id
                    firstTitle = saved.displayTitle
                }
            } else {
                let created = createNote(title: fallbackTitle, content: text, notebook: "导入", open: false)
                if firstNoteID == nil {
                    firstNoteID = created.id
                    firstTitle = created.displayTitle
                }
            }
            openedNotes += 1
        }

        if let firstNoteID {
            openNote(firstNoteID)
        }

        let totalSucceeded = openedNotes + reusedNotes + openedExtras
        if totalSucceeded > 0 && failedFiles.isEmpty && skippedUnsupported.isEmpty {
            let summary: String
            if totalSucceeded == 1 && !firstTitle.isEmpty {
                summary = reusedNotes == 1 ? "已打开「\(firstTitle)」" : "已打开并导入「\(firstTitle)」"
            } else if openedNotes == totalSucceeded {
                summary = "已\(sourceLabel) \(openedNotes) 篇笔记"
            } else {
                summary = "已打开 \(totalSucceeded) 个文件"
            }
            dataStatusMessage = summary
            showToast(summary, symbol: "checkmark.circle")
        } else if totalSucceeded > 0 {
            var details: [String] = []
            if let first = failedFiles.first {
                details.append("失败 \(failedFiles.count) 个（如 \(first.name)：\(first.reason)）")
            }
            if !skippedUnsupported.isEmpty {
                details.append("已跳过 \(skippedUnsupported.count) 个不支持项")
            }
            let summary = "已打开 \(totalSucceeded) 个，\(details.joined(separator: "；"))"
            dataStatusMessage = summary
            showToast(summary, symbol: "exclamationmark.triangle")
        } else if let firstFailed = failedFiles.first {
            let summary = "无法打开「\(firstFailed.name)」：\(firstFailed.reason)"
            dataStatusMessage = summary
            showToast(summary, symbol: "exclamationmark.triangle")
        } else if !skippedUnsupported.isEmpty {
            let summary = "不支持打开：\(skippedUnsupported.prefix(2).joined(separator: "、"))"
            dataStatusMessage = summary
            showToast(summary, symbol: "exclamationmark.triangle")
        }

        return (totalSucceeded, failedFiles.count)
    }

    private func friendlyReadError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError: return "文件不存在"
            case NSFileReadNoPermissionError: return "没有读取权限"
            case NSFileReadInapplicableStringEncodingError: return "不是有效的 UTF-8 文本"
            default: break
            }
        }
        return error.localizedDescription
    }

    func importBackupOrMarkdown() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"), .plainText].compactMap { $0 }
        guard panel.runModal() == .OK else { return }
        _ = ingestExternalFiles(panel.urls, includeJsonBackups: true, sourceLabel: "导入")
    }

    func rebuildIndex() {
        library.rebuildIndex()
        let count = notes.filter { !$0.isTrashed && $0.vaultID == activeVaultID }.count
        if !library.loadWarnings.isEmpty {
            dataStatusMessage = "索引已重建（\(count) 篇笔记），但有 \(library.loadWarnings.count) 个读取异常：\(library.loadWarnings.first ?? "")"
            showToast("索引已重建，发现 \(library.loadWarnings.count) 个异常文件", symbol: "exclamationmark.triangle")
        } else {
            dataStatusMessage = "索引已重建，共 \(count) 篇笔记"
            showToast("索引已重建（\(count) 篇笔记）", symbol: "arrow.triangle.2.circlepath")
        }
    }

    func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "设为文档目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.customStoragePath = url.path
        dataStatusMessage = "已设置文档目录为 \(url.path)（重启应用后生效）"
        showToast("已更新文档目录（重启生效）", symbol: "folder")
    }

    func importMarkdownFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"), .plainText].compactMap { $0 }
        guard panel.runModal() == .OK else { return }
        _ = ingestExternalFiles(panel.urls, includeJsonBackups: false, sourceLabel: "导入")
    }

    func insertAttachmentForCurrentNote() {
        guard let note = currentNote, let vault = vault(note.vaultID) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = library.importAttachment(from: url, for: note, in: vault) else {
            showToast("附件导入失败", symbol: "exclamationmark.triangle")
            return
        }
        let snippet = imported.isImage
            ? "![\(imported.fileName)](\(imported.relativePath))"
            : "[\(imported.fileName)](\(imported.relativePath))"
        let updatedContent = note.content.isEmpty ? snippet : "\(note.content.trimmingCharacters(in: .newlines))\n\n\(snippet)\n"
        updateNoteContent(note.id, content: updatedContent)
        showToast("已插入附件「\(imported.fileName)」", symbol: "paperclip")
    }

    func revealNoteInFinder(_ id: String) {
        guard let note = note(id), let vault = vault(note.vaultID) else { return }
        let url = vaultFolder(vault).appendingPathComponent(note.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealStorageInFinder() {
        NSWorkspace.shared.open(storageRoot)
    }

    func copyNotePath(_ id: String) {
        guard let note = note(id), let vault = vault(note.vaultID) else { return }
        let url = vaultFolder(vault).appendingPathComponent(note.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        showToast("已复制文件路径", symbol: "doc.on.clipboard")
    }

    // MARK: Toast & palette

    func showToast(_ message: String, symbol: String = "checkmark.circle") {
        let toast = ToastMessage(id: UUID(), message: message, symbol: symbol)
        self.toast = toast
        paletteTimer?.invalidate()
        paletteTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.toast?.id == toast.id { withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil } }
            }
        }
    }

    func presentCommandPalette() {
        paletteMode = .commands
        paletteVisible = true
    }

    func presentQuickSwitch() {
        paletteMode = .quickSwitch
        paletteVisible = true
    }

    func dismissPalette() {
        paletteVisible = false
    }

    func jump(to heading: OutlineHeading, in note: Note) {
        openNote(note.id)
        pendingJump = JumpRequest(noteID: note.id, line: heading.line, headingID: heading.id, token: UUID())
    }

    // MARK: Helpers

    func sanitizeFolder(_ value: String) -> String {
        library.sanitizeFolder(value)
    }

    func sanitizeFileName(_ value: String) -> String {
        library.sanitizeFileName(value)
    }
}
