import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Root

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.lexiSnapshot) private var snapshotMode

    @State private var sidebarDragStart: CGFloat?
    @State private var inspectorDragStart: CGFloat?
    @State private var isFullScreen = false
    @State private var trafficLightsTrailing: CGFloat = WindowChrome.defaultTrafficLightsTrailing

    private var isDark: Bool {
        switch settings.appearance {
        case .light: return false
        case .dark: return true
        case .system: return systemScheme == .dark
        }
    }

    private var palette: ThemePalette { settings.palette(dark: isDark) }

    var body: some View {
        let palette = self.palette
        let zoom = CGFloat(max(0.75, min(1.5, settings.interfaceZoom / 100.0)))
        GeometryReader { geo in
            VStack(spacing: 0) {
                TitleBarView(model: model, settings: settings,
                             isFullScreen: isFullScreen,
                             trafficLightsTrailing: trafficLightsTrailing)
                    .background(WindowDragArea())
                HStack(spacing: 0) {
                    if settings.showRibbon {
                        RailView(model: model, settings: settings)
                    }
                    SidebarView(model: model, settings: settings)
                        .frame(width: settings.sidebarWidth)
                        .frame(width: settings.showSidebar ? settings.sidebarWidth : 0, alignment: .trailing)
                        .clipped()
                        .opacity(settings.showSidebar ? 1 : 0)
                        .allowsHitTesting(settings.showSidebar)
                        .accessibilityHidden(!settings.showSidebar)
                        .overlay(alignment: .trailing) {
                            if settings.showSidebar {
                                ResizeHandle(onDrag: { translation in
                                    if sidebarDragStart == nil { sidebarDragStart = settings.sidebarWidth }
                                    settings.sidebarWidth = Double(clamp((sidebarDragStart ?? settings.sidebarWidth) + translation, 200, 420))
                                }, onEnd: { sidebarDragStart = nil })
                                .offset(x: 4)
                            }
                        }
                        .zIndex(1)
                    MainAreaView(model: model, settings: settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    InspectorContainer(model: model, settings: settings)
                        .frame(width: settings.inspectorWidth)
                        .frame(width: (settings.showInspector && showsInspector) ? settings.inspectorWidth : 0, alignment: .leading)
                        .clipped()
                        .opacity((settings.showInspector && showsInspector) ? 1 : 0)
                        .allowsHitTesting(settings.showInspector && showsInspector)
                        .accessibilityHidden(!(settings.showInspector && showsInspector))
                        .overlay(alignment: .leading) {
                            if settings.showInspector && showsInspector {
                                ResizeHandle(onDrag: { translation in
                                    if inspectorDragStart == nil { inspectorDragStart = settings.inspectorWidth }
                                    settings.inspectorWidth = Double(clamp((inspectorDragStart ?? settings.inspectorWidth) - translation, 232, 420))
                                }, onEnd: { inspectorDragStart = nil })
                                .offset(x: -4)
                            }
                        }
                        .zIndex(1)
                }
            }
            .frame(
                width: abs(zoom - 1.0) > 0.001 ? max(1, geo.size.width / zoom) : geo.size.width,
                height: abs(zoom - 1.0) > 0.001 ? max(1, geo.size.height / zoom) : geo.size.height
            )
            .scaleEffect(zoom, anchor: .topLeading)
        }
        .disabled(model.settingsVisible || model.trashVisible)
        .accessibilityHidden(model.settingsVisible || model.trashVisible)
        .animation(LexiMotion.drawer(settings), value: settings.showSidebar)
        .animation(LexiMotion.drawer(settings), value: settings.showInspector)
        .animation(LexiMotion.fast(settings), value: settings.showRibbon)
        .background(palette.workspacePage)
        .environment(\.lexiPalette, palette)
        .environment(\.lexiSnapshot, snapshotMode)
        .preferredColorScheme(settings.preferredColorScheme)
        .tint(palette.brand)
        .frame(minWidth: 1120, minHeight: 720)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChrome(appearance: settings.appearance,
                                 pageColor: palette.workspacePage,
                                 onWindowChange: { window in
                                     if let window {
                                         WindowRegistry.shared.register(window: window, model: model, settings: settings)
                                     }
                                 }) { fullScreen, trailing in
            isFullScreen = fullScreen
            if trailing > 0 {
                trafficLightsTrailing = trailing
            }
        })
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(60)
            }
        }
        .overlay {
            if model.paletteVisible {
                CommandPalettePanel(model: model, settings: settings)
                    .transition(LexiMotion.paletteTransition(reduced: LexiMotion.isReduced(settings)))
                    .zIndex(80)
            }
        }
        .overlay {
            WorkspaceModalSheet(isPresented: model.settingsVisible, settings: settings,
                                onDismiss: { model.settingsVisible = false }) {
                SettingsView(model: model, settings: settings)
            }
            .environment(\.lexiPalette, palette)
            .preferredColorScheme(settings.preferredColorScheme)
            .tint(palette.brand)
        }
        .overlay {
            WorkspaceModalSheet(isPresented: model.trashVisible, settings: settings,
                                onDismiss: { model.trashVisible = false }) {
                TrashSheet(model: model, settings: settings,
                           onClose: { model.trashVisible = false })
            }
            .environment(\.lexiPalette, palette)
            .preferredColorScheme(settings.preferredColorScheme)
            .tint(palette.brand)
        }
        .animation(model.paletteVisible ? LexiMotion.paletteIn(settings) : nil, value: model.paletteVisible)
        .animation(LexiMotion.fast(settings), value: model.toast?.id)
        .sheet(isPresented: $model.templatesVisible) {
            TemplatePickerSheet(model: model, settings: settings)
        }
        .sheet(isPresented: $model.welcomeVisible) {
            WelcomeSheet(model: model, settings: settings)
        }
        .sheet(item: $model.workspacePromptVault) { vault in
            WorkspaceOpenPromptSheet(model: model, settings: settings, vault: vault)
        }
        .sheet(isPresented: $model.historyVisible) {
            if let noteID = model.historyTargetNoteID ?? model.currentNote?.id, !noteID.isEmpty {
                NoteHistorySheet(model: model, settings: settings, noteID: noteID)
            }
        }
        .transaction { transaction in
            if !settings.animateAppearance || settings.reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .onAppear {
            model.bootstrapSession()
            model.plugins.applyThemeCss(palette: palette)
        }
        .onChange(of: palette) { _, newPalette in
            model.plugins.applyThemeCss(palette: newPalette)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lexiFocusSidebarSearch)) { _ in
            settings.showSidebar = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lexiOpenSettings)) { _ in
            model.presentSettings()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers)
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in matching {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let str = String(data: data, encoding: .utf8),
                   let url = URL(string: str) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                } else if let url = item as? URL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                model.openExternalFiles(urls, sourceLabel: "拖入")
            }
        }
        return true
    }

    private var showsInspector: Bool {
        guard let tab = model.currentTab else { return true }
        return tab.kind != .graph && tab.kind != .map
    }
}

// MARK: - Title bar

struct TitleBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    var isFullScreen: Bool = false
    var trafficLightsTrailing: CGFloat = WindowChrome.defaultTrafficLightsTrailing
    @Environment(\.lexiPalette) private var palette
    @Environment(\.lexiSnapshot) private var snapshotMode

    private var trafficAreaWidth: CGFloat {
        if isFullScreen { return 14 }
        return max(78, trafficLightsTrailing + 12)
    }

    private var sidebarTint: Color {
        palette.workspaceSidebar
    }

    private var tabsTint: Color {
        palette.workspaceTabs
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if snapshotMode && !isFullScreen {
                    snapshotTrafficLights
                        .frame(width: trafficAreaWidth, height: Metrics.titlebarHeight, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: trafficAreaWidth, height: Metrics.titlebarHeight)
                }

                HStack(spacing: 7) {
                    LexiLogoMark(size: 28)
                    Text("知萤")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    if settings.showSidebar {
                        Text("LexiNote")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.brandInk)
                            .padding(.top, 1)
                            .transition(.opacity)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                if settings.showSidebar {
                    Spacer(minLength: 0)
                } else {
                    Spacer().frame(width: 10)
                    Rectangle()
                        .fill(palette.workspaceLine.opacity(0.85))
                        .frame(width: 0.5, height: 16)
                }
            }
            .frame(width: settings.showSidebar ? settings.sidebarWidth + (settings.showRibbon ? Metrics.railWidth : 0) : nil)
            .frame(maxHeight: .infinity)
            .background(settings.showSidebar ? sidebarTint : Color.clear)
            .overlay(alignment: .trailing) {
                if settings.showSidebar {
                    Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
                }
            }

            HStack(spacing: 4) {
                LexiIconButton(symbol: "list.bullet", size: 17, frame: 34,
                               help: settings.showSidebar ? "隐藏知识库侧栏 (⌃⌘S)" : "显示知识库侧栏 (⌃⌘S)") {
                    LexiMotion.perform(settings, LexiMotion.drawer(settings)) { settings.showSidebar.toggle() }
                }
                .padding(.leading, settings.showSidebar ? 6 : 8)

                if settings.showTabStrip {
                    TabStripView(model: model, settings: settings)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 8) {
                        Text(model.currentTab.map { model.tabTitle($0) } ?? "知萤工作区")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity)
                }

                NewContentMenu(model: model)

                LexiIconButton(symbol: "sidebar.trailing", size: 18, frame: 34,
                               active: settings.showInspector,
                               help: settings.showInspector ? "隐藏右侧栏 (⌥⌘S)" : "显示右侧栏 (⌥⌘S)") {
                    LexiMotion.perform(settings, LexiMotion.drawer(settings)) { settings.showInspector.toggle() }
                }

                if !settings.showRibbon {
                    LexiIconButton(symbol: "gearshape", size: 14.5, frame: 30,
                                   active: model.settingsVisible,
                                   help: "设置 (⌘,)") {
                        model.presentSettings()
                    }
                }
            }
            .padding(.trailing, 10)
            .frame(maxHeight: .infinity)
            .background(settings.showSidebar ? tabsTint : Color.clear)
        }
        .frame(height: Metrics.titlebarHeight)
        .background(settings.showSidebar ? Color.clear : tabsTint)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private var snapshotTrafficLights: some View {
        let dotSize: CGFloat = {
            if #available(macOS 26.0, *) { return 14 }
            return 12
        }()
        let dotGap: CGFloat = {
            if #available(macOS 26.0, *) { return 9 }
            return 8
        }()
        let leading: CGFloat = {
            if #available(macOS 26.0, *) { return 18 }
            return 16
        }()
        return HStack(spacing: dotGap) {
            Circle().fill(Color(hex: "#FF5F57")).frame(width: dotSize, height: dotSize)
            Circle().fill(Color(hex: "#FEBC2E")).frame(width: dotSize, height: dotSize)
            Circle().fill(Color(hex: "#28C840")).frame(width: dotSize, height: dotSize)
        }
        .padding(.leading, leading)
    }
}

private struct TabStripView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette
    @Namespace private var activeTabNamespace

    var body: some View {
        GeometryReader { geometry in
            let count = max(model.openTabs.count, 1)
            let available = max(geometry.size.width - CGFloat(count - 1) * 3, 104)
            let tabWidth = clamp(available / CGFloat(count), 104, 196)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(model.openTabs) { tab in
                            TabItemView(model: model, settings: settings, tab: tab, width: tabWidth, namespace: activeTabNamespace)
                                .id(tab.id)
                        }
                    }
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .onChange(of: model.selectedTabID) { _, selected in
                    guard !selected.isEmpty else { return }
                    let contentWidth = tabWidth * CGFloat(count) + 3 * CGFloat(max(0, count - 1))
                    guard contentWidth > geometry.size.width else { return }
                    LexiMotion.perform(settings, LexiMotion.fast(settings)) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
        }
        .padding(.leading, 2)
        .frame(height: Metrics.titlebarHeight)
    }
}

private struct TabItemView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let tab: WorkspaceTab
    let width: CGFloat
    let namespace: Namespace.ID
    @Environment(\.lexiPalette) private var palette
    @State private var hovering = false

    private var selected: Bool { model.selectedTabID == tab.id }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: model.tabSymbol(tab))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? palette.brandInk : palette.textSecondary.opacity(0.9))
            Text(model.tabTitle(tab))
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LexiPressButtonStyle())
            .opacity(selected || hovering ? 1 : 0.72)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: width, height: Metrics.titlebarHeight - 10)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: LexiTokens.radiusSM, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: LexiTokens.radiusSM, style: .continuous)
                .fill(selected ? palette.workspacePage : (hovering ? palette.hoverFill : Color.clear))
        }
        .overlay(alignment: .top) {
            if selected {
                Rectangle()
                    .fill(palette.brand)
                    .frame(height: 2)
                    .matchedGeometryEffect(id: "active-tab-bar", in: namespace)
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: LexiTokens.radiusSM, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: LexiTokens.radiusSM, style: .continuous))
        .animation(LexiMotion.fast(settings), value: selected)
        .animation(LexiMotion.easeOutMicro, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            LexiMotion.perform(settings, LexiMotion.fast(settings)) {
                model.selectTab(tab.id)
            }
        }
        .contextMenu {
            Button("关闭标签") { model.closeTab(tab.id) }
            Button("关闭其他标签") { model.closeOtherTabs(keeping: tab.id) }
            Button("关闭右侧标签") { model.closeTabsToRight(of: tab.id) }
            if tab.kind == .note {
                Divider()
                Button("在 Finder 中显示") { model.revealNoteInFinder(tab.refID) }
                Button("复制文件路径") { model.copyNotePath(tab.refID) }
            }
        }
        .help(model.tabTitle(tab))
    }
}

private struct NewContentMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        Menu {
            Button("笔记") { model.createNote(title: "无标题笔记", type: .markdown) }
            Button("快速笔记") { model.createNote(title: "快速笔记", type: .quick, notebook: "速记收件箱") }
            Button("学习笔记") { model.createNote(title: "学习笔记", type: .study) }
            Divider()
            Button("思维导图") { model.createMap() }
            Button("白板") { model.createCanvas() }
            Divider()
            Button("从模板新建…") { model.templatesVisible = true }
            Button("今日笔记") { model.openDailyNote() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("新建")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(palette.brandInk)
            .frame(width: 76, height: 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: 76, height: 34)
        .background(palette.workspaceSelection, in: RoundedRectangle(cornerRadius: LexiTokens.radiusSM))
        .fixedSize()
        .padding(.horizontal, 6)
    }
}

// MARK: - Rail

private struct RailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var viewRegistry = PluginViewRegistry.shared
    @Environment(\.lexiPalette) private var palette

    private var activeTabKind: TabKind? { model.currentTab?.kind }

    var body: some View {
        VStack(spacing: 6) {
            if settings.isRibbonCommandVisible("vault") {
                railButton(.library, symbol: "folder", active: activeTabKind == nil || activeTabKind == .note || activeTabKind == .map || activeTabKind == .canvas) {
                    LexiMotion.perform(settings, LexiMotion.drawer(settings)) { settings.showSidebar.toggle() }
                }
            }
            if settings.isRibbonCommandVisible("switcher") {
                railButton(.search, symbol: "magnifyingglass", active: false) {
                    model.presentQuickSwitch()
                }
            }
            if settings.isRibbonCommandVisible("commands") {
                railButton(.commands, symbol: "command", active: model.paletteVisible && model.paletteMode == .commands) {
                    model.presentCommandPalette()
                }
            }
            if settings.isRibbonCommandVisible("reading") {
                let isReading = model.currentNote != nil && LexiEditorBridge.shared.isCurrentNoteReading
                railButton(.reading, symbol: "doc.text", active: isReading) {
                    NotificationCenter.default.post(
                        name: .lexiEditorCommand,
                        object: nil,
                        userInfo: ["command": EditorCommand.reading.rawValue]
                    )
                }
            }
            if settings.isRibbonCommandVisible("graph") {
                railButton(.graph, symbol: "point.3.connected.trianglepath.dotted", active: activeTabKind == .graph) {
                    model.openGraph(focus: model.currentNote?.id)
                }
            }

            ForEach(viewRegistry.ribbonActions) { action in
                if settings.isRibbonCommandVisible(action.id) {
                    RailButton(
                        symbol: action.icon,
                        label: action.title,
                        active: settings.showInspector && settings.inspectorMode.hasPrefix("plugin:\(action.pluginId):"),
                        tint: nil
                    ) {
                        settings.showInspector = true
                        settings.inspectorMode = "plugin:\(action.pluginId):\(action.actionId)"
                        Task { @MainActor in
                            await model.plugins.presentView(pluginId: action.pluginId, viewId: action.actionId)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            railButton(.trash, symbol: "trash", active: model.trashVisible, tint: model.trashVisible ? palette.brand : palette.textSecondary) {
                model.openTrash()
            }
            railButton(.settings, symbol: "gearshape", active: model.settingsVisible) {
                model.presentSettings()
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: Metrics.railWidth)
        .frame(maxHeight: .infinity)
        .background(palette.workspaceRail)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
        }
    }

    private func railButton(_ kind: RailKind, symbol: String, active: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        RailButton(symbol: symbol, label: kind.label, active: active, tint: tint, action: action)
    }
}

private enum RailKind {
    case library, search, commands, reading, graph, trash, settings
    var label: String {
        switch self {
        case .library: return "知识库"
        case .search: return "快速切换文档 (⌘P)"
        case .commands: return "命令面板 (⌘K)"
        case .reading: return "切换编辑与阅读"
        case .graph: return "笔记关联 (⌘G)"
        case .trash: return "回收站"
        case .settings: return "设置 (⌘,)"
        }
    }
}

private struct RailButton: View {
    @Environment(\.lexiPalette) private var palette
    let symbol: String
    let label: String
    let active: Bool
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(active ? palette.brand : (tint ?? palette.textSecondary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: LexiTokens.radiusSM, style: .continuous)
                        .fill(active ? palette.workspaceSelection : (hovering ? palette.hoverFill : Color.clear))
                )
                .animation(LexiMotion.easeOutMicro, value: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(LexiPressButtonStyle())
        .onHover { hovering = $0 }
        .help(label)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette
    @State private var collapsed: Set<String> = []
    @State private var prompt: PromptRequest?
    @State private var hoveredNotebook: String?
    @State private var hoveredNoteID: String?
    @State private var switcherOpen = false

    var body: some View {
        VStack(spacing: 0) {
            header
            search
            quickActions
            filters
            noteList
            switcher
        }
        .background(palette.workspaceSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
        }
        .sheet(item: $prompt) { request in
            TextPromptSheet(request: request)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("知识库")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text("\(model.visibleNotes.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
        .frame(height: 48)
        .padding(.leading, 18)
        .padding(.trailing, 12)
    }

    private var search: some View {
        LexiSearchField(text: $model.searchText, placeholder: "搜索 · tag: type: ...")
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            Button {
                model.openDailyNote()
            } label: {
                Text("今日笔记")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.brand)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.templatesVisible = true
            } label: {
                Text("模板")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.brand)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            sortMenu
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(NoteSortMode.allCases) { mode in
                Button {
                    settings.sidebarSortMode = mode
                } label: {
                    HStack {
                        Text(mode.label)
                        if settings.sidebarSortMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("排序：\(settings.sidebarSortMode.label)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("切换笔记排序方式")
    }

    private var filters: some View {
        let unconnectedCount = model.unconnectedNoteCount
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill("全部笔记", active: !model.favoritesOnly && !model.unconnectedOnly) {
                    model.favoritesOnly = false
                    model.unconnectedOnly = false
                }
                filterPill("收藏", active: model.favoritesOnly) {
                    model.favoritesOnly = true
                    model.unconnectedOnly = false
                }
                filterPill("未连接 (\(unconnectedCount))", active: model.unconnectedOnly) {
                    model.unconnectedOnly.toggle()
                    if model.unconnectedOnly { model.favoritesOnly = false }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func filterPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? palette.workspaceSelection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noteList: some View {
        let unconnectedIDs = Set(model.unconnectedNotes().map(\.id))
        let trimmedQuery = model.searchText.trimmingCharacters(in: .whitespaces)
        let flatRecent = settings.sidebarSortMode == .accessed && trimmedQuery.isEmpty
        return ScrollView {
            LazyVStack(spacing: 4) {
                if model.visibleNotes.isEmpty {
                    emptyHint
                } else if flatRecent {
                    ForEach(model.visibleNotes) { note in
                        noteRow(note, isUnconnected: unconnectedIDs.contains(note.id), showNotebookMeta: true)
                    }
                } else {
                    ForEach(model.notebookGroups) { group in
                        notebookGroup(group, unconnectedIDs: unconnectedIDs)
                    }
                }
                if !trimmedQuery.isEmpty {
                    searchSummary
                }
                if model.searchText.isEmpty && !model.favoritesOnly && !model.unconnectedOnly {
                    visualSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyHint: some View {
        Text(model.searchText.isEmpty
             ? (model.favoritesOnly ? "收藏的笔记会出现在这里"
                : (model.unconnectedOnly ? "所有笔记都已建立连接" : "写下第一条笔记"))
             : "没有找到匹配的笔记")
            .font(.system(size: 12))
            .lineSpacing(10)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    private var searchSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5))
            Text("匹配 \(model.visibleNotes.count) 篇笔记")
                .font(.system(size: 10.5))
            Spacer()
            Button("清除") { model.searchText = "" }
                .font(.system(size: 10.5))
                .buttonStyle(.plain)
                .foregroundStyle(palette.brandInk)
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    private func notebookGroup(_ group: NotebookGroup, unconnectedIDs: Set<String>) -> some View {
        let isCollapsed = collapsed.contains(group.name) && model.searchText.isEmpty
        return VStack(spacing: 2) {
            Button {
                LexiMotion.perform(settings, LexiMotion.fast(settings)) {
                    if collapsed.contains(group.name) {
                        collapsed.remove(group.name)
                    } else {
                        collapsed.insert(group.name)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(LexiMotion.fast(settings), value: isCollapsed)
                        .frame(width: 9)
                    Image(systemName: "folder")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.brand)
                    Text(group.name)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(group.notes.count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                }
                .padding(.leading, 5)
                .padding(.trailing, 10)
                .frame(height: 36)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: LexiTokens.radiusXS, style: .continuous)
                        .fill(hoveredNotebook == group.name ? palette.hoverFill : Color.clear)
                )
                .animation(LexiMotion.easeOutMicro, value: hoveredNotebook)
            }
            .buttonStyle(LexiPressButtonStyle())
            .onHover { hoveredNotebook = $0 ? group.name : nil }
            .contextMenu {
                Button("在此新建笔记") {
                    model.createNote(title: "无标题笔记", type: .markdown, notebook: group.name)
                }
                Button("新建此文件夹的思维导图") {
                    model.createMap(title: "\(group.name)导图")
                }
            }

            if !isCollapsed {
                ForEach(group.notes) { note in
                    noteRow(note, isUnconnected: unconnectedIDs.contains(note.id), showNotebookMeta: false)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func noteRow(_ note: Note, isUnconnected: Bool = false, showNotebookMeta: Bool = false) -> some View {
        let selected = model.currentNote?.id == note.id
        let trimmedSearch = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchSnippet = trimmedSearch.isEmpty ? "" : note.snippet(matching: trimmedSearch, maxLength: 72)
        return Button {
            model.openNote(note.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: note.type == .quick ? "bolt" : "doc.text")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(selected ? palette.brand : palette.textSecondary)
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HighlightText(text: note.displayTitle,
                                  query: trimmedSearch,
                                  font: .system(size: 13, weight: selected ? .medium : .regular),
                                  color: selected ? palette.brandInk : palette.textPrimary,
                                  lineLimit: 1)
                    if !matchSnippet.isEmpty {
                        HighlightText(text: matchSnippet,
                                      query: trimmedSearch,
                                      font: .system(size: 11),
                                      color: palette.textSecondary,
                                      lineLimit: 2)
                    } else if showNotebookMeta {
                        Text("\(note.notebook) · \(LexiDate.relative(model.accessDate(for: note)))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isUnconnected {
                        Text("未连")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 4).fill(palette.softSurface))
                    }
                    if note.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.brand)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, (matchSnippet.isEmpty && !showNotebookMeta) ? 8 : 7)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: LexiTokens.radiusXS, style: .continuous)
                    .fill(selected ? palette.workspaceSelection : (hoveredNoteID == note.id ? palette.hoverFill : Color.clear))
            )
            .animation(LexiMotion.easeOutMicro, value: hoveredNoteID)
        }
        .buttonStyle(LexiPressButtonStyle())
        .onHover { inside in
            hoveredNoteID = inside ? note.id : (hoveredNoteID == note.id ? nil : hoveredNoteID)
        }
        .contextMenu {
            Button("打开") { model.openNote(note.id) }
            Button("版本历史与差异对比…") { model.openVersionHistory(for: note.id) }
            Button(note.favorite ? "取消收藏" : "收藏") { model.toggleFavorite(note.id) }
            Button(note.pinned ? "取消置顶" : "置顶") { model.togglePin(note.id) }
            Button("重命名…") {
                prompt = PromptRequest(title: "重命名笔记", placeholder: "笔记标题",
                                       initial: note.title, confirmTitle: "重命名") { value in
                    model.updateNoteTitle(note.id, title: value)
                    _ = model.saveNoteNow(note.id)
                }
            }
            Menu("移动到") {
                ForEach(model.notebookGroups.map(\.name), id: \.self) { name in
                    Button(name) { model.moveNote(note.id, toNotebook: name) }
                }
                Divider()
                Button("新建笔记本…") {
                    prompt = PromptRequest(title: "新建笔记本", placeholder: "笔记本名称",
                                           initial: "", confirmTitle: "创建并移动") { value in
                        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        model.moveNote(note.id, toNotebook: value)
                    }
                }
            }
            Divider()
            Button("复制笔记") { model.duplicateNote(note.id) }
            Button("复制文件路径") { model.copyNotePath(note.id) }
            Button("在 Finder 中显示") { model.revealNoteInFinder(note.id) }
            Divider()
            Button("移至回收站", role: .destructive) { model.trashNote(note.id) }
        }
        .help(note.notebook + " · " + LexiDate.relative(note.updatedAt))
    }

    private var visualSection: some View {
        VStack(spacing: 4) {
            Divider()
                .overlay(palette.workspaceLine)
                .padding(.vertical, 8)
            HStack {
                Text("可视化空间")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.leading, 6)
            .padding(.bottom, 2)

            ForEach(model.maps.filter { $0.vaultID == model.activeVaultID && $0.trashedAt == nil }) { map in
                visualRow(symbol: "point.3.connected.trianglepath.dotted",
                          title: map.title.isEmpty ? "未命名导图" : map.title,
                          selected: model.currentTab?.kind == .map && model.currentTab?.refID == map.id) {
                    model.openMap(map.id)
                }
            }
            ForEach(model.canvases.filter { $0.vaultID == model.activeVaultID }) { board in
                visualRow(symbol: "rectangle.3.group",
                          title: board.title.isEmpty ? "未命名白板" : board.title,
                          selected: model.currentTab?.kind == .canvas && model.currentTab?.refID == board.id) {
                    model.openCanvas(board.id)
                }
            }
        }
    }

    private func visualRow(symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? palette.brand : palette.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? palette.brandInk : palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? palette.workspaceSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var switcher: some View {
        Button {
            switcherOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(palette.brandInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.activeVault?.name ?? "我的工作区")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("全部项目")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $switcherOpen, arrowEdge: .top) {
            switcherPopover
        }
        .overlay(alignment: .top) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
        .help("工作区与项目")
    }

    private var switcherPopover: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("选择工作区")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 3)
            ForEach(model.vaults) { vault in
                Button {
                    switcherOpen = false
                    model.requestOpenWorkspace(vault)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(vault.id == model.activeVaultID ? palette.brandInk : palette.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vault.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(vault.id == model.activeVaultID ? palette.brandInk : palette.textPrimary)
                            Text(vault.detail)
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if vault.id == model.activeVaultID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.brandInk)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(palette.workspaceLine).padding(.vertical, 4)
            menuRow("新建工作区…", symbol: "folder.badge.plus") {
                switcherOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    prompt = PromptRequest(title: "新建工作区",
                                           placeholder: "工作区名称",
                                           initial: "",
                                           confirmTitle: "创建") { value in
                        _ = model.createVault(name: value)
                    }
                }
            }
            menuRow("在 Finder 中显示知识库", symbol: "folder") {
                model.revealStorageInFinder()
                switcherOpen = false
            }
            menuRow("导出工作区压缩包…", symbol: "doc.zipper") {
                model.exportWorkspaceZip()
                switcherOpen = false
            }
            menuRow("设置…", symbol: "gearshape") {
                switcherOpen = false
                model.presentSettings()
            }
        }
        .padding(8)
        .frame(width: 280)
        .background(palette.surface)
    }

    private func menuRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11.5))
                Spacer()
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

struct PromptRequest: Identifiable {
    let id = UUID()
    let title: String
    let placeholder: String
    let initial: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
}

// MARK: - Main content

struct MainAreaView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        Group {
            if let tab = model.currentTab {
                switch tab.kind {
                case .note:
                    if let note = model.note(tab.refID) {
                        NoteWorkspaceView(model: model, settings: settings, note: note)
                            .id(note.id + (model.presentationOverride?.rawValue ?? ""))
                    } else {
                        missingView
                    }
                case .map:
                    if let map = model.map(tab.refID) {
                        MindMapWorkspaceView(model: model, settings: settings, map: map)
                    } else {
                        missingView
                    }
                case .canvas:
                    if let board = model.canvas(tab.refID) {
                        CanvasWorkspaceView(model: model, settings: settings, board: board)
                    } else {
                        missingView
                    }
                case .graph:
                    GraphWorkspaceView(model: model, settings: settings)
                case .trash:
                    TrashWorkspaceView(model: model, settings: settings)
                }
            } else {
                EmptyWorkspaceView(model: model, settings: settings)
            }
        }
    }

    private var missingView: some View {
        EmptyStatePanel(symbol: "doc.questionmark", title: "文档暂时无法打开",
                        detail: "它可能已被移动或删除。请从侧栏重新选择一篇笔记。")
    }
}

// MARK: - Empty workspace

struct EmptyWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(palette.brand)
            Text("选择或新建一篇笔记")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            Text("从左侧打开已有笔记，或点击右上角“新建”开始记录。")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.workspacePage)
    }
}
