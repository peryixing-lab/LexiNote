package com.lovexjy.lexinote.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.lovexjy.lexinote.R
import com.lovexjy.lexinote.core.LexiThemePalette
import com.lovexjy.lexinote.core.toComposeColor

@Composable
fun LexiLogo(
    size: Dp = 28.dp,
    modifier: Modifier = Modifier
) {
    Image(
        painter = painterResource(id = R.drawable.lexi_logo),
        contentDescription = "LexiNote Logo",
        modifier = modifier.size(size)
    )
}

@Composable
fun LexiIcon(
    name: String,
    size: Dp = 18.dp,
    muted: Boolean = false,
    tint: Color? = null,
    palette: LexiThemePalette? = null,
    modifier: Modifier = Modifier
) {
    val resolvedColor = tint ?: when {
        palette != null -> if (muted) palette.text_secondary.toComposeColor() else palette.brand.toComposeColor()
        muted -> Color(0xFF6E6385)
        else -> Color(0xFF6E44D9)
    }

    val normalizedName = remember(name) { name.trim().lowercase() }

    Canvas(modifier = modifier.size(size)) {
        val scaleFactor = this.size.minDimension / 24f
        val strokeWidth = if (normalizedName.startsWith("sidebar-")) 1.6f else 1.8f
        val stroke = Stroke(
            width = strokeWidth,
            cap = StrokeCap.Round,
            join = StrokeJoin.Round
        )
        scale(scaleX = scaleFactor, scaleY = scaleFactor, pivot = Offset.Zero) {
            drawLexiIcon(normalizedName, resolvedColor, stroke)
        }
    }
}

private fun DrawScope.drawSvgPath(pathData: String, color: Color, stroke: Stroke) {
    val path = PathParser().parsePathString(pathData).toPath()
    drawPath(path = path, color = color, style = stroke)
}

private fun DrawScope.drawSvgRect(
    x: Float,
    y: Float,
    w: Float,
    h: Float,
    rx: Float,
    color: Color,
    stroke: Stroke
) {
    drawRoundRect(
        color = color,
        topLeft = Offset(x, y),
        size = Size(w, h),
        cornerRadius = CornerRadius(rx, rx),
        style = stroke
    )
}

private fun DrawScope.drawSvgCircle(
    cx: Float,
    cy: Float,
    r: Float,
    color: Color,
    stroke: Stroke
) {
    drawCircle(
        color = color,
        radius = r,
        center = Offset(cx, cy),
        style = stroke
    )
}

private fun DrawScope.drawLexiIcon(name: String, color: Color, stroke: Stroke) {
    when (name) {
        "back" -> {
            drawSvgPath("m14 5-7 7 7 7", color, stroke)
        }
        "chevron" -> {
            drawSvgPath("m9 6 6 6-6 6", color, stroke)
        }
        "plus" -> {
            drawSvgPath("M12 5v14M5 12h14", color, stroke)
        }
        "search", "sidebar-search" -> {
            drawSvgCircle(10.5f, 10.5f, 6.5f, color, stroke)
            drawSvgPath("m16 16 5 5", color, stroke)
        }
        "dock-home" -> {
            drawSvgPath(
                "M4 10.25 10.72 4.65a2 2 0 0 1 2.56 0L20 10.25v8.5A1.25 1.25 0 0 1 18.75 20H14.5v-6.25h-5V20H5.25A1.25 1.25 0 0 1 4 18.75Z",
                color,
                stroke
            )
        }
        "dock-vault", "vault", "workspace" -> {
            drawSvgPath(
                "M4 6.5A2.5 2.5 0 0 1 6.5 4H10l2 2.2h5.5A2.5 2.5 0 0 1 20 8.7v8.8a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5Z",
                color,
                stroke
            )
            drawSvgPath("M8 12h8M8 15.5h5", color, stroke)
        }
        "dock-explore", "graph", "sidebar-graph" -> {
            drawSvgCircle(6.5f, 12f, 2.5f, color, stroke)
            drawSvgCircle(17.5f, 6.5f, 2.5f, color, stroke)
            drawSvgCircle(17.5f, 17.5f, 2.5f, color, stroke)
            drawSvgPath("m8.8 10.8 6.4-3.1M8.8 13.2l6.4 3.1", color, stroke)
        }
        "dock-profile", "profile" -> {
            drawSvgCircle(12f, 7.25f, 3.25f, color, stroke)
            drawSvgPath("M4.5 19.75V19a7.5 6 0 0 1 15 0v.75Z", color, stroke)
        }
        "note", "sidebar-files" -> {
            drawSvgPath(
                "M6 3.75h8.25L18.75 8.25v12A1.5 1.5 0 0 1 17.25 21.75H6A1.5 1.5 0 0 1 4.5 20.25V5.25A1.5 1.5 0 0 1 6 3.75Z",
                color,
                stroke
            )
            drawSvgPath("M14 3.75v4.5h4.75M8 12h8M8 15.5h5", color, stroke)
        }
        "study" -> {
            drawSvgPath("M12 4.5 3 9l9 4.5 9-4.5-9-4.5Z", color, stroke)
            drawSvgPath("M6.5 11.5v4.8c0 1.4 2.5 2.7 5.5 2.7s5.5-1.3 5.5-2.7v-4.8", color, stroke)
            drawSvgPath("M21 9v6", color, stroke)
        }
        "markdown" -> {
            drawSvgRect(3f, 5f, 18f, 14f, 2.5f, color, stroke)
            drawSvgPath("M6.5 15V9l2.5 3 2.5-3v6M16.5 9v6M14.5 13l2 2 2-2", color, stroke)
        }
        "mindmap" -> {
            drawSvgRect(3f, 9.5f, 5.5f, 5f, 1.4f, color, stroke)
            drawSvgRect(15.5f, 4f, 5.5f, 4.5f, 1.4f, color, stroke)
            drawSvgRect(15.5f, 9.75f, 5.5f, 4.5f, 1.4f, color, stroke)
            drawSvgRect(15.5f, 15.5f, 5.5f, 4.5f, 1.4f, color, stroke)
            drawSvgPath("M8.5 12h3.5m0 0V6.25h3.5M12 12h3.5M12 12v5.75h3.5", color, stroke)
        }
        "canvas", "sidebar-canvas" -> {
            drawSvgRect(3.5f, 4f, 7f, 6f, 1.5f, color, stroke)
            drawSvgRect(13.5f, 14f, 7f, 6f, 1.5f, color, stroke)
            drawSvgPath("M10.5 7h3a2 2 0 0 1 2 2v5", color, stroke)
        }
        "link" -> {
            drawSvgPath("M10 13a5 5 0 0 0 7.54.54l2.5-2.5a5 5 0 0 0-7.07-7.07l-1.5 1.5", color, stroke)
            drawSvgPath("M14 11a5 5 0 0 0-7.54-.54l-2.5 2.5a5 5 0 0 0 7.07 7.07l1.5-1.5", color, stroke)
        }
        "folder" -> {
            drawSvgPath(
                "M3.5 7A2.5 2.5 0 0 1 6 4.5h3.8l2.1 2.2H18A2.5 2.5 0 0 1 20.5 9.2v8.3A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5Z",
                color,
                stroke
            )
        }
        "tag", "sidebar-tags" -> {
            drawSvgPath("M9.5 4v16M15.5 4v16M4 9.5h16M4 14.5h16", color, stroke)
        }
        "star" -> {
            drawSvgPath(
                "m12 3.75 2.55 5.17 5.7.83-4.12 4.02.97 5.68L12 16.77l-5.1 2.68.97-5.68L3.75 9.75l5.7-.83L12 3.75Z",
                color,
                stroke
            )
        }
        "pin" -> {
            drawSvgPath(
                "m14.5 4.5 5 5-2 2-3-1-4 4 1 3-1.5 1.5-3.5-3.5L3 19l3.5-3.5-3.5-3.5L4.5 10.5l3 1 4-4-1-3 2-2Z",
                color,
                stroke
            )
        }
        "trash", "sidebar-trash" -> {
            drawSvgPath(
                "M4.5 7h15M9.5 7V5a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v2M6.5 7l.8 11.5a1.5 1.5 0 0 0 1.5 1.5h6.4a1.5 1.5 0 0 0 1.5-1.5L17.5 7",
                color,
                stroke
            )
        }
        "sun", "settings", "sidebar-settings" -> {
            drawSvgCircle(12f, 12f, 4f, color, stroke)
            drawSvgPath(
                "M12 2.5v2M12 19.5v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2.5 12h2M19.5 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4",
                color,
                stroke
            )
        }
        "shield" -> {
            drawSvgPath(
                "M12 3.5 5 6.5v5.25c0 4.5 3 8.25 7 9.75 4-1.5 7-5.25 7-9.75V6.5L12 3.5Z",
                color,
                stroke
            )
            drawSvgPath("m9.5 12 1.8 1.8 3.4-3.6", color, stroke)
        }
        "info", "sidebar-help" -> {
            drawSvgCircle(12f, 12f, 8.5f, color, stroke)
            drawSvgPath("M12 11.5v5M12 8.2h.01", color, stroke)
        }
        "export" -> {
            drawSvgPath(
                "M12 3.5v11M8 8.5l4-5 4 5M4.5 15.5v3A1.5 1.5 0 0 0 6 20h12a1.5 1.5 0 0 0 1.5-1.5v-3",
                color,
                stroke
            )
        }
        "undo" -> {
            drawSvgPath("M9 14 4 9l5-5", color, stroke)
            drawSvgPath("M4 9h10.5a5.5 5.5 0 0 1 0 11H11", color, stroke)
        }
        "redo" -> {
            drawSvgPath("m15 14 5-5-5-5", color, stroke)
            drawSvgPath("M20 9H9.5a5.5 5.5 0 0 0 0 11H13", color, stroke)
        }
        "plugin" -> {
            drawSvgPath(
                "M9 3h6v5h3a3 3 0 1 1 0 6h-3v7H9v-3a3 3 0 1 0-6 0v-7h6V3Z",
                color,
                stroke
            )
        }
        "mic" -> {
            drawSvgRect(9f, 3.5f, 6f, 10.5f, 3f, color, stroke)
            drawSvgPath("M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6", color, stroke)
        }
        "outline", "list" -> {
            drawSvgPath("M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01", color, stroke)
        }
        "gear" -> {
            drawSvgCircle(12f, 12f, 3.2f, color, stroke)
            drawSvgPath(
                "M12 3.2v2.1M12 18.7v2.1M5.8 5.8l1.5 1.5M16.7 16.7l1.5 1.5M3.2 12h2.1M18.7 12h2.1M5.8 18.2l1.5-1.5M16.7 7.3l1.5-1.5",
                color,
                stroke
            )
        }
        "calendar", "sidebar-daily" -> {
            drawSvgRect(4f, 5f, 16f, 16f, 2f, color, stroke)
            drawSvgPath("M8 3v4m8-4v4M4 10h16m-11 5 2 2 4-4", color, stroke)
        }
        "sidebar-templates" -> {
            drawSvgRect(3.5f, 4f, 17f, 16f, 2f, color, stroke)
            drawSvgPath("M3.5 9h17M9.5 9v11", color, stroke)
        }
        "sidebar-capture" -> {
            drawSvgPath("M13 3L5 14h6l-1 7 9-11h-6l1-7Z", color, stroke)
        }
        else -> {
            drawSvgPath(
                "M6 3.75h8.25L18.75 8.25v12A1.5 1.5 0 0 1 17.25 21.75H6A1.5 1.5 0 0 1 4.5 20.25V5.25A1.5 1.5 0 0 1 6 3.75Z",
                color,
                stroke
            )
            drawSvgPath("M14 3.75v4.5h4.75M8 12h8M8 15.5h5", color, stroke)
        }
    }
}
