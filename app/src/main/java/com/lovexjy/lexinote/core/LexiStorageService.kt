package com.lovexjy.lexinote.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Date
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

data class LexiCapturedNoteSaveResult(
    var note: NoteItem = NoteItem(),
    var duplicate: Boolean = false,
    var alreadySaved: Boolean = false
)

object LexiWorkspacePreferences {
    val keys = setOf(
        "appearanceMode",
        "themeId",
        "customThemeHex",
        "customBackgroundHex",
        "customForegroundHex",
        "customAccentHex",
        "fontSize",
        "quickFontSize",
        "cssSnippets",
        "defaultNewTabView",
        "defaultEditMode",
        "showViewStatus",
        "showInlineTitle",
        "readableLineLength",
        "defaultEditorTier",
        "enabledPlugins",
        "pluginSafeMode",
        "historyRetentionPolicy",
        "noteSortMode",
        "noteViewMode",
        "homeRecentNotesMode"
    )

    fun contains(key: String): Boolean = keys.contains(key)

    fun key(vaultId: String, settingKey: String): String {
        val owner = vaultId.ifEmpty { "default-vault" }
        return "ws:$owner:$settingKey"
    }

    fun pluginIds(rawJson: String): List<String> {
        return try {
            val arr = JSONArray(rawJson)
            val list = mutableListOf<String>()
            for (i in 0 until arr.length()) {
                val id = arr.optString(i, "").trim()
                if (id.isNotEmpty() && !list.contains(id)) list.add(id)
            }
            list
        } catch (_: Exception) {
            emptyList()
        }
    }
}

/**
 * Local-first storage service for LexiNote Android, matching LexiStorageService.ets.
 */
object LexiStorageService {
    private const val STORAGE_ACCESS_PROMPT_STATE = "storageAccessPrompt:v1"

    private var rootDir: File? = null
    private var initialized: Boolean = false
    private var windowVaultId: String = ""
    private var storagePromptNoteId: String = ""

    private val settingsMap = mutableMapOf<String, String>()
    private val vaultsList = mutableListOf<VaultItem>()
    private val projectsList = mutableListOf<LexiProject>()
    private val notesList = mutableListOf<NoteItem>()
    private val mindMapsList = mutableListOf<MindMapDoc>()
    private val canvasesList = mutableListOf<CanvasBoard>()
    private var templateLibraryState = LexiTemplateLibrary.fresh()
    private val historyMap = mutableMapOf<String, MutableList<NoteRevision>>()
    private val walMap = mutableMapOf<String, LexiDraftWalEntry>()
    private val pendingCrashWalMap = mutableMapOf<String, LexiDraftWalEntry>()
    private val installedPlugins = mutableListOf<LexiPluginRecord>()
    private val clipFingerprints = mutableMapOf<String, String>() // fingerprint -> noteId

    private val changeListeners = mutableListOf<() -> Unit>()

    fun addChangeListener(listener: () -> Unit) {
        if (!changeListeners.contains(listener)) {
            changeListeners.add(listener)
        }
    }

    fun removeChangeListener(listener: () -> Unit) {
        changeListeners.remove(listener)
    }

    private fun notifyChanged() {
        for (l in changeListeners.toList()) {
            try {
                l()
            } catch (_: Exception) {
            }
        }
    }

    @Synchronized
    fun init(context: Context) {
        val dir = File(context.filesDir, "lexinote_store")
        if (!dir.exists()) dir.mkdirs()
        if (initialized && rootDir?.absolutePath == dir.absolutePath) return
        rootDir = dir
        loadFromDisk()
        ensureCleanStart()
        promotePendingWalOnStartup()
        initialized = true
    }

    @Synchronized
    fun initForTest(tempDir: File? = null) {
        rootDir = tempDir
        tempDir?.mkdirs()
        settingsMap.clear()
        vaultsList.clear()
        projectsList.clear()
        notesList.clear()
        mindMapsList.clear()
        canvasesList.clear()
        templateLibraryState = LexiTemplateLibrary.fresh()
        historyMap.clear()
        walMap.clear()
        pendingCrashWalMap.clear()
        installedPlugins.clear()
        clipFingerprints.clear()
        windowVaultId = ""
        storagePromptNoteId = ""
        if (tempDir != null) {
            loadFromDisk()
        }
        ensureCleanStart()
        initialized = true
    }

    private fun ensureCleanStart() {
        val now = System.currentTimeMillis()
        var dirty = false
        if (vaultsList.isEmpty()) {
            val defaultVault = VaultItem(
                id = "default-vault",
                name = "我的工作区",
                description = "本地 Markdown 笔记工作区",
                createdAt = now,
                version = 1
            )
            vaultsList.add(defaultVault)
            settingsMap["activeVaultId"] = defaultVault.id
            windowVaultId = defaultVault.id
            dirty = true
        }
        if (windowVaultId.isEmpty()) {
            windowVaultId = getActiveVaultId()
        }
        if (projectsList.isEmpty()) {
            projectsList.add(
                LexiProject(
                    id = "proj-default",
                    vaultId = windowVaultId,
                    name = "核心知识库",
                    color = "#6E44D9",
                    createdAt = now
                )
            )
            dirty = true
        }
        if (notesList.isEmpty()) {
            val baseDir = rootDir?.absolutePath ?: "/data/local/tmp/lexinote"
            val starterNotes = listOf(
                NoteItem(
                    id = "note-welcome",
                    vaultId = windowVaultId,
                    title = "欢迎使用知萤 LexiNote",
                    notebook = "使用指南",
                    content = """
                        ---
                        tags: [欢迎, 指南]
                        status: active
                        ---
                        # 欢迎使用知萤 LexiNote

                        知萤（LexiNote）是一款本地优先的 Markdown 知识库与双链笔记应用。

                        ## 核心特性

                        - [x] 支持 `[[双向链接规范]]` 与未链接提及发现
                        - [x] 支持 LaTeX 数学公式，例如 ${'$'}E = mc^2${'$'}
                        - [ ] 探索知识图谱、思维导图与自由白板

                        #欢迎 #知识管理
                    """.trimIndent(),
                    path = "$baseDir/vaults/$windowVaultId/notes/欢迎使用知萤_LexiNote.md",
                    noteType = "markdown",
                    editorLevel = "pro",
                    tags = mutableListOf("欢迎", "指南", "知识管理"),
                    properties = mutableListOf(NoteProperty("status", "active")),
                    pinned = true,
                    favorite = true,
                    createdAt = now - 3000L,
                    updatedAt = now - 1000L,
                    lastOpenedAt = now - 1000L
                ),
                NoteItem(
                    id = "note-wikilink-spec",
                    vaultId = windowVaultId,
                    title = "双向链接规范",
                    notebook = "使用指南",
                    content = """
                        # 双向链接规范

                        在正文中输入 `[[笔记标题]]` 即可建立双向链接，也可使用 `[[欢迎使用知萤 LexiNote#核心特性|查看核心特性]]` 链接到指定小节。

                        关联阅读：[[知识图谱与思维导图指南]]

                        #双链 #指南
                    """.trimIndent(),
                    path = "$baseDir/vaults/$windowVaultId/notes/双向链接规范.md",
                    noteType = "study",
                    editorLevel = "study",
                    tags = mutableListOf("双链", "指南"),
                    createdAt = now - 2000L,
                    updatedAt = now - 2000L,
                    lastOpenedAt = now - 2000L
                ),
                NoteItem(
                    id = "note-graph-guide",
                    vaultId = windowVaultId,
                    title = "知识图谱与思维导图指南",
                    notebook = "使用指南",
                    content = """
                        # 知识图谱与思维导图指南

                        通过 [[欢迎使用知萤 LexiNote]] 与 [[双向链接规范]]，所有笔记会自动构建确定性力导向知识图谱，并支持一键转换为思维导图。

                        #图谱 #思维导图
                    """.trimIndent(),
                    path = "$baseDir/vaults/$windowVaultId/notes/知识图谱与思维导图指南.md",
                    noteType = "quick",
                    editorLevel = "simple",
                    tags = mutableListOf("图谱", "思维导图"),
                    createdAt = now - 1500L,
                    updatedAt = now - 1500L,
                    lastOpenedAt = now - 1500L
                )
            )
            notesList.addAll(starterNotes)
            for (n in starterNotes) {
                writeNoteMarkdownFile(n)
                recordRevisionInternal(n, "autosave", n.updatedAt)
            }
            dirty = true
        }
        if (mindMapsList.isEmpty()) {
            val nodes = MarkdownEngine.markdownToMindMapNodes("知萤知识结构导图", "", "note-welcome")
            mindMapsList.add(
                MindMapDoc(
                    id = "map-starter",
                    vaultId = windowVaultId,
                    title = "知萤知识结构导图",
                    layoutKind = "right",
                    rootNodeId = "root",
                    nodes = nodes,
                    createdAt = now,
                    updatedAt = now
                )
            )
            dirty = true
        }
        if (canvasesList.isEmpty()) {
            val c1 = CanvasCard(
                id = "card-1",
                title = "核心问题",
                content = "点击卡片即可在下方编辑标题、内容、颜色或关联已有笔记。",
                noteRefId = "note-welcome",
                noteRefTitle = "欢迎使用知萤 LexiNote",
                x = 44f,
                y = 48f,
                colorTag = "purple"
            )
            val c2 = CanvasCard(
                id = "card-2",
                title = "延伸想法",
                content = "拖动卡片改变空间位置，点击连线按钮建立卡片关联。",
                x = 276f,
                y = 148f,
                colorTag = "teal"
            )
            val edge = CanvasEdge(
                id = "edge-1",
                fromId = "card-1",
                toId = "card-2",
                label = "启发"
            )
            canvasesList.add(
                CanvasBoard(
                    id = "canvas-starter",
                    vaultId = windowVaultId,
                    title = "灵感自由白板",
                    cards = mutableListOf(c1, c2),
                    edges = mutableListOf(edge),
                    createdAt = now,
                    updatedAt = now
                )
            )
            dirty = true
        }
        if (installedPlugins.isEmpty()) {
            installedPlugins.add(
                LexiPluginRecord(
                    id = "lexi.plugin.wordstats",
                    name = "字数与阅读时长统计",
                    version = "1.1.0",
                    description = "分析当前工作区笔记总字数、代码块数量、链接密度与预计阅读时长。",
                    permissions = mutableListOf("读取当前工作区笔记"),
                    commands = mutableListOf("生成字数统计报告", "标记长文笔记"),
                    granted = true
                )
            )
            installedPlugins.add(
                LexiPluginRecord(
                    id = "lexi.plugin.review",
                    name = "每日回顾助手",
                    version = "1.2.0",
                    description = "汇总当前工作区今日新增笔记、待办完成率与孤立笔记提醒。",
                    permissions = mutableListOf("读取当前工作区笔记", "插入回顾摘要"),
                    commands = mutableListOf("插入今日回顾小节", "检查未完成待办"),
                    granted = true
                )
            )
            dirty = true
        }
        val lang = settingsMap["language"] ?: LexiI18n.systemLanguage()
        LexiI18n.currentLanguage = if (lang == "en") "en" else "zh-Hans"
        if (dirty) {
            persistToDisk()
        }
    }

    private fun promotePendingWalOnStartup() {
        if (walMap.isNotEmpty()) {
            for ((noteId, entry) in walMap) {
                pendingCrashWalMap[noteId] = entry
            }
            walMap.clear()
            persistToDisk()
        }
    }

    // --- Settings ---

    fun getSetting(key: String, fallback: String = "", vaultId: String = ""): String {
        val scopedKey = if (LexiWorkspacePreferences.contains(key)) {
            val owner = vaultId.ifEmpty { windowVaultId.ifEmpty { getActiveVaultId() } }
            LexiWorkspacePreferences.key(owner, key)
        } else {
            key
        }
        return settingsMap[scopedKey] ?: fallback
    }

    fun setSetting(key: String, value: String, vaultId: String = "") {
        val scopedKey = if (LexiWorkspacePreferences.contains(key)) {
            val owner = vaultId.ifEmpty { windowVaultId.ifEmpty { getActiveVaultId() } }
            LexiWorkspacePreferences.key(owner, key)
        } else {
            key
        }
        settingsMap[scopedKey] = value
        if (key == "language") {
            LexiI18n.currentLanguage = if (value == "en") "en" else "zh-Hans"
        }
        persistToDisk()
        notifyChanged()
    }

    fun deleteSetting(key: String, vaultId: String = "") {
        val scopedKey = if (LexiWorkspacePreferences.contains(key)) {
            val owner = vaultId.ifEmpty { windowVaultId.ifEmpty { getActiveVaultId() } }
            LexiWorkspacePreferences.key(owner, key)
        } else {
            key
        }
        settingsMap.remove(scopedKey)
        persistToDisk()
        notifyChanged()
    }

    fun takeStorageAccessPrompt(): Boolean {
        if (getSetting(STORAGE_ACCESS_PROMPT_STATE, "") != "pending") return false
        setSetting(STORAGE_ACCESS_PROMPT_STATE, "internal")
        return notesList.any { it.trashedAt == 0L } && getSetting("localRootUri", "").isEmpty()
    }

    fun storageLocationStatus(): LexiStorageLocationStatus {
        val localRoot = getSetting("localRootUri", "")
        val vaultId = getActiveVaultId()
        val projectId = getActiveProjectId(vaultId)
        val project = if (projectId.isNotEmpty()) projectsList.find { it.id == projectId } else null
        val vault = vaultsList.find { it.id == vaultId }
        val folderUri = localRoot.ifEmpty {
            project?.folderUri?.ifEmpty { vault?.folderUri ?: "" } ?: vault?.folderUri ?: ""
        }
        return if (folderUri.isNotEmpty()) {
            LexiStorageLocationStatus(
                mode = "external",
                title = "系统公共目录 (Documents/LexiNote)",
                path = folderUri,
                description = "笔记以标准 .md 文件直接存放在您授权的外部文件夹中，支持跨应用访问与备份。"
            )
        } else {
            val internalPath = rootDir?.absolutePath ?: "/data/data/com.lovexjy.lexinote/files/lexinote_store"
            LexiStorageLocationStatus(
                mode = "internal",
                title = "应用私有空间 (Internal Sandbox)",
                path = internalPath,
                description = "当前保存在应用沙盒内，您可随时切换至系统文件夹以在文件管理器中直接查看 .md 文件。"
            )
        }
    }

    fun configureLocalRoot(documentsUri: String): String {
        val clean = documentsUri.trim().ifEmpty { "content://com.android.externalstorage.documents/tree/primary%3ADocuments/LexiNote" }
        setSetting("localRootUri", clean)
        setSetting("localRootPermissionUri", clean)
        setSetting(STORAGE_ACCESS_PROMPT_STATE, "external")
        for (v in vaultsList) {
            if (v.folderUri.isEmpty()) {
                v.folderUri = "$clean/${v.name}"
                v.permissionUri = clean
            }
        }
        persistToDisk()
        notifyChanged()
        return clean
    }

    // --- Vaults & Projects ---

    fun getVaults(includeArchived: Boolean = false): List<VaultItem> {
        return vaultsList.filter { includeArchived || !it.archived }.map { it.copy() }
    }

    fun getActiveVaultId(): String {
        val current = windowVaultId.ifEmpty { settingsMap["activeVaultId"] ?: "default-vault" }
        val activeVaults = getVaults(false)
        if (activeVaults.any { it.id == current }) {
            windowVaultId = current
            return current
        }
        windowVaultId = activeVaults.firstOrNull()?.id ?: "default-vault"
        settingsMap["activeVaultId"] = windowVaultId
        return windowVaultId
    }

    fun setActiveVaultId(vaultId: String) {
        if (vaultsList.any { it.id == vaultId && !it.archived }) {
            windowVaultId = vaultId
            settingsMap["activeVaultId"] = vaultId
            persistToDisk()
            notifyChanged()
        }
    }

    fun createVault(name: String, description: String = "", folderUri: String = ""): VaultItem {
        val cleanName = name.trim().ifEmpty { "新工作区" }
        val vault = VaultItem(
            id = "vault-${System.currentTimeMillis()}-${(100..999).random()}",
            name = cleanName,
            description = description.trim().ifEmpty { "本地 Markdown 笔记工作区" },
            createdAt = System.currentTimeMillis(),
            version = 1,
            folderUri = folderUri,
            permissionUri = folderUri
        )
        vaultsList.add(vault)
        windowVaultId = vault.id
        settingsMap["activeVaultId"] = vault.id
        persistToDisk()
        notifyChanged()
        return vault.copy()
    }

    fun renameVault(vaultId: String, newName: String) {
        val clean = newName.trim()
        if (clean.isEmpty()) return
        val vault = vaultsList.find { it.id == vaultId } ?: return
        vault.name = clean
        persistToDisk()
        notifyChanged()
    }

    fun setVaultArchived(vaultId: String, archived: Boolean) {
        val activeCount = vaultsList.count { !it.archived }
        if (archived && activeCount <= 1) {
            throw IllegalStateException("至少保留一个活动工作区")
        }
        val vault = vaultsList.find { it.id == vaultId } ?: return
        vault.archived = archived
        if (archived && windowVaultId == vaultId) {
            windowVaultId = vaultsList.firstOrNull { !it.archived }?.id ?: "default-vault"
            settingsMap["activeVaultId"] = windowVaultId
        }
        persistToDisk()
        notifyChanged()
    }

    fun toggleVaultFavorite(vaultId: String) {
        val vault = vaultsList.find { it.id == vaultId } ?: return
        vault.favorite = !vault.favorite
        persistToDisk()
        notifyChanged()
    }

    fun deleteVault(vaultId: String) {
        if (vaultsList.size <= 1) {
            throw IllegalStateException("至少保留一个工作区")
        }
        vaultsList.removeAll { it.id == vaultId }
        projectsList.removeAll { it.vaultId == vaultId }
        notesList.removeAll { it.vaultId == vaultId }
        mindMapsList.removeAll { it.vaultId == vaultId }
        canvasesList.removeAll { it.vaultId == vaultId }
        if (windowVaultId == vaultId) {
            windowVaultId = vaultsList.firstOrNull { !it.archived }?.id ?: vaultsList.first().id
            settingsMap["activeVaultId"] = windowVaultId
        }
        persistToDisk()
        notifyChanged()
    }

    fun getProjects(vaultId: String = "", includeArchived: Boolean = false): List<LexiProject> {
        return projectsList.filter {
            (vaultId.isEmpty() || it.vaultId == vaultId) && (includeArchived || !it.archived)
        }.map { it.copy() }
    }

    fun getActiveProjectId(vaultId: String): String {
        val selected = settingsMap["activeProject:$vaultId"] ?: ""
        val projects = getProjects(vaultId, false)
        return if (projects.any { it.id == selected }) selected else ""
    }

    fun setActiveProjectId(vaultId: String, projectId: String) {
        if (projectId.isNotEmpty() && getProjects(vaultId, false).none { it.id == projectId }) {
            throw IllegalArgumentException("项目不存在")
        }
        settingsMap["activeProject:$vaultId"] = projectId
        persistToDisk()
        notifyChanged()
    }

    fun createProject(vaultId: String, name: String, folderUri: String = ""): LexiProject {
        val clean = name.trim().ifEmpty { "新项目" }
        val project = LexiProject(
            id = "proj-${System.currentTimeMillis()}-${(100..999).random()}",
            vaultId = vaultId.ifEmpty { getActiveVaultId() },
            name = clean,
            folderUri = folderUri,
            permissionUri = folderUri,
            createdAt = System.currentTimeMillis()
        )
        projectsList.add(project)
        settingsMap["activeProject:${project.vaultId}"] = project.id
        persistToDisk()
        notifyChanged()
        return project.copy()
    }

    fun renameProject(projectId: String, newName: String) {
        val clean = newName.trim()
        if (clean.isEmpty()) return
        val proj = projectsList.find { it.id == projectId } ?: return
        proj.name = clean
        persistToDisk()
        notifyChanged()
    }

    fun setProjectArchived(projectId: String, archived: Boolean) {
        val proj = projectsList.find { it.id == projectId } ?: return
        proj.archived = archived
        if (archived && settingsMap["activeProject:${proj.vaultId}"] == projectId) {
            settingsMap["activeProject:${proj.vaultId}"] = ""
        }
        persistToDisk()
        notifyChanged()
    }

    fun toggleProjectFavorite(projectId: String) {
        val proj = projectsList.find { it.id == projectId } ?: return
        proj.favorite = !proj.favorite
        persistToDisk()
        notifyChanged()
    }

    fun deleteProject(projectId: String) {
        val proj = projectsList.find { it.id == projectId } ?: return
        projectsList.removeAll { it.id == projectId }
        for (n in notesList) {
            if (n.projectId == projectId) n.projectId = ""
        }
        for (m in mindMapsList) {
            if (m.projectId == projectId) m.projectId = ""
        }
        for (c in canvasesList) {
            if (c.projectId == projectId) c.projectId = ""
        }
        if (settingsMap["activeProject:${proj.vaultId}"] == projectId) {
            settingsMap["activeProject:${proj.vaultId}"] = ""
        }
        persistToDisk()
        notifyChanged()
    }

    // --- Notes ---

    fun getNotes(vaultId: String = "", projectId: String = ""): List<NoteItem> {
        val validProjects = if (vaultId.isNotEmpty()) {
            getProjects(vaultId, false).map { it.id }.toSet()
        } else {
            null
        }
        return notesList.filter { note ->
            val matchVault = vaultId.isEmpty() || note.vaultId == vaultId
            val matchProject = if (projectId.isNotEmpty()) {
                note.projectId == projectId
            } else if (validProjects != null) {
                note.projectId.isEmpty() || validProjects.contains(note.projectId)
            } else {
                true
            }
            matchVault && matchProject
        }.sortedWith { a, b ->
            if (a.pinned != b.pinned) {
                if (a.pinned) -1 else 1
            } else {
                b.updatedAt.compareTo(a.updatedAt)
            }
        }.map { it.deepCopy() }
    }

    fun getNoteById(noteId: String): NoteItem? {
        return notesList.find { it.id == noteId }?.deepCopy()
    }

    fun saveNote(
        note: NoteItem,
        recordHistory: Boolean = true,
        historyReason: String = "autosave"
    ): NoteItem {
        val now = System.currentTimeMillis()
        val isNew = note.id.isEmpty() || notesList.none { it.id == note.id }
        val existing = if (!isNew) notesList.find { it.id == note.id } else null
        val oldTitle = existing?.title?.trim() ?: ""

        val working = note.deepCopy()
        if (working.id.isEmpty()) {
            working.id = "note-$now-${(100..999).random()}"
        }
        if (working.vaultId.isEmpty()) {
            working.vaultId = getActiveVaultId()
        }
        if (working.createdAt <= 0L) {
            working.createdAt = existing?.createdAt ?: now
        }
        working.updatedAt = now
        if (working.lastOpenedAt <= 0L) {
            working.lastOpenedAt = existing?.lastOpenedAt ?: now
        }

        // Parse frontmatter & inline tags
        val fm = LexiFrontmatter.parse(working.content)
        val inlineTags = MarkdownEngine.extractInlineTags(fm.body)
        val mergedTags = mutableListOf<String>()
        for (t in working.tags + fm.tags + inlineTags) {
            val clean = t.removePrefix("#").trim()
            if (clean.isNotEmpty() && !mergedTags.contains(clean)) {
                mergedTags.add(clean)
            }
        }
        working.tags = mergedTags

        if (working.title.trim().isEmpty()) {
            working.title = MarkdownEngine.displayTitle(working)
        }

        if (working.path.isEmpty()) {
            val baseDir = rootDir?.absolutePath ?: "/data/local/tmp/lexinote"
            val safeName = working.title.replace(Regex("""[/\\:*?"<>|\r\n]+"""), "_").take(60).ifEmpty { working.id }
            working.path = "$baseDir/vaults/${working.vaultId}/notes/$safeName.md"
        }

        if (existing != null) {
            val idx = notesList.indexOfFirst { it.id == working.id }
            if (idx >= 0) notesList[idx] = working
        } else {
            notesList.add(0, working)
            if (settingsMap[STORAGE_ACCESS_PROMPT_STATE].isNullOrEmpty() &&
                settingsMap["localRootUri"].isNullOrEmpty()
            ) {
                settingsMap[STORAGE_ACCESS_PROMPT_STATE] = "pending"
            }
        }

        // Propagate wiki-link and mindmap reference renames if title changed
        val newTitle = working.title.trim()
        if (oldTitle.isNotEmpty() && newTitle.isNotEmpty() && oldTitle != newTitle) {
            for (other in notesList) {
                if (other.id != working.id && other.vaultId == working.vaultId && other.trashedAt == 0L) {
                    val updatedContent = MarkdownEngine.renameLinksInMarkdown(other.content, oldTitle, newTitle)
                    if (updatedContent != other.content) {
                        other.content = updatedContent
                        other.updatedAt = now
                    }
                }
            }
            for (map in mindMapsList) {
                if (map.vaultId == working.vaultId) {
                    for (node in map.nodes) {
                        if (node.noteRefId == working.id) {
                            node.noteRefTitle = newTitle
                        }
                    }
                }
            }
            for (board in canvasesList) {
                if (board.vaultId == working.vaultId) {
                    for (card in board.cards) {
                        if (card.noteRefId == working.id) {
                            card.noteRefTitle = newTitle
                        }
                    }
                }
            }
        }

        if (recordHistory) {
            recordRevisionInternal(working, historyReason, now)
        }

        writeNoteMarkdownFile(working)
        clearDraftWalSync(working.id)
        persistToDisk()
        notifyChanged()
        return working.deepCopy()
    }

    fun createQuickCapture(content: String, vaultId: String = "", projectId: String = ""): NoteItem {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val firstLine = content.split("\n")
            .map { it.replace(Regex("""^[#>*\-\s]+"""), "").trim() }
            .firstOrNull { it.isNotEmpty() }
            ?.take(28)
            ?: "随手速记"
        val note = NoteItem(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = firstLine,
            notebook = "速记收件箱",
            content = content.trim(),
            noteType = "quick",
            editorLevel = getSetting("defaultEditorTier", "simple", targetVaultId)
        )
        return saveNote(note, recordHistory = true, historyReason = "autosave")
    }

    fun openOrCreateDailyNote(vaultId: String = "", projectId: String = "", now: Date = Date()): NoteItem {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val todayTitle = LexiTemplates.dateKey(now)
        val existing = notesList.find {
            it.trashedAt == 0L &&
                it.vaultId == targetVaultId &&
                it.projectId == targetProjectId &&
                it.title.trim() == todayTitle
        }
        if (existing != null) {
            recordNoteOpened(existing.id)
            return existing.deepCopy()
        }
        val defaultTplId = templateLibraryState.defaultDailyId
        val tpl = templateLibraryState.templates.find { it.id == defaultTplId }
            ?: templateLibraryState.templates.firstOrNull()
        val renderedContent = if (tpl != null) {
            LexiTemplates.render(tpl.content, todayTitle, now)
        } else {
            "# $todayTitle\n\n## 今日重点\n\n- [ ] \n"
        }
        val note = NoteItem(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = todayTitle,
            notebook = "每日记录",
            content = renderedContent,
            noteType = "quick",
            editorLevel = getSetting("defaultEditorTier", "simple", targetVaultId),
            tags = (tpl?.tags ?: mutableListOf("日记")).toMutableList(),
            properties = (tpl?.properties?.map { it.copy() } ?: emptyList()).toMutableList()
        )
        return saveNote(note, recordHistory = true, historyReason = "autosave")
    }

    fun createNoteFromTemplate(
        templateId: String,
        customTitle: String = "",
        vaultId: String = "",
        projectId: String = "",
        now: Date = Date()
    ): NoteItem {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val tpl = templateLibraryState.templates.find { it.id == templateId }
            ?: LexiTemplateLibrary.builtins().first()
        val title = customTitle.trim().ifEmpty { "${tpl.title} ${LexiTemplates.dateKey(now)}" }
        val rendered = LexiTemplates.render(tpl.content, title, now)
        val noteType = when (tpl.category) {
            "学习" -> "study"
            "代码", "项目" -> "markdown"
            else -> "quick"
        }
        val editorLevel = when (noteType) {
            "study" -> "study"
            "markdown" -> "pro"
            else -> getSetting("defaultEditorTier", "simple", targetVaultId)
        }
        val note = NoteItem(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = title,
            notebook = tpl.category.ifEmpty { "模板笔记" },
            content = rendered,
            noteType = noteType,
            editorLevel = editorLevel,
            tags = tpl.tags.toMutableList(),
            properties = tpl.properties.map { it.copy() }.toMutableList()
        )
        return saveNote(note, recordHistory = true, historyReason = "autosave")
    }

    fun saveNoteAsTemplate(note: NoteItem, customTitle: String = "", category: String = "自定义"): LexiTemplateItem {
        val now = System.currentTimeMillis()
        val title = customTitle.trim().ifEmpty { MarkdownEngine.displayTitle(note) }
        val item = LexiTemplateItem(
            id = "tpl-$now-${(100..999).random()}",
            title = title,
            content = LexiFrontmatter.parse(note.content).body.ifEmpty { note.content },
            category = category.trim().ifEmpty { "自定义" },
            tags = note.tags.toMutableList(),
            properties = note.properties.map { it.copy() }.toMutableList(),
            builtIn = false,
            sourceNoteId = note.id,
            createdAt = now,
            updatedAt = now
        )
        templateLibraryState.templates.add(item)
        persistToDisk()
        notifyChanged()
        return LexiTemplateLibrary.clone(item)
    }

    fun togglePin(noteId: String) {
        val note = notesList.find { it.id == noteId } ?: return
        note.pinned = !note.pinned
        note.updatedAt = System.currentTimeMillis()
        writeNoteMarkdownFile(note)
        persistToDisk()
        notifyChanged()
    }

    fun toggleFavorite(noteId: String) {
        val note = notesList.find { it.id == noteId } ?: return
        note.favorite = !note.favorite
        note.updatedAt = System.currentTimeMillis()
        writeNoteMarkdownFile(note)
        persistToDisk()
        notifyChanged()
    }

    fun moveToTrash(noteId: String) {
        val note = notesList.find { it.id == noteId } ?: return
        note.trashedAt = System.currentTimeMillis()
        note.pinned = false
        writeNoteMarkdownFile(note)
        persistToDisk()
        notifyChanged()
    }

    fun restoreFromTrash(noteId: String) {
        val note = notesList.find { it.id == noteId } ?: return
        note.trashedAt = 0L
        note.updatedAt = System.currentTimeMillis()
        writeNoteMarkdownFile(note)
        persistToDisk()
        notifyChanged()
    }

    fun deleteForever(noteId: String) {
        val note = notesList.find { it.id == noteId }
        notesList.removeAll { it.id == noteId }
        historyMap.remove(noteId)
        clearDraftWalSync(noteId)
        if (note != null && note.path.isNotEmpty()) {
            try {
                File(note.path).delete()
            } catch (_: Exception) {
            }
        }
        persistToDisk()
        notifyChanged()
    }

    fun emptyTrash(vaultId: String = "") {
        val toRemove = notesList.filter { it.trashedAt > 0L && (vaultId.isEmpty() || it.vaultId == vaultId) }
        for (n in toRemove) {
            historyMap.remove(n.id)
            if (n.path.isNotEmpty()) {
                try {
                    File(n.path).delete()
                } catch (_: Exception) {
                }
            }
        }
        notesList.removeAll { it.trashedAt > 0L && (vaultId.isEmpty() || it.vaultId == vaultId) }
        mindMapsList.removeAll { it.trashedAt > 0L && (vaultId.isEmpty() || it.vaultId == vaultId) }
        persistToDisk()
        notifyChanged()
    }

    fun recordNoteOpened(noteId: String, openedAt: Long = 0L): Long {
        val note = notesList.find { it.id == noteId } ?: return 0L
        val stamp = if (openedAt > 0L) openedAt else System.currentTimeMillis()
        note.lastOpenedAt = maxOf(note.lastOpenedAt, stamp)
        persistToDisk()
        return stamp
    }

    fun duplicateNote(noteId: String): NoteItem? {
        val src = notesList.find { it.id == noteId } ?: return null
        val copy = src.deepCopy().apply {
            id = ""
            title = "${MarkdownEngine.displayTitle(src)} 副本"
            path = ""
            pinned = false
            createdAt = System.currentTimeMillis()
            updatedAt = createdAt
        }
        return saveNote(copy, recordHistory = true, historyReason = "manual")
    }

    fun establishMention(mention: UnlinkedMention): Boolean {
        val source = notesList.find { it.id == mention.sourceId && it.trashedAt == 0L } ?: return false
        val updated = LexiCompletion.linkFirstMention(source.content, mention.targetTitle)
        if (updated == source.content) return false
        source.content = updated
        saveNote(source, recordHistory = true, historyReason = "autosave")
        return true
    }

    fun connectNotes(sourceNoteId: String, targetNoteId: String): Boolean {
        val source = notesList.find { it.id == sourceNoteId && it.trashedAt == 0L } ?: return false
        val target = notesList.find { it.id == targetNoteId && it.trashedAt == 0L } ?: return false
        val targetTitle = MarkdownEngine.displayTitle(target)
        val updated = LexiCompletion.linkFirstMention(source.content, targetTitle)
        source.content = if (updated != source.content) {
            updated
        } else {
            val sep = if (source.content.endsWith("\n") || source.content.isEmpty()) "" else "\n"
            "${source.content}$sep\n相关笔记：[[$targetTitle]]\n"
        }
        saveNote(source, recordHistory = true, historyReason = "autosave")
        return true
    }

    // --- MindMaps ---

    fun getMindMaps(vaultId: String = "", projectId: String = ""): List<MindMapDoc> {
        val validProjects = if (vaultId.isNotEmpty()) {
            getProjects(vaultId, false).map { it.id }.toSet()
        } else {
            null
        }
        return mindMapsList.filter { map ->
            val matchVault = vaultId.isEmpty() || map.vaultId == vaultId
            val matchProject = if (projectId.isNotEmpty()) {
                map.projectId == projectId
            } else if (validProjects != null) {
                map.projectId.isEmpty() || validProjects.contains(map.projectId)
            } else {
                true
            }
            matchVault && matchProject
        }.sortedByDescending { it.updatedAt }.map { it.deepCopy() }
    }

    fun getMindMapById(mapId: String): MindMapDoc? {
        return mindMapsList.find { it.id == mapId }?.deepCopy()
    }

    fun saveMindMap(doc: MindMapDoc): MindMapDoc {
        val now = System.currentTimeMillis()
        val working = doc.deepCopy()
        for (n in working.nodes) {
            if (n.noteId.isNotEmpty() && n.noteRefId != n.noteId) n.noteRefId = n.noteId
            if (n.noteRefId.isNotEmpty() && n.noteId.isEmpty()) n.noteId = n.noteRefId
            if (n.noteRefId.isNotEmpty() && n.noteRefTitle.isEmpty()) {
                val targetNote = notesList.find { it.id == n.noteRefId }
                if (targetNote != null) n.noteRefTitle = MarkdownEngine.displayTitle(targetNote)
            }
        }
        if (working.id.isEmpty()) {
            working.id = "map-$now-${(100..999).random()}"
        }
        if (working.vaultId.isEmpty()) {
            working.vaultId = getActiveVaultId()
        }
        if (working.createdAt <= 0L) {
            working.createdAt = now
        }
        working.updatedAt = now
        if (working.title.trim().isEmpty()) {
            val root = working.nodes.find { it.id == working.rootNodeId } ?: working.nodes.firstOrNull()
            working.title = root?.text?.trim()?.ifEmpty { "未命名导图" } ?: "未命名导图"
        }
        val idx = mindMapsList.indexOfFirst { it.id == working.id }
        if (idx >= 0) {
            mindMapsList[idx] = working
        } else {
            mindMapsList.add(0, working)
        }
        persistToDisk()
        notifyChanged()
        return working.deepCopy()
    }

    fun createStarterMindMap(title: String = "知识结构导图", vaultId: String = "", projectId: String = ""): MindMapDoc {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val nodes = MarkdownEngine.markdownToMindMapNodes(title, "")
        val doc = MindMapDoc(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = title,
            layoutKind = "right",
            rootNodeId = "root",
            nodes = nodes
        )
        return saveMindMap(doc)
    }

    fun createMindMapFromNote(note: NoteItem): MindMapDoc {
        val title = MarkdownEngine.displayTitle(note)
        val body = LexiFrontmatter.parse(note.content).body
        val nodes = MarkdownEngine.markdownToMindMapNodes(title, body, note.id)
        val doc = MindMapDoc(
            vaultId = note.vaultId.ifEmpty { getActiveVaultId() },
            projectId = note.projectId,
            title = "$title · 导图",
            layoutKind = "right",
            rootNodeId = "root",
            nodes = nodes
        )
        return saveMindMap(doc)
    }

    fun toggleMindMapFavorite(mapId: String) {
        val map = mindMapsList.find { it.id == mapId } ?: return
        map.favorite = !map.favorite
        map.updatedAt = System.currentTimeMillis()
        persistToDisk()
        notifyChanged()
    }

    fun trashMindMap(mapId: String) {
        val map = mindMapsList.find { it.id == mapId } ?: return
        map.trashedAt = System.currentTimeMillis()
        persistToDisk()
        notifyChanged()
    }

    fun restoreMindMapFromTrash(mapId: String) {
        val map = mindMapsList.find { it.id == mapId } ?: return
        map.trashedAt = 0L
        map.updatedAt = System.currentTimeMillis()
        persistToDisk()
        notifyChanged()
    }

    fun deleteMindMapForever(mapId: String) {
        mindMapsList.removeAll { it.id == mapId }
        persistToDisk()
        notifyChanged()
    }

    // --- Canvases ---

    fun getCanvases(vaultId: String = "", projectId: String = ""): List<CanvasBoard> {
        val validProjects = if (vaultId.isNotEmpty()) {
            getProjects(vaultId, false).map { it.id }.toSet()
        } else {
            null
        }
        return canvasesList.filter { board ->
            val matchVault = vaultId.isEmpty() || board.vaultId == vaultId
            val matchProject = if (projectId.isNotEmpty()) {
                board.projectId == projectId
            } else if (validProjects != null) {
                board.projectId.isEmpty() || validProjects.contains(board.projectId)
            } else {
                true
            }
            matchVault && matchProject
        }.sortedByDescending { it.updatedAt }.map { it.deepCopy() }
    }

    fun getCanvasById(canvasId: String): CanvasBoard? {
        return canvasesList.find { it.id == canvasId }?.deepCopy()
    }

    fun saveCanvas(board: CanvasBoard): CanvasBoard {
        val now = System.currentTimeMillis()
        val working = board.deepCopy()
        for (c in working.cards) {
            if (c.noteId.isNotEmpty() && c.noteRefId != c.noteId) c.noteRefId = c.noteId
            if (c.noteRefId.isNotEmpty() && c.noteId.isEmpty()) c.noteId = c.noteRefId
            if (c.noteRefId.isNotEmpty() && c.noteRefTitle.isEmpty()) {
                val targetNote = notesList.find { it.id == c.noteRefId }
                if (targetNote != null) c.noteRefTitle = MarkdownEngine.displayTitle(targetNote)
            }
        }
        for (e in working.edges) {
            if (e.fromCardId.isNotEmpty() && e.fromId != e.fromCardId) e.fromId = e.fromCardId
            if (e.fromId.isNotEmpty() && e.fromCardId.isEmpty()) e.fromCardId = e.fromId
            if (e.toCardId.isNotEmpty() && e.toId != e.toCardId) e.toId = e.toCardId
            if (e.toId.isNotEmpty() && e.toCardId.isEmpty()) e.toCardId = e.toId
        }
        if (working.id.isEmpty()) {
            working.id = "canvas-$now-${(100..999).random()}"
        }
        if (working.vaultId.isEmpty()) {
            working.vaultId = getActiveVaultId()
        }
        if (working.createdAt <= 0L) {
            working.createdAt = now
        }
        working.updatedAt = now
        if (working.title.trim().isEmpty()) {
            working.title = "未命名白板"
        }
        val idx = canvasesList.indexOfFirst { it.id == working.id }
        if (idx >= 0) {
            canvasesList[idx] = working
        } else {
            canvasesList.add(0, working)
        }
        persistToDisk()
        notifyChanged()
        return working.deepCopy()
    }

    fun createStarterCanvas(title: String = "灵感自由白板", vaultId: String = "", projectId: String = ""): CanvasBoard {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val c1 = CanvasCard(
            id = "card-1",
            title = "核心问题",
            content = "点击卡片即可在下方编辑标题、内容、颜色或关联已有笔记。",
            x = 44f,
            y = 48f,
            colorTag = "purple"
        )
        val c2 = CanvasCard(
            id = "card-2",
            title = "延伸想法",
            content = "拖动卡片改变空间位置，在下方点击其他卡片即可建立或断开连线。",
            x = 276f,
            y = 148f,
            colorTag = "teal"
        )
        val edge = CanvasEdge(
            id = "edge-1",
            fromId = "card-1",
            toId = "card-2",
            label = "启发"
        )
        val board = CanvasBoard(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = title,
            cards = mutableListOf(c1, c2),
            edges = mutableListOf(edge)
        )
        return saveCanvas(board)
    }

    fun deleteCanvas(canvasId: String) {
        canvasesList.removeAll { it.id == canvasId }
        persistToDisk()
        notifyChanged()
    }

    // --- Templates ---

    fun getTemplates(): List<LexiTemplateItem> {
        return templateLibraryState.templates.map { LexiTemplateLibrary.clone(it) }
    }

    fun getDefaultDailyTemplateId(): String {
        return templateLibraryState.defaultDailyId
    }

    fun setDefaultDailyTemplateId(id: String) {
        if (id.isEmpty() || templateLibraryState.templates.any { it.id == id }) {
            templateLibraryState.defaultDailyId = id
            persistToDisk()
            notifyChanged()
        }
    }

    fun saveTemplate(item: LexiTemplateItem): LexiTemplateItem {
        val now = System.currentTimeMillis()
        val working = LexiTemplateLibrary.clone(item)
        if (working.id.isEmpty()) {
            working.id = "tpl-$now-${(100..999).random()}"
        }
        if (working.createdAt <= 0L) working.createdAt = now
        working.updatedAt = now
        val idx = templateLibraryState.templates.indexOfFirst { it.id == working.id }
        if (idx >= 0) {
            templateLibraryState.templates[idx] = working
        } else {
            templateLibraryState.templates.add(working)
        }
        persistToDisk()
        notifyChanged()
        return LexiTemplateLibrary.clone(working)
    }

    fun deleteTemplate(id: String) {
        val tpl = templateLibraryState.templates.find { it.id == id } ?: return
        if (tpl.builtIn) return
        templateLibraryState.templates.removeAll { it.id == id }
        if (templateLibraryState.defaultDailyId == id) {
            templateLibraryState.defaultDailyId = templateLibraryState.templates.firstOrNull()?.id ?: ""
        }
        persistToDisk()
        notifyChanged()
    }

    // --- History & Crash Recovery WAL ---

    fun getHistoryPolicy(vaultId: String = ""): LexiHistoryRetentionPolicy {
        val raw = getSetting("historyRetentionPolicy", "", vaultId)
        if (raw.isEmpty()) return LexiNoteHistory.defaultPolicy()
        return try {
            val obj = JSONObject(raw)
            LexiNoteHistory.clampPolicy(
                LexiHistoryRetentionPolicy(
                    maxAgeDays = obj.optInt("maxAgeDays", 30),
                    maxCountPerNote = obj.optInt("maxCountPerNote", 30),
                    maxBytesPerNote = obj.optInt("maxBytesPerNote", 2 * 1024 * 1024),
                    maxTotalBytes = obj.optInt("maxTotalBytes", 50 * 1024 * 1024)
                )
            )
        } catch (_: Exception) {
            LexiNoteHistory.defaultPolicy()
        }
    }

    fun saveHistoryPolicy(policy: LexiHistoryRetentionPolicy, vaultId: String = "") {
        val clamped = LexiNoteHistory.clampPolicy(policy)
        val obj = JSONObject().apply {
            put("maxAgeDays", clamped.maxAgeDays)
            put("maxCountPerNote", clamped.maxCountPerNote)
            put("maxBytesPerNote", clamped.maxBytesPerNote)
            put("maxTotalBytes", clamped.maxTotalBytes)
        }
        setSetting("historyRetentionPolicy", obj.toString(), vaultId)
        pruneAllHistoryNow()
    }

    private fun recordRevisionInternal(note: NoteItem, reason: String, now: Long) {
        val policy = getHistoryPolicy(note.vaultId)
        val existing = historyMap[note.id] ?: mutableListOf()
        val candidate = LexiNoteHistory.buildRevision(
            id = "rev-$now-${(100..999).random()}",
            snapshot = note,
            savedAt = now,
            reason = reason
        )
        val updated = LexiNoteHistory.appendAndPrune(existing, candidate, policy, now)
        historyMap[note.id] = updated
    }

    fun getNoteRevisions(noteId: String): List<NoteRevision> {
        return (historyMap[noteId] ?: emptyList()).map { LexiNoteHistory.normalizeRevision(it) }
    }

    fun saveManualRevision(note: NoteItem): List<NoteRevision> {
        val now = System.currentTimeMillis()
        recordRevisionInternal(note, "manual", now)
        persistToDisk()
        notifyChanged()
        return getNoteRevisions(note.id)
    }

    fun restoreNoteRevision(noteId: String, revisionId: String): NoteItem? {
        val current = notesList.find { it.id == noteId } ?: return null
        val targetRev = historyMap[noteId]?.find { it.id == revisionId } ?: return null
        val now = System.currentTimeMillis()
        recordRevisionInternal(current, "restore-backup", now)
        val restored = targetRev.snapshot.deepCopy().apply {
            id = current.id
            vaultId = current.vaultId
            projectId = current.projectId
            trashedAt = 0L
            updatedAt = now + 1
        }
        return saveNote(restored, recordHistory = true, historyReason = "manual")
    }

    fun getHistoryUsageSummary(): LexiHistoryUsageSummary {
        val entries = historyMap.map { (id, revs) -> LexiHistoryNoteEntry(id, revs) }
        return LexiNoteHistory.summarize(entries)
    }

    fun pruneAllHistoryNow(): Int {
        val policy = getHistoryPolicy()
        val entries = historyMap.map { (id, revs) -> LexiHistoryNoteEntry(id, revs) }
        val res = LexiNoteHistory.pruneAllEntries(entries, policy)
        historyMap.clear()
        for (e in res.entries) {
            historyMap[e.noteId] = e.revisions
        }
        persistToDisk()
        notifyChanged()
        return res.removedCount
    }

    fun clearAllHistory() {
        historyMap.clear()
        persistToDisk()
        notifyChanged()
    }

    fun writeDraftWalSync(entry: LexiDraftWalEntry): Boolean {
        if (entry.noteId.isEmpty()) return false
        walMap[entry.noteId] = entry.copy(
            tags = entry.tags.toMutableList(),
            properties = entry.properties.map { it.copy() }.toMutableList(),
            updatedAt = System.currentTimeMillis()
        )
        return true
    }

    fun clearDraftWalSync(noteId: String) {
        walMap.remove(noteId)
    }

    fun getPendingCrashDraftSync(noteId: String): LexiDraftWalEntry? {
        return pendingCrashWalMap[noteId]?.copy()
    }

    fun clearPendingCrashRecoverySync(noteId: String) {
        pendingCrashWalMap.remove(noteId)
    }

    // --- Plugins ---

    fun getInstalledPlugins(): List<LexiPluginRecord> {
        return installedPlugins.map {
            it.copy(
                permissions = it.permissions.toMutableList(),
                commands = it.commands.toMutableList()
            )
        }
    }

    fun installSamplePlugin(kind: String = "wordcount"): LexiPluginRecord {
        val record = when (kind) {
            "review" -> LexiPluginRecord(
                id = "lexi.plugin.review",
                name = "每日回顾助手",
                version = "1.2.0",
                description = "汇总当前工作区今日新增笔记、待办完成率与孤立笔记提醒。",
                permissions = mutableListOf("读取当前工作区笔记", "插入回顾摘要"),
                commands = mutableListOf("插入今日回顾小节", "检查未完成待办"),
                granted = true
            )
            else -> LexiPluginRecord(
                id = "lexi.plugin.wordstats",
                name = "字数与阅读时长统计",
                version = "1.1.0",
                description = "分析当前工作区笔记总字数、代码块数量、链接密度与预计阅读时长。",
                permissions = mutableListOf("读取当前工作区笔记"),
                commands = mutableListOf("生成字数统计报告", "标记长文笔记"),
                granted = true
            )
        }
        installedPlugins.removeAll { it.id == record.id }
        installedPlugins.add(record)
        setPluginEnabled(record.id, true)
        persistToDisk()
        notifyChanged()
        return record.copy()
    }

    fun uninstallPlugin(pluginId: String) {
        installedPlugins.removeAll { it.id == pluginId }
        for (v in vaultsList) {
            setPluginEnabled(pluginId, false, v.id)
        }
        persistToDisk()
        notifyChanged()
    }

    fun getEnabledPlugins(vaultId: String = ""): List<String> {
        val owner = vaultId.ifEmpty { getActiveVaultId() }
        if (getSetting("pluginSafeMode", "false", owner) == "true") return emptyList()
        return LexiWorkspacePreferences.pluginIds(getSetting("enabledPlugins", "[]", owner))
    }

    fun setPluginEnabled(pluginId: String, enabled: Boolean, vaultId: String = "") {
        val owner = vaultId.ifEmpty { getActiveVaultId() }
        val current = LexiWorkspacePreferences.pluginIds(getSetting("enabledPlugins", "[]", owner)).toMutableList()
        current.removeAll { it == pluginId }
        if (enabled) current.add(pluginId)
        val arr = JSONArray(current)
        setSetting("enabledPlugins", arr.toString(), owner)
    }

    fun setPluginPermissionGranted(pluginId: String, granted: Boolean) {
        val plugin = installedPlugins.find { it.id == pluginId } ?: return
        plugin.granted = granted
        persistToDisk()
        notifyChanged()
    }

    // --- System Share Clipping ---

    fun buildShareMarkdown(draft: LexiShareDraft): String {
        val title = draft.title.trim().ifEmpty { "网页与文本剪藏" }
        val lines = mutableListOf("# $title", "")
        if (draft.url.trim().isNotEmpty()) {
            lines.add("> 来源链接：[${draft.url.trim()}](${draft.url.trim()})")
            lines.add("")
        }
        if (draft.comment.trim().isNotEmpty()) {
            lines.add("## 批注与想法")
            lines.add("")
            lines.add(draft.comment.trim())
            lines.add("")
        }
        if (draft.content.trim().isNotEmpty()) {
            lines.add("## 剪藏内容")
            lines.add("")
            lines.add(draft.content.trim())
            lines.add("")
        }
        lines.add("#剪藏")
        return lines.joinToString("\n")
    }

    fun saveSharedClip(
        draft: LexiShareDraft,
        vaultId: String = "",
        projectId: String = ""
    ): LexiCapturedNoteSaveResult {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val fp = draft.fingerprint.ifEmpty {
            LexiNoteHistory.fnv1aHex("${draft.title}|${draft.url}|${draft.content}|$targetVaultId|$targetProjectId")
        }
        val existingId = clipFingerprints[fp]
        if (existingId != null) {
            val existingNote = notesList.find { it.id == existingId && it.trashedAt == 0L }
            if (existingNote != null) {
                return LexiCapturedNoteSaveResult(note = existingNote.deepCopy(), duplicate = true, alreadySaved = true)
            }
        }
        val props = mutableListOf<NoteProperty>()
        if (draft.url.trim().isNotEmpty()) {
            props.add(NoteProperty("source", draft.url.trim()))
        }
        val note = NoteItem(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = draft.title.trim().ifEmpty { "网页与文本剪藏" },
            notebook = "剪藏收件箱",
            content = buildShareMarkdown(draft),
            noteType = "markdown",
            editorLevel = "pro",
            tags = mutableListOf("剪藏"),
            properties = props
        )
        val saved = saveNote(note, recordHistory = true, historyReason = "autosave")
        clipFingerprints[fp] = saved.id
        return LexiCapturedNoteSaveResult(note = saved, duplicate = false, alreadySaved = false)
    }

    // --- Import / Export / Backup ---

    fun exportBackupJson(): String {
        val root = JSONObject()
        root.put("format", "LexiNote.Backup")
        root.put("version", 1)
        root.put("exportedAt", System.currentTimeMillis())
        root.put("vaults", serializeVaultsJson(vaultsList))
        root.put("projects", serializeProjectsJson(projectsList))
        root.put("notes", serializeNotesJson(notesList))
        root.put("mindMaps", serializeMindMapsJson(mindMapsList))
        root.put("canvases", serializeCanvasesJson(canvasesList))
        root.put("templateLibrary", LexiTemplateLibrary.encode(templateLibraryState))
        return root.toString(2)
    }

    fun importBackupJson(rawJson: String): Boolean {
        val obj = try {
            JSONObject(rawJson)
        } catch (_: Exception) {
            return false
        }
        if (obj.optString("format") != "LexiNote.Backup") {
            return false
        }
        val importedVaults = parseVaultsJson(obj.optJSONArray("vaults") ?: JSONArray())
        val importedProjects = parseProjectsJson(obj.optJSONArray("projects") ?: JSONArray())
        val importedNotes = parseNotesJson(obj.optJSONArray("notes") ?: JSONArray())
        val importedMaps = parseMindMapsJson(obj.optJSONArray("mindMaps") ?: JSONArray())
        val importedCanvases = parseCanvasesJson(obj.optJSONArray("canvases") ?: JSONArray())
        val tplRaw = obj.optString("templateLibrary", "")
        if (tplRaw.isNotEmpty()) {
            try {
                templateLibraryState = LexiTemplateLibrary.decode(tplRaw)
            } catch (_: Exception) {
            }
        }
        if (importedVaults.isNotEmpty()) {
            vaultsList.clear()
            vaultsList.addAll(importedVaults)
        }
        projectsList.clear()
        projectsList.addAll(importedProjects)
        notesList.clear()
        notesList.addAll(importedNotes)
        mindMapsList.clear()
        mindMapsList.addAll(importedMaps)
        canvasesList.clear()
        canvasesList.addAll(importedCanvases)
        ensureCleanStart()
        persistToDisk()
        notifyChanged()
        return true
    }

    fun exportSettingsAndPluginsJson(): String {
        val root = JSONObject()
        root.put("format", "LexiNote.SettingsPlugins")
        root.put("version", 1)
        root.put("exportedAt", System.currentTimeMillis())
        val settingsArr = JSONArray()
        for ((k, v) in settingsMap) {
            val entry = JSONObject()
            entry.put("key", k)
            entry.put("value", v)
            settingsArr.put(entry)
        }
        root.put("settings", settingsArr)
        root.put("installedPlugins", serializePluginsJson(installedPlugins))
        return root.toString(2)
    }

    fun importSettingsAndPluginsJson(rawJson: String) {
        val obj = try {
            JSONObject(rawJson)
        } catch (_: Exception) {
            throw IllegalArgumentException("设置与插件备份不是有效 JSON")
        }
        if (obj.optString("format") != "LexiNote.SettingsPlugins") {
            throw IllegalArgumentException("设置与插件备份格式不受支持")
        }
        val settingsArr = obj.optJSONArray("settings") ?: JSONArray()
        for (i in 0 until settingsArr.length()) {
            val item = settingsArr.optJSONObject(i) ?: continue
            val k = item.optString("key", "")
            val v = item.optString("value", "")
            if (k.isNotEmpty()) settingsMap[k] = v
        }
        val pluginsArr = obj.optJSONArray("installedPlugins")
        if (pluginsArr != null) {
            installedPlugins.clear()
            installedPlugins.addAll(parsePluginsJson(pluginsArr))
        }
        val lang = settingsMap["language"] ?: LexiI18n.systemLanguage()
        LexiI18n.currentLanguage = if (lang == "en") "en" else "zh-Hans"
        persistToDisk()
        notifyChanged()
    }

    fun exportMarkdownCollection(vaultId: String = "", projectId: String = ""): String {
        val active = getNotes(vaultId, projectId).filter { it.trashedAt == 0L }
        if (active.isEmpty()) return "# 知萤 LexiNote 知识库导出\n\n（当前工作区暂无笔记）\n"
        return active.joinToString("\n\n---\n\n") { note ->
            "# ${MarkdownEngine.displayTitle(note)}\n\n${LexiFrontmatter.parse(note.content).body.ifEmpty { note.content }}"
        }
    }

    fun exportSingleNoteMarkdown(note: NoteItem): String {
        return LexiFrontmatter.serializeFull(note)
    }

    fun exportWorkspaceZipBytes(vaultId: String = ""): ByteArray {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zos ->
            val activeNotes = getNotes(targetVaultId).filter { it.trashedAt == 0L }
            val usedNames = mutableSetOf<String>()
            for (note in activeNotes) {
                var baseName = MarkdownEngine.displayTitle(note).replace(Regex("""[/\\:*?"<>|\r\n]+"""), "_").take(60)
                if (baseName.isEmpty()) baseName = note.id
                var fileName = "$baseName.md"
                var suffix = 2
                while (usedNames.contains(fileName)) {
                    fileName = "$baseName-$suffix.md"
                    suffix++
                }
                usedNames.add(fileName)
                zos.putNextEntry(ZipEntry("notes/$fileName"))
                zos.write(LexiFrontmatter.serializeFull(note).toByteArray(Charsets.UTF_8))
                zos.closeEntry()
            }
            zos.putNextEntry(ZipEntry("backup.json"))
            zos.write(exportBackupJson().toByteArray(Charsets.UTF_8))
            zos.closeEntry()
        }
        return baos.toByteArray()
    }

    fun importMarkdownText(
        fileName: String,
        rawContent: String,
        vaultId: String = "",
        projectId: String = ""
    ): NoteItem {
        val targetVaultId = vaultId.ifEmpty { getActiveVaultId() }
        val targetProjectId = projectId.ifEmpty { getActiveProjectId(targetVaultId) }
        val fallbackTitle = fileName.replace(Regex("""\.(md|markdown|txt)$""", RegexOption.IGNORE_CASE), "").trim()
        val note = NoteItem(
            vaultId = targetVaultId,
            projectId = targetProjectId,
            title = fallbackTitle.ifEmpty { "导入笔记" },
            notebook = "导入收件箱",
            content = rawContent,
            noteType = "markdown",
            editorLevel = "pro"
        )
        LexiFrontmatter.apply(note, rawContent)
        if (note.title.trim().isEmpty()) {
            note.title = fallbackTitle.ifEmpty { MarkdownEngine.displayTitle(note) }
        }
        return saveNote(note, recordHistory = true, historyReason = "manual")
    }

    fun rebuildIndex(): Int {
        val now = System.currentTimeMillis()
        for (note in notesList) {
            if (note.trashedAt > 0L) continue
            val fm = LexiFrontmatter.parse(note.content)
            val inlineTags = MarkdownEngine.extractInlineTags(fm.body)
            val merged = mutableListOf<String>()
            for (t in note.tags + fm.tags + inlineTags) {
                val clean = t.removePrefix("#").trim()
                if (clean.isNotEmpty() && !merged.contains(clean)) merged.add(clean)
            }
            note.tags = merged
            if (note.title.trim().isEmpty()) {
                note.title = MarkdownEngine.displayTitle(note)
            }
        }
        persistToDisk()
        notifyChanged()
        return notesList.count { it.trashedAt == 0L }
    }

    // --- Disk Serialization ---

    private fun writeNoteMarkdownFile(note: NoteItem) {
        val dir = rootDir ?: return
        try {
            val file = if (note.path.isNotEmpty()) {
                File(note.path)
            } else {
                File(dir, "vaults/${note.vaultId}/notes/${note.id}.md")
            }
            file.parentFile?.mkdirs()
            file.writeText(LexiFrontmatter.serializeFull(note), Charsets.UTF_8)
        } catch (_: Exception) {
        }
    }

    private fun persistToDisk() {
        val dir = rootDir ?: return
        try {
            dir.mkdirs()
            val stateObj = JSONObject()
            val settingsObj = JSONObject()
            for ((k, v) in settingsMap) settingsObj.put(k, v)
            stateObj.put("settings", settingsObj)
            stateObj.put("vaults", serializeVaultsJson(vaultsList))
            stateObj.put("projects", serializeProjectsJson(projectsList))
            stateObj.put("notes", serializeNotesJson(notesList))
            stateObj.put("mindMaps", serializeMindMapsJson(mindMapsList))
            stateObj.put("canvases", serializeCanvasesJson(canvasesList))
            stateObj.put("templateLibrary", LexiTemplateLibrary.encode(templateLibraryState))
            stateObj.put("plugins", serializePluginsJson(installedPlugins))
            val historyObj = JSONObject()
            for ((noteId, revs) in historyMap) {
                val arr = JSONArray()
                for (r in revs) {
                    val rObj = JSONObject()
                    rObj.put("id", r.id)
                    rObj.put("savedAt", r.savedAt)
                    rObj.put("reason", r.reason)
                    rObj.put("contentHash", r.contentHash)
                    rObj.put("byteSize", r.byteSize)
                    rObj.put("snapshot", serializeNoteObj(r.snapshot))
                    arr.put(rObj)
                }
                historyObj.put(noteId, arr)
            }
            stateObj.put("history", historyObj)
            val tmpFile = File(dir, "lexinote_state.json.tmp")
            val targetFile = File(dir, "lexinote_state.json")
            tmpFile.writeText(stateObj.toString(), Charsets.UTF_8)
            tmpFile.renameTo(targetFile)
        } catch (_: Exception) {
        }
    }

    private fun loadFromDisk() {
        val dir = rootDir ?: return
        val file = File(dir, "lexinote_state.json")
        if (!file.exists()) return
        try {
            val raw = file.readText(Charsets.UTF_8)
            val stateObj = JSONObject(raw)
            settingsMap.clear()
            val settingsObj = stateObj.optJSONObject("settings")
            if (settingsObj != null) {
                for (k in settingsObj.keys()) {
                    settingsMap[k] = settingsObj.optString(k, "")
                }
            }
            vaultsList.clear()
            vaultsList.addAll(parseVaultsJson(stateObj.optJSONArray("vaults") ?: JSONArray()))
            projectsList.clear()
            projectsList.addAll(parseProjectsJson(stateObj.optJSONArray("projects") ?: JSONArray()))
            notesList.clear()
            notesList.addAll(parseNotesJson(stateObj.optJSONArray("notes") ?: JSONArray()))
            mindMapsList.clear()
            mindMapsList.addAll(parseMindMapsJson(stateObj.optJSONArray("mindMaps") ?: JSONArray()))
            canvasesList.clear()
            canvasesList.addAll(parseCanvasesJson(stateObj.optJSONArray("canvases") ?: JSONArray()))
            val tplRaw = stateObj.optString("templateLibrary", "")
            if (tplRaw.isNotEmpty()) {
                try {
                    templateLibraryState = LexiTemplateLibrary.decode(tplRaw)
                } catch (_: Exception) {
                    templateLibraryState = LexiTemplateLibrary.fresh()
                }
            }
            installedPlugins.clear()
            installedPlugins.addAll(parsePluginsJson(stateObj.optJSONArray("plugins") ?: JSONArray()))
            historyMap.clear()
            val historyObj = stateObj.optJSONObject("history")
            if (historyObj != null) {
                for (noteId in historyObj.keys()) {
                    val arr = historyObj.optJSONArray(noteId) ?: continue
                    val list = mutableListOf<NoteRevision>()
                    for (i in 0 until arr.length()) {
                        val rObj = arr.optJSONObject(i) ?: continue
                        val snapObj = rObj.optJSONObject("snapshot") ?: continue
                        list.add(
                            NoteRevision(
                                id = rObj.optString("id", ""),
                                savedAt = rObj.optLong("savedAt", 0L),
                                reason = rObj.optString("reason", "autosave"),
                                contentHash = rObj.optString("contentHash", ""),
                                byteSize = rObj.optInt("byteSize", 0),
                                snapshot = parseNoteObj(snapObj)
                            )
                        )
                    }
                    if (list.isNotEmpty()) historyMap[noteId] = list
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun serializeVaultsJson(vaults: List<VaultItem>): JSONArray {
        val arr = JSONArray()
        for (v in vaults) {
            arr.put(
                JSONObject().apply {
                    put("id", v.id)
                    put("name", v.name)
                    put("description", v.description)
                    put("archived", v.archived)
                    put("favorite", v.favorite)
                    put("createdAt", v.createdAt)
                    put("version", v.version)
                    put("folderUri", v.folderUri)
                    put("permissionUri", v.permissionUri)
                }
            )
        }
        return arr
    }

    private fun parseVaultsJson(arr: JSONArray): List<VaultItem> {
        val list = mutableListOf<VaultItem>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(
                VaultItem(
                    id = o.optString("id", "default-vault"),
                    name = o.optString("name", "我的工作区"),
                    description = o.optString("description", ""),
                    archived = o.optBoolean("archived", false),
                    favorite = o.optBoolean("favorite", false),
                    createdAt = o.optLong("createdAt", 0L),
                    version = o.optInt("version", 1),
                    folderUri = o.optString("folderUri", ""),
                    permissionUri = o.optString("permissionUri", "")
                )
            )
        }
        return list
    }

    private fun serializeProjectsJson(projects: List<LexiProject>): JSONArray {
        val arr = JSONArray()
        for (p in projects) {
            arr.put(
                JSONObject().apply {
                    put("id", p.id)
                    put("vaultId", p.vaultId)
                    put("name", p.name)
                    put("archived", p.archived)
                    put("favorite", p.favorite)
                    put("folderUri", p.folderUri)
                    put("permissionUri", p.permissionUri)
                    put("createdAt", p.createdAt)
                }
            )
        }
        return arr
    }

    private fun parseProjectsJson(arr: JSONArray): List<LexiProject> {
        val list = mutableListOf<LexiProject>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(
                LexiProject(
                    id = o.optString("id", ""),
                    vaultId = o.optString("vaultId", "default-vault"),
                    name = o.optString("name", ""),
                    archived = o.optBoolean("archived", false),
                    favorite = o.optBoolean("favorite", false),
                    folderUri = o.optString("folderUri", ""),
                    permissionUri = o.optString("permissionUri", ""),
                    createdAt = o.optLong("createdAt", 0L)
                )
            )
        }
        return list
    }

    private fun serializeNoteObj(n: NoteItem): JSONObject {
        return JSONObject().apply {
            put("id", n.id)
            put("vaultId", n.vaultId)
            put("projectId", n.projectId)
            put("sourceMissing", n.sourceMissing)
            put("title", n.title)
            put("notebook", n.notebook)
            put("content", n.content)
            put("path", n.path)
            put("noteType", n.noteType)
            put("editorLevel", n.editorLevel)
            put("tags", JSONArray(n.tags))
            val propsArr = JSONArray()
            for (p in n.properties) {
                propsArr.put(JSONObject().apply {
                    put("key", p.key)
                    put("propValue", p.propValue)
                })
            }
            put("properties", propsArr)
            put("pinned", n.pinned)
            put("favorite", n.favorite)
            put("trashedAt", n.trashedAt)
            put("createdAt", n.createdAt)
            put("updatedAt", n.updatedAt)
            put("lastOpenedAt", n.lastOpenedAt)
        }
    }

    private fun serializeNotesJson(notes: List<NoteItem>): JSONArray {
        val arr = JSONArray()
        for (n in notes) arr.put(serializeNoteObj(n))
        return arr
    }

    private fun parseNoteObj(o: JSONObject): NoteItem {
        val tagsArr = o.optJSONArray("tags") ?: JSONArray()
        val tags = mutableListOf<String>()
        for (i in 0 until tagsArr.length()) {
            val t = tagsArr.optString(i, "")
            if (t.isNotEmpty()) tags.add(t)
        }
        val propsArr = o.optJSONArray("properties") ?: JSONArray()
        val props = mutableListOf<NoteProperty>()
        for (i in 0 until propsArr.length()) {
            val pObj = propsArr.optJSONObject(i) ?: continue
            props.add(NoteProperty(pObj.optString("key", ""), pObj.optString("propValue", "")))
        }
        return NoteItem(
            id = o.optString("id", ""),
            vaultId = o.optString("vaultId", "default-vault"),
            projectId = o.optString("projectId", ""),
            sourceMissing = o.optBoolean("sourceMissing", false),
            title = o.optString("title", ""),
            notebook = o.optString("notebook", "速记收件箱"),
            content = o.optString("content", ""),
            path = o.optString("path", ""),
            noteType = o.optString("noteType", "quick"),
            editorLevel = o.optString("editorLevel", "simple"),
            tags = tags,
            properties = props,
            pinned = o.optBoolean("pinned", false),
            favorite = o.optBoolean("favorite", false),
            trashedAt = o.optLong("trashedAt", 0L),
            createdAt = o.optLong("createdAt", 0L),
            updatedAt = o.optLong("updatedAt", 0L),
            lastOpenedAt = o.optLong("lastOpenedAt", 0L)
        )
    }

    private fun parseNotesJson(arr: JSONArray): List<NoteItem> {
        val list = mutableListOf<NoteItem>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(parseNoteObj(o))
        }
        return list
    }

    private fun serializeMindMapsJson(maps: List<MindMapDoc>): JSONArray {
        val arr = JSONArray()
        for (m in maps) {
            val nodesArr = JSONArray()
            for (n in m.nodes) {
                nodesArr.put(
                    JSONObject().apply {
                        put("id", n.id)
                        put("parentId", n.parentId)
                        put("text", n.text)
                        put("note", n.note)
                        put("noteRefId", n.noteRefId)
                        put("noteRefTitle", n.noteRefTitle)
                        put("order", n.order)
                        put("collapsed", n.collapsed)
                        put("colorTag", n.colorTag)
                        put("offsetX", n.offsetX)
                        put("offsetY", n.offsetY)
                    }
                )
            }
            arr.put(
                JSONObject().apply {
                    put("id", m.id)
                    put("vaultId", m.vaultId)
                    put("projectId", m.projectId)
                    put("title", m.title)
                    put("layoutKind", m.layoutKind)
                    put("rootNodeId", m.rootNodeId)
                    put("nodes", nodesArr)
                    put("favorite", m.favorite)
                    put("trashedAt", m.trashedAt)
                    put("createdAt", m.createdAt)
                    put("updatedAt", m.updatedAt)
                }
            )
        }
        return arr
    }

    private fun parseMindMapsJson(arr: JSONArray): List<MindMapDoc> {
        val list = mutableListOf<MindMapDoc>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val nodesArr = o.optJSONArray("nodes") ?: JSONArray()
            val nodes = mutableListOf<MindMapNode>()
            for (j in 0 until nodesArr.length()) {
                val nObj = nodesArr.optJSONObject(j) ?: continue
                nodes.add(
                    MindMapNode(
                        id = nObj.optString("id", ""),
                        parentId = nObj.optString("parentId", ""),
                        text = nObj.optString("text", ""),
                        note = nObj.optString("note", ""),
                        noteRefId = nObj.optString("noteRefId", ""),
                        noteRefTitle = nObj.optString("noteRefTitle", ""),
                        order = nObj.optInt("order", 0),
                        collapsed = nObj.optBoolean("collapsed", false),
                        colorTag = nObj.optString("colorTag", "purple"),
                        offsetX = nObj.optDouble("offsetX", 0.0),
                        offsetY = nObj.optDouble("offsetY", 0.0)
                    )
                )
            }
            list.add(
                MindMapDoc(
                    id = o.optString("id", ""),
                    vaultId = o.optString("vaultId", "default-vault"),
                    projectId = o.optString("projectId", ""),
                    title = o.optString("title", ""),
                    layoutKind = o.optString("layoutKind", "right"),
                    rootNodeId = o.optString("rootNodeId", "root"),
                    nodes = nodes,
                    favorite = o.optBoolean("favorite", false),
                    trashedAt = o.optLong("trashedAt", 0L),
                    createdAt = o.optLong("createdAt", 0L),
                    updatedAt = o.optLong("updatedAt", 0L)
                )
            )
        }
        return list
    }

    private fun serializeCanvasesJson(boards: List<CanvasBoard>): JSONArray {
        val arr = JSONArray()
        for (b in boards) {
            val cardsArr = JSONArray()
            for (c in b.cards) {
                cardsArr.put(
                    JSONObject().apply {
                        put("id", c.id)
                        put("title", c.title)
                        put("content", c.content)
                        put("noteRefId", c.noteRefId)
                        put("noteRefTitle", c.noteRefTitle)
                        put("x", c.x)
                        put("y", c.y)
                        put("colorTag", c.colorTag)
                    }
                )
            }
            val edgesArr = JSONArray()
            for (e in b.edges) {
                edgesArr.put(
                    JSONObject().apply {
                        put("id", e.id)
                        put("fromId", e.fromId)
                        put("toId", e.toId)
                        put("label", e.label)
                    }
                )
            }
            arr.put(
                JSONObject().apply {
                    put("id", b.id)
                    put("vaultId", b.vaultId)
                    put("projectId", b.projectId)
                    put("title", b.title)
                    put("cards", cardsArr)
                    put("edges", edgesArr)
                    put("createdAt", b.createdAt)
                    put("updatedAt", b.updatedAt)
                }
            )
        }
        return arr
    }

    private fun parseCanvasesJson(arr: JSONArray): List<CanvasBoard> {
        val list = mutableListOf<CanvasBoard>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val cardsArr = o.optJSONArray("cards") ?: JSONArray()
            val cards = mutableListOf<CanvasCard>()
            for (j in 0 until cardsArr.length()) {
                val cObj = cardsArr.optJSONObject(j) ?: continue
                cards.add(
                    CanvasCard(
                        id = cObj.optString("id", ""),
                        title = cObj.optString("title", ""),
                        content = cObj.optString("content", ""),
                        noteRefId = cObj.optString("noteRefId", ""),
                        noteRefTitle = cObj.optString("noteRefTitle", ""),
                        x = cObj.optDouble("x", 60.0).toFloat(),
                        y = cObj.optDouble("y", 60.0).toFloat(),
                        colorTag = cObj.optString("colorTag", "purple")
                    )
                )
            }
            val edgesArr = o.optJSONArray("edges") ?: JSONArray()
            val edges = mutableListOf<CanvasEdge>()
            for (j in 0 until edgesArr.length()) {
                val eObj = edgesArr.optJSONObject(j) ?: continue
                edges.add(
                    CanvasEdge(
                        id = eObj.optString("id", ""),
                        fromId = eObj.optString("fromId", ""),
                        toId = eObj.optString("toId", ""),
                        label = eObj.optString("label", "")
                    )
                )
            }
            list.add(
                CanvasBoard(
                    id = o.optString("id", ""),
                    vaultId = o.optString("vaultId", "default-vault"),
                    projectId = o.optString("projectId", ""),
                    title = o.optString("title", ""),
                    cards = cards,
                    edges = edges,
                    createdAt = o.optLong("createdAt", 0L),
                    updatedAt = o.optLong("updatedAt", 0L)
                )
            )
        }
        return list
    }

    private fun serializePluginsJson(plugins: List<LexiPluginRecord>): JSONArray {
        val arr = JSONArray()
        for (p in plugins) {
            arr.put(
                JSONObject().apply {
                    put("id", p.id)
                    put("name", p.name)
                    put("version", p.version)
                    put("description", p.description)
                    put("permissions", JSONArray(p.permissions))
                    put("commands", JSONArray(p.commands))
                    put("granted", p.granted)
                }
            )
        }
        return arr
    }

    private fun parsePluginsJson(arr: JSONArray): List<LexiPluginRecord> {
        val list = mutableListOf<LexiPluginRecord>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val permsArr = o.optJSONArray("permissions") ?: JSONArray()
            val perms = mutableListOf<String>()
            for (j in 0 until permsArr.length()) perms.add(permsArr.optString(j, ""))
            val cmdsArr = o.optJSONArray("commands") ?: JSONArray()
            val cmds = mutableListOf<String>()
            for (j in 0 until cmdsArr.length()) cmds.add(cmdsArr.optString(j, ""))
            list.add(
                LexiPluginRecord(
                    id = o.optString("id", ""),
                    name = o.optString("name", ""),
                    version = o.optString("version", "1.0.0"),
                    description = o.optString("description", ""),
                    permissions = perms,
                    commands = cmds,
                    granted = o.optBoolean("granted", true)
                )
            )
        }
        return list
    }
}
