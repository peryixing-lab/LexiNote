package com.lovexjy.lexinote.ui.tabs

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lovexjy.lexinote.core.*
import com.lovexjy.lexinote.ui.components.*
import java.util.Calendar

@Composable
fun LexiHomeTab(
    notes: List<NoteItem>,
    mindMaps: List<MindMapDoc>,
    canvases: List<CanvasBoard>,
    links: List<NoteLink>,
    vaults: List<VaultItem>,
    recentNotesMode: String,
    quickCaptureDraft: String,
    palette: LexiThemePalette,
    onQuickCaptureChange: (String) -> Unit,
    onSaveQuickCapture: () -> Unit,
    onExpandQuickCapture: () -> Unit = {},
    onOpenDailyNote: () -> Unit,
    onOpenTemplatePicker: () -> Unit,
    onOpenPluginPanel: () -> Unit,
    onRecentModeChange: (String) -> Unit,
    onOpenNote: (NoteItem) -> Unit,
    onTogglePin: (NoteItem) -> Unit,
    onToggleFavorite: (NoteItem) -> Unit,
    onDeleteNote: (NoteItem) -> Unit,
    onDuplicateNote: (NoteItem) -> Unit,
    onExportNote: (NoteItem) -> Unit,
    onSelectTag: (String) -> Unit,
    onJumpToVaultSection: (Int) -> Unit,
    onJumpToExplore: () -> Unit = {}
) {
    val vaultNameMap = remember(vaults) { vaults.associate { it.id to it.name } }
    val connectedIds = remember(links, mindMaps) {
        LexiRelations.connectedNoteIds(links, mindMaps)
    }
    val outgoingCountMap = remember(links) {
        val map = mutableMapOf<String, Int>()
        links.forEach { map[it.sourceId] = (map[it.sourceId] ?: 0) + 1 }
        map
    }
    val backlinkCountMap = remember(links) {
        val map = mutableMapOf<String, Int>()
        links.forEach { map[it.targetId] = (map[it.targetId] ?: 0) + 1 }
        map
    }
    val pinnedNotes = remember(notes) {
        notes.filter { it.pinned }.sortedByDescending { it.updatedAt }.take(3)
    }
    val recentNotes = remember(notes, recentNotesMode) {
        val nonPinned = notes.filterNot { it.pinned }
        val sorted = if (recentNotesMode == "visited") {
            nonPinned.sortedByDescending { maxOf(it.lastOpenedAt, it.updatedAt) }
        } else {
            nonPinned.sortedByDescending { it.updatedAt }
        }
        sorted.take(8)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Phone Top Quick Actions Row (matches LexiHomeTab.ets)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val actionShape = RoundedCornerShape(16.dp)
            val dailyInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
            Box(
                modifier = Modifier
                    .weight(1.2f)
                    .height(44.dp)
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(dailyInteraction))
                    .clip(actionShape)
                    .background(palette.brand.toComposeColor())
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(dailyInteraction) { onOpenDailyNote() }),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = trText("今日笔记"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.inverse_text.toComposeColor(),
                    maxLines = 1
                )
            }

            val tplInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
            Box(
                modifier = Modifier
                    .weight(1.2f)
                    .height(44.dp)
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(tplInteraction))
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = actionShape,
                            dark = palette.dark
                        )
                    )
                    .clip(actionShape)
                    .background(palette.surface_card.toComposeColor())
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(tplInteraction) { onOpenTemplatePicker() }),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = trText("从模板新建"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.brand_ink.toComposeColor(),
                    maxLines = 1
                )
            }

            val pluginInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
            Row(
                modifier = Modifier
                    .weight(0.8f)
                    .height(44.dp)
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(pluginInteraction))
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = actionShape,
                            dark = palette.dark
                        )
                    )
                    .clip(actionShape)
                    .background(palette.surface_card.toComposeColor())
                    .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(pluginInteraction) { onOpenPluginPanel() }),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                LexiIcon(name = "plugin", size = 15.dp, tint = palette.brand_ink.toComposeColor())
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = trText("插件"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.brand_ink.toComposeColor(),
                    maxLines = 1
                )
            }
        }

        // Quick Capture Card ("随手记")
        val quickShape = RoundedCornerShape(24.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = quickShape,
                        dark = palette.dark
                    )
                )
                .clip(quickShape)
                .background(palette.surface_card.toComposeColor())
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LexiIcon(name = "note", size = 18.dp, palette = palette)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = trText("随手记"),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (quickCaptureDraft.isNotBlank()) {
                        Text(
                            text = trText("清空"),
                            fontSize = 12.sp,
                            color = palette.text_muted.toComposeColor(),
                            modifier = Modifier.clickable { onQuickCaptureChange("") }
                        )
                    }
                    Text(
                        text = trText("完整编辑 →"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.brand.toComposeColor(),
                        modifier = Modifier.clickable { onExpandQuickCapture() }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 112.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(palette.surface_soft.toComposeColor())
                    .padding(14.dp)
            ) {
                if (quickCaptureDraft.isEmpty()) {
                    Text(
                        text = trText("记录想法或待办…"),
                        fontSize = 14.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
                BasicTextField(
                    value = quickCaptureDraft,
                    onValueChange = onQuickCaptureChange,
                    textStyle = TextStyle(
                        color = palette.text_primary.toComposeColor(),
                        fontSize = 14.sp,
                        lineHeight = 20.sp
                    ),
                    cursorBrush = SolidColor(palette.brand.toComposeColor()),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .height(36.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            if (quickCaptureDraft.isNotBlank()) palette.brand.toComposeColor()
                            else palette.brand.toComposeColor().copy(alpha = 0.55f)
                        )
                        .clickable(enabled = quickCaptureDraft.isNotBlank()) { onSaveQuickCapture() }
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText("随手记下"),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.inverse_text.toComposeColor()
                    )
                }
            }
        }

        // 4 Metrics Row (matches LexiHomeTab.ets order: 笔记, 链接, 导图, 白板)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MetricMiniCard(
                label = trText("笔记"),
                count = notes.size,
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { onJumpToVaultSection(0) }
            )
            MetricMiniCard(
                label = trText("链接"),
                count = links.size,
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { onJumpToExplore() }
            )
            MetricMiniCard(
                label = trText("导图"),
                count = mindMaps.size,
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { onJumpToVaultSection(1) }
            )
            MetricMiniCard(
                label = trText("白板"),
                count = canvases.size,
                palette = palette,
                modifier = Modifier.weight(1f),
                onClick = { onJumpToVaultSection(2) }
            )
        }

        // Pinned Notes Section
        if (pinnedNotes.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LexiIcon(name = "pin", size = 15.dp, palette = palette)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = trText("置顶"),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.text_primary.toComposeColor()
                        )
                    }
                    Text(
                        text = "${pinnedNotes.size}",
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.TnumCaption,
                        color = palette.text_muted.toComposeColor()
                    )
                }

                pinnedNotes.forEachIndexed { idx, note ->
                    androidx.compose.runtime.key(note.id) {
                        LexiNoteCard(
                            note = note,
                            vaultName = vaultNameMap[note.vaultId] ?: "",
                            outgoingCount = outgoingCountMap[note.id] ?: 0,
                            backlinkCount = backlinkCountMap[note.id] ?: 0,
                            isUnconnected = !connectedIds.contains(note.id),
                            palette = palette,
                            modifier = com.lovexjy.lexinote.ui.theme.LexiMotion.staggerReveal(idx),
                            onOpen = { onOpenNote(note) },
                            onTogglePin = { onTogglePin(note) },
                            onToggleFavorite = { onToggleFavorite(note) },
                            onDelete = { onDeleteNote(note) },
                            onDuplicate = { onDuplicateNote(note) },
                            onExportMarkdown = { onExportNote(note) },
                            onTagClick = onSelectTag
                        )
                    }
                }
            }
        }

        // Recent Notes Section
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = trText("最近笔记"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val modeOptions = listOf("visited" to "最近访问", "edited" to "最近编辑")
                    modeOptions.forEach { (mode, label) ->
                        val active = recentNotesMode == mode
                        Box(
                            modifier = Modifier
                                .height(26.dp)
                                .clip(RoundedCornerShape(13.dp))
                                .background(
                                    if (active) palette.brand.toComposeColor()
                                    else palette.surface_card.toComposeColor()
                                )
                                .clickable { onRecentModeChange(mode) }
                                .padding(horizontal = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = trText(label),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium,
                                color = if (active) palette.inverse_text.toComposeColor()
                                else palette.text_secondary.toComposeColor()
                            )
                        }
                    }
                    Text(
                        text = trText("全部笔记 →"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.brand.toComposeColor(),
                        modifier = Modifier
                            .padding(start = 2.dp)
                            .clickable { onJumpToVaultSection(0) }
                    )
                }
            }

            if (recentNotes.isEmpty()) {
                val emptyShape = RoundedCornerShape(20.dp)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = emptyShape,
                                dark = palette.dark
                            )
                        )
                        .clip(emptyShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText("暂无更多笔记，点击右上角 + 或「今日笔记」开始创作"),
                        fontSize = 13.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
            } else {
                recentNotes.forEach { note ->
                    LexiNoteCard(
                        note = note,
                        vaultName = vaultNameMap[note.vaultId] ?: "",
                        showAccessTime = (recentNotesMode == "visited"),
                        outgoingCount = outgoingCountMap[note.id] ?: 0,
                        backlinkCount = backlinkCountMap[note.id] ?: 0,
                        isUnconnected = !connectedIds.contains(note.id),
                        palette = palette,
                        onOpen = { onOpenNote(note) },
                        onTogglePin = { onTogglePin(note) },
                        onToggleFavorite = { onToggleFavorite(note) },
                        onDelete = { onDeleteNote(note) },
                        onDuplicate = { onDuplicateNote(note) },
                        onExportMarkdown = { onExportNote(note) },
                        onTagClick = onSelectTag
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricMiniCard(
    label: String,
    count: Int,
    palette: LexiThemePalette,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val cardShape = RoundedCornerShape(18.dp)
    val interaction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
    Column(
        modifier = modifier
            .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(interaction))
            .then(
                com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                    elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                    shape = cardShape,
                    dark = palette.dark
                )
            )
            .clip(cardShape)
            .background(palette.surface_card.toComposeColor())
            .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(interaction) { onClick() })
            .padding(vertical = 12.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.Start
    ) {
        Text(
            text = count.toString(),
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = palette.brand.toComposeColor()
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = palette.text_secondary.toComposeColor()
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LexiVaultTab(
    notes: List<NoteItem>,
    mindMaps: List<MindMapDoc>,
    canvases: List<CanvasBoard>,
    links: List<NoteLink>,
    tags: List<TagCount>,
    activeVault: VaultItem?,
    projects: List<LexiProject>,
    activeProjectId: String,
    vaultSectionIndex: Int,
    searchQuery: String,
    noteFilterMode: String,
    noteSortMode: String,
    noteViewMode: String,
    selectedTag: String,
    palette: LexiThemePalette,
    onOpenWorkspaces: () -> Unit,
    onSelectProject: (String) -> Unit,
    onSectionChange: (Int) -> Unit,
    onSearchQueryChange: (String) -> Unit,
    onFilterModeChange: (String) -> Unit,
    onSortModeChange: (String) -> Unit,
    onViewModeChange: (String) -> Unit,
    onSelectTag: (String) -> Unit,
    onOpenNote: (NoteItem) -> Unit,
    onCreateNote: () -> Unit,
    onTogglePin: (NoteItem) -> Unit,
    onToggleFavorite: (NoteItem) -> Unit,
    onDeleteNote: (NoteItem) -> Unit,
    onDuplicateNote: (NoteItem) -> Unit,
    onExportNote: (NoteItem) -> Unit,
    onOpenMindMap: (MindMapDoc) -> Unit,
    onCreateMindMap: () -> Unit,
    onDeleteMindMap: (MindMapDoc) -> Unit,
    onDuplicateMindMap: (MindMapDoc) -> Unit,
    onOpenCanvas: (CanvasBoard) -> Unit,
    onCreateCanvas: () -> Unit,
    onDeleteCanvas: (CanvasBoard) -> Unit,
    onDuplicateCanvas: (CanvasBoard) -> Unit,
    onRenameTag: (String, String) -> Unit,
    onDeleteTag: (String) -> Unit
) {
    val unconnectedIds = remember(notes, links, mindMaps) {
        val connected = LexiRelations.connectedNoteIds(links, mindMaps)
        notes.filter { !connected.contains(it.id) }.map { it.id }.toSet()
    }
    val backlinkCountMap = remember(notes, links) {
        val map = mutableMapOf<String, Int>()
        links.forEach { link ->
            map[link.targetNoteId] = (map[link.targetNoteId] ?: 0) + 1
        }
        map
    }

    val filteredNotes = remember(
        notes,
        activeProjectId,
        searchQuery,
        noteFilterMode,
        noteSortMode,
        selectedTag,
        unconnectedIds,
        backlinkCountMap
    ) {
        val step1 = notes.filter { n ->
            val matchProject = activeProjectId.isEmpty() || n.projectId == activeProjectId
            val matchTag = selectedTag.isEmpty() || n.tags.any {
                it.equals(selectedTag, ignoreCase = true) || it.startsWith("$selectedTag/", ignoreCase = true)
            }
            val matchFilter = when (noteFilterMode) {
                "pinned" -> n.pinned
                "favorite" -> n.favorite
                "unconnected" -> unconnectedIds.contains(n.id)
                else -> true
            }
            matchProject && matchTag && matchFilter
        }
        val step2 = if (searchQuery.isNotBlank()) {
            LexiSearch.rank(step1, searchQuery)
        } else {
            LexiSearch.sortNotes(step1, noteSortMode, backlinkCountMap)
        }
        step2
    }

    var showProjectDropdown by remember { mutableStateOf(false) }
    var showSortDropdown by remember { mutableStateOf(false) }
    var tagToRename by remember { mutableStateOf<String?>(null) }
    var newTagName by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LexiHeroHeading(
            title = activeVault?.name ?: trText("我的工作区"),
            palette = palette
        )

        // Workspace & Project Entry Button (matches LexiVaultTab.ets)
        val wsInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
        val wsShape = RoundedCornerShape(12.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp)
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(wsInteraction))
                .clip(wsShape)
                .background(palette.brand_soft.toComposeColor())
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(wsInteraction) { onOpenWorkspaces() })
                .padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            LexiIcon(name = "folder", size = 15.dp, tint = palette.brand_ink.toComposeColor())
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = trText("工作区与项目"),
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = palette.brand_ink.toComposeColor()
            )
        }

        // Search Bar
        val searchShape = RoundedCornerShape(12.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(42.dp)
                .clip(searchShape)
                .background(palette.surface_card.toComposeColor())
                .border(com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline, palette.divider.toComposeColor(), searchShape)
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            LexiIcon(name = "search", size = 16.dp, muted = true, palette = palette)
            Spacer(modifier = Modifier.width(8.dp))
            Box(modifier = Modifier.weight(1f)) {
                if (searchQuery.isEmpty()) {
                    Text(
                        text = trText("搜索笔记、#标签、path: 或 prop:key=val"),
                        fontSize = 13.sp,
                        color = palette.text_muted.toComposeColor(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                BasicTextField(
                    value = searchQuery,
                    onValueChange = onSearchQueryChange,
                    singleLine = true,
                    textStyle = TextStyle(
                        color = palette.text_primary.toComposeColor(),
                        fontSize = 13.sp
                    ),
                    cursorBrush = SolidColor(palette.brand.toComposeColor()),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (searchQuery.isNotEmpty()) {
                Text(
                    text = trText("清空"),
                    fontSize = 12.sp,
                    color = palette.brand.toComposeColor(),
                    modifier = Modifier.clickable { onSearchQueryChange("") }
                )
            }
        }

        // 4 Section Tabs: 笔记 / 导图 / 白板 / 标签 (no icons inside buttons, matches HarmonyOS)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val sections = listOf(
                0 to "${trText("笔记")} (${notes.size})",
                1 to "${trText("导图")} (${mindMaps.size})",
                2 to "${trText("白板")} (${canvases.size})",
                3 to "${trText("标签")} (${tags.size})"
            )
            sections.forEach { (idx, label) ->
                val active = vaultSectionIndex == idx
                val secInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
                val secShape = RoundedCornerShape(12.dp)
                val secBg = com.lovexjy.lexinote.ui.theme.LexiMotion.animateColor(
                    if (active) palette.brand.toComposeColor() else palette.surface_card.toComposeColor(),
                    label = "vaultSecBg"
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(36.dp)
                        .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(secInteraction))
                        .clip(secShape)
                        .background(secBg)
                        .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(secInteraction) { onSectionChange(idx) })
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = label,
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.TnumMicro,
                        fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                        color = if (active) palette.inverse_text.toComposeColor() else palette.text_secondary.toComposeColor(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }

        when (vaultSectionIndex) {
            0 -> {
                // Filter chips + Project/Sort/View bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    LexiFilterChip(
                        label = trText("全部笔记"),
                        selected = noteFilterMode == "all",
                        palette = palette,
                        onClick = { onFilterModeChange("all") }
                    )
                    LexiFilterChip(
                        label = trText("置顶"),
                        selected = noteFilterMode == "pinned",
                        palette = palette,
                        onClick = { onFilterModeChange("pinned") }
                    )
                    LexiFilterChip(
                        label = trText("收藏"),
                        selected = noteFilterMode == "favorite",
                        palette = palette,
                        onClick = { onFilterModeChange("favorite") }
                    )
                    LexiFilterChip(
                        label = "${trText("未连接")} (${unconnectedIds.size})",
                        selected = noteFilterMode == "unconnected",
                        palette = palette,
                        onClick = { onFilterModeChange("unconnected") }
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        // Project selector
                        Box {
                            val activeProjName = projects.firstOrNull { it.id == activeProjectId }?.name ?: trText("全部笔记本")
                            SmallControlChip(
                                text = "📁 $activeProjName",
                                palette = palette,
                                active = activeProjectId.isNotEmpty(),
                                onClick = { showProjectDropdown = true }
                            )
                            DropdownMenu(
                                expanded = showProjectDropdown,
                                onDismissRequest = { showProjectDropdown = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(trText("全部笔记本")) },
                                    onClick = {
                                        showProjectDropdown = false
                                        onSelectProject("")
                                    }
                                )
                                projects.forEach { p ->
                                    DropdownMenuItem(
                                        text = { Text(p.name) },
                                        onClick = {
                                            showProjectDropdown = false
                                            onSelectProject(p.id)
                                        }
                                    )
                                }
                            }
                        }

                        // Sort selector
                        Box {
                            val sortLabel = when (noteSortMode) {
                                "created" -> trText("最近创建")
                                "title" -> trText("标题 A-Z")
                                "links" -> trText("反向链接数")
                                else -> trText("最近编辑")
                            }
                            SmallControlChip(
                                text = "${trText("排序")}：$sortLabel",
                                palette = palette,
                                onClick = { showSortDropdown = true }
                            )
                            DropdownMenu(
                                expanded = showSortDropdown,
                                onDismissRequest = { showSortDropdown = false }
                            ) {
                                listOf(
                                    "updated" to "最近编辑",
                                    "created" to "最近创建",
                                    "title" to "标题 A-Z",
                                    "links" to "反向链接数"
                                ).forEach { (mode, label) ->
                                    DropdownMenuItem(
                                        text = { Text(trText(label)) },
                                        onClick = {
                                            showSortDropdown = false
                                            onSortModeChange(mode)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    SmallControlChip(
                        text = if (noteViewMode == "grid") trText("视图：双栏") else trText("视图：列表"),
                        palette = palette,
                        onClick = {
                            onViewModeChange(if (noteViewMode == "grid") "list" else "grid")
                        }
                    )
                }

                if (selectedTag.isNotEmpty()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.brand_soft.toComposeColor())
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "${trText("正在筛选标签")}: #$selectedTag",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.brand.toComposeColor()
                        )
                        Text(
                            text = trText("清除筛选"),
                            fontSize = 12.sp,
                            color = palette.brand.toComposeColor(),
                            modifier = Modifier.clickable { onSelectTag("") }
                        )
                    }
                }

                val outgoingMap = remember(links) {
                    val m = mutableMapOf<String, Int>()
                    links.forEach { m[it.sourceId] = (m[it.sourceId] ?: 0) + 1 }
                    m
                }
                if (filteredNotes.isEmpty()) {
                    EmptyVaultSectionCard(
                        title = "没有匹配的笔记",
                        subtitle = "试试调整筛选条件，或新建一篇笔记",
                        actionText = "+ 新建笔记",
                        palette = palette,
                        onAction = onCreateNote
                    )
                } else if (noteViewMode == "grid") {
                    val rows = filteredNotes.chunked(2)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        rows.forEach { pair ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                pair.forEach { note ->
                                    LexiNoteCard(
                                        note = note,
                                        highlightQuery = searchQuery,
                                        outgoingCount = outgoingMap[note.id] ?: 0,
                                        backlinkCount = backlinkCountMap[note.id] ?: 0,
                                        isUnconnected = unconnectedIds.contains(note.id),
                                        palette = palette,
                                        onOpen = { onOpenNote(note) },
                                        onTogglePin = { onTogglePin(note) },
                                        onToggleFavorite = { onToggleFavorite(note) },
                                        onDelete = { onDeleteNote(note) },
                                        onDuplicate = { onDuplicateNote(note) },
                                        onExportMarkdown = { onExportNote(note) },
                                        onTagClick = onSelectTag,
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                                if (pair.size == 1) {
                                    Spacer(modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        filteredNotes.forEach { note ->
                            LexiNoteCard(
                                note = note,
                                highlightQuery = searchQuery,
                                outgoingCount = outgoingMap[note.id] ?: 0,
                                backlinkCount = backlinkCountMap[note.id] ?: 0,
                                isUnconnected = unconnectedIds.contains(note.id),
                                palette = palette,
                                onOpen = { onOpenNote(note) },
                                onTogglePin = { onTogglePin(note) },
                                onToggleFavorite = { onToggleFavorite(note) },
                                onDelete = { onDeleteNote(note) },
                                onDuplicate = { onDuplicateNote(note) },
                                onExportMarkdown = { onExportNote(note) },
                                onTagClick = onSelectTag
                            )
                        }
                    }
                }
            }

            1 -> {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = trText("思维导图列表"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    SmallControlChip(
                        text = trText("+ 新建导图"),
                        palette = palette,
                        active = true,
                        onClick = onCreateMindMap
                    )
                }

                if (mindMaps.isEmpty()) {
                    EmptyVaultSectionCard(
                        title = "暂无思维导图",
                        subtitle = "用节点树梳理读书框架、项目拆解与复习提纲",
                        actionText = "+ 新建思维导图",
                        palette = palette,
                        onAction = onCreateMindMap
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        mindMaps.forEach { doc ->
                            var showMenu by remember { mutableStateOf(false) }
                            Box {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .then(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                                shape = RoundedCornerShape(18.dp),
                                                dark = palette.dark
                                            )
                                        )
                                        .clip(RoundedCornerShape(18.dp))
                                        .background(palette.surface_card.toComposeColor())
                                        .border(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline,
                                            palette.stroke.toComposeColor().copy(alpha = 0.5f),
                                            RoundedCornerShape(18.dp)
                                        )
                                        .combinedClickable(
                                            onClick = { onOpenMindMap(doc) },
                                            onLongClick = { showMenu = true }
                                        )
                                        .padding(14.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(40.dp)
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(palette.brand_soft.toComposeColor()),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        LexiIcon(name = "mindmap", size = 20.dp, palette = palette)
                                    }
                                    Spacer(modifier = Modifier.width(12.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = doc.title,
                                            fontSize = 15.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = palette.text_primary.toComposeColor()
                                        )
                                        Text(
                                            text = "${doc.nodes.size} 个主题节点 · ${formatTimeShort(doc.updatedAt)}",
                                            fontSize = 11.sp,
                                            color = palette.text_muted.toComposeColor()
                                        )
                                    }
                                    LexiIcon(name = "chevron", size = 16.dp, muted = true, palette = palette)
                                }

                                DropdownMenu(
                                    expanded = showMenu,
                                    onDismissRequest = { showMenu = false }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text(trText("打开导图")) },
                                        onClick = {
                                            showMenu = false
                                            onOpenMindMap(doc)
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("创建副本")) },
                                        onClick = {
                                            showMenu = false
                                            onDuplicateMindMap(doc)
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("移入回收站"), color = palette.danger.toComposeColor()) },
                                        onClick = {
                                            showMenu = false
                                            onDeleteMindMap(doc)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            2 -> {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = trText("自由白板列表"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    SmallControlChip(
                        text = trText("+ 新建白板"),
                        palette = palette,
                        active = true,
                        onClick = onCreateCanvas
                    )
                }

                if (canvases.isEmpty()) {
                    EmptyVaultSectionCard(
                        title = "暂无自由白板",
                        subtitle = "在二维空间自由排布卡片、建立连线并关联笔记",
                        actionText = "+ 新建自由白板",
                        palette = palette,
                        onAction = onCreateCanvas
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        canvases.forEach { board ->
                            var showMenu by remember { mutableStateOf(false) }
                            Box {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .then(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                                shape = RoundedCornerShape(18.dp),
                                                dark = palette.dark
                                            )
                                        )
                                        .clip(RoundedCornerShape(18.dp))
                                        .background(palette.surface_card.toComposeColor())
                                        .border(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline,
                                            palette.stroke.toComposeColor().copy(alpha = 0.5f),
                                            RoundedCornerShape(18.dp)
                                        )
                                        .combinedClickable(
                                            onClick = { onOpenCanvas(board) },
                                            onLongClick = { showMenu = true }
                                        )
                                        .padding(14.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(40.dp)
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(palette.brand_soft.toComposeColor()),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        LexiIcon(name = "canvas", size = 20.dp, palette = palette)
                                    }
                                    Spacer(modifier = Modifier.width(12.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = board.title,
                                            fontSize = 15.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = palette.text_primary.toComposeColor()
                                        )
                                        Text(
                                            text = "${board.cards.size} 张卡片 · ${board.edges.size} 条连线 · ${formatTimeShort(board.updatedAt)}",
                                            fontSize = 11.sp,
                                            color = palette.text_muted.toComposeColor()
                                        )
                                    }
                                    LexiIcon(name = "chevron", size = 16.dp, muted = true, palette = palette)
                                }

                                DropdownMenu(
                                    expanded = showMenu,
                                    onDismissRequest = { showMenu = false }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text(trText("打开白板")) },
                                        onClick = {
                                            showMenu = false
                                            onOpenCanvas(board)
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("创建副本")) },
                                        onClick = {
                                            showMenu = false
                                            onDuplicateCanvas(board)
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("移入回收站"), color = palette.danger.toComposeColor()) },
                                        onClick = {
                                            showMenu = false
                                            onDeleteCanvas(board)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            3 -> {
                if (tags.isEmpty()) {
                    EmptyVaultSectionCard(
                        title = "暂无标签",
                        subtitle = "在笔记正文输入 #标签 或 #父标签/子标签 即可自动归档",
                        actionText = "+ 新建笔记",
                        palette = palette,
                        onAction = onCreateNote
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        tags.forEach { tc ->
                            var showMenu by remember { mutableStateOf(false) }
                            val depth = tc.name.count { it == '/' }
                            Box {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(start = (depth * 14).dp)
                                        .then(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                                shape = RoundedCornerShape(16.dp),
                                                dark = palette.dark
                                            )
                                        )
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(palette.surface_card.toComposeColor())
                                        .border(
                                            com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline,
                                            palette.stroke.toComposeColor().copy(alpha = 0.5f),
                                            RoundedCornerShape(16.dp)
                                        )
                                        .combinedClickable(
                                            onClick = {
                                                onSelectTag(tc.name)
                                                onSectionChange(0)
                                            },
                                            onLongClick = { showMenu = true }
                                        )
                                        .padding(horizontal = 14.dp, vertical = 12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        LexiIcon(name = "tag", size = 15.dp, palette = palette)
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(
                                            text = "#${tc.name}",
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = palette.text_primary.toComposeColor()
                                        )
                                    }
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(999.dp))
                                            .background(palette.brand_soft.toComposeColor())
                                            .padding(horizontal = 8.dp, vertical = 2.dp)
                                    ) {
                                        Text(
                                            text = "${tc.count} 篇",
                                            fontSize = 11.sp,
                                            color = palette.brand.toComposeColor()
                                        )
                                    }
                                }

                                DropdownMenu(
                                    expanded = showMenu,
                                    onDismissRequest = { showMenu = false }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text(trText("查看该标签下笔记")) },
                                        onClick = {
                                            showMenu = false
                                            onSelectTag(tc.name)
                                            onSectionChange(0)
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("重命名标签")) },
                                        onClick = {
                                            showMenu = false
                                            tagToRename = tc.name
                                            newTagName = tc.name
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text(trText("移除标签"), color = palette.danger.toComposeColor()) },
                                        onClick = {
                                            showMenu = false
                                            onDeleteTag(tc.name)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (tagToRename != null) {
        AlertDialog(
            onDismissRequest = { tagToRename = null },
            title = { Text(trText("重命名标签")) },
            text = {
                OutlinedTextField(
                    value = newTagName,
                    onValueChange = { newTagName = it },
                    label = { Text(trText("新标签名称")) },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val old = tagToRename
                        if (old != null && newTagName.isNotBlank()) {
                            onRenameTag(old, newTagName.trim())
                        }
                        tagToRename = null
                    }
                ) {
                    Text(trText("保存"))
                }
            },
            dismissButton = {
                TextButton(onClick = { tagToRename = null }) {
                    Text(trText("取消"))
                }
            }
        )
    }
}

@Composable
private fun EmptyVaultSectionCard(
    title: String,
    subtitle: String,
    actionText: String,
    palette: LexiThemePalette,
    onAction: () -> Unit
) {
    val emptyShape = RoundedCornerShape(20.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                    elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                    shape = emptyShape,
                    dark = palette.dark
                )
            )
            .clip(emptyShape)
            .background(palette.surface_card.toComposeColor())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = trText(title),
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = palette.text_primary.toComposeColor()
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = trText(subtitle),
            fontSize = 12.sp,
            color = palette.text_muted.toComposeColor()
        )
        Spacer(modifier = Modifier.height(14.dp))
        Box(
            modifier = Modifier
                .height(36.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(palette.brand.toComposeColor())
                .clickable { onAction() }
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = trText(actionText),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }
    }
}

@Composable
fun LexiExploreTab(
    notes: List<NoteItem>,
    mindMaps: List<MindMapDoc>,
    links: List<NoteLink>,
    tags: List<TagCount>,
    palette: LexiThemePalette,
    onOpenNote: (NoteItem) -> Unit,
    onOpenMindMap: (MindMapDoc) -> Unit,
    onSelectTagAndJump: (String) -> Unit,
    onQuickLinkNotes: (NoteItem, NoteItem) -> Unit
) {
    var viewMode by remember { mutableStateOf("list") } // "list" or "graph"
    var includeMindMaps by remember { mutableStateOf(true) }
    var includeTags by remember { mutableStateOf(true) }
    var focusNoteId by remember { mutableStateOf("") }
    var selectedNode by remember { mutableStateOf<GraphNode?>(null) }
    var showDisplayMenu by remember { mutableStateOf(false) }
    var previewTarget by remember { mutableStateOf<LexiLinkTargetPreview?>(null) }
    var previewNoteToOpen by remember { mutableStateOf<NoteItem?>(null) }

    val unconnectedNotes = remember(notes, links, mindMaps) {
        LexiRelations.unconnectedNotes(notes, links, mindMaps)
    }
    val connectedNotes = remember(notes, unconnectedNotes) {
        val unIds = unconnectedNotes.map { it.id }.toSet()
        notes.filter { !unIds.contains(it.id) }
    }

    val graphData = remember(notes, links, mindMaps, tags, includeMindMaps, includeTags, focusNoteId) {
        val filteredMindMaps = if (includeMindMaps) mindMaps else emptyList()
        val filteredTags = if (includeTags) tags else emptyList()
        if (focusNoteId.isNotEmpty()) {
            GraphLayout.local(focusNoteId, notes, links, filteredMindMaps, filteredTags)
        } else {
            GraphLayout.build(notes, links, filteredMindMaps, filteredTags)
        }
    }

    // Potential unlinked mentions across vault
    val potentialMentions = remember(notes) {
        val list = mutableListOf<Triple<NoteItem, NoteItem, UnlinkedMention>>()
        notes.take(8).forEach { n ->
            val found = MarkdownEngine.findUnlinkedMentions(n, notes)
            found.take(2).forEach { m ->
                val source = notes.firstOrNull { it.id == m.sourceNoteId }
                if (source != null) {
                    list.add(Triple(source, n, m))
                }
            }
        }
        list.take(6)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        LexiHeroHeading(
            title = trText("笔记关联"),
            palette = palette
        )

        // Scope summary line (matches LexiExploreTab.ets)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(horizontal = 2.dp)
        ) {
            LexiIcon(name = "folder", size = 15.dp, muted = true, palette = palette)
            Text(
                text = "${connectedNotes.size} ${trText("篇已连接")} · ${unconnectedNotes.size} ${trText("篇待连接")}",
                fontSize = 13.sp,
                color = palette.text_secondary.toComposeColor()
            )
        }

        // Full-width Soft Surface Segmented Switcher (关联列表 / 关系图)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(42.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(palette.surface_soft.toComposeColor())
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            listOf("list" to "关联列表", "graph" to "关系图").forEach { (mode, label) ->
                val active = viewMode == mode
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (active) palette.surface_card.toComposeColor() else Color.Transparent)
                        .clickable { viewMode = mode },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText(label),
                        fontSize = 13.sp,
                        fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                        color = if (active) palette.brand.toComposeColor()
                        else palette.text_secondary.toComposeColor()
                    )
                }
            }
        }

        if (viewMode == "graph") {
            val graphShape = RoundedCornerShape(24.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = graphShape,
                            dark = palette.dark
                        )
                    )
                    .clip(graphShape)
                    .background(palette.surface_card.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        SmallControlChip(
                            text = "${trText("未连接")} ${unconnectedNotes.size}",
                            palette = palette,
                            active = false,
                            onClick = {}
                        )
                        if (selectedNode?.kind == "note") {
                            SmallControlChip(
                                text = if (focusNoteId.isEmpty()) trText("只看这篇") else trText("查看全部"),
                                palette = palette,
                                active = focusNoteId.isNotEmpty(),
                                onClick = {
                                    focusNoteId = if (focusNoteId.isEmpty()) selectedNode!!.refId else ""
                                }
                            )
                        } else if (focusNoteId.isNotEmpty()) {
                            SmallControlChip(
                                text = trText("查看全部"),
                                palette = palette,
                                active = true,
                                onClick = { focusNoteId = "" }
                            )
                        }
                    }

                    Box {
                        SmallControlChip(
                            text = trText("显示 ▾"),
                            palette = palette,
                            onClick = { showDisplayMenu = true }
                        )
                        DropdownMenu(
                            expanded = showDisplayMenu,
                            onDismissRequest = { showDisplayMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        (if (includeMindMaps) "✓ " else "   ") + trText("包含思维导图")
                                    )
                                },
                                onClick = {
                                    includeMindMaps = !includeMindMaps
                                    showDisplayMenu = false
                                }
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        (if (includeTags) "✓ " else "   ") + trText("包含标签")
                                    )
                                },
                                onClick = {
                                    includeTags = !includeTags
                                    showDisplayMenu = false
                                }
                            )
                        }
                    }
                }

                LexiGraphView(
                    graphData = graphData,
                    selectedNodeId = selectedNode?.id ?: "",
                    palette = palette,
                    height = 320.dp,
                    onNodeClick = { node ->
                        selectedNode = node
                    }
                )

                selectedNode?.let { node ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = node.label,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_primary.toComposeColor()
                            )
                            Text(
                                text = "${trText("连接度")}: ${node.degree}",
                                fontSize = 11.sp,
                                color = palette.text_muted.toComposeColor()
                            )
                        }
                        SmallControlChip(
                            text = when (node.kind) {
                                "mindmap" -> trText("打开导图")
                                "tag" -> trText("筛选标签")
                                else -> trText("打开笔记")
                            },
                            palette = palette,
                            active = true,
                            onClick = {
                                when (node.kind) {
                                    "mindmap" -> {
                                        mindMaps.firstOrNull { it.id == node.refId }?.let(onOpenMindMap)
                                    }
                                    "tag" -> {
                                        onSelectTagAndJump(node.refId)
                                    }
                                    else -> {
                                        notes.firstOrNull { it.id == node.refId }?.let(onOpenNote)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        } else {
            // Onboarding Hero Card when there are no explicit links yet (matches LexiExploreTab.ets)
            if (links.isEmpty()) {
                val guideShape = RoundedCornerShape(24.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = guideShape,
                                dark = palette.dark
                            )
                        )
                        .clip(guideShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(114.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(palette.brand_soft.toComposeColor().copy(alpha = 0.6f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(18.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(
                                modifier = Modifier
                                    .width(82.dp)
                                    .height(58.dp)
                                    .graphicsLayer(rotationZ = -6f)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(palette.surface_card.toComposeColor())
                                    .padding(10.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(0.7f)
                                        .height(6.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(palette.brand_soft.toComposeColor())
                                )
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(5.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(palette.surface_soft.toComposeColor())
                                )
                            }
                            Column(
                                modifier = Modifier
                                    .width(82.dp)
                                    .height(58.dp)
                                    .graphicsLayer(rotationZ = 6f)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(palette.surface_card.toComposeColor())
                                    .padding(10.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(0.65f)
                                        .height(6.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(palette.brand_soft.toComposeColor())
                                )
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(5.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(palette.surface_soft.toComposeColor())
                                )
                            }
                        }
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .clip(CircleShape)
                                .background(palette.brand.toComposeColor()),
                            contentAlignment = Alignment.Center
                        ) {
                            LexiIcon(name = "link", size = 16.dp, tint = palette.inverse_text.toComposeColor())
                        }
                    }

                    Text(
                        text = trText("从两篇笔记的联系开始"),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("在正文输入 [[笔记标题]] 即可建立双向链接，这里会自动汇总引用关系、潜在提及与关系网络。"),
                        fontSize = 13.sp,
                        lineHeight = 19.sp,
                        color = palette.text_secondary.toComposeColor()
                    )
                }
            }

            // Connected Notes List
            if (connectedNotes.isNotEmpty()) {
                val relCardShape = RoundedCornerShape(20.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = relCardShape,
                                dark = palette.dark
                            )
                        )
                        .clip(relCardShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = "${trText("已连接笔记")} (${connectedNotes.size})",
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.H3,
                        color = palette.text_primary.toComposeColor()
                    )
                    connectedNotes.take(6).forEach { note ->
                        val relCount = LexiRelations.counts(note, links, mindMaps)
                        val rowInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
                        val rowShape = RoundedCornerShape(16.dp)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(rowInteraction))
                                .clip(rowShape)
                                .background(palette.surface_soft.toComposeColor())
                                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(rowInteraction) { onOpenNote(note) })
                                .padding(horizontal = 12.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                modifier = Modifier.weight(1f),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(palette.brand_soft.toComposeColor()),
                                    contentAlignment = Alignment.Center
                                ) {
                                    LexiIcon(name = "note", size = 18.dp, palette = palette)
                                }
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = note.title,
                                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.BodyMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        color = palette.text_primary.toComposeColor(),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = "${relCount.outgoing} 处引用 · ${relCount.backlinks} 处被引用",
                                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.TnumMicro,
                                        color = palette.text_muted.toComposeColor()
                                    )
                                }
                            }
                            LexiIcon(name = "chevron", size = 15.dp, muted = true, palette = palette)
                        }
                    }
                }
            }

            // Unconnected Notes Prompt Card
            if (unconnectedNotes.isNotEmpty()) {
                val unconnShape = RoundedCornerShape(20.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = unconnShape,
                                dark = palette.dark
                            )
                        )
                        .clip(unconnShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = "${trText("待连接笔记")} (${unconnectedNotes.size})",
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.H3,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("以下笔记尚未加入关联网络，点击推荐即可一键建立双向链接："),
                        fontSize = 12.sp,
                        color = palette.text_secondary.toComposeColor()
                    )

                    unconnectedNotes.take(4).forEach { orphan ->
                        val candidates = remember(orphan, notes, links) {
                            LexiRelations.suggestLinkCandidates(orphan, notes, links, 1)
                        }
                        val bestCandidate = candidates.firstOrNull()
                        val bestTarget = remember(bestCandidate, notes) {
                            notes.firstOrNull { it.id == bestCandidate?.noteId }
                        }

                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(palette.surface_soft.toComposeColor())
                                .padding(12.dp)
                        ) {
                            Text(
                                text = orphan.title,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_primary.toComposeColor()
                            )
                            if (bestCandidate != null && bestTarget != null) {
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = "${trText("推荐关联")}: [[${bestCandidate.noteTitle}]] (${bestCandidate.reason})",
                                    fontSize = 11.sp,
                                    color = palette.brand.toComposeColor()
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (bestTarget != null) {
                                    SmallControlChip(
                                        text = trText("预览"),
                                        palette = palette,
                                        onClick = {
                                            previewNoteToOpen = bestTarget
                                            previewTarget = MarkdownEngine.linkTargetPreview(bestTarget)
                                        }
                                    )
                                    SmallControlChip(
                                        text = trText("一键关联"),
                                        palette = palette,
                                        active = true,
                                        onClick = { onQuickLinkNotes(orphan, bestTarget) }
                                    )
                                }
                                SmallControlChip(
                                    text = trText("打开并连接"),
                                    palette = palette,
                                    onClick = { onOpenNote(orphan) }
                                )
                            }
                        }
                    }
                }
            }

            // Potential Unlinked Mentions
            if (potentialMentions.isNotEmpty()) {
                val mentionShape = RoundedCornerShape(20.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = mentionShape,
                                dark = palette.dark
                            )
                        )
                        .clip(mentionShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = trText("可能有关（潜在提及）"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    potentialMentions.forEach { (source, target, mention) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(palette.surface_soft.toComposeColor())
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "${source.title} 提及了「${target.title}」",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = palette.text_primary.toComposeColor()
                                )
                                Text(
                                    text = mention.lineText,
                                    fontSize = 11.sp,
                                    color = palette.text_muted.toComposeColor(),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            Spacer(modifier = Modifier.width(8.dp))
                            SmallControlChip(
                                text = trText("建立链接"),
                                palette = palette,
                                active = true,
                                onClick = { onQuickLinkNotes(source, target) }
                            )
                        }
                    }
                }
            }
        }
    }

    if (previewTarget != null && previewNoteToOpen != null) {
        LexiLinkPreviewPopupCard(
            preview = previewTarget!!,
            palette = palette,
            onOpen = { onOpenNote(previewNoteToOpen!!) },
            onDismiss = { previewTarget = null }
        )
    }
}

@Composable
fun LexiProfileTab(
    activeVault: VaultItem?,
    noteCount: Int,
    deletedCount: Int,
    palette: LexiThemePalette,
    onOpenSettings: () -> Unit,
    onOpenTrash: () -> Unit,
    onOpenHelp: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        LexiHeroHeading(
            title = trText("我的"),
            palette = palette
        )

        // Brand Identity Card
        val brandShape = RoundedCornerShape(22.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = brandShape,
                        dark = palette.dark
                    )
                )
                .clip(brandShape)
                .background(palette.surface_card.toComposeColor())
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            LexiLogo(
                size = 50.dp,
                modifier = Modifier.clip(RoundedCornerShape(15.dp))
            )
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = trText("知萤 LexiNote"),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Spacer(modifier = Modifier.height(3.dp))
                Text(
                    text = activeVault?.name ?: trText("默认工作区"),
                    fontSize = 12.sp,
                    color = palette.text_secondary.toComposeColor()
                )
            }
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(palette.brand_soft.toComposeColor())
                    .padding(horizontal = 10.dp, vertical = 5.dp)
            ) {
                Text(
                    text = "$noteCount ${trText("篇笔记")}",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.brand.toComposeColor()
                )
            }
        }

        Text(
            text = trText("管理"),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = palette.text_secondary.toComposeColor(),
            modifier = Modifier.padding(horizontal = 4.dp)
        )

        // Settings Card
        val settingsShape = RoundedCornerShape(18.dp)
        val settingsInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(settingsInteraction))
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = settingsShape,
                        dark = palette.dark
                    )
                )
                .clip(settingsShape)
                .background(palette.surface_card.toComposeColor())
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(settingsInteraction) { onOpenSettings() })
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(palette.brand_soft.toComposeColor()),
                contentAlignment = Alignment.Center
            ) {
                LexiIcon(name = "gear", size = 20.dp, palette = palette)
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = trText("设置"),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = trText("外观、编辑器、插件与数据"),
                    fontSize = 12.sp,
                    color = palette.text_muted.toComposeColor()
                )
            }
            LexiIcon(name = "chevron", size = 16.dp, muted = true, palette = palette)
        }

        // Trash Card
        val trashShape = RoundedCornerShape(18.dp)
        val trashInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(trashInteraction))
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                        shape = trashShape,
                        dark = palette.dark
                    )
                )
                .clip(trashShape)
                .background(palette.surface_card.toComposeColor())
                .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(trashInteraction) { onOpenTrash() })
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(palette.brand_soft.toComposeColor()),
                contentAlignment = Alignment.Center
            ) {
                LexiIcon(name = "trash", size = 20.dp, palette = palette)
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = trText("回收站"),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = trText("恢复已删除的笔记，或永久删除"),
                    fontSize = 12.sp,
                    color = palette.text_muted.toComposeColor()
                )
            }
            if (deletedCount > 0) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = deletedCount.toString(),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                }
                Spacer(modifier = Modifier.width(6.dp))
            }
            LexiIcon(name = "chevron", size = 16.dp, muted = true, palette = palette)
        }

        Text(
            text = trText("笔记保存在本机，可随时在设置中导出备份。"),
            fontSize = 12.sp,
            color = palette.text_muted.toComposeColor(),
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp)
        )
    }
}
