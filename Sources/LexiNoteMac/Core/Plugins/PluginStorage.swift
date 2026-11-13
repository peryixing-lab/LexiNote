import Foundation

final class PluginStorage {
    private(set) var rootURL: URL
    private let ephemeral: Bool
    private var memoryRegistry: [PluginRecord] = []
    private var memoryEnabled: [String: [String]] = [:]
    private var memoryPermissions: [String: [String: PluginPermissionGrant]] = [:]
    private var memoryPluginData: [String: [String: [String: String]]] = [:]
    private var memoryFiles: [String: [String: Data]] = [:]

    init(storageRoot: URL, ephemeral: Bool = false) {
        self.rootURL = storageRoot.appendingPathComponent(".plugins", isDirectory: true)
        self.ephemeral = ephemeral
        if !ephemeral {
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    func updateRoot(storageRoot: URL) {
        guard !ephemeral else { return }
        self.rootURL = storageRoot.appendingPathComponent(".plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func safeKey(_ value: String) -> String {
        value.map { ch in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." ? ch : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private func workspaceDir(_ workspaceID: String) -> URL {
        rootURL.appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(Self.safeKey(workspaceID), isDirectory: true)
    }

    private var registryURL: URL {
        rootURL.appendingPathComponent("registry.json")
    }

    func pluginFolder(pluginId: String) -> URL {
        rootURL.appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(Self.safeKey(pluginId), isDirectory: true)
    }

    // MARK: - Registry

    func loadRegistry() -> [PluginRecord] {
        if ephemeral { return memoryRegistry }
        guard let data = try? Data(contentsOf: registryURL),
              let records = try? JSONDecoder().decode([PluginRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.manifest.name < $1.manifest.name }
    }

    func saveRegistry(_ records: [PluginRecord]) {
        if ephemeral {
            memoryRegistry = records
            return
        }
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    // MARK: - Extracted Bundle Files

    func installFiles(pluginId: String, entries: [ZipExtractedEntry]) throws {
        if ephemeral {
            var map: [String: Data] = [:]
            for entry in entries { map[entry.relativePath] = entry.data }
            memoryFiles[pluginId] = map
            return
        }
        let fm = FileManager.default
        let staging = rootURL.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let target = pluginFolder(pluginId: pluginId)
        defer { try? fm.removeItem(at: staging) }

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for entry in entries {
                let dest = staging.appendingPathComponent(entry.relativePath)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: dest, options: .atomic)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: staging, to: target)
        } catch {
            throw PluginHostError(PluginErrorCode.io, "写入插件文件失败：\(error.localizedDescription)")
        }
    }

    func removeFiles(pluginId: String) {
        if ephemeral {
            memoryFiles.removeValue(forKey: pluginId)
            return
        }
        try? FileManager.default.removeItem(at: pluginFolder(pluginId: pluginId))
    }

    func readPluginFile(pluginId: String, relativePath: String) -> Data? {
        guard let clean = PluginZip.sanitizeRelativePath(relativePath) else { return nil }
        if ephemeral {
            return memoryFiles[pluginId]?[clean]
        }
        let url = pluginFolder(pluginId: pluginId).appendingPathComponent(clean)
        return try? Data(contentsOf: url)
    }

    // MARK: - Per-Workspace Enablement

    func loadEnabledPlugins(workspaceID: String) -> [String] {
        if ephemeral { return memoryEnabled[workspaceID] ?? [] }
        let url = workspaceDir(workspaceID).appendingPathComponent("enabled.json")
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    func saveEnabledPlugins(workspaceID: String, ids: [String]) {
        if ephemeral {
            memoryEnabled[workspaceID] = ids
            return
        }
        let dir = workspaceDir(workspaceID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(Set(ids)).sorted()) {
            try? data.write(to: dir.appendingPathComponent("enabled.json"), options: .atomic)
        }
    }

    // MARK: - Per-Workspace Permissions (Deny-by-default)

    func loadPermissionGrant(workspaceID: String, pluginId: String) -> PluginPermissionGrant {
        if ephemeral {
            return memoryPermissions[workspaceID]?[pluginId] ?? PluginPermissionGrant()
        }
        let url = workspaceDir(workspaceID)
            .appendingPathComponent("permissions", isDirectory: true)
            .appendingPathComponent("\(Self.safeKey(pluginId)).json")
        guard let data = try? Data(contentsOf: url),
              let grant = try? JSONDecoder().decode(PluginPermissionGrant.self, from: data) else {
            return PluginPermissionGrant()
        }
        return grant
    }

    func savePermissionGrant(workspaceID: String, pluginId: String, grant: PluginPermissionGrant) {
        if ephemeral {
            var ws = memoryPermissions[workspaceID] ?? [:]
            ws[pluginId] = grant
            memoryPermissions[workspaceID] = ws
            return
        }
        let dir = workspaceDir(workspaceID).appendingPathComponent("permissions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(Self.safeKey(pluginId)).json")
        if let data = try? JSONEncoder().encode(grant) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func clearWorkspaceStateForPlugin(pluginId: String) {
        if ephemeral {
            for ws in memoryEnabled.keys {
                memoryEnabled[ws]?.removeAll { $0 == pluginId }
                memoryPermissions[ws]?.removeValue(forKey: pluginId)
                memoryPluginData[ws]?.removeValue(forKey: pluginId)
            }
            return
        }
        let wsRoot = rootURL.appendingPathComponent("workspaces", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: wsRoot, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            let wsId = dir.lastPathComponent
            var enabled = loadEnabledPlugins(workspaceID: wsId)
            if enabled.contains(pluginId) {
                enabled.removeAll { $0 == pluginId }
                saveEnabledPlugins(workspaceID: wsId, ids: enabled)
            }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("permissions").appendingPathComponent("\(Self.safeKey(pluginId)).json"))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("data").appendingPathComponent("\(Self.safeKey(pluginId)).json"))
        }
    }

    // MARK: - Per-Workspace Isolated Key-Value Data

    func loadPluginDataMap(workspaceID: String, pluginId: String) -> [String: String] {
        if ephemeral {
            return memoryPluginData[workspaceID]?[pluginId] ?? [:]
        }
        let url = workspaceDir(workspaceID)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("\(Self.safeKey(pluginId)).json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    func savePluginDataMap(workspaceID: String, pluginId: String, map: [String: String]) throws {
        guard map.count <= PluginLimits.maxStorageKeys else {
            throw PluginHostError(PluginErrorCode.quotaExceeded, "插件存储键数量超过 \(PluginLimits.maxStorageKeys) 上限")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(map)
        guard encoded.count <= PluginLimits.maxStorageBytes else {
            throw PluginHostError(PluginErrorCode.quotaExceeded, "插件存储空间超过 5 MB 上限")
        }
        if ephemeral {
            var ws = memoryPluginData[workspaceID] ?? [:]
            ws[pluginId] = map
            memoryPluginData[workspaceID] = ws
            return
        }
        let dir = workspaceDir(workspaceID).appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoded.write(to: dir.appendingPathComponent("\(Self.safeKey(pluginId)).json"), options: .atomic)
    }

    func loadPluginDataJsonString(workspaceID: String, pluginId: String) -> String {
        let map = loadPluginDataMap(workspaceID: workspaceID, pluginId: pluginId)
        if let encoded = try? JSONEncoder().encode(map),
           let str = String(data: encoded, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - Plugin AI Bindings & Secrets (Per-Plugin Isolated)

    private var aiDir: URL {
        rootURL.appendingPathComponent("ai", isDirectory: true)
    }

    func loadAiBindingRaw(pluginId: String) -> String? {
        guard !ephemeral else { return nil }
        let url = aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).binding.json")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveAiBindingRaw(pluginId: String, json: String) throws {
        guard !ephemeral else { return }
        try FileManager.default.createDirectory(at: aiDir, withIntermediateDirectories: true)
        let url = aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).binding.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadAiSecret(pluginId: String, profileId: String) -> String {
        guard !ephemeral else { return "" }
        let url = aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).secrets.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ""
        }
        return map[profileId] ?? ""
    }

    func saveAiSecret(pluginId: String, profileId: String, secret: String) {
        guard !ephemeral else { return }
        try? FileManager.default.createDirectory(at: aiDir, withIntermediateDirectories: true)
        let url = aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).secrets.json")
        var map: [String: String] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            map = existing
        }
        if secret.isEmpty {
            map.removeValue(forKey: profileId)
        } else {
            map[profileId] = secret
        }
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func clearAiConfig(pluginId: String) {
        guard !ephemeral else { return }
        try? FileManager.default.removeItem(at: aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).binding.json"))
        try? FileManager.default.removeItem(at: aiDir.appendingPathComponent("\(Self.safeKey(pluginId)).secrets.json"))
    }
}
