import SwiftUI
import AppKit

// MARK: - Hex color math (port of ArkTS LexiTheme)

enum HexColor {
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        var a = 1.0
        if s.count == 8 {
            // ArkUI uses #AARRGGBB for eight digit colors.
            let alpha = Double(Int(s.prefix(2), radix: 16) ?? 255)
            a = alpha / 255.0
            s = String(s.dropFirst(2))
        }
        guard let r = Int(s.prefix(2), radix: 16),
              let g = Int(s.dropFirst(2).prefix(2), radix: 16),
              let b = Int(s.dropFirst(4).prefix(2), radix: 16) else { return nil }
        return (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0, a)
    }

    static func normalize(_ hex: String) -> String {
        guard let c = components(hex) else { return "#6E44D9" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.r * 255)), Int(round(c.g * 255)), Int(round(c.b * 255)))
    }

    static func mix(_ base: String, _ tint: String, _ amount: Double) -> String {
        guard let a = components(base), let b = components(tint) else { return base }
        let t = max(0, min(1, amount))
        return String(format: "#%02X%02X%02X",
                      Int(round((a.r * (1 - t) + b.r * t) * 255)),
                      Int(round((a.g * (1 - t) + b.g * t) * 255)),
                      Int(round((a.b * (1 - t) + b.b * t) * 255)))
    }

    static func luminance(_ hex: String) -> Double {
        guard let c = components(hex) else { return 0 }
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linear(c.r) * 0.2126 + linear(c.g) * 0.7152 + linear(c.b) * 0.0722
    }

    static func contrast(_ first: String, _ second: String) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func readable(_ hex: String, on background: String, dark: Bool) -> String {
        let target = dark ? "#FFFFFF" : "#000000"
        for step in 0...100 {
            let adjusted = mix(hex, target, Double(step) / 100.0)
            if contrast(adjusted, background) >= 4.5 { return adjusted }
        }
        return target
    }

    static func fitText(_ color: String, surfaces: [String], dark: Bool) -> String {
        let target = dark ? "#FFFFFF" : "#000000"
        for step in 0...100 {
            let adjusted = mix(color, target, Double(step) / 100.0)
            if surfaces.allSatisfy({ contrast(adjusted, $0) >= 4.5 }) { return adjusted }
        }
        return target
    }

    static func opacity(_ hex: String, _ alpha: Double) -> Color {
        guard let c = components(hex) else { return .clear }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: min(1, max(0, alpha * c.a)))
    }
}

extension Color {
    init(hex: String) {
        guard let c = HexColor.components(hex) else {
            self = .clear
            return
        }
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

// MARK: - Palette

struct ThemePalette: Equatable {
    let isDark: Bool
    let background: Color
    let surface: Color
    let softSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let brand: Color
    let brandSoft: Color
    let brandInk: Color
    let inverseText: Color
    let divider: Color
    let success: Color
    let warning: Color
    let error: Color
    let hero: Color
    let workspaceRail: Color
    let workspaceSidebar: Color
    let workspaceTabs: Color
    let workspacePage: Color
    let workspaceInspector: Color
    let workspaceSelection: Color
    let workspaceLine: Color
    let canvasSurface: Color

    // Raw strings are kept for gradients, CSS theme injection, and tint math.
    let backgroundHex: String
    let surfaceHex: String
    let brandHex: String
    let brandInkHex: String
    let textPrimaryHex: String
    let textSecondaryHex: String
    let workspacePageHex: String
    let workspaceInspectorHex: String
    let workspaceLineHex: String

    init(isDark: Bool,
         background: String, surface: String, softSurface: String,
         textPrimary: String, textSecondary: String,
         brand: String, brandSoft: String, brandInk: String, inverseText: String,
         divider: String, success: String, warning: String, error: String, hero: String,
         workspaceRail: String, workspaceSidebar: String, workspaceTabs: String,
         workspacePage: String, workspaceInspector: String, workspaceSelection: String,
         workspaceLine: String, canvasSurface: String) {
        self.isDark = isDark
        self.backgroundHex = background
        self.surfaceHex = surface
        self.brandHex = brand
        self.brandInkHex = brandInk
        self.textPrimaryHex = textPrimary
        self.textSecondaryHex = textSecondary
        self.workspacePageHex = workspacePage
        self.workspaceInspectorHex = workspaceInspector
        self.workspaceLineHex = workspaceLine
        self.background = Color(hex: background)
        self.surface = Color(hex: surface)
        self.softSurface = Color(hex: softSurface)
        self.textPrimary = Color(hex: textPrimary)
        self.textSecondary = Color(hex: textSecondary)
        self.brand = Color(hex: brand)
        self.brandSoft = Color(hex: brandSoft)
        self.brandInk = Color(hex: brandInk)
        self.inverseText = Color(hex: inverseText)
        self.divider = Color(hex: divider)
        self.success = Color(hex: success)
        self.warning = Color(hex: warning)
        self.error = Color(hex: error)
        self.hero = Color(hex: hero)
        self.workspaceRail = Color(hex: workspaceRail)
        self.workspaceSidebar = Color(hex: workspaceSidebar)
        self.workspaceTabs = Color(hex: workspaceTabs)
        self.workspacePage = Color(hex: workspacePage)
        self.workspaceInspector = Color(hex: workspaceInspector)
        self.workspaceSelection = Color(hex: workspaceSelection)
        self.workspaceLine = Color(hex: workspaceLine)
        self.canvasSurface = Color(hex: canvasSurface)
    }

    /// A subtle elevated fill for cards and hover rows.
    var subtleFill: Color { isDark ? workspaceSelection.opacity(0.55) : softSurface.opacity(0.7) }
    var hoverFill: Color { isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.035) }
    var controlFill: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045) }
    var shadow: Color { Color.black.opacity(isDark ? 0.45 : 0.10) }
}

// MARK: - Accent presets

enum AccentPreset: String, CaseIterable, Identifiable {
    case iris, rose, amber, forest, sky, graphite

    var id: String { rawValue }
    var hex: String {
        switch self {
        case .iris: return "#6E44D9"
        case .rose: return "#D94B73"
        case .amber: return "#DC8137"
        case .forest: return "#308F70"
        case .sky: return "#3688CD"
        case .graphite: return "#68738A"
        }
    }
    var label: String {
        switch self {
        case .iris: return "鸢尾紫"
        case .rose: return "玫瑰粉"
        case .amber: return "暖杏橙"
        case .forest: return "森林绿"
        case .sky: return "晴空蓝"
        case .graphite: return "石墨灰"
        }
    }
    var color: Color { Color(hex: hex) }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case original, preset, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "原始主题"
        case .preset: return "预设强调色"
        case .custom: return "自定义"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - Theme engine (faithful port of LexiTheme)

enum ThemeEngine {
    static let defaultAccent = "#6E44D9"

    static func original(dark: Bool) -> ThemePalette {
        if dark {
            return ThemePalette(
                isDark: true,
                background: "#12131B", surface: "#20212D", softSurface: "#2D2F3E",
                textPrimary: "#F5F3FB", textSecondary: "#C6C2D4",
                brand: "#C7B3FF", brandSoft: "#3A3157", brandInk: "#E0D4FF", inverseText: "#20162E",
                divider: "#4B465F", success: "#86CDB5", warning: "#F0B86E", error: "#FF9EAB",
                hero: "#29233D",
                workspaceRail: "#1D1A29", workspaceSidebar: "#242030", workspaceTabs: "#211E2C",
                workspacePage: "#191822", workspaceInspector: "#1E1C29",
                workspaceSelection: "#403355", workspaceLine: "#3B354C",
                canvasSurface: "#181A24")
        }
        return ThemePalette(
            isDark: false,
            background: "#F6F4FB", surface: "#FFFFFF", softSurface: "#EEEAF8",
            textPrimary: "#231B36", textSecondary: "#6E6385",
            brand: "#6E44D9", brandSoft: "#E9E0FF", brandInk: "#4E2B9E", inverseText: "#FFFFFF",
            divider: "#E4DDF2", success: "#348672", warning: "#C9822B", error: "#C44D62",
            hero: "#E9E0FF",
            workspaceRail: "#EAE4F5", workspaceSidebar: "#F4F0FA", workspaceTabs: "#F0EBF8",
            workspacePage: "#FFFFFF", workspaceInspector: "#FCFAFF",
            workspaceSelection: "#E4D8FA", workspaceLine: "#DDD5EA",
            canvasSurface: "#1C162B")
    }

    static func generated(accent rawAccent: String, dark: Bool) -> ThemePalette {
        let tint = rawAccent.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
            ? rawAccent.uppercased() : defaultAccent
        let background = HexColor.mix(dark ? "#111318" : "#F7F8FA", tint, dark ? 0.07 : 0.035)
        let surface = HexColor.mix(dark ? "#202229" : "#FFFFFF", tint, dark ? 0.08 : 0.012)
        let softSurface = HexColor.mix(dark ? "#2B2D35" : "#EEF0F4", tint, dark ? 0.10 : 0.05)
        var textPrimary = HexColor.mix(dark ? "#F5F6FA" : "#1A1D24", tint, dark ? 0.025 : 0.08)
        var textSecondary = HexColor.mix(dark ? "#C6CAD4" : "#535863", tint, 0.10)
        let brandSoft = HexColor.mix(dark ? "#292C34" : "#EDF0F5", tint, dark ? 0.23 : 0.08)
        let workspaceSelection = HexColor.mix(dark ? "#30333B" : "#E2E5EC", tint, dark ? 0.30 : 0.12)
        textPrimary = HexColor.readable(HexColor.readable(textPrimary, on: workspaceSelection, dark: dark), on: softSurface, dark: dark)
        textSecondary = HexColor.readable(HexColor.readable(textSecondary, on: workspaceSelection, dark: dark), on: softSurface, dark: dark)
        let brand = HexColor.readable(HexColor.readable(tint, on: workspaceSelection, dark: dark), on: softSurface, dark: dark)
        let inverse = HexColor.contrast("#FFFFFF", brand) >= 4.5 ? "#FFFFFF" : "#111318"
        let divider = HexColor.mix(dark ? "#41444D" : "#E5E7EC", tint, 0.12)
        let workspaceRail = HexColor.mix(dark ? "#1A1C23" : "#E8EBF0", tint, dark ? 0.12 : 0.07)
        let workspaceSidebar = HexColor.mix(dark ? "#21232B" : "#F4F5F7", tint, dark ? 0.10 : 0.05)
        let workspaceTabs = HexColor.mix(dark ? "#1D1F27" : "#EEF0F4", tint, dark ? 0.10 : 0.06)
        let workspacePage = HexColor.mix(dark ? "#17191F" : "#FFFFFF", tint, dark ? 0.06 : 0.004)
        let workspaceInspector = HexColor.mix(dark ? "#1D1F26" : "#FFFFFF", tint, dark ? 0.08 : 0.025)
        return ThemePalette(
            isDark: dark,
            background: background, surface: surface, softSurface: softSurface,
            textPrimary: textPrimary, textSecondary: textSecondary,
            brand: brand, brandSoft: brandSoft, brandInk: brand, inverseText: inverse,
            divider: divider,
            success: dark ? "#86CDB5" : "#348672", warning: dark ? "#F0B86E" : "#C9822B",
            error: dark ? "#FF9EAB" : "#C44D62", hero: brandSoft,
            workspaceRail: workspaceRail, workspaceSidebar: workspaceSidebar, workspaceTabs: workspaceTabs,
            workspacePage: workspacePage, workspaceInspector: workspaceInspector,
            workspaceSelection: workspaceSelection, workspaceLine: divider,
            canvasSurface: background)
    }

    static func custom(accent rawAccent: String, background customBackground: String,
                       foreground customForeground: String, dark: Bool) -> ThemePalette {
        let accent = rawAccent.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
            ? rawAccent.uppercased() : defaultAccent
        let fallback = generated(accent: accent, dark: dark)
        let background = customBackground.count == 7 ? customBackground.uppercased() : fallback.backgroundHex
        let canvasDark = HexColor.luminance(background) < 0.179
        let foreground = customForeground.count == 7 ? customForeground.uppercased()
            : HexColor.mix(canvasDark ? "#F5F6FA" : "#1A1D24", accent, 0.08)
        let surface = HexColor.mix(background, "#FFFFFF", canvasDark ? 0.07 : 0.65)
        let softSurface = HexColor.mix(background, foreground, 0.055)
        let workspaceRail = HexColor.mix(background, accent, 0.09)
        let workspaceSidebar = HexColor.mix(background, accent, 0.045)
        let workspaceTabs = HexColor.mix(background, accent, 0.065)
        let workspaceInspector = HexColor.mix(background, accent, 0.025)
        let workspaceSelection = HexColor.mix(background, accent, canvasDark ? 0.25 : 0.14)
        let brandSoft = HexColor.mix(background, accent, canvasDark ? 0.20 : 0.10)
        let divider = HexColor.mix(background, foreground, 0.16)
        let surfaces = [background, surface, softSurface, workspaceSelection, workspaceSidebar, workspaceInspector, brandSoft]
        let textPrimary = HexColor.fitText(foreground, surfaces: surfaces, dark: canvasDark)
        let textSecondary = HexColor.fitText(HexColor.mix(foreground, background, 0.25), surfaces: surfaces, dark: canvasDark)
        let brand = HexColor.fitText(accent, surfaces: surfaces, dark: canvasDark)
        let inverse = HexColor.contrast("#FFFFFF", brand) >= 4.5 ? "#FFFFFF" : "#111318"
        return ThemePalette(
            isDark: canvasDark,
            background: background, surface: surface, softSurface: softSurface,
            textPrimary: textPrimary, textSecondary: textSecondary,
            brand: brand, brandSoft: brandSoft, brandInk: brand, inverseText: inverse,
            divider: divider,
            success: canvasDark ? "#86CDB5" : "#348672",
            warning: canvasDark ? "#F0B86E" : "#C9822B",
            error: canvasDark ? "#FF9EAB" : "#C44D62",
            hero: brandSoft,
            workspaceRail: workspaceRail, workspaceSidebar: workspaceSidebar, workspaceTabs: workspaceTabs,
            workspacePage: background, workspaceInspector: workspaceInspector,
            workspaceSelection: workspaceSelection, workspaceLine: divider,
            canvasSurface: background)
    }

    static func resolve(mode: ThemeMode, accent: String, customBackground: String,
                        customForeground: String, dark: Bool) -> ThemePalette {
        switch mode {
        case .original: return original(dark: dark)
        case .preset: return generated(accent: accent, dark: dark)
        case .custom: return custom(accent: accent, background: customBackground, foreground: customForeground, dark: dark)
        }
    }
}

// MARK: - Environment palette

private struct LexiPaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = ThemeEngine.original(dark: false)
}

extension EnvironmentValues {
    var lexiPalette: ThemePalette {
        get { self[LexiPaletteKey.self] }
        set { self[LexiPaletteKey.self] = newValue }
    }
}

// MARK: - Shared metrics

enum Metrics {
    static let titlebarHeight: CGFloat = 50
    static let railWidth: CGFloat = 56
    static let sidebarMin: CGFloat = 212
    static let sidebarMax: CGFloat = 360
    static let inspectorMin: CGFloat = 240
    static let inspectorMax: CGFloat = 400
    static let editorToolbarHeight: CGFloat = 48
    static let editorStatusHeight: CGFloat = 40
    static let contentMaxWidth: CGFloat = 760
    static let corner: CGFloat = 8
}

// MARK: - Note color tags (mind map / canvas)

enum NoteColorTag: String, CaseIterable, Codable, Identifiable {
    case purple, indigo, teal, amber, rose, green, gray

    var id: String { rawValue }
    var label: String {
        switch self {
        case .purple: return "鸢尾紫"
        case .indigo: return "靛蓝"
        case .teal: return "青绿"
        case .amber: return "琥珀"
        case .rose: return "玫瑰"
        case .green: return "森绿"
        case .gray: return "石墨"
        }
    }
    var hex: String {
        switch self {
        case .purple: return "#6E44D9"
        case .indigo: return "#4C6FFF"
        case .teal: return "#2F9E8F"
        case .amber: return "#D98E2B"
        case .rose: return "#D94B73"
        case .green: return "#3E8E5A"
        case .gray: return "#6B7280"
        }
    }
    var color: Color { Color(hex: hex) }
}
