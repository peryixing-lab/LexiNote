import Foundation
import Combine

struct VaultTabSession: Codable {
    var tabs: [WorkspaceTab]
    var selectedID: String?
}

struct SessionSnapshot: Codable {
    var tabs: [WorkspaceTab]?
    var selectedID: String?
    var activeVaultID: String?
    var vaultSessions: [String: VaultTabSession]?
}

enum PersistOutcome {
    case saved(Note)
    case conflict(NoteConflictInfo)
    case failed(String)
}

@MainActor
final class LibraryStore: ObservableObject {
    let storageRoot: URL
    let isSnapshot: Bool
    let historyStore: NoteHistoryStore

    @Published var vaults: [Vault] = []
    @Published var notes: [Note] = []
    @Published private(set) var noteAccessedAt: [String: Date] = [:]
    @Published var maps: [MindMap] = []
    @Published var canvases: [CanvasBoard] = []
    @Published var saveState: SaveState = .saved(Date()) {
        didSet {
            if case .saved(let date) = saveState {
                lastSavedDate = date
            }
        }
    }
    @Published private(set) var lastSavedDate: Date = Date()
    @Published var loadWarnings: [String] = []
    @Published var recoveredDrafts: [CrashRecoveryDraft] = []
    @Published var pendingConflicts: [String: NoteConflictInfo] = [:]

    var historyPolicy: HistoryRetentionPolicy = .default
    /// Optional test hook passed through to atomic file writes for fault injection.
    var writeHook: LexiSafeIO.WriteHook? {
        didSet { historyStore.writeHook = writeHook }
    }

    private var dirtyNotes: [String: String] = [:]
    private var unsavedManualNotes: Set<String> = []
    private var noteLastSavedDates: [String: Date] = [:]
    private var pendingWalNotes: [String: String] = [:]
    private var diskBaseHashes: [String: String] = [:]
    private var committedNotes: [String: Note] = [:]
    private var lastEditorWindowID: [String: UUID] = [:]
    private var autosaveTimer: Timer?
    private var walDebounceTask: Task<Void, Never>?

    init(storageRoot: URL? = nil, inMemory: Bool = false, seedDemo: Bool = true) {
        self.isSnapshot = inMemory
        let root = storageRoot ?? LibraryStore.defaultStorageRoot()
        self.storageRoot = root
        self.historyStore = NoteHistoryStore(storageRoot: root, inMemory: inMemory)
        if inMemory {
            if seedDemo {
                self.vaults = SeedData.vaults()
                self.notes = SeedData.notes()
                self.maps = SeedData.mindMaps()
                self.canvases = [SeedData.canvas()]
            } else {
                self.vaults = [Vault(id: "default-vault", name: "我的工作区",
                                     detail: "本地优先的知识库", createdAt: Date())]
            }
            for note in self.notes {
                self.diskBaseHashes[note.id] = NoteHistoryHash.computeNoteHash(note)
                self.committedNotes[note.id] = note
            }
            self.saveState = .saved(Date())
        } else {
            prepareStorage()
            loadLibrary()
        }
        startAutosave()
    }

    deinit {
        autosaveTimer?.invalidate()
        walDebounceTask?.cancel()
    }

    static func defaultStorageRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["LEXINOTE_STORE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let custom = UserDefaults.standard.string(forKey: SettingsStore.customStoragePathKey),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("LexiNote", isDirectory: true)
    }

    func rebuildIndex() {
        guard !isSnapshot else { return }
        flushDirty()
        loadLibrary()
    }

    var defaultVaultID: String {
        vaults.first?.id ?? "default-vault"
    }

    func vault(_ id: String) -> Vault? {
        vaults.first { $0.id == id }
    }

    func vaultFolder(_ vault: Vault) -> URL {
        if let custom = vault.folderPath, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return storageRoot.appendingPathComponent(sanitizeFolder(vault.name), isDirectory: true)
    }

    func bindVaultFolder(vaultID: String, folderURL: URL) {
        guard let idx = vaults.firstIndex(where: { $0.id == vaultID }) else { return }
        vaults[idx].folderPath = folderURL.path
        saveVaults()
        loadLibrary()
        if !FileManager.default.isWritableFile(atPath: folderURL.path) {
            loadWarnings.append("工作区目录暂无写入权限：\(folderURL.lastPathComponent)")
        }
    }

    func clearLoadWarnings() {
        loadWarnings.removeAll()
    }

    func registerFolderWorkspace(name: String, folderURL: URL) -> Vault {
        if let existing = vaults.first(where: { $0.folderPath == folderURL.path }) {
            loadLibrary()
            return existing
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folderURL.lastPathComponent : name
        let vault = Vault(id: "vault-\(UUID().uuidString.prefix(8).lowercased())",
                          name: uniqueVaultName(from: cleanName),
                          detail: "本地文件夹工作区",
                          createdAt: Date(),
                          folderPath: folderURL.path)
        vaults.append(vault)
        saveVaults()
        loadLibrary()
        return vault
    }

    // MARK: Storage bootstrapping

    private func prepareStorage() {
        if !FileManager.default.fileExists(atPath: storageRoot.path) {
            try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        }
    }

    private var libraryURL: URL { storageRoot.appendingPathComponent("library.json") }
    private var sessionURL: URL { storageRoot.appendingPathComponent("session.json") }
    private var noteAccessURL: URL { storageRoot.appendingPathComponent("note-access.json") }

    private func loadLibrary() {
        var warnings: [String] = []
        var loadedVaults: [Vault] = []
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            do {
                let data = try Data(contentsOf: libraryURL)
                loadedVaults = try JSONDecoder().decode([Vault].self, from: data)
            } catch {
                warnings.append("工作区索引 library.json 读取异常：\(error.localizedDescription)")
            }
        }
        if loadedVaults.isEmpty {
            // A fresh install starts with one empty workspace and no documents.
            loadedVaults = [Vault(id: "default-vault", name: "我的工作区",
                                  detail: "本地优先的知识库", createdAt: Date())]
            saveVaults(loadedVaults)
        }
        vaults = loadedVaults

        var loadedNotes: [Note] = []
        diskBaseHashes.removeAll()
        committedNotes.removeAll()
        for vault in loadedVaults {
            let folder = vaultFolder(vault)
            if !FileManager.default.fileExists(atPath: folder.path) {
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                } catch {
                    warnings.append("无法创建工作区目录「\(vault.name)」：\(error.localizedDescription)")
                }
            }
            loadedNotes.append(contentsOf: scanNotes(in: vault, warnings: &warnings))
        }
        for note in loadedNotes {
            diskBaseHashes[note.id] = NoteHistoryHash.computeNoteHash(note)
            committedNotes[note.id] = note
        }

        let recovered = recoverCrashWalDrafts(into: &loadedNotes, vaults: loadedVaults)

        var loadedMaps: [MindMap] = []
        var loadedCanvases: [CanvasBoard] = []
        for vault in loadedVaults {
            loadedMaps.append(contentsOf: loadMaps(in: vault, warnings: &warnings))
            loadedCanvases.append(contentsOf: loadCanvases(in: vault, warnings: &warnings))
        }

        let loadedAccess = readNoteAccessTimes(validIDs: Set(loadedNotes.map(\.id)))
        for idx in loadedNotes.indices {
            if let accessed = loadedAccess[loadedNotes[idx].id] {
                loadedNotes[idx].lastAccessedAt = accessed
            }
        }

        noteAccessedAt = loadedAccess
        notes = loadedNotes
        maps = loadedMaps
        canvases = loadedCanvases
        recoveredDrafts = recovered
        loadWarnings = warnings
    }

    func accessDate(for note: Note) -> Date {
        noteAccessedAt[note.id] ?? note.lastAccessedAt ?? note.updatedAt
    }

    func recordNoteOpened(_ noteID: String, at date: Date = Date()) {
        guard !noteID.isEmpty, notes.contains(where: { $0.id == noteID }) else { return }
        noteAccessedAt[noteID] = date
        if let idx = notes.firstIndex(where: { $0.id == noteID }) {
            notes[idx].lastAccessedAt = date
        }
        writeNoteAccessTimes()
    }

    private func readNoteAccessTimes(validIDs: Set<String>) -> [String: Date] {
        guard let data = try? Data(contentsOf: noteAccessURL),
              let raw = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return [:]
        }
        var result: [String: Date] = [:]
        for (id, ts) in raw where validIDs.contains(id) && ts.isFinite && ts > 0 {
            result[id] = Date(timeIntervalSince1970: ts)
        }
        return result
    }

    private func writeNoteAccessTimes() {
        guard !isSnapshot else { return }
        let validIDs = Set(notes.map(\.id))
        var payload: [String: TimeInterval] = [:]
        for (id, date) in noteAccessedAt where validIDs.contains(id) {
            payload[id] = date.timeIntervalSince1970
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? LexiSafeIO.atomicWriteData(data, to: noteAccessURL, hook: writeHook)
    }

    func saveVaults(_ list: [Vault]? = nil) {
        guard !isSnapshot else { return }
        let target = list ?? vaults
        do {
            let data = try JSONEncoder().encode(target)
            try LexiSafeIO.atomicWriteData(data, to: libraryURL, hook: writeHook)
        } catch {
            saveState = .failed(LexiSafeIO.friendlyWriteError(error, target: "工作区索引"))
        }
    }

    @discardableResult
    func createVault(name: String, detail: String = "本地优先的知识库") -> Vault {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = base.isEmpty ? "新建工作区" : base
        let uniqueName = uniqueVaultName(from: candidate)
        let vault = Vault(id: "vault-\(UUID().uuidString.lowercased())",
                          name: uniqueName,
                          detail: detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "本地优先的知识库" : detail,
                          createdAt: Date())
        vaults.append(vault)
        if !isSnapshot {
            let folder = vaultFolder(vault)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            saveVaults()
        }
        return vault
    }

    private func uniqueVaultName(from base: String) -> String {
        let usedFolders = Set(vaults.map { sanitizeFolder($0.name).lowercased() })
        var candidate = base
        var counter = 2
        while usedFolders.contains(sanitizeFolder(candidate).lowercased()) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    private func scanNotes(in vault: Vault, warnings: inout [String]) -> [Note] {
        let folder = vaultFolder(vault)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                              includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                              options: [.skipsHiddenFiles]) else {
            warnings.append("无法遍历工作区目录：\(folder.lastPathComponent)")
            return []
        }
        var result: [Note] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let parentName = url.deletingLastPathComponent().lastPathComponent
            if parentName == "思维导图" || parentName == "白板" || parentName == "attachments" { continue }
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                warnings.append("无法读取笔记「\(url.lastPathComponent)」：\(error.localizedDescription)")
                continue
            }
            let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
            if let note = NoteCodec.decode(text: text, relativePath: relative, vaultID: vault.id,
                                           fallbackNotebook: url.deletingLastPathComponent().lastPathComponent,
                                           fileDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()) {
                result.append(note)
            } else {
                warnings.append("无法解析笔记「\(url.lastPathComponent)」")
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadMaps(in vault: Vault, warnings: inout [String]) -> [MindMap] {
        let folder = vaultFolder(vault).appendingPathComponent("思维导图")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch {
            warnings.append("无法读取思维导图目录：\(error.localizedDescription)")
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> MindMap? in
            do {
                let data = try Data(contentsOf: url)
                var map = try JSONDecoder().decode(MindMap.self, from: data)
                map.vaultID = vault.id
                return map
            } catch {
                warnings.append("导图「\(url.lastPathComponent)」解析失败：\(error.localizedDescription)")
                return nil
            }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadCanvases(in vault: Vault, warnings: inout [String]) -> [CanvasBoard] {
        let folder = vaultFolder(vault).appendingPathComponent("白板")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch {
            warnings.append("无法读取白板目录：\(error.localizedDescription)")
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> CanvasBoard? in
            do {
                let data = try Data(contentsOf: url)
                var board = try JSONDecoder().decode(CanvasBoard.self, from: data)
                board.vaultID = vault.id
                return board
            } catch {
                warnings.append("白板「\(url.lastPathComponent)」解析失败：\(error.localizedDescription)")
                return nil
            }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Session storage

    func readSession() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func writeSession(tabs: [WorkspaceTab], selectedID: String, activeVaultID: String, primaryWindow: Bool) {
        guard !isSnapshot else { return }
        var snapshot = readSession() ?? SessionSnapshot()
        var sessions = snapshot.vaultSessions ?? [:]
        sessions[activeVaultID] = VaultTabSession(tabs: tabs, selectedID: selectedID)
        snapshot.vaultSessions = sessions
        if primaryWindow {
            snapshot.tabs = tabs
            snapshot.selectedID = selectedID
            snapshot.activeVaultID = activeVaultID
        } else if snapshot.activeVaultID == nil {
            snapshot.activeVaultID = activeVaultID
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try LexiSafeIO.atomicWriteData(data, to: sessionURL, hook: writeHook)
        } catch {
            saveState = .failed(LexiSafeIO.friendlyWriteError(error, target: "窗口会话"))
        }
    }

    // MARK: Persistence & autosave

    private func startAutosave() {
        guard !isSnapshot else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushDirty()
            }
        }
    }

    func hasDirtyNote(_ id: String) -> Bool {
        dirtyNotes[id] != nil || unsavedManualNotes.contains(id)
    }

    func noteLastSavedDate(for id: String) -> Date? {
        noteLastSavedDates[id]
    }

    func dirtyNoteIDs() -> [String] {
        Array(Set(dirtyNotes.keys).union(unsavedManualNotes))
    }

    func noteHash(for id: String) -> String? {
        guard let note = notes.first(where: { $0.id == id }) else { return nil }
        return NoteHistoryHash.computeNoteHash(note)
    }

    func noteHashFrom(title: String, content: String, tags: [String], properties: [NoteProperty]) -> String {
        NoteHistoryHash.computeSnapshotHash(title: title, content: content, tags: tags, properties: properties)
    }

    func syncBaseFromNote(_ note: Note, windowID: UUID) {
        lastEditorWindowID[note.id] = windowID
    }

    func checkConcurrentWindowEdit(noteID: String,
                                   windowID: UUID,
                                   expectedBaseHash: String?,
                                   proposedTitle: String,
                                   proposedContent: String,
                                   proposedTags: [String],
                                   proposedProperties: [NoteProperty]) -> NoteConflictInfo? {
        guard let current = notes.first(where: { $0.id == noteID }) else { return nil }
        let currentHash = NoteHistoryHash.computeNoteHash(current)
        let proposedHash = NoteHistoryHash.computeSnapshotHash(title: proposedTitle,
                                                               content: proposedContent,
                                                               tags: proposedTags,
                                                               properties: proposedProperties)
        guard let expected = expectedBaseHash,
              expected != currentHash,
              let lastWindow = lastEditorWindowID[noteID],
              lastWindow != windowID,
              proposedHash != currentHash else {
            return nil
        }

        // Preserve both competing versions into history before refusing silent overwrite.
        _ = historyStore.recordRevision(for: current, reason: .autosave, policy: historyPolicy)
        var mineCopy = current
        mineCopy.title = proposedTitle
        mineCopy.content = proposedContent
        mineCopy.tags = proposedTags
        mineCopy.properties = proposedProperties
        _ = historyStore.recordRevision(for: mineCopy, reason: .conflictBackup, policy: historyPolicy)

        let conflict = NoteConflictInfo(
            noteID: noteID,
            sourceLabel: "多窗口并发编辑",
            mineTitle: proposedTitle,
            mineContent: proposedContent,
            mineTags: proposedTags,
            mineProperties: proposedProperties,
            mineNotebook: current.notebook,
            theirsTitle: current.title,
            theirsContent: current.content,
            theirsTags: current.tags,
            theirsProperties: current.properties,
            theirsNotebook: current.notebook,
            detectedAt: Date()
        )
        pendingConflicts[noteID] = conflict
        saveState = .failed("检测到其他窗口对「\(current.displayTitle)」的并发修改，已保留双方版本等待处理")
        return conflict
    }

    func scheduleSave(_ id: String,
                      autoSave: Bool,
                      fallbackNotebook: String,
                      windowID: UUID? = nil) {
        if let windowID {
            lastEditorWindowID[id] = windowID
        }
        pendingWalNotes[id] = fallbackNotebook
        scheduleWalFlush()
        if autoSave {
            unsavedManualNotes.remove(id)
            dirtyNotes[id] = fallbackNotebook
            saveState = .saving
        } else {
            unsavedManualNotes.insert(id)
            saveState = .unsaved
        }
    }

    private func scheduleWalFlush() {
        guard !isSnapshot else { return }
        walDebounceTask?.cancel()
        walDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            self.flushCrashWalNow()
        }
    }

    func flushCrashWalNow() {
        walDebounceTask?.cancel()
        let ids = Array(Set(Array(pendingWalNotes.keys) + Array(dirtyNotes.keys) + Array(unsavedManualNotes)))
        for id in ids {
            guard let note = notes.first(where: { $0.id == id }) else {
                pendingWalNotes.removeValue(forKey: id)
                continue
            }
            let baseHash = diskBaseHashes[id] ?? NoteHistoryHash.computeNoteHash(note)
            let draft = CrashRecoveryDraft(
                noteID: note.id,
                vaultID: note.vaultID,
                title: note.title,
                content: note.content,
                tags: note.tags,
                properties: note.properties,
                notebook: note.notebook,
                baseHash: baseHash,
                updatedAt: Date()
            )
            _ = historyStore.writeWalDraft(draft)
            pendingWalNotes.removeValue(forKey: id)
        }
    }

    func flushDirty() {
        guard !dirtyNotes.isEmpty else { return }
        let items = dirtyNotes
        var remaining: [String: String] = [:]
        var firstError: String?

        for (id, fallbackNotebook) in items {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            switch persistWithOutcome(notes[index], fallbackNotebook: fallbackNotebook) {
            case .saved(let updated):
                if let currentIdx = notes.firstIndex(where: { $0.id == id }),
                   updated.path != notes[currentIdx].path {
                    notes[currentIdx].path = updated.path
                }
                unsavedManualNotes.remove(id)
                noteLastSavedDates[id] = Date()
            case .conflict(let info):
                remaining[id] = fallbackNotebook
                if firstError == nil {
                    firstError = "检测到冲突：\(info.sourceLabel)"
                }
            case .failed(let message):
                remaining[id] = fallbackNotebook
                if firstError == nil {
                    firstError = message
                }
            }
        }

        dirtyNotes = remaining
        if let firstError {
            saveState = .failed(firstError)
        } else {
            saveState = .saved(Date())
        }
    }

    func flushAllNotes(fallbackNotebook: String = "笔记") {
        flushCrashWalNow()
        var firstError: String?
        var remaining: [String: String] = [:]
        let dirtySet = Set(dirtyNotes.keys)

        for note in notes where !note.isTrashed || dirtySet.contains(note.id) {
            let nb = dirtyNotes[note.id] ?? fallbackNotebook
            switch persistWithOutcome(note, fallbackNotebook: nb) {
            case .saved(let updated):
                if let idx = notes.firstIndex(where: { $0.id == note.id }),
                   updated.path != notes[idx].path {
                    notes[idx].path = updated.path
                }
                unsavedManualNotes.remove(note.id)
                noteLastSavedDates[note.id] = Date()
            case .conflict(let info):
                remaining[note.id] = nb
                if firstError == nil { firstError = "检测到冲突：\(info.sourceLabel)" }
            case .failed(let message):
                remaining[note.id] = nb
                if firstError == nil { firstError = message }
            }
        }

        dirtyNotes = remaining
        if let firstError {
            saveState = .failed(firstError)
        } else {
            saveState = .saved(Date())
        }
    }

    @discardableResult
    func saveNoteNow(_ id: String, fallbackNotebook: String, forceOverwrite: Bool = false) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        switch persistWithOutcome(notes[index], fallbackNotebook: fallbackNotebook, forceOverwrite: forceOverwrite) {
        case .saved(let updated):
            if let currentIdx = notes.firstIndex(where: { $0.id == id }),
               updated.path != notes[currentIdx].path {
                notes[currentIdx].path = updated.path
            }
            dirtyNotes.removeValue(forKey: id)
            unsavedManualNotes.remove(id)
            pendingWalNotes.removeValue(forKey: id)
            let now = Date()
            noteLastSavedDates[id] = now
            saveState = .saved(now)
            return true
        case .conflict(let info):
            dirtyNotes[id] = fallbackNotebook
            saveState = .failed("检测到冲突（\(info.sourceLabel)），已暂停覆盖")
            return false
        case .failed(let message):
            dirtyNotes[id] = fallbackNotebook
            saveState = .failed(message)
            return false
        }
    }

    @discardableResult
    func persist(_ note: Note, fallbackNotebook: String) -> Note {
        switch persistWithOutcome(note, fallbackNotebook: fallbackNotebook) {
        case .saved(let updated):
            return updated
        case .conflict, .failed:
            return note
        }
    }

    func persistWithOutcome(_ note: Note,
                            fallbackNotebook: String,
                            forceOverwrite: Bool = false) -> PersistOutcome {
        guard !isSnapshot else { return .saved(note) }
        guard let vault = vault(note.vaultID) else {
            return .failed("找不到目标工作区")
        }
        var updated = note
        let folderName = sanitizeFolder(updated.notebook.isEmpty ? fallbackNotebook : updated.notebook)
        let vaultDir = vaultFolder(vault)
        let folderURL = vaultDir.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            let msg = LexiSafeIO.friendlyWriteError(error, target: folderName)
            saveState = .failed(msg)
            return .failed(msg)
        }

        let baseName = sanitizeFileName(updated.displayTitle)
        var fileName = baseName + ".md"
        var relative = "\(folderName)/\(fileName)"
        var target = vaultDir.appendingPathComponent(relative)

        if !updated.path.isEmpty {
            let oldURL = vaultDir.appendingPathComponent(updated.path)
            if oldURL.path != target.path, FileManager.default.fileExists(atPath: oldURL.path) {
                if FileManager.default.fileExists(atPath: target.path) {
                    // Do not clobber another note; keep the existing file name.
                    relative = updated.path
                    target = vaultDir.appendingPathComponent(relative)
                } else {
                    do {
                        try FileManager.default.moveItem(at: oldURL, to: target)
                    } catch {
                        let msg = LexiSafeIO.friendlyWriteError(error, target: fileName)
                        saveState = .failed(msg)
                        return .failed(msg)
                    }
                }
            } else if !FileManager.default.fileExists(atPath: target.path) {
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    relative = updated.path
                    target = oldURL
                }
            }
        } else {
            var counter = 2
            while FileManager.default.fileExists(atPath: target.path) {
                fileName = "\(baseName) \(counter).md"
                relative = "\(folderName)/\(fileName)"
                target = vaultDir.appendingPathComponent(relative)
                counter += 1
            }
        }

        let newHash = NoteHistoryHash.computeNoteHash(updated)

        // Check for external disk modification before overwriting existing file.
        if !forceOverwrite,
           FileManager.default.fileExists(atPath: target.path),
           let expectedDiskHash = diskBaseHashes[updated.id],
           let diskText = try? String(contentsOf: target, encoding: .utf8) {
            let decodedDisk = NoteCodec.decode(
                text: diskText,
                relativePath: relative,
                vaultID: vault.id,
                fallbackNotebook: folderName,
                fileDate: Date()
            )
            let diskHash = decodedDisk.map { NoteHistoryHash.computeNoteHash($0) }
                ?? NoteHistoryHash.computeSnapshotHash(title: "", content: diskText, tags: [])
            if diskHash != expectedDiskHash && diskHash != newHash {
                if let diskNote = decodedDisk {
                    _ = historyStore.recordRevision(for: diskNote, reason: .autosave, policy: historyPolicy)
                }
                _ = historyStore.recordRevision(for: updated, reason: .conflictBackup, policy: historyPolicy)
                let info = NoteConflictInfo(
                    noteID: updated.id,
                    sourceLabel: "外部磁盘文件已被修改",
                    mineTitle: updated.title,
                    mineContent: updated.content,
                    mineTags: updated.tags,
                    mineProperties: updated.properties,
                    mineNotebook: updated.notebook,
                    theirsTitle: decodedDisk?.title ?? updated.title,
                    theirsContent: decodedDisk?.content ?? diskText,
                    theirsTags: decodedDisk?.tags ?? [],
                    theirsProperties: decodedDisk?.properties ?? [],
                    theirsNotebook: decodedDisk?.notebook ?? updated.notebook,
                    detectedAt: Date()
                )
                pendingConflicts[updated.id] = info
                let msg = "检测到「\(updated.displayTitle)」在磁盘上已被外部修改，已暂停覆盖并保留备份"
                saveState = .failed(msg)
                return .conflict(info)
            }
        }

        updated.path = relative
        let text = NoteCodec.encode(updated)
        do {
            try LexiSafeIO.atomicWriteText(text, to: target, hook: writeHook)
        } catch {
            let msg = LexiSafeIO.friendlyWriteError(error, target: updated.displayTitle)
            saveState = .failed(msg)
            return .failed(msg)
        }

        // Preserve previous committed snapshot first if this is the first edit since load/commit.
        if let prior = committedNotes[updated.id],
           NoteHistoryHash.computeNoteHash(prior) != newHash {
            _ = historyStore.recordRevision(for: prior, reason: .autosave, policy: historyPolicy)
        }
        _ = historyStore.recordRevision(for: updated, reason: .autosave, policy: historyPolicy)

        diskBaseHashes[updated.id] = newHash
        committedNotes[updated.id] = updated
        historyStore.clearWalDraft(for: updated.id)
        pendingWalNotes.removeValue(forKey: updated.id)
        return .saved(updated)
    }

    // MARK: Version History, Restore, Conflict & Recovery

    func revisions(for noteID: String) -> [NoteRevision] {
        historyStore.revisions(for: noteID)
    }

    @discardableResult
    func createManualSnapshot(for noteID: String) -> (revision: NoteRevision?, warning: String?) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return (nil, "找不到目标笔记") }
        return historyStore.recordRevision(for: note, reason: .manual, policy: historyPolicy)
    }

    @discardableResult
    func restoreNoteRevision(noteID: String, revisionID: String, fallbackNotebook: String) -> (ok: Bool, error: String?) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return (false, "找不到目标笔记")
        }
        guard let targetRevision = historyStore.revisions(for: noteID).first(where: { $0.id == revisionID }) else {
            return (false, "找不到指定的历史版本")
        }

        // Auto-preserve both prior committed version and current unsaved live draft before restoring.
        if let priorCommitted = committedNotes[noteID],
           NoteHistoryHash.computeNoteHash(priorCommitted) != NoteHistoryHash.computeNoteHash(notes[index]) {
            _ = historyStore.recordRevision(for: priorCommitted, reason: .autosave, policy: historyPolicy)
        }
        _ = historyStore.recordRevision(for: notes[index], reason: .restoreBackup, policy: historyPolicy)

        var restored = notes[index]
        restored.title = targetRevision.title
        restored.content = targetRevision.content
        restored.tags = targetRevision.tags
        restored.properties = targetRevision.properties
        if !targetRevision.notebook.isEmpty {
            restored.notebook = targetRevision.notebook
        }
        restored.updatedAt = Date()

        switch persistWithOutcome(restored, fallbackNotebook: fallbackNotebook, forceOverwrite: true) {
        case .saved(let savedNote):
            notes[index] = savedNote
            dirtyNotes.removeValue(forKey: noteID)
            pendingConflicts.removeValue(forKey: noteID)
            recoveredDrafts.removeAll { $0.noteID == noteID }
            saveState = .saved(Date())
            return (true, nil)
        case .conflict(let info):
            return (false, "恢复前遇到冲突：\(info.sourceLabel)")
        case .failed(let message):
            return (false, message)
        }
    }

    func resolveConflict(noteID: String,
                         mode: ConflictResolutionMode,
                         fallbackNotebook: String,
                         windowID: UUID) -> Note? {
        guard let conflict = pendingConflicts[noteID],
              let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return nil
        }

        var current = notes[index]
        switch mode {
        case .keepMineBackupTheirs:
            var theirsNote = current
            theirsNote.title = conflict.theirsTitle
            theirsNote.content = conflict.theirsContent
            theirsNote.tags = conflict.theirsTags
            theirsNote.properties = conflict.theirsProperties
            theirsNote.notebook = conflict.theirsNotebook
            _ = historyStore.recordRevision(for: theirsNote, reason: .conflictBackup, policy: historyPolicy)

            current.title = conflict.mineTitle
            current.content = conflict.mineContent
            current.tags = conflict.mineTags
            current.properties = conflict.mineProperties
            current.notebook = conflict.mineNotebook
            current.updatedAt = Date()
            if case .saved(let saved) = persistWithOutcome(current, fallbackNotebook: fallbackNotebook, forceOverwrite: true) {
                notes[index] = saved
                dirtyNotes.removeValue(forKey: noteID)
                pendingConflicts.removeValue(forKey: noteID)
                lastEditorWindowID[noteID] = windowID
                saveState = .saved(Date())
                return saved
            }
            return nil

        case .takeTheirsBackupMine:
            var mineNote = current
            mineNote.title = conflict.mineTitle
            mineNote.content = conflict.mineContent
            mineNote.tags = conflict.mineTags
            mineNote.properties = conflict.mineProperties
            mineNote.notebook = conflict.mineNotebook
            _ = historyStore.recordRevision(for: mineNote, reason: .conflictBackup, policy: historyPolicy)

            current.title = conflict.theirsTitle
            current.content = conflict.theirsContent
            current.tags = conflict.theirsTags
            current.properties = conflict.theirsProperties
            current.notebook = conflict.theirsNotebook
            current.updatedAt = Date()
            if case .saved(let saved) = persistWithOutcome(current, fallbackNotebook: fallbackNotebook, forceOverwrite: true) {
                notes[index] = saved
                dirtyNotes.removeValue(forKey: noteID)
                pendingConflicts.removeValue(forKey: noteID)
                lastEditorWindowID[noteID] = windowID
                saveState = .saved(Date())
                return saved
            }
            return nil

        case .saveConflictCopy:
            var mineBackup = current
            mineBackup.title = conflict.mineTitle
            mineBackup.content = conflict.mineContent
            mineBackup.tags = conflict.mineTags
            mineBackup.properties = conflict.mineProperties
            _ = historyStore.recordRevision(for: mineBackup, reason: .conflictBackup, policy: historyPolicy)

            // Ensure original stays cleanly at theirs
            current.title = conflict.theirsTitle
            current.content = conflict.theirsContent
            current.tags = conflict.theirsTags
            current.properties = conflict.theirsProperties
            current.notebook = conflict.theirsNotebook
            if case .saved(let savedOriginal) = persistWithOutcome(current, fallbackNotebook: fallbackNotebook, forceOverwrite: true) {
                notes[index] = savedOriginal
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "MMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            let copyTitle = "\(conflict.mineTitle.isEmpty ? "无标题笔记" : conflict.mineTitle) (冲突副本 \(stamp))"
            let copy = Note(
                vaultID: current.vaultID,
                notebook: conflict.mineNotebook.isEmpty ? fallbackNotebook : conflict.mineNotebook,
                type: current.type,
                level: current.level,
                title: copyTitle,
                content: conflict.mineContent,
                tags: conflict.mineTags,
                properties: conflict.mineProperties
            )
            notes.insert(copy, at: 0)
            if case .saved(let savedCopy) = persistWithOutcome(copy, fallbackNotebook: fallbackNotebook, forceOverwrite: true),
               let copyIdx = notes.firstIndex(where: { $0.id == copy.id }) {
                notes[copyIdx] = savedCopy
                dirtyNotes.removeValue(forKey: noteID)
                pendingConflicts.removeValue(forKey: noteID)
                lastEditorWindowID[noteID] = windowID
                lastEditorWindowID[savedCopy.id] = windowID
                saveState = .saved(Date())
                return savedCopy
            }
            return nil
        }
    }

    func dismissCrashRecovery(for noteID: String) {
        recoveredDrafts.removeAll { $0.noteID == noteID }
        historyStore.clearWalDraft(for: noteID)
    }

    func revertCrashRecovery(for noteID: String, fallbackNotebook: String) -> Bool {
        recoveredDrafts.removeAll { $0.noteID == noteID }
        historyStore.clearWalDraft(for: noteID)
        // Restore to latest non-crash-recovery revision if available
        let candidates = historyStore.revisions(for: noteID).filter { $0.reason != .crashRecovery }
        guard let prior = candidates.first else { return false }
        return restoreNoteRevision(noteID: noteID, revisionID: prior.id, fallbackNotebook: fallbackNotebook).ok
    }

    func historyUsage() -> HistoryUsageSummary {
        historyStore.usageSummary()
    }

    @discardableResult
    func pruneHistoryNow() -> HistoryUsageSummary {
        historyStore.pruneAll(policy: historyPolicy)
    }

    func deleteHistory(for noteID: String) {
        historyStore.deleteHistory(for: noteID)
        dirtyNotes.removeValue(forKey: noteID)
        pendingWalNotes.removeValue(forKey: noteID)
        diskBaseHashes.removeValue(forKey: noteID)
        committedNotes.removeValue(forKey: noteID)
        pendingConflicts.removeValue(forKey: noteID)
        recoveredDrafts.removeAll { $0.noteID == noteID }
    }

    private func recoverCrashWalDrafts(into loadedNotes: inout [Note], vaults: [Vault]) -> [CrashRecoveryDraft] {
        let drafts = historyStore.loadAllWalDrafts()
        guard !drafts.isEmpty else { return [] }
        var recovered: [CrashRecoveryDraft] = []

        for draft in drafts {
            let walHash = NoteHistoryHash.computeSnapshotHash(
                title: draft.title,
                content: draft.content,
                tags: draft.tags,
                properties: draft.properties
            )
            if let idx = loadedNotes.firstIndex(where: { $0.id == draft.noteID }) {
                let diskNote = loadedNotes[idx]
                let diskHash = NoteHistoryHash.computeNoteHash(diskNote)
                if walHash == diskHash {
                    historyStore.clearWalDraft(for: draft.noteID)
                    continue
                }
                _ = historyStore.recordRevision(for: diskNote, reason: .autosave, policy: historyPolicy)
                loadedNotes[idx].title = draft.title
                loadedNotes[idx].content = draft.content
                loadedNotes[idx].tags = draft.tags
                loadedNotes[idx].properties = draft.properties
                if !draft.notebook.isEmpty {
                    loadedNotes[idx].notebook = draft.notebook
                }
                loadedNotes[idx].updatedAt = draft.updatedAt
                dirtyNotes[draft.noteID] = loadedNotes[idx].notebook.isEmpty ? "笔记" : loadedNotes[idx].notebook
                _ = historyStore.recordRevision(for: loadedNotes[idx], reason: .crashRecovery, policy: historyPolicy)
                recovered.append(draft)
            } else {
                let targetVaultID = vaults.first(where: { $0.id == draft.vaultID })?.id
                    ?? vaults.first?.id
                    ?? "default-vault"
                let reconstructed = Note(
                    id: draft.noteID,
                    vaultID: targetVaultID,
                    notebook: draft.notebook.isEmpty ? "笔记" : draft.notebook,
                    title: draft.title,
                    content: draft.content,
                    tags: draft.tags,
                    properties: draft.properties,
                    createdAt: draft.updatedAt,
                    updatedAt: draft.updatedAt
                )
                loadedNotes.insert(reconstructed, at: 0)
                dirtyNotes[draft.noteID] = reconstructed.notebook
                _ = historyStore.recordRevision(for: reconstructed, reason: .crashRecovery, policy: historyPolicy)
                recovered.append(draft)
            }
        }
        return recovered
    }

    func saveMap(_ map: MindMap) {
        guard !isSnapshot, let vault = vault(map.vaultID) else { return }
        let folder = vaultFolder(vault).appendingPathComponent("思维导图", isDirectory: true)
        let url = folder.appendingPathComponent("\(map.id).mindmap.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(map)
            try LexiSafeIO.atomicWriteData(data, to: url, hook: writeHook)
        } catch {
            saveState = .failed(LexiSafeIO.friendlyWriteError(error, target: map.title))
        }
    }

    func saveCanvas(_ board: CanvasBoard) {
        guard !isSnapshot, let vault = vault(board.vaultID) else { return }
        let folder = vaultFolder(vault).appendingPathComponent("白板", isDirectory: true)
        let url = folder.appendingPathComponent("\(board.id).canvas.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(board)
            try LexiSafeIO.atomicWriteData(data, to: url, hook: writeHook)
        } catch {
            saveState = .failed(LexiSafeIO.friendlyWriteError(error, target: board.title))
        }
    }

    func importAttachment(from sourceURL: URL, for note: Note?, in vault: Vault) -> (relativePath: String, fileName: String, isImage: Bool)? {
        let root = vaultFolder(vault)
        let attachmentsDir = root.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension
        let rawBase = sourceURL.deletingPathExtension().lastPathComponent
        let base = sanitizeFileName(rawBase.isEmpty ? "attachment" : rawBase)
        var targetName = ext.isEmpty ? base : "\(base).\(ext)"
        var counter = 1
        while FileManager.default.fileExists(atPath: attachmentsDir.appendingPathComponent(targetName).path) {
            targetName = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        let destURL = attachmentsDir.appendingPathComponent(targetName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            return nil
        }

        let noteDir: URL
        if let note, !note.path.isEmpty {
            noteDir = root.appendingPathComponent(note.path).deletingLastPathComponent()
        } else if let note, !note.notebook.isEmpty, note.notebook != "默认" {
            noteDir = root.appendingPathComponent(sanitizeFolder(note.notebook), isDirectory: true)
        } else {
            noteDir = root
        }
        let noteComponents = noteDir.standardizedFileURL.pathComponents
        let destComponents = destURL.standardizedFileURL.pathComponents
        var common = 0
        while common < noteComponents.count && common < destComponents.count && noteComponents[common] == destComponents[common] {
            common += 1
        }
        let upCount = max(0, noteComponents.count - common)
        let relParts = Array(repeating: "..", count: upCount) + Array(destComponents.dropFirst(common))
        let relPath = relParts.joined(separator: "/")
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic", "tiff"]
        return (relPath, targetName, imageExts.contains(ext.lowercased()))
    }

    func sanitizeFolder(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "笔记" : cleaned
    }

    func sanitizeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        var cleaned = value.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "无标题笔记" }
        if cleaned.count > 80 { cleaned = String(cleaned.prefix(80)) }
        return cleaned
    }
}
