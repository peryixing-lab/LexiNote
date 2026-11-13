import SwiftUI
import Combine
import AppKit

// MARK: - Window payload & environment

struct WorkspaceWindowPayload: Codable, Hashable {
    var sessionID: String
    var vaultID: String?

    static let primary = WorkspaceWindowPayload(sessionID: "primary", vaultID: nil)
}

@MainActor
enum AppEnvironment {
    static let isSnapshot = CommandLine.arguments.contains("--snapshot")
        || CommandLine.arguments.contains("--window-shot")
        || CommandLine.arguments.contains("--settings-shot")

    static let defaults: UserDefaults = {
        if isSnapshot, let suite = UserDefaults(suiteName: "com.lexinote.mac.snapshot") {
            return suite
        }
        return .standard
    }()

    static let library: LibraryStore = {
        LibraryStore(storageRoot: LibraryStore.defaultStorageRoot(), inMemory: isSnapshot)
    }()

    static let settings: SettingsStore = {
        let sessionVault = isSnapshot ? nil : library.readSession()?.activeVaultID
        let initialVaultID = sessionVault.flatMap { library.vault($0)?.id } ?? library.defaultVaultID
        return SettingsStore(defaults: defaults, vaultID: initialVaultID)
    }()

    static let model: AppModel = {
        AppModel(settings: settings,
                 sharedLibrary: library,
                 initialVaultID: nil,
                 isPrimaryWindow: true)
    }()
}

// MARK: - Window registry

@MainActor
final class WindowRegistry: ObservableObject {
    static let shared = WindowRegistry()

    private struct Entry {
        weak var window: NSWindow?
        weak var model: AppModel?
        weak var settings: SettingsStore?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private weak var activeWindow: NSWindow?
    private var appObservers: [NSObjectProtocol] = []
    private var activeCancellables: [AnyCancellable] = []

    @Published private(set) var revision: Int = 0

    private init() {
        let center = NotificationCenter.default
        let keyObserver = center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                             object: nil,
                                             queue: .main) { [weak self] notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                self?.handleBecameKey(window)
            }
        }
        let closeObserver = center.addObserver(forName: NSWindow.willCloseNotification,
                                               object: nil,
                                               queue: .main) { [weak self] notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                self?.handleWillClose(window)
            }
        }
        appObservers = [keyObserver, closeObserver]
    }

    var currentModel: AppModel {
        activeModel(for: NSApp.keyWindow) ?? AppEnvironment.model
    }

    var currentSettings: SettingsStore {
        activeSettings(for: NSApp.keyWindow) ?? AppEnvironment.settings
    }

    func register(window: NSWindow, model: AppModel, settings: SettingsStore) {
        pruneDeallocated()
        let key = ObjectIdentifier(window)
        entries[key] = Entry(window: window, model: model, settings: settings)
        if NSApp.keyWindow === window || activeWindow == nil {
            setActiveWindow(window)
        }
    }

    func activeModel(for window: NSWindow?) -> AppModel? {
        guard let target = resolveHostWindow(from: window),
              let entry = entries[ObjectIdentifier(target)] else {
            return entries.values.compactMap(\.model).first
        }
        return entry.model
    }

    func activeSettings(for window: NSWindow?) -> SettingsStore? {
        guard let target = resolveHostWindow(from: window),
              let entry = entries[ObjectIdentifier(target)] else {
            return entries.values.compactMap(\.settings).first
        }
        return entry.settings
    }

    func flushAllWindows() {
        pruneDeallocated()
        for entry in entries.values {
            entry.model?.flushAll()
        }
        AppEnvironment.library.flushAllNotes(fallbackNotebook: currentSettings.newNoteNotebook)
    }

    private func resolveHostWindow(from window: NSWindow?) -> NSWindow? {
        if let window {
            let candidate = window.sheetParent ?? window
            if entries[ObjectIdentifier(candidate)] != nil {
                return candidate
            }
        }
        return activeWindow
    }

    private func handleBecameKey(_ window: NSWindow?) {
        guard let host = window.map({ $0.sheetParent ?? $0 }) else { return }
        guard entries[ObjectIdentifier(host)] != nil else { return }
        setActiveWindow(host)
    }

    private func handleWillClose(_ window: NSWindow?) {
        guard let window else { return }
        let key = ObjectIdentifier(window)
        if let entry = entries.removeValue(forKey: key) {
            entry.model?.flushAll()
        }
        if activeWindow === window {
            let next = NSApp.keyWindow.flatMap { entries[ObjectIdentifier($0.sheetParent ?? $0)]?.window }
                ?? entries.values.compactMap(\.window).first(where: { $0.isVisible })
            setActiveWindow(next)
        }
    }

    private func setActiveWindow(_ window: NSWindow?) {
        activeWindow = window
        activeCancellables.removeAll()
        if let window, let entry = entries[ObjectIdentifier(window)] {
            if let model = entry.model {
                model.objectWillChange
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.revision &+= 1 }
                    .store(in: &activeCancellables)
            }
            if let settings = entry.settings {
                settings.objectWillChange
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.revision &+= 1 }
                    .store(in: &activeCancellables)
            }
        }
        revision &+= 1
    }

    private func pruneDeallocated() {
        entries = entries.filter { _, entry in
            entry.window != nil && entry.model != nil
        }
    }
}

// MARK: - Window hosts

private struct WorkspaceWindowHost: View {
    let payload: WorkspaceWindowPayload

    var body: some View {
        if AppEnvironment.isSnapshot || (payload.sessionID == WorkspaceWindowPayload.primary.sessionID && payload.vaultID == nil) {
            ManagedRootView(model: AppEnvironment.model, settings: AppEnvironment.settings)
        } else {
            SecondaryWorkspaceWindowHost(vaultID: payload.vaultID)
                .id(payload.sessionID)
        }
    }
}

private struct SecondaryWorkspaceWindowHost: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppModel

    init(vaultID: String?) {
        let targetVaultID = vaultID ?? AppEnvironment.library.defaultVaultID
        let windowSettings = SettingsStore(defaults: AppEnvironment.defaults, vaultID: targetVaultID)
        let windowModel = AppModel(settings: windowSettings,
                                   sharedLibrary: AppEnvironment.library,
                                   initialVaultID: targetVaultID,
                                   isPrimaryWindow: false)
        _settings = StateObject(wrappedValue: windowSettings)
        _model = StateObject(wrappedValue: windowModel)
    }

    var body: some View {
        ManagedRootView(model: model, settings: settings)
    }
}

private struct ManagedRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RootView(model: model, settings: settings)
            .navigationTitle(windowTitle)
            .onAppear {
                model.onOpenNewWindow = { vaultID in
                    let payload = WorkspaceWindowPayload(sessionID: UUID().uuidString, vaultID: vaultID)
                    openWindow(id: "workspace", value: payload)
                }
            }
    }

    private var windowTitle: String {
        if AppEnvironment.isSnapshot || model.isPrimaryWindow {
            return "知萤 LexiNote"
        }
        let vaultName = model.activeVault?.name ?? "工作区"
        return "知萤 LexiNote — \(vaultName)"
    }
}

// MARK: - Application entry point

@main
struct LexiNoteMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var registry = WindowRegistry.shared

    var body: some Scene {
        WindowGroup("知萤 LexiNote", id: "workspace", for: WorkspaceWindowPayload.self) { $payload in
            WorkspaceWindowHost(payload: payload)
        } defaultValue: {
            .primary
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            LexiMenuCommands(registry: registry)
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var snapshotting = false
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollZoomAccumulator: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count {
            snapshotting = true
            let root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            let passed = SelfTest.run(root: root)
            exit(passed ? 0 : 1)
        }
        if let index = arguments.firstIndex(of: "--window-shot"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1])
            let showEmpty = arguments.contains("--empty")
            snapshotting = true
            let settings = AppEnvironment.settings
            settings.showWelcome = false
            settings.showInspector = true
            settings.appearance = .light
            settings.themeMode = .original
            settings.useMaterial = true
            settings.showTabStrip = true
            settings.showStatusBar = true
            AppEnvironment.model.bootstrapSession()
            if showEmpty {
                AppEnvironment.model.closeAllTabs()
            } else if let note = AppEnvironment.model.notes.first(where: { $0.id == "note-algo-complexity" }) {
                AppEnvironment.model.openNote(note.id)
            }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible && $0.title == "知萤 LexiNote" })?.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "知萤 LexiNote" })
                    ?? NSApp.keyWindow
                    ?? NSApp.windows.first(where: { $0.isVisible })
                self.capture(window: window, to: url)
                exit(0)
            }
            return
        }
        if let index = arguments.firstIndex(of: "--settings-shot"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1])
            snapshotting = true
            let settings = AppEnvironment.settings
            settings.showWelcome = false
            settings.appearance = .light
            settings.themeMode = .original
            settings.showInspector = true
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                AppEnvironment.model.presentSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    let main = NSApp.windows.first(where: { $0.isVisible && $0.title == "知萤 LexiNote" })
                    let sheet = main?.attachedSheet
                    self.capture(window: sheet ?? main, to: url)
                    exit(0)
                }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            snapshotting = true
            NSApp.windows.forEach { $0.alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                SnapshotRenderer.run(directory: directory)
                NSApp.terminate(nil)
            }
            return
        }
        installInputMonitors()
        DispatchQueue.main.async { [weak self] in
            self?.installCloseTabMenuItem()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !snapshotting
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        WindowRegistry.shared.flushAllWindows()
    }

    private func installInputMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !CommandRouter.isRecordingHotkey,
                  let canonical = HotkeyCodec.canonical(from: event) else {
                return event
            }
            let model = WindowRegistry.shared.currentModel
            let settings = WindowRegistry.shared.currentSettings
            if CommandRouter.performCustomHotkey(canonical: canonical, model: model, settings: settings) {
                return nil
            }
            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let settings = WindowRegistry.shared.currentSettings
            guard settings.quickZoom, event.modifierFlags.contains(.control) else {
                self.scrollZoomAccumulator = 0
                return event
            }
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.01 else { return nil }
            self.scrollZoomAccumulator += delta
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 0.5
            if abs(self.scrollZoomAccumulator) >= threshold {
                let step = self.scrollZoomAccumulator > 0 ? 1.0 : -1.0
                self.scrollZoomAccumulator = 0
                settings.editorFontSize = min(26, max(12, settings.editorFontSize + step))
            }
            return nil
        }
    }

    private func capture(window: NSWindow?, to url: URL) {
        guard let window, let view = window.contentView?.superview ?? window.contentView else {
            print("[capture] no window")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url, options: .atomic)
            print("[capture] \(Int(view.bounds.width))x\(Int(view.bounds.height)) -> \(url.path)")
        }
    }

    /// Replaces the system Close (⌘W) with "close active tab", keeping the window open while tabs remain.
    private func installCloseTabMenuItem() {
        guard let mainMenu = NSApp.mainMenu,
              let fileMenu = mainMenu.items.first(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) }) == true })?.submenu else { return }
        if let closeItem = fileMenu.items.first(where: { $0.action == #selector(NSWindow.performClose(_:)) }) {
            closeItem.title = "关闭标签"
            closeItem.action = #selector(closeActiveTab(_:))
            closeItem.target = self
            closeItem.keyEquivalent = "w"
            closeItem.keyEquivalentModifierMask = [.command]
        }
    }

    @objc private func closeActiveTab(_ sender: Any?) {
        if let window = NSApp.keyWindow, window.sheetParent != nil {
            window.performClose(sender)
            return
        }
        let model = WindowRegistry.shared.currentModel
        if model.selectedTabID.isEmpty {
            NSApp.keyWindow?.performClose(sender)
        } else {
            model.closeTab(model.selectedTabID)
        }
    }
}

// MARK: - Menus

struct LexiMenuCommands: Commands {
    @ObservedObject var registry: WindowRegistry

    private var model: AppModel { registry.currentModel }
    private var settings: SettingsStore { registry.currentSettings }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { model.presentSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("新建笔记") { CommandRouter.perform(.newNote, model: model) }
                .keyboardShortcut("n", modifiers: .command)
            Button("新建快速笔记") { CommandRouter.perform(.quickNote, model: model) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("新建学习笔记") { CommandRouter.perform(.studyNote, model: model) }
            Button("今日笔记") { CommandRouter.perform(.dailyNote, model: model) }
                .keyboardShortcut("d", modifiers: .command)
            Button("从模板新建…") { CommandRouter.perform(.templates, model: model) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("导入 Markdown…") { CommandRouter.perform(.importMarkdown, model: model) }
                .keyboardShortcut("o", modifiers: .command)
            Button("导出当前 Markdown…") { CommandRouter.perform(.exportMarkdown, model: model) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("导出完整备份…") { CommandRouter.perform(.exportBackup, model: model) }
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存当前文件") { CommandRouter.perform(.save, model: model) }
                .keyboardShortcut("s", modifiers: .command)
        }

        CommandGroup(replacing: .sidebar) {
            Button(settings.showSidebar ? "隐藏侧边栏" : "显示侧边栏") {
                CommandRouter.perform(.toggleSidebar, model: model)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(settings.showInspector ? "隐藏检查器" : "显示检查器") {
                CommandRouter.perform(.toggleInspector, model: model)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandGroup(after: .toolbar) {
            Button("命令面板") { CommandRouter.perform(.palette, model: model) }
                .keyboardShortcut("k", modifiers: .command)
            Button("快速切换文档") { CommandRouter.perform(.quickSwitch, model: model) }
                .keyboardShortcut("p", modifiers: .command)
            Button("关系图谱") { CommandRouter.perform(.graph, model: model) }
                .keyboardShortcut("g", modifiers: .command)
            Button("回收站") { CommandRouter.perform(.trash, model: model) }
            Divider()
            Menu("外观") {
                Button("浅色") { CommandRouter.perform(.appearanceLight, model: model) }
                Button("深色") { CommandRouter.perform(.appearanceDark, model: model) }
                Button("跟随系统") { CommandRouter.perform(.appearanceSystem, model: model) }
            }
        }

        CommandMenu("笔记") {
            Button("新建笔记") { CommandRouter.perform(.newNote, model: model) }
            Button("新建思维导图") { CommandRouter.perform(.newMap, model: model) }
            Button("新建白板") { CommandRouter.perform(.newCanvas, model: model) }
            Button("将当前笔记转为思维导图") { CommandRouter.perform(.convertToMap, model: model) }
                .disabled(model.currentNote == nil)
            Divider()
            Button("生成副本") { CommandRouter.perform(.duplicateNote, model: model) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.currentNote == nil)
            Button("在 Finder 中显示") { CommandRouter.perform(.revealInFinder, model: model) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.currentNote == nil)
            Button("复制文件路径") { CommandRouter.perform(.copyPath, model: model) }
                .disabled(model.currentNote == nil)
            Button("移至回收站") { CommandRouter.perform(.trashNote, model: model) }
                .disabled(model.currentNote == nil)
            Divider()
            Button("下一个标签") { model.nextTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .control, .shift])
            Button("上一个标签") { model.nextTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .control, .shift])
        }

        CommandMenu("格式") {
            Button("加粗") { postEditor(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("倾斜") { postEditor(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("删除线") { postEditor(.strike) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("高亮") { postEditor(.highlight) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("小标题 1") { postEditor(.h1) }
            Button("小标题 2") { postEditor(.h2) }
            Button("待办事项") { postEditor(.todo) }
            Button("表格") { postEditor(.table) }
            Button("代码块") { postEditor(.code) }
            Button("数学公式") { postEditor(.formula) }
            Button("标注") { postEditor(.callout) }
            Button("双向链接") { postEditor(.link) }
                .keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("切换编辑与阅读") { postEditor(.reading) }
                .keyboardShortcut("e", modifiers: .command)
            Button("查找…") {
                NotificationCenter.default.post(name: .lexiFindInNote, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("知萤使用说明") {
                model.welcomeVisible = true
            }
            Button("GitHub 项目主页") {
                if let url = URL(string: "https://github.com/peryixing-lab/LexiNote") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func postEditor(_ command: EditorCommand) {
        NotificationCenter.default.post(name: .lexiEditorCommand, object: nil,
                                        userInfo: ["command": command.rawValue])
    }
}
