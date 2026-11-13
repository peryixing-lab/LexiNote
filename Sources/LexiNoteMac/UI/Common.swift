import SwiftUI
import AppKit

// MARK: - Environment

private struct LexiSnapshotKey: EnvironmentKey {
    static let defaultValue: Bool = false
}
extension EnvironmentValues {
    var lexiSnapshot: Bool {
        get { self[LexiSnapshotKey.self] }
        set { self[LexiSnapshotKey.self] = newValue }
    }
}

// MARK: - Window chrome

struct WindowChrome: NSViewRepresentable {
    var appearance: AppearanceMode = .system
    var pageColor: Color = Color(white: 0.98)
    var onWindowChange: ((NSWindow?) -> Void)? = nil
    var onMetricsChange: ((Bool, CGFloat) -> Void)? = nil

    static var defaultTrafficLightsTrailing: CGFloat {
        if #available(macOS 26.0, *) { return 78 }
        return 68
    }

    final class ChromeView: NSView {
        var appearanceMode: AppearanceMode = .system
        var pageColor: Color = Color(white: 0.98)
        var onWindowChange: ((NSWindow?) -> Void)?
        var onMetricsChange: ((Bool, CGFloat) -> Void)?

        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var nativePitch: CGFloat?
        private var scheduled = false
        private var lastFullScreen: Bool?
        private var lastTrailing: CGFloat = -1

        deinit {
            teardownObservers()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                teardownObservers()
                observedWindow = nil
                onWindowChange?(nil)
                return
            }
            if observedWindow !== window {
                teardownObservers()
                observedWindow = window
                nativePitch = nil
                configureWindow(window)
                installObservers(for: window)
                onWindowChange?(window)
            }
            applyWindowAppearance(appearanceMode, pageColor: pageColor)
            scheduleTrafficLightLayout()
        }

        func applyWindowAppearance(_ mode: AppearanceMode, pageColor: Color) {
            self.appearanceMode = mode
            self.pageColor = pageColor
            guard let window else { return }
            let target: NSAppearance?
            switch mode {
            case .system: target = nil
            case .light: target = NSAppearance(named: .aqua)
            case .dark: target = NSAppearance(named: .darkAqua)
            }
            if window.appearance?.name != target?.name {
                window.appearance = target
            }
            window.backgroundColor = NSColor(pageColor)
        }

        private func configureWindow(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.minSize = NSSize(width: 1120, height: 720)
            applyWindowAppearance(appearanceMode, pageColor: pageColor)
        }

        private func teardownObservers() {
            let center = NotificationCenter.default
            for token in observers {
                center.removeObserver(token)
            }
            observers.removeAll()
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            let windowNotifications: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didUpdateNotification
            ]
            for name in windowNotifications {
                let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.applyTrafficLightLayout()
                }
                observers.append(token)
            }

            if let close = window.standardWindowButton(.closeButton),
               let mini = window.standardWindowButton(.miniaturizeButton),
               let zoom = window.standardWindowButton(.zoomButton) {
                let pitch = mini.frame.minX - close.frame.minX
                if pitch > 0 {
                    nativePitch = pitch
                }
                var observedViews: [NSView] = [close, mini, zoom]
                if let container = close.superview?.superview {
                    observedViews.append(container)
                }
                for view in observedViews {
                    view.postsFrameChangedNotifications = true
                    let token = center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                        self?.scheduleTrafficLightLayout()
                    }
                    observers.append(token)
                }
            }
        }

        private func scheduleTrafficLightLayout() {
            applyTrafficLightLayout()
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.applyTrafficLightLayout()
            }
        }

        private func applyTrafficLightLayout() {
            guard let window else { return }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if isFullScreen {
                notifyMetricsIfNeeded(fullScreen: true, trailing: 0)
                return
            }
            guard let close = window.standardWindowButton(.closeButton),
                  let mini = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let titlebarView = close.superview,
                  let containerView = titlebarView.superview,
                  let themeFrame = containerView.superview else { return }

            if nativePitch == nil {
                let pitch = mini.frame.minX - close.frame.minX
                if pitch > 0 {
                    nativePitch = pitch
                }
            }

            let targetHeight = Metrics.titlebarHeight
            let targetContainer = NSRect(
                x: 0,
                y: themeFrame.bounds.height - targetHeight,
                width: themeFrame.bounds.width,
                height: targetHeight
            )
            if containerView.frame != targetContainer {
                containerView.frame = targetContainer
            }

            let targetTitlebar = NSRect(x: 0, y: 0, width: containerView.bounds.width, height: targetHeight)
            if titlebarView.frame != targetTitlebar {
                titlebarView.frame = targetTitlebar
            }

            for subview in titlebarView.subviews {
                guard type(of: subview) == NSView.self else { continue }
                if subview.frame != targetTitlebar {
                    subview.frame = targetTitlebar
                }
            }

            let leftInset: CGFloat = if #available(macOS 26.0, *) { 18 } else { 16 }
            let defaultPitch: CGFloat = if #available(macOS 26.0, *) { 23 } else { 20 }
            let pitch = nativePitch ?? defaultPitch
            let buttons = [close, mini, zoom]

            for (index, button) in buttons.enumerated() {
                let y = round((targetHeight - button.frame.height) / 2)
                let origin = NSPoint(x: leftInset + CGFloat(index) * pitch, y: y)
                if button.frame.origin != origin {
                    button.setFrameOrigin(origin)
                }
            }

            notifyMetricsIfNeeded(fullScreen: false, trailing: zoom.frame.maxX)
        }

        private func notifyMetricsIfNeeded(fullScreen: Bool, trailing: CGFloat) {
            if lastFullScreen == fullScreen && abs(lastTrailing - trailing) < 0.5 {
                return
            }
            lastFullScreen = fullScreen
            lastTrailing = trailing
            let callback = onMetricsChange
            DispatchQueue.main.async {
                callback?(fullScreen, trailing)
            }
        }
    }

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView(frame: .zero)
        view.appearanceMode = appearance
        view.pageColor = pageColor
        view.onWindowChange = onWindowChange
        view.onMetricsChange = onMetricsChange
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.onMetricsChange = onMetricsChange
        nsView.applyWindowAppearance(appearance, pageColor: pageColor)
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView(frame: .zero) }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = emphasized ? .active : .followsWindowActiveState
        view.isEmphasized = emphasized
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = emphasized ? .active : .followsWindowActiveState
    }
}

// MARK: - Brand mark

struct LexiLogoMark: View {
    var size: CGFloat = 26
    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024.0
            let background = Path(roundedRect: CGRect(origin: .zero, size: canvasSize),
                                  cornerRadius: 240 * scale)
            context.fill(background, with: .color(Color(hex: "#E9E0FF")))

            var page = Path()
            page.move(to: CGPoint(x: 286 * scale, y: 286 * scale))
            page.addCurve(to: CGPoint(x: 350 * scale, y: 222 * scale),
                          control1: CGPoint(x: 286 * scale, y: 250 * scale),
                          control2: CGPoint(x: 315 * scale, y: 222 * scale))
            page.addLine(to: CGPoint(x: 574 * scale, y: 222 * scale))
            page.addLine(to: CGPoint(x: 714 * scale, y: 362 * scale))
            page.addLine(to: CGPoint(x: 714 * scale, y: 738 * scale))
            page.addCurve(to: CGPoint(x: 650 * scale, y: 802 * scale),
                          control1: CGPoint(x: 714 * scale, y: 774 * scale),
                          control2: CGPoint(x: 685 * scale, y: 802 * scale))
            page.addLine(to: CGPoint(x: 350 * scale, y: 802 * scale))
            page.addCurve(to: CGPoint(x: 286 * scale, y: 738 * scale),
                          control1: CGPoint(x: 315 * scale, y: 802 * scale),
                          control2: CGPoint(x: 286 * scale, y: 774 * scale))
            page.closeSubpath()
            context.fill(page, with: .color(Color(hex: "#6E44D9")))

            var fold = Path()
            fold.move(to: CGPoint(x: 574 * scale, y: 222 * scale))
            fold.addLine(to: CGPoint(x: 574 * scale, y: 330 * scale))
            fold.addCurve(to: CGPoint(x: 606 * scale, y: 362 * scale),
                          control1: CGPoint(x: 574 * scale, y: 348 * scale),
                          control2: CGPoint(x: 588 * scale, y: 362 * scale))
            fold.addLine(to: CGPoint(x: 714 * scale, y: 362 * scale))
            fold.closeSubpath()
            context.fill(fold, with: .color(Color(hex: "#B69CFF")))

            var lines = Path()
            lines.move(to: CGPoint(x: 388 * scale, y: 458 * scale))
            lines.addLine(to: CGPoint(x: 608 * scale, y: 458 * scale))
            lines.move(to: CGPoint(x: 388 * scale, y: 550 * scale))
            lines.addLine(to: CGPoint(x: 538 * scale, y: 550 * scale))
            context.stroke(lines, with: .color(Color(hex: "#E9E0FF")),
                           style: StrokeStyle(lineWidth: 38 * scale, lineCap: .round))

            for index in 0..<2 {
                let center = CGPoint(x: CGFloat(388 + index * 220) * scale, y: 668 * scale)
                let dot = Path(ellipseIn: CGRect(x: center.x - 24 * scale, y: center.y - 24 * scale,
                                                 width: 48 * scale, height: 48 * scale))
                context.fill(dot, with: .color(.white))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

struct LexiIconButton: View {
    @Environment(\.lexiPalette) private var palette
    let symbol: String
    var size: CGFloat = 15
    var frame: CGFloat = 30
    var active: Bool = false
    var tint: Color? = nil
    var help: String? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? palette.brandInk : (tint ?? palette.textSecondary))
                .frame(width: frame, height: frame)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? palette.workspaceSelection : (hovering ? palette.hoverFill : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
    }
}

struct LexiToolButton: View {
    @Environment(\.lexiPalette) private var palette
    let title: String
    var symbol: String? = nil
    var active: Bool = false
    var compact: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                }
                Text(title).font(.system(size: 12, weight: active ? .medium : .regular))
            }
            .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
            .padding(.horizontal, compact ? 8 : 11)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? palette.workspaceSelection : (hovering ? palette.hoverFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct LexiPrimaryButton: View {
    @Environment(\.lexiPalette) private var palette
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(palette.inverseText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.brand.opacity(hovering ? 0.88 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Search field

struct LexiSearchField: View {
    @Environment(\.lexiPalette) private var palette
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .focused($focused)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.workspacePage)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(focused ? palette.brand.opacity(0.55) : palette.workspaceLine.opacity(0.7), lineWidth: 1)
                )
        )
        .onTapGesture { focused = true }
    }
}

// MARK: - Segmented control

struct LexiSegment<Value: Hashable>: View {
    @Environment(\.lexiPalette) private var palette
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: compact ? 11 : 12, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                        .padding(.horizontal, compact ? 9 : 12)
                        .frame(height: compact ? 24 : 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(active ? palette.workspacePage : Color.clear)
                                .shadow(color: active ? palette.shadow.opacity(0.35) : .clear, radius: 1.5, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.controlFill)
        )
    }
}

// MARK: - Small pieces

struct SectionLabel: View {
    @Environment(\.lexiPalette) private var palette
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary.opacity(0.9))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 10)).foregroundStyle(palette.textSecondary.opacity(0.8))
            }
        }
    }
}

struct TagChip: View {
    @Environment(\.lexiPalette) private var palette
    let text: String
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(text)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.brandInk)
            if removable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(palette.brandInk.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule().fill(palette.brandSoft.opacity(palette.isDark ? 0.8 : 1))
        )
    }
}

struct LexiDivider: View {
    @Environment(\.lexiPalette) private var palette
    var vertical: Bool = false
    var body: some View {
        Rectangle()
            .fill(palette.workspaceLine)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

struct KeyboardHint: View {
    @Environment(\.lexiPalette) private var palette
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.controlFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(palette.workspaceLine.opacity(0.8), lineWidth: 0.6)
                    )
            )
    }
}

struct EmptyStatePanel: View {
    @Environment(\.lexiPalette) private var palette
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.brand.opacity(0.55))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ToastView: View {
    @Environment(\.lexiPalette) private var palette
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.brandInk)
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            Capsule()
                .fill(palette.surface.opacity(0.78))
                .shadow(color: palette.shadow, radius: 14, y: 6)
                .overlay(Capsule().stroke(palette.workspaceLine.opacity(0.8), lineWidth: 1))
        )
        .background {
            if #available(macOS 26.0, *) {
                Rectangle().fill(Color.clear).glassEffect(.regular, in: .capsule)
            }
        }
    }
}

// MARK: - Resize handle

struct ResizeHandle: View {
    @Environment(\.lexiPalette) private var palette
    let onDrag: (CGFloat) -> Void
    var onEnd: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(hovering ? palette.brand.opacity(0.8) : palette.workspaceLine)
                .frame(width: hovering ? 2 : 1)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in onDrag(value.translation.width) }
                .onEnded { _ in onEnd() }
        )
    }
}

// MARK: - Utility

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

extension View {
    func hoverPointer(_ cursor: NSCursor = .pointingHand) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }

    func panelShadow(_ palette: ThemePalette, radius: CGFloat = 18) -> some View {
        shadow(color: palette.shadow, radius: radius, x: 0, y: 8)
    }
}

// MARK: - Liquid Glass

/// Apple's Liquid Glass on macOS 26+, with a system material fallback on older systems.
struct LiquidGlassLayer: View {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    var interactive: Bool = false
    var fallback: Material = .ultraThinMaterial

    var body: some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = {
                var value = Glass.regular
                if let tint { value = value.tint(tint) }
                if interactive { value = value.interactive() }
                return value
            }()
            Rectangle()
                .fill(Color.clear)
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fallback)
        }
    }
}
