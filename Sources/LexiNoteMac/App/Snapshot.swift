import SwiftUI
import AppKit

@MainActor
enum SnapshotRenderer {
    static func run(directory: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let model = AppEnvironment.model
        let settings = AppEnvironment.settings
        settings.showWelcome = false
        settings.useMaterial = false
        settings.restoreSession = true
        settings.showTabStrip = true
        settings.showStatusBar = true
        settings.animateAppearance = true
        settings.showInspector = false
        settings.inspectorMode = "outline"
        settings.appearance = .light
        settings.themeMode = .original
        settings.showSidebar = true
        settings.sidebarWidth = 248
        settings.inspectorWidth = 280
        model.bootstrapSession()

        let heroID = "note-algo-complexity"
        if let quick = model.notes.first(where: { $0.id == "note-quick-today" }) {
            model.openNote(quick.id)
        }
        if let note = model.notes.first(where: { $0.id == heroID }) {
            model.openNote(note.id)
        }

        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "01-workspace-light", size: CGSize(width: 1440, height: 900), directory: directory)

        settings.appearance = .dark
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "02-workspace-dark", size: CGSize(width: 1440, height: 900), directory: directory)

        settings.appearance = .light
        settings.showInspector = true
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "03-inspector", size: CGSize(width: 1440, height: 900), directory: directory)
        settings.showInspector = false

        model.presentationOverride = .reading
        if let note = model.notes.first(where: { $0.id == heroID }) {
            model.openNote(note.id)
        }
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "04-reading", size: CGSize(width: 1440, height: 900), directory: directory)
        model.presentationOverride = nil
        if let note = model.notes.first(where: { $0.id == heroID }) {
            model.openNote(note.id)
        }

        model.toast = nil
        model.presentCommandPalette()
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "05-command-palette", size: CGSize(width: 1440, height: 900), directory: directory)
        model.dismissPalette()

        model.presentQuickSwitch()
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "06-quick-switch", size: CGSize(width: 1440, height: 900), directory: directory)
        model.dismissPalette()

        model.openGraph()
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "07-graph", size: CGSize(width: 1440, height: 900), directory: directory)

        model.openMap("map-ds-system")
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "08-mind-map", size: CGSize(width: 1440, height: 900), directory: directory)

        model.openCanvas("canvas-main")
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "09-canvas", size: CGSize(width: 1440, height: 900), directory: directory)

        model.trashNote("note-quick-today")
        render(TrashSheet(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "10-trash", size: CGSize(width: 760, height: 560), directory: directory)
        model.restoreNote("note-quick-today")
        settings.appearance = .dark
        model.presentCommandPalette()
        render(RootView(model: model, settings: settings)
                .environment(\.lexiSnapshot, true),
               name: "11-palette-dark", size: CGSize(width: 1440, height: 900), directory: directory)
        model.dismissPalette()
        settings.appearance = .light

        renderSettings(model: model, settings: settings, section: .about, name: "12-settings-about", directory: directory)
        renderSettings(model: model, settings: settings, section: .appearance, name: "13-settings-appearance", directory: directory)

        render(WelcomeSheet(model: model, settings: settings)
                .frame(width: 760, height: 480)
                .environment(\.lexiSnapshot, true),
               name: "14-welcome", size: CGSize(width: 760, height: 480), directory: directory)

        let emptyDefaults = UserDefaults(suiteName: "com.lexinote.mac.snapshot.empty") ?? .standard
        let emptySettings = SettingsStore(defaults: emptyDefaults)
        emptySettings.showWelcome = false
        emptySettings.useMaterial = false
        emptySettings.showSidebar = true
        emptySettings.showInspector = true
        emptySettings.showTabStrip = true
        emptySettings.showStatusBar = true
        emptySettings.appearance = .light
        emptySettings.themeMode = .original
        emptySettings.sidebarWidth = 248
        emptySettings.inspectorWidth = 280
        let emptyModel = AppModel(settings: emptySettings, inMemory: true, seedDemo: false)
        emptyModel.bootstrapSession()
        render(RootView(model: emptyModel, settings: emptySettings)
                .environment(\.lexiSnapshot, true),
               name: "15-empty", size: CGSize(width: 1440, height: 900), directory: directory)

        renderSettings(model: emptyModel, settings: emptySettings, section: .interface, name: "16-settings-interface", directory: directory)
        renderSettings(model: emptyModel, settings: emptySettings, section: .editor, name: "17-settings-editor", directory: directory)
        renderSettings(model: emptyModel, settings: emptySettings, section: .data, name: "18-settings-data", directory: directory)
        renderSettings(model: emptyModel, settings: emptySettings, section: .plugins, name: "19-settings-plugins", directory: directory)
        renderSettings(model: emptyModel, settings: emptySettings, section: .shortcuts, name: "20-settings-shortcuts", directory: directory)

        print("[snapshot] wrote screenshots to \(directory.path)")
    }

    private static func renderSettings(model: AppModel,
                                       settings: SettingsStore,
                                       section: SettingsSection,
                                       name: String,
                                       directory: URL) {
        let card = ZStack {
            Color(white: 0.88)
            SettingsView(model: model, settings: settings, initialSection: section)
                .frame(width: 780, height: 560)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
        }
        .environment(\.lexiSnapshot, true)
        render(card, name: name, size: CGSize(width: 860, height: 640), directory: directory)
    }

    private static func render<V: View>(_ view: V, name: String, size: CGSize, directory: URL) {
        let dark = AppEnvironment.settings.appearance == .dark
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrame(NSRect(x: 80, y: 80, width: size.width, height: size.height), display: true)
        window.orderFrontRegardless()
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.28))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            print("[snapshot] failed to allocate bitmap for \(name)")
            window.orderOut(nil)
            return
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("[snapshot] failed to encode \(name)")
            window.orderOut(nil)
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url, options: .atomic)
            print("[snapshot] \(name).png \(Int(size.width))x\(Int(size.height))@2x")
        } catch {
            print("[snapshot] write failed \(name): \(error.localizedDescription)")
        }
        window.orderOut(nil)
        window.contentView = nil
    }
}
