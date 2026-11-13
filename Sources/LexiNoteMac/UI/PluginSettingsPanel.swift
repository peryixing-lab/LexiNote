import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PluginSettingsPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var plugins: PluginManager
    @Environment(\.lexiPalette) private var palette

    @State private var busy = false
    @State private var statusMessage = ""
    @State private var expandedPluginIDs: Set<String> = []
    @State private var aiExpandedPluginIDs: Set<String> = []
    @State private var pendingGrantAllPlugin: PluginRecord?
    @State private var uninstallCandidate: PluginRecord?

    init(model: AppModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
        self.plugins = model.plugins
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("插件")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: 5) {
                Text("兼容 LexiNote 原生协议与 Obsidian 兼容插件。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("已安装插件在所有工作区中可见；启用状态、能力授权与私有数据均按当前工作区独立隔离保存。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
                Text("实验性插件支持：仅安装你自己编写或已审查的插件。Obsidian 兼容层覆盖已测试的 Vault / Metadata / Workspace / Editor / Command / View / Setting / Modal API 子集，未实现或被禁止的模块会返回明确错误码。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }

            // Header action strip
            HStack(spacing: 8) {
                let runningCount = plugins.records.filter { $0.state == .running }.count
                Text("沙盒就绪 · 运行中 \(runningCount) / 已安装 \(plugins.records.count)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button {
                    installFromZip()
                } label: {
                    Text("从本地安装 ZIP…")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(palette.brand))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .padding(.vertical, 2)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.brandInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.brandSoft)
                    )
            }

            if plugins.records.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("尚未安装插件。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    Text("支持 LexiNote 原生插件包（如 Harness 智能体）与标准 Obsidian 插件（含 manifest.json 与 main.js 的 ZIP 或目录）。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.softSurface.opacity(palette.isDark ? 0.45 : 0.72))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(plugins.records) { record in
                        pluginCard(record)
                    }
                }
            }

            // Security & AI proxy disclosures
            VStack(alignment: .leading, spacing: 6) {
                if plugins.records.contains(where: { $0.manifest.capabilities.contains(PluginCapability.aiInference.rawValue) }) {
                    Text("模型能力说明：插件只提交消息与工具定义，HTTP 请求、API Key 与超时均由知萤宿主代理管理；插件拿不到直接联网能力，也读不回密钥。")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)
                }
                Text("安全说明：插件运行在非持久化独立 WKWebView 沙盒内，所有工作区读写必须经宿主权限校验；默认拒绝全部敏感权限，禁用或切换工作区立即销毁对应沙盒实例。")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(3)
            }
            .padding(.top, 4)
        }
        .alert(item: $pendingGrantAllPlugin) { record in
            let titles = record.manifest.capabilities
                .compactMap { PluginCapability(rawValue: $0)?.title }
                .joined(separator: "、")
            return Alert(
                title: Text("授予「\(record.manifest.name)」全部权限？"),
                message: Text("将允许此插件在工作区「\(model.activeVault?.name ?? "我的工作区")」中使用：\(titles)。\n\n请只为您信任的插件开启写入或 AI 代理能力。"),
                primaryButton: .destructive(Text("确认授予")) {
                    plugins.grantAllCapabilities(for: record.id)
                    statusMessage = "已授予「\(record.manifest.name)」全部声明权限。"
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(item: $uninstallCandidate) { record in
            Alert(
                title: Text("卸载「\(record.manifest.name)」？"),
                message: Text("将移除插件代码、所有工作区授权及该插件的私有配置与模型密钥。此操作不可恢复。"),
                primaryButton: .destructive(Text("卸载")) {
                    Task { @MainActor in
                        await plugins.uninstall(pluginId: record.id)
                        statusMessage = "已卸载 \(record.manifest.name)"
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - Plugin Card

    @ViewBuilder
    private func pluginCard(_ record: PluginRecord) -> some View {
        let enabled = plugins.isEnabled(record.id)
        let grant = plugins.capabilityGrant(for: record.id)
        let allGranted = !record.manifest.capabilities.isEmpty &&
            record.manifest.capabilities.allSatisfy { grant.granted.contains($0) }
        let isExpanded = expandedPluginIDs.contains(record.id)
        let isAiExpanded = aiExpandedPluginIDs.contains(record.id)
        let declaresAi = record.manifest.capabilities.contains(PluginCapability.aiInference.rawValue)

        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 10) {
                statePill(record: record, enabled: enabled, allGranted: allGranted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.manifest.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(record.id) · v\(record.manifest.version) · \(record.manifest.kind.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if declaresAi {
                    Button {
                        if isAiExpanded {
                            aiExpandedPluginIDs.remove(record.id)
                        } else {
                            aiExpandedPluginIDs.insert(record.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10.5))
                            Text("模型设置")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(palette.brandInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !record.manifest.description.isEmpty {
                Text(record.manifest.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(2)
            }

            if !record.manifest.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(record.manifest.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.warning)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.warning)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.warning.opacity(0.08))
                )
            }

            // All permissions quick switch (default deny)
            if !record.manifest.capabilities.isEmpty {
                HStack(spacing: 12) {
                    LexiSwitch(isOn: Binding(
                        get: { allGranted },
                        set: { newValue in
                            if newValue {
                                pendingGrantAllPlugin = record
                            } else {
                                plugins.revokeAllCapabilities(for: record.id)
                                statusMessage = "已撤回「\(record.manifest.name)」在当前工作区的全部权限。"
                            }
                        }
                    ))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("授予全部权限（当前工作区）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Text("默认拒绝全部能力；关闭会立即撤回授权。")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            if !record.lastError.isEmpty {
                Text(record.lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.error)
                    .lineLimit(3)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    busy = true
                    Task { @MainActor in
                        defer { busy = false }
                        if enabled {
                            await plugins.disable(pluginId: record.id)
                        } else {
                            do {
                                try await plugins.enable(pluginId: record.id)
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    Text(enabled ? "停用" : "启用")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(enabled ? palette.textPrimary : palette.inverseText)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(enabled ? palette.surface : palette.brand))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    if isExpanded {
                        expandedPluginIDs.remove(record.id)
                    } else {
                        expandedPluginIDs.insert(record.id)
                    }
                } label: {
                    Text(isExpanded ? "收起权限与日志" : "能力与诊断")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(palette.surface))
                }
                .buttonStyle(.plain)

                if enabled {
                    Button {
                        let view = PluginViewRegistry.shared.views.first(where: { $0.pluginId == record.id })
                        settings.showInspector = true
                        settings.inspectorMode = "plugin:\(record.id):\(view?.viewId ?? "")"
                        model.settingsVisible = false
                        Task { @MainActor in
                            await plugins.presentView(pluginId: record.id, viewId: view?.viewId ?? "")
                        }
                    } label: {
                        Text("打开侧栏视图")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.brandInk)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    uninstallCandidate = record
                } label: {
                    Text("卸载")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.error)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(palette.surface))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            if isAiExpanded && declaresAi {
                PluginAiProfileEditor(plugins: plugins, pluginId: record.id)
                    .padding(.top, 4)
            }

            if isExpanded {
                expandedDetails(record: record, grant: grant)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.softSurface.opacity(palette.isDark ? 0.5 : 0.85))
        )
    }

    @ViewBuilder
    private func statePill(record: PluginRecord, enabled: Bool, allGranted: Bool) -> some View {
        let label: String = {
            if record.state == .running { return "运行中" }
            if record.state == .loading { return "启动中" }
            if record.state == .crashed {
                return allGranted ? "需重载" : "异常"
            }
            return enabled ? "已启用" : "已停用"
        }()
        let color: Color = {
            if record.state == .running { return palette.success }
            if record.state == .crashed && !allGranted { return palette.error }
            return palette.textSecondary
        }()
        Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(minWidth: 52, minHeight: 22, maxHeight: 22)
            .background(Capsule().fill(palette.surface))
    }

    private func expandedDetails(record: PluginRecord, grant: PluginPermissionGrant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(palette.divider).frame(height: 0.5)

            Text("能力授权（当前工作区独立存储，取消即生效）")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.textSecondary)

            if record.manifest.capabilities.isEmpty {
                Text("该插件未声明额外能力。")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(record.manifest.capabilities, id: \.self) { capRaw in
                        let cap = PluginCapability(rawValue: capRaw)
                        let granted = grant.granted.contains(capRaw)
                        HStack(spacing: 10) {
                            LexiSwitch(isOn: Binding(
                                get: { granted },
                                set: { plugins.setCapability(capRaw, granted: $0, for: record.id) }
                            ))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(cap?.title ?? capRaw)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(granted ? palette.textPrimary : palette.textSecondary)
                                    if let risk = cap?.risk {
                                        Text(risk.rawValue)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(risk == .high ? palette.warning : palette.textSecondary)
                                            .padding(.horizontal, 6)
                                            .frame(height: 16)
                                            .background(Capsule().fill(palette.surface))
                                    }
                                }
                                if let desc = cap?.description {
                                    Text(desc)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            let pluginLogs = plugins.logs.filter { $0.pluginId == record.id }.suffix(15)
            HStack {
                Text("诊断日志")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if !pluginLogs.isEmpty {
                    Button("清空日志") {
                        plugins.clearLogs(for: record.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.brandInk)
                }
            }

            if pluginLogs.isEmpty {
                Text("暂无诊断日志")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(pluginLogs)) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text(log.level.uppercased())
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(log.level == "error" ? palette.error : (log.level == "warn" ? palette.warning : palette.textSecondary))
                            Text(log.message)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.surface))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Install Pickers

    private func installFromZip() {
        let panel = NSOpenPanel()
        panel.title = "选择插件压缩包 (.zip)"
        panel.allowedContentTypes = [UTType.zip]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let record = try await plugins.installFromZip(url: url)
                expandedPluginIDs.insert(record.id)
                let warningNote = record.manifest.warnings.isEmpty ? "" : "（\(record.manifest.warnings.joined(separator: "；"))）"
                statusMessage = "已安装「\(record.manifest.name)」v\(record.manifest.version)。请授权所需能力后启用\(warningNote)"
            } catch let err as PluginHostError {
                statusMessage = "安装失败 [\(err.code)]：\(err.message)"
            } catch {
                statusMessage = "安装失败：\(error.localizedDescription)"
            }
        }
    }

    private func installFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择插件文件夹（含 manifest.json）"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let record = try await plugins.installFromDirectory(url: url)
                expandedPluginIDs.insert(record.id)
                statusMessage = "已从目录安装「\(record.manifest.name)」v\(record.manifest.version)。请授权所需能力后启用。"
            } catch let err as PluginHostError {
                statusMessage = "安装失败 [\(err.code)]：\(err.message)"
            } catch {
                statusMessage = "安装失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Host-Managed AI Proxy Config Editor

private struct PluginAiProfileEditor: View {
    @ObservedObject var plugins: PluginManager
    let pluginId: String
    @Environment(\.lexiPalette) private var palette

    @State private var presetID = "deepseek"
    @State private var provider = "openai-compatible"
    @State private var baseUrl = "https://api.deepseek.com"
    @State private var modelName = "deepseek-chat"
    @State private var apiKey = ""
    @State private var feedback = ""

    var body: some View {
        let binding = plugins.aiBinding(for: pluginId)
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(palette.divider).frame(height: 0.5)

            HStack {
                Text("AI 服务商与密钥配置（仅宿主存储，插件不可见 Key）")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !binding.activeProfileId.isEmpty {
                    let hasSecret = plugins.aiHasSecret(pluginId: pluginId, profileId: binding.activeProfileId)
                    Text(hasSecret ? "已配置密钥" : "未填密钥")
                        .font(.system(size: 10.5))
                        .foregroundStyle(hasSecret ? palette.success : palette.warning)
                }
            }

            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PluginAiPresets.all) { preset in
                        let selected = presetID == preset.id
                        Button {
                            presetID = preset.id
                            provider = preset.provider
                            baseUrl = preset.baseUrl
                            modelName = preset.defaultModel
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? palette.brandInk : palette.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(
                                    Capsule().fill(selected ? palette.workspaceSelection : palette.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Base URL").font(.system(size: 11)).foregroundStyle(palette.textSecondary).frame(width: 72, alignment: .leading)
                    TextField("https://api.deepseek.com", text: $baseUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                }
                HStack(spacing: 8) {
                    Text("模型").font(.system(size: 11)).foregroundStyle(palette.textSecondary).frame(width: 72, alignment: .leading)
                    TextField("deepseek-chat", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                }
                HStack(spacing: 8) {
                    Text("API Key").font(.system(size: 11)).foregroundStyle(palette.textSecondary).frame(width: 72, alignment: .leading)
                    SecureField("仅写入宿主安全文件，不回显", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                }
            }

            HStack(spacing: 8) {
                Button("保存配置") {
                    do {
                        let profile = PluginAiProfile(
                            profileId: presetID,
                            name: PluginAiPresets.all.first { $0.id == presetID }?.title ?? modelName,
                            provider: provider,
                            baseUrl: baseUrl,
                            model: modelName,
                            maxTokens: 4096,
                            temperature: 0.3
                        )
                        try plugins.saveAiProfile(pluginId: pluginId, profile: profile, apiKey: apiKey.isEmpty ? nil : apiKey)
                        apiKey = ""
                        feedback = "已保存到宿主模型代理"
                    } catch let err as PluginHostError {
                        feedback = err.message
                    } catch {
                        feedback = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if !binding.profiles.isEmpty {
                    Button("清除配置") {
                        plugins.clearAiConfig(pluginId: pluginId)
                        feedback = "已清除当前插件模型配置"
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.error)
                }

                Spacer()
                if !feedback.isEmpty {
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.brandInk)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.surface.opacity(0.65)))
        .onAppear {
            if let active = binding.profiles.first(where: { $0.profileId == binding.activeProfileId }) ?? binding.profiles.first {
                presetID = active.profileId
                provider = active.provider
                baseUrl = active.baseUrl
                modelName = active.model
            }
        }
    }
}
