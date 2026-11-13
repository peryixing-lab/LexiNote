import Foundation

enum PluginProtocol {
    static let version = 1
    static let runtimeVersion = "1"
}

enum PluginLimits {
    static let maxRpcBytes = 1_048_576
    static let maxFileBytes = 5_242_880
    static let maxZipTotalBytes = 32 * 1024 * 1024
    static let maxZipFiles = 250
    static let maxStorageBytes = 5 * 1024 * 1024
    static let maxStorageKeys = 500
    static let maxNoticeBytes = 1024
    static let maxEventsPerSecond = 200
}

enum PluginErrorCode {
    static let invalidArgument = "E_INVALID_ARGUMENT"
    static let invalidPath = "E_INVALID_PATH"
    static let pathExists = "E_PATH_EXISTS"
    static let notFound = "E_NOT_FOUND"
    static let conflict = "E_CONFLICT"
    static let editorConflict = "E_EDITOR_CONFLICT"
    static let editorReadonly = "E_EDITOR_READONLY"
    static let permissionDenied = "E_PERMISSION_DENIED"
    static let vaultForbidden = "E_VAULT_FORBIDDEN"
    static let unsupportedApi = "E_UNSUPPORTED_API"
    static let unsupportedModule = "E_UNSUPPORTED_MODULE"
    static let quotaExceeded = "E_QUOTA_EXCEEDED"
    static let rateLimited = "E_RATE_LIMITED"
    static let timeout = "E_TIMEOUT"
    static let cancelled = "E_CANCELLED"
    static let runtimeUnavailable = "E_RUNTIME_UNAVAILABLE"
    static let pluginFailed = "E_PLUGIN_FAILED"
    static let installRejected = "E_INSTALL_REJECTED"
    static let missingCredential = "E_MISSING_CREDENTIAL"
    static let invalidCredential = "E_INVALID_CREDENTIAL"
    static let modelUnavailable = "E_MODEL_UNAVAILABLE"
    static let protocolError = "E_PROTOCOL"
    static let io = "E_IO"
    static let unknown = "E_UNKNOWN"
}

struct PluginHostError: Error {
    let code: String
    let message: String
    let details: String

    init(_ code: String, _ message: String, details: String = "") {
        self.code = code
        self.message = message
        self.details = details
    }
}

enum PluginKind: String, Codable, CaseIterable {
    case lexinote
    case obsidian

    var label: String {
        switch self {
        case .lexinote: return "知萤原生插件"
        case .obsidian: return "Obsidian 兼容插件"
        }
    }
}

enum PluginLifecycleState: String, Codable {
    case installed
    case loading
    case running
    case disabled
    case crashed

    var label: String {
        switch self {
        case .installed: return "已安装"
        case .loading: return "加载中"
        case .running: return "运行中"
        case .disabled: return "已停用"
        case .crashed: return "异常中止"
        }
    }
}

enum PluginCapability: String, CaseIterable, Codable, Identifiable {
    case vaultRead = "vault.read"
    case vaultWrite = "vault.write"
    case notesMetadataRead = "notes.metadata.read"
    case editorRead = "editor.read"
    case editorWrite = "editor.write"
    case workspaceViews = "workspace.views"
    case uiCommands = "ui.commands"
    case uiViews = "ui.views"
    case uiModal = "ui.modal"
    case uiNotice = "ui.notice"
    case pluginStorage = "plugin.storage"
    case aiInference = "ai.inference"

    var id: String { rawValue }

    enum RiskLevel: String {
        case high = "高风险"
        case medium = "中风险"
        case low = "基础"
    }

    var title: String {
        switch self {
        case .vaultRead: return "读取笔记文件"
        case .vaultWrite: return "修改、创建和删除笔记"
        case .notesMetadataRead: return "读取笔记大纲、标签与链接"
        case .editorRead: return "读取当前编辑器正文与选区"
        case .editorWrite: return "修改当前编辑器正文"
        case .workspaceViews: return "读取或打开工作区笔记"
        case .uiCommands: return "注册命令面板与快捷键"
        case .uiViews: return "创建侧边栏或面板视图"
        case .uiModal: return "弹出确认对话框"
        case .uiNotice: return "发送通知提示"
        case .pluginStorage: return "读写插件私有配置数据"
        case .aiInference: return "调用 AI 大模型推理与配额查询"
        }
    }

    var description: String {
        switch self {
        case .vaultRead: return "允许读取当前工作区中的 Markdown 笔记内容与文件列表。"
        case .vaultWrite: return "允许新建、改写、重命名或删除当前工作区内的笔记文件。"
        case .notesMetadataRead: return "允许读取笔记的标题层级、标签、属性与双向链接索引。"
        case .editorRead: return "允许查看当前打开笔记的文本、光标行号与选中文本。"
        case .editorWrite: return "允许向当前编辑中的笔记插入或替换内容。"
        case .workspaceViews: return "允许查询当前活动文件或在标签栏中打开指定笔记。"
        case .uiCommands: return "允许向知萤命令面板和快捷键列表添加插件命令。"
        case .uiViews: return "允许在工作区右侧边栏添加自定义交互页面。"
        case .uiModal: return "允许弹出交互确认框以征求用户确认。"
        case .uiNotice: return "允许在工作区底部展示短暂提示消息。"
        case .pluginStorage: return "允许在当前工作区隔离目录下保存插件设置与状态。"
        case .aiInference: return "允许通过知萤宿主的模型代理发送推理请求，密钥不向插件暴露。"
        }
    }

    var risk: RiskLevel {
        switch self {
        case .vaultWrite, .editorWrite, .aiInference:
            return .high
        case .vaultRead, .editorRead, .notesMetadataRead, .workspaceViews:
            return .medium
        case .uiCommands, .uiViews, .uiModal, .uiNotice, .pluginStorage:
            return .low
        }
    }

    static func requiredCapability(for method: String) -> String {
        if method == "plugin.ping" || method == "events.on" || method == "events.off" { return "" }
        if method == "vault.listMarkdown" || method == "vault.getByPath" ||
            method == "vault.getById" || method == "vault.readText" {
            return vaultRead.rawValue
        }
        if method.hasPrefix("vault.") { return vaultWrite.rawValue }
        if method == "metadata.get" { return notesMetadataRead.rawValue }
        if method == "workspace.activeFile" || method == "workspace.openFile" ||
            method == "workspace.snapshot" {
            return workspaceViews.rawValue
        }
        if method == "editor.active" { return editorRead.rawValue }
        if method == "editor.replaceSelection" || method == "editor.replaceAll" { return editorWrite.rawValue }
        if method == "commands.register" || method == "commands.unregister" { return uiCommands.rawValue }
        if method == "ui.notice" { return uiNotice.rawValue }
        if method == "ui.confirm" { return uiModal.rawValue }
        if method.hasPrefix("ai.") { return aiInference.rawValue }
        if method.hasPrefix("views.") { return uiViews.rawValue }
        if method.hasPrefix("storage.") { return pluginStorage.rawValue }
        return ""
    }
}

struct PluginCommandDeclaration: Codable, Hashable {
    var id: String
    var name: String
    var hotkeys: [String]?
}

struct PluginViewDeclaration: Codable, Hashable {
    var id: String
    var type: String
    var title: String
    var icon: String?
    var location: String?
    var entry: String?
}

struct PluginManifest: Codable, Hashable {
    var id: String
    var name: String
    var version: String
    var kind: PluginKind
    var description: String
    var author: String
    var authorUrl: String?
    var minAppVersion: String?
    var main: String
    var styles: String?
    var capabilities: [String]
    var commands: [PluginCommandDeclaration]
    var views: [PluginViewDeclaration]
    var targets: [String]
    var isDesktopOnly: Bool
    var warnings: [String]
    var rawJson: String
}

struct PluginRecord: Identifiable, Codable, Hashable {
    var manifest: PluginManifest
    var state: PluginLifecycleState
    var lastError: String
    var installedAt: Date
    var updatedAt: Date

    var id: String { manifest.id }
}

struct PluginPermissionGrant: Codable, Hashable {
    var granted: [String]
    var denied: [String]

    init(granted: [String] = [], denied: [String] = []) {
        self.granted = granted
        self.denied = denied
    }
}

struct PluginRegisteredCommand: Identifiable, Hashable {
    var pluginId: String
    var pluginName: String
    var commandId: String
    var qualifiedId: String
    var name: String
    var hotkeys: [String]

    var id: String { qualifiedId }
}

struct PluginRegisteredView: Identifiable, Hashable {
    var pluginId: String
    var pluginName: String
    var viewId: String
    var qualifiedId: String
    var title: String
    var icon: String
    var location: String
    var entry: String?

    var id: String { qualifiedId }
}

struct PluginRibbonAction: Identifiable, Hashable {
    var id: String
    var pluginId: String
    var pluginName: String
    var title: String
    var icon: String
    var actionId: String
}

// MARK: - RPC Wire Models

struct PluginRpcRequest {
    var protocolVersion: Int = PluginProtocol.version
    var id: String = ""
    var pluginId: String = ""
    var token: String = ""
    var method: String = ""
    var paramsJson: String = "{}"

    static func parse(raw: String) throws -> PluginRpcRequest {
        guard !raw.isEmpty else {
            throw PluginHostError(PluginErrorCode.protocolError, "请求为空")
        }
        guard raw.utf8.count <= PluginLimits.maxRpcBytes else {
            throw PluginHostError(PluginErrorCode.rateLimited, "请求体超过大小上限")
        }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginHostError(PluginErrorCode.protocolError, "请求不是合法 JSON")
        }
        var req = PluginRpcRequest()
        if let v = obj["protocol"] as? Int { req.protocolVersion = v }
        if let v = obj["id"] as? String { req.id = v }
        if let v = obj["pluginId"] as? String { req.pluginId = v }
        if let v = obj["token"] as? String { req.token = v }
        if let v = obj["method"] as? String { req.method = v }
        if let paramsStr = obj["params"] as? String {
            req.paramsJson = paramsStr
        } else if let paramsAny = obj["params"], !(paramsAny is NSNull) {
            if let encoded = try? JSONSerialization.data(withJSONObject: paramsAny),
               let str = String(data: encoded, encoding: .utf8) {
                req.paramsJson = str
            }
        }
        return req
    }

    func paramsDictionary() throws -> [String: Any] {
        guard let data = paramsJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请求参数不是合法 JSON")
        }
        return dict
    }
}

struct PluginRpcResponse: Encodable {
    struct ErrorBody: Encodable {
        let code: String
        let message: String
    }
    let `protocol`: Int = PluginProtocol.version
    let id: String
    let ok: Bool
    let result: String
    let error: ErrorBody?

    static func success(id: String, resultObject: Any) -> String {
        let resultJson: String
        if resultObject is NSNull {
            resultJson = "null"
        } else if let str = resultObject as? String,
                  let data = try? JSONSerialization.data(withJSONObject: [str]),
                  let encoded = String(data: data, encoding: .utf8),
                  encoded.count >= 2 {
            resultJson = String(encoded.dropFirst().dropLast())
        } else if let b = resultObject as? Bool {
            resultJson = b ? "true" : "false"
        } else if let num = resultObject as? NSNumber {
            resultJson = "\(num)"
        } else if JSONSerialization.isValidJSONObject(resultObject),
                  let data = try? JSONSerialization.data(withJSONObject: resultObject),
                  let str = String(data: data, encoding: .utf8) {
            resultJson = str
        } else {
            resultJson = "null"
        }
        let resp = PluginRpcResponse(id: id, ok: true, result: resultJson, error: nil)
        return encodeJson(resp)
    }

    static func failure(id: String, code: String, message: String) -> String {
        let resp = PluginRpcResponse(id: id, ok: false, result: "", error: ErrorBody(code: code, message: message))
        return encodeJson(resp)
    }

    private static func encodeJson(_ resp: PluginRpcResponse) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(resp), let str = String(data: data, encoding: .utf8) else {
            return "{\"protocol\":1,\"id\":\"\",\"ok\":false,\"result\":\"\",\"error\":{\"code\":\"E_UNKNOWN\",\"message\":\"encode failed\"}}"
        }
        return str
    }
}

struct PluginRuntimeBoot: Encodable {
    let type = "boot"
    let `protocol` = PluginProtocol.version
    let pluginId: String
    let kind: String
    let token: String
    let runtimeVersion = PluginProtocol.runtimeVersion
    let capabilities: [String]
    let vaultId: String
    let manifestJson: String
    let filesJson: String
    let activeFileJson: String
    let editorJson: String
    let settingsJson: String
    let dataJson: String
    let sourceCode: String
    let sourceName: String
    let stylesCss: String
    let warnings: [String]
}

struct PluginRpcEvent: Encodable {
    let `protocol` = PluginProtocol.version
    let type = "event"
    let pluginId: String
    let event: String
    let seq: Int
    let payload: String
}

// MARK: - Plugin AI Models

struct PluginAiProfile: Codable, Hashable, Identifiable {
    var profileId: String
    var name: String
    var provider: String
    var baseUrl: String
    var model: String
    var maxTokens: Int
    var temperature: Double

    var id: String { profileId }
}

struct PluginAiBinding: Codable {
    var version: Int = 2
    var activeProfileId: String = ""
    var profiles: [PluginAiProfile] = []
}

struct PluginAiPreset: Identifiable {
    let id: String
    let title: String
    let provider: String
    let baseUrl: String
    let defaultModel: String
    let needsApiKey: Bool
}

enum PluginAiPresets {
    static let all: [PluginAiPreset] = [
        PluginAiPreset(id: "deepseek", title: "DeepSeek", provider: "openai-compatible", baseUrl: "https://api.deepseek.com", defaultModel: "deepseek-chat", needsApiKey: true),
        PluginAiPreset(id: "openai", title: "OpenAI", provider: "openai-compatible", baseUrl: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", needsApiKey: true),
        PluginAiPreset(id: "anthropic", title: "Anthropic Claude", provider: "anthropic-compatible", baseUrl: "https://api.anthropic.com", defaultModel: "claude-sonnet-4-20250514", needsApiKey: true),
        PluginAiPreset(id: "openrouter", title: "OpenRouter", provider: "openai-compatible", baseUrl: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", needsApiKey: true),
        PluginAiPreset(id: "siliconflow", title: "硅基流动 SiliconFlow", provider: "openai-compatible", baseUrl: "https://api.siliconflow.cn/v1", defaultModel: "Qwen/Qwen2.5-72B-Instruct", needsApiKey: true),
        PluginAiPreset(id: "glm", title: "智谱 GLM Coding Plan", provider: "openai-compatible", baseUrl: "https://open.bigmodel.cn/api/coding/paas/v4", defaultModel: "glm-4.5", needsApiKey: true),
        PluginAiPreset(id: "kimi", title: "Kimi For Coding", provider: "anthropic-compatible", baseUrl: "https://api.kimi.com/coding", defaultModel: "kimi-k2-0711-preview", needsApiKey: true),
        PluginAiPreset(id: "minimax", title: "MiniMax Coding Plan", provider: "anthropic-compatible", baseUrl: "https://api.minimaxi.com/anthropic", defaultModel: "MiniMax-M1", needsApiKey: true),
        PluginAiPreset(id: "ollama", title: "Ollama 本地模型", provider: "openai-compatible", baseUrl: "http://127.0.0.1:11434/v1", defaultModel: "qwen2.5:7b", needsApiKey: false)
    ]
}
