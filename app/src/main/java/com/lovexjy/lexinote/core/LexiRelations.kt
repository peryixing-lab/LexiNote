package com.lovexjy.lexinote.core

data class RelatedContent(
    var id: String = "",
    var title: String = "",
    var snippet: String = "",
    var kind: String = "note",
    var reason: String = ""
)

private class LexiScoredLinkCandidate(
    val item: LexiLinkCandidate,
    val score: Int,
    val updatedAt: Long
)

/**
 * Human-readable, deduplicated relations, independent of graph display filters.
 * Exact 1:1 port of LexiRelations.ets.
 */
object LexiRelations {
    fun counts(contents: List<GraphNode>, maps: List<MindMapDoc>, links: List<NoteLink>): Map<String, Int> {
        val neighbours = mutableMapOf<String, MutableSet<String>>()
        for (content in contents) {
            neighbours[content.id] = mutableSetOf()
        }
        val connect = { source: String, target: String ->
            if (source != target) {
                val a = neighbours[source]
                val b = neighbours[target]
                if (a != null && b != null) {
                    a.add(target)
                    b.add(source)
                }
            }
        }
        for (link in links) {
            connect(link.sourceId, link.targetId)
        }
        for (map in maps) {
            if (map.trashedAt > 0L) continue
            for (node in map.nodes) {
                connect("map:${map.id}", node.noteRefId)
            }
        }
        val result = mutableMapOf<String, Int>()
        for ((id, ids) in neighbours) {
            result[id] = ids.size
        }
        return result
    }

    fun contents(notes: List<NoteItem>, maps: List<MindMapDoc>): List<GraphNode> {
        val result = mutableListOf<GraphNode>()
        for (note in notes) {
            if (note.trashedAt > 0L) continue
            result.add(
                GraphNode(
                    id = note.id,
                    label = MarkdownEngine.displayTitle(note),
                    snippet = MarkdownEngine.extractSnippet(note)
                )
            )
        }
        for (map in maps) {
            if (map.trashedAt > 0L) continue
            result.add(
                GraphNode(
                    id = "map:${map.id}",
                    label = map.title.ifEmpty { "未命名导图" },
                    kind = "mindmap",
                    snippet = "思维导图"
                )
            )
        }
        return result
    }

    fun connected(focusId: String, contents: List<GraphNode>, maps: List<MindMapDoc>, links: List<NoteLink>): List<RelatedContent> {
        val reasons = mutableMapOf<String, String>()
        for (link in links) {
            if (link.targetId.isEmpty() || link.sourceId == link.targetId) continue
            if (link.sourceId == focusId) {
                reasons[link.targetId] = "这篇笔记引用了它"
            }
            if (link.targetId == focusId) {
                reasons[link.sourceId] = if (reasons.containsKey(link.sourceId)) "两篇笔记互相引用" else "它引用了这篇笔记"
            }
        }
        for (link in links) {
            if (link.sourceId == focusId && links.any { other -> other.sourceId == link.targetId && other.targetId == focusId }) {
                reasons[link.targetId] = "两篇笔记互相引用"
            }
        }
        for (map in maps) {
            if (map.trashedAt > 0L) continue
            for (node in map.nodes) {
                if (node.noteRefId.isEmpty()) continue
                if (focusId == "map:${map.id}") {
                    reasons[node.noteRefId] = "导图中的笔记引用"
                }
                if (focusId == node.noteRefId) {
                    reasons["map:${map.id}"] = "这张导图引用了它"
                }
            }
        }
        val result = mutableListOf<RelatedContent>()
        for (content in contents) {
            val reason = reasons[content.id]
            if (reason == null || content.id == focusId) continue
            result.add(
                RelatedContent(
                    id = content.id,
                    title = content.label,
                    snippet = content.snippet,
                    kind = content.kind,
                    reason = reason
                )
            )
        }
        return result
    }

    fun connectedNoteIds(links: List<NoteLink>, maps: List<MindMapDoc> = emptyList(), includeMaps: Boolean = false): Set<String> {
        val ids = mutableSetOf<String>()
        for (link in links) {
            if (link.targetId.isNotEmpty() && link.sourceId.isNotEmpty() && link.sourceId != link.targetId) {
                ids.add(link.sourceId)
                ids.add(link.targetId)
            }
        }
        if (includeMaps) {
            for (map in maps) {
                if (map.trashedAt > 0L) continue
                for (node in map.nodes) {
                    if (node.noteRefId.isNotEmpty()) {
                        ids.add(node.noteRefId)
                    }
                }
            }
        }
        return ids
    }

    fun unconnectedNotes(
        notes: List<NoteItem>,
        links: List<NoteLink>,
        maps: List<MindMapDoc> = emptyList(),
        includeMaps: Boolean = false
    ): List<NoteItem> {
        val connected = connectedNoteIds(links, maps, includeMaps)
        return notes.filter { it.trashedAt == 0L && !connected.contains(it.id) }
    }

    fun isNoteUnconnected(noteId: String, links: List<NoteLink>): Boolean {
        if (noteId.isEmpty()) return false
        return !links.any { link ->
            link.targetId.isNotEmpty() && link.sourceId != link.targetId && (link.sourceId == noteId || link.targetId == noteId)
        }
    }

    fun suggestLinkCandidates(
        note: NoteItem,
        notes: List<NoteItem>,
        links: List<NoteLink>,
        limit: Int = 4
    ): List<LexiLinkCandidate> {
        val active = notes.filter { it.trashedAt == 0L && it.id != note.id && it.vaultId == note.vaultId }
        val linked = mutableSetOf<String>()
        for (link in links) {
            if (link.sourceId == note.id && link.targetId.isNotEmpty()) linked.add(link.targetId)
            if (link.targetId == note.id && link.sourceId.isNotEmpty()) linked.add(link.sourceId)
        }
        val sourceTitleLower = (note.title.trim().ifEmpty { MarkdownEngine.displayTitle(note) }).lowercase()
        val sourceBodyLower = note.content.lowercase()
        val sourceTags = note.tags.map { it.trim().lowercase() }.toSet()
        val scored = mutableListOf<LexiScoredLinkCandidate>()
        for (other in active) {
            if (linked.contains(other.id)) continue
            val otherTitle = MarkdownEngine.displayTitle(other)
            val otherTitleLower = otherTitle.lowercase()
            var score = 0
            var reason = ""
            if (otherTitle.length >= 2 && sourceBodyLower.contains(otherTitleLower)) {
                score += 5
                reason = "正文中提及此笔记"
            } else if (sourceTitleLower.length >= 2 && other.content.lowercase().contains(sourceTitleLower)) {
                score += 4
                reason = "对方正文中提及本笔记"
            }
            for (rawTag in other.tags) {
                val lowerTag = rawTag.trim().lowercase()
                if (lowerTag.isNotEmpty() && sourceTags.contains(lowerTag)) {
                    score += 3
                    if (reason.isEmpty()) reason = "共同标签 #$rawTag"
                    break
                }
            }
            if (other.notebook.isNotEmpty() && note.notebook.isNotEmpty() && other.notebook == note.notebook) {
                score += 1
                if (reason.isEmpty()) reason = "同在「${other.notebook}」"
            }
            if (score == 0) continue
            scored.add(
                LexiScoredLinkCandidate(
                    item = LexiLinkCandidate(
                        noteId = other.id,
                        title = otherTitle,
                        notebook = other.notebook.ifEmpty { "笔记" },
                        reason = reason
                    ),
                    score = score,
                    updatedAt = other.updatedAt
                )
            )
        }
        scored.sortWith { a, b ->
            if (b.score != a.score) b.score.compareTo(a.score) else b.updatedAt.compareTo(a.updatedAt)
        }
        return scored.take(limit).map { it.item }
    }
}
