import Foundation

/// Host-managed AI proxy for plugins. Keeps provider credentials in isolated host files
/// and never returns API keys back to the JS sandbox.
final class PluginAiService {
    private let storage: PluginStorage
    private var balanceCache: [String: (timestamp: Date, payload: [String: Any])] = [:]

    init(storage: PluginStorage) {
        self.storage = storage
    }

    // MARK: - Profile & Status

    func loadBinding(pluginId: String) -> PluginAiBinding {
        guard let raw = storage.loadAiBindingRaw(pluginId: pluginId),
              let data = raw.data(using: .utf8),
              let binding = try? JSONDecoder().decode(PluginAiBinding.self, from: data) else {
            return PluginAiBinding()
        }
        return binding
    }

    func saveBinding(pluginId: String, binding: PluginAiBinding) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(binding)
        guard let str = String(data: data, encoding: .utf8) else {
            throw PluginHostError(PluginErrorCode.io, "编码模型配置失败")
        }
        try storage.saveAiBindingRaw(pluginId: pluginId, json: str)
    }

    func statusDictionary(pluginId: String) -> [String: Any] {
        let binding = loadBinding(pluginId: pluginId)
        guard let active = activeProfile(binding: binding) else {
            return [
                "configured": false,
                "profileId": "",
                "name": "",
                "provider": "openai-compatible",
                "baseUrl": "",
                "model": "",
                "maxTokens": 4096,
                "temperature": 0.3,
                "balanceProvider": "",
                "needsApiKey": true,
                "profiles": []
            ]
        }
        let secret = storage.loadAiSecret(pluginId: pluginId, profileId: active.profileId)
        let needsKey = needsApiKey(baseUrl: active.baseUrl)
        let configured = !active.baseUrl.isEmpty && !active.model.isEmpty && (!needsKey || !secret.isEmpty)
        let profilesList: [[String: Any]] = binding.profiles.map { profile in
            [
                "profileId": profile.profileId,
                "name": profile.name,
                "provider": profile.provider,
                "baseUrl": profile.baseUrl,
                "model": profile.model,
                "hasKey": !storage.loadAiSecret(pluginId: pluginId, profileId: profile.profileId).isEmpty
            ]
        }
        return [
            "configured": configured,
            "profileId": active.profileId,
            "name": active.name,
            "provider": active.provider,
            "baseUrl": active.baseUrl,
            "model": active.model,
            "maxTokens": active.maxTokens,
            "temperature": active.temperature,
            "balanceProvider": balanceProviderName(baseUrl: active.baseUrl),
            "needsApiKey": needsKey,
            "profiles": profilesList
        ]
    }

    func configure(pluginId: String, params: [String: Any]) throws -> [String: Any] {
        let action: String
        if params["clear"] as? Bool == true {
            action = "clear"
        } else if params["remove"] as? Bool == true {
            action = "remove"
        } else {
            action = ((params["action"] as? String) ?? "upsert").lowercased()
        }
        var binding = loadBinding(pluginId: pluginId)

        switch action {
        case "clear":
            storage.clearAiConfig(pluginId: pluginId)
            balanceCache.removeAll()
            return statusDictionary(pluginId: pluginId)

        case "select":
            guard let targetId = params["profileId"] as? String,
                  binding.profiles.contains(where: { $0.profileId == targetId }) else {
                throw PluginHostError(PluginErrorCode.notFound, "未找到指定的 AI 服务商配置")
            }
            binding.activeProfileId = targetId
            try saveBinding(pluginId: pluginId, binding: binding)
            return statusDictionary(pluginId: pluginId)

        case "remove":
            guard let targetId = params["profileId"] as? String else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 profileId")
            }
            binding.profiles.removeAll { $0.profileId == targetId }
            storage.saveAiSecret(pluginId: pluginId, profileId: targetId, secret: "")
            if binding.activeProfileId == targetId {
                binding.activeProfileId = binding.profiles.first?.profileId ?? ""
            }
            try saveBinding(pluginId: pluginId, binding: binding)
            return statusDictionary(pluginId: pluginId)

        case "upsert":
            let profileId = (params["profileId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedId = (profileId?.isEmpty == false) ? profileId! : "default"
            let provider = normalizeProvider(params["provider"] as? String)
            let baseUrl = try normalizeBaseUrl(params["baseUrl"] as? String ?? "https://api.deepseek.com")
            let model = ((params["model"] as? String) ?? "deepseek-chat").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "模型名称不能为空")
            }
            let name = (params["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? model
            let maxTokens = max(256, min(32_768, (params["maxTokens"] as? Int) ?? 4096))
            let temp = max(0.0, min(2.0, (params["temperature"] as? Double) ?? 0.3))
            let profile = PluginAiProfile(
                profileId: resolvedId,
                name: name.isEmpty ? model : name,
                provider: provider,
                baseUrl: baseUrl,
                model: model,
                maxTokens: maxTokens,
                temperature: temp
            )
            if let idx = binding.profiles.firstIndex(where: { $0.profileId == resolvedId }) {
                binding.profiles[idx] = profile
            } else {
                guard binding.profiles.count < 8 else {
                    throw PluginHostError(PluginErrorCode.quotaExceeded, "最多保存 8 个 AI 服务商配置")
                }
                binding.profiles.append(profile)
            }
            binding.activeProfileId = resolvedId

            if let apiKey = params["apiKey"] as? String, apiKey != "__KEEP__" {
                let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    storage.saveAiSecret(pluginId: pluginId, profileId: resolvedId, secret: clean)
                }
            }
            try saveBinding(pluginId: pluginId, binding: binding)
            return statusDictionary(pluginId: pluginId)

        default:
            throw PluginHostError(PluginErrorCode.invalidArgument, "未知配置操作：\(action)")
        }
    }

    /// UI helper called directly from native Swift settings / popover forms.
    func saveQuickProfile(pluginId: String, profile: PluginAiProfile, apiKey: String?) throws {
        var params: [String: Any] = [
            "action": "upsert",
            "profileId": profile.profileId,
            "name": profile.name,
            "provider": profile.provider,
            "baseUrl": profile.baseUrl,
            "model": profile.model,
            "maxTokens": profile.maxTokens,
            "temperature": profile.temperature
        ]
        if let apiKey { params["apiKey"] = apiKey }
        _ = try configure(pluginId: pluginId, params: params)
    }

    // MARK: - Inference (`ai.chat`)

    func chat(pluginId: String, params: [String: Any]) async throws -> [String: Any] {
        let binding = loadBinding(pluginId: pluginId)
        guard let profile = activeProfile(binding: binding) else {
            throw PluginHostError(PluginErrorCode.missingCredential, "尚未配置 AI 服务商，请先在插件设置中添加模型与密钥")
        }
        let secret = storage.loadAiSecret(pluginId: pluginId, profileId: profile.profileId)
        if needsApiKey(baseUrl: profile.baseUrl) && secret.isEmpty {
            throw PluginHostError(PluginErrorCode.missingCredential, "当前 AI 服务商缺少 API Key")
        }

        let messages = (params["messages"] as? [[String: Any]]) ?? []
        let systemPrompt = params["system"] as? String
        let modelOverride = (params["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (modelOverride?.isEmpty == false) ? modelOverride! : profile.model
        let temperature = (params["temperature"] as? Double) ?? profile.temperature
        let maxTokens = (params["maxTokens"] as? Int) ?? profile.maxTokens
        let tools = params["tools"] as? [[String: Any]]

        if profile.provider == "anthropic-compatible" {
            return try await sendAnthropicChat(
                profile: profile, secret: secret, model: model,
                system: systemPrompt, messages: messages,
                tools: tools, maxTokens: maxTokens, temperature: temperature
            )
        } else {
            return try await sendOpenAiChat(
                profile: profile, secret: secret, model: model,
                system: systemPrompt, messages: messages,
                tools: tools, maxTokens: maxTokens, temperature: temperature
            )
        }
    }

    func listModels(pluginId: String) async throws -> [String: Any] {
        let binding = loadBinding(pluginId: pluginId)
        guard let profile = activeProfile(binding: binding) else {
            throw PluginHostError(PluginErrorCode.missingCredential, "尚未配置 AI 服务商")
        }
        let secret = storage.loadAiSecret(pluginId: pluginId, profileId: profile.profileId)
        let urlString = appendPath(profile.baseUrl, segment: "models")
        guard let url = URL(string: urlString) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "无效的 Base URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await performRequest(request)
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw mapHttpError(status: http.statusCode, data: data)
        }
        let rawList = (json["data"] as? [[String: Any]]) ?? []
        let models = rawList.compactMap { $0["id"] as? String }
        return ["models": models]
    }

    func checkBalance(pluginId: String) async throws -> [String: Any] {
        let binding = loadBinding(pluginId: pluginId)
        guard let profile = activeProfile(binding: binding) else {
            throw PluginHostError(PluginErrorCode.missingCredential, "尚未配置 AI 服务商")
        }
        let secret = storage.loadAiSecret(pluginId: pluginId, profileId: profile.profileId)
        guard !secret.isEmpty else {
            throw PluginHostError(PluginErrorCode.missingCredential, "缺少 API Key")
        }
        let cacheKey = "\(pluginId):\(profile.profileId)"
        if let cached = balanceCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < 60 {
            return cached.payload
        }

        let host = URL(string: profile.baseUrl)?.host?.lowercased() ?? ""
        let payload: [String: Any]
        if host.contains("deepseek.com") {
            payload = try await querySimpleBalance(url: "https://api.deepseek.com/user/balance", authHeader: "Bearer \(secret)", provider: "deepseek")
        } else if host.contains("openrouter.ai") {
            payload = try await querySimpleBalance(url: "https://openrouter.ai/api/v1/credits", authHeader: "Bearer \(secret)", provider: "openrouter")
        } else {
            payload = ["supported": false, "provider": balanceProviderName(baseUrl: profile.baseUrl), "message": "当前服务商暂未提供标准余额接口"]
        }
        balanceCache[cacheKey] = (Date(), payload)
        return payload
    }

    // MARK: - HTTP Implementations

    private func sendOpenAiChat(
        profile: PluginAiProfile,
        secret: String,
        model: String,
        system: String?,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        maxTokens: Int,
        temperature: Double
    ) async throws -> [String: Any] {
        let urlString = openAiEndpoint(profile.baseUrl)
        guard let url = URL(string: urlString) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "无效的推理 URL")
        }

        var fullMessages: [[String: Any]] = []
        if let system, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullMessages.append(["role": "system", "content": system])
        }
        fullMessages.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "messages": fullMessages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await performRequest(request)
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw mapHttpError(status: http.statusCode, data: data)
        }

        let choices = (json["choices"] as? [[String: Any]]) ?? []
        let first = choices.first ?? [:]
        let message = (first["message"] as? [String: Any]) ?? [:]
        let text = message["content"] as? String ?? ""
        let reasoning = (message["reasoning_content"] as? String) ?? (message["reasoning"] as? String) ?? ""
        let finishReason = (first["finish_reason"] as? String) ?? "stop"
        var parsedTools: [[String: Any]] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for call in rawCalls {
                let fn = (call["function"] as? [String: Any]) ?? [:]
                parsedTools.append([
                    "id": call["id"] as? String ?? "",
                    "name": fn["name"] as? String ?? "",
                    "arguments": fn["arguments"] as? String ?? "{}"
                ])
            }
        }
        let usage = (json["usage"] as? [String: Any]) ?? [:]
        return [
            "text": text,
            "reasoning": reasoning,
            "toolCalls": parsedTools,
            "finishReason": finishReason,
            "model": (json["model"] as? String) ?? model,
            "usage": [
                "inputTokens": (usage["prompt_tokens"] as? Int) ?? 0,
                "outputTokens": (usage["completion_tokens"] as? Int) ?? 0
            ]
        ]
    }

    private func sendAnthropicChat(
        profile: PluginAiProfile,
        secret: String,
        model: String,
        system: String?,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        maxTokens: Int,
        temperature: Double
    ) async throws -> [String: Any] {
        let trimmed = profile.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = trimmed.hasSuffix("/v1/messages") ? trimmed : (trimmed.hasSuffix("/v1") ? "\(trimmed)/messages" : "\(trimmed)/v1/messages")
        guard let url = URL(string: urlString) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "无效的 Anthropic URL")
        }

        var convertedMessages: [[String: Any]] = []
        for msg in messages {
            let role = (msg["role"] as? String) == "assistant" ? "assistant" : "user"
            let content = msg["content"] ?? ""
            convertedMessages.append(["role": role, "content": content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": convertedMessages,
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        if let system, !system.isEmpty {
            body["system"] = system
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools.compactMap { item -> [String: Any]? in
                let fn = (item["function"] as? [String: Any]) ?? item
                guard let name = fn["name"] as? String else { return nil }
                return [
                    "name": name,
                    "description": fn["description"] as? String ?? "",
                    "input_schema": fn["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]]
                ]
            }
        }

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await performRequest(request)
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw mapHttpError(status: http.statusCode, data: data)
        }

        var textParts: [String] = []
        var parsedTools: [[String: Any]] = []
        if let blocks = json["content"] as? [[String: Any]] {
            for block in blocks {
                let kind = block["type"] as? String ?? ""
                if kind == "text", let t = block["text"] as? String {
                    textParts.append(t)
                } else if kind == "tool_use" {
                    let inputData = (try? JSONSerialization.data(withJSONObject: block["input"] ?? [:])) ?? Data()
                    parsedTools.append([
                        "id": block["id"] as? String ?? "",
                        "name": block["name"] as? String ?? "",
                        "arguments": String(data: inputData, encoding: .utf8) ?? "{}"
                    ])
                }
            }
        }
        let usage = (json["usage"] as? [String: Any]) ?? [:]
        return [
            "text": textParts.joined(),
            "reasoning": "",
            "toolCalls": parsedTools,
            "finishReason": (json["stop_reason"] as? String) ?? "stop",
            "model": (json["model"] as? String) ?? model,
            "usage": [
                "inputTokens": (usage["input_tokens"] as? Int) ?? 0,
                "outputTokens": (usage["output_tokens"] as? Int) ?? 0
            ]
        ]
    }

    private func querySimpleBalance(url urlString: String, authHeader: String, provider: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            return ["supported": false, "provider": provider]
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (data, http) = try await performRequest(request)
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["supported": true, "provider": provider, "error": "HTTP \(http.statusCode)"]
        }
        var result = json
        result["supported"] = true
        result["provider"] = provider
        return result
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let err as URLError where err.code == .timedOut {
            throw PluginHostError(PluginErrorCode.timeout, "AI 请求超时")
        } catch {
            throw PluginHostError(PluginErrorCode.io, "网络请求失败：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw PluginHostError(PluginErrorCode.io, "无效的 HTTP 响应")
        }
        return (data, http)
    }

    private func mapHttpError(status: Int, data: Data) -> PluginHostError {
        let text = String(data: data, encoding: .utf8) ?? ""
        if status == 401 || status == 403 {
            return PluginHostError(PluginErrorCode.invalidCredential, "API Key 无效或无权限（HTTP \(status)）")
        }
        if status == 429 {
            return PluginHostError(PluginErrorCode.rateLimited, "模型请求频率或配额受限（HTTP 429）")
        }
        if status == 404 {
            return PluginHostError(PluginErrorCode.modelUnavailable, "模型或推理接口不可用（HTTP 404）")
        }
        return PluginHostError(PluginErrorCode.pluginFailed, "AI 请求失败（HTTP \(status)）：\(String(text.prefix(200)))")
    }

    // MARK: - Helpers

    private func activeProfile(binding: PluginAiBinding) -> PluginAiProfile? {
        if !binding.activeProfileId.isEmpty,
           let match = binding.profiles.first(where: { $0.profileId == binding.activeProfileId }) {
            return match
        }
        return binding.profiles.first
    }

    private func normalizeProvider(_ raw: String?) -> String {
        let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "anthropic" || cleaned == "anthropic-compatible" {
            return "anthropic-compatible"
        }
        return "openai-compatible"
    }

    private func normalizeBaseUrl(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请输入合法的模型服务地址")
        }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "远程服务必须使用 HTTPS（本地调试可使用 http://127.0.0.1）")
        }
        return trimmed
    }

    private func needsApiKey(baseUrl: String) -> Bool {
        let host = URL(string: baseUrl)?.host?.lowercased() ?? ""
        return !(host == "127.0.0.1" || host == "localhost" || host == "::1")
    }

    private func appendPath(_ baseUrl: String, segment: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/v1") {
            return "\(trimmed)/\(segment)"
        }
        return "\(trimmed)/v1/\(segment)"
    }

    private func openAiEndpoint(_ baseUrl: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") { return trimmed }
        if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/v4") {
            return "\(trimmed)/chat/completions"
        }
        return "\(trimmed)/v1/chat/completions"
    }

    private func balanceProviderName(baseUrl: String) -> String {
        let host = URL(string: baseUrl)?.host?.lowercased() ?? ""
        if host.contains("deepseek.com") { return "deepseek" }
        if host.contains("openrouter.ai") { return "openrouter" }
        if host.contains("bigmodel.cn") || host.contains("z.ai") { return "glm" }
        if host.contains("kimi.com") { return "kimi" }
        if host.contains("minimaxi.com") || host.contains("minimax") { return "minimax" }
        return ""
    }
}
