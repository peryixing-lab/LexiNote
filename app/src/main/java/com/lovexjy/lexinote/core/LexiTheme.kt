package com.lovexjy.lexinote.core

import androidx.compose.ui.graphics.Color
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

class LexiThemePreset(
    val id: String = "purple",
    val name: String = "鸢尾紫",
    val lightBrand: String = "#6E44D9",
    val darkBrand: String = "#C7B3FF",
    val lightBackground: String = "#F6F4FB",
    val darkBackground: String = "#12131B",
    val lightForeground: String = "#231B36",
    val darkForeground: String = "#F5F3FB"
)

data class LexiThemePalette(
    var id: String = "original",
    var dark: Boolean = false,
    var page_bg: String = "#F6F4FB",
    var page_bg_end: String = "#EEEAF8",
    var surface: String = "#FFFFFF",
    var elevated_surface: String = "#FCFAFF",
    var soft_surface: String = "#EEEAF8",
    var dock_surface: String = "#F4FFFFFF",
    var dock_border: String = "#E4DDF2",
    var glass_fill: String = "#CCFFFFFF",
    var glass_stroke: String = "#E3DBF8",
    var brand: String = "#6E44D9",
    var brand_ink: String = "#4E2B9E",
    var brand_soft: String = "#E9E0FF",
    var brand_glow: String = "#D6C5FF",
    var text_primary: String = "#231B36",
    var text_secondary: String = "#6E6385",
    var inverse_text: String = "#FFFFFF",
    var divider: String = "#E4DDF2",
    var node_indigo: String = "#4F46E5",
    var node_indigo_soft: String = "#E4E6FF",
    var node_teal: String = "#0D9488",
    var node_teal_soft: String = "#DCFCE7",
    var node_amber: String = "#D97706",
    var node_amber_soft: String = "#FEF3C7",
    var node_rose: String = "#E11D48",
    var node_rose_soft: String = "#FFE4E6",
    var danger: String = "#C44D62",
    var danger_soft: String = "#FEE2E2",
    var success: String = "#348672",
    var canvas_grid_bg: String = "#F4F0FF",
    var canvas_grid_dot: String = "#C7BBE6"
)

fun String.toComposeColor(): Color {
    val clean = trim().removePrefix("#")
    return try {
        when (clean.length) {
            6 -> Color(("FF$clean").toLong(16))
            8 -> Color(clean.toLong(16))
            else -> Color(0xFF6E44D9)
        }
    } catch (_: Exception) {
        Color(0xFF6E44D9)
    }
}

/**
 * Computes full surface, border, text and canvas palettes from a single brand color.
 * Exact 1:1 port of LexiTheme.ets.
 */
object LexiTheme {
    val PRESETS: List<LexiThemePreset> = listOf(
        LexiThemePreset("purple", "鸢尾紫", "#6E44D9", "#B69CFF", "#F6F3FF", "#120F1B", "#1E1830", "#F5F3FB"),
        LexiThemePreset("rose", "玫瑰粉", "#D63B75", "#FF9BC0", "#FFF4F8", "#191015", "#2E1621", "#FBF2F6"),
        LexiThemePreset("amber", "暖杏橙", "#C86A1E", "#FFB978", "#FFF7F0", "#19130E", "#2C1D12", "#FBF5EF"),
        LexiThemePreset("emerald", "森林绿", "#1F8A65", "#76E0B8", "#F1FAF6", "#0E1714", "#142923", "#EFFAF5"),
        LexiThemePreset("sky", "晴空蓝", "#2563EB", "#93C5FD", "#F2F7FF", "#0E1420", "#162133", "#F1F6FE"),
        LexiThemePreset("slate", "石墨灰", "#475569", "#CBD5E1", "#F5F7FA", "#111418", "#1B222C", "#F3F6FA")
    )

    fun preset(id: String): LexiThemePreset {
        return PRESETS.find { it.id == id } ?: PRESETS[0]
    }

    fun validHex(raw: String): Boolean {
        return Regex("^#?[0-9A-Fa-f]{6}$").matches(raw.trim())
    }

    fun normalizeHex(raw: String, fallback: String): String {
        val clean = raw.trim().removePrefix("#")
        return if (Regex("^[0-9A-Fa-f]{6}$").matches(clean)) {
            "#${clean.uppercase()}"
        } else {
            fallback
        }
    }

    private fun channel(hex: String, offset: Int): Int {
        return hex.substring(offset, offset + 2).toInt(16)
    }

    private fun hexByte(value: Double): String {
        val clamped = max(0, min(255, value.roundToInt()))
        return clamped.toString(16).uppercase().padStart(2, '0')
    }

    fun mix(a: String, b: String, weightB: Double): String {
        val first = normalizeHex(a, "#6E44D9")
        val second = normalizeHex(b, "#FFFFFF")
        val w = max(0.0, min(1.0, weightB))
        val r = channel(first, 1) * (1.0 - w) + channel(second, 1) * w
        val g = channel(first, 3) * (1.0 - w) + channel(second, 3) * w
        val blue = channel(first, 5) * (1.0 - w) + channel(second, 5) * w
        return "#${hexByte(r)}${hexByte(g)}${hexByte(blue)}"
    }

    private fun withAlpha(alphaHex: String, rgbHex: String): String {
        return "#$alphaHex${normalizeHex(rgbHex, "#FFFFFF").substring(1)}"
    }

    fun luminance(hex: String): Double {
        val color = normalizeHex(hex, "#6E44D9")
        val linear = { offset: Int ->
            val s = channel(color, offset) / 255.0
            if (s <= 0.03928) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(1) + 0.7152 * linear(3) + 0.0722 * linear(5)
    }

    fun contrast(a: String, b: String): Double {
        val l1 = luminance(a)
        val l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    fun readable(foreground: String, background: String, minRatio: Double = 3.2): Boolean {
        return contrast(foreground, background) >= minRatio
    }

    fun fitText(preferred: String, background: String, minRatio: Double = 4.5): String {
        val candidate = normalizeHex(preferred, "#1E1830")
        if (readable(candidate, background, minRatio)) {
            return candidate
        }
        val target = if (luminance(background) < 0.42) "#FFFFFF" else "#121018"
        for (step in 1..10) {
            val mixed = mix(candidate, target, step / 10.0)
            if (readable(mixed, background, minRatio)) {
                return mixed
            }
        }
        return target
    }

    fun originalPalette(dark: Boolean): LexiThemePalette {
        val p = LexiThemePalette(id = "original", dark = dark)
        if (!dark) {
            return p
        }
        p.page_bg = "#12131B"
        p.page_bg_end = "#191822"
        p.surface = "#20212D"
        p.elevated_surface = "#242030"
        p.soft_surface = "#2D2F3E"
        p.dock_surface = "#EE20212D"
        p.dock_border = "#3B354C"
        p.glass_fill = "#CC211E2C"
        p.glass_stroke = "#4B465F"
        p.brand = "#C7B3FF"
        p.brand_ink = "#E0D4FF"
        p.brand_soft = "#3A3157"
        p.brand_glow = "#4B396E"
        p.text_primary = "#F5F3FB"
        p.text_secondary = "#C6C2D4"
        p.inverse_text = "#20162E"
        p.divider = "#4B465F"
        p.node_indigo = "#A5B4FC"
        p.node_indigo_soft = "#272A52"
        p.node_teal = "#5EEAD4"
        p.node_teal_soft = "#183B3A"
        p.node_amber = "#FCD34D"
        p.node_amber_soft = "#3F2E18"
        p.node_rose = "#FDA4AF"
        p.node_rose_soft = "#431D2B"
        p.danger = "#FF9EAB"
        p.danger_soft = "#3F1D24"
        p.success = "#86CDB5"
        p.canvas_grid_bg = "#161222"
        p.canvas_grid_dot = "#3A3152"
        return p
    }

    fun palette(
        themeId: String,
        customHex: String,
        dark: Boolean,
        customBackground: String = "",
        customForeground: String = ""
    ): LexiThemePalette {
        if (themeId == "original") {
            return originalPalette(dark)
        }
        val preset = preset(themeId)
        val rawBrand = if (themeId == "custom") {
            normalizeHex(customHex, if (dark) preset.darkBrand else preset.lightBrand)
        } else {
            if (dark) preset.darkBrand else preset.lightBrand
        }
        val baseBg = if (themeId == "custom" && validHex(customBackground)) {
            normalizeHex(customBackground, if (dark) preset.darkBackground else preset.lightBackground)
        } else {
            if (dark) preset.darkBackground else preset.lightBackground
        }
        val darkSurface = luminance(baseBg) < 0.42
        val brand = if (themeId == "custom" && darkSurface && luminance(rawBrand) < 0.28) {
            mix(rawBrand, "#FFFFFF", 0.44)
        } else if (themeId == "custom" && !darkSurface && luminance(rawBrand) > 0.58) {
            mix(rawBrand, "#161124", 0.36)
        } else {
            rawBrand
        }
        val p = originalPalette(darkSurface)
        p.id = themeId
        p.dark = darkSurface
        val rawFg = if (themeId == "custom" && validHex(customForeground)) {
            normalizeHex(customForeground, if (darkSurface) "#F5F3FB" else preset.lightForeground)
        } else {
            if (darkSurface) preset.darkForeground else preset.lightForeground
        }
        val textPrimary = fitText(rawFg, baseBg, 4.5)
        if (darkSurface) {
            p.page_bg = mix(baseBg, brand, 0.05)
            p.page_bg_end = mix(baseBg, brand, 0.11)
            p.surface = mix(baseBg, "#FFFFFF", 0.05)
            p.elevated_surface = mix(p.surface, brand, 0.08)
            p.soft_surface = mix(p.surface, brand, 0.14)
            p.dock_surface = withAlpha("E6", mix(p.surface, brand, 0.06))
            p.dock_border = mix(p.surface, brand, 0.24)
            p.glass_fill = withAlpha("CC", p.elevated_surface)
            p.glass_stroke = mix(p.surface, brand, 0.28)
            p.brand = fitText(brand, p.surface, 3.2)
            p.brand_ink = fitText(mix(p.brand, "#FFFFFF", 0.35), p.soft_surface, 4.2)
            p.brand_soft = mix(p.surface, p.brand, 0.22)
            p.brand_glow = mix(p.surface, p.brand, 0.38)
            p.text_primary = fitText(textPrimary, p.surface, 4.5)
            p.text_secondary = fitText(mix(p.text_primary, p.surface, 0.32), p.surface, 3.2)
            p.inverse_text = fitText("#161124", p.brand, 4.5)
            p.divider = mix(p.surface, p.text_primary, 0.14)
            p.canvas_grid_bg = mix(baseBg, p.brand, 0.07)
            p.canvas_grid_dot = mix(p.surface, p.brand, 0.28)
        } else {
            val cardSurface = if (luminance(baseBg) > 0.9) "#FFFFFF" else mix(baseBg, "#FFFFFF", 0.45)
            p.page_bg = mix(baseBg, brand, 0.04)
            p.page_bg_end = mix(baseBg, brand, 0.10)
            p.surface = cardSurface
            p.elevated_surface = mix(cardSurface, brand, 0.03)
            p.soft_surface = mix(baseBg, brand, 0.10)
            p.dock_surface = withAlpha("E6", cardSurface)
            p.dock_border = mix(cardSurface, brand, 0.22)
            p.glass_fill = withAlpha("CC", cardSurface)
            p.glass_stroke = mix(cardSurface, brand, 0.20)
            p.brand = fitText(brand, cardSurface, 3.2)
            p.brand_ink = fitText(mix(p.brand, "#141022", 0.30), p.brand_soft, 4.2)
            p.brand_soft = mix(cardSurface, p.brand, 0.15)
            p.brand_glow = mix(cardSurface, p.brand, 0.28)
            p.text_primary = fitText(textPrimary, cardSurface, 4.5)
            p.text_secondary = fitText(mix(p.text_primary, cardSurface, 0.38), cardSurface, 3.2)
            p.inverse_text = fitText("#FFFFFF", p.brand, 4.5)
            p.divider = mix(cardSurface, p.text_primary, 0.13)
            p.canvas_grid_bg = mix(baseBg, p.brand, 0.06)
            p.canvas_grid_dot = mix(cardSurface, p.brand, 0.28)
        }
        return p
    }

    fun resolvePalette(
        themeId: String,
        customHex: String,
        customBackground: String,
        customForeground: String,
        appearanceMode: String,
        systemDark: Boolean
    ): LexiThemePalette {
        val dark = if (appearanceMode == "dark") {
            true
        } else if (appearanceMode == "light") {
            false
        } else {
            systemDark
        }
        return palette(themeId, customHex, dark, customBackground, customForeground)
    }

    fun resolveAccent(customAccent: String, p: LexiThemePalette): String {
        val base = if (validHex(customAccent)) normalizeHex(customAccent, p.brand) else p.brand
        return fitText(base, p.surface, 3.0)
    }
}
