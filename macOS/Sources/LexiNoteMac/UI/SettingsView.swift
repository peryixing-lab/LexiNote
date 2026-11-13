import SwiftUI
import AppKit

enum SettingsSection: String, CaseIterable, Identifiable {
    case about, appearance, interface, editor, data, plugins, shortcuts

    var id: String { rawValue }
    var title: String {
        switch self {
        case .about: return "关于"
        case .appearance: return "外观"
        case .interface: return "界面"
        case .editor: return "编辑器"
        case .data: return "文件与链接"
        case .plugins: return "插件"
        case .shortcuts: return "快捷键"
        }
    }
    var symbol: String {
        switch self {
        case .about: return "info.circle"
        case .appearance: return "sun.max"
        case .interface: return "rectangle.grid.1x2"
        case .editor: return "doc.text"
        case .data: return "folder"
        case .plugins: return "sparkles"
        case .shortcuts: return "command"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    var initialSection: SettingsSection = .about

    @State private var selectedSection: SettingsSection = .about
    @State private var searchQuery: String = ""
    @State private var ribbonSubpage: Bool = false
    @State private var showCssManager: Bool = false

    @Environment(\.lexiPalette) private var palette

    private var visibleSections: [SettingsSection] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SettingsSection.allCases }
        return SettingsSection.allCases.filter { section in
            section.title.lowercased().contains(q) || keywords(for: section).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 38pt centered header matching HarmonyOS LexiSettingsWindow
            ZStack {
                Text("设置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                HStack {
                    Spacer()
                    Button("关闭") {
                        model.settingsVisible = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 38)
            .background(palette.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
            }

            HStack(spacing: 0) {
                leftRail
                ScrollView {
                    sectionContent
                        .padding(.horizontal, 26)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.workspacePage)
            }
        }
        .frame(width: 780, height: 560)
        .onAppear {
            if let req = settings.requestedSettingsSection,
               let sec = SettingsSection(rawValue: req) {
                selectedSection = sec
                settings.requestedSettingsSection = nil
            } else {
                selectedSection = initialSection
            }
        }
    }

    // MARK: - Left 216pt Rail

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                TextField("搜索设置...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.textPrimary)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(palette.surface)
                    .overlay(Capsule().stroke(palette.workspaceLine, lineWidth: 0.6))
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Text("选项")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(visibleSections) { section in
                        let selected = selectedSection == section
                        Button {
                            selectedSection = section
                            ribbonSubpage = false
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: section.symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(selected ? palette.brandInk : palette.textSecondary)
                                    .frame(width: 18)
                                Text(section.title)
                                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                                    .foregroundStyle(selected ? palette.brandInk : palette.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? palette.workspaceSelection : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 8)
        }
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .background(palette.workspaceSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
        }
    }

    // MARK: - Section Switcher

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .about:
            AboutSettingsView(model: model, settings: settings)
        case .appearance:
            AppearanceSettingsView(settings: settings, showCssManager: $showCssManager)
        case .interface:
            InterfaceSettingsView(model: model, settings: settings, ribbonSubpage: $ribbonSubpage)
        case .editor:
            EditorSettingsView(model: model, settings: settings)
        case .data:
            DataSettingsView(model: model, settings: settings)
        case .plugins:
            PluginSettingsPanel(model: model, settings: settings)
        case .shortcuts:
            ShortcutsSettingsView(model: model, settings: settings)
        }
    }

    private func keywords(for section: SettingsSection) -> String {
        switch section {
        case .about: return "版本 语言 帮助 目录 文档 2.0.1"
        case .appearance: return "明暗 主题 配色 鸢尾紫 玫瑰粉 CSS 字体 行高 字号 缩放"
        case .interface: return "标签页 标题栏 功能区 缩放 比例 ribbon zoom"
        case .editor: return "打开 视图 编辑 阅读 源码 实时 标题 行宽 简洁 学习 专业"
        case .data: return "保存 位置 目录 备份 导出 导入 markdown json 索引"
        case .plugins: return "plugin zip obsidian lexinote harness ai 权限 模型 密钥"
        case .shortcuts: return "hotkey 键位 录制 冲突 命令"
        }
    }
}

// MARK: - 1. About

private struct AboutSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPageTitle(text: "关于")

            SettingsGroupCard {
                HStack {
                    Text("版本")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("2.0.1")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.vertical, 6)

                cardDivider

                HStack {
                    Text("语言")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Picker("", selection: $settings.interfaceLanguage) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .frame(width: 128)
                }
                .padding(.vertical, 4)

                cardDivider

                HStack {
                    Text("使用帮助")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button {
                        model.settingsVisible = false
                        model.welcomeVisible = true
                    } label: {
                        Text("打开")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.brand)
                            .padding(.horizontal, 16)
                            .frame(height: 30)
                            .background(Capsule().fill(palette.brandSoft))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            SettingsGroupHeader(text: "数据与备份")

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.brandSoft)
                                .frame(width: 36, height: 36)
                            Image(systemName: "folder")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.brand)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("工作区文件夹：\(abbreviatedPath(model.activeWorkspaceFolder.path))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("笔记 (.md)、思维导图与白板均直接保存在此工作区文件夹中。")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }

                    Button {
                        model.chooseActiveWorkspaceFolder()
                    } label: {
                        Text("更改工作区文件夹")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.brand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brandSoft))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cardDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 0.5).padding(.vertical, 6)
    }
}

// MARK: - 2. Appearance

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var showCssManager: Bool
    @Environment(\.lexiPalette) private var palette

    @State private var accentDraft = ""
    @State private var bgDraft = ""
    @State private var fgDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("外观")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(palette.textPrimary)

            SettingsGroupCard {
                // Base color mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("基础颜色")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("设置应用的明暗外观。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 4) {
                        ForEach(AppearanceMode.allCases) { item in
                            let selected = settings.appearance == item
                            Button {
                                settings.appearance = item
                            } label: {
                                Text(item == .system ? "跟随系统" : (item == .light ? "浅色" : "深色"))
                                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                                    .foregroundStyle(selected ? palette.brandInk : palette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selected ? palette.workspaceSelection : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.surface.opacity(0.55))
                    )
                }

                cardDivider

                // Global palette
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("全局色调")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(activeThemeName)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.brandInk)
                    }
                    Text("统一调整背景、侧栏、按钮和笔记链接，选择后自动保存。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)

                    themePreviewCard

                    // Original theme banner button
                    Button {
                        settings.themeMode = .original
                        settings.accentHex = ThemeEngine.defaultAccent
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: ThemeEngine.defaultAccent))
                                .frame(width: 18, height: 18)
                            Text("原配色调")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if settings.themeMode == .original {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.brand)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(settings.themeMode == .original ? palette.brand : palette.workspaceLine,
                                                lineWidth: settings.themeMode == .original ? 1.4 : 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    // 3x2 preset grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(AccentPreset.allCases) { preset in
                            let selected = settings.themeMode == .preset && settings.accentHex.uppercased() == preset.hex
                            Button {
                                settings.selectPreset(preset)
                                syncHexDrafts()
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 22, height: 22)
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text(preset.label)
                                        .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                                        .foregroundStyle(selected ? palette.brandInk : palette.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? palette.workspaceSelection : palette.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(selected ? palette.brand : palette.workspaceLine,
                                                        lineWidth: selected ? 1.5 : 0.6)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Custom hex rows
                    Text("自定义")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 4)

                    hexRow("强调色", hex: $accentDraft) { value in
                        settings.accentHex = value
                        settings.themeMode = .custom
                    }
                    hexRow("背景", hex: $bgDraft) { value in
                        settings.customBackgroundHex = value
                        settings.themeMode = .custom
                    }
                    hexRow("前景", hex: $fgDraft) { value in
                        settings.customForegroundHex = value
                        settings.themeMode = .custom
                    }

                    Text("输入颜色后按回车或离开输入框，即可保存。")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }

                cardDivider

                // CSS Snippets
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CSS 样式代码片段")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        let enabledCount = settings.cssSnippets.filter(\.enabled).count
                        Text("已启用 \(enabledCount) 个 · 应用于增强编辑器")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Button("管理") {
                        showCssManager = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                }
            }

            // Font section
            Text("字体")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 4)

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("字体大小")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Text("调整笔记编辑与预览中的文字大小。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Button("重置") {
                            settings.editorFontSize = 16
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.brandInk)
                        Text("\(Int(settings.editorFontSize))")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.leading, 8)
                    }
                    Slider(value: $settings.editorFontSize, in: 12...26, step: 1)
                        .tint(palette.brand)
                }

                cardDivider

                SettingsSwitchRow(
                    title: "快速调整字体大小",
                    subtitle: "开启后，在笔记中使用 Ctrl 与鼠标滚轮调整字号。",
                    isOn: $settings.quickZoom
                )
            }
        }
        .onAppear { syncHexDrafts() }
        .sheet(isPresented: $showCssManager) {
            CssSnippetsSheet(settings: settings)
        }
    }

    private var activeThemeName: String {
        switch settings.themeMode {
        case .original: return "原始色调"
        case .preset:
            return AccentPreset.allCases.first { $0.hex == settings.accentHex.uppercased() }?.label ?? "预设色调"
        case .custom: return "自定义"
        }
    }

    private var themePreviewCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("知萤")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 6)
                Text("笔记")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.workspaceSelection))
                Text("文件夹")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                Spacer()
            }
            .padding(8)
            .frame(width: 110)
            .background(palette.workspaceSidebar)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("主题预览")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Circle().fill(palette.brand).frame(width: 7, height: 7)
                }
                Text("让灵感拥有你的颜色")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("[[ 双向链接 ]]")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.surface)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.workspaceLine, lineWidth: 0.7)
        )
    }

    private func hexRow(_ title: String, hex: Binding<String>, onCommit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: hex.wrappedValue))
                    .frame(width: 12, height: 12)
                TextField("#6E44D9", text: hex)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 76)
                    .onSubmit { commitHex(hex.wrappedValue, assign: onCommit) }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(palette.surface)
                    .overlay(Capsule().stroke(palette.workspaceLine, lineWidth: 0.6))
            )
        }
    }

    private func commitHex(_ raw: String, assign: (String) -> Void) {
        let normalized = HexColor.normalize(raw)
        assign(normalized)
        syncHexDrafts()
    }

    private func syncHexDrafts() {
        accentDraft = settings.accentHex
        bgDraft = settings.customBackgroundHex
        fgDraft = settings.customForegroundHex
    }

    private var cardDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 0.5).padding(.vertical, 6)
    }
}

private struct CssSnippetsSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette

    @State private var name = ""
    @State private var css = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CSS 样式代码片段")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            if settings.cssSnippets.isEmpty {
                Text("尚未添加 CSS 代码片段。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($settings.cssSnippets) { $snippet in
                            HStack(spacing: 10) {
                                LexiSwitch(isOn: $snippet.enabled)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.name)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(snippet.css.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    settings.cssSnippets.removeAll { $0.id == snippet.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.error)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(palette.softSurface))
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            Divider()
            Text("新建片段").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.textPrimary)
            TextField("片段名称（例如：紧凑引用块）", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            TextEditor(text: $css)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.workspaceLine, lineWidth: 0.7))
            HStack {
                Spacer()
                Button("添加片段") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanCss = css.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty, !cleanCss.isEmpty else { return }
                    settings.cssSnippets.append(CssSnippet(id: UUID().uuidString, name: cleanName, css: cleanCss, enabled: true))
                    name = ""
                    css = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || css.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(palette.workspacePage)
    }
}

// MARK: - 3. Interface + Ribbon Subpage

private struct InterfaceSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Binding var ribbonSubpage: Bool
    @ObservedObject private var viewRegistry = PluginViewRegistry.shared
    @Environment(\.lexiPalette) private var palette

    private let coreRibbonCommands: [(id: String, title: String)] = [
        ("vault", "知识库"),
        ("switcher", "快速切换文档"),
        ("commands", "命令面板"),
        ("reading", "切换编辑与阅读"),
        ("graph", "笔记关联")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ribbonSubpage {
                HStack(spacing: 8) {
                    Button {
                        ribbonSubpage = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("界面")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(palette.brandInk)
                    }
                    .buttonStyle(.plain)

                    Text("/")
                        .foregroundStyle(palette.textSecondary)

                    Text("功能区")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }

                SettingsGroupCard {
                    Text("选择要在窗口最左侧功能区展示的快捷命令：")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.bottom, 4)

                    ForEach(Array(coreRibbonCommands.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { cardDivider }
                        SettingsSwitchRow(
                            title: item.title,
                            subtitle: "",
                            isOn: Binding(
                                get: { settings.isRibbonCommandVisible(item.id) },
                                set: { settings.setRibbonCommandVisible(item.id, $0) }
                            )
                        )
                    }

                    ForEach(viewRegistry.ribbonActions) { action in
                        cardDivider
                        SettingsSwitchRow(
                            title: "\(action.title)（\(action.pluginName)）",
                            subtitle: "由插件注册的功能区快捷按钮。",
                            isOn: Binding(
                                get: { settings.isRibbonCommandVisible(action.id) },
                                set: { settings.setRibbonCommandVisible(action.id, $0) }
                            )
                        )
                    }
                }
            } else {
                Text("界面")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                SettingsGroupCard {
                    SettingsSwitchRow(
                        title: "显示标签页标题栏",
                        subtitle: "在每个标签页上方显示标题栏。",
                        isOn: $settings.showTabStrip
                    )

                    cardDivider

                    SettingsSwitchRow(
                        title: "显示功能区",
                        subtitle: "显示窗口最左侧的功能区，以便快速执行命令。",
                        isOn: $settings.showRibbon
                    )

                    cardDivider

                    Button {
                        ribbonSubpage = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("功能区")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(palette.textPrimary)
                                Text("设置哪些命令需要显示在功能区上。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("高级")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 4)

                SettingsGroupCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("缩放比例")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Text("控制应用程序的整体缩放比例")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Button {
                            settings.interfaceZoom = 100
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("重置为 100%")

                        Text("\(Int(settings.interfaceZoom))%")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 44, alignment: .trailing)

                        Slider(value: $settings.interfaceZoom, in: 75...150, step: 5)
                            .tint(palette.brand)
                            .frame(width: 110)
                    }
                }
            }
        }
    }

    private var cardDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 0.5).padding(.vertical, 6)
    }
}

// MARK: - 4. Editor

private struct EditorSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPageTitle(text: "编辑器")
            SettingsScopeBanner(text: "以下视图和显示选项通用于标准编辑器。编辑器设置仅应用于工作区「\(model.activeVault?.name ?? "我的工作区")」。")

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作区打开方式（全局）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("所有工作区共用此打开方式；选择“每次询问”可恢复提示。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                    Picker("", selection: $settings.workspaceOpenMode) {
                        ForEach(WorkspaceOpenMode.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroupCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("新标签页的默认视图")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Text("设置新打开笔记的默认视图。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.editorDefaultView) {
                        Text("编辑视图").tag("edit")
                        Text("阅读视图").tag("preview")
                    }
                    .labelsHidden()
                    .frame(width: 118)
                }

                cardDivider

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("默认编辑模式")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Text("编辑视图中，新打开笔记采用的编辑模式。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.editorDefaultMode) {
                        Text("实时预览").tag("live")
                        Text("源码模式").tag("source")
                    }
                    .labelsHidden()
                    .frame(width: 118)
                }

                cardDivider

                SettingsSwitchRow(
                    title: "视图状态",
                    subtitle: "在状态栏显示当前视图，并点击切换阅读和编辑。",
                    isOn: $settings.editorViewStatus
                )
            }

            Text("显示")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 2)

            SettingsGroupCard {
                SettingsSwitchRow(
                    title: "页面内标题",
                    subtitle: "在正文上方显示可编辑的笔记标题。",
                    isOn: $settings.editorShowTitle
                )
                cardDivider
                SettingsSwitchRow(
                    title: "限制行宽",
                    subtitle: "限制正文宽度，让较长的段落更易阅读。",
                    isOn: $settings.limitEditorWidth
                )
            }

            SettingsGroupHeader(text: "编辑器类型")

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("默认编辑工具")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    HStack(spacing: 4) {
                        tierPill("简洁", tag: .simple)
                        tierPill("学习", tag: .study)
                        tierPill("专业", tag: .pro)
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(palette.workspacePage)
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func tierPill(_ title: String, tag: EditorLevel) -> some View {
        let active = settings.editorDefaultTier == tag
        return Button {
            settings.editorDefaultTier = tag
        } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundStyle(active ? palette.inverseText : palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? palette.brand : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var cardDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 0.5).padding(.vertical, 6)
    }
}

// MARK: - 5. Data & Links

private struct DataSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPageTitle(text: "文件与链接")

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.brandSoft)
                                .frame(width: 36, height: 36)
                            Image(systemName: "folder")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.brand)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("工作区文件夹：\(abbreviatedPath(model.activeWorkspaceFolder.path))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("工作区是一个独立文件夹，Markdown (.md)、思维导图与白板文件均保存在其中。")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }

                    Button {
                        model.chooseActiveWorkspaceFolder()
                    } label: {
                        Text("更改工作区文件夹")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.brand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brandSoft))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !model.dataStatusMessage.isEmpty {
                SettingsScopeBanner(text: model.dataStatusMessage)
            }

            SettingsGroupHeader(text: "工作区归档 (.zip)")

            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        model.exportWorkspaceZip()
                    } label: {
                        Text("导出工作区压缩包 (.zip)")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.inverseText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brand))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.importWorkspaceZip()
                    } label: {
                        Text("导入压缩包到指定文件夹 (.zip)")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.brand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brandSoft))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button {
                            model.exportMarkdownBundle()
                        } label: {
                            Text("导出 Markdown (.md)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.workspacePage))
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.importBackupOrMarkdown()
                        } label: {
                            Text("导入笔记")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.workspacePage))
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.rebuildIndex()
                        } label: {
                            Text("重建索引")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.workspacePage))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SettingsGroupHeader(text: "设置与插件备份 (.json)")

            SettingsGroupCard {
                HStack(spacing: 10) {
                    Button {
                        model.exportSettingsAndPlugins()
                    } label: {
                        Text("导出设置与插件 (.json)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.brand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brandSoft))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.importSettingsAndPlugins()
                    } label: {
                        Text("导入设置与插件 (.json)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.workspacePage))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 6. Shortcuts Recorder

private struct ShortcutsSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    @State private var query = ""
    @State private var recordingCommandID: String?
    @State private var keyMonitor: Any?

    private var commands: [LexiCommand] {
        let all = CommandCatalog.allWithPlugins()
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q)
                || $0.group.lowercased().contains(q)
                || currentBinding(for: $0).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(palette.textPrimary)

            Text("搜索命令，点击「+」后按下组合键；Esc 取消录制。")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: 8) {
                TextField("搜索命令或快捷键", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.textPrimary)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.softSurface.opacity(palette.isDark ? 0.45 : 0.75))
            )

            LazyVStack(spacing: 0) {
                ForEach(commands) { cmd in
                    let binding = currentBinding(for: cmd)
                    let conflict = conflictLabel(for: cmd, binding: binding)
                    let recording = recordingCommandID == cmd.id

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cmd.title)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(palette.textPrimary)
                                if case .plugin = cmd.action {
                                    Text("插件命令 · \(cmd.group)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer()

                            Text(recording ? "请按下组合键…" : (binding.isEmpty ? "未设置" : binding))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(recording ? palette.brand : (conflict != nil ? palette.warning : palette.textSecondary))

                            Button {
                                startRecording(for: cmd.id)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(recording ? palette.inverseText : palette.brandInk)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(recording ? palette.brand : palette.workspaceSelection)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button("重置") {
                                stopRecording()
                                settings.hotkeyOverrides.removeValue(forKey: cmd.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.brandInk)
                        }
                        .frame(minHeight: 38)

                        if let conflict {
                            Text(conflict)
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.warning)
                        }
                    }
                    .padding(.vertical, 2)
                    Rectangle().fill(palette.divider).frame(height: 0.5)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func currentBinding(for cmd: LexiCommand) -> String {
        if let overrides = settings.hotkeyOverrides[cmd.id] {
            return overrides.map(HotkeyCodec.displayLabel).joined(separator: " / ")
        }
        return cmd.shortcut
    }

    private func conflictLabel(for cmd: LexiCommand, binding: String) -> String? {
        guard let list = settings.hotkeyOverrides[cmd.id], !list.isEmpty else { return nil }
        if let reason = HotkeyCodec.systemConflictReason(for: list) {
            return "与系统保留快捷键冲突（\(reason)）"
        }
        let dupes = settings.hotkeyOverrides.filter { entry in
            entry.key != cmd.id && entry.value.contains(where: { candidate in
                list.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            })
        }
        if !dupes.isEmpty {
            return "与另一条命令的自定义快捷键冲突"
        }
        return nil
    }

    private func startRecording(for cmdID: String) {
        stopRecording()
        recordingCommandID = cmdID
        CommandRouter.isRecordingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            guard let canonical = HotkeyCodec.canonical(from: event) else {
                NSSound.beep()
                return nil
            }
            settings.hotkeyOverrides[cmdID] = [canonical]
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recordingCommandID = nil
        CommandRouter.isRecordingHotkey = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Shared Card & Switch Components

private struct SettingsPageTitle: View {
    let text: String
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(palette.textPrimary)
            .padding(.bottom, 2)
    }
}

private struct SettingsGroupHeader: View {
    let text: String
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

private struct SettingsScopeBanner: View {
    let text: String
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(palette.brand)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.brandSoft)
        )
    }
}

private struct SettingsGroupCard<Content: View>: View {
    @Environment(\.lexiPalette) private var palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.softSurface)
        )
    }
}

private struct SettingsSwitchRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            LexiSwitch(isOn: $isOn)
        }
        .frame(minHeight: 34)
    }
}

struct LexiSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? palette.brand : palette.textSecondary.opacity(0.26))
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.15), radius: 1.5, y: 0.5)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

func abbreviatedPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
