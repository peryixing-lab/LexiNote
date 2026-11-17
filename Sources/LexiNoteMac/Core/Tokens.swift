import SwiftUI
import AppKit

enum LexiTokens {
    // Spacing scale (4pt base + 2pt hairline)
    static let space1: CGFloat = 2
    static let space2: CGFloat = 4
    static let space3: CGFloat = 8
    static let space4: CGFloat = 12
    static let space5: CGFloat = 16
    static let space6: CGFloat = 20
    static let space7: CGFloat = 24
    static let space8: CGFloat = 32
    static let space9: CGFloat = 40
    static let space10: CGFloat = 48

    // Radii
    static let radiusXS: CGFloat = 6
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusFull: CGFloat = 999

    // Typography sizes
    static let typeDisplay: CGFloat = 30
    static let typeH1: CGFloat = 24
    static let typeH2: CGFloat = 20
    static let typeH3: CGFloat = 17
    static let typeBody: CGFloat = 16
    static let typeUI: CGFloat = 13
    static let typeCaption: CGFloat = 12
    static let typeMicro: CGFloat = 11

    // Elevations
    static func applyElevation1(_ view: some View, palette: ThemePalette) -> some View {
        view.shadow(color: Color.black.opacity(palette.isDark ? 0.18 : 0.06),
                    radius: palette.isDark ? 4 : 3, y: palette.isDark ? 2 : 1)
    }

    static func applyElevation2(_ view: some View, palette: ThemePalette) -> some View {
        view.shadow(color: Color.black.opacity(palette.isDark ? 0.32 : 0.12),
                    radius: palette.isDark ? 12 : 10, y: palette.isDark ? 6 : 4)
    }

    static func applyElevation3(_ view: some View, palette: ThemePalette) -> some View {
        view.shadow(color: Color.black.opacity(palette.isDark ? 0.48 : 0.18),
                    radius: palette.isDark ? 28 : 24, y: palette.isDark ? 14 : 12)
    }
}

enum LexiMotion {
    static let durMicro: Double = 0.10
    static let durFast: Double = 0.16
    static let durBase: Double = 0.22
    static let durSlow: Double = 0.30
    static let durPalette: Double = 0.12
    static let exitFactor: Double = 0.7

    static let pressScale: CGFloat = 0.97
    static let popoverScale: CGFloat = 0.96
    static let modalScale: CGFloat = 0.96

    static let easeOutMicro: Animation = .timingCurve(0.23, 1.0, 0.32, 1.0, duration: durMicro)
    static let easeOutFast: Animation = .timingCurve(0.23, 1.0, 0.32, 1.0, duration: durFast)
    static let easeInOutBase: Animation = .timingCurve(0.65, 0.0, 0.35, 1.0, duration: durBase)
    static let easeDrawer: Animation = .timingCurve(0.32, 0.72, 0.0, 1.0, duration: durSlow)
    static let springCurve: Animation = .spring(response: 0.35, dampingFraction: 0.86)
    static let paletteInCurve: Animation = .timingCurve(0.23, 1.0, 0.32, 1.0, duration: durPalette)
    static let reducedFade: Animation = .linear(duration: 0.12)

    @MainActor
    static func isReduced(_ settings: SettingsStore?) -> Bool {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return true
        }
        guard let settings else { return false }
        return settings.reduceMotion || !settings.animateAppearance
    }

    @MainActor
    static func fast(_ settings: SettingsStore?) -> Animation {
        isReduced(settings) ? reducedFade : easeOutFast
    }

    @MainActor
    static func micro(_ settings: SettingsStore?) -> Animation {
        isReduced(settings) ? reducedFade : easeOutMicro
    }

    @MainActor
    static func base(_ settings: SettingsStore?) -> Animation {
        isReduced(settings) ? reducedFade : easeInOutBase
    }

    @MainActor
    static func drawer(_ settings: SettingsStore?) -> Animation {
        isReduced(settings) ? reducedFade : easeDrawer
    }

    @MainActor
    static func sheet(_ settings: SettingsStore?, isPresented: Bool) -> Animation {
        if isReduced(settings) { return reducedFade }
        return isPresented ? easeDrawer
            : .timingCurve(0.4, 0, 1, 1, duration: durBase)
    }

    static func sheetTransition(reduced: Bool, distance: CGFloat) -> AnyTransition {
        reduced ? .opacity : .offset(y: distance)
    }

    @MainActor
    static func paletteIn(_ settings: SettingsStore?) -> Animation {
        isReduced(settings) ? reducedFade : paletteInCurve
    }

    @MainActor
    static func perform(_ settings: SettingsStore?, _ animation: Animation, _ action: () -> Void) {
        if isReduced(settings) {
            withAnimation(reducedFade, action)
        } else {
            withAnimation(animation, action)
        }
    }

    static func modalTransition(reduced: Bool) -> AnyTransition {
        if reduced {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: modalScale)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }

    static func paletteTransition(reduced: Bool) -> AnyTransition {
        if reduced {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: popoverScale)),
            removal: .identity
        )
    }
}

struct LexiPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var scale: CGFloat = LexiMotion.pressScale
    var opacityOnPress: Double = 0.94

    func makeBody(configuration: Configuration) -> some View {
        let reduced = systemReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? scale : 1.0)
            .opacity(configuration.isPressed ? opacityOnPress : 1.0)
            .animation(reduced ? nil : LexiMotion.easeOutMicro, value: configuration.isPressed)
    }
}
