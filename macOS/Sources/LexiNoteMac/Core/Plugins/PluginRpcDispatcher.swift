import Foundation
import AppKit

@MainActor
final class PluginRpcDispatcher {
    private unowned let manager: PluginManager
    private let storage: PluginStorage
    private let aiService: PluginAiService

    init(manager: PluginManager, storage: PluginStorage, aiService: PluginAiService) {
        self.manager = manager
        self.storage = storage
        self.aiService = aiService
    }

    func handleRaw(_ raw: String, sessionPluginId: String, expectedToken: String) async -> String {
        let reqId: String
        let request: PluginRpcRequest
        do {
            request = try PluginRpcRequest.parse(raw: raw)
            reqId = request.id
        } catch let err as PluginHostError {
            return PluginRpcResponse.failure(id: "", code: err.code, message: err.message)
        } catch {
            return PluginRpcResponse.failure(id: "", code: PluginErrorCode.protocolError, message: error.localizedDescription)
        }

        do {
            guard request.protocolVersion == PluginProtocol.version else {
                throw PluginHostError(PluginErrorCode.protocolError, "不兼容的插件协议版本：\(request.protocolVersion)")
            }
            guard !request.id.isEmpty, request.pluginId == sessionPluginId else {
                throw PluginHostError(PluginErrorCode.protocolError, "插件身份校验失败")
            }
            guard request.token == expectedToken else {
                throw PluginHostError(PluginErrorCode.permissionDenied, "插件运行时令牌无效")
            }
            guard let model = manager.boundModel else {
                throw PluginHostError(PluginErrorCode.runtimeUnavailable, "工作区未就绪")
            }

            let requiredCap = PluginCapability.requiredCapability(for: request.method)
            if !requiredCap.isEmpty {
                try manager.requireCapability(pluginId: sessionPluginId, capability: requiredCap)
            }

            let params = try request.paramsDictionary()
            let result = try await dispatch(method: request.method, params: params, pluginId: sessionPluginId, model: model)
            return PluginRpcResponse.success(id: reqId, resultObject: result)
        } catch let err as PluginHostError {
            return PluginRpcResponse.failure(id: reqId, code: err.code, message: err.message)
        } catch {
            return PluginRpcResponse.failure(id: reqId, code: PluginErrorCode.unknown, message: error.localizedDescription)
        }
    }

    private func dispatch(method: String, params: [String: Any], pluginId: String, model: AppModel) async throws -> Any {
        let record = manager.record(for: pluginId)
        let pluginName = record?.manifest.name ?? pluginId

        switch method {
        case "plugin.ping":
            return ["ok": true, "runtimeVersion": PluginProtocol.runtimeVersion, "vaultId": model.activeVaultID]

        // MARK: Vault
        case "vault.listMarkdown":
            return try LexiVaultBridge.listMarkdown(vaultId: params["vaultId"] as? String, model: model)

        case "vault.getByPath":
            let path = params["path"] as? String ?? ""
            return try LexiVaultBridge.getByPath(vaultId: params["vaultId"] as? String, path: path, model: model) ?? NSNull()

        case "vault.getById":
            let fileId = params["fileId"] as? String ?? ""
            return try LexiVaultBridge.getById(vaultId: params["vaultId"] as? String, fileId: fileId, model: model) ?? NSNull()

        case "vault.readText":
            let fileId = params["fileId"] as? String ?? ""
            return try LexiVaultBridge.readText(vaultId: params["vaultId"] as? String, fileId: fileId, model: model)

        case "vault.createText":
            let path = params["path"] as? String ?? ""
            let content = params["content"] as? String ?? ""
            return try LexiVaultBridge.createText(vaultId: params["vaultId"] as? String, path: path, content: content, model: model)

        case "vault.writeText":
            let fileId = params["fileId"] as? String ?? ""
            let content = params["content"] as? String ?? ""
            let expected = (params["expectedUpdatedAt"] as? Int64)
                ?? Int64((params["expectedUpdatedAt"] as? Double) ?? 0)
            return try LexiVaultBridge.writeText(vaultId: params["vaultId"] as? String, fileId: fileId, content: content, expectedUpdatedAt: expected, model: model)

        case "vault.renameText":
            let fileId = params["fileId"] as? String ?? ""
            let newPath = (params["newPath"] as? String) ?? (params["path"] as? String) ?? ""
            return try LexiVaultBridge.renameText(vaultId: params["vaultId"] as? String, fileId: fileId, newPath: newPath, model: model)

        case "vault.deleteText":
            let fileId = params["fileId"] as? String ?? ""
            return try LexiVaultBridge.deleteText(vaultId: params["vaultId"] as? String, fileId: fileId, model: model)

        // MARK: Metadata
        case "metadata.get":
            let fileId = params["fileId"] as? String ?? ""
            guard let note = model.note(fileId), !note.isTrashed, note.vaultID == model.activeVaultID else {
                throw PluginHostError(PluginErrorCode.notFound, "找不到指定笔记：\(fileId)")
            }
            return LexiMetadataBridge.metadataDictionary(for: note)

        // MARK: Editor
        case "editor.active":
            return LexiEditorBridge.shared.snapshotDictionary(model: model) ?? NSNull()

        case "editor.replaceSelection":
            let text = params["text"] as? String ?? ""
            let from = params["from"] as? Int
            let to = params["to"] as? Int
            let rev = (params["expectedVersion"] as? Int) ?? (params["expectedRevision"] as? Int)
            return try LexiEditorBridge.shared.replaceSelection(model: model, text: text, from: from, to: to, expectedRevision: rev)

        case "editor.replaceAll":
            let content = (params["text"] as? String) ?? (params["content"] as? String) ?? ""
            let rev = (params["expectedVersion"] as? Int) ?? (params["expectedRevision"] as? Int)
            return try LexiEditorBridge.shared.replaceAll(model: model, content: content, expectedRevision: rev)

        // MARK: Workspace
        case "workspace.activeFile":
            guard let note = model.currentNote, note.vaultID == model.activeVaultID else { return NSNull() }
            return LexiPathValidator.fileRefDictionary(for: note)

        case "workspace.openFile":
            return try LexiVaultBridge.openFile(
                vaultId: params["vaultId"] as? String,
                fileId: params["fileId"] as? String,
                path: params["path"] as? String,
                model: model
            )

        case "workspace.snapshot":
            let files = try LexiVaultBridge.listMarkdown(vaultId: nil, model: model)
            let active: Any = model.currentNote.map { LexiPathValidator.fileRefDictionary(for: $0) as Any } ?? NSNull()
            return [
                "vaultId": model.activeVaultID,
                "vaultName": model.activeVault?.name ?? "我的工作区",
                "files": files,
                "activeFile": active
            ]

        // MARK: Commands
        case "commands.register":
            let cid = (params["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = ((params["title"] as? String) ?? (params["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cid.isEmpty, !name.isEmpty else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "注册命令需要 id 与 name")
            }
            let hotkeys = (params["hotkeys"] as? [String]) ?? []
            PluginCommandRegistry.shared.register(pluginId: pluginId, pluginName: pluginName, commandId: cid, name: name, hotkeys: hotkeys)
            return ["qualifiedId": "\(pluginId):\(cid)"]

        case "commands.unregister":
            let cid = (params["id"] as? String ?? "")
            let qualified = cid.contains(":") ? cid : "\(pluginId):\(cid)"
            PluginCommandRegistry.shared.unregister(qualifiedId: qualified)
            return true

        // MARK: Events
        case "events.on":
            let eventName = (params["event"] as? String ?? "")
            manager.subscribe(pluginId: pluginId, eventName: eventName)
            return true

        case "events.off":
            let eventName = (params["event"] as? String ?? "")
            manager.unsubscribe(pluginId: pluginId, eventName: eventName)
            return true

        // MARK: Views & Ribbon
        case "views.register":
            let kind = (params["kind"] as? String ?? "view").lowercased()
            let vid = (params["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (params["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = params["icon"] as? String
            let location = params["location"] as? String
            if kind == "ribbon" || location == "ribbon" {
                PluginViewRegistry.shared.registerRibbon(
                    pluginId: pluginId,
                    pluginName: pluginName,
                    actionId: vid.isEmpty ? "ribbon" : vid,
                    title: title,
                    icon: icon
                )
            } else {
                guard !vid.isEmpty else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "注册视图需要 id")
                }
                PluginViewRegistry.shared.register(
                    pluginId: pluginId,
                    pluginName: pluginName,
                    viewId: vid,
                    title: title,
                    icon: icon,
                    location: location,
                    entry: nil
                )
            }
            return ["qualifiedId": "\(pluginId):\(vid)"]

        case "views.unregister":
            let vid = (params["id"] as? String ?? "")
            let qualified = vid.contains(":") ? vid : "\(pluginId):\(vid)"
            PluginViewRegistry.shared.unregister(qualifiedId: qualified)
            return true

        case "views.open":
            let vid = (params["id"] as? String ?? "")
            let qualified = vid.contains(":") ? vid : "\(pluginId):\(vid)"
            model.settings.showInspector = true
            model.settings.inspectorMode = "plugin:\(qualified)"
            return true

        // MARK: UI Notice & Modal
        case "ui.notice":
            let message = (params["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard message.utf8.count <= PluginLimits.maxNoticeBytes else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "通知内容过长")
            }
            if !message.isEmpty {
                model.showToast(message, symbol: "puzzlepiece.extension")
            }
            return true

        case "ui.confirm":
            let title = (params["title"] as? String) ?? pluginName
            let message = (params["body"] as? String) ?? (params["message"] as? String) ?? "是否允许继续执行此操作？"
            if let handler = manager.confirmHandlerOverride {
                return handler(title, message)
            }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: (params["confirmLabel"] as? String) ?? "确定")
            alert.addButton(withTitle: (params["cancelLabel"] as? String) ?? "取消")
            return alert.runModal() == .alertFirstButtonReturn

        // MARK: Isolated Per-Workspace Plugin Storage
        case "storage.get":
            let key = params["key"] as? String ?? ""
            guard !key.isEmpty else { throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 key") }
            let map = storage.loadPluginDataMap(workspaceID: model.activeVaultID, pluginId: pluginId)
            return map[key] ?? NSNull()

        case "storage.set":
            let key = params["key"] as? String ?? ""
            guard !key.isEmpty else { throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 key") }
            let valueStr: String
            if let s = params["value"] as? String {
                valueStr = s
            } else if let obj = params["value"], JSONSerialization.isValidJSONObject(obj),
                      let data = try? JSONSerialization.data(withJSONObject: obj),
                      let encoded = String(data: data, encoding: .utf8) {
                valueStr = encoded
            } else if let b = params["value"] as? Bool {
                valueStr = b ? "true" : "false"
            } else if let obj = params["value"] {
                valueStr = "\(obj)"
            } else {
                valueStr = ""
            }
            var map = storage.loadPluginDataMap(workspaceID: model.activeVaultID, pluginId: pluginId)
            map[key] = valueStr
            try storage.savePluginDataMap(workspaceID: model.activeVaultID, pluginId: pluginId, map: map)
            return true

        case "storage.remove":
            let key = params["key"] as? String ?? ""
            guard !key.isEmpty else { throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 key") }
            var map = storage.loadPluginDataMap(workspaceID: model.activeVaultID, pluginId: pluginId)
            map.removeValue(forKey: key)
            try storage.savePluginDataMap(workspaceID: model.activeVaultID, pluginId: pluginId, map: map)
            return true

        // MARK: AI Host Proxy
        case "ai.status":
            return aiService.statusDictionary(pluginId: pluginId)

        case "ai.configure":
            return try aiService.configure(pluginId: pluginId, params: params)

        case "ai.chat":
            return try await aiService.chat(pluginId: pluginId, params: params)

        case "ai.models":
            return try await aiService.listModels(pluginId: pluginId)

        case "ai.balance":
            return try await aiService.checkBalance(pluginId: pluginId)

        default:
            throw PluginHostError(PluginErrorCode.unsupportedApi, "不支持的插件方法：\(method)")
        }
    }
}
