package com.lovexjy.lexinote.core

data class VaultItem(
    var archived: Boolean = false,
    var favorite: Boolean = false,
    var id: String = "default-vault",
    var name: String = "个人知识库",
    var description: String = "日常记录、课程学习与技术文档",
    var createdAt: Long = 0L,
    var version: Int = 1,
    var folderUri: String = "",
    var permissionUri: String = ""
)

data class LexiProject(
    var archived: Boolean = false,
    var favorite: Boolean = false,
    var id: String = "",
    var vaultId: String = "",
    var name: String = "",
    var color: String = "#6E44D9",
    var folderUri: String = "",
    var permissionUri: String = "",
    var createdAt: Long = 0L
)

data class NoteProperty(
    var key: String = "",
    var propValue: String = ""
) {
    var type: String = "text"
    var value: String
        get() = propValue
        set(v) { propValue = v }

    constructor(key: String, type: String, value: String) : this(key = key, propValue = value) {
        this.type = type
    }
}

data class NoteItem(
    var id: String = "",
    var vaultId: String = "default-vault",
    var projectId: String = "",
    var sourceMissing: Boolean = false,
    var title: String = "",
    var notebook: String = "速记收件箱",
    var content: String = "",
    var path: String = "",
    var noteType: String = "quick", // 'quick' | 'study' | 'markdown'
    var editorLevel: String = "simple", // 'simple' | 'study' | 'pro'
    var tags: MutableList<String> = mutableListOf(),
    var properties: MutableList<NoteProperty> = mutableListOf(),
    var pinned: Boolean = false,
    var favorite: Boolean = false,
    var trashedAt: Long = 0L,
    var createdAt: Long = 0L,
    var updatedAt: Long = 0L,
    var lastOpenedAt: Long = 0L
) {
    fun deepCopy(): NoteItem = copy(
        tags = tags.toMutableList(),
        properties = properties.map { it.copy() }.toMutableList()
    )
}

data class NoteLink(
    var sourceId: String = "",
    var sourceTitle: String = "",
    var targetId: String = "",
    var targetTitle: String = "",
    var anchor: String = "",
    var displayText: String = ""
)

data class UnlinkedMention(
    var sourceId: String = "",
    var sourceTitle: String = "",
    var targetId: String = "",
    var targetTitle: String = "",
    var snippet: String = ""
)

data class MindMapNode(
    var id: String = "",
    var parentId: String = "",
    var text: String = "",
    var note: String = "",
    var noteRefId: String = "",
    var noteRefTitle: String = "",
    var order: Int = 0,
    var collapsed: Boolean = false,
    var colorTag: String = "purple", // 'purple' | 'indigo' | 'teal' | 'amber' | 'rose'
    var level: Int = 0,
    var x: Float = 0f,
    var y: Float = 0f,
    var boxWidth: Double = 136.0,
    var boxHeight: Double = 44.0,
    var offsetX: Double = 0.0,
    var offsetY: Double = 0.0,
    var color: String = "#6E44D9",
    var noteId: String = ""
) {
    init {
        if (noteId.isNotEmpty() && noteRefId.isEmpty()) noteRefId = noteId
        if (noteRefId.isNotEmpty() && noteId.isEmpty()) noteId = noteRefId
    }
}

data class MindMapDoc(
    var id: String = "",
    var vaultId: String = "default-vault",
    var projectId: String = "",
    var title: String = "",
    var layoutKind: String = "right", // 'right' | 'balanced' | 'org'
    var rootNodeId: String = "root",
    var nodes: MutableList<MindMapNode> = mutableListOf(),
    var favorite: Boolean = false,
    var trashedAt: Long = 0L,
    var createdAt: Long = 0L,
    var updatedAt: Long = 0L
) {
    fun deepCopy(): MindMapDoc = copy(
        nodes = nodes.map { it.copy() }.toMutableList()
    )
}

data class CanvasCard(
    var id: String = "",
    var title: String = "",
    var content: String = "",
    var noteRefId: String = "",
    var noteRefTitle: String = "",
    var x: Float = 60f,
    var y: Float = 60f,
    var colorTag: String = "purple",
    var width: Float = 180f,
    var height: Float = 105f,
    var color: String = "#EAE1FF",
    var noteId: String = ""
) {
    init {
        if (noteId.isNotEmpty() && noteRefId.isEmpty()) noteRefId = noteId
        if (noteRefId.isNotEmpty() && noteId.isEmpty()) noteId = noteRefId
    }
}

data class CanvasEdge(
    var id: String = "",
    var fromId: String = "",
    var toId: String = "",
    var label: String = "",
    var fromCardId: String = "",
    var toCardId: String = ""
) {
    init {
        if (fromCardId.isNotEmpty() && fromId.isEmpty()) fromId = fromCardId
        if (fromId.isNotEmpty() && fromCardId.isEmpty()) fromCardId = fromId
        if (toCardId.isNotEmpty() && toId.isEmpty()) toId = toCardId
        if (toId.isNotEmpty() && toCardId.isEmpty()) toCardId = toId
    }
}

data class CanvasBoard(
    var id: String = "",
    var vaultId: String = "default-vault",
    var projectId: String = "",
    var title: String = "",
    var cards: MutableList<CanvasCard> = mutableListOf(),
    var edges: MutableList<CanvasEdge> = mutableListOf(),
    var trashedAt: Long = 0L,
    var createdAt: Long = 0L,
    var updatedAt: Long = 0L
) {
    fun deepCopy(): CanvasBoard = copy(
        cards = cards.map { it.copy() }.toMutableList(),
        edges = edges.map { it.copy() }.toMutableList()
    )
}

data class GraphNode(
    var id: String = "",
    var label: String = "",
    var kind: String = "note", // 'note' | 'mindmap' | 'tag'
    var noteType: String = "quick",
    var degree: Int = 0,
    var x: Float = 0f,
    var y: Float = 0f,
    var tags: MutableList<String> = mutableListOf(),
    var snippet: String = ""
) {
    val refId: String
        get() = id.removePrefix("map:").removePrefix("tag:")
}

data class GraphEdge(
    var sourceId: String = "",
    var targetId: String = "",
    var kind: String = "link" // 'link' | 'mapRef' | 'tag'
)

data class MarkdownBlock(
    var id: String = "",
    var kind: String = "paragraph", // 'h1' | 'h2' | 'h3' | 'todo' | 'bullet' | 'ordered' | 'quote' | 'callout' | 'code' | 'formula' | 'table' | 'image' | 'embed' | 'hr' | 'paragraph'
    var text: String = "",
    var checked: Boolean = false,
    var meta: String = "",
    var lineIndex: Int = 0
)

data class OutlineHeading(
    var id: String = "",
    var level: Int = 1,
    var title: String = "",
    var lineIndex: Int = 0
)

data class NoteEditorRouteParam(
    var restoreSelectionStart: Int = -1,
    var restoreSelectionEnd: Int = -1,
    var restoreSourceMode: Boolean = false,
    var launchAssistant: Boolean = false,
    var templateId: String = "",
    var vaultId: String = "",
    var projectId: String = "",
    var noteId: String = "",
    var createNew: Boolean = false,
    var deferCreationUntilInput: Boolean = false,
    var initialType: String = "quick",
    var initialTier: String = "simple",
    var initialTitle: String = "",
    var initialNotebook: String = "",
    var initialContent: String = "",
    var externalFileMode: Boolean = false,
    var externalFileUri: String = ""
)

data class MindMapRouteParam(
    var projectId: String = "",
    var mapId: String = "",
    var createNew: Boolean = false,
    var fromNoteId: String = ""
)

data class CanvasRouteParam(
    var projectId: String = "",
    var canvasId: String = "",
    var createNew: Boolean = false
)

data class LexiCollectionBackup(
    var vaultId: String = "",
    var bookmarks: String = "[]",
    var databases: String = "[]"
)

data class LexiBackupPackage(
    var format: String = "LexiNote.Backup",
    var version: Int = 1,
    var exportedAt: Long = 0L,
    var vaults: MutableList<VaultItem> = mutableListOf(),
    var projects: MutableList<LexiProject> = mutableListOf(),
    var notes: MutableList<NoteItem> = mutableListOf(),
    var mindMaps: MutableList<MindMapDoc> = mutableListOf(),
    var canvases: MutableList<CanvasBoard> = mutableListOf(),
    var templateLibrary: String = "",
    var collections: MutableList<LexiCollectionBackup> = mutableListOf()
)

data class TagCount(
    var name: String = "",
    var count: Int = 0
)

data class CreateEntry(
    var kind: String = "",
    var icon: String = "",
    var title: String = "",
    var caption: String = ""
)

val CREATE_ENTRIES: List<CreateEntry> = listOf(
    CreateEntry("quick", "note", "快速笔记", "灵感 · 待办 · 日记"),
    CreateEntry("study", "study", "学习笔记", "公式 · 代码 · 大纲"),
    CreateEntry("markdown", "markdown", "专业 Markdown", "源码 · 双链 · 属性"),
    CreateEntry("mindmap", "mindmap", "思维导图", "树形结构 · 大纲切换"),
    CreateEntry("canvas", "canvas", "自由白板", "卡片 · 连线 · 拼贴"),
    CreateEntry("explore", "graph", "笔记关联", "查看相关笔记与引用")
)

data class NoteRevision(
    var id: String = "",
    var savedAt: Long = 0L,
    var reason: String = "autosave",
    var contentHash: String = "",
    var byteSize: Int = 0,
    var snapshot: NoteItem = NoteItem()
)

data class LexiHighlightSpan(
    var id: String = "",
    var text: String = "",
    var hit: Boolean = false
)

data class LexiLinkTargetPreview(
    var exists: Boolean = false,
    var noteId: String = "",
    var title: String = "",
    var targetName: String = "",
    var anchor: String = "",
    var notebook: String = "",
    var tags: MutableList<String> = mutableListOf(),
    var snippet: String = "",
    var outgoingCount: Int = 0,
    var backlinkCount: Int = 0,
    var updatedAt: Long = 0L,
    var lastOpenedAt: Long = 0L
)

data class LexiLinkCandidate(
    var noteId: String = "",
    var title: String = "",
    var notebook: String = "",
    var reason: String = ""
)

data class CssSnippet(
    var id: String = "",
    var name: String = "",
    var css: String = "",
    var enabled: Boolean = true
)

data class LexiPluginRecord(
    var id: String = "",
    var name: String = "",
    var version: String = "1.0.0",
    var description: String = "",
    var permissions: MutableList<String> = mutableListOf(),
    var commands: MutableList<String> = mutableListOf(),
    var granted: Boolean = true
)

data class LexiShareDraft(
    var title: String = "",
    var url: String = "",
    var comment: String = "",
    var content: String = "",
    var fingerprint: String = "",
    var text: String = "",
    var sourceApp: String = "",
    var createdAt: Long = 0L
) {
    init {
        if (text.isNotEmpty() && content.isEmpty()) content = text
        if (content.isNotEmpty() && text.isEmpty()) text = content
    }
}
