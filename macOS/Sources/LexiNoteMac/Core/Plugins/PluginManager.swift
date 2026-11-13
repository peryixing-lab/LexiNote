import Foundation
import SwiftUI
import AppKit

/// Owns installed plugins, per-workspace enablement and deny-by-default capability grants,
/// live sandboxed `WKWebView` runtime sessions, event broadcasting, and the host AI proxy.
@MainActor
final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published private(set) var records: [PluginRecord] = []
    @Published private(set) var enabledIDs: Set<String> = []
    @Published private(set) var logs: [PluginLogEntry] = []
    @Published private(set) var lastStatusMessage: String = ""
    @Published private(set) var permissionRevision: Int = 0

    /// Test hook so automated checks can verify `ui.confirm` without blocking on modal UI.
    var confirmHandlerOverride: ((String, String) -> Bool)?

    private(set) weak var boundModel: AppModel?
    let storage: PluginStorage
    let aiService: PluginAiService

    private lazy var dispatcher = PluginRpcDispatcher(manager: self, storage: storage, aiService: aiService)
    private var sessions: [String: PluginRuntimeSession] = [:]
    private var eventSubscriptions: [String: Set<String>] = [:]
    private var eventSeq: Int = 0
    private var workspaceID: String = "default-vault"
    private var switchGeneration: Int = 0
    private let ephemeral: Bool

    init(ephemeral: Bool = false, storageRoot: URL? = nil) {
        self.ephemeral = ephemeral
        self.storage = PluginStorage(
            storageRoot: storageRoot ?? LibraryStore.defaultStorageRoot(),
            ephemeral: ephemeral
        )
        self.aiService = PluginAiService(storage: self.storage)
        self.records = self.storage.loadRegistry()
    }

    // MARK: - Workspace Lifecycle

    func attach(model: AppModel) {
        boundModel = model
        if !ephemeral {
            storage.updateRoot(storageRoot: model.storageRoot)
            records = storage.loadRegistry()
        }
        switchWorkspace(model: model, vaultID: model.activeVaultID)
    }

    func switchWorkspace(model: AppModel, vaultID: String) {
        boundModel = model
        switchGeneration &+= 1
        let gen = switchGeneration
        workspaceID = vaultID
        enabledIDs = Set(storage.loadEnabledPlugins(workspaceID: vaultID))

        let oldSessions = Array(sessions.values)
        sessions.removeAll()
        eventSubscriptions.removeAll()
        PluginCommandRegistry.shared.clearAll()
        PluginViewRegistry.shared.clearAll()

        for idx in records.indices where records[idx].state != .installed {
            records[idx].state = enabledIDs.contains(records[idx].id) ? .loading : .disabled
        }
        objectWillChange.send()

        Task { @MainActor [weak self] in
            for session in oldSessions {
                await session.unload()
            }
            guard let self, self.switchGeneration == gen else { return }
            await self.bootEnabledPlugins(expectedGeneration: gen)
        }
    }

    func updateStorageRoot(_ root: URL) {
        guard !ephemeral else { return }
        storage.updateRoot(storageRoot: root)
        records = storage.loadRegistry()
        if let model = boundModel {
            switchWorkspace(model: model, vaultID: model.activeVaultID)
        }
    }

    // MARK: - Lookups

    func record(for pluginId: String) -> PluginRecord? {
        records.first { $0.manifest.id == pluginId }
    }

    func session(for pluginId: String) -> PluginRuntimeSession? {
        sessions[pluginId]
    }

    func isEnabled(_ pluginId: String) -> Bool {
        enabledIDs.contains(pluginId)
    }

    func capabilityGrant(for pluginId: String) -> PluginPermissionGrant {
        _ = permissionRevision
        return storage.loadPermissionGrant(workspaceID: workspaceID, pluginId: pluginId)
    }

    func hasCapability(_ capability: String, pluginId: String) -> Bool {
        guard let rec = record(for: pluginId) else { return false }
        guard rec.manifest.capabilities.contains(capability) else { return false }
        return capabilityGrant(for: pluginId).granted.contains(capability)
    }

    func missingCapabilities(for pluginId: String) -> [PluginCapability] {
        guard let rec = record(for: pluginId) else { return [] }
        let granted = Set(capabilityGrant(for: pluginId).granted)
        return rec.manifest.capabilities.compactMap { raw in
            guard !granted.contains(raw) else { return nil }
            return PluginCapability(rawValue: raw)
        }
    }

    func requireCapability(pluginId: String, capability: String) throws {
        guard let rec = record(for: pluginId) else {
            throw PluginHostError(PluginErrorCode.notFound, "未找到插件：\(pluginId)")
        }
        guard rec.manifest.capabilities.contains(capability) else {
            throw PluginHostError(
                PluginErrorCode.permissionDenied,
                "插件「\(rec.manifest.name)」未在清单中声明权限：\(capability)"
            )
        }
        let grant = storage.loadPermissionGrant(workspaceID: workspaceID, pluginId: pluginId)
        guard grant.granted.contains(capability) else {
            let label = PluginCapability(rawValue: capability)?.title ?? capability
            throw PluginHostError(
                PluginErrorCode.permissionDenied,
                "插件「\(rec.manifest.name)」缺少当前工作区权限「\(label)」，请在设置 → 插件中授权"
            )
        }
    }

    // MARK: - Permissions (Deny-by-default per workspace)

    func setCapability(_ capability: String, granted isGranted: Bool, for pluginId: String) {
        var grant = storage.loadPermissionGrant(workspaceID: workspaceID, pluginId: pluginId)
        grant.granted.removeAll { $0 == capability }
        grant.denied.removeAll { $0 == capability }
        if isGranted {
            grant.granted.append(capability)
        } else {
            grant.denied.append(capability)
        }
        storage.savePermissionGrant(workspaceID: workspaceID, pluginId: pluginId, grant: grant)
        permissionRevision &+= 1
        appendLog(pluginId: pluginId, level: "info", message: "权限 \(capability) 已\(isGranted ? "授予" : "撤销")")

        if enabledIDs.contains(pluginId) {
            Task { @MainActor [weak self] in
                await self?.bootPlugin(pluginId: pluginId)
            }
        }
    }

    func grantAllCapabilities(for pluginId: String) {
        guard let rec = record(for: pluginId) else { return }
        let grant = PluginPermissionGrant(granted: rec.manifest.capabilities, denied: [])
        storage.savePermissionGrant(workspaceID: workspaceID, pluginId: pluginId, grant: grant)
        permissionRevision &+= 1
        appendLog(pluginId: pluginId, level: "info", message: "已授予当前工作区全部声明权限")

        if enabledIDs.contains(pluginId) {
            Task { @MainActor [weak self] in
                await self?.bootPlugin(pluginId: pluginId)
            }
        }
    }

    func revokeAllCapabilities(for pluginId: String) {
        guard let rec = record(for: pluginId) else { return }
        let grant = PluginPermissionGrant(granted: [], denied: rec.manifest.capabilities)
        storage.savePermissionGrant(workspaceID: workspaceID, pluginId: pluginId, grant: grant)
        permissionRevision &+= 1
        appendLog(pluginId: pluginId, level: "info", message: "已撤销当前工作区全部插件权限")

        if enabledIDs.contains(pluginId) {
            Task { @MainActor [weak self] in
                await self?.bootPlugin(pluginId: pluginId)
            }
        }
    }

    // MARK: - Install / Enable / Disable / Uninstall

    @discardableResult
    func installFromZip(url: URL) async throws -> PluginRecord {
        let entries = try PluginZip.readEntries(from: url)
        return try await finishInstall(entries: entries)
    }

    @discardableResult
    func installFromDirectory(url: URL) async throws -> PluginRecord {
        let entries = try PluginZip.readEntries(fromDirectory: url)
        return try await finishInstall(entries: entries)
    }

    private func finishInstall(entries: [ZipExtractedEntry]) async throws -> PluginRecord {
        let manifest = try PluginManifestService.parseAndValidate(entries: entries)
        try storage.installFiles(pluginId: manifest.id, entries: entries)

        let now = Date()
        let wasRunning = enabledIDs.contains(manifest.id)
        let record: PluginRecord
        if let idx = records.firstIndex(where: { $0.manifest.id == manifest.id }) {
            let existing = records[idx]
            record = PluginRecord(
                manifest: manifest,
                state: wasRunning ? .loading : .installed,
                lastError: "",
                installedAt: existing.installedAt,
                updatedAt: now
            )
            records[idx] = record
        } else {
            record = PluginRecord(
                manifest: manifest,
                state: .installed,
                lastError: "",
                installedAt: now,
                updatedAt: now
            )
            records.append(record)
            records.sort { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
        }
        storage.saveRegistry(records)
        lastStatusMessage = "已安装插件：\(manifest.name) (\(manifest.version))"
        appendLog(pluginId: manifest.id, level: "info", message: "已安装 \(manifest.kind.label) v\(manifest.version)")

        if wasRunning {
            await bootPlugin(pluginId: manifest.id)
        }
        return self.record(for: manifest.id) ?? record
    }

    func enable(pluginId: String) async throws {
        guard record(for: pluginId) != nil else {
            throw PluginHostError(PluginErrorCode.notFound, "未找到插件：\(pluginId)")
        }
        enabledIDs.insert(pluginId)
        storage.saveEnabledPlugins(workspaceID: workspaceID, ids: Array(enabledIDs))
        await bootPlugin(pluginId: pluginId)
    }

    func disable(pluginId: String) async {
        enabledIDs.remove(pluginId)
        storage.saveEnabledPlugins(workspaceID: workspaceID, ids: Array(enabledIDs))
        await teardownSession(pluginId: pluginId)

        if let idx = records.firstIndex(where: { $0.manifest.id == pluginId }) {
            records[idx].state = .disabled
            records[idx].lastError = ""
            storage.saveRegistry(records)
        }
        if let model = boundModel, model.settings.inspectorMode.hasPrefix("plugin:\(pluginId):") {
            model.settings.inspectorMode = "outline"
        }
        appendLog(pluginId: pluginId, level: "info", message: "已在当前工作区停用")
    }

    func uninstall(pluginId: String) async {
        let name = record(for: pluginId)?.manifest.name ?? pluginId
        await disable(pluginId: pluginId)
        storage.removeFiles(pluginId: pluginId)
        storage.clearWorkspaceStateForPlugin(pluginId: pluginId)
        storage.clearAiConfig(pluginId: pluginId)
        records.removeAll { $0.manifest.id == pluginId }
        storage.saveRegistry(records)
        permissionRevision &+= 1
        lastStatusMessage = "已卸载插件：\(name)"
        appendLog(pluginId: pluginId, level: "info", message: "插件已彻底卸载")
    }

    func clearLogs(for pluginId: String? = nil) {
        if let pluginId {
            logs.removeAll { $0.pluginId == pluginId }
        } else {
            logs.removeAll()
        }
    }

    // MARK: - Boot & Teardown

    private func bootEnabledPlugins(expectedGeneration: Int) async {
        for pluginId in enabledIDs.sorted() {
            guard switchGeneration == expectedGeneration, enabledIDs.contains(pluginId) else { return }
            await bootPlugin(pluginId: pluginId)
        }
    }

    private func teardownSession(pluginId: String) async {
        PluginCommandRegistry.shared.clear(pluginId: pluginId)
        PluginViewRegistry.shared.clear(pluginId: pluginId)
        eventSubscriptions.removeValue(forKey: pluginId)
        if let old = sessions.removeValue(forKey: pluginId) {
            await old.unload()
        }
    }

    func bootPlugin(pluginId: String) async {
        guard let idx = records.firstIndex(where: { $0.manifest.id == pluginId }),
              enabledIDs.contains(pluginId) else {
            return
        }
        let rec = records[idx]
        updateRecordState(pluginId: pluginId, state: .loading, error: "")
        await teardownSession(pluginId: pluginId)

        guard let model = boundModel else {
            updateRecordState(pluginId: pluginId, state: .crashed, error: "宿主工作区尚未就绪")
            return
        }
        guard let mainData = storage.readPluginFile(pluginId: pluginId, relativePath: rec.manifest.main),
              let sourceCode = String(data: mainData, encoding: .utf8) else {
            let msg = "无法读取插件入口脚本：\(rec.manifest.main)"
            updateRecordState(pluginId: pluginId, state: .crashed, error: msg)
            appendLog(pluginId: pluginId, level: "error", message: msg)
            return
        }

        let stylesCss: String
        if let stylesPath = rec.manifest.styles,
           let cssData = storage.readPluginFile(pluginId: pluginId, relativePath: stylesPath),
           let cssStr = String(data: cssData, encoding: .utf8) {
            stylesCss = cssStr
        } else {
            stylesCss = ""
        }

        let grant = storage.loadPermissionGrant(workspaceID: workspaceID, pluginId: pluginId)
        let activeCaps = rec.manifest.capabilities.filter { grant.granted.contains($0) }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let session = PluginRuntimeSession(pluginId: pluginId, token: token)
        sessions[pluginId] = session

        session.onLog = { [weak self] level, message in
            self?.appendLog(pluginId: pluginId, level: level, message: message)
        }
        session.onRpcRequest = { [weak self, weak session] raw in
            guard let self, let session else { return }
            Task { @MainActor in
                let responseJson = await self.dispatcher.handleRaw(raw, sessionPluginId: pluginId, expectedToken: session.token)
                await session.sendResponse(responseJson)
            }
        }
        session.onProcessCrash = { [weak self] reason in
            guard let self else { return }
            PluginCommandRegistry.shared.clear(pluginId: pluginId)
            PluginViewRegistry.shared.clear(pluginId: pluginId)
            self.eventSubscriptions.removeValue(forKey: pluginId)
            self.sessions.removeValue(forKey: pluginId)
            self.updateRecordState(pluginId: pluginId, state: .crashed, error: reason)
            self.appendLog(pluginId: pluginId, level: "error", message: reason)
        }

        let settingsJson = encodeSettingsJson(pluginId: pluginId)
        let bootPayload = PluginRuntimeBoot(
            pluginId: pluginId,
            kind: rec.manifest.kind.rawValue,
            token: token,
            capabilities: activeCaps,
            vaultId: model.activeVaultID,
            manifestJson: rec.manifest.rawJson,
            filesJson: LexiVaultBridge.filesListJson(model: model),
            activeFileJson: LexiVaultBridge.activeFileJson(model: model),
            editorJson: LexiEditorBridge.shared.snapshotJson(model: model),
            settingsJson: settingsJson,
            dataJson: storage.loadPluginDataJsonString(workspaceID: workspaceID, pluginId: pluginId),
            sourceCode: sourceCode,
            sourceName: rec.manifest.main,
            stylesCss: stylesCss,
            warnings: rec.manifest.warnings
        )

        do {
            try await session.boot(bootPayload)
            // Let any immediate startup `views.register` / `commands.register` RPC tasks settle.
            await Task.yield()

            seedManifestDeclarationsIfNeeded(record: rec, activeCapabilities: Set(activeCaps))
            await session.applyTheme(palette: currentHostPalette(model: model))

            if let presentIdx = records.firstIndex(where: { $0.manifest.id == pluginId }),
               enabledIDs.contains(pluginId),
               sessions[pluginId] === session {
                records[presentIdx].state = .running
                records[presentIdx].lastError = ""
                storage.saveRegistry(records)
                appendLog(pluginId: pluginId, level: "info", message: "插件已在安全沙盒中启动")
            }
        } catch let err as PluginHostError {
            updateRecordState(pluginId: pluginId, state: .crashed, error: err.message)
            appendLog(pluginId: pluginId, level: "error", message: "启动失败 [\(err.code)]：\(err.message)")
        } catch {
            updateRecordState(pluginId: pluginId, state: .crashed, error: error.localizedDescription)
            appendLog(pluginId: pluginId, level: "error", message: "启动失败：\(error.localizedDescription)")
        }
    }

    private func seedManifestDeclarationsIfNeeded(record rec: PluginRecord, activeCapabilities: Set<String>) {
        let pid = rec.manifest.id
        if activeCapabilities.contains(PluginCapability.uiViews.rawValue) {
            for viewDecl in rec.manifest.views {
                let qualified = "\(pid):\(viewDecl.id)"
                if !PluginViewRegistry.shared.views.contains(where: { $0.qualifiedId == qualified }) {
                    PluginViewRegistry.shared.register(
                        pluginId: pid,
                        pluginName: rec.manifest.name,
                        viewId: viewDecl.id,
                        title: viewDecl.title,
                        icon: viewDecl.icon,
                        location: viewDecl.location,
                        entry: viewDecl.entry
                    )
                }
            }
            if rec.manifest.kind == .obsidian && !PluginViewRegistry.shared.views.contains(where: { $0.pluginId == pid }) {
                PluginViewRegistry.shared.register(
                    pluginId: pid,
                    pluginName: rec.manifest.name,
                    viewId: "obsidian-main",
                    title: rec.manifest.name,
                    icon: "puzzle",
                    location: "right-sidebar",
                    entry: nil
                )
            }
        }
    }

    // MARK: - Execution & Presentation

    func runCommand(qualifiedId: String) async {
        let parts = qualifiedId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let pluginId = parts[0]
        if sessions[pluginId] == nil, enabledIDs.contains(pluginId) {
            await bootPlugin(pluginId: pluginId)
        }
        guard let session = sessions[pluginId] else {
            boundModel?.showToast("插件未运行，无法执行命令", symbol: "exclamationmark.triangle")
            return
        }
        let ok = await session.runCommand(qualifiedId: qualifiedId)
        if !ok {
            appendLog(pluginId: pluginId, level: "warn", message: "命令执行未响应：\(qualifiedId)")
        }
    }

    func presentView(pluginId: String, viewId: String) async {
        if sessions[pluginId] == nil, enabledIDs.contains(pluginId) {
            await bootPlugin(pluginId: pluginId)
        }
        guard let session = sessions[pluginId] else { return }
        do {
            try await session.present(viewId: viewId)
        } catch let err as PluginHostError {
            appendLog(pluginId: pluginId, level: "warn", message: err.message)
        } catch {
            appendLog(pluginId: pluginId, level: "warn", message: error.localizedDescription)
        }
    }

    // MARK: - Event Bus

    func subscribe(pluginId: String, eventName: String) {
        let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var set = eventSubscriptions[pluginId] ?? []
        set.insert(trimmed)
        eventSubscriptions[pluginId] = set
    }

    func unsubscribe(pluginId: String, eventName: String) {
        eventSubscriptions[pluginId]?.remove(eventName)
    }

    func notifyVaultCreate(note: Note) {
        let payload: [String: Any] = [
            "vaultId": note.vaultID,
            "fileId": note.id,
            "path": LexiPathValidator.virtualPath(for: note),
            "file": LexiPathValidator.fileRefDictionary(for: note)
        ]
        emitEvent("vault.created", payload: payload)
    }

    func notifyVaultModify(note: Note) {
        let payload: [String: Any] = [
            "vaultId": note.vaultID,
            "fileId": note.id,
            "path": LexiPathValidator.virtualPath(for: note),
            "file": LexiPathValidator.fileRefDictionary(for: note)
        ]
        emitEvent("vault.modified", payload: payload)
    }

    func notifyVaultRename(note: Note, oldPath: String) {
        let payload: [String: Any] = [
            "vaultId": note.vaultID,
            "fileId": note.id,
            "path": LexiPathValidator.virtualPath(for: note),
            "oldPath": oldPath,
            "file": LexiPathValidator.fileRefDictionary(for: note)
        ]
        emitEvent("vault.renamed", payload: payload)
    }

    func notifyVaultDelete(note: Note) {
        let payload: [String: Any] = [
            "vaultId": note.vaultID,
            "fileId": note.id,
            "path": LexiPathValidator.virtualPath(for: note),
            "file": LexiPathValidator.fileRefDictionary(for: note)
        ]
        emitEvent("vault.deleted", payload: payload)
    }

    func notifyActiveLeafChanged() {
        guard let model = boundModel else { return }
        var payload: [String: Any] = ["vaultId": model.activeVaultID]
        if let note = model.currentNote, note.vaultID == model.activeVaultID {
            payload["fileId"] = note.id
            payload["path"] = LexiPathValidator.virtualPath(for: note)
            payload["file"] = LexiPathValidator.fileRefDictionary(for: note)
        } else {
            payload["fileId"] = NSNull()
            payload["file"] = NSNull()
        }
        if let editorDict = LexiEditorBridge.shared.snapshotDictionary(model: model) {
            payload["editor"] = editorDict
        }
        emitEvent("workspace.active-file-changed", payload: payload)
    }

    func notifyEditorChanged() {
        guard let model = boundModel,
              let editorDict = LexiEditorBridge.shared.snapshotDictionary(model: model) else { return }
        emitEvent("editor.changed", payload: editorDict)
    }

    func applyThemeCss(palette: ThemePalette) {
        for session in sessions.values {
            Task { @MainActor in
                await session.applyTheme(palette: palette)
            }
        }
    }

    private func emitEvent(_ name: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        eventSeq &+= 1
        let seq = eventSeq
        for (pluginId, session) in sessions {
            let subs = eventSubscriptions[pluginId] ?? []
            guard subs.contains(name) || subs.contains("*") else { continue }
            let event = PluginRpcEvent(pluginId: pluginId, event: name, seq: seq, payload: json)
            Task { @MainActor in
                await session.sendEvent(event)
            }
        }
    }

    // MARK: - AI Convenience Helpers (for Settings Panel & Plugins)

    func aiStatus(for pluginId: String) -> [String: Any] {
        aiService.statusDictionary(pluginId: pluginId)
    }

    func aiBinding(for pluginId: String) -> PluginAiBinding {
        aiService.loadBinding(pluginId: pluginId)
    }

    func saveAiProfile(pluginId: String, profile: PluginAiProfile, apiKey: String?) throws {
        try aiService.saveQuickProfile(pluginId: pluginId, profile: profile, apiKey: apiKey)
        objectWillChange.send()
    }

    func selectAiProfile(pluginId: String, profileId: String) throws {
        _ = try aiService.configure(pluginId: pluginId, params: ["action": "select", "profileId": profileId])
        objectWillChange.send()
    }

    func removeAiProfile(pluginId: String, profileId: String) throws {
        _ = try aiService.configure(pluginId: pluginId, params: ["action": "remove", "profileId": profileId])
        objectWillChange.send()
    }

    func clearAiConfig(pluginId: String) {
        _ = try? aiService.configure(pluginId: pluginId, params: ["action": "clear"])
        objectWillChange.send()
    }

    func aiHasSecret(pluginId: String, profileId: String) -> Bool {
        !storage.loadAiSecret(pluginId: pluginId, profileId: profileId).isEmpty
    }

    func fetchAiBalance(pluginId: String) async throws -> [String: Any] {
        try await aiService.checkBalance(pluginId: pluginId)
    }

    // MARK: - Internal Helpers

    private func updateRecordState(pluginId: String, state: PluginLifecycleState, error: String) {
        guard let idx = records.firstIndex(where: { $0.manifest.id == pluginId }) else { return }
        records[idx].state = state
        records[idx].lastError = error
        records[idx].updatedAt = Date()
        storage.saveRegistry(records)
    }

    func appendLog(pluginId: String, level: String, message: String) {
        let entry = PluginLogEntry(timestamp: Date(), pluginId: pluginId, level: level, message: message)
        logs.append(entry)
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    private func encodeSettingsJson(pluginId: String) -> String {
        let map = storage.loadPluginDataMap(workspaceID: workspaceID, pluginId: pluginId)
        if let raw = map["plugin-data"] {
            return raw
        }
        return "{}"
    }

    private func currentHostPalette(model: AppModel) -> ThemePalette {
        let dark: Bool
        switch model.settings.appearance {
        case .dark: dark = true
        case .light: dark = false
        case .system:
            dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return model.settings.palette(dark: dark)
    }
}
