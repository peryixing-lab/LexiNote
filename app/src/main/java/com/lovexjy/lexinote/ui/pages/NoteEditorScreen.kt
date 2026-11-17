package com.lovexjy.lexinote.ui.pages

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lovexjy.lexinote.core.*
import com.lovexjy.lexinote.ui.components.*

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NoteEditorScreen(
    initialNote: NoteItem,
    allNotes: List<NoteItem>,
    allLinks: List<NoteLink>,
    allMindMaps: List<MindMapDoc>,
    allTags: List<TagCount>,
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onNoteSaved: (NoteItem) -> Unit,
    onOpenLinkedNote: (NoteItem) -> Unit,
    onOpenMindMap: (MindMapDoc) -> Unit,
    onConvertToMindMap: (NoteItem) -> Unit,
    onExportMarkdown: (NoteItem) -> Unit,
    onSelectTagAndJump: (String) -> Unit
) {
    val context = LocalContext.current
    var note by remember(initialNote.id) { mutableStateOf(initialNote.copy()) }
    var title by remember(initialNote.id) { mutableStateOf(initialNote.title) }
    var content by remember(initialNote.id) { mutableStateOf(initialNote.content) }
    var tags by remember(initialNote.id) { mutableStateOf<List<String>>(initialNote.tags) }
    var properties by remember(initialNote.id) { mutableStateOf<List<NoteProperty>>(initialNote.properties) }
    var pinned by remember(initialNote.id) { mutableStateOf(initialNote.pinned) }
    var favorite by remember(initialNote.id) { mutableStateOf(initialNote.favorite) }

    var undoStack by remember(initialNote.id) { mutableStateOf(listOf<String>()) }
    var redoStack by remember(initialNote.id) { mutableStateOf(listOf<String>()) }

    var editorMode by remember {
        mutableStateOf(
            when (LexiStorageService.getDefaultEditorViewMode()) {
                "reading" -> "reading"
                "source" -> "source"
                else -> "live"
            }
        )
    }
    var toolbarTier by remember { mutableStateOf(LexiStorageService.getNoteToolbarMode()) }
    var showMobileTools by remember { mutableStateOf(false) }
    var mobileToolsTab by remember { mutableStateOf("format") } // "format" or "panels"

    var showPropsPanel by remember { mutableStateOf(false) }
    var showOutlinePanel by remember { mutableStateOf(false) }
    var showRelationsPanel by remember { mutableStateOf(false) }
    var completionActive by remember(initialNote.id) { mutableStateOf(false) }
    var showHistoryDialog by remember { mutableStateOf(false) }
    var showAssistantDialog by remember { mutableStateOf(false) }
    var assistantInitialTab by remember { mutableStateOf("voice") }

    var newTagInput by remember { mutableStateOf("") }
    var newPropKey by remember { mutableStateOf("") }
    var newPropVal by remember { mutableStateOf("") }

    var recoveryWal by remember(initialNote.id) {
        mutableStateOf(LexiStorageService.getDraftWal(initialNote.id))
    }

    val fontSizeScale = remember {
        (LexiStorageService.getEditorFontSize().coerceIn(13, 24)) / 16f
    }

    val parsedFrontmatter = remember(content) { LexiFrontmatter.parse(content) }
    val bodyText = parsedFrontmatter.body
    val outline = remember(content) { MarkdownEngine.extractOutline(content) }
    val wordCount = remember(bodyText) {
        bodyText.replace(Regex("\\s+"), "").length
    }
    val hasUnclosedMath = remember(bodyText) { LexiMathSyntax.hasUnclosedMath(bodyText) }

    val completionCtx = remember(content, completionActive) {
        if (completionActive) LexiCompletion.context(content, content.length) else null
    }
    val completionCandidates = remember(completionCtx, allNotes, allTags, note.id) {
        if (completionCtx != null) {
            LexiCompletion.candidates(completionCtx, allNotes, allTags, note.id, 8)
        } else emptyList()
    }

    fun pushUndoAndUpdateContent(nextContent: String, fromTyping: Boolean = false) {
        if (nextContent == content) return
        undoStack = (undoStack + content).takeLast(30)
        redoStack = emptyList()
        content = nextContent
        completionActive = fromTyping && LexiCompletion.context(nextContent, nextContent.length) != null
        LexiStorageService.saveDraftWal(note.id, title, nextContent)
    }

    fun updateBody(nextBody: String) {
        val nextFull = LexiFrontmatter.apply(
            nextBody,
            properties,
            tags,
            parsedFrontmatter.hasBlock || properties.isNotEmpty()
        )
        pushUndoAndUpdateContent(nextFull, fromTyping = true)
    }

    fun insertSnippet(snippet: String) {
        val updated = if (content.endsWith("\n") || content.isEmpty()) {
            content + snippet
        } else {
            "$content\n$snippet"
        }
        pushUndoAndUpdateContent(updated)
    }

    fun saveNow(reason: String = "auto"): NoteItem {
        val syncedFull = LexiFrontmatter.apply(
            LexiFrontmatter.parse(content).body,
            properties,
            tags,
            parsedFrontmatter.hasBlock || properties.isNotEmpty()
        )
        val updated = note.copy(
            title = title.ifBlank { trText("未命名笔记") },
            content = syncedFull,
            tags = tags.toMutableList(),
            properties = properties.toMutableList(),
            pinned = pinned,
            favorite = favorite,
            updatedAt = System.currentTimeMillis()
        )
        val saved = LexiStorageService.saveNote(updated, reason)
        LexiStorageService.clearDraftWal(saved.id)
        note = saved
        onNoteSaved(saved)
        return saved
    }

    val imagePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes != null) {
                    val relPath = LexiStorageService.saveAttachmentImage("img.png", bytes)
                    insertSnippet("![图片]($relPath)")
                }
            } catch (_: Exception) {
            }
        }
    }

    val relatedContents = remember(note, content, allNotes, allLinks, allMindMaps) {
        val tempNote = note.copy(title = title, content = content, tags = tags.toMutableList())
        val liveLinks = MarkdownEngine.buildNoteLinks(
            allNotes.map { if (it.id == tempNote.id) tempNote else it }
        )
        LexiRelations.contents(tempNote, allNotes, liveLinks, allMindMaps)
    }
    val unlinkedMentions = remember(note, title, content, allNotes) {
        val tempNote = note.copy(title = title, content = content)
        MarkdownEngine.findUnlinkedMentions(tempNote, allNotes)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.surface_card.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("笔记"),
            subtitle = "",
            rightText = "",
            palette = palette,
            onBack = {
                saveNow("manual")
                onBack()
            }
        )

        // Crash Recovery Banner
        if (recoveryWal != null && recoveryWal!!.content != content) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 4.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color(0x22D69E2E))
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = trText("检测到未同步草稿"),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = formatTimeShort(recoveryWal!!.updatedAt),
                        fontSize = 11.sp,
                        color = palette.text_secondary.toComposeColor()
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SmallControlChip(
                        text = trText("忽略"),
                        palette = palette,
                        onClick = {
                            LexiStorageService.clearDraftWal(note.id)
                            recoveryWal = null
                        }
                    )
                    SmallControlChip(
                        text = trText("恢复草稿"),
                        palette = palette,
                        active = true,
                        onClick = {
                            val wal = recoveryWal!!
                            title = wal.title
                            content = wal.content
                            LexiStorageService.clearDraftWal(note.id)
                            recoveryWal = null
                        }
                    )
                }
            }
        }

        // Scrollable Pure White Writing Canvas (matches NoteEditorPage.ets)
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            // Editable Borderless Title
            Box(modifier = Modifier.fillMaxWidth()) {
                if (title.isEmpty()) {
                    Text(
                        text = trText("标题（选填）"),
                        fontSize = 25.sp,
                        fontWeight = FontWeight.Bold,
                        lineHeight = 32.sp,
                        color = palette.text_muted.toComposeColor().copy(alpha = 0.7f)
                    )
                }
                BasicTextField(
                    value = title,
                    onValueChange = { title = it },
                    readOnly = editorMode == "reading",
                    textStyle = TextStyle(
                        color = palette.text_primary.toComposeColor(),
                        fontSize = 25.sp,
                        fontWeight = FontWeight.Bold,
                        lineHeight = 32.sp
                    ),
                    cursorBrush = SolidColor(palette.brand.toComposeColor()),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (hasUnclosedMath) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0x22D69E2E))
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = trText("提示：当前存在未闭合的 \$ 或 \$\$ 数学公式标记"),
                        fontSize = 11.sp,
                        color = Color(0xFFD69E2E)
                    )
                }
                Spacer(modifier = Modifier.height(10.dp))
            }

            // Editor Body by Mode
            when (editorMode) {
                "reading" -> {
                    LexiMarkdownPreview(
                        markdown = content,
                        allNotes = allNotes,
                        palette = palette,
                        fontSizeScale = fontSizeScale,
                        onWikiLinkClick = { rawTarget ->
                            val targetTitle = rawTarget.substringBefore("#").substringBefore("|").trim()
                            val found = allNotes.firstOrNull {
                                it.title.equals(targetTitle, ignoreCase = true)
                            }
                            if (found != null) {
                                saveNow("auto")
                                onOpenLinkedNote(found)
                            } else {
                                val created = LexiStorageService.createNote(
                                    title = targetTitle,
                                    content = "# $targetTitle\n\n",
                                    vaultId = note.vaultId,
                                    projectId = note.projectId
                                )
                                saveNow("auto")
                                onOpenLinkedNote(created)
                            }
                        },
                        onTagClick = onSelectTagAndJump,
                        onToggleTask = { lineIdx, checked ->
                            val updatedBody = LexiLiveMarkdown.toggleTaskLine(bodyText, lineIdx, checked)
                            updateBody(updatedBody)
                        }
                    )
                }
                "source" -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 360.dp)
                    ) {
                        if (content.isEmpty()) {
                            Text(
                                text = trText("输入 Markdown 源码，支持 [[双链]]、#标签、\$公式\$..."),
                                fontSize = (15 * fontSizeScale).sp,
                                color = palette.text_muted.toComposeColor()
                            )
                        }
                        BasicTextField(
                            value = content,
                            onValueChange = { pushUndoAndUpdateContent(it, fromTyping = true) },
                            textStyle = TextStyle(
                                color = palette.text_primary.toComposeColor(),
                                fontSize = (15 * fontSizeScale).sp,
                                fontFamily = FontFamily.Monospace,
                                lineHeight = (22 * fontSizeScale).sp
                            ),
                            cursorBrush = SolidColor(palette.brand.toComposeColor()),
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 360.dp)
                        )
                    }
                }
                "split" -> {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 160.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(palette.surface_soft.toComposeColor())
                                .padding(12.dp)
                        ) {
                            BasicTextField(
                                value = content,
                                onValueChange = { pushUndoAndUpdateContent(it, fromTyping = true) },
                                textStyle = TextStyle(
                                    color = palette.text_primary.toComposeColor(),
                                    fontSize = (14 * fontSizeScale).sp,
                                    fontFamily = FontFamily.Monospace,
                                    lineHeight = (20 * fontSizeScale).sp
                                ),
                                cursorBrush = SolidColor(palette.brand.toComposeColor()),
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        HorizontalDivider(color = palette.divider.toComposeColor())
                        LexiMarkdownPreview(
                            markdown = content,
                            allNotes = allNotes,
                            palette = palette,
                            fontSizeScale = fontSizeScale,
                            onWikiLinkClick = { rawTarget ->
                                val targetTitle = rawTarget.substringBefore("#").substringBefore("|").trim()
                                allNotes.firstOrNull {
                                    it.title.equals(targetTitle, ignoreCase = true)
                                }?.let {
                                    saveNow("auto")
                                    onOpenLinkedNote(it)
                                }
                            },
                            onTagClick = onSelectTagAndJump
                        )
                    }
                }
                else -> {
                    // "live" mode
                    LexiLiveMarkdownEditor(
                        bodyText = bodyText,
                        palette = palette,
                        fontSizeScale = fontSizeScale,
                        onBodyChange = { updateBody(it) },
                        onWikiLinkClick = { rawTarget ->
                            val targetTitle = rawTarget.substringBefore("#").substringBefore("|").trim()
                            val found = allNotes.firstOrNull {
                                it.title.equals(targetTitle, ignoreCase = true)
                            }
                            if (found != null) {
                                saveNow("auto")
                                onOpenLinkedNote(found)
                            } else {
                                val created = LexiStorageService.createNote(
                                    title = targetTitle,
                                    content = "# $targetTitle\n\n",
                                    vaultId = note.vaultId,
                                    projectId = note.projectId
                                )
                                saveNow("auto")
                                onOpenLinkedNote(created)
                            }
                        },
                        onTagClick = onSelectTagAndJump
                    )
                }
            }

            Spacer(modifier = Modifier.height(64.dp))
        }

        // Active Completion Suggestions Tray above Bottom Bar
        if (completionActive && completionCtx != null && completionCandidates.isNotEmpty() && editorMode != "reading") {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(palette.surface_soft.toComposeColor())
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = if (completionCtx.kind == "tag") trText("补全标签 #") else trText("补全双链 [["),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                    Text(
                        text = "×",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_muted.toComposeColor(),
                        modifier = Modifier.clickable { completionActive = false }
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    completionCandidates.forEach { cand ->
                        SmallControlChip(
                            text = cand.label,
                            palette = palette,
                            active = true,
                            onClick = {
                                val edit = LexiCompletion.apply(content, completionCtx, cand)
                                pushUndoAndUpdateContent(edit.text, fromTyping = false)
                                completionActive = false
                            }
                        )
                    }
                }
            }
        }

        // Slide-up Tray: Properties & Tags
        if (showPropsPanel) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 320.dp)
                    .verticalScroll(rememberScrollState())
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(palette.bg_root.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${trText("属性与标签")} (${tags.size + properties.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("收起"),
                        fontSize = 12.sp,
                        color = palette.brand.toComposeColor(),
                        modifier = Modifier.clickable { showPropsPanel = false }
                    )
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    tags.forEach { tag ->
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(palette.brand_soft.toComposeColor())
                                .padding(horizontal = 10.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "#$tag",
                                fontSize = 12.sp,
                                color = palette.brand.toComposeColor(),
                                modifier = Modifier.clickable { onSelectTagAndJump(tag) }
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = "×",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_muted.toComposeColor(),
                                modifier = Modifier.clickable {
                                    tags = tags.filterNot { it == tag }
                                }
                            )
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(38.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_card.toComposeColor())
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        if (newTagInput.isEmpty()) {
                            Text(trText("添加标签 (支持 a/b 多级)"), fontSize = 12.sp, color = palette.text_muted.toComposeColor())
                        }
                        BasicTextField(
                            value = newTagInput,
                            onValueChange = { newTagInput = it },
                            singleLine = true,
                            textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 13.sp),
                            cursorBrush = SolidColor(palette.brand.toComposeColor()),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    SmallControlChip(
                        text = trText("+ 添加"),
                        palette = palette,
                        active = true,
                        onClick = {
                            val clean = newTagInput.trim().removePrefix("#")
                            if (clean.isNotEmpty() && !tags.contains(clean)) {
                                tags = tags + clean
                                newTagInput = ""
                            }
                        }
                    )
                }

                Text(
                    text = trText("YAML Frontmatter 属性"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_secondary.toComposeColor()
                )
                properties.forEachIndexed { pIdx, prop ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "${prop.key}: ${prop.value}",
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = palette.text_primary.toComposeColor()
                        )
                        Text(
                            text = trText("删除"),
                            fontSize = 11.sp,
                            color = palette.danger.toComposeColor(),
                            modifier = Modifier.clickable {
                                properties = properties.filterIndexed { i, _ -> i != pIdx }
                            }
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(36.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(palette.surface_card.toComposeColor())
                            .padding(horizontal = 10.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        if (newPropKey.isEmpty()) Text("key", fontSize = 12.sp, color = palette.text_muted.toComposeColor())
                        BasicTextField(
                            value = newPropKey,
                            onValueChange = { newPropKey = it },
                            singleLine = true,
                            textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 12.sp),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(36.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(palette.surface_card.toComposeColor())
                            .padding(horizontal = 10.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        if (newPropVal.isEmpty()) Text("value", fontSize = 12.sp, color = palette.text_muted.toComposeColor())
                        BasicTextField(
                            value = newPropVal,
                            onValueChange = { newPropVal = it },
                            singleLine = true,
                            textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 12.sp),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    SmallControlChip(
                        text = "+",
                        palette = palette,
                        active = true,
                        onClick = {
                            if (newPropKey.isNotBlank()) {
                                properties = properties + NoteProperty(
                                    key = newPropKey.trim(),
                                    type = "text",
                                    value = newPropVal.trim()
                                )
                                newPropKey = ""
                                newPropVal = ""
                            }
                        }
                    )
                }
            }
        }

        // Slide-up Tray: Document Outline
        if (showOutlinePanel) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 260.dp)
                    .verticalScroll(rememberScrollState())
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(palette.bg_root.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${trText("文档大纲")} (${outline.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("收起"),
                        fontSize = 12.sp,
                        color = palette.brand.toComposeColor(),
                        modifier = Modifier.clickable { showOutlinePanel = false }
                    )
                }
                if (outline.isEmpty()) {
                    Text(
                        text = trText("正文使用 # / ## / ### 标题后将自动生成章节目录"),
                        fontSize = 12.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                } else {
                    outline.forEach { item ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = ((item.level - 1) * 12).dp, top = 4.dp, bottom = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "H${item.level}",
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = item.text,
                                fontSize = 13.sp,
                                color = palette.text_primary.toComposeColor(),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }

        // Slide-up Tray: Relations & Backlinks
        if (showRelationsPanel) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 320.dp)
                    .verticalScroll(rememberScrollState())
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(palette.bg_root.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${trText("知识关联与反向引用")} (${relatedContents.outgoingNotes.size + relatedContents.backlinkNotes.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("收起"),
                        fontSize = 12.sp,
                        color = palette.brand.toComposeColor(),
                        modifier = Modifier.clickable { showRelationsPanel = false }
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${relatedContents.outgoingNotes.size} 处正向引用 · ${relatedContents.backlinkNotes.size} 处反向链接",
                        fontSize = 12.sp,
                        color = palette.text_secondary.toComposeColor()
                    )
                    SmallControlChip(
                        text = trText("生成导图"),
                        palette = palette,
                        active = true,
                        onClick = {
                            val saved = saveNow("auto")
                            onConvertToMindMap(saved)
                        }
                    )
                }

                if (relatedContents.outgoingNotes.isNotEmpty()) {
                    Text(trText("正向引用"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = palette.text_primary.toComposeColor())
                    relatedContents.outgoingNotes.forEach { target ->
                        RelationNoteRow(target, palette) {
                            saveNow("auto")
                            onOpenLinkedNote(target)
                        }
                    }
                }
                if (relatedContents.backlinkNotes.isNotEmpty()) {
                    Text(trText("反向链接"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = palette.text_primary.toComposeColor())
                    relatedContents.backlinkNotes.forEach { src ->
                        RelationNoteRow(src, palette) {
                            saveNow("auto")
                            onOpenLinkedNote(src)
                        }
                    }
                }
                if (relatedContents.mindMaps.isNotEmpty()) {
                    Text(trText("关联思维导图"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = palette.text_primary.toComposeColor())
                    relatedContents.mindMaps.forEach { mm ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(palette.surface_card.toComposeColor())
                                .clickable {
                                    saveNow("auto")
                                    onOpenMindMap(mm)
                                }
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            LexiIcon(name = "mindmap", size = 14.dp, palette = palette)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(text = mm.title, fontSize = 13.sp, color = palette.brand.toComposeColor())
                        }
                    }
                }
                if (unlinkedMentions.isNotEmpty()) {
                    Text(trText("潜在提及（未建立链接）"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = palette.text_primary.toComposeColor())
                    unlinkedMentions.take(4).forEach { m ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(palette.surface_card.toComposeColor())
                                .padding(10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(m.sourceTitle, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = palette.text_primary.toComposeColor())
                                Text(m.lineText, fontSize = 11.sp, color = palette.text_muted.toComposeColor(), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            SmallControlChip(
                                text = trText("建立链接"),
                                palette = palette,
                                active = true,
                                onClick = {
                                    val srcNote = allNotes.firstOrNull { it.id == m.sourceNoteId }
                                    if (srcNote != null) {
                                        val linkedContent = LexiCompletion.linkFirstMention(srcNote.content, title)
                                        LexiStorageService.saveNote(
                                            srcNote.copy(content = linkedContent, updatedAt = System.currentTimeMillis())
                                        )
                                        saveNow("auto")
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }

        // Phone Tools Popup Panel (when `showMobileTools == true`)
        if (showMobileTools) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(palette.bg_root.toComposeColor())
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        SmallControlChip(
                            text = trText("格式"),
                            palette = palette,
                            active = mobileToolsTab == "format",
                            onClick = { mobileToolsTab = "format" }
                        )
                        SmallControlChip(
                            text = trText("面板与视图"),
                            palette = palette,
                            active = mobileToolsTab == "panels",
                            onClick = { mobileToolsTab = "panels" }
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(
                            "minimal" to "简洁",
                            "study" to "学习",
                            "pro" to "专业"
                        ).forEach { (tier, label) ->
                            SmallControlChip(
                                text = trText(label),
                                palette = palette,
                                active = toolbarTier == tier,
                                onClick = {
                                    toolbarTier = tier
                                    LexiStorageService.setNoteToolbarMode(tier)
                                }
                            )
                        }
                    }
                }

                if (mobileToolsTab == "format") {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        SmallControlChip(text = trText("撤销"), palette = palette) {
                            if (undoStack.isNotEmpty()) {
                                val prev = undoStack.last()
                                undoStack = undoStack.dropLast(1)
                                redoStack = redoStack + content
                                content = prev
                            }
                        }
                        SmallControlChip(text = trText("重做"), palette = palette) {
                            if (redoStack.isNotEmpty()) {
                                val next = redoStack.last()
                                redoStack = redoStack.dropLast(1)
                                undoStack = undoStack + content
                                content = next
                            }
                        }
                        SmallControlChip(text = "H1", palette = palette) { insertSnippet("# ") }
                        SmallControlChip(text = "H2", palette = palette) { insertSnippet("## ") }
                        SmallControlChip(text = "H3", palette = palette) { insertSnippet("### ") }
                        SmallControlChip(text = trText("加粗"), palette = palette) { insertSnippet("**重点**") }
                        SmallControlChip(text = trText("列表"), palette = palette) { insertSnippet("- ") }
                        SmallControlChip(text = trText("待办"), palette = palette) { insertSnippet("- [ ] ") }
                        SmallControlChip(text = trText("双链 [["), palette = palette) { insertSnippet("[[") }
                        SmallControlChip(text = trText("代码块"), palette = palette) {
                            insertSnippet("```kotlin\n\n```")
                        }
                        SmallControlChip(text = trText("插入图片"), palette = palette) {
                            imagePickerLauncher.launch("image/*")
                        }

                        if (toolbarTier == "study" || toolbarTier == "pro") {
                            SmallControlChip(text = trText("斜体"), palette = palette) { insertSnippet("*斜体*") }
                            SmallControlChip(text = trText("高亮 =="), palette = palette) { insertSnippet("==高亮内容==") }
                            SmallControlChip(text = trText("引用 >"), palette = palette) { insertSnippet("> ") }
                            SmallControlChip(text = trText("行内公式 \$"), palette = palette) { insertSnippet("\$E = mc^2\$") }
                            SmallControlChip(text = trText("公式块 \$\$"), palette = palette) {
                                insertSnippet("$$\n\\sum_{i=1}^{n} x_i\n$$")
                            }
                            SmallControlChip(text = trText("提示块"), palette = palette) {
                                insertSnippet("> [!NOTE]\n> 重点提示内容")
                            }
                            SmallControlChip(text = trText("表格"), palette = palette) {
                                insertSnippet("| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |")
                            }
                        }

                        if (toolbarTier == "pro") {
                            SmallControlChip(text = trText("分割线"), palette = palette) { insertSnippet("---") }
                            SmallControlChip(text = trText("嵌入 ![[ "), palette = palette) { insertSnippet("![[") }
                            SmallControlChip(text = trText("时间戳"), palette = palette) {
                                insertSnippet(formatTimeShort(System.currentTimeMillis()))
                            }
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            listOf(
                                "live" to "实时预览",
                                "source" to "源码编辑",
                                "split" to "分栏对照",
                                "reading" to "沉浸阅读"
                            ).forEach { (m, label) ->
                                SmallControlChip(
                                    text = trText(label),
                                    palette = palette,
                                    active = editorMode == m,
                                    onClick = { editorMode = m }
                                )
                            }
                        }
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            SmallControlChip(
                                text = if (pinned) "📌 ${trText("已置顶")}" else trText("置顶"),
                                palette = palette,
                                active = pinned,
                                onClick = {
                                    pinned = !pinned
                                    saveNow("auto")
                                }
                            )
                            SmallControlChip(
                                text = if (favorite) "★ ${trText("已收藏")}" else trText("收藏"),
                                palette = palette,
                                active = favorite,
                                onClick = {
                                    favorite = !favorite
                                    saveNow("auto")
                                }
                            )
                            SmallControlChip(
                                text = trText("整理"),
                                palette = palette,
                                onClick = {
                                    showMobileTools = false
                                    assistantInitialTab = "arrange"
                                    showAssistantDialog = true
                                }
                            )
                            SmallControlChip(
                                text = trText("属性与标签"),
                                palette = palette,
                                active = showPropsPanel,
                                onClick = {
                                    showPropsPanel = !showPropsPanel
                                    showOutlinePanel = false
                                    showRelationsPanel = false
                                }
                            )
                            SmallControlChip(
                                text = trText("知识关联"),
                                palette = palette,
                                active = showRelationsPanel,
                                onClick = {
                                    showRelationsPanel = !showRelationsPanel
                                    showPropsPanel = false
                                    showOutlinePanel = false
                                }
                            )
                            SmallControlChip(
                                text = trText("版本历史"),
                                palette = palette,
                                onClick = {
                                    showMobileTools = false
                                    saveNow("auto")
                                    showHistoryDialog = true
                                }
                            )
                            SmallControlChip(
                                text = trText("转为导图"),
                                palette = palette,
                                onClick = {
                                    showMobileTools = false
                                    val saved = saveNow("auto")
                                    onConvertToMindMap(saved)
                                }
                            )
                            SmallControlChip(
                                text = trText("导出 .md"),
                                palette = palette,
                                onClick = {
                                    showMobileTools = false
                                    val saved = saveNow("auto")
                                    onExportMarkdown(saved)
                                }
                            )
                        }
                    }
                }
            }
        }

        // Bottom Phone Writing Bar (Matches `NoteEditorPage.ets` 48dp clean phone bar)
        HorizontalDivider(thickness = 0.5.dp, color = palette.divider.toComposeColor().copy(alpha = 0.7f))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .background(palette.surface_card.toComposeColor())
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (showMobileTools) palette.brand_soft.toComposeColor() else Color.Transparent)
                        .clickable { showMobileTools = !showMobileTools }
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = trText("工具"),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (showMobileTools) palette.brand.toComposeColor() else palette.text_primary.toComposeColor()
                    )
                }
                Row(
                    modifier = Modifier.clickable {
                        assistantInitialTab = "voice"
                        showAssistantDialog = true
                    },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    LexiIcon(name = "mic", size = 16.dp, muted = true, palette = palette)
                    Text(
                        text = trText("语音记录"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.text_secondary.toComposeColor()
                    )
                }
                Row(
                    modifier = Modifier.clickable {
                        showOutlinePanel = !showOutlinePanel
                        if (showOutlinePanel) {
                            showPropsPanel = false
                            showRelationsPanel = false
                        }
                    },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    LexiIcon(name = "outline", size = 16.dp, muted = !showOutlinePanel, palette = palette)
                    Text(
                        text = trText("大纲"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (showOutlinePanel) palette.brand.toComposeColor() else palette.text_secondary.toComposeColor()
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = "$wordCount ${trText("字")}",
                    fontSize = 12.sp,
                    color = palette.text_muted.toComposeColor()
                )
                Box(
                    modifier = Modifier
                        .height(28.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(
                            if (editorMode == "reading") palette.brand.toComposeColor()
                            else palette.surface_soft.toComposeColor()
                        )
                        .clickable {
                            editorMode = if (editorMode == "reading") "live" else "reading"
                        }
                        .padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (editorMode == "reading") trText("继续编辑") else trText("阅读"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (editorMode == "reading") palette.inverse_text.toComposeColor()
                        else palette.text_primary.toComposeColor()
                    )
                }
            }
        }
    }

    if (showHistoryDialog) {
        LexiHistoryDialog(
            note = note.copy(
                title = title,
                content = content,
                tags = tags.toMutableList(),
                properties = properties.toMutableList()
            ),
            palette = palette,
            onDismiss = { showHistoryDialog = false },
            onCreateSnapshot = {
                val saved = saveNow("manual")
                LexiStorageService.createManualRevision(saved.id)
            },
            onRestoreRevision = { rev ->
                val restored = LexiStorageService.restoreNoteRevision(note.id, rev.id)
                if (restored != null) {
                    note = restored
                    title = restored.title
                    content = restored.content
                    tags = restored.tags
                    properties = restored.properties
                    onNoteSaved(restored)
                }
            }
        )
    }

    if (showAssistantDialog) {
        LexiCaptureAssistantDialog(
            noteTitle = title,
            noteContent = content,
            allNotes = allNotes,
            initialTab = assistantInitialTab,
            palette = palette,
            onDismiss = { showAssistantDialog = false },
            onInsertMarkdown = { snippet ->
                insertSnippet(snippet)
            },
            onAddTag = { tag ->
                if (!tags.contains(tag)) {
                    tags = tags + tag
                }
            }
        )
    }
}

@Composable
private fun RelationNoteRow(
    note: NoteItem,
    palette: LexiThemePalette,
    onClick: () -> Unit
) {
    val interaction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
    val rowShape = RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.MD)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(interaction))
            .clip(rowShape)
            .background(palette.surface_soft.toComposeColor())
            .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(interaction) { onClick() })
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LexiIcon(name = "note", size = 14.dp, palette = palette)
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = note.title,
                fontSize = 13.sp,
                color = palette.brand.toComposeColor(),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        LexiIcon(name = "chevron", size = 14.dp, muted = true, palette = palette)
    }
}
