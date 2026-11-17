import SwiftUI

struct InspectorContainer: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var plugins: PluginManager
    @ObservedObject private var viewRegistry = PluginViewRegistry.shared
    @Environment(\.lexiPalette) private var palette

    init(model: AppModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
        self.plugins = model.plugins
    }

    private var harnessRecord: PluginRecord? {
        plugins.records.first { $0.id == "lexinote.harness" }
    }

    private var otherPluginRecords: [PluginRecord] {
        plugins.records.filter { $0.id != "lexinote.harness" }
    }

    private var activePluginSelection: (pluginId: String, viewId: String)? {
        let mode = settings.inspectorMode
        guard mode.hasPrefix("plugin:") else { return nil }
        let rest = String(mode.dropFirst("plugin:".count))
        if let colon = rest.firstIndex(of: ":") {
            let pid = String(rest[..<colon])
            let vid = String(rest[rest.index(after: colon)...])
            return (pid, vid)
        }
        return (rest, defaultViewId(for: rest))
    }

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            if let selection = activePluginSelection {
                pluginContent(pluginId: selection.pluginId, viewId: selection.viewId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note = model.currentNote {
                NoteInspectorBodyView(model: model, settings: settings, note: note)
            } else {
                emptyOutlineContent
            }
        }
        .background(palette.workspaceInspector)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
        }
    }

    // MARK: - Top 48pt Icon Bar (Matches HarmonyOS LexiWorkspaceRightSidebar)

    private var topToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if let harness = harnessRecord {
                    toolbarTabButton(
                        symbol: "star",
                        help: harness.manifest.name,
                        active: activePluginSelection?.pluginId == harness.id
                    ) {
                        selectPlugin(harness)
                    }
                }

                toolbarTabButton(
                    symbol: "list.bullet",
                    help: "大纲与知识索引",
                    active: activePluginSelection == nil
                ) {
                    LexiMotion.perform(settings, LexiMotion.fast(settings)) {
                        settings.inspectorMode = "outline"
                    }
                }

                ForEach(otherPluginRecords) { record in
                    toolbarTabButton(
                        symbol: pluginSymbol(for: record),
                        help: record.manifest.name,
                        active: activePluginSelection?.pluginId == record.id
                    ) {
                        selectPlugin(record)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: max(0, settings.inspectorWidth - 24), minHeight: 48, maxHeight: 48, alignment: .center)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func toolbarTabButton(symbol: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? palette.workspaceSelection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Empty Outline State (Image 1)

    private var emptyOutlineContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("打开一篇笔记以查看大纲。")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Plugin Surface & Permission Gate

    @ViewBuilder
    private func pluginContent(pluginId: String, viewId: String) -> some View {
        if let record = plugins.record(for: pluginId) {
            let missing = plugins.missingCapabilities(for: pluginId)
            let hasAnyGrant = !plugins.capabilityGrant(for: pluginId).granted.isEmpty || record.manifest.capabilities.isEmpty
            let isRunning = record.state == .running && plugins.session(for: pluginId) != nil

            if isRunning {
                PluginWebHostView(manager: plugins, pluginId: pluginId, viewId: viewId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: pluginSymbol(for: record))
                                .font(.system(size: 16))
                                .foregroundStyle(palette.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.manifest.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(record.manifest.kind.label + " · v" + record.manifest.version)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }

                        if !record.lastError.isEmpty {
                            let isPermissionError = record.lastError.contains(PluginErrorCode.permissionDenied)
                            let displayError = isPermissionError
                                ? record.lastError.replacingOccurrences(of: "E_PLUGIN_FAILED: ", with: "")
                                : record.lastError
                            let tint = isPermissionError ? palette.warning : palette.error
                            Text(displayError)
                                .font(.system(size: 11.5))
                                .foregroundStyle(tint)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(tint.opacity(0.08))
                                )
                        }

                        if record.state == .loading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在沙盒中启动插件…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        } else if !plugins.isEnabled(pluginId) {
                            Text(!missing.isEmpty && !hasAnyGrant
                                 ? "该插件在当前工作区尚未授权或启用；授予核心或全部能力即可使用。"
                                 : "该插件在当前工作区尚未启用。")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)

                            if !missing.isEmpty {
                                LexiPrimaryButton(title: "授予全部权限并启用", symbol: "checkmark.shield") {
                                    plugins.grantAllCapabilities(for: pluginId)
                                    Task { @MainActor in
                                        try? await plugins.enable(pluginId: pluginId)
                                        await plugins.presentView(pluginId: pluginId, viewId: defaultViewId(for: pluginId))
                                    }
                                }
                            }
                            if missing.isEmpty || hasAnyGrant {
                                LexiPrimaryButton(title: "在当前工作区启用", symbol: "play.fill") {
                                    Task { @MainActor in
                                        try? await plugins.enable(pluginId: pluginId)
                                        await plugins.presentView(pluginId: pluginId, viewId: defaultViewId(for: pluginId))
                                    }
                                }
                            }
                        } else {
                            if !missing.isEmpty {
                                LexiPrimaryButton(title: "授予全部权限并重载", symbol: "checkmark.shield") {
                                    plugins.grantAllCapabilities(for: pluginId)
                                    Task { @MainActor in
                                        try? await plugins.enable(pluginId: pluginId)
                                        await plugins.presentView(pluginId: pluginId, viewId: defaultViewId(for: pluginId))
                                    }
                                }
                            }
                            LexiPrimaryButton(title: "重新加载插件", symbol: "arrow.clockwise") {
                                Task { @MainActor in
                                    try? await plugins.enable(pluginId: pluginId)
                                    await plugins.presentView(pluginId: pluginId, viewId: defaultViewId(for: pluginId))
                                }
                            }
                        }

                        Button("前往设置 → 插件详情管理") {
                            settings.requestedSettingsSection = "plugins"
                            model.presentSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.brandInk)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            emptyOutlineContent
        }
    }

    // MARK: - Helpers

    private func selectPlugin(_ record: PluginRecord) {
        let vid = defaultViewId(for: record.id)
        withAnimation(.easeOut(duration: 0.12)) {
            settings.inspectorMode = "plugin:\(record.id):\(vid)"
        }
        let hasAnyGrant = !plugins.capabilityGrant(for: record.id).granted.isEmpty || record.manifest.capabilities.isEmpty
        if record.state == .running || hasAnyGrant {
            Task { @MainActor in
                if !plugins.isEnabled(record.id) || plugins.session(for: record.id) == nil {
                    try? await plugins.enable(pluginId: record.id)
                }
                await plugins.presentView(pluginId: record.id, viewId: defaultViewId(for: record.id))
            }
        }
    }

    private func defaultViewId(for pluginId: String) -> String {
        if let registered = viewRegistry.views.first(where: { $0.pluginId == pluginId }) {
            return registered.viewId
        }
        if let declared = plugins.record(for: pluginId)?.manifest.views.first {
            return declared.id
        }
        return ""
    }

    private func pluginSymbol(for record: PluginRecord) -> String {
        if record.id == "lexinote.harness" { return "star" }
        if record.id.lowercased().contains("calendar") { return "calendar" }
        if let reg = viewRegistry.views.first(where: { $0.pluginId == record.id }) {
            return reg.icon
        }
        return "puzzlepiece.extension"
    }
}

// MARK: - Document Outline / Links / Properties Inspector

private struct NoteInspectorBodyView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let note: Note
    @Environment(\.lexiPalette) private var palette

    @State private var addingProperty = false
    @State private var newPropertyKey = ""
    @State private var newPropertyValue = ""
    @State private var newTag = ""
    @Namespace private var subTabNamespace

    private var mode: String {
        switch settings.inspectorMode {
        case "links", "properties":
            return settings.inspectorMode
        default:
            return "outline"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .padding(.bottom, 6)

                HStack(spacing: 4) {
                    subTab("大纲", id: "outline")
                    subTab("链接", id: "links")
                    subTab("属性", id: "properties")
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)

                switch mode {
                case "links":
                    linksSection
                case "properties":
                    propertiesContent
                default:
                    outlineContent
                }

                Spacer(minLength: 24)
                statistics
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    private func subTab(_ title: String, id: String) -> some View {
        let active = mode == id
        return Button {
            LexiMotion.perform(settings, LexiMotion.fast(settings)) { settings.inspectorMode = id }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    ZStack {
                        Capsule().fill(palette.softSurface.opacity(0.6))
                        if active {
                            Capsule()
                                .fill(palette.workspaceSelection)
                                .matchedGeometryEffect(id: "inspector-subtab-pill", in: subTabNamespace)
                        }
                    }
                }
        }
        .buttonStyle(LexiPressButtonStyle())
    }

    private var outlineContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let headings = note.outline
            if headings.isEmpty {
                Text("用 Markdown 标题梳理思路，大纲会出现在这里。")
                    .font(.system(size: 12))
                    .lineSpacing(6)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(headings) { heading in
                    Button {
                        model.jump(to: heading, in: note)
                    } label: {
                        Text(heading.title)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8 + CGFloat(heading.level - 1) * 12)
                            .padding(.trailing, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            linksSection
        }
    }

    private var linksSection: some View {
        let outgoing = model.outgoingLinks(for: note)
        let backlinks = model.backlinks(for: note)
        let isUnconnected = model.isNoteUnconnected(note)
        let candidates = isUnconnected ? model.suggestLinkCandidates(for: note, limit: 4) : []
        return VStack(alignment: .leading, spacing: 4) {
            if isUnconnected {
                unconnectedPromptBanner(candidates: candidates)
                    .padding(.bottom, 12)
            }

            sectionHeader("出链", count: outgoing.count)
            if outgoing.isEmpty {
                Text("这篇笔记还没有引用其他笔记。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 3)
            } else {
                ForEach(outgoing, id: \.id) { link in
                    InspectorOutgoingLinkRow(link: link, noteVaultID: note.vaultID, model: model)
                }
            }

            sectionHeader("反向链接", count: backlinks.count, top: 22)
            if backlinks.isEmpty {
                Text("还没有其他笔记链接到这里。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 3)
            } else {
                ForEach(backlinks, id: \.id) { link in
                    InspectorBacklinkRow(link: link, noteVaultID: note.vaultID, model: model)
                }
            }
        }
    }

    private func unconnectedPromptBanner(candidates: [LinkCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.warning)
                Text("当前笔记尚未建立连接")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            Text("添加 [[双向链接]] 或一键插入推荐关联，避免形成孤立笔记。")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !candidates.isEmpty {
                VStack(spacing: 5) {
                    ForEach(candidates) { candidate in
                        InspectorLinkCandidateRow(candidate: candidate, sourceNote: note, model: model)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.openGraph(focus: note.id)
                } label: {
                    Label("在图谱中查看", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.brandInk)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.warning.opacity(palette.isDark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.warning.opacity(0.32), lineWidth: 0.75)
        )
    }

    private var propertiesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("笔记属性")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 4)

            if note.properties.isEmpty && !addingProperty {
                Text("暂无属性")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            ForEach(note.properties) { property in
                HStack(alignment: .top, spacing: 6) {
                    Text(property.key)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                        .frame(minWidth: 60, alignment: .leading)
                    Text(property.value)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        model.updateNoteProperties(note.id, properties: note.properties.filter { $0.key != property.key })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            if addingProperty {
                VStack(spacing: 6) {
                    TextField("属性名", text: $newPropertyKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    TextField("属性值", text: $newPropertyValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    HStack {
                        Button("取消") {
                            addingProperty = false
                            newPropertyKey = ""
                            newPropertyValue = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Button("添加") {
                            let key = newPropertyKey.trimmingCharacters(in: .whitespaces)
                            let value = newPropertyValue.trimmingCharacters(in: .whitespaces)
                            guard !key.isEmpty else { return }
                            var properties = note.properties
                            properties.removeAll { $0.key == key }
                            properties.append(NoteProperty(key: key, value: value))
                            model.updateNoteProperties(note.id, properties: properties)
                            addingProperty = false
                            newPropertyKey = ""
                            newPropertyValue = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    addingProperty = true
                } label: {
                    Label("添加属性", systemImage: "plus")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.brandInk)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Divider().overlay(palette.divider).padding(.vertical, 12)

            Text("标签")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            if note.tags.isEmpty {
                Text("暂无标签")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(note.tags, id: \.self) { tag in
                        HStack(spacing: 5) {
                            Text("#\(tag)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.brandInk)
                            Spacer()
                            Button {
                                model.updateNoteTags(note.id, tags: note.tags.filter { $0 != tag })
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 22)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("添加标签", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .onSubmit { commitTag() }
                Button("添加") { commitTag() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.brandInk)
            }
            .padding(.top, 4)
        }
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty, !note.tags.contains(tag) else { return }
        model.updateNoteTags(note.id, tags: note.tags + [tag])
        newTag = ""
    }

    private func sectionHeader(_ title: String, count: Int, top: CGFloat = 22) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            Text("· \(count)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary.opacity(0.8))
            Spacer()
        }
        .padding(.top, top)
        .padding(.bottom, 3)
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().overlay(palette.divider).padding(.bottom, 8)
            HStack {
                Text("创建于")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack {
                Text("最后编辑")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(LexiDate.relative(note.updatedAt))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack {
                Text("文件")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button {
                    model.copyNotePath(note.id)
                } label: {
                    Text(note.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("复制绝对路径")
            }
            HStack {
                Text("版本历史")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button {
                    model.openVersionHistory(for: note.id)
                } label: {
                    let count = model.noteRevisions(for: note.id).count
                    Text(count > 0 ? "查看对比（\(count) 条快照）" : "查看与保存快照")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.brandInk)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct InspectorOutgoingLinkRow: View {
    @Environment(\.lexiPalette) private var palette
    let link: NoteLink
    let noteVaultID: String
    @ObservedObject var model: AppModel
    @State private var showPreview = false

    private var previewProvider: () -> LinkTargetPreview {
        let raw = link.targetID.isEmpty ? link.targetTitle : link.targetID
        let anchor = link.anchor.isEmpty ? nil : link.anchor
        return {
            model.linkTargetPreview(rawTarget: raw, anchor: anchor, preferredVaultID: noteVaultID)
        }
    }

    private func openTarget() {
        if link.targetID.isEmpty {
            model.openWikiLink(link.targetTitle)
        } else if !link.anchor.isEmpty {
            model.openWikiLink("\(link.targetTitle)#\(link.anchor)")
        } else {
            model.openNote(link.targetID)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: link.targetID.isEmpty ? "plus.circle" : "arrow.up.right")
                .font(.system(size: 9.5))
                .foregroundStyle(link.targetID.isEmpty ? palette.warning : palette.brand)
            Button {
                openTarget()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.targetTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(link.targetID.isEmpty ? palette.textSecondary : palette.brandInk)
                        .lineLimit(1)
                    if !link.anchor.isEmpty {
                        Text("#\(link.anchor)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if link.targetID.isEmpty {
                Text("未创建")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.warning)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Capsule().fill(palette.warning.opacity(0.14)))
            }
            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("快速预览链接目标")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 32)
        .modifier(LinkHoverPreviewModifier(previewProvider: previewProvider,
                                           arrowEdge: .leading,
                                           onOpen: openTarget,
                                           isPresented: $showPreview))
    }
}

private struct InspectorBacklinkRow: View {
    @Environment(\.lexiPalette) private var palette
    let link: NoteLink
    let noteVaultID: String
    @ObservedObject var model: AppModel
    @State private var showPreview = false

    private var previewProvider: () -> LinkTargetPreview {
        { model.linkTargetPreview(rawTarget: link.sourceID, anchor: nil, preferredVaultID: noteVaultID) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.openNote(link.sourceID)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.brand)
                    Text(link.sourceTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.brandInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("快速预览来源笔记")
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .modifier(LinkHoverPreviewModifier(previewProvider: previewProvider,
                                           arrowEdge: .leading,
                                           onOpen: { model.openNote(link.sourceID) },
                                           isPresented: $showPreview))
    }
}

private struct InspectorLinkCandidateRow: View {
    @Environment(\.lexiPalette) private var palette
    let candidate: LinkCandidate
    let sourceNote: Note
    @ObservedObject var model: AppModel
    @State private var showPreview = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showPreview.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(candidate.reason)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.insertWikiLink(candidate.title, into: sourceNote.id)
            } label: {
                Text("+ 链接")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(palette.brandSoft))
            }
            .buttonStyle(.plain)
            .help("向正文添加 [[\(candidate.title)]]")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surface.opacity(0.85))
        )
        .modifier(LinkHoverPreviewModifier(
            previewProvider: { model.linkTargetPreview(rawTarget: candidate.noteID, preferredVaultID: sourceNote.vaultID) },
            arrowEdge: .leading,
            onOpen: { model.openNote(candidate.noteID) },
            isPresented: $showPreview
        ))
    }
}
