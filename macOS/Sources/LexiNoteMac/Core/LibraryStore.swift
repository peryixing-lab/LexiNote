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

@MainActor
final class LibraryStore: ObservableObject {
    let storageRoot: URL
    let isSnapshot: Bool

    @Published var vaults: [Vault] = []
    @Published var notes: [Note] = []
    @Published var maps: [MindMap] = []
    @Published var canvases: [CanvasBoard] = []
    @Published var saveState: SaveState = .saved(Date())

    private var dirtyNotes: [String: String] = [:]
    private var autosaveTimer: Timer?

    init(storageRoot: URL? = nil, inMemory: Bool = false, seedDemo: Bool = true) {
        self.isSnapshot = inMemory
        let root = storageRoot ?? LibraryStore.defaultStorageRoot()
        self.storageRoot = root
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
            self.saveState = .saved(Date())
        } else {
            prepareStorage()
            loadLibrary()
        }
        startAutosave()
    }

    deinit {
        autosaveTimer?.invalidate()
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

    private func loadLibrary() {
        var loadedVaults: [Vault] = []
        if let data = try? Data(contentsOf: libraryURL),
           let decoded = try? JSONDecoder().decode([Vault].self, from: data) {
            loadedVaults = decoded
        }
        if loadedVaults.isEmpty {
            // A fresh install starts with one empty workspace and no documents.
            loadedVaults = [Vault(id: "default-vault", name: "我的工作区",
                                  detail: "本地优先的知识库", createdAt: Date())]
            saveVaults(loadedVaults)
        }
        vaults = loadedVaults

        var loadedNotes: [Note] = []
        for vault in loadedVaults {
            let folder = vaultFolder(vault)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            loadedNotes.append(contentsOf: scanNotes(in: vault))
        }

        var loadedMaps: [MindMap] = []
        var loadedCanvases: [CanvasBoard] = []
        for vault in loadedVaults {
            loadedMaps.append(contentsOf: loadMaps(in: vault))
            loadedCanvases.append(contentsOf: loadCanvases(in: vault))
        }

        notes = loadedNotes
        maps = loadedMaps
        canvases = loadedCanvases
    }

    func saveVaults(_ list: [Vault]? = nil) {
        guard !isSnapshot else { return }
        let target = list ?? vaults
        if let data = try? JSONEncoder().encode(target) {
            try? data.write(to: libraryURL, options: .atomic)
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

    private func scanNotes(in vault: Vault) -> [Note] {
        let folder = vaultFolder(vault)
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                              includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var result: [Note] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            if url.deletingLastPathComponent().lastPathComponent == "思维导图" { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
            if let note = NoteCodec.decode(text: text, relativePath: relative, vaultID: vault.id,
                                           fallbackNotebook: url.deletingLastPathComponent().lastPathComponent,
                                           fileDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()) {
                result.append(note)
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadMaps(in vault: Vault) -> [MindMap] {
        let folder = vaultFolder(vault).appendingPathComponent("思维导图")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> MindMap? in
            guard let data = try? Data(contentsOf: url),
                  var map = try? JSONDecoder().decode(MindMap.self, from: data) else { return nil }
            map.vaultID = vault.id
            return map
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadCanvases(in vault: Vault) -> [CanvasBoard] {
        let folder = vaultFolder(vault).appendingPathComponent("白板")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> CanvasBoard? in
            guard let data = try? Data(contentsOf: url),
                  var board = try? JSONDecoder().decode(CanvasBoard.self, from: data) else { return nil }
            board.vaultID = vault.id
            return board
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
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: sessionURL, options: .atomic)
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

    func scheduleSave(_ id: String, autoSave: Bool, fallbackNotebook: String) {
        if autoSave {
            dirtyNotes[id] = fallbackNotebook
            saveState = .saving
        } else {
            saveState = .unsaved
        }
    }

    func flushDirty() {
        guard !dirtyNotes.isEmpty else { return }
        let items = dirtyNotes
        dirtyNotes.removeAll()
        var failed: String?
        for (id, fallbackNotebook) in items {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            let updated = persist(notes[index], fallbackNotebook: fallbackNotebook)
            if updated.path != notes[index].path {
                notes[index].path = updated.path
            }
            if updated.id.isEmpty { failed = "保存失败" }
        }
        if let failed {
            saveState = .failed(failed)
        } else {
            saveState = .saved(Date())
        }
    }

    func flushAllNotes(fallbackNotebook: String = "笔记") {
        for note in notes where !note.isTrashed {
            _ = persist(note, fallbackNotebook: fallbackNotebook)
        }
        dirtyNotes.removeAll()
    }

    @discardableResult
    func saveNoteNow(_ id: String, fallbackNotebook: String) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let updated = persist(notes[index], fallbackNotebook: fallbackNotebook)
        if updated.path != notes[index].path { notes[index].path = updated.path }
        dirtyNotes.removeValue(forKey: id)
        saveState = .saved(Date())
        return true
    }

    @discardableResult
    func persist(_ note: Note, fallbackNotebook: String) -> Note {
        guard !isSnapshot else { return note }
        guard let vault = vault(note.vaultID) else { return note }
        var updated = note
        let folderName = sanitizeFolder(updated.notebook.isEmpty ? fallbackNotebook : updated.notebook)
        let vaultDir = vaultFolder(vault)
        let folderURL = vaultDir.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

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
                    try? FileManager.default.moveItem(at: oldURL, to: target)
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
        updated.path = relative
        let text = NoteCodec.encode(updated)
        do {
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            saveState = .failed("无法写入 \(relative)")
        }
        return updated
    }

    func saveMap(_ map: MindMap) {
        guard !isSnapshot, let vault = vault(map.vaultID) else { return }
        let folder = vaultFolder(vault).appendingPathComponent("思维导图", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(map.id).mindmap.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(map) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func saveCanvas(_ board: CanvasBoard) {
        guard !isSnapshot, let vault = vault(board.vaultID) else { return }
        let folder = vaultFolder(vault).appendingPathComponent("白板", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(board.id).canvas.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(board) {
            try? data.write(to: url, options: .atomic)
        }
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
