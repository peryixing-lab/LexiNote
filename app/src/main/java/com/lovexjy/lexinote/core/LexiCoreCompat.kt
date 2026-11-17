package com.lovexjy.lexinote.core

import java.io.ByteArrayInputStream
import java.io.File
import java.net.URLEncoder
import java.util.zip.ZipInputStream
import kotlin.math.max
import kotlin.math.min

data class LexiStorageLocationStatus(
    var mode: String = "internal",
    var title: String = "应用私有空间",
    var path: String = "",
    var description: String = ""
)

data class LexiMathDisplayInfo(
    val envLabel: String = "",
    val tag: String = "",
    val lines: List<String> = emptyList()
)

data class LexiNoteRelationsBundle(
    val outgoingNotes: List<NoteItem> = emptyList(),
    val backlinkNotes: List<NoteItem> = emptyList(),
    val mindMaps: List<MindMapDoc> = emptyList()
)

data class LexiRelationCounts(
    val outgoing: Int = 0,
    val backlinks: Int = 0,
    val mindMaps: Int = 0
)

data class LexiCodeLine(
    val lineNumber: Int,
    val spans: List<LexiCodeToken>
)

data class LexiLiveLineInfo(
    val kind: String = "paragraph",
    val level: Int = 1,
    val checked: Boolean = false,
    val displayText: String = ""
)

// --- Theme extensions ---

val LexiThemePalette.bg_root: String get() = page_bg
val LexiThemePalette.bg_accent: String get() = page_bg_end
val LexiThemePalette.surface_card: String get() = surface
val LexiThemePalette.surface_soft: String get() = soft_surface
val LexiThemePalette.surface_elevated: String get() = elevated_surface
val LexiThemePalette.top_bar_bg: String get() = glass_fill
val LexiThemePalette.dock_bg: String get() = dock_surface
val LexiThemePalette.stroke: String get() = divider
val LexiThemePalette.stroke_soft: String get() = divider
val LexiThemePalette.stroke_strong: String get() = glass_stroke
val LexiThemePalette.text_muted: String get() = text_secondary
val LexiThemePalette.brand_strong: String get() = brand_ink
val LexiThemePalette.accent: String get() = brand
val LexiThemePalette.accent_soft: String get() = brand_soft
val LexiThemePalette.chip_bg: String get() = soft_surface
val LexiThemePalette.chip_active_bg: String get() = brand
val LexiThemePalette.chip_active_fg: String get() = inverse_text
val LexiThemePalette.code_bg: String get() = soft_surface
val LexiThemePalette.quote_bg: String get() = soft_surface
val LexiThemePalette.shadow_color: String get() = glass_stroke

val LexiThemePreset.subtitle: String get() = id
val LexiThemePreset.light: LexiThemePalette get() = LexiTheme.palette(id, lightBrand, false)

fun LexiTheme.resolvePalette(
    themeId: String,
    colorMode: String = "light",
    systemDark: Boolean = false
): LexiThemePalette {
    return resolvePalette(themeId, "", "", "", colorMode, systemDark)
}

fun LexiTheme.resolveAccent(palette: LexiThemePalette, customAccent: String): LexiThemePalette {
    val clean = customAccent.trim()
    if (clean.isEmpty()) return palette
    val resolvedBrand = resolveAccent(clean, palette)
    return palette.copy(
        brand = resolvedBrand,
        brand_ink = fitText(mix(resolvedBrand, if (palette.dark) "#FFFFFF" else "#141022", 0.32), palette.soft_surface, 4.2),
        brand_soft = mix(palette.surface, resolvedBrand, if (palette.dark) 0.22 else 0.15)
    )
}

// --- Model property aliases ---

var NoteItem.deletedAt: Long
    get() = trashedAt
    set(value) {
        trashedAt = value
    }

val NoteLink.targetNoteId: String
    get() = targetId

val UnlinkedMention.sourceNoteId: String
    get() = sourceId

val UnlinkedMention.lineText: String
    get() = snippet

var MindMapDoc.deletedAt: Long
    get() = trashedAt
    set(value) {
        trashedAt = value
    }

var CanvasBoard.deletedAt: Long
    get() = trashedAt
    set(value) {
        trashedAt = value
    }

val MarkdownBlock.type: String
    get() = when {
        kind.length == 2 && kind[0] == 'h' && kind[1].isDigit() -> "heading"
        kind == "todo" -> "task"
        kind == "formula" -> "math"
        else -> kind
    }

val MarkdownBlock.level: Int
    get() = meta.toIntOrNull() ?: if (kind.length == 2 && kind[0] == 'h' && kind[1].isDigit()) (kind[1] - '0') else 1

val OutlineHeading.text: String
    get() = title

val CreateEntry.key: String
    get() = kind

val CreateEntry.subtitle: String
    get() = caption

val NoteRevision.content: String
    get() = snapshot.content

val LexiHighlightSpan.matched: Boolean
    get() = hit

val LexiLinkTargetPreview.noteTitle: String
    get() = title.ifEmpty { targetName }

val LexiLinkTargetPreview.matchedHeading: String
    get() = anchor

val LexiLinkCandidate.noteTitle: String
    get() = title

var LexiPluginRecord.enabled: Boolean
    get() = LexiStorageService.getEnabledPlugins().contains(id)
    set(value) {
        LexiStorageService.setPluginEnabled(id, value)
    }

val LexiFrontmatterResult.hasBlock: Boolean
    get() = hasFrontmatter

val LexiMathToken.isMath: Boolean
    get() = true

val LexiCompletionCandidate.insertText: String
    get() = insertion.removePrefix("[[").removeSuffix("]]").trim()

val LexiLocalArrangement.summaryBullets: List<String>
    get() = summary.split("；", "\n").map { it.trim() }.filter { it.isNotEmpty() }.ifEmpty {
        if (summary.isNotBlank()) listOf(summary) else emptyList()
    }

val LexiLocalArrangement.actionItems: List<String>
    get() = actions.map { it.label }

val LexiLocalArrangement.candidateLinks: List<LexiLinkCandidate>
    get() = links.map {
        LexiLinkCandidate(
            noteId = it.id.removePrefix("link-"),
            title = it.label,
            notebook = "笔记",
            reason = it.detail
        )
    }

val LexiLocalArrangement.candidateTags: List<String>
    get() = tags.map { it.label.removePrefix("#") }

val LexiMarkdownTable.headers: List<String>
    get() = rows.firstOrNull() ?: emptyList()

val LexiHistoryUsageSummary.totalRevisions: Int
    get() = revisionCount

val LexiDeepLinkRequest.content: String
    get() = ""

// --- Core engine overloads ---

fun LexiCodeHighlight.languageLabel(language: String): String {
    return label(language)
}

fun LexiCodeHighlight.parseLines(source: String, language: String): List<LexiCodeLine> {
    val rawLines = if (source.isEmpty()) listOf("") else source.split("\n")
    return rawLines.mapIndexed { idx, line ->
        val tokens = tokenize(line, language).ifEmpty {
            listOf(LexiCodeToken(id = "line-$idx", text = line, kind = "text"))
        }
        LexiCodeLine(lineNumber = idx + 1, spans = tokens)
    }
}

fun LexiLiveMarkdown.classifyLine(rawLine: String): LexiLiveLineInfo {
    val trimmed = rawLine.trim()
    val headingMatch = Regex("""^(#{1,6})\s+(.+)$""").matchEntire(trimmed)
    if (headingMatch != null) {
        return LexiLiveLineInfo(
            kind = "heading",
            level = headingMatch.groupValues[1].length.coerceIn(1, 6),
            displayText = headingMatch.groupValues[2].trim()
        )
    }
    val checkedTask = Regex("""^[-*+]\s+\[[xX]\]\s*(.*)$""").matchEntire(trimmed)
    if (checkedTask != null) {
        return LexiLiveLineInfo(
            kind = "task",
            checked = true,
            displayText = checkedTask.groupValues[1]
        )
    }
    val uncheckedTask = Regex("""^[-*+]\s+\[ \]\s*(.*)$""").matchEntire(trimmed)
    if (uncheckedTask != null) {
        return LexiLiveLineInfo(
            kind = "task",
            checked = false,
            displayText = uncheckedTask.groupValues[1]
        )
    }
    if (trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ")) {
        return LexiLiveLineInfo(
            kind = "bullet",
            displayText = trimmed.substring(2).trim()
        )
    }
    if (trimmed.startsWith(">")) {
        return LexiLiveLineInfo(
            kind = "quote",
            displayText = trimmed.removePrefix(">").trim()
        )
    }
    if (Regex("""^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$""").matches(trimmed)) {
        return LexiLiveLineInfo(kind = "divider")
    }
    return LexiLiveLineInfo(kind = "paragraph", displayText = rawLine)
}

fun LexiLiveMarkdown.toggleTaskLine(bodyText: String, lineIndex: Int, checked: Boolean): String {
    val lines = bodyText.split("\n").toMutableList()
    if (lineIndex in lines.indices) {
        val mark = if (checked) "[x]" else "[ ]"
        lines[lineIndex] = lines[lineIndex].replaceFirst(Regex("""^(\s*[-*+]\s+)\[[ xX]\]"""), "$1$mark")
    }
    return lines.joinToString("\n")
}

fun LexiEcosystemLink.parse(rawUri: String): LexiDeepLinkRequest? {
    return parseLexiNoteUri(rawUri)
}

fun LexiEcosystemLink.buildOpenNoteUrl(noteId: String, title: String = ""): String {
    val encodedId = URLEncoder.encode(noteId, "UTF-8")
    val encodedTitle = URLEncoder.encode(title, "UTF-8")
    return "lexinote://open?noteId=$encodedId&title=$encodedTitle"
}

fun LexiFrontmatter.apply(
    body: String,
    properties: List<NoteProperty>,
    tags: List<String>,
    forceBlock: Boolean = false
): String {
    val parsed = parse(body)
    val cleanBody = parsed.body
    val cleanTags = tags.map { it.removePrefix("#").trim() }.filter { it.isNotEmpty() }.distinct().toMutableList()
    val cleanProps = properties.filter { it.key.trim().isNotEmpty() }.map { it.copy() }.toMutableList()
    if (!forceBlock && !parsed.hasFrontmatter && cleanTags.isEmpty() && cleanProps.isEmpty()) {
        return cleanBody
    }
    val tempNote = NoteItem(
        content = cleanBody,
        tags = cleanTags,
        properties = cleanProps
    )
    val yamlBlock = serialize(tempNote)
    if (yamlBlock.isEmpty() && forceBlock) {
        return "---\n---\n$cleanBody"
    }
    return if (yamlBlock.isEmpty()) cleanBody else "$yamlBlock\n$cleanBody"
}

fun LexiMathSyntax.displayBlock(raw: String): LexiMathDisplayInfo {
    var inner = raw.trim()
    if (inner.startsWith("$$") && inner.endsWith("$$") && inner.length >= 4) {
        inner = inner.substring(2, inner.length - 2).trim()
    } else if (inner.startsWith("\\[") && inner.endsWith("\\]") && inner.length >= 4) {
        inner = inner.substring(2, inner.length - 2).trim()
    }
    val envMatch = Regex("""\\begin\{([A-Za-z*]+)\}""").find(inner)
    val envLabel = envMatch?.groupValues?.get(1) ?: ""
    val tagMatch = Regex("""\\tag\{([^}]+)\}""").find(inner)
    val tag = tagMatch?.groupValues?.get(1)?.trim() ?: ""
    val cleaned = inner
        .replace(Regex("""\\begin\{[A-Za-z*]+\}"""), "")
        .replace(Regex("""\\end\{[A-Za-z*]+\}"""), "")
        .replace(Regex("""\\tag\{[^}]+\}"""), "")
        .trim()
    val lines = cleaned
        .split(Regex("""\\\\|\n"""))
        .map { it.replace("&", " = ").replace(Regex("""\s+"""), " ").trim() }
        .filter { it.isNotEmpty() }
        .ifEmpty { listOf(inner.ifEmpty { "f(x)" }) }
    return LexiMathDisplayInfo(envLabel = envLabel, tag = tag, lines = lines)
}

fun LexiSearch.rank(notes: List<NoteItem>, query: String): List<NoteItem> {
    if (query.trim().isEmpty()) return notes
    return notes
        .filter { matches(it, query) }
        .sortedWith { a, b ->
            val ra = rank(MarkdownEngine.displayTitle(a), query).let { if (it < 0) 9999 else it }
            val rb = rank(MarkdownEngine.displayTitle(b), query).let { if (it < 0) 9999 else it }
            if (ra != rb) ra.compareTo(rb) else b.updatedAt.compareTo(a.updatedAt)
        }
}

fun LexiSearch.highlightSegments(text: String, terms: List<String>): List<LexiHighlightSpan> {
    return highlightSegments(text, terms.joinToString(" "))
}

fun LexiSearch.sortNotes(
    notes: List<NoteItem>,
    sortMode: String,
    backlinkCounts: Map<String, Int>
): List<NoteItem> {
    val sorted = sortNotes(notes, sortMode)
    if (sortMode == "backlinks" || sortMode == "links") {
        return sorted.sortedWith { a, b ->
            if (a.pinned != b.pinned) {
                if (a.pinned) -1 else 1
            } else {
                val ca = backlinkCounts[a.id] ?: 0
                val cb = backlinkCounts[b.id] ?: 0
                if (cb != ca) cb.compareTo(ca) else b.updatedAt.compareTo(a.updatedAt)
            }
        }
    }
    return sorted
}

fun MarkdownEngine.tableData(raw: String): LexiMarkdownTable {
    val lines = raw.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
    if (lines.isEmpty()) return LexiMarkdownTable()
    if (raw.trim().startsWith("{")) {
        return tableData(MarkdownBlock(kind = "table", meta = raw))
    }
    val table = LexiMarkdownTable()
    val headers = splitTableRow(lines[0])
    table.rows.add(headers)
    if (lines.size >= 2) {
        val sep = splitTableRow(lines[1])
        table.alignments = sep.map { cell ->
            when {
                cell.startsWith(":") && cell.endsWith(":") -> "center"
                cell.endsWith(":") -> "right"
                else -> "left"
            }
        }.toMutableList()
        for (i in 2 until lines.size) {
            val row = splitTableRow(lines[i])
            while (row.size < headers.size) row.add("")
            table.rows.add(row.take(headers.size).toMutableList())
        }
    }
    return table
}

fun MarkdownEngine.extractSnippet(markdown: String, query: String = "", maxLen: Int = 140): String {
    val parsed = LexiFrontmatter.parse(markdown)
    val plain = parsed.body
        .replace(Regex("""```[\s\S]*?```"""), " ")
        .replace(Regex("""^[#>*\-\s]+""", RegexOption.MULTILINE), "")
        .replace(Regex("""\[\[([^\[\]|]+)(?:\|([^\[\]]+))?\]\]""")) { m ->
            m.groupValues[2].ifEmpty { m.groupValues[1] }
        }
        .replace(Regex("""\s+"""), " ")
        .trim()
    if (plain.isEmpty()) return ""
    val terms = LexiSearch.highlightTerms(query)
    if (terms.isNotEmpty()) {
        val lower = plain.lowercase()
        val hit = terms.map { lower.indexOf(it) }.filter { it >= 0 }.minOrNull() ?: -1
        if (hit >= 0) {
            val start = max(0, hit - 18)
            val end = min(plain.length, start + maxLen)
            val prefix = if (start > 0) "…" else ""
            val suffix = if (end < plain.length) "…" else ""
            return "$prefix${plain.substring(start, end)}$suffix"
        }
    }
    return if (plain.length > maxLen) plain.take(maxLen) + "…" else plain
}

fun MarkdownEngine.findUnlinkedMentions(targetNote: NoteItem, allNotes: List<NoteItem>): List<UnlinkedMention> {
    val links = buildNoteLinks(allNotes)
    return findUnlinkedMentions(allNotes, links).filter {
        it.targetId == targetNote.id || it.targetTitle.equals(displayTitle(targetNote), ignoreCase = true)
    }
}

fun MarkdownEngine.linkTargetPreview(note: NoteItem): LexiLinkTargetPreview {
    val allNotes = LexiStorageService.listNotes().ifEmpty { listOf(note) }
    val allLinks = LexiStorageService.listLinks()
    return linkTargetPreview(displayTitle(note), allNotes, allLinks, note.vaultId)
}

fun MarkdownEngine.computeMindMapLayout(
    nodes: List<MindMapNode>,
    direction: String = "right"
): List<MindMapNode> {
    val cloned = nodes.map { it.copy() }.toMutableList()
    val root = cloned.find { it.parentId.isEmpty() } ?: cloned.firstOrNull()
    val layoutKind = if (direction == "both") "balanced" else direction
    val doc = MindMapDoc(
        layoutKind = layoutKind,
        rootNodeId = root?.id ?: "root",
        nodes = cloned
    )
    computeMindMapLayout(doc)
    return doc.nodes
}

fun MarkdownEngine.mindMapToMarkdownOutline(title: String, nodes: List<MindMapNode>): String {
    val root = nodes.find { it.parentId.isEmpty() } ?: nodes.firstOrNull()
    val doc = MindMapDoc(
        title = title,
        rootNodeId = root?.id ?: "root",
        nodes = nodes.map { it.copy() }.toMutableList()
    )
    return mindMapToMarkdownOutline(doc)
}

fun LexiRelations.contents(
    note: NoteItem,
    allNotes: List<NoteItem>,
    allLinks: List<NoteLink>,
    allMindMaps: List<MindMapDoc>
): LexiNoteRelationsBundle {
    val noteTitle = MarkdownEngine.displayTitle(note)
    val outgoingIds = allLinks.filter { it.sourceId == note.id }.map { it.targetId }.toSet()
    val outgoingTitles = allLinks.filter { it.sourceId == note.id }.map { it.targetTitle.lowercase() }.toSet()
    val backlinkIds = allLinks.filter {
        it.targetId == note.id || it.targetTitle.equals(noteTitle, ignoreCase = true)
    }.map { it.sourceId }.toSet()

    val outgoingNotes = allNotes.filter {
        it.id != note.id && (outgoingIds.contains(it.id) || outgoingTitles.contains(MarkdownEngine.displayTitle(it).lowercase()))
    }
    val backlinkNotes = allNotes.filter {
        it.id != note.id && backlinkIds.contains(it.id)
    }
    val relatedMaps = allMindMaps.filter { map ->
        map.trashedAt == 0L && map.nodes.any { n ->
            n.noteRefId == note.id || n.noteId == note.id || n.noteRefTitle.equals(noteTitle, ignoreCase = true)
        }
    }
    return LexiNoteRelationsBundle(
        outgoingNotes = outgoingNotes,
        backlinkNotes = backlinkNotes,
        mindMaps = relatedMaps
    )
}

fun LexiRelations.counts(
    note: NoteItem,
    links: List<NoteLink>,
    mindMaps: List<MindMapDoc>
): LexiRelationCounts {
    val noteTitle = MarkdownEngine.displayTitle(note)
    val outgoing = links.count { it.sourceId == note.id }
    val backlinks = links.count {
        it.sourceId != note.id && (it.targetId == note.id || it.targetTitle.equals(noteTitle, ignoreCase = true))
    }
    val mapCount = mindMaps.count { map ->
        map.trashedAt == 0L && map.nodes.any { n ->
            n.noteRefId == note.id || n.noteId == note.id
        }
    }
    return LexiRelationCounts(
        outgoing = outgoing,
        backlinks = backlinks,
        mindMaps = mapCount
    )
}

fun GraphLayout.build(
    notes: List<NoteItem>,
    links: List<NoteLink>,
    mindMaps: List<MindMapDoc>,
    tags: List<TagCount>
): GraphData {
    return build(
        notes = notes,
        maps = mindMaps,
        links = links,
        includeMaps = mindMaps.isNotEmpty(),
        includeTags = tags.isNotEmpty()
    )
}

fun GraphLayout.local(
    focusNoteId: String,
    notes: List<NoteItem>,
    links: List<NoteLink>,
    mindMaps: List<MindMapDoc>,
    tags: List<TagCount>
): GraphData {
    val full = build(notes, links, mindMaps, tags)
    return local(full, focusNoteId)
}

fun LexiGraphForce.layout(
    nodes: List<GraphNode>,
    edges: List<GraphEdge>,
    width: Float,
    height: Float
): List<GraphNode> {
    val copyNodes = nodes.map { it.copy(tags = it.tags.toMutableList()) }
    layout(copyNodes, edges)
    if (width > 0f && height > 0f) {
        val scaleX = width / 720f
        val scaleY = height / 420f
        for (n in copyNodes) {
            n.x *= scaleX
            n.y *= scaleY
        }
    }
    return copyNodes
}

fun LexiCompletion.candidates(
    context: LexiCompletionContext,
    notes: List<NoteItem>,
    tags: List<TagCount>,
    currentNoteId: String = "",
    maxCount: Int = 8
): List<LexiCompletionCandidate> {
    return candidates(context, notes, currentNoteId).take(maxCount)
}

fun LexiLocalAssistant.arrange(
    title: String,
    content: String,
    allNotes: List<NoteItem>
): LexiLocalArrangement {
    val combined = if (content.trim().startsWith("#")) content else "# $title\n$content"
    return arrange(combined, allNotes)
}

fun LexiNoteHistory.diffVersions(oldText: String, newText: String): LexiDiffResult {
    return diffVersions("", oldText, "", newText)
}

// --- LexiStorageService extensions ---

fun LexiStorageService.listVaults(includeArchived: Boolean = true): List<VaultItem> {
    return getVaults(includeArchived)
}

fun LexiStorageService.listProjects(vaultId: String = ""): List<LexiProject> {
    return getProjects(vaultId.ifEmpty { getActiveVaultId() }, includeArchived = true)
}

fun LexiStorageService.listNotes(vaultId: String = "", projectId: String = ""): List<NoteItem> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getNotes(targetVault, projectId).filter { it.trashedAt == 0L }
}

fun LexiStorageService.listDeletedNotes(vaultId: String = ""): List<NoteItem> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getNotes(targetVault, "").filter { it.trashedAt > 0L }
}

fun LexiStorageService.listMindMaps(vaultId: String = "", projectId: String = ""): List<MindMapDoc> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getMindMaps(targetVault, projectId).filter { it.trashedAt == 0L }
}

fun LexiStorageService.listDeletedMindMaps(vaultId: String = ""): List<MindMapDoc> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getMindMaps(targetVault, "").filter { it.trashedAt > 0L }
}

fun LexiStorageService.listCanvases(vaultId: String = "", projectId: String = ""): List<CanvasBoard> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getCanvases(targetVault, projectId).filter { it.trashedAt == 0L }
}

fun LexiStorageService.listDeletedCanvases(vaultId: String = ""): List<CanvasBoard> {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    return getCanvases(targetVault, "").filter { it.trashedAt > 0L }
}

fun LexiStorageService.listLinks(vaultId: String = ""): List<NoteLink> {
    return MarkdownEngine.buildNoteLinks(listNotes(vaultId))
}

fun LexiStorageService.listTags(vaultId: String = ""): List<TagCount> {
    val counts = mutableMapOf<String, Int>()
    for (note in listNotes(vaultId)) {
        for (tag in note.tags) {
            val clean = tag.removePrefix("#").trim()
            if (clean.isNotEmpty()) {
                counts[clean] = (counts[clean] ?: 0) + 1
            }
        }
    }
    return counts.entries
        .sortedWith { a, b ->
            if (b.value != a.value) b.value.compareTo(a.value) else a.key.compareTo(b.key)
        }
        .map { TagCount(it.key, it.value) }
}

fun LexiStorageService.listTemplates(): List<LexiTemplateItem> {
    return getTemplates()
}

fun LexiStorageService.listPlugins(): List<LexiPluginRecord> {
    return getInstalledPlugins()
}

fun LexiStorageService.listNoteRevisions(noteId: String): List<NoteRevision> {
    return getNoteRevisions(noteId)
}

fun LexiStorageService.getNote(noteId: String): NoteItem? {
    return getNoteById(noteId)
}

fun LexiStorageService.getMindMap(mapId: String): MindMapDoc? {
    return getMindMapById(mapId)
}

fun LexiStorageService.getCanvas(canvasId: String): CanvasBoard? {
    return getCanvasById(canvasId)
}

fun LexiStorageService.createNote(
    title: String = "",
    content: String = "",
    notebook: String = "速记收件箱",
    noteType: String = "quick",
    editorLevel: String = "simple",
    tags: List<String> = emptyList(),
    vaultId: String = "",
    projectId: String = ""
): NoteItem {
    val targetVault = vaultId.ifEmpty { getActiveVaultId() }
    val targetProject = projectId.ifEmpty { getActiveProjectId(targetVault) }
    val cleanTitle = title.trim().ifEmpty { "未命名笔记" }
    val body = content.ifEmpty { "# $cleanTitle\n\n" }
    val note = NoteItem(
        vaultId = targetVault,
        projectId = targetProject,
        title = cleanTitle,
        notebook = notebook,
        content = body,
        noteType = noteType,
        editorLevel = editorLevel,
        tags = tags.toMutableList()
    )
    return saveNote(note, recordHistory = true, historyReason = "manual")
}

fun LexiStorageService.createMindMap(
    title: String = "思维导图",
    vaultId: String = "",
    projectId: String = "",
    fromNoteId: String = ""
): MindMapDoc {
    if (fromNoteId.isNotEmpty()) {
        val src = getNoteById(fromNoteId)
        if (src != null) return createMindMapFromNote(src)
    }
    return createStarterMindMap(
        title = title.ifEmpty { "思维导图" },
        vaultId = vaultId,
        projectId = projectId
    )
}

fun LexiStorageService.createCanvas(
    title: String = "自由白板",
    vaultId: String = "",
    projectId: String = ""
): CanvasBoard {
    return createStarterCanvas(
        title = title.ifEmpty { "自由白板" },
        vaultId = vaultId,
        projectId = projectId
    )
}

fun LexiStorageService.saveNote(note: NoteItem, reason: String): NoteItem {
    return saveNote(note = note, recordHistory = true, historyReason = reason)
}

fun LexiStorageService.togglePinNote(noteId: String) {
    togglePin(noteId)
}

fun LexiStorageService.toggleFavoriteNote(noteId: String) {
    toggleFavorite(noteId)
}

fun LexiStorageService.softDeleteNote(noteId: String) {
    moveToTrash(noteId)
}

fun LexiStorageService.restoreNote(noteId: String) {
    restoreFromTrash(noteId)
}

fun LexiStorageService.purgeNote(noteId: String) {
    deleteForever(noteId)
}

fun LexiStorageService.markNoteOpened(noteId: String): Long {
    return recordNoteOpened(noteId)
}

fun LexiStorageService.softDeleteMindMap(mapId: String) {
    trashMindMap(mapId)
}

fun LexiStorageService.restoreMindMap(mapId: String) {
    restoreMindMapFromTrash(mapId)
}

fun LexiStorageService.purgeMindMap(mapId: String) {
    deleteMindMapForever(mapId)
}

fun LexiStorageService.duplicateMindMap(mapId: String): MindMapDoc? {
    val src = getMindMapById(mapId) ?: return null
    val copy = src.deepCopy().apply {
        id = ""
        title = "${src.title} 副本"
        createdAt = System.currentTimeMillis()
        updatedAt = createdAt
    }
    return saveMindMap(copy)
}

fun LexiStorageService.softDeleteCanvas(canvasId: String) {
    val board = getCanvasById(canvasId) ?: return
    board.trashedAt = System.currentTimeMillis()
    saveCanvas(board)
}

fun LexiStorageService.restoreCanvas(canvasId: String) {
    val board = getCanvasById(canvasId) ?: return
    board.trashedAt = 0L
    saveCanvas(board)
}

fun LexiStorageService.purgeCanvas(canvasId: String) {
    deleteCanvas(canvasId)
}

fun LexiStorageService.duplicateCanvas(canvasId: String): CanvasBoard? {
    val src = getCanvasById(canvasId) ?: return null
    val copy = src.deepCopy().apply {
        id = ""
        title = "${src.title} 副本"
        createdAt = System.currentTimeMillis()
        updatedAt = createdAt
    }
    return saveCanvas(copy)
}

fun LexiStorageService.convertNoteToMindMap(noteId: String): MindMapDoc {
    val note = getNoteById(noteId) ?: return createStarterMindMap()
    return createMindMapFromNote(note)
}

fun LexiStorageService.convertMindMapToNote(mapId: String): NoteItem {
    val map = getMindMapById(mapId) ?: return createNote(title = "导图大纲")
    val outline = MarkdownEngine.mindMapToMarkdownOutline(map)
    return createNote(
        title = "${map.title} · 大纲",
        content = outline,
        notebook = "思维导图",
        noteType = "study",
        editorLevel = "study",
        tags = listOf("思维导图"),
        projectId = map.projectId
    )
}

fun LexiStorageService.renameTag(oldTag: String, newTag: String, vaultId: String = "") {
    val cleanOld = oldTag.removePrefix("#").trim()
    val cleanNew = newTag.removePrefix("#").trim()
    if (cleanOld.isEmpty() || cleanNew.isEmpty() || cleanOld == cleanNew) return
    for (note in listNotes(vaultId)) {
        val hadTag = note.tags.any { it.equals(cleanOld, ignoreCase = true) }
        val replacedBody = note.content.replace(Regex("""(^|\s)#${Regex.escape(cleanOld)}(?=\s|$)"""), "$1#$cleanNew")
        if (hadTag || replacedBody != note.content) {
            note.tags = note.tags.map { if (it.equals(cleanOld, ignoreCase = true)) cleanNew else it }.distinct().toMutableList()
            note.content = replacedBody
            saveNote(note, recordHistory = false)
        }
    }
}

fun LexiStorageService.deleteTag(tag: String, vaultId: String = "") {
    val clean = tag.removePrefix("#").trim()
    if (clean.isEmpty()) return
    for (note in listNotes(vaultId)) {
        val hadTag = note.tags.any { it.equals(clean, ignoreCase = true) }
        val replacedBody = note.content.replace(Regex("""(^|\s)#${Regex.escape(clean)}(?=\s|$)"""), "$1")
        if (hadTag || replacedBody != note.content) {
            note.tags = note.tags.filterNot { it.equals(clean, ignoreCase = true) }.toMutableList()
            note.content = replacedBody
            saveNote(note, recordHistory = false)
        }
    }
}

fun LexiStorageService.saveCustomTemplate(item: LexiTemplateItem): LexiTemplateItem {
    if (item.name.isNotEmpty() && item.title.isEmpty()) item.title = item.name
    if (item.title.isNotEmpty() && item.name.isEmpty()) item.name = item.title
    return saveTemplate(item)
}

fun LexiStorageService.deleteCustomTemplate(id: String) {
    deleteTemplate(id)
}

fun LexiStorageService.createManualRevision(noteId: String): NoteRevision? {
    val note = getNoteById(noteId) ?: return null
    return saveManualRevision(note).firstOrNull()
}

fun LexiStorageService.getDraftWal(noteId: String): LexiDraftWalEntry? {
    return getPendingCrashDraftSync(noteId)
}

fun LexiStorageService.saveDraftWal(
    noteId: String,
    title: String,
    content: String,
    tags: List<String> = emptyList(),
    properties: List<NoteProperty> = emptyList()
): Boolean {
    return writeDraftWalSync(
        LexiDraftWalEntry(
            noteId = noteId,
            title = title,
            content = content,
            tags = tags.toMutableList(),
            properties = properties.map { it.copy() }.toMutableList(),
            updatedAt = System.currentTimeMillis()
        )
    )
}

fun LexiStorageService.clearDraftWal(noteId: String) {
    clearDraftWalSync(noteId)
    clearPendingCrashRecoverySync(noteId)
}

fun LexiStorageService.saveAttachmentImage(bytes: ByteArray, extension: String = "png"): String {
    val ext = extension.trim().removePrefix(".").ifEmpty { "png" }
    val fileName = "img-${System.currentTimeMillis()}.$ext"
    val basePath = storageLocationStatus().path
    return try {
        val dir = File(basePath, "attachments")
        dir.mkdirs()
        val file = File(dir, fileName)
        file.writeBytes(bytes)
        "file://${file.absolutePath}"
    } catch (_: Exception) {
        "attachments/$fileName"
    }
}

fun LexiStorageService.saveAttachmentImage(fileName: String, bytes: ByteArray): String {
    val ext = fileName.substringAfterLast('.', "png")
    return saveAttachmentImage(bytes, ext)
}

fun LexiStorageService.exportMarkdown(noteId: String): String {
    val note = getNoteById(noteId) ?: return ""
    return exportSingleNoteMarkdown(note)
}

fun LexiStorageService.exportMarkdown(note: NoteItem): String {
    return exportSingleNoteMarkdown(note)
}

fun LexiStorageService.importMarkdownFile(fileName: String, content: String): NoteItem {
    return importMarkdownText(fileName, content)
}

fun LexiStorageService.importZipArchive(bytes: ByteArray): Boolean {
    return try {
        var importedCount = 0
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    val name = entry.name.substringAfterLast('/')
                    val text = zis.readBytes().toString(Charsets.UTF_8)
                    if (name == "backup.json") {
                        if (importBackupJson(text)) importedCount++
                    } else if (name.endsWith(".md", ignoreCase = true) || name.endsWith(".markdown", ignoreCase = true)) {
                        importMarkdownText(name, text)
                        importedCount++
                    }
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
        importedCount > 0
    } catch (_: Exception) {
        false
    }
}

fun LexiStorageService.saveShareClip(draft: LexiShareDraft): LexiCapturedNoteSaveResult {
    if (draft.content.isEmpty() && draft.text.isNotEmpty()) {
        draft.content = draft.text
    }
    return saveSharedClip(draft)
}

fun LexiStorageService.activeLocalRootPath(): String {
    return storageLocationStatus().path
}

fun LexiStorageService.resetToInternalStorage() {
    deleteSetting("localRootUri")
    deleteSetting("localRootPermissionUri")
    setSetting("storageAccessPrompt:v1", "internal")
}

fun LexiStorageService.syncSnapshotToLocalRoot(): Boolean {
    return rebuildIndex() >= 0
}

fun LexiStorageService.pruneAllNoteHistories(): LexiHistoryPruneResult {
    val removed = pruneAllHistoryNow()
    return LexiHistoryPruneResult(removedCount = removed)
}

// --- Settings convenience getters & setters ---

fun LexiStorageService.isOnboardingCompleted(): Boolean {
    return getSetting("onboardingCompleted", "false") == "true"
}

fun LexiStorageService.setOnboardingCompleted(completed: Boolean) {
    setSetting("onboardingCompleted", if (completed) "true" else "false")
}

fun LexiStorageService.getThemeId(): String {
    return getSetting("themeId", "purple")
}

fun LexiStorageService.setThemeId(themeId: String) {
    setSetting("themeId", themeId)
}

fun LexiStorageService.getColorMode(): String {
    return getSetting("appearanceMode", "light")
}

fun LexiStorageService.setColorMode(mode: String) {
    setSetting("appearanceMode", mode)
}

fun LexiStorageService.getAccentColor(): String {
    return getSetting("customAccentHex", "")
}

fun LexiStorageService.setAccentColor(hex: String) {
    setSetting("customAccentHex", hex)
}

fun LexiStorageService.getHomeRecentNotesMode(): String {
    return getSetting("homeRecentNotesMode", "opened")
}

fun LexiStorageService.setHomeRecentNotesMode(mode: String) {
    setSetting("homeRecentNotesMode", mode)
}

fun LexiStorageService.getNoteSortMode(vaultId: String = ""): String {
    return getSetting("noteSortMode", "updated", vaultId)
}

fun LexiStorageService.setNoteSortMode(mode: String, vaultId: String = "") {
    setSetting("noteSortMode", mode, vaultId)
}

fun LexiStorageService.getNoteViewMode(vaultId: String = ""): String {
    return getSetting("noteViewMode", "card", vaultId)
}

fun LexiStorageService.setNoteViewMode(mode: String, vaultId: String = "") {
    setSetting("noteViewMode", mode, vaultId)
}

fun LexiStorageService.getDefaultEditorViewMode(): String {
    return getSetting("defaultEditMode", "live")
}

fun LexiStorageService.setDefaultEditorViewMode(mode: String) {
    setSetting("defaultEditMode", mode)
}

fun LexiStorageService.getNoteToolbarMode(): String {
    return getSetting("defaultEditorTier", "study")
}

fun LexiStorageService.setNoteToolbarMode(mode: String) {
    setSetting("defaultEditorTier", mode)
}

fun LexiStorageService.getEditorFontSize(): Int {
    return getSetting("fontSize", "16").toIntOrNull()?.coerceIn(13, 24) ?: 16
}

fun LexiStorageService.setEditorFontSize(size: Int) {
    setSetting("fontSize", size.coerceIn(13, 24).toString())
}

fun LexiStorageService.getEditorShowLineNumbers(): Boolean {
    return getSetting("editorShowLineNumbers", "true") == "true"
}

fun LexiStorageService.setEditorShowLineNumbers(show: Boolean) {
    setSetting("editorShowLineNumbers", if (show) "true" else "false")
}

fun LexiStorageService.getEditorReadableLineLength(): Boolean {
    return getSetting("readableLineLength", "true") == "true"
}

fun LexiStorageService.setEditorReadableLineLength(enabled: Boolean) {
    setSetting("readableLineLength", if (enabled) "true" else "false")
}

fun LexiStorageService.getEditorSpellcheck(): Boolean {
    return getSetting("editorSpellcheck", "false") == "true"
}

fun LexiStorageService.setEditorSpellcheck(enabled: Boolean) {
    setSetting("editorSpellcheck", if (enabled) "true" else "false")
}

fun LexiStorageService.getAutoUpdateLinks(): Boolean {
    return getSetting("autoUpdateLinks", "true") == "true"
}

fun LexiStorageService.setAutoUpdateLinks(enabled: Boolean) {
    setSetting("autoUpdateLinks", if (enabled) "true" else "false")
}

fun LexiStorageService.getPluginSafeMode(): Boolean {
    return getSetting("pluginSafeMode", "false") == "true"
}

fun LexiStorageService.setPluginSafeMode(enabled: Boolean) {
    setSetting("pluginSafeMode", if (enabled) "true" else "false")
}

fun LexiStorageService.getAppLanguage(): String {
    return getSetting("language", "zh-Hans")
}

fun LexiStorageService.setAppLanguage(lang: String) {
    setSetting("language", lang)
}
