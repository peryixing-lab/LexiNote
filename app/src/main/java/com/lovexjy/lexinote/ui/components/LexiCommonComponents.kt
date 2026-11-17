package com.lovexjy.lexinote.ui.components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.lovexjy.lexinote.core.*
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

fun trText(raw: String): String = LexiI18n.text(raw, LexiStorageService.getAppLanguage())

fun formatTimeShort(ts: Long): String {
    if (ts <= 0L) return ""
    val cal = java.util.Calendar.getInstance()
    val todayYear = cal.get(java.util.Calendar.YEAR)
    val todayDay = cal.get(java.util.Calendar.DAY_OF_YEAR)
    val targetCal = java.util.Calendar.getInstance().apply { timeInMillis = ts }
    val hmFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
    val hm = hmFmt.format(Date(ts))
    if (targetCal.get(java.util.Calendar.YEAR) == todayYear &&
        targetCal.get(java.util.Calendar.DAY_OF_YEAR) == todayDay) {
        return "${trText("今天")} $hm"
    }
    val yesterdayCal = java.util.Calendar.getInstance().apply {
        timeInMillis = System.currentTimeMillis() - 86_400_000L
    }
    if (targetCal.get(java.util.Calendar.YEAR) == yesterdayCal.get(java.util.Calendar.YEAR) &&
        targetCal.get(java.util.Calendar.DAY_OF_YEAR) == yesterdayCal.get(java.util.Calendar.DAY_OF_YEAR)) {
        return "${trText("昨天")} $hm"
    }
    val month = targetCal.get(java.util.Calendar.MONTH) + 1
    val day = targetCal.get(java.util.Calendar.DAY_OF_MONTH)
    return "${month}月${day}日"
}

@Composable
fun LexiHeroHeading(
    title: String,
    subtitle: String = "",
    palette: LexiThemePalette,
    collapsed: Boolean = false,
    modifier: Modifier = Modifier
) {
    val heroAlpha by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (collapsed) 0f else 1f,
        animationSpec = androidx.compose.animation.core.tween(160),
        label = "heroAlpha"
    )
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = trText(title),
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            color = palette.text_primary.toComposeColor().copy(alpha = heroAlpha)
        )
        if (subtitle.isNotEmpty()) {
            Text(
                text = trText(subtitle),
                fontSize = 13.sp,
                lineHeight = 20.sp,
                color = palette.text_secondary.toComposeColor().copy(alpha = heroAlpha)
            )
        }
    }
}

@Composable
fun LexiFilterChip(
    selected: Boolean,
    label: String,
    palette: LexiThemePalette,
    onClick: () -> Unit
) {
    val bg = com.lovexjy.lexinote.ui.theme.LexiMotion.animateColor(
        if (selected) palette.brand.toComposeColor() else palette.surface.toComposeColor(),
        label = "filterChipBg"
    )
    val fg = com.lovexjy.lexinote.ui.theme.LexiMotion.animateColor(
        if (selected) palette.inverse_text.toComposeColor() else palette.text_secondary.toComposeColor(),
        label = "filterChipFg"
    )
    val shape = RoundedCornerShape(13.dp)
    Box(
        modifier = Modifier
            .height(36.dp)
            .clip(shape)
            .background(bg)
            .clickable { onClick() }
            .padding(horizontal = 15.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
            color = fg,
            maxLines = 1
        )
    }
}

@Composable
fun LexiBackHeader(
    title: String,
    subtitle: String = "",
    rightText: String = "",
    palette: LexiThemePalette,
    tintedScrim: Boolean = true,
    onBack: () -> Unit,
    onRightAction: (() -> Unit)? = null
) {
    val bgModifier = if (tintedScrim) {
        Modifier.background(
            Brush.verticalGradient(
                colors = listOf(
                    palette.bg_root.toComposeColor(),
                    palette.bg_root.toComposeColor().copy(alpha = 0.94f),
                    Color.Transparent
                )
            )
        )
    } else {
        Modifier.background(palette.surface.toComposeColor())
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(bgModifier)
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val backInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
        Box(
            modifier = Modifier
                .size(40.dp)
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = CircleShape,
                        dark = palette.dark
                    )
                )
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(backInteraction))
                .clip(CircleShape)
                .background(palette.surface_card.toComposeColor())
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(backInteraction) { onBack() }),
            contentAlignment = Alignment.Center
        ) {
            LexiIcon(name = "back", size = 20.dp, palette = palette)
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = trText(title),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_primary.toComposeColor(),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = trText(subtitle),
                    fontSize = 11.sp,
                    color = palette.text_secondary.toComposeColor(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        if (rightText.isNotEmpty() && onRightAction != null) {
            val rightInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
            val rightShape = RoundedCornerShape(19.dp)
            Box(
                modifier = Modifier
                    .height(38.dp)
                    .widthIn(min = 68.dp)
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(rightInteraction))
                    .clip(rightShape)
                    .background(palette.brand_soft.toComposeColor())
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(rightInteraction) { onRightAction() })
                    .padding(horizontal = 14.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = trText(rightText),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.brand.toComposeColor()
                )
            }
        }
    }
}

@Composable
fun LexiLaunchScreen(palette: LexiThemePalette) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.page_bg.toComposeColor()),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(24.dp)
        ) {
            Box(
                modifier = Modifier.size(220.dp),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .size(212.dp)
                        .clip(CircleShape)
                        .border(1.dp, palette.divider.toComposeColor().copy(alpha = 0.65f), CircleShape)
                )
                Box(
                    modifier = Modifier
                        .size(176.dp)
                        .clip(CircleShape)
                        .background(palette.brand_soft.toComposeColor().copy(alpha = 0.36f))
                )
                Box(
                    modifier = Modifier
                        .size(140.dp)
                        .clip(CircleShape)
                        .background(palette.brand_soft.toComposeColor().copy(alpha = 0.55f))
                )
                LexiLogo(
                    size = 96.dp,
                    modifier = Modifier.clip(RoundedCornerShape(24.dp))
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = trText("知萤 LexiNote"),
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_primary.toComposeColor()
            )
            Spacer(modifier = Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(
                    modifier = Modifier
                        .width(24.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(palette.brand.toComposeColor())
                )
                Box(
                    modifier = Modifier
                        .width(12.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(palette.divider.toComposeColor())
                )
                Box(
                    modifier = Modifier
                        .width(12.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(palette.divider.toComposeColor())
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = trText("正在打开本地工作区"),
                fontSize = 13.sp,
                color = palette.text_secondary.toComposeColor()
            )
        }
    }
}

private data class WelcomeStep(
    val icon: String,
    val badge: String,
    val title: String,
    val subtitle: String,
    val points: List<String>
)

@Composable
fun LexiWelcomeGuide(
    palette: LexiThemePalette,
    onFinish: () -> Unit
) {
    val steps = remember {
        listOf(
            WelcomeStep(
                icon = "note",
                badge = "欢迎来到知萤",
                title = "构建属于你的第二大脑",
                subtitle = "知萤 LexiNote 将极简笔记、双向链接、思维导图与无限白板融为一体。",
                points = listOf(
                    "纯正本地优先存储，支持导出标准 .md 与 JSON 备份",
                    "支持 [[双向链接]]、#多级标签、YAML Frontmatter 与 LaTeX 公式",
                    "手机端单手友好设计，灵感随时记录"
                )
            ),
            WelcomeStep(
                icon = "markdown",
                badge = "沉浸式写作",
                title = "实时预览与多档工具栏",
                subtitle = "不论是随手记还是深度学术笔记，都能找到最舒服的节奏。",
                points = listOf(
                    "支持实时预览、源码编辑、分栏对照与沉浸阅读四种模式",
                    "底部工具栏提供「简洁 / 学习 / 专业」三档自由切换",
                    "内置版本历史快照与逐行差异对比，防止误删"
                )
            ),
            WelcomeStep(
                icon = "graph",
                badge = "知识网络",
                title = "让每一条笔记产生连接",
                subtitle = "在探索页与笔记底部随时查看双向引用、未连接笔记与关系图谱。",
                points = listOf(
                    "输入 [[ 即可智能补全笔记标题与 #章节锚点",
                    "自动发现潜在提及，一键建立知识连接",
                    "力导向关系图谱直观呈现你的知识拓扑"
                )
            ),
            WelcomeStep(
                icon = "mindmap",
                badge = "多维思考",
                title = "思维导图与自由白板",
                subtitle = "跳出线性文字束缚，在二维空间梳理结构与灵感。",
                points = listOf(
                    "思维导图支持向右、双向、组织结构三种布局及 Markdown 互转",
                    "自由白板支持拖拽卡片、连线标注与关联知识库笔记",
                    "所有视图均支持手势缩放与拖拽漫游"
                )
            ),
            WelcomeStep(
                icon = "shield",
                badge = "准备就绪",
                title = "开启你的知萤之旅",
                subtitle = "你的所有数据均安全保存在本地知识库中，随时可在设置中配置本地文件夹。",
                points = listOf(
                    "首页「今日笔记」与「随手记」助你零阻力启动记录",
                    "支持 5 套精选主题与深浅色自适应",
                    "现在开始探索吧！"
                )
            )
        )
    }
    var currentStep by remember { mutableIntStateOf(0) }
    val step = steps[currentStep]

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0x88140F23)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(palette.surface_card.toComposeColor())
                .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(24.dp))
                .padding(22.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = trText(step.badge),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                }
                Text(
                    text = trText("跳过"),
                    fontSize = 13.sp,
                    color = palette.text_muted.toComposeColor(),
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { onFinish() }
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }

            Spacer(modifier = Modifier.height(18.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(palette.brand_soft.toComposeColor()),
                    contentAlignment = Alignment.Center
                ) {
                    LexiIcon(name = step.icon, size = 24.dp, palette = palette)
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = trText(step.title),
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "${currentStep + 1} / ${steps.size}",
                        fontSize = 11.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = trText(step.subtitle),
                fontSize = 13.sp,
                color = palette.text_secondary.toComposeColor(),
                lineHeight = 19.sp
            )

            Spacer(modifier = Modifier.height(14.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(palette.surface_soft.toComposeColor())
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                step.points.forEach { pt ->
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "• ",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.brand.toComposeColor()
                        )
                        Text(
                            text = trText(pt),
                            fontSize = 12.sp,
                            color = palette.text_primary.toComposeColor(),
                            lineHeight = 18.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (currentStep > 0) {
                    Box(
                        modifier = Modifier
                            .height(40.dp)
                            .clip(RoundedCornerShape(20.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                            .clickable { currentStep -= 1 }
                            .padding(horizontal = 16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = trText("上一步"),
                            fontSize = 13.sp,
                            color = palette.text_secondary.toComposeColor()
                        )
                    }
                } else {
                    Spacer(modifier = Modifier.width(1.dp))
                }

                Box(
                    modifier = Modifier
                        .height(40.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(palette.brand.toComposeColor())
                        .clickable {
                            if (currentStep < steps.size - 1) {
                                currentStep += 1
                            } else {
                                onFinish()
                            }
                        }
                        .padding(horizontal = 20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (currentStep < steps.size - 1) trText("下一步") else trText("开始使用"),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }
    }
}

@Composable
fun LexiHighlightText(
    text: String,
    query: String = "",
    fontSize: TextUnit = 14.sp,
    fontWeight: FontWeight = FontWeight.Normal,
    color: Color,
    highlightBg: Color,
    highlightFg: Color,
    maxLines: Int = 2,
    modifier: Modifier = Modifier
) {
    val spans = remember(text, query) {
        val terms = LexiSearch.highlightTerms(query)
        LexiSearch.highlightSegments(text, terms)
    }
    val annotated = remember(spans, color, highlightBg, highlightFg) {
        buildAnnotatedString {
            spans.forEach { span ->
                if (span.matched) {
                    withStyle(
                        SpanStyle(
                            color = highlightFg,
                            background = highlightBg,
                            fontWeight = FontWeight.Bold
                        )
                    ) {
                        append(span.text)
                    }
                } else {
                    withStyle(SpanStyle(color = color)) {
                        append(span.text)
                    }
                }
            }
        }
    }
    Text(
        text = annotated,
        fontSize = fontSize,
        fontWeight = fontWeight,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
    )
}

@Composable
fun LexiLinkPreviewPopupCard(
    preview: LexiLinkTargetPreview,
    palette: LexiThemePalette,
    onOpen: () -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(palette.surface_card.toComposeColor())
                .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f)
                ) {
                    LexiIcon(name = "link", size = 16.dp, palette = palette)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = preview.noteTitle,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (preview.matchedHeading.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(palette.brand_soft.toComposeColor())
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "#${preview.matchedHeading}",
                            fontSize = 11.sp,
                            color = palette.brand.toComposeColor()
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(palette.surface_soft.toComposeColor())
                    .padding(12.dp)
            ) {
                Text(
                    text = preview.snippet.ifEmpty { trText("暂无内容预览") },
                    fontSize = 13.sp,
                    color = palette.text_secondary.toComposeColor(),
                    lineHeight = 19.sp,
                    maxLines = 6,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (preview.tags.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    preview.tags.take(5).forEach { tag ->
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(palette.chip_bg.toComposeColor())
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        ) {
                            Text(
                                text = "#$tag",
                                fontSize = 11.sp,
                                color = palette.brand.toComposeColor()
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(14.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) {
                    Text(text = trText("关闭"), color = palette.text_secondary.toComposeColor())
                }
                Spacer(modifier = Modifier.width(6.dp))
                Button(
                    onClick = {
                        onDismiss()
                        onOpen()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                ) {
                    Text(text = trText("打开笔记"), color = Color.White, fontSize = 13.sp)
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LexiNoteCard(
    note: NoteItem,
    vaultName: String = "",
    highlightQuery: String = "",
    palette: LexiThemePalette,
    showAccessTime: Boolean = false,
    outgoingCount: Int = 0,
    backlinkCount: Int = 0,
    isUnconnected: Boolean = false,
    onOpen: () -> Unit,
    onTogglePin: (() -> Unit)? = null,
    onToggleFavorite: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    onDuplicate: (() -> Unit)? = null,
    onExportMarkdown: (() -> Unit)? = null,
    onTagClick: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    var showMenu by remember { mutableStateOf(false) }
    val spans = remember(note.id, note.title, note.content, note.updatedAt, highlightQuery) {
        MarkdownEngine.previewSpans(note, highlightQuery)
    }
    val typeLabel = when (note.noteType) {
        "study" -> trText("学习")
        "markdown" -> "Markdown"
        else -> trText("速记")
    }
    val typeIcon = when (note.noteType) {
        "study" -> "study"
        "markdown" -> "markdown"
        else -> "note"
    }
    val displayNotebook = note.notebook.ifBlank { vaultName }
    val timeTs = if (showAccessTime && note.lastOpenedAt > 0L) note.lastOpenedAt else note.updatedAt
    val timeText = if (showAccessTime && note.lastOpenedAt > 0L) {
        "${trText("访问")} ${formatTimeShort(timeTs)}"
    } else {
        formatTimeShort(timeTs)
    }

    val previewAnnotated = remember(spans, palette) {
        buildAnnotatedString {
            if (spans.isEmpty()) {
                withStyle(SpanStyle(color = palette.text_secondary.toComposeColor())) {
                    append(trText("点击继续记录内容…"))
                }
            } else {
                spans.forEach { sp ->
                    val fg = when {
                        sp.searchMatch -> palette.brand_ink.toComposeColor()
                        sp.kind == "link" || sp.kind == "url" || sp.kind == "wikilink" -> palette.brand_ink.toComposeColor()
                        else -> palette.text_secondary.toComposeColor()
                    }
                    val bg = when {
                        sp.searchMatch -> Color(0x59FACC15)
                        sp.kind == "highlight" -> palette.brand_soft.toComposeColor()
                        else -> Color.Transparent
                    }
                    withStyle(
                        SpanStyle(
                            color = fg,
                            background = bg,
                            fontWeight = if (sp.kind == "bold" || sp.searchMatch) FontWeight.Bold else FontWeight.Normal,
                            fontStyle = if (sp.kind == "italic") FontStyle.Italic else FontStyle.Normal,
                            fontFamily = if (sp.kind == "code") FontFamily.Monospace else FontFamily.Default,
                            textDecoration = if (sp.kind == "strike") TextDecoration.LineThrough else TextDecoration.None
                        )
                    ) {
                        append(sp.text)
                    }
                }
            }
        }
    }

    val cardInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
    val cardShape = RoundedCornerShape(20.dp)
    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(cardInteraction))
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = cardShape,
                        dark = palette.dark
                    )
                )
                .clip(cardShape)
                .background(palette.surface_card.toComposeColor())
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiMotion.combinedClickTarget(
                        interactionSource = cardInteraction,
                        onLongClick = { showMenu = true },
                        onClick = onOpen
                    )
                )
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                LexiIcon(name = typeIcon, size = 16.dp, palette = palette)
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = typeLabel,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.brand.toComposeColor()
                    )
                }
                if (displayNotebook.isNotEmpty()) {
                    Text(
                        text = displayNotebook,
                        fontSize = 11.sp,
                        color = palette.text_secondary.toComposeColor(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                if (note.pinned) {
                    LexiIcon(name = "pin", size = 14.dp, palette = palette)
                }
                if (note.favorite) {
                    LexiIcon(name = "star", size = 14.dp, tint = Color(0xFFC9822B), palette = palette)
                }
                Text(
                    text = timeText,
                    fontSize = 11.sp,
                    color = palette.text_secondary.toComposeColor()
                )
                Box(
                    modifier = Modifier
                        .size(width = 28.dp, height = 26.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .clickable { showMenu = true },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "⋯",
                        fontSize = 14.sp,
                        color = palette.text_secondary.toComposeColor()
                    )
                }
            }

            LexiHighlightText(
                text = MarkdownEngine.displayTitle(note).ifBlank { trText("未命名速记") },
                query = highlightQuery,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_primary.toComposeColor(),
                highlightBg = palette.brand_soft.toComposeColor(),
                highlightFg = palette.brand_ink.toComposeColor(),
                maxLines = 1
            )

            Text(
                text = previewAnnotated,
                fontSize = 14.sp,
                lineHeight = 22.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                note.tags.take(3).forEach { tag ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(7.dp))
                            .background(palette.soft_surface.toComposeColor())
                            .clickable(enabled = onTagClick != null) { onTagClick?.invoke(tag) }
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "#$tag",
                            fontSize = 11.sp,
                            color = palette.brand_ink.toComposeColor()
                        )
                    }
                }
                Spacer(modifier = Modifier.weight(1f))
                if (outgoingCount > 0 || backlinkCount > 0) {
                    Text(
                        text = "🔗 $outgoingCount 出 · $backlinkCount 反",
                        fontSize = 11.sp,
                        color = palette.brand.toComposeColor()
                    )
                } else if (isUnconnected && note.trashedAt == 0L) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(palette.soft_surface.toComposeColor())
                            .padding(horizontal = 7.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = trText("未连接"),
                            fontSize = 10.sp,
                            color = palette.text_secondary.toComposeColor()
                        )
                    }
                }
            }
        }

        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false }
        ) {
            DropdownMenuItem(
                text = { Text(trText("打开笔记")) },
                onClick = {
                    showMenu = false
                    onOpen()
                }
            )
            if (onTogglePin != null) {
                DropdownMenuItem(
                    text = { Text(if (note.pinned) trText("取消置顶") else trText("置顶笔记")) },
                    onClick = {
                        showMenu = false
                        onTogglePin()
                    }
                )
            }
            if (onToggleFavorite != null) {
                DropdownMenuItem(
                    text = { Text(if (note.favorite) trText("取消收藏") else trText("加入收藏")) },
                    onClick = {
                        showMenu = false
                        onToggleFavorite()
                    }
                )
            }
            if (onDuplicate != null) {
                DropdownMenuItem(
                    text = { Text(trText("创建副本")) },
                    onClick = {
                        showMenu = false
                        onDuplicate()
                    }
                )
            }
            if (onExportMarkdown != null) {
                DropdownMenuItem(
                    text = { Text(trText("导出 Markdown (.md)")) },
                    onClick = {
                        showMenu = false
                        onExportMarkdown()
                    }
                )
            }
            if (onDelete != null) {
                DropdownMenuItem(
                    text = { Text(trText("移入回收站"), color = palette.danger.toComposeColor()) },
                    onClick = {
                        showMenu = false
                        onDelete()
                    }
                )
            }
        }
    }
}

@Composable
fun LexiGraphView(
    graphData: GraphData,
    selectedNodeId: String = "",
    palette: LexiThemePalette,
    height: Dp = 280.dp,
    onNodeClick: (GraphNode) -> Unit
) {
    var nodes by remember(graphData) { mutableStateOf(graphData.nodes.map { it.copy() }) }
    val edges = graphData.edges
    var zoom by remember { mutableFloatStateOf(1f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }
    var layoutSeed by remember { mutableIntStateOf(1) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(palette.surface_card.toComposeColor())
            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(18.dp))
            .padding(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                LegendDot(color = palette.brand.toComposeColor(), label = trText("笔记"), palette = palette)
                LegendDot(color = Color(0xFF2B6CB0), label = trText("导图"), palette = palette)
                LegendDot(color = Color(0xFFD69E2E), label = trText("标签"), palette = palette)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SmallControlChip(text = trText("重排"), palette = palette) {
                    layoutSeed += 1
                    val relayout = LexiGraphForce.layout(
                        nodes.map { it.copy() },
                        edges,
                        720f,
                        420f
                    )
                    nodes = relayout
                }
                SmallControlChip(text = trText("居中"), palette = palette) {
                    zoom = 1f
                    panOffset = Offset.Zero
                }
                SmallControlChip(text = "-", palette = palette) {
                    zoom = max(0.55f, zoom - 0.15f)
                }
                SmallControlChip(text = "${(zoom * 100).toInt()}%", palette = palette) {
                    zoom = 1f
                }
                SmallControlChip(text = "+", palette = palette) {
                    zoom = min(2.2f, zoom + 0.15f)
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(height)
                .clip(RoundedCornerShape(14.dp))
                .background(palette.surface_soft.toComposeColor())
                .pointerInput(nodes, zoom, panOffset) {
                    detectTapGestures { tapOffset ->
                        val w = size.width.toFloat().coerceAtLeast(1f)
                        val h = size.height.toFloat().coerceAtLeast(1f)
                        val hit = nodes.firstOrNull { node ->
                            val nx = ((node.x / 720f) * w - w / 2f) * zoom + w / 2f + panOffset.x
                            val ny = ((node.y / 420f) * h - h / 2f) * zoom + h / 2f + panOffset.y
                            hypot(tapOffset.x - nx, tapOffset.y - ny) <= 28f * zoom
                        }
                        if (hit != null) {
                            onNodeClick(hit)
                        }
                    }
                }
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, gestureZoom, _ ->
                        zoom = (zoom * gestureZoom).coerceIn(0.55f, 2.2f)
                        panOffset += pan
                    }
                }
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val w = size.width.coerceAtLeast(1f)
                val h = size.height.coerceAtLeast(1f)

                fun mapPoint(nx: Float, ny: Float): Offset {
                    val x = ((nx / 720f) * w - w / 2f) * zoom + w / 2f + panOffset.x
                    val y = ((ny / 420f) * h - h / 2f) * zoom + h / 2f + panOffset.y
                    return Offset(x, y)
                }

                val nodeMap = nodes.associateBy { it.id }
                edges.forEach { edge ->
                    val s = nodeMap[edge.sourceId] ?: return@forEach
                    val t = nodeMap[edge.targetId] ?: return@forEach
                    val p1 = mapPoint(s.x, s.y)
                    val p2 = mapPoint(t.x, t.y)
                    val isSelectedEdge = edge.sourceId == selectedNodeId || edge.targetId == selectedNodeId
                    drawLine(
                        color = if (isSelectedEdge) palette.brand.toComposeColor() else palette.stroke.toComposeColor(),
                        start = p1,
                        end = p2,
                        strokeWidth = if (isSelectedEdge) 3f else 1.8f
                    )
                }

                nodes.forEach { node ->
                    val center = mapPoint(node.x, node.y)
                    val isSelected = node.id == selectedNodeId
                    val baseColor = when (node.kind) {
                        "mindmap" -> Color(0xFF2B6CB0)
                        "tag" -> Color(0xFFD69E2E)
                        else -> palette.brand.toComposeColor()
                    }
                    val radius = (10f + min(10f, node.degree * 1.8f)) * zoom
                    if (isSelected) {
                        drawCircle(
                            color = baseColor.copy(alpha = 0.25f),
                            radius = radius + 8f,
                            center = center
                        )
                    }
                    drawCircle(
                        color = baseColor,
                        radius = radius,
                        center = center
                    )
                }
            }

            // Node labels overlay
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val w = constraints.maxWidth.toFloat().coerceAtLeast(1f)
                val h = constraints.maxHeight.toFloat().coerceAtLeast(1f)
                val density = androidx.compose.ui.platform.LocalDensity.current
                nodes.forEach { node ->
                    val xPx = ((node.x / 720f) * w - w / 2f) * zoom + w / 2f + panOffset.x
                    val yPx = ((node.y / 420f) * h - h / 2f) * zoom + h / 2f + panOffset.y
                    val xDp = with(density) { xPx.toDp() }
                    val yDp = with(density) { (yPx + 14f * zoom).toDp() }
                    Text(
                        text = node.label,
                        fontSize = 10.sp,
                        fontWeight = if (node.id == selectedNodeId) FontWeight.Bold else FontWeight.Normal,
                        color = if (node.id == selectedNodeId) palette.brand.toComposeColor() else palette.text_primary.toComposeColor(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .offset(x = xDp - 36.dp, y = yDp)
                            .widthIn(max = 88.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun LegendDot(color: Color, label: String, palette: LexiThemePalette) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = label,
            fontSize = 11.sp,
            color = palette.text_secondary.toComposeColor()
        )
    }
}

@Composable
fun SmallControlChip(
    text: String,
    palette: LexiThemePalette,
    active: Boolean = false,
    onClick: () -> Unit
) {
    val chipBg = com.lovexjy.lexinote.ui.theme.LexiMotion.animateColor(
        if (active) palette.brand.toComposeColor() else palette.surface.toComposeColor(),
        label = "chipBg"
    )
    val chipFg = com.lovexjy.lexinote.ui.theme.LexiMotion.animateColor(
        if (active) palette.inverse_text.toComposeColor() else palette.text_secondary.toComposeColor(),
        label = "chipFg"
    )
    val chipShape = RoundedCornerShape(10.dp)
    Box(
        modifier = Modifier
            .height(32.dp)
            .clip(chipShape)
            .background(chipBg)
            .clickable { onClick() }
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            fontSize = 12.sp,
            fontWeight = if (active) FontWeight.Medium else FontWeight.Normal,
            color = chipFg,
            maxLines = 1
        )
    }
}

@Composable
fun LexiMarkdownPreview(
    markdown: String,
    allNotes: List<NoteItem>,
    palette: LexiThemePalette,
    fontSizeScale: Float = 1f,
    onWikiLinkClick: (String) -> Unit,
    onTagClick: (String) -> Unit,
    onToggleTask: ((Int, Boolean) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val parsed = remember(markdown) { LexiFrontmatter.parse(markdown) }
    val blocks = remember(parsed.body) { MarkdownEngine.parseBlocks(parsed.body) }
    val context = LocalContext.current

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        blocks.forEachIndexed { idx, block ->
            when (block.type) {
                "heading" -> {
                    val size = when (block.level) {
                        1 -> (22 * fontSizeScale).sp
                        2 -> (19 * fontSizeScale).sp
                        3 -> (17 * fontSizeScale).sp
                        else -> (15 * fontSizeScale).sp
                    }
                    LexiRichInlineText(
                        text = block.text,
                        palette = palette,
                        fontSize = size,
                        fontWeight = FontWeight.Bold,
                        onWikiLinkClick = onWikiLinkClick,
                        onTagClick = onTagClick
                    )
                }
                "callout" -> {
                    val calloutColor = when (block.meta.uppercase()) {
                        "WARNING", "CAUTION" -> Color(0xFFD69E2E)
                        "DANGER", "ERROR" -> palette.danger.toComposeColor()
                        "TIP", "SUCCESS" -> palette.success.toComposeColor()
                        else -> palette.brand.toComposeColor()
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(calloutColor.copy(alpha = 0.10f))
                            .border(
                                com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline,
                                calloutColor.copy(alpha = 0.32f),
                                RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.MD)
                            )
                            .padding(12.dp)
                    ) {
                        Text(
                            text = "[!${block.meta}]",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = calloutColor
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        LexiRichInlineText(
                            text = block.text,
                            palette = palette,
                            fontSize = (14 * fontSizeScale).sp,
                            onWikiLinkClick = onWikiLinkClick,
                            onTagClick = onTagClick
                        )
                    }
                }
                "quote" -> {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(10.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .heightIn(min = 20.dp)
                                .background(palette.brand.toComposeColor())
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        LexiRichInlineText(
                            text = block.text,
                            palette = palette,
                            fontSize = (14 * fontSizeScale).sp,
                            color = palette.text_secondary.toComposeColor(),
                            onWikiLinkClick = onWikiLinkClick,
                            onTagClick = onTagClick
                        )
                    }
                }
                "task" -> {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .clickable(enabled = onToggleTask != null) {
                                onToggleTask?.invoke(idx, !block.checked)
                            }
                            .padding(vertical = 2.dp)
                    ) {
                        Checkbox(
                            checked = block.checked,
                            onCheckedChange = if (onToggleTask != null) {
                                { onToggleTask(idx, it) }
                            } else null,
                            colors = CheckboxDefaults.colors(
                                checkedColor = palette.brand.toComposeColor(),
                                uncheckedColor = palette.text_muted.toComposeColor()
                            ),
                            modifier = Modifier.size(22.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        LexiRichInlineText(
                            text = block.text,
                            palette = palette,
                            fontSize = (14 * fontSizeScale).sp,
                            strikethrough = false,
                            color = palette.text_primary.toComposeColor(),
                            onWikiLinkClick = onWikiLinkClick,
                            onTagClick = onTagClick
                        )
                    }
                }
                "bullet" -> {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "•  ",
                            fontSize = (14 * fontSizeScale).sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.brand.toComposeColor()
                        )
                        LexiRichInlineText(
                            text = block.text,
                            palette = palette,
                            fontSize = (14 * fontSizeScale).sp,
                            onWikiLinkClick = onWikiLinkClick,
                            onTagClick = onTagClick
                        )
                    }
                }
                "ordered" -> {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "${block.meta.ifEmpty { "1." }} ",
                            fontSize = (14 * fontSizeScale).sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.brand.toComposeColor()
                        )
                        LexiRichInlineText(
                            text = block.text,
                            palette = palette,
                            fontSize = (14 * fontSizeScale).sp,
                            onWikiLinkClick = onWikiLinkClick,
                            onTagClick = onTagClick
                        )
                    }
                }
                "code" -> {
                    var wrapLines by remember { mutableStateOf(true) }
                    var showLineNums by remember { mutableStateOf(true) }
                    val lang = LexiCodeHighlight.languageLabel(block.meta)
                    val codeLines = remember(block.text, block.meta) {
                        LexiCodeHighlight.parseLines(block.text, block.meta)
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(14.dp))
                            .padding(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = lang,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    text = if (showLineNums) trText("隐藏行号") else trText("显示行号"),
                                    fontSize = 11.sp,
                                    color = palette.text_muted.toComposeColor(),
                                    modifier = Modifier.clickable { showLineNums = !showLineNums }
                                )
                                Text(
                                    text = if (wrapLines) trText("取消折行") else trText("自动折行"),
                                    fontSize = 11.sp,
                                    color = palette.text_muted.toComposeColor(),
                                    modifier = Modifier.clickable { wrapLines = !wrapLines }
                                )
                                Text(
                                    text = trText("复制"),
                                    fontSize = 11.sp,
                                    color = palette.brand.toComposeColor(),
                                    modifier = Modifier.clickable {
                                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                                        cm?.setPrimaryClip(ClipData.newPlainText("code", block.text))
                                    }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        val scrollMod = if (wrapLines) Modifier.fillMaxWidth() else Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                        Column(modifier = scrollMod, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            codeLines.forEach { cl ->
                                Row {
                                    if (showLineNums) {
                                        Text(
                                            text = cl.lineNumber.toString().padStart(2, ' ') + "  ",
                                            fontSize = 12.sp,
                                            fontFamily = FontFamily.Monospace,
                                            color = palette.text_muted.toComposeColor()
                                        )
                                    }
                                    val annotatedLine = buildAnnotatedString {
                                        cl.spans.forEach { sp ->
                                            val c = when (sp.kind) {
                                                "keyword" -> palette.brand.toComposeColor()
                                                "string" -> palette.success.toComposeColor()
                                                "comment" -> palette.text_muted.toComposeColor()
                                                "number" -> Color(0xFFD69E2E)
                                                else -> palette.text_primary.toComposeColor()
                                            }
                                            withStyle(
                                                SpanStyle(
                                                    color = c,
                                                    fontWeight = if (sp.kind == "keyword") FontWeight.Bold else FontWeight.Normal
                                                )
                                            ) {
                                                append(sp.text)
                                            }
                                        }
                                    }
                                    Text(
                                        text = annotatedLine,
                                        fontSize = 12.sp,
                                        fontFamily = FontFamily.Monospace,
                                        softWrap = wrapLines
                                    )
                                }
                            }
                        }
                    }
                }
                "math" -> {
                    val mathInfo = remember(block.text) { LexiMathSyntax.displayBlock(block.text) }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.brand_soft.toComposeColor())
                            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(12.dp))
                            .padding(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = mathInfo.envLabel,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                            if (mathInfo.tag.isNotEmpty()) {
                                Text(
                                    text = "(${mathInfo.tag})",
                                    fontSize = 11.sp,
                                    color = palette.text_secondary.toComposeColor()
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(6.dp))
                        mathInfo.lines.forEach { line ->
                            Text(
                                text = line,
                                fontSize = (15 * fontSizeScale).sp,
                                fontFamily = FontFamily.Serif,
                                fontStyle = FontStyle.Italic,
                                color = palette.text_primary.toComposeColor()
                            )
                        }
                    }
                }
                "table" -> {
                    val table = remember(block.text) { MarkdownEngine.tableData(block.text) }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .clip(RoundedCornerShape(12.dp))
                            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(12.dp))
                    ) {
                        if (table.headers.isNotEmpty()) {
                            Row(
                                modifier = Modifier
                                    .background(palette.brand_soft.toComposeColor())
                                    .padding(vertical = 8.dp, horizontal = 10.dp)
                            ) {
                                table.headers.forEach { header ->
                                    Text(
                                        text = header,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = palette.brand.toComposeColor(),
                                        modifier = Modifier.width(110.dp)
                                    )
                                }
                            }
                        }
                        table.rows.forEachIndexed { rIdx, row ->
                            Row(
                                modifier = Modifier
                                    .background(
                                        if (rIdx % 2 == 0) palette.surface_card.toComposeColor()
                                        else palette.surface_soft.toComposeColor()
                                    )
                                    .padding(vertical = 7.dp, horizontal = 10.dp)
                            ) {
                                row.forEach { cell ->
                                    Text(
                                        text = cell,
                                        fontSize = 12.sp,
                                        color = palette.text_primary.toComposeColor(),
                                        modifier = Modifier.width(110.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                "embed" -> {
                    val targetTitle = block.meta.substringBefore("#").trim()
                    val heading = block.meta.substringAfter("#", "").trim()
                    val targetNote = allNotes.firstOrNull {
                        it.title.equals(targetTitle, ignoreCase = true)
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(12.dp))
                            .clickable { onWikiLinkClick(block.meta) }
                            .padding(12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            LexiIcon(name = "link", size = 14.dp, palette = palette)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = trText("嵌入笔记：") + block.meta,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                        }
                        Spacer(modifier = Modifier.height(6.dp))
                        val excerpt = if (targetNote != null) {
                            if (heading.isNotEmpty()) {
                                MarkdownEngine.extractEmbeddedSection(targetNote.content, heading)
                            } else {
                                MarkdownEngine.extractSnippet(targetNote.content, "", 200)
                            }
                        } else {
                            trText("点击创建或打开关联笔记")
                        }
                        Text(
                            text = excerpt,
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor(),
                            maxLines = 5,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                "image" -> {
                    LexiMarkdownImageCard(
                        alt = block.text,
                        rawUrl = block.meta,
                        palette = palette
                    )
                }
                "divider" -> {
                    HorizontalDivider(color = palette.stroke.toComposeColor())
                }
                else -> {
                    LexiRichInlineText(
                        text = block.text,
                        palette = palette,
                        fontSize = (14 * fontSizeScale).sp,
                        onWikiLinkClick = onWikiLinkClick,
                        onTagClick = onTagClick
                    )
                }
            }
        }
    }
}

@Composable
private fun LexiMarkdownImageCard(
    alt: String,
    rawUrl: String,
    palette: LexiThemePalette
) {
    val resolvedPath = remember(rawUrl) {
        MarkdownEngine.resolveImageSource(rawUrl, LexiStorageService.activeLocalRootPath())
    }
    val bitmap = remember(resolvedPath) {
        try {
            val clean = resolvedPath.removePrefix("file://")
            val file = File(clean)
            if (file.exists()) {
                BitmapFactory.decodeFile(file.absolutePath)?.asImageBitmap()
            } else null
        } catch (_: Exception) {
            null
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(palette.surface_soft.toComposeColor())
            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(14.dp))
            .padding(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap,
                contentDescription = alt,
                contentScale = ContentScale.FillWidth,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 220.dp)
                    .clip(RoundedCornerShape(10.dp))
            )
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(vertical = 8.dp)
            ) {
                LexiIcon(name = "markdown", size = 18.dp, palette = palette)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = alt.ifBlank { rawUrl },
                    fontSize = 12.sp,
                    color = palette.text_secondary.toComposeColor()
                )
            }
        }
        if (alt.isNotBlank()) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = alt,
                fontSize = 11.sp,
                color = palette.text_muted.toComposeColor()
            )
        }
    }
}

@Composable
fun LexiRichInlineText(
    text: String,
    palette: LexiThemePalette,
    fontSize: TextUnit = 14.sp,
    fontWeight: FontWeight = FontWeight.Normal,
    color: Color = palette.text_primary.toComposeColor(),
    strikethrough: Boolean = false,
    onWikiLinkClick: (String) -> Unit,
    onTagClick: (String) -> Unit
) {
    val spans = remember(text) { MarkdownEngine.inlineSpans(text) }
    val firstWiki = remember(spans) { spans.firstOrNull { it.kind == "wikilink" } }
    val firstTag = remember(spans) { spans.firstOrNull { it.kind == "tag" } }

    val annotated = remember(spans, palette, color, strikethrough) {
        buildAnnotatedString {
            spans.forEach { sp ->
                when (sp.kind) {
                    "bold" -> withStyle(SpanStyle(color = color, fontWeight = FontWeight.Bold)) {
                        append(sp.text)
                    }
                    "italic" -> withStyle(SpanStyle(color = color, fontStyle = FontStyle.Italic)) {
                        append(sp.text)
                    }
                    "code" -> withStyle(
                        SpanStyle(
                            color = palette.brand.toComposeColor(),
                            background = palette.surface_soft.toComposeColor(),
                            fontFamily = FontFamily.Monospace
                        )
                    ) {
                        append(" ${sp.text} ")
                    }
                    "highlight" -> withStyle(
                        SpanStyle(
                            color = palette.text_primary.toComposeColor(),
                            background = Color(0x44ECC94B),
                            fontWeight = FontWeight.Medium
                        )
                    ) {
                        append(sp.text)
                    }
                    "strike" -> withStyle(
                        SpanStyle(
                            color = palette.text_muted.toComposeColor(),
                            textDecoration = TextDecoration.LineThrough
                        )
                    ) {
                        append(sp.text)
                    }
                    "math" -> withStyle(
                        SpanStyle(
                            color = palette.brand.toComposeColor(),
                            background = palette.brand_soft.toComposeColor(),
                            fontFamily = FontFamily.Serif,
                            fontStyle = FontStyle.Italic
                        )
                    ) {
                        append(" ${LexiMathSyntax.formatReadableMath(sp.text)} ")
                    }
                    "wikilink" -> withStyle(
                        SpanStyle(
                            color = palette.brand.toComposeColor(),
                            background = palette.brand_soft.toComposeColor(),
                            fontWeight = FontWeight.Bold,
                            textDecoration = TextDecoration.Underline
                        )
                    ) {
                        append("[[${sp.text}]]")
                    }
                    "tag" -> withStyle(
                        SpanStyle(
                            color = palette.brand.toComposeColor(),
                            fontWeight = FontWeight.Medium
                        )
                    ) {
                        append("#${sp.text}")
                    }
                    "link" -> withStyle(
                        SpanStyle(
                            color = palette.brand.toComposeColor(),
                            textDecoration = TextDecoration.Underline
                        )
                    ) {
                        append(sp.text)
                    }
                    else -> withStyle(
                        SpanStyle(
                            color = color,
                            textDecoration = if (strikethrough) TextDecoration.LineThrough else TextDecoration.None
                        )
                    ) {
                        append(sp.text)
                    }
                }
            }
        }
    }

    Column {
        Text(
            text = annotated,
            fontSize = fontSize,
            fontWeight = fontWeight,
            lineHeight = (fontSize.value * 1.48f).sp,
            modifier = if (firstWiki != null || firstTag != null) {
                Modifier.clickable {
                    if (firstWiki != null) {
                        onWikiLinkClick(firstWiki.target.ifEmpty { firstWiki.text })
                    } else if (firstTag != null) {
                        onTagClick(firstTag.target.ifEmpty { firstTag.text })
                    }
                }
            } else Modifier
        )
    }
}

@Composable
fun LexiLiveMarkdownEditor(
    bodyText: String,
    palette: LexiThemePalette,
    fontSizeScale: Float = 1f,
    onBodyChange: (String) -> Unit,
    onWikiLinkClick: (String) -> Unit,
    onTagClick: (String) -> Unit
) {
    val lines = remember(bodyText) { bodyText.split("\n") }
    var activeLineIndex by remember { mutableIntStateOf(max(0, lines.lastIndex)) }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        lines.forEachIndexed { index, rawLine ->
            val isEditingLine = index == activeLineIndex
            if (isEditingLine) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(palette.surface_soft.toComposeColor())
                        .border(1.dp, palette.brand.toComposeColor(), RoundedCornerShape(10.dp))
                        .padding(horizontal = 10.dp, vertical = 8.dp)
                ) {
                    BasicTextField(
                        value = rawLine,
                        onValueChange = { updatedLine ->
                            val mutable = lines.toMutableList()
                            if (index in mutable.indices) {
                                mutable[index] = updatedLine
                                val joined = mutable.joinToString("\n")
                                onBodyChange(joined)
                                if (updatedLine.contains("\n")) {
                                    activeLineIndex = index + 1
                                }
                            }
                        },
                        textStyle = TextStyle(
                            color = palette.text_primary.toComposeColor(),
                            fontSize = (15 * fontSizeScale).sp,
                            lineHeight = (22 * fontSizeScale).sp
                        ),
                        cursorBrush = SolidColor(palette.brand.toComposeColor()),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } else {
                val info = remember(rawLine) { LexiLiveMarkdown.classifyLine(rawLine) }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { activeLineIndex = index }
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    when (info.kind) {
                        "heading" -> {
                            val hSize = when (info.level) {
                                1 -> (21 * fontSizeScale).sp
                                2 -> (18 * fontSizeScale).sp
                                else -> (16 * fontSizeScale).sp
                            }
                            LexiRichInlineText(
                                text = info.displayText,
                                palette = palette,
                                fontSize = hSize,
                                fontWeight = FontWeight.Bold,
                                onWikiLinkClick = onWikiLinkClick,
                                onTagClick = onTagClick
                            )
                        }
                        "task" -> {
                            Checkbox(
                                checked = info.checked,
                                onCheckedChange = { checked ->
                                    val updated = LexiLiveMarkdown.toggleTaskLine(bodyText, index, checked)
                                    onBodyChange(updated)
                                },
                                colors = CheckboxDefaults.colors(
                                    checkedColor = palette.brand.toComposeColor()
                                ),
                                modifier = Modifier.size(20.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            LexiRichInlineText(
                                text = info.displayText,
                                palette = palette,
                                fontSize = (14 * fontSizeScale).sp,
                                strikethrough = false,
                                onWikiLinkClick = onWikiLinkClick,
                                onTagClick = onTagClick
                            )
                        }
                        "bullet" -> {
                            Text(
                                text = "•  ",
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                            LexiRichInlineText(
                                text = info.displayText,
                                palette = palette,
                                fontSize = (14 * fontSizeScale).sp,
                                onWikiLinkClick = onWikiLinkClick,
                                onTagClick = onTagClick
                            )
                        }
                        "quote" -> {
                            Box(
                                modifier = Modifier
                                    .width(3.dp)
                                    .height(18.dp)
                                    .background(palette.brand.toComposeColor())
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            LexiRichInlineText(
                                text = info.displayText,
                                palette = palette,
                                fontSize = (14 * fontSizeScale).sp,
                                color = palette.text_secondary.toComposeColor(),
                                onWikiLinkClick = onWikiLinkClick,
                                onTagClick = onTagClick
                            )
                        }
                        "divider" -> {
                            HorizontalDivider(color = palette.stroke.toComposeColor())
                        }
                        else -> {
                            if (rawLine.isBlank()) {
                                Spacer(modifier = Modifier.height(14.dp))
                            } else {
                                LexiRichInlineText(
                                    text = rawLine,
                                    palette = palette,
                                    fontSize = (14 * fontSizeScale).sp,
                                    onWikiLinkClick = onWikiLinkClick,
                                    onTagClick = onTagClick
                                )
                            }
                        }
                    }
                }
            }
        }

        // Quick append line area at bottom
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(32.dp)
                .clickable {
                    onBodyChange(if (bodyText.isEmpty()) "" else "$bodyText\n")
                    activeLineIndex = lines.size
                },
            contentAlignment = Alignment.CenterStart
        ) {
            Text(
                text = trText("+ 点击继续输入新行..."),
                fontSize = 12.sp,
                color = palette.text_muted.toComposeColor()
            )
        }
    }
}
