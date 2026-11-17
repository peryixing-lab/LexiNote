import Foundation

/// Host-managed AI proxy for plugins. Keeps provider credentials in isolated host files
/// and never returns API keys back to the JS sandbox.
final class PluginAiService {
    private let storage: PluginStorage
    private var balanceCache: [String: (timestamp: Date, payload: [String: Any])] = [:]
    /// Optional environment override map (used in self-tests to exercise `env` credential fallback without mutating process env).
    var envOverrides: [String: String] = [:]

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

    private static let maxProfiles = 32
    private static let profileIdRegex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_.-]{1,64}$")
    private static let credentialRefRegex = try? NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9_]*$")
    private static let envLineRegex = try? NSRegularExpression(pattern: "^[A-Z][A-Z0-9_]*=[^=]")

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
                "maxTokens": 8192,
                "temperature": 0.3,
                "balanceProvider": "",
                "needsApiKey": true,
                "credentialRef": "",
                "credentialSource": "",
                "credentialWritable": true,
                "maskedApiKey": "",
                "credential": [
                    "ref": "",
                    "configured": false,
                    "writable": true
                ],
                "profiles": []
            ]
        }

        let activeCred = (try? resolveCredential(pluginId: pluginId, profile: active)) ?? (secret: "", source: nil, ref: resolvedCredentialRef(for: active))
        let configured = !active.baseUrl.isEmpty && !active.model.isEmpty && (!needsApiKey(baseUrl: active.baseUrl) || !activeCred.secret.isEmpty)
        let activeMasked = Self.maskCredential(activeCred.secret)

        let profilesList: [[String: Any]] = binding.profiles.map { profile in
            let itemCred = (try? resolveCredential(pluginId: pluginId, profile: profile)) ?? (secret: "", source: nil, ref: resolvedCredentialRef(for: profile))
            let itemConfigured = !profile.baseUrl.isEmpty && !profile.model.isEmpty && (!needsApiKey(baseUrl: profile.baseUrl) || !itemCred.secret.isEmpty)
            let itemMasked = Self.maskCredential(itemCred.secret)
            var entry: [String: Any] = [
                "profileId": profile.profileId,
                "name": profile.name,
                "provider": profile.provider,
                "baseUrl": profile.baseUrl,
                "model": profile.model,
                "maxTokens": profile.maxTokens,
                "temperature": profile.temperature,
                "balanceProvider": balanceProviderName(baseUrl: profile.baseUrl),
                "hasKey": !itemCred.secret.isEmpty,
                "configured": itemConfigured,
                "needsApiKey": !itemConfigured,
                "credentialRef": itemCred.ref,
                "credentialSource": itemCred.source ?? "",
                "credentialWritable": true,
                "maskedApiKey": itemMasked,
                "credential": credentialInfoDictionary(
                    ref: itemCred.ref,
                    configured: !itemCred.secret.isEmpty,
                    source: itemCred.source,
                    masked: itemMasked
                )
            ]
            if let compat = compatDictionary(profile.compat) {
                entry["compat"] = compat
            }
            if let retryPolicy = retryPolicyDictionary(profile.retryPolicy) {
                entry["retryPolicy"] = retryPolicy
            }
            return entry
        }

        var result: [String: Any] = [
            "configured": configured,
            "profileId": active.profileId,
            "name": active.name,
            "provider": active.provider,
            "baseUrl": active.baseUrl,
            "model": active.model,
            "maxTokens": active.maxTokens,
            "temperature": active.temperature,
            "balanceProvider": balanceProviderName(baseUrl: active.baseUrl),
            "needsApiKey": !configured,
            "credentialRef": activeCred.ref,
            "credentialSource": activeCred.source ?? "",
            "credentialWritable": true,
            "maskedApiKey": activeMasked,
            "credential": credentialInfoDictionary(
                ref: activeCred.ref,
                configured: !activeCred.secret.isEmpty,
                source: activeCred.source,
                masked: activeMasked
            ),
            "profiles": profilesList
        ]
        if let compat = compatDictionary(active.compat) {
            result["compat"] = compat
        }
        if let retryPolicy = retryPolicyDictionary(active.retryPolicy) {
            result["retryPolicy"] = retryPolicy
        }
        return result
    }

    func configure(pluginId: String, params: [String: Any]) throws -> [String: Any] {
        let action = resolveConfigureAction(params: params)
        var binding = loadBinding(pluginId: pluginId)

        switch action {
        case "clear":
            storage.clearAiConfig(pluginId: pluginId)
            balanceCache.removeAll()
            return statusDictionary(pluginId: pluginId)

        case "select":
            return try selectProfile(pluginId: pluginId, binding: &binding, params: params)

        case "remove":
            return try removeProfile(pluginId: pluginId, binding: &binding, params: params)

        case "create", "save", "upsert":
            return try upsertProfile(pluginId: pluginId, binding: &binding, action: action, params: params)

        case "clearcredential":
            let requestedId = (params["profileId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let targetId = requestedId.isEmpty ? binding.activeProfileId : requestedId
            guard !targetId.isEmpty, binding.profiles.contains(where: { $0.profileId == targetId }) else {
                throw PluginHostError(PluginErrorCode.notFound, "未找到指定的 AI 服务商配置")
            }
            try storage.saveAiSecret(pluginId: pluginId, profileId: targetId, secret: "")
            balanceCache.removeValue(forKey: "\(pluginId):\(targetId)")
            return statusDictionary(pluginId: pluginId)

        default:
            throw PluginHostError(PluginErrorCode.invalidArgument, "未知配置操作：\(action)")
        }
    }

    private func resolveConfigureAction(params: [String: Any]) -> String {
        if params["clear"] as? Bool == true {
            return "clear"
        }
        if params["remove"] as? Bool == true {
            return "remove"
        }
        let raw = (params["action"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw.isEmpty ? "save" : raw
    }

    private func selectProfile(pluginId: String, binding: inout PluginAiBinding, params: [String: Any]) throws -> [String: Any] {
        guard let rawId = params["profileId"] as? String else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "缺少服务商标识")
        }
        let targetId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetId.isEmpty else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "缺少服务商标识")
        }
        guard let found = binding.profiles.first(where: { $0.profileId == targetId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "未找到指定的 AI 服务商配置")
        }
        let cred = try resolveCredential(pluginId: pluginId, profile: found)
        if needsApiKey(baseUrl: found.baseUrl) && cred.secret.isEmpty {
            throw PluginHostError(PluginErrorCode.missingCredential, "请先编辑此服务商补填 API Key")
        }
        binding.activeProfileId = targetId
        try saveBinding(pluginId: pluginId, binding: binding)
        balanceCache.removeValue(forKey: "\(pluginId):\(targetId)")
        return statusDictionary(pluginId: pluginId)
    }

    private func removeProfile(pluginId: String, binding: inout PluginAiBinding, params: [String: Any]) throws -> [String: Any] {
        guard let rawId = params["profileId"] as? String else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 profileId")
        }
        let targetId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetId.isEmpty else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "缺少 profileId")
        }
        guard binding.profiles.contains(where: { $0.profileId == targetId }) else {
            throw PluginHostError(PluginErrorCode.notFound, "服务商不存在，请刷新后重试")
        }
        binding.profiles.removeAll { $0.profileId == targetId }
        try storage.saveAiSecret(pluginId: pluginId, profileId: targetId, secret: "")
        if binding.activeProfileId == targetId {
            binding.activeProfileId = binding.profiles.first?.profileId ?? ""
        }
        try saveBinding(pluginId: pluginId, binding: binding)
        balanceCache.removeValue(forKey: "\(pluginId):\(targetId)")
        return statusDictionary(pluginId: pluginId)
    }

    private func upsertProfile(
        pluginId: String,
        binding: inout PluginAiBinding,
        action: String,
        params: [String: Any]
    ) throws -> [String: Any] {
        let requestedId = (params["profileId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedId: String
        if !requestedId.isEmpty {
            resolvedId = requestedId
        } else if action != "create", !binding.activeProfileId.isEmpty {
            resolvedId = binding.activeProfileId
        } else {
            resolvedId = Self.generateProfileId()
        }
        guard Self.isValidProfileId(resolvedId) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "服务商标识非法")
        }

        let existingIndex = binding.profiles.firstIndex(where: { $0.profileId == resolvedId })
        let creating = existingIndex == nil
        if creating && binding.profiles.count >= Self.maxProfiles {
            throw PluginHostError(PluginErrorCode.quotaExceeded, "最多保存 \(Self.maxProfiles) 个 AI 服务商配置")
        }

        var profile = existingIndex.map { binding.profiles[$0] } ?? PluginAiProfile(
            profileId: resolvedId,
            name: "",
            provider: "openai-compatible",
            baseUrl: "",
            model: "",
            maxTokens: 8192,
            temperature: 0.3
        )
        profile.profileId = resolvedId

        if let rawName = params["name"] as? String {
            let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedName.count <= 64 else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "服务商名称最多 64 字符")
            }
            profile.name = trimmedName
        }

        if let rawProvider = params["provider"] as? String {
            let trimmedProvider = rawProvider.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedProvider.isEmpty {
                guard let normalized = normalizeProviderStrict(trimmedProvider) else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "模型服务类型只能是 openai-compatible 或 anthropic-compatible")
                }
                profile.provider = normalized
            }
        }

        var baseUrlChanged = false
        if let rawBaseUrl = params["baseUrl"] as? String {
            let trimmedBaseUrl = rawBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBaseUrl.isEmpty {
                let nextBaseUrl = try normalizeBaseUrl(trimmedBaseUrl)
                baseUrlChanged = !creating && nextBaseUrl != profile.baseUrl
                profile.baseUrl = nextBaseUrl
            }
        }
        guard !profile.baseUrl.isEmpty else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请填写 Base URL")
        }

        if let rawModel = params["model"] as? String {
            let trimmedModel = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                guard trimmedModel.count <= 128 else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "模型名称长度必须在 1-128 之间")
                }
                profile.model = trimmedModel
            } else if profile.model.isEmpty {
                throw PluginHostError(PluginErrorCode.invalidArgument, "模型名称不能为空")
            }
        } else if profile.model.isEmpty {
            throw PluginHostError(PluginErrorCode.invalidArgument, "模型名称不能为空")
        }

        if let maxTokens = extractInt(params["maxTokens"]), maxTokens > 0 {
            profile.maxTokens = max(256, min(32_768, maxTokens))
        }
        if let temperature = extractDouble(params["temperature"]), temperature.isFinite, temperature >= 0 {
            profile.temperature = max(0.0, min(2.0, temperature))
        }

        if let rawCredRef = params["credentialRef"] as? String {
            let trimmedRef = rawCredRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRef.isEmpty {
                guard Self.isValidCredentialRef(trimmedRef) else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "credentialRef 需为合法的环境变量名（^[A-Za-z_][A-Za-z0-9_]*$）")
                }
                profile.credentialRef = trimmedRef
            } else {
                profile.credentialRef = nil
            }
        }
        if (profile.credentialRef ?? "").isEmpty {
            profile.credentialRef = Self.defaultCredentialRef(provider: profile.provider, baseUrl: profile.baseUrl, profileId: profile.profileId)
        }

        if let rawCompat = params["compat"] as? [String: Any] {
            var nextCompat = profile.compat ?? PluginAiCompatConfig()
            if let field = rawCompat["maxTokensField"] as? String {
                let normalizedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedField == "max_tokens" || normalizedField == "max_completion_tokens" {
                    nextCompat.maxTokensField = normalizedField
                } else if normalizedField.isEmpty {
                    nextCompat.maxTokensField = nil
                } else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "compat.maxTokensField 只能为 max_tokens 或 max_completion_tokens")
                }
            }
            if let thinking = rawCompat["thinkingFormat"] as? String {
                let trimmedThinking = thinking.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let allowed = ["auto", "openai", "deepseek", "openrouter", "zai", "qwen", "chat-template"]
                if trimmedThinking.isEmpty {
                    nextCompat.thinkingFormat = nil
                } else if allowed.contains(trimmedThinking) {
                    nextCompat.thinkingFormat = trimmedThinking
                } else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "不支持的 compat.thinkingFormat：\(trimmedThinking)")
                }
            }
            if let supportsDev = rawCompat["supportsDeveloperRole"] as? Bool {
                nextCompat.supportsDeveloperRole = supportsDev
            }
            profile.compat = (nextCompat.maxTokensField == nil && nextCompat.thinkingFormat == nil && nextCompat.supportsDeveloperRole == nil) ? nil : nextCompat
        }

        if let rawRetry = params["retryPolicy"] as? [String: Any] {
            var nextRetry = profile.retryPolicy ?? PluginAiRetryPolicy()
            if let mode = rawRetry["mode"] as? String {
                let trimmedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmedMode == "normal" || trimmedMode == "off" {
                    nextRetry.mode = trimmedMode
                } else if trimmedMode.isEmpty {
                    nextRetry.mode = nil
                } else {
                    throw PluginHostError(PluginErrorCode.invalidArgument, "retryPolicy.mode 只能为 normal 或 off")
                }
            }
            if let maxRetries = extractInt(rawRetry["maxRetries"]) {
                nextRetry.maxRetries = max(0, min(3, maxRetries))
            }
            profile.retryPolicy = (nextRetry.mode == nil && nextRetry.maxRetries == nil) ? nil : nextRetry
        }

        let clearApiKey = (params["clearApiKey"] as? Bool) == true
        let rawApiKey = params["apiKey"] as? String
        if let rawApiKey, !rawApiKey.isEmpty, rawApiKey != "__KEEP__",
           rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginHostError(PluginErrorCode.invalidArgument, "API Key 不能为空白字符，请粘贴完整密钥或留空以保持现有配置")
        }
        let apiKeyInput = (rawApiKey == "__KEEP__" ? "" : (rawApiKey ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = try validateApiKey(apiKeyInput)

        let effectiveEnvCred = envCredential(for: resolvedCredentialRef(for: profile))
        if !clearApiKey && creating && needsApiKey(baseUrl: profile.baseUrl) && cleanKey.isEmpty && effectiveEnvCred.isEmpty {
            throw PluginHostError(PluginErrorCode.missingCredential, "首次绑定需要填写 API Key")
        }
        if !clearApiKey && !creating && baseUrlChanged && !storage.loadAiSecret(pluginId: pluginId, profileId: resolvedId).isEmpty && cleanKey.isEmpty {
            throw PluginHostError(PluginErrorCode.invalidArgument, "更换 Base URL 时请重新填写 API Key")
        }

        if let idx = existingIndex {
            binding.profiles[idx] = profile
        } else {
            binding.profiles.append(profile)
        }
        let shouldSelect = (params["select"] as? Bool) ?? true
        if shouldSelect || binding.activeProfileId.isEmpty {
            binding.activeProfileId = resolvedId
        }

        let previousSecret = (wroteOrClearingKey(clearApiKey: clearApiKey, cleanKey: cleanKey))
            ? storage.loadAiSecret(pluginId: pluginId, profileId: resolvedId)
            : ""
        var wroteKey = false
        if clearApiKey && cleanKey.isEmpty {
            try storage.saveAiSecret(pluginId: pluginId, profileId: resolvedId, secret: "")
            wroteKey = true
        } else if !cleanKey.isEmpty {
            try storage.saveAiSecret(pluginId: pluginId, profileId: resolvedId, secret: cleanKey)
            wroteKey = true
        }
        do {
            try saveBinding(pluginId: pluginId, binding: binding)
        } catch {
            if wroteKey {
                try? storage.saveAiSecret(pluginId: pluginId, profileId: resolvedId, secret: previousSecret)
            }
            throw error
        }
        balanceCache.removeValue(forKey: "\(pluginId):\(resolvedId)")
        return statusDictionary(pluginId: pluginId)
    }

    private func wroteOrClearingKey(clearApiKey: Bool, cleanKey: String) -> Bool {
        clearApiKey || !cleanKey.isEmpty
    }

    /// UI helper called directly from native Swift settings / popover forms.
    func saveQuickProfile(pluginId: String, profile: PluginAiProfile, apiKey: String?) throws {
        var params: [String: Any] = [
            "action": "save",
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
        // Per-request dynamic resolution so key changes apply on the next request without plugin reload.
        let cred = try resolveCredential(pluginId: pluginId, profile: profile)
        let secret = cred.secret
        if needsApiKey(baseUrl: profile.baseUrl) && secret.isEmpty {
            throw PluginHostError(PluginErrorCode.missingCredential, "当前 AI 服务商缺少 API Key")
        }

        let messages = (params["messages"] as? [[String: Any]]) ?? []
        let systemPrompt = params["system"] as? String
        let modelOverride = (params["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (modelOverride?.isEmpty == false) ? modelOverride! : profile.model
        let requestedTemp = extractDouble(params["temperature"])
        let temperature = (requestedTemp != nil && requestedTemp!.isFinite && requestedTemp! >= 0)
            ? max(0.0, min(2.0, requestedTemp!))
            : profile.temperature
        let requestedMaxTokens = extractInt(params["maxTokens"])
        let maxTokens = (requestedMaxTokens ?? 0) > 0
            ? max(256, min(32_768, requestedMaxTokens!))
            : profile.maxTokens
        let tools = params["tools"] as? [[String: Any]]

        if isAnthropic(profile) {
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
        let secret = try resolveCredential(pluginId: pluginId, profile: profile).secret
        let urlString = appendPath(profile.baseUrl, segment: "models")
        guard let url = URL(string: urlString) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "无效的 Base URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await performRequestWithRetry(request, policy: profile.retryPolicy)
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
        let secret = try resolveCredential(pluginId: pluginId, profile: profile).secret
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

        let body = Self.openAiChatBody(
            model: model,
            system: system,
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature,
            compat: profile.compat
        )

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await performRequestWithRetry(request, policy: profile.retryPolicy)
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

        let body = Self.anthropicChatBody(
            model: model,
            system: system,
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature
        )

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await performRequestWithRetry(request, policy: profile.retryPolicy)
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

    // MARK: - Provider Wire Serialization

    private static func emptyToolSchema() -> [String: Any] {
        ["type": "object", "properties": [String: Any](), "required": [String]()]
    }

    private static func jsonArgumentsString(from value: Any?) -> String {
        if let str = value as? String {
            return str.isEmpty ? "{}" : str
        }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }
        return "{}"
    }

    private static func normalizedToolSpec(_ item: [String: Any]) -> (name: String, description: String, parameters: [String: Any])? {
        let fn = ((item["type"] as? String) == "function" ? (item["function"] as? [String: Any]) : nil)
            ?? (item["function"] as? [String: Any])
            ?? item
        guard let rawName = fn["name"] as? String else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let description = fn["description"] as? String ?? ""
        let parameters = (fn["parameters"] as? [String: Any]) ?? emptyToolSchema()
        return (name, description, parameters)
    }

    /// Converts flat plugin tool declarations (`{name, description, parameters}`) into OpenAI `tools` format.
    static func openAiTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { item in
            guard let spec = normalizedToolSpec(item) else { return nil }
            return [
                "type": "function",
                "function": [
                    "name": spec.name,
                    "description": spec.description,
                    "parameters": spec.parameters
                ]
            ]
        }
    }

    private static func openAiToolCalls(from message: [String: Any]) -> [[String: Any]] {
        let rawCalls = (message["toolCalls"] as? [[String: Any]])
            ?? (message["tool_calls"] as? [[String: Any]])
            ?? []
        var converted: [[String: Any]] = []
        for (index, call) in rawCalls.enumerated() {
            let fn = (call["function"] as? [String: Any]) ?? call
            let rawName = (fn["name"] as? String) ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let rawId = (call["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = (rawId?.isEmpty == false) ? rawId! : "call_\(index)"
            let args = jsonArgumentsString(from: fn["arguments"])
            converted.append([
                "id": id,
                "type": "function",
                "function": [
                    "name": name,
                    "arguments": args
                ]
            ])
        }
        return converted
    }

    /// Converts Harness plugin messages (`assistant.toolCalls`, `tool.toolCallId`) into OpenAI Chat Completions wire messages.
    static func openAiMessages(
        _ messages: [[String: Any]],
        system: String? = nil,
        supportsDeveloperRole: Bool = false
    ) -> [[String: Any]] {
        var result: [[String: Any]] = []
        let systemRole = supportsDeveloperRole ? "developer" : "system"
        if let system, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(["role": systemRole, "content": system])
        }
        for msg in messages {
            let role = (msg["role"] as? String) ?? "user"
            let contentText = msg["content"] as? String ?? ""
            if role == "assistant" {
                var entry: [String: Any] = ["role": "assistant", "content": contentText]
                let calls = openAiToolCalls(from: msg)
                if !calls.isEmpty {
                    entry["tool_calls"] = calls
                }
                result.append(entry)
            } else if role == "tool" {
                let toolCallId = (msg["toolCallId"] as? String) ?? (msg["tool_call_id"] as? String) ?? ""
                result.append([
                    "role": "tool",
                    "tool_call_id": toolCallId,
                    "content": contentText.isEmpty ? "Done" : contentText
                ])
            } else {
                let contentValue: Any = msg["content"] is String ? contentText : (msg["content"] ?? "")
                result.append([
                    "role": role == "system" ? systemRole : "user",
                    "content": contentValue
                ])
            }
        }
        return result
    }

    static func openAiChatBody(
        model: String,
        system: String?,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        maxTokens: Int,
        temperature: Double,
        compat: PluginAiCompatConfig? = nil
    ) -> [String: Any] {
        let maxTokensField = compat?.maxTokensField == "max_completion_tokens"
            ? "max_completion_tokens"
            : "max_tokens"
        let supportsDev = compat?.supportsDeveloperRole == true
        var body: [String: Any] = [
            "model": model,
            "messages": openAiMessages(messages, system: system, supportsDeveloperRole: supportsDev),
            maxTokensField: maxTokens,
            "temperature": temperature,
            "stream": false
        ]
        if let tools, !tools.isEmpty {
            let wireTools = openAiTools(tools)
            if !wireTools.isEmpty {
                body["tools"] = wireTools
            }
        }
        return body
    }

    /// Converts flat plugin tool declarations into Anthropic Messages API `tools` format.
    static func anthropicTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { item in
            guard let spec = normalizedToolSpec(item) else { return nil }
            return [
                "name": spec.name,
                "description": spec.description,
                "input_schema": spec.parameters
            ]
        }
    }

    /// Converts Harness plugin messages into Anthropic `messages` and merged `system` text.
    static func anthropicMessages(_ messages: [[String: Any]], system: String? = nil) -> (messages: [[String: Any]], systemPrompt: String) {
        var systemParts: [String] = []
        if let system, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(system.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var converted: [[String: Any]] = []
        for msg in messages {
            let role = (msg["role"] as? String) ?? "user"
            let contentText = msg["content"] as? String ?? ""
            if role == "system" {
                let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    systemParts.append(trimmed)
                }
                continue
            }
            if role == "assistant" {
                var blocks: [[String: Any]] = []
                if !contentText.isEmpty {
                    blocks.append(["type": "text", "text": contentText])
                }
                let rawCalls = (msg["toolCalls"] as? [[String: Any]]) ?? []
                for (index, call) in rawCalls.enumerated() {
                    let name = (call["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !name.isEmpty else { continue }
                    let rawId = (call["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = (rawId?.isEmpty == false) ? rawId! : "toolu_\(index)"
                    let argsString = jsonArgumentsString(from: call["arguments"])
                    let parsedInput: [String: Any]
                    if let data = argsString.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        parsedInput = obj
                    } else {
                        parsedInput = [:]
                    }
                    blocks.append([
                        "type": "tool_use",
                        "id": id,
                        "name": name,
                        "input": parsedInput
                    ])
                }
                if !blocks.isEmpty {
                    converted.append(["role": "assistant", "content": blocks])
                }
                continue
            }
            let block: [String: Any]
            if role == "tool" {
                let toolCallId = (msg["toolCallId"] as? String) ?? (msg["tool_call_id"] as? String) ?? ""
                block = [
                    "type": "tool_result",
                    "tool_use_id": toolCallId,
                    "content": contentText.isEmpty ? "OK" : contentText,
                    "is_error": (msg["isError"] as? Bool) ?? (msg["is_error"] as? Bool) ?? false
                ]
            } else {
                block = ["type": "text", "text": contentText]
            }
            if var last = converted.last,
               (last["role"] as? String) == "user",
               var existingBlocks = last["content"] as? [[String: Any]] {
                if role == "tool" {
                    existingBlocks.insert(block, at: 0)
                } else {
                    existingBlocks.append(block)
                }
                last["content"] = existingBlocks
                converted[converted.count - 1] = last
            } else {
                converted.append(["role": "user", "content": [block]])
            }
        }
        return (converted, systemParts.joined(separator: "\n\n"))
    }

    static func anthropicChatBody(
        model: String,
        system: String?,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        maxTokens: Int,
        temperature: Double
    ) -> [String: Any] {
        let converted = anthropicMessages(messages, system: system)
        var body: [String: Any] = [
            "model": model,
            "messages": converted.messages,
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        if !converted.systemPrompt.isEmpty {
            body["system"] = converted.systemPrompt
        }
        if let tools, !tools.isEmpty {
            let wireTools = anthropicTools(tools)
            if !wireTools.isEmpty {
                body["tools"] = wireTools
            }
        }
        return body
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

    private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let noRedirectDelegate = NoRedirectSessionDelegate()
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: noRedirectDelegate, delegateQueue: nil)
    }()

    private func performRequestWithRetry(_ request: URLRequest, policy: PluginAiRetryPolicy?) async throws -> (Data, HTTPURLResponse) {
        let mode = (policy?.mode ?? "off").lowercased()
        let maxRetries = mode == "normal" ? max(0, min(3, policy?.maxRetries ?? 1)) : 0
        var attempt = 0
        while true {
            do {
                let (data, http) = try await performRequest(request)
                let retryableStatus = http.statusCode == 429 || http.statusCode == 502 || http.statusCode == 503 || http.statusCode == 504
                if retryableStatus && attempt < maxRetries {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(150_000_000 * attempt))
                    continue
                }
                return (data, http)
            } catch let err as PluginHostError where (err.code == PluginErrorCode.timeout || err.code == PluginErrorCode.io) && attempt < maxRetries {
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(150_000_000 * attempt))
            }
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.noRedirectSession.data(for: request)
        } catch let err as URLError where err.code == .timedOut {
            throw PluginHostError(PluginErrorCode.timeout, "AI 请求超时")
        } catch {
            throw PluginHostError(PluginErrorCode.io, "网络请求失败：\(Self.redactSecrets(error.localizedDescription))")
        }
        guard let http = response as? HTTPURLResponse else {
            throw PluginHostError(PluginErrorCode.io, "无效的 HTTP 响应")
        }
        if (300...399).contains(http.statusCode) {
            throw PluginHostError(PluginErrorCode.invalidArgument, "为保护 API Key，模型请求拒绝 HTTP 重定向（HTTP \(http.statusCode)）")
        }
        return (data, http)
    }

    private func mapHttpError(status: Int, data: Data) -> PluginHostError {
        let text = Self.redactSecrets(String(data: data, encoding: .utf8) ?? "")
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

    // MARK: - Helpers (DeepSeek-Harness Credential & Compat Model)

    static func maskCredential(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else { return "" }
        let sepIdx = scalars.firstIndex(where: { $0 == "-" || $0 == "_" })
        let providerEnd = sepIdx.map { $0 + 1 } ?? 0
        let hidden = scalars.count - providerEnd - 5 - 4
        if hidden < 8 {
            return String(repeating: "\u{2022}", count: scalars.count)
        }
        let prefix = String(String.UnicodeScalarView(scalars.prefix(providerEnd + 5)))
        let suffix = String(String.UnicodeScalarView(scalars.suffix(4)))
        return prefix + String(repeating: "\u{2022}", count: hidden) + suffix
    }

    static func isValidCredentialRef(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        let range = NSRange(location: 0, length: ref.utf16.count)
        return credentialRefRegex?.firstMatch(in: ref, range: range) != nil
    }

    static func defaultCredentialRef(provider: String, baseUrl: String, profileId: String) -> String {
        let host = URL(string: baseUrl)?.host?.lowercased() ?? ""
        if host.contains("deepseek.com") { return "DEEPSEEK_API_KEY" }
        if host.contains("anthropic.com") || provider == "anthropic-compatible" { return "ANTHROPIC_API_KEY" }
        if host.contains("openrouter.ai") { return "OPENROUTER_API_KEY" }
        if host.contains("siliconflow.cn") { return "SILICONFLOW_API_KEY" }
        if host.contains("bigmodel.cn") || host.contains("z.ai") { return "ZHIPU_API_KEY" }
        if host.contains("kimi.com") || host.contains("moonshot.cn") { return "MOONSHOT_API_KEY" }
        if host.contains("minimaxi.com") || host.contains("minimax.io") { return "MINIMAX_API_KEY" }
        if host.contains("openai.com") { return "OPENAI_API_KEY" }
        let sanitized = profileId.uppercased().map { ch -> Character in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) ? ch : "_"
        }
        let cleaned = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if cleaned.isEmpty { return "OPENAI_API_KEY" }
        let lead = cleaned.first?.isNumber == true ? "KEY_" : ""
        return "\(lead)\(cleaned)_API_KEY"
    }

    private func resolvedCredentialRef(for profile: PluginAiProfile) -> String {
        if let ref = profile.credentialRef, !ref.isEmpty, Self.isValidCredentialRef(ref) {
            return ref
        }
        return Self.defaultCredentialRef(provider: profile.provider, baseUrl: profile.baseUrl, profileId: profile.profileId)
    }

    private func envCredential(for ref: String) -> String {
        guard !ref.isEmpty else { return "" }
        let raw = envOverrides[ref] ?? ProcessInfo.processInfo.environment[ref] ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveCredential(pluginId: String, profile: PluginAiProfile) throws -> (secret: String, source: String?, ref: String) {
        let ref = resolvedCredentialRef(for: profile)
        let stored = try storage.resolveStoredSecret(pluginId: pluginId, profileId: profile.profileId)
        if !stored.isEmpty {
            return (stored, "store", ref)
        }
        let fromEnv = envCredential(for: ref)
        if !fromEnv.isEmpty {
            return (fromEnv, "env", ref)
        }
        return ("", nil, ref)
    }

    private func credentialInfoDictionary(ref: String, configured: Bool, source: String?, masked: String) -> [String: Any] {
        var info: [String: Any] = [
            "ref": ref,
            "configured": configured,
            "writable": true
        ]
        if let source, !source.isEmpty {
            info["source"] = source
        }
        if !masked.isEmpty {
            info["masked"] = masked
        }
        return info
    }

    private func compatDictionary(_ compat: PluginAiCompatConfig?) -> [String: Any]? {
        guard let compat else { return nil }
        var out: [String: Any] = [:]
        if let maxTokensField = compat.maxTokensField { out["maxTokensField"] = maxTokensField }
        if let thinkingFormat = compat.thinkingFormat { out["thinkingFormat"] = thinkingFormat }
        if let supportsDeveloperRole = compat.supportsDeveloperRole { out["supportsDeveloperRole"] = supportsDeveloperRole }
        return out.isEmpty ? nil : out
    }

    private func retryPolicyDictionary(_ policy: PluginAiRetryPolicy?) -> [String: Any]? {
        guard let policy else { return nil }
        var out: [String: Any] = [:]
        if let mode = policy.mode { out["mode"] = mode }
        if let maxRetries = policy.maxRetries { out["maxRetries"] = maxRetries }
        return out.isEmpty ? nil : out
    }

    func validateApiKey(_ raw: String) throws -> String {
        guard !raw.isEmpty else { return "" }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "API Key 不能为空白字符")
        }
        guard clean.count <= 8192 else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "API Key 长度超出限制")
        }
        if (clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count >= 2)
            || (clean.hasPrefix("'") && clean.hasSuffix("'") && clean.count >= 2)
            || (clean.hasPrefix("`") && clean.hasSuffix("`") && clean.count >= 2) {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请去掉 API Key 首尾的引号")
        }
        let nsRange = NSRange(location: 0, length: clean.utf16.count)
        if Self.envLineRegex?.firstMatch(in: clean, range: nsRange) != nil {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请只粘贴 API Key 值本身，不要包含 ENV_VAR= 前缀")
        }
        for scalar in clean.unicodeScalars {
            guard scalar.value >= 0x21 && scalar.value <= 0x7E else {
                throw PluginHostError(PluginErrorCode.invalidArgument, "API Key 包含无效字符或空白符")
            }
        }
        return clean
    }

    static func redactSecrets(_ text: String, knownSecret: String = "") -> String {
        var out = text
        if !knownSecret.isEmpty {
            out = out.replacingOccurrences(of: knownSecret, with: "[REDACTED]")
        }
        let patterns = [
            "(?i)(Bearer\\s+)[A-Za-z0-9._\\-+=/]+",
            "(?i)(x-api-key\\s*[:=]\\s*)[^\\s,;\"']+",
            "\\bsk-[A-Za-z0-9._\\-]{8,}"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                if pattern.contains("(") {
                    out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1[REDACTED]")
                } else {
                    out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "[REDACTED]")
                }
            }
        }
        return out
    }

    private func activeProfile(binding: PluginAiBinding) -> PluginAiProfile? {
        if !binding.activeProfileId.isEmpty,
           let match = binding.profiles.first(where: { $0.profileId == binding.activeProfileId }) {
            return match
        }
        return binding.profiles.first
    }

    private static func generateProfileId() -> String {
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        return "service_\(ts)_\(suffix)"
    }

    private static func isValidProfileId(_ value: String) -> Bool {
        guard !value.isEmpty, let regex = profileIdRegex else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private func extractInt(_ raw: Any?) -> Int? {
        if raw is Bool { return nil }
        if let value = raw as? Int { return value }
        if let value = raw as? Double, value.isFinite { return Int(value) }
        return nil
    }

    private func extractDouble(_ raw: Any?) -> Double? {
        if raw is Bool { return nil }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    private func isAnthropic(_ profile: PluginAiProfile) -> Bool {
        if profile.provider == "anthropic-compatible" { return true }
        let lower = profile.baseUrl.lowercased()
        return lower.contains("/anthropic") || lower.hasSuffix("/v1/messages")
    }

    private func normalizeProviderStrict(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "openai-compatible" || cleaned == "deepseek-openai" || cleaned == "openai" {
            return "openai-compatible"
        }
        if cleaned == "anthropic-compatible" || cleaned == "deepseek-anthropic" || cleaned == "anthropic" {
            return "anthropic-compatible"
        }
        return nil
    }

    private func normalizeBaseUrl(_ raw: String) throws -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty,
              trimmed.count <= 8192,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "请输入合法的模型服务地址")
        }
        guard scheme == "https" || (scheme == "http" && isPrivateHost(host)) else {
            throw PluginHostError(PluginErrorCode.invalidArgument, "远程服务必须使用 HTTPS（本地调试可使用 http://127.0.0.1）")
        }
        return trimmed
    }

    private func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "0.0.0.0" || host.hasSuffix(".local") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return false }
        if parts[0] == 127 || parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    private func needsApiKey(baseUrl: String) -> Bool {
        let host = URL(string: baseUrl)?.host?.lowercased() ?? ""
        return !(host == "127.0.0.1" || host == "localhost" || host == "::1")
    }

    private func hasVersionSuffix(_ trimmedBaseUrl: String) -> Bool {
        trimmedBaseUrl.range(of: "/v\\d+$", options: .regularExpression) != nil
    }

    private func appendPath(_ baseUrl: String, segment: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if hasVersionSuffix(trimmed) {
            return "\(trimmed)/\(segment)"
        }
        return "\(trimmed)/v1/\(segment)"
    }

    private func openAiEndpoint(_ baseUrl: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") { return trimmed }
        if hasVersionSuffix(trimmed) {
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
