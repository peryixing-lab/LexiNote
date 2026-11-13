import SwiftUI
import Combine

enum EditorFontDesign: String, CaseIterable, Identifiable {
    case system, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "系统"
        case .serif: return "衬线"
        case .mono: return "等宽"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

enum EditorPresentation: String, CaseIterable, Identifiable {
    case source, live, reading
    var id: String { rawValue }
    var label: String {
        switch self {
        case .source: return "源码"
        case .live: return "实时预览"
        case .reading: return "阅读"
        }
    }
    var symbol: String {
        switch self {
        case .source: return "chevron.left.forwardslash.chevron.right"
        case .live: return "rectangle.split.2x1"
        case .reading: return "book"
        }
    }
}

enum WorkspaceOpenMode: String, CaseIterable, Identifiable {
    case ask
    case current
    case new

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: return "每次询问"
        case .current: return "在当前窗口打开"
        case .new: return "在新窗口打开"
        }
    }
}

struct CssSnippet: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var css: String
    var enabled: Bool
}

@MainActor
final class SettingsStore: ObservableObject {
    static let customStoragePathKey = "lexi.mac.customStoragePath"

    private enum GlobalKey {
        static let workspaceOpenMode = "lexi.mac.workspaceOpenMode"
        static let showWelcome = "lexi.mac.showWelcome"
        static let interfaceLanguage = "lexi.mac.interfaceLanguage"
        static let hotkeyOverrides = "lexi.mac.hotkeyOverrides"
        static let customStoragePath = "lexi.mac.customStoragePath"
        static let migrationFlag = "lexi.mac.workspacePrefsMigrated.v1"
        static let legacyPrefix = "lexi.mac."
    }

    private enum ScopeKey: String, CaseIterable {
        case appearance
        case themeMode
        case accent
        case customBackground
        case customForeground
        case useMaterial
        case sidebarWidth
        case inspectorWidth
        case showSidebar
        case showInspector
        case showTabStrip
        case showRibbon
        case hiddenRibbonCommands
        case interfaceZoom
        case showStatusBar
        case appearanceAnimated
        case editorFontSize
        case editorDesign
        case editorLineHeight
        case limitEditorWidth
        case spellCheck
        case autoSave
        case defaultPresentation
        case editorDefaultView
        case editorDefaultMode
        case editorViewStatus
        case editorShowTitle
        case editorDefaultTier
        case quickZoom
        case cssSnippets
        case restoreSession
        case reduceMotion
        case dailyNotebook
        case newNoteNotebook
        case inspectorMode
    }

    private enum SyncScope {
        case workspace(String)
        case global
    }

    private enum ReloadScope {
        case workspace
        case global
        case all
    }

    private static let syncNotification = Notification.Name("lexi.mac.settingsDidChange")

    let defaults: UserDefaults
    private(set) var vaultID: String
    private var isApplyingValues = false
    private var syncObserver: NSObjectProtocol?

    // Workspace-scoped settings (bound per vaultID)
    @Published var appearance: AppearanceMode = .system {
        didSet { writeScoped(appearance.rawValue, key: .appearance) }
    }
    @Published var themeMode: ThemeMode = .original {
        didSet { writeScoped(themeMode.rawValue, key: .themeMode) }
    }
    @Published var accentHex: String = ThemeEngine.defaultAccent {
        didSet { writeScoped(accentHex, key: .accent) }
    }
    @Published var customBackgroundHex: String = "#F6F4FB" {
        didSet { writeScoped(customBackgroundHex, key: .customBackground) }
    }
    @Published var customForegroundHex: String = "#231B36" {
        didSet { writeScoped(customForegroundHex, key: .customForeground) }
    }
    @Published var useMaterial: Bool = true {
        didSet { writeScoped(useMaterial, key: .useMaterial) }
    }
    @Published var sidebarWidth: Double = 248 {
        didSet { writeScoped(sidebarWidth, key: .sidebarWidth) }
    }
    @Published var inspectorWidth: Double = 280 {
        didSet { writeScoped(inspectorWidth, key: .inspectorWidth) }
    }
    @Published var showSidebar: Bool = true {
        didSet { writeScoped(showSidebar, key: .showSidebar) }
    }
    @Published var showInspector: Bool = true {
        didSet { writeScoped(showInspector, key: .showInspector) }
    }
    @Published var showTabStrip: Bool = true {
        didSet { writeScoped(showTabStrip, key: .showTabStrip) }
    }
    @Published var showRibbon: Bool = true {
        didSet { writeScoped(showRibbon, key: .showRibbon) }
    }
    @Published var hiddenRibbonCommands: [String] = [] {
        didSet { writeScoped(hiddenRibbonCommands, key: .hiddenRibbonCommands) }
    }
    @Published var interfaceZoom: Double = 100 {
        didSet { writeScoped(interfaceZoom, key: .interfaceZoom) }
    }
    @Published var requestedSettingsSection: String? = nil
    @Published var showStatusBar: Bool = true {
        didSet { writeScoped(showStatusBar, key: .showStatusBar) }
    }
    @Published var animateAppearance: Bool = true {
        didSet { writeScoped(animateAppearance, key: .appearanceAnimated) }
    }
    @Published var editorFontSize: Double = 16 {
        didSet { writeScoped(editorFontSize, key: .editorFontSize) }
    }
    @Published var editorDesign: EditorFontDesign = .system {
        didSet { writeScoped(editorDesign.rawValue, key: .editorDesign) }
    }
    @Published var editorLineHeight: Double = 1.72 {
        didSet { writeScoped(editorLineHeight, key: .editorLineHeight) }
    }
    @Published var limitEditorWidth: Bool = true {
        didSet { writeScoped(limitEditorWidth, key: .limitEditorWidth) }
    }
    @Published var spellCheck: Bool = true {
        didSet { writeScoped(spellCheck, key: .spellCheck) }
    }
    @Published var autoSave: Bool = true {
        didSet { writeScoped(autoSave, key: .autoSave) }
    }
    @Published var defaultPresentation: EditorPresentation = .live {
        didSet { writeScoped(defaultPresentation.rawValue, key: .defaultPresentation) }
    }
    @Published var editorDefaultView: String = "edit" {
        didSet {
            writeScoped(editorDefaultView, key: .editorDefaultView)
            if !isApplyingValues {
                defaultPresentation = preferredPresentation
            }
        }
    }
    @Published var editorDefaultMode: String = "live" {
        didSet {
            writeScoped(editorDefaultMode, key: .editorDefaultMode)
            if !isApplyingValues {
                defaultPresentation = preferredPresentation
            }
        }
    }
    @Published var editorViewStatus: Bool = true {
        didSet { writeScoped(editorViewStatus, key: .editorViewStatus) }
    }
    @Published var editorShowTitle: Bool = true {
        didSet { writeScoped(editorShowTitle, key: .editorShowTitle) }
    }
    @Published var editorDefaultTier: EditorLevel = .simple {
        didSet { writeScoped(editorDefaultTier.rawValue, key: .editorDefaultTier) }
    }
    @Published var quickZoom: Bool = false {
        didSet { writeScoped(quickZoom, key: .quickZoom) }
    }
    @Published var cssSnippets: [CssSnippet] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(cssSnippets) {
                writeScoped(data, key: .cssSnippets)
            }
        }
    }
    @Published var restoreSession: Bool = true {
        didSet { writeScoped(restoreSession, key: .restoreSession) }
    }
    @Published var reduceMotion: Bool = false {
        didSet { writeScoped(reduceMotion, key: .reduceMotion) }
    }
    @Published var dailyNotebook: String = "每日笔记" {
        didSet { writeScoped(dailyNotebook, key: .dailyNotebook) }
    }
    @Published var newNoteNotebook: String = "笔记" {
        didSet { writeScoped(newNoteNotebook, key: .newNoteNotebook) }
    }
    @Published var inspectorMode: String = "outline" {
        didSet { writeScoped(inspectorMode, key: .inspectorMode) }
    }

    // Global app-level settings (not bound to individual workspaces)
    @Published var showWelcome: Bool = true {
        didSet { writeGlobal(showWelcome, key: GlobalKey.showWelcome) }
    }
    @Published var workspaceOpenMode: WorkspaceOpenMode = .ask {
        didSet { writeGlobal(workspaceOpenMode.rawValue, key: GlobalKey.workspaceOpenMode) }
    }
    @Published var interfaceLanguage: String = "zh-Hans" {
        didSet { writeGlobal(interfaceLanguage, key: GlobalKey.interfaceLanguage) }
    }
    @Published var hotkeyOverrides: [String: [String]] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeyOverrides) {
                writeGlobal(data, key: GlobalKey.hotkeyOverrides)
            }
        }
    }
    @Published var customStoragePath: String = "" {
        didSet { writeGlobal(customStoragePath, key: GlobalKey.customStoragePath) }
    }

    init(defaults: UserDefaults = .standard, vaultID: String = "default-vault") {
        self.defaults = defaults
        let normalizedVault = Self.sanitizedVaultKey(vaultID)
        self.vaultID = normalizedVault
        Self.migrateLegacyIfNeeded(defaults: defaults, initialVaultID: normalizedVault)
        reload(scope: .all)
        installSyncObserver()
    }

    deinit {
        if let token = syncObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    static func sanitizedVaultKey(_ vaultID: String) -> String {
        let cleaned = vaultID.replacingOccurrences(of: ".", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "default-vault" : cleaned
    }

    private static func scopedKey(_ key: ScopeKey, vaultID: String) -> String {
        "lexi.mac.vault.\(sanitizedVaultKey(vaultID)).\(key.rawValue)"
    }

    static func migrateLegacyIfNeeded(defaults: UserDefaults, initialVaultID: String) {
        guard !defaults.bool(forKey: GlobalKey.migrationFlag) else { return }
        let targetVaultID = sanitizedVaultKey(initialVaultID)
        for key in ScopeKey.allCases {
            let legacyKey = GlobalKey.legacyPrefix + key.rawValue
            let destKey = scopedKey(key, vaultID: targetVaultID)
            if let legacyValue = defaults.object(forKey: legacyKey),
               defaults.object(forKey: destKey) == nil {
                defaults.set(legacyValue, forKey: destKey)
            }
        }
        defaults.set(true, forKey: GlobalKey.migrationFlag)
    }

    static func restoreSessionEnabled(for vaultID: String, defaults: UserDefaults = .standard) -> Bool {
        let key = scopedKey(.restoreSession, vaultID: vaultID)
        return defaults.object(forKey: key) as? Bool ?? true
    }

    func bind(to newVaultID: String) {
        let normalized = Self.sanitizedVaultKey(newVaultID)
        guard normalized != vaultID else { return }
        vaultID = normalized
        reload(scope: .workspace)
    }

    private func reload(scope: ReloadScope) {
        isApplyingValues = true
        defer { isApplyingValues = false }

        if scope == .workspace || scope == .all {
            let v = vaultID
            appearance = AppearanceMode(rawValue: defaults.string(forKey: Self.scopedKey(.appearance, vaultID: v)) ?? "") ?? .system
            themeMode = ThemeMode(rawValue: defaults.string(forKey: Self.scopedKey(.themeMode, vaultID: v)) ?? "") ?? .original
            accentHex = defaults.string(forKey: Self.scopedKey(.accent, vaultID: v)) ?? ThemeEngine.defaultAccent
            customBackgroundHex = defaults.string(forKey: Self.scopedKey(.customBackground, vaultID: v)) ?? "#F6F4FB"
            customForegroundHex = defaults.string(forKey: Self.scopedKey(.customForeground, vaultID: v)) ?? "#231B36"
            useMaterial = defaults.object(forKey: Self.scopedKey(.useMaterial, vaultID: v)) as? Bool ?? true
            sidebarWidth = defaults.object(forKey: Self.scopedKey(.sidebarWidth, vaultID: v)) as? Double ?? 248
            inspectorWidth = defaults.object(forKey: Self.scopedKey(.inspectorWidth, vaultID: v)) as? Double ?? 280
            showSidebar = defaults.object(forKey: Self.scopedKey(.showSidebar, vaultID: v)) as? Bool ?? true
            showInspector = defaults.object(forKey: Self.scopedKey(.showInspector, vaultID: v)) as? Bool ?? true
            showTabStrip = defaults.object(forKey: Self.scopedKey(.showTabStrip, vaultID: v)) as? Bool ?? true
            showRibbon = defaults.object(forKey: Self.scopedKey(.showRibbon, vaultID: v)) as? Bool ?? true
            hiddenRibbonCommands = defaults.stringArray(forKey: Self.scopedKey(.hiddenRibbonCommands, vaultID: v)) ?? []
            interfaceZoom = defaults.object(forKey: Self.scopedKey(.interfaceZoom, vaultID: v)) as? Double ?? 100
            showStatusBar = defaults.object(forKey: Self.scopedKey(.showStatusBar, vaultID: v)) as? Bool ?? true
            animateAppearance = defaults.object(forKey: Self.scopedKey(.appearanceAnimated, vaultID: v)) as? Bool ?? true
            editorFontSize = defaults.object(forKey: Self.scopedKey(.editorFontSize, vaultID: v)) as? Double ?? 16
            editorDesign = EditorFontDesign(rawValue: defaults.string(forKey: Self.scopedKey(.editorDesign, vaultID: v)) ?? "") ?? .system
            editorLineHeight = defaults.object(forKey: Self.scopedKey(.editorLineHeight, vaultID: v)) as? Double ?? 1.72
            limitEditorWidth = defaults.object(forKey: Self.scopedKey(.limitEditorWidth, vaultID: v)) as? Bool ?? true
            spellCheck = defaults.object(forKey: Self.scopedKey(.spellCheck, vaultID: v)) as? Bool ?? true
            autoSave = defaults.object(forKey: Self.scopedKey(.autoSave, vaultID: v)) as? Bool ?? true
            editorDefaultView = defaults.string(forKey: Self.scopedKey(.editorDefaultView, vaultID: v)) ?? "edit"
            editorDefaultMode = defaults.string(forKey: Self.scopedKey(.editorDefaultMode, vaultID: v)) ?? "live"
            let rawPresentation = defaults.string(forKey: Self.scopedKey(.defaultPresentation, vaultID: v)) ?? ""
            defaultPresentation = EditorPresentation(rawValue: rawPresentation) ?? preferredPresentation
            editorViewStatus = defaults.object(forKey: Self.scopedKey(.editorViewStatus, vaultID: v)) as? Bool ?? true
            editorShowTitle = defaults.object(forKey: Self.scopedKey(.editorShowTitle, vaultID: v)) as? Bool ?? true
            editorDefaultTier = EditorLevel(rawValue: defaults.string(forKey: Self.scopedKey(.editorDefaultTier, vaultID: v)) ?? "") ?? .simple
            quickZoom = defaults.object(forKey: Self.scopedKey(.quickZoom, vaultID: v)) as? Bool ?? false
            if let data = defaults.data(forKey: Self.scopedKey(.cssSnippets, vaultID: v)),
               let decoded = try? JSONDecoder().decode([CssSnippet].self, from: data) {
                cssSnippets = decoded
            } else {
                cssSnippets = []
            }
            restoreSession = defaults.object(forKey: Self.scopedKey(.restoreSession, vaultID: v)) as? Bool ?? true
            reduceMotion = defaults.object(forKey: Self.scopedKey(.reduceMotion, vaultID: v)) as? Bool ?? false
            dailyNotebook = defaults.string(forKey: Self.scopedKey(.dailyNotebook, vaultID: v)) ?? "每日笔记"
            newNoteNotebook = defaults.string(forKey: Self.scopedKey(.newNoteNotebook, vaultID: v)) ?? "笔记"
            inspectorMode = defaults.string(forKey: Self.scopedKey(.inspectorMode, vaultID: v)) ?? "outline"
        }

        if scope == .global || scope == .all {
            showWelcome = defaults.object(forKey: GlobalKey.showWelcome) as? Bool ?? true
            workspaceOpenMode = WorkspaceOpenMode(rawValue: defaults.string(forKey: GlobalKey.workspaceOpenMode) ?? "") ?? .ask
            interfaceLanguage = defaults.string(forKey: GlobalKey.interfaceLanguage) ?? "zh-Hans"
            customStoragePath = defaults.string(forKey: GlobalKey.customStoragePath) ?? ""
            if let data = defaults.data(forKey: GlobalKey.hotkeyOverrides),
               let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
                hotkeyOverrides = decoded
            } else {
                hotkeyOverrides = [:]
            }
        }
    }

    private func writeScoped(_ value: Any?, key: ScopeKey) {
        guard !isApplyingValues else { return }
        defaults.set(value, forKey: Self.scopedKey(key, vaultID: vaultID))
        postSync(.workspace(vaultID))
    }

    private func writeGlobal(_ value: Any?, key: String) {
        guard !isApplyingValues else { return }
        defaults.set(value, forKey: key)
        postSync(.global)
    }

    private func postSync(_ scope: SyncScope) {
        let sender = UInt(bitPattern: ObjectIdentifier(self))
        var info: [AnyHashable: Any] = ["sender": sender]
        switch scope {
        case .global:
            info["scope"] = "global"
        case .workspace(let changedVaultID):
            info["scope"] = "workspace"
            info["vaultID"] = changedVaultID
        }
        NotificationCenter.default.post(name: Self.syncNotification, object: defaults, userInfo: info)
    }

    private func installSyncObserver() {
        let sender = UInt(bitPattern: ObjectIdentifier(self))
        syncObserver = NotificationCenter.default.addObserver(
            forName: Self.syncNotification,
            object: defaults,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  (info["sender"] as? UInt) != sender,
                  let scope = info["scope"] as? String else { return }
            let changedVaultID = info["vaultID"] as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                if scope == "global" {
                    self.reload(scope: .global)
                } else if scope == "workspace", changedVaultID == self.vaultID {
                    self.reload(scope: .workspace)
                }
            }
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func palette(dark: Bool) -> ThemePalette {
        ThemeEngine.resolve(mode: themeMode,
                            accent: accentHex,
                            customBackground: customBackgroundHex,
                            customForeground: customForegroundHex,
                            dark: dark)
    }

    func selectPreset(_ preset: AccentPreset) {
        accentHex = preset.hex
        if themeMode == .original { themeMode = .preset }
    }

    func resetAppearance() {
        appearance = .system
        themeMode = .original
        accentHex = ThemeEngine.defaultAccent
        customBackgroundHex = "#F6F4FB"
        customForegroundHex = "#231B36"
        useMaterial = true
    }

    var preferredPresentation: EditorPresentation {
        if editorDefaultView == "preview" { return .reading }
        return editorDefaultMode == "source" ? .source : .live
    }

    func isRibbonCommandVisible(_ id: String) -> Bool {
        !hiddenRibbonCommands.contains(id)
    }

    func setRibbonCommandVisible(_ id: String, _ visible: Bool) {
        if visible {
            hiddenRibbonCommands.removeAll { $0 == id }
        } else if !hiddenRibbonCommands.contains(id) {
            hiddenRibbonCommands.append(id)
        }
    }

    func resetEditor() {
        editorFontSize = 16
        editorDesign = .system
        editorLineHeight = 1.72
        limitEditorWidth = true
        spellCheck = true
        autoSave = true
        editorDefaultView = "edit"
        editorDefaultMode = "live"
        editorViewStatus = true
        editorShowTitle = true
        editorDefaultTier = .simple
        defaultPresentation = .live
    }

    func markWelcomeSeen() {
        showWelcome = false
    }
}
