package com.lovexjy.lexinote

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.lovexjy.lexinote.core.*
import com.lovexjy.lexinote.ui.components.*
import com.lovexjy.lexinote.ui.pages.*
import com.lovexjy.lexinote.ui.tabs.*
import kotlinx.coroutines.delay
import java.io.File

sealed class LexiScreenRoute {
    data object MainTabs : LexiScreenRoute()
    data class NoteEditor(val noteId: String) : LexiScreenRoute()
    data class MindMapEditor(val docId: String) : LexiScreenRoute()
    data class CanvasEditor(val boardId: String) : LexiScreenRoute()
    data object Workspaces : LexiScreenRoute()
    data class Settings(val initialCategory: String = "") : LexiScreenRoute()
    data object Trash : LexiScreenRoute()
    data object Help : LexiScreenRoute()
    data class ShareCapture(val draft: LexiShareDraft?) : LexiScreenRoute()
}

class MainActivity : ComponentActivity() {
    private var pendingRouteState = mutableStateOf<LexiScreenRoute?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LexiStorageService.init(applicationContext)
        handleIncomingIntent(intent)
        enableEdgeToEdge()
        setContent {
            LexiNotePhoneApp(
                externalRoute = pendingRouteState.value,
                onExternalRouteConsumed = { pendingRouteState.value = null }
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
                val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""
                if (sharedText.isNotBlank()) {
                    val draft = LexiShareDraft(
                        title = sharedSubject.ifBlank { "分享摘录 ${LexiTemplates.dateKey()}" },
                        text = sharedText,
                        sourceApp = intent.`package` ?: "",
                        createdAt = System.currentTimeMillis()
                    )
                    LexiStorageService.saveShareClip(draft)
                    pendingRouteState.value = LexiScreenRoute.ShareCapture(draft)
                }
            }
            Intent.ACTION_VIEW, Intent.ACTION_EDIT -> {
                val data: Uri = intent.data ?: return
                if (data.scheme.equals("lexinote", ignoreCase = true)) {
                    val cmd = LexiEcosystemLink.parse(data.toString()) ?: return
                    when (cmd.action) {
                        "daily" -> {
                            val daily = LexiStorageService.openOrCreateDailyNote()
                            pendingRouteState.value = LexiScreenRoute.NoteEditor(daily.id)
                        }
                        "open" -> {
                            val notes = LexiStorageService.listNotes(LexiStorageService.getActiveVaultId())
                            val target = notes.firstOrNull {
                                it.id == cmd.noteId || it.title.equals(cmd.title, ignoreCase = true)
                            }
                            if (target != null) {
                                pendingRouteState.value = LexiScreenRoute.NoteEditor(target.id)
                            }
                        }
                        "new" -> {
                            val created = LexiStorageService.createNote(
                                title = cmd.title.ifBlank { "新笔记" },
                                content = cmd.content.ifBlank { "# ${cmd.title.ifBlank { "新笔记" }}\n\n" }
                            )
                            pendingRouteState.value = LexiScreenRoute.NoteEditor(created.id)
                        }
                    }
                } else {
                    try {
                        val rawMd = contentResolver.openInputStream(data)?.use {
                            String(it.readBytes(), Charsets.UTF_8)
                        }
                        if (!rawMd.isNullOrBlank()) {
                            val fileName = data.lastPathSegment?.substringAfterLast('/') ?: "外部笔记.md"
                            val imported = LexiStorageService.importMarkdownFile(fileName, rawMd)
                            pendingRouteState.value = LexiScreenRoute.NoteEditor(imported.id)
                        }
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }
}

@Composable
fun LexiNotePhoneApp(
    externalRoute: LexiScreenRoute? = null,
    onExternalRouteConsumed: () -> Unit = {}
) {
    val context = LocalContext.current
    val systemDark = isSystemInDarkTheme()

    var refreshTick by remember { mutableIntStateOf(0) }
    var showLaunchSplash by remember { mutableStateOf(true) }
    var showWelcomeGuide by remember {
        mutableStateOf(!LexiStorageService.isOnboardingCompleted())
    }

    LaunchedEffect(Unit) {
        delay(420)
        showLaunchSplash = false
    }

    val themeId = remember(refreshTick) { LexiStorageService.getThemeId() }
    val colorMode = remember(refreshTick) { LexiStorageService.getColorMode() }
    val accentHex = remember(refreshTick) { LexiStorageService.getAccentColor() }
    val palette = remember(themeId, colorMode, accentHex, systemDark) {
        val base = LexiTheme.resolvePalette(themeId, colorMode, systemDark)
        LexiTheme.resolveAccent(base, accentHex)
    }

    var routeStack by remember { mutableStateOf(listOf<LexiScreenRoute>(LexiScreenRoute.MainTabs)) }
    val currentRoute = routeStack.lastOrNull() ?: LexiScreenRoute.MainTabs

    fun pushRoute(route: LexiScreenRoute) {
        routeStack = routeStack + route
    }

    fun popRoute() {
        if (routeStack.size > 1) {
            routeStack = routeStack.dropLast(1)
            refreshTick += 1
        }
    }

    LaunchedEffect(externalRoute) {
        if (externalRoute != null) {
            pushRoute(externalRoute)
            onExternalRouteConsumed()
        }
    }

    // Phone Main Tabs State
    var currentTab by remember { mutableIntStateOf(0) } // 0: 首页, 1: 知识库, 2: 探索, 3: 我的
    var vaultSectionIndex by remember { mutableIntStateOf(0) } // 0: 笔记, 1: 导图, 2: 白板, 3: 标签
    var recentNotesMode by remember {
        mutableStateOf(LexiStorageService.getHomeRecentNotesMode())
    }
    var quickCaptureDraft by remember { mutableStateOf("") }
    var searchQuery by remember { mutableStateOf("") }
    var noteFilterMode by remember { mutableStateOf("all") }
    var noteSortMode by remember { mutableStateOf(LexiStorageService.getNoteSortMode()) }
    var noteViewMode by remember { mutableStateOf(LexiStorageService.getNoteViewMode()) }
    var selectedTag by remember { mutableStateOf("") }

    // Dialogs & Sheets State
    var showCreateMenu by remember { mutableStateOf(false) }
    var showTemplatePicker by remember { mutableStateOf(false) }
    var showPluginSheet by remember { mutableStateOf(false) }
    var destinationPickerMode by remember { mutableStateOf("") } // "" | "new_note" | "quick_capture" | "template"
    var pendingTemplate by remember { mutableStateOf<LexiTemplateItem?>(null) }
    var showStoragePromptDialog by remember { mutableStateOf(false) }

    // Data Queries
    val activeVaultId = remember(refreshTick) { LexiStorageService.getActiveVaultId() }
    val vaults = remember(refreshTick) { LexiStorageService.listVaults(false) }
    val activeVault = remember(vaults, activeVaultId) {
        vaults.firstOrNull { it.id == activeVaultId } ?: vaults.firstOrNull()
    }
    val projects = remember(refreshTick, activeVaultId) {
        LexiStorageService.listProjects(activeVaultId)
    }
    val activeProjectId = remember(refreshTick, activeVaultId) {
        LexiStorageService.getActiveProjectId(activeVaultId)
    }
    val notes = remember(refreshTick, activeVaultId) {
        LexiStorageService.listNotes(activeVaultId)
    }
    val mindMaps = remember(refreshTick, activeVaultId) {
        LexiStorageService.listMindMaps(activeVaultId)
    }
    val canvases = remember(refreshTick, activeVaultId) {
        LexiStorageService.listCanvases(activeVaultId)
    }
    val links = remember(refreshTick, activeVaultId) {
        LexiStorageService.listLinks(activeVaultId)
    }
    val tags = remember(refreshTick, activeVaultId) {
        LexiStorageService.listTags(activeVaultId)
    }
    val deletedCount = remember(refreshTick, activeVaultId) {
        LexiStorageService.listDeletedNotes(activeVaultId).size +
            LexiStorageService.listDeletedMindMaps(activeVaultId).size +
            LexiStorageService.listDeletedCanvases(activeVaultId).size
    }

    fun checkFirstNoteStoragePrompt() {
        if (LexiStorageService.takeStorageAccessPrompt()) {
            showStoragePromptDialog = true
        }
    }

    fun shareExportMarkdownFile(note: NoteItem) {
        try {
            val exportDir = File(context.cacheDir, "exports").apply { mkdirs() }
            val safeName = note.title.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "note" }
            val outFile = File(exportDir, "$safeName.md")
            outFile.writeText(LexiStorageService.exportMarkdown(note), Charsets.UTF_8)
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                outFile
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/markdown"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(Intent.createChooser(shareIntent, trText("导出 Markdown")))
        } catch (_: Exception) {
        }
    }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            val externalDir = context.getExternalFilesDir(null)
            val targetDir = if (externalDir != null) {
                File(externalDir, "LexiNoteVault").apply { mkdirs() }.absolutePath
            } else {
                uri.toString()
            }
            LexiStorageService.configureLocalRoot(targetDir)
            refreshTick += 1
        }
    }

    BackHandler(enabled = routeStack.size > 1 || currentTab != 0) {
        if (routeStack.size > 1) {
            popRoute()
        } else if (currentTab != 0) {
            currentTab = 0
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
            .windowInsetsPadding(WindowInsets.systemBars)
    ) {
        com.lovexjy.lexinote.ui.theme.LexiMotion.RouteContent(
            targetState = currentRoute,
            isForward = { old, new -> old is LexiScreenRoute.MainTabs && new !is LexiScreenRoute.MainTabs }
        ) { currentActiveRoute ->
        when (val route = currentActiveRoute) {
            is LexiScreenRoute.MainTabs -> {
                val mainScrollState = rememberScrollState()
                val isCollapsedHeader by remember {
                    derivedStateOf { mainScrollState.value > 60 }
                }

                Box(modifier = Modifier.fillMaxSize()) {
                    Column(modifier = Modifier.fillMaxSize()) {
                        // Top Phone Header Bar (matches Index.ets primaryTitleBar)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(palette.bg_root.toComposeColor())
                                .padding(
                                    horizontal = 16.dp,
                                    vertical = if (isCollapsedHeader) 8.dp else 10.dp
                                ),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (!isCollapsedHeader) {
                                    LexiLogo(
                                        size = 28.dp,
                                        modifier = Modifier.clip(RoundedCornerShape(8.dp))
                                    )
                                    Spacer(modifier = Modifier.width(10.dp))
                                }
                                Text(
                                    text = if (!isCollapsedHeader) {
                                        "LexiNote"
                                    } else {
                                        when (currentTab) {
                                            0 -> trText("首页")
                                            1 -> trText("知识库")
                                            2 -> trText("关联")
                                            else -> trText("我的")
                                        }
                                    },
                                    fontSize = if (isCollapsedHeader) 20.sp else 23.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = palette.text_primary.toComposeColor()
                                )
                            }

                            // Right '+' Quick Create Circle Button & Menu
                            Box {
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(CircleShape)
                                        .background(palette.brand_soft.toComposeColor())
                                        .clickable { showCreateMenu = true },
                                    contentAlignment = Alignment.Center
                                ) {
                                    LexiIcon(name = "plus", size = 20.dp, tint = palette.brand.toComposeColor())
                                }

                                DropdownMenu(
                                    expanded = showCreateMenu,
                                    onDismissRequest = { showCreateMenu = false }
                                ) {
                                    CREATE_ENTRIES.forEach { entry ->
                                        DropdownMenuItem(
                                            text = {
                                                Column {
                                                    Text(
                                                        text = trText(entry.title),
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 14.sp
                                                    )
                                                    Text(
                                                        text = trText(entry.subtitle),
                                                        fontSize = 11.sp,
                                                        color = palette.text_muted.toComposeColor()
                                                    )
                                                }
                                            },
                                            leadingIcon = {
                                                LexiIcon(name = entry.icon, size = 18.dp, palette = palette)
                                            },
                                            onClick = {
                                                showCreateMenu = false
                                                when (entry.key) {
                                                    "note" -> {
                                                        destinationPickerMode = "new_note"
                                                    }
                                                    "mindmap" -> {
                                                        val doc = LexiStorageService.createMindMap(
                                                            title = trText("新建思维导图"),
                                                            vaultId = activeVaultId
                                                        )
                                                        refreshTick += 1
                                                        pushRoute(LexiScreenRoute.MindMapEditor(doc.id))
                                                    }
                                                    "canvas" -> {
                                                        val board = LexiStorageService.createCanvas(
                                                            title = trText("新建自由白板"),
                                                            vaultId = activeVaultId
                                                        )
                                                        refreshTick += 1
                                                        pushRoute(LexiScreenRoute.CanvasEditor(board.id))
                                                    }
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        // Tab Scroll Body
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .verticalScroll(mainScrollState)
                                .padding(top = 6.dp, bottom = 108.dp)
                        ) {
                            when (currentTab) {
                                0 -> LexiHomeTab(
                                    notes = notes,
                                    mindMaps = mindMaps,
                                    canvases = canvases,
                                    links = links,
                                    vaults = vaults,
                                    recentNotesMode = recentNotesMode,
                                    quickCaptureDraft = quickCaptureDraft,
                                    palette = palette,
                                    onQuickCaptureChange = { quickCaptureDraft = it },
                                    onSaveQuickCapture = {
                                        if (quickCaptureDraft.isNotBlank()) {
                                            destinationPickerMode = "quick_capture"
                                        }
                                    },
                                    onExpandQuickCapture = {
                                        val draft = quickCaptureDraft.trim()
                                        val lines = draft.split("\n")
                                        val firstLine = lines.firstOrNull()?.replace(Regex("^#+\\s*"), "")?.trim() ?: ""
                                        val noteTitle = if (firstLine.length in 1..28) {
                                            firstLine
                                        } else if (draft.isNotEmpty()) {
                                            "随手记 ${LexiTemplates.dateKey()}"
                                        } else {
                                            ""
                                        }
                                        val noteContent = if (draft.isNotEmpty()) {
                                            "# $noteTitle\n\n$draft\n"
                                        } else {
                                            ""
                                        }
                                        val created = LexiStorageService.createNote(
                                            title = noteTitle,
                                            content = noteContent,
                                            vaultId = activeVaultId,
                                            projectId = activeProjectId
                                        )
                                        quickCaptureDraft = ""
                                        refreshTick += 1
                                        checkFirstNoteStoragePrompt()
                                        pushRoute(LexiScreenRoute.NoteEditor(created.id))
                                    },
                                    onOpenDailyNote = {
                                        val daily = LexiStorageService.openOrCreateDailyNote(activeVaultId)
                                        refreshTick += 1
                                        checkFirstNoteStoragePrompt()
                                        pushRoute(LexiScreenRoute.NoteEditor(daily.id))
                                    },
                                    onOpenTemplatePicker = { showTemplatePicker = true },
                                    onOpenPluginPanel = { showPluginSheet = true },
                                    onRecentModeChange = { mode ->
                                        recentNotesMode = mode
                                        LexiStorageService.setHomeRecentNotesMode(mode)
                                    },
                                    onOpenNote = { note ->
                                        LexiStorageService.markNoteOpened(note.id)
                                        pushRoute(LexiScreenRoute.NoteEditor(note.id))
                                    },
                                    onTogglePin = { note ->
                                        LexiStorageService.togglePinNote(note.id)
                                        refreshTick += 1
                                    },
                                    onToggleFavorite = { note ->
                                        LexiStorageService.toggleFavoriteNote(note.id)
                                        refreshTick += 1
                                    },
                                    onDeleteNote = { note ->
                                        LexiStorageService.softDeleteNote(note.id)
                                        refreshTick += 1
                                    },
                                    onDuplicateNote = { note ->
                                        LexiStorageService.duplicateNote(note.id)
                                        refreshTick += 1
                                    },
                                    onExportNote = { note ->
                                        shareExportMarkdownFile(note)
                                    },
                                    onSelectTag = { tag ->
                                        selectedTag = tag
                                        currentTab = 1
                                        vaultSectionIndex = 0
                                    },
                                    onJumpToVaultSection = { secIdx ->
                                        currentTab = 1
                                        vaultSectionIndex = secIdx
                                    },
                                    onJumpToExplore = {
                                        currentTab = 2
                                    }
                                )

                                1 -> LexiVaultTab(
                                    notes = notes,
                                    mindMaps = mindMaps,
                                    canvases = canvases,
                                    links = links,
                                    tags = tags,
                                    activeVault = activeVault,
                                    projects = projects,
                                    activeProjectId = activeProjectId,
                                    vaultSectionIndex = vaultSectionIndex,
                                    searchQuery = searchQuery,
                                    noteFilterMode = noteFilterMode,
                                    noteSortMode = noteSortMode,
                                    noteViewMode = noteViewMode,
                                    selectedTag = selectedTag,
                                    palette = palette,
                                    onOpenWorkspaces = { pushRoute(LexiScreenRoute.Workspaces) },
                                    onSelectProject = { projId ->
                                        LexiStorageService.setActiveProjectId(projId, activeVaultId)
                                        refreshTick += 1
                                    },
                                    onSectionChange = { vaultSectionIndex = it },
                                    onSearchQueryChange = { searchQuery = it },
                                    onFilterModeChange = { noteFilterMode = it },
                                    onSortModeChange = { mode ->
                                        noteSortMode = mode
                                        LexiStorageService.setNoteSortMode(mode, activeVaultId)
                                    },
                                    onViewModeChange = { mode ->
                                        noteViewMode = mode
                                        LexiStorageService.setNoteViewMode(mode, activeVaultId)
                                    },
                                    onSelectTag = { selectedTag = it },
                                    onOpenNote = { note ->
                                        LexiStorageService.markNoteOpened(note.id)
                                        pushRoute(LexiScreenRoute.NoteEditor(note.id))
                                    },
                                    onCreateNote = {
                                        destinationPickerMode = "new_note"
                                    },
                                    onTogglePin = { note ->
                                        LexiStorageService.togglePinNote(note.id)
                                        refreshTick += 1
                                    },
                                    onToggleFavorite = { note ->
                                        LexiStorageService.toggleFavoriteNote(note.id)
                                        refreshTick += 1
                                    },
                                    onDeleteNote = { note ->
                                        LexiStorageService.softDeleteNote(note.id)
                                        refreshTick += 1
                                    },
                                    onDuplicateNote = { note ->
                                        LexiStorageService.duplicateNote(note.id)
                                        refreshTick += 1
                                    },
                                    onExportNote = { note ->
                                        shareExportMarkdownFile(note)
                                    },
                                    onOpenMindMap = { doc ->
                                        pushRoute(LexiScreenRoute.MindMapEditor(doc.id))
                                    },
                                    onCreateMindMap = {
                                        val doc = LexiStorageService.createMindMap(
                                            title = trText("新建思维导图"),
                                            vaultId = activeVaultId
                                        )
                                        refreshTick += 1
                                        pushRoute(LexiScreenRoute.MindMapEditor(doc.id))
                                    },
                                    onDeleteMindMap = { doc ->
                                        LexiStorageService.softDeleteMindMap(doc.id)
                                        refreshTick += 1
                                    },
                                    onDuplicateMindMap = { doc ->
                                        LexiStorageService.duplicateMindMap(doc.id)
                                        refreshTick += 1
                                    },
                                    onOpenCanvas = { board ->
                                        pushRoute(LexiScreenRoute.CanvasEditor(board.id))
                                    },
                                    onCreateCanvas = {
                                        val board = LexiStorageService.createCanvas(
                                            title = trText("新建自由白板"),
                                            vaultId = activeVaultId
                                        )
                                        refreshTick += 1
                                        pushRoute(LexiScreenRoute.CanvasEditor(board.id))
                                    },
                                    onDeleteCanvas = { board ->
                                        LexiStorageService.softDeleteCanvas(board.id)
                                        refreshTick += 1
                                    },
                                    onDuplicateCanvas = { board ->
                                        LexiStorageService.duplicateCanvas(board.id)
                                        refreshTick += 1
                                    },
                                    onRenameTag = { oldName, newName ->
                                        LexiStorageService.renameTag(oldName, newName, activeVaultId)
                                        refreshTick += 1
                                    },
                                    onDeleteTag = { tagName ->
                                        LexiStorageService.deleteTag(tagName, activeVaultId)
                                        refreshTick += 1
                                    }
                                )

                                2 -> LexiExploreTab(
                                    notes = notes,
                                    mindMaps = mindMaps,
                                    links = links,
                                    tags = tags,
                                    palette = palette,
                                    onOpenNote = { note ->
                                        LexiStorageService.markNoteOpened(note.id)
                                        pushRoute(LexiScreenRoute.NoteEditor(note.id))
                                    },
                                    onOpenMindMap = { doc ->
                                        pushRoute(LexiScreenRoute.MindMapEditor(doc.id))
                                    },
                                    onSelectTagAndJump = { tag ->
                                        selectedTag = tag
                                        currentTab = 1
                                        vaultSectionIndex = 0
                                    },
                                    onQuickLinkNotes = { source, target ->
                                        val updatedContent = if (source.content.contains("[[${target.title}]]")) {
                                            source.content
                                        } else {
                                            LexiCompletion.linkFirstMention(source.content, target.title)
                                        }
                                        LexiStorageService.saveNote(
                                            source.copy(
                                                content = updatedContent,
                                                updatedAt = System.currentTimeMillis()
                                            )
                                        )
                                        refreshTick += 1
                                    }
                                )

                                else -> LexiProfileTab(
                                    activeVault = activeVault,
                                    noteCount = notes.size,
                                    deletedCount = deletedCount,
                                    palette = palette,
                                    onOpenSettings = { pushRoute(LexiScreenRoute.Settings("")) },
                                    onOpenTrash = { pushRoute(LexiScreenRoute.Trash) },
                                    onOpenHelp = { pushRoute(LexiScreenRoute.Help) }
                                )
                            }
                        }
                    }

                    // Floating Pill Bottom Dock Bar (matches Index.ets dockBarBuilder: height 62, radius 31)
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 14.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(62.dp)
                                .then(
                                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level2,
                                        shape = RoundedCornerShape(31.dp),
                                        dark = palette.dark
                                    )
                                )
                                .clip(RoundedCornerShape(31.dp))
                                .background(palette.dock_bg.toComposeColor())
                                .border(
                                    com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline,
                                    palette.dock_border.toComposeColor(),
                                    RoundedCornerShape(31.dp)
                                )
                                .padding(horizontal = 8.dp),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val dockTabs = listOf(
                                Triple(0, "dock-home", "首页"),
                                Triple(1, "dock-vault", "知识库"),
                                Triple(2, "dock-explore", "关联"),
                                Triple(3, "dock-profile", "我的")
                            )
                            dockTabs.forEach { (idx, iconName, label) ->
                                val active = currentTab == idx
                                val tabInteraction = com.lovexjy.lexinote.ui.theme.LexiMotion.rememberInteraction()
                                Column(
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(48.dp)
                                        .then(com.lovexjy.lexinote.ui.theme.LexiMotion.pressScale(tabInteraction))
                                        .clip(RoundedCornerShape(24.dp))
                                        .then(com.lovexjy.lexinote.ui.theme.LexiMotion.clickTarget(tabInteraction) { currentTab = idx }),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.Center
                                ) {
                                    LexiIcon(
                                        name = iconName,
                                        size = 22.dp,
                                        muted = !active,
                                        palette = palette
                                    )
                                    Spacer(modifier = Modifier.height(3.dp))
                                    Text(
                                        text = trText(label),
                                        fontSize = 10.sp,
                                        fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                                        color = if (active) palette.brand.toComposeColor()
                                        else palette.text_secondary.toComposeColor()
                                    )
                                }
                            }
                        }
                    }
                }
            }

            is LexiScreenRoute.NoteEditor -> {
                val targetNote = remember(route.noteId, refreshTick) {
                    LexiStorageService.getNote(route.noteId)
                        ?: notes.firstOrNull { it.id == route.noteId }
                }
                if (targetNote != null) {
                    NoteEditorScreen(
                        initialNote = targetNote,
                        allNotes = notes,
                        allLinks = links,
                        allMindMaps = mindMaps,
                        allTags = tags,
                        palette = palette,
                        onBack = { popRoute() },
                        onNoteSaved = {
                            refreshTick += 1
                            checkFirstNoteStoragePrompt()
                        },
                        onOpenLinkedNote = { linked ->
                            LexiStorageService.markNoteOpened(linked.id)
                            pushRoute(LexiScreenRoute.NoteEditor(linked.id))
                        },
                        onOpenMindMap = { mm ->
                            pushRoute(LexiScreenRoute.MindMapEditor(mm.id))
                        },
                        onConvertToMindMap = { savedNote ->
                            val mm = LexiStorageService.convertNoteToMindMap(savedNote.id)
                            refreshTick += 1
                            if (mm != null) {
                                pushRoute(LexiScreenRoute.MindMapEditor(mm.id))
                            }
                        },
                        onExportMarkdown = { savedNote ->
                            shareExportMarkdownFile(savedNote)
                        },
                        onSelectTagAndJump = { tag ->
                            selectedTag = tag
                            routeStack = listOf(LexiScreenRoute.MainTabs)
                            currentTab = 1
                            vaultSectionIndex = 0
                        }
                    )
                } else {
                    LaunchedEffect(Unit) { popRoute() }
                }
            }

            is LexiScreenRoute.MindMapEditor -> {
                val targetDoc = remember(route.docId, refreshTick) {
                    LexiStorageService.getMindMap(route.docId)
                        ?: mindMaps.firstOrNull { it.id == route.docId }
                }
                if (targetDoc != null) {
                    MindMapScreen(
                        initialDoc = targetDoc,
                        allNotes = notes,
                        palette = palette,
                        onBack = { popRoute() },
                        onSaved = { refreshTick += 1 },
                        onOpenNote = { n ->
                            pushRoute(LexiScreenRoute.NoteEditor(n.id))
                        },
                        onConvertToNote = { savedDoc ->
                            val createdNote = LexiStorageService.convertMindMapToNote(savedDoc.id)
                            refreshTick += 1
                            if (createdNote != null) {
                                pushRoute(LexiScreenRoute.NoteEditor(createdNote.id))
                            }
                        }
                    )
                } else {
                    LaunchedEffect(Unit) { popRoute() }
                }
            }

            is LexiScreenRoute.CanvasEditor -> {
                val targetBoard = remember(route.boardId, refreshTick) {
                    LexiStorageService.getCanvas(route.boardId)
                        ?: canvases.firstOrNull { it.id == route.boardId }
                }
                if (targetBoard != null) {
                    CanvasScreen(
                        initialBoard = targetBoard,
                        allNotes = notes,
                        palette = palette,
                        onBack = { popRoute() },
                        onSaved = { refreshTick += 1 },
                        onOpenNote = { n ->
                            pushRoute(LexiScreenRoute.NoteEditor(n.id))
                        }
                    )
                } else {
                    LaunchedEffect(Unit) { popRoute() }
                }
            }

            is LexiScreenRoute.Workspaces -> {
                WorkspacesScreen(
                    palette = palette,
                    onBack = { popRoute() },
                    onVaultChanged = { refreshTick += 1 }
                )
            }

            is LexiScreenRoute.Settings -> {
                SettingsScreen(
                    initialCategory = route.initialCategory,
                    palette = palette,
                    onBack = { popRoute() },
                    onSettingsChanged = { refreshTick += 1 },
                    onReplayGuide = {
                        routeStack = listOf(LexiScreenRoute.MainTabs)
                        showWelcomeGuide = true
                    },
                    onOpenHelp = { pushRoute(LexiScreenRoute.Help) }
                )
            }

            is LexiScreenRoute.Trash -> {
                TrashScreen(
                    palette = palette,
                    onBack = { popRoute() },
                    onChanged = { refreshTick += 1 }
                )
            }

            is LexiScreenRoute.Help -> {
                HelpScreen(
                    palette = palette,
                    onBack = { popRoute() }
                )
            }

            is LexiScreenRoute.ShareCapture -> {
                ShareCaptureScreen(
                    initialDraft = route.draft,
                    palette = palette,
                    onBack = { popRoute() },
                    onSavedToNote = { created ->
                        refreshTick += 1
                        routeStack = listOf(
                            LexiScreenRoute.MainTabs,
                            LexiScreenRoute.NoteEditor(created.id)
                        )
                    }
                )
            }
        }
        }

        // Dialogs & Overlays
        if (showTemplatePicker) {
            LexiTemplatePickerDialog(
                palette = palette,
                onDismiss = { showTemplatePicker = false },
                onSelectTemplate = { tpl ->
                    showTemplatePicker = false
                    pendingTemplate = tpl
                    destinationPickerMode = "template"
                }
            )
        }

        if (destinationPickerMode.isNotEmpty()) {
            LexiNoteDestinationPickerDialog(
                title = when (destinationPickerMode) {
                    "quick_capture" -> "保存随手记到..."
                    "template" -> "选择模板创建位置"
                    else -> "选择新建笔记位置"
                },
                palette = palette,
                onDismiss = { destinationPickerMode = "" },
                onConfirm = { chosenVaultId, chosenProjectId ->
                    val mode = destinationPickerMode
                    destinationPickerMode = ""
                    when (mode) {
                        "quick_capture" -> {
                            val lines = quickCaptureDraft.trim().split("\n")
                            val firstLine = lines.firstOrNull()?.replace(Regex("^#+\\s*"), "")?.trim() ?: ""
                            val noteTitle = if (firstLine.length in 1..28) {
                                firstLine
                            } else {
                                "随手记 ${LexiTemplates.dateKey()}"
                            }
                            val created = LexiStorageService.createNote(
                                title = noteTitle,
                                content = "# $noteTitle\n\n${quickCaptureDraft.trim()}\n\n#随手记\n",
                                tags = listOf("随手记"),
                                vaultId = chosenVaultId,
                                projectId = chosenProjectId
                            )
                            quickCaptureDraft = ""
                            refreshTick += 1
                            checkFirstNoteStoragePrompt()
                            pushRoute(LexiScreenRoute.NoteEditor(created.id))
                        }
                        "template" -> {
                            val tpl = pendingTemplate
                            if (tpl != null) {
                                val created = LexiStorageService.createNoteFromTemplate(
                                    templateId = tpl.id,
                                    customTitle = "",
                                    vaultId = chosenVaultId,
                                    projectId = chosenProjectId
                                )
                                refreshTick += 1
                                checkFirstNoteStoragePrompt()
                                pushRoute(LexiScreenRoute.NoteEditor(created.id))
                            }
                        }
                        else -> {
                            val created = LexiStorageService.createNote(
                                title = trText("新建笔记"),
                                content = "# ${trText("新建笔记")}\n\n",
                                vaultId = chosenVaultId,
                                projectId = chosenProjectId
                            )
                            refreshTick += 1
                            checkFirstNoteStoragePrompt()
                            pushRoute(LexiScreenRoute.NoteEditor(created.id))
                        }
                    }
                }
            )
        }

        if (showPluginSheet) {
            LexiMobilePluginSheet(
                palette = palette,
                onDismiss = { showPluginSheet = false },
                onExecuteCommand = { _, cmd ->
                    when {
                        cmd.contains("每日笔记") || cmd.contains("Daily", ignoreCase = true) -> {
                            val daily = LexiStorageService.openOrCreateDailyNote(activeVaultId)
                            refreshTick += 1
                            pushRoute(LexiScreenRoute.NoteEditor(daily.id))
                        }
                        cmd.contains("索引") || cmd.contains("Index", ignoreCase = true) -> {
                            LexiStorageService.rebuildIndex()
                            refreshTick += 1
                        }
                        else -> {
                            val latest = notes.maxByOrNull { it.updatedAt }
                            if (latest != null) {
                                pushRoute(LexiScreenRoute.NoteEditor(latest.id))
                            }
                        }
                    }
                },
                onOpenPluginSettings = {
                    pushRoute(LexiScreenRoute.Settings("plugins"))
                }
            )
        }

        if (showStoragePromptDialog) {
            AlertDialog(
                onDismissRequest = { showStoragePromptDialog = false },
                title = { Text(trText("第一篇笔记已保存")) },
                text = {
                    Text(
                        trText("是否现在选择本地文件夹以同步标准 Markdown (.md) 文件？你也可以稍后在「设置 -> 文件与链接」中随时配置。")
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            showStoragePromptDialog = false
                            folderPickerLauncher.launch(null)
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                    ) {
                        Text(trText("选择本地位置"), color = Color.White)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showStoragePromptDialog = false }) {
                        Text(trText("稍后在设置中选择"), color = palette.text_secondary.toComposeColor())
                    }
                }
            )
        }

        if (showWelcomeGuide && !showLaunchSplash) {
            LexiWelcomeGuide(
                palette = palette,
                onFinish = {
                    LexiStorageService.setOnboardingCompleted(true)
                    showWelcomeGuide = false
                }
            )
        }

        if (showLaunchSplash) {
            LexiLaunchScreen(palette = palette)
        }
    }
}
