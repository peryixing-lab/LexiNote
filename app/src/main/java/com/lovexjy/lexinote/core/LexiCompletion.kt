package com.lovexjy.lexinote.core

import java.net.URLDecoder

data class LexiLinkTarget(
    var noteName: String = "",
    var anchor: String = ""
)

data class LexiCompletionContext(
    var kind: String = "",
    var query: String = "",
    var noteName: String = "",
    var start: Int = 0,
    var end: Int = 0
)

data class LexiCompletionCandidate(
    var id: String = "",
    var label: String = "",
    var detail: String = "",
    var insertion: String = ""
)

data class LexiCompletionEdit(
    var text: String = "",
    var cursor: Int = 0
)

/**
 * Shared cursor-aware completion and link handling for both editor surfaces.
 * Exact 1:1 port of LexiCompletion.ets.
 */
object LexiCompletion {
    private val wikiPrefixSuffixRegex = Regex("""^!\[\[|^\[\[|\]\]$""")
    private val wikiContextRegex = Regex("""\[\[([^\[\]\n]{0,160})$""")
    private val tagContextRegex = Regex("""(?:^|\s)#([\u4e00-\u9fffA-Za-z0-9_/-]{0,48})$""")
    private val headingLineRegex = Regex("""^\s*#{1,6}\s""")
    private val fenceLineRegex = Regex("""^\s*(`{3,}|~{3,})""")

    fun splitTarget(raw: String): LexiLinkTarget {
        val target = LexiLinkTarget()
        val clean = raw.replace(wikiPrefixSuffixRegex, "").split("|")[0].trim()
        val marker = clean.indexOf('#')
        target.noteName = (if (marker < 0) clean else clean.substring(0, marker)).trim()
        target.anchor = if (marker < 0) "" else clean.substring(marker + 1).trim()
        try {
            target.anchor = URLDecoder.decode(target.anchor, "UTF-8")
        } catch (_: Exception) {
        }
        return target
    }

    fun context(text: String, start: Int, end: Int = start): LexiCompletionContext {
        val result = LexiCompletionContext()
        if (start != end || start < 0 || start > text.length || inCode(text, start)) {
            return result
        }
        val before = text.substring(0, start)
        val wiki = wikiContextRegex.find(before)
        if (wiki != null) {
            result.kind = "note"
            result.query = wiki.groupValues[1]
            result.start = start - wiki.value.length
            result.end = start
            val hash = result.query.indexOf('#')
            if (hash >= 0) {
                result.kind = "heading"
                result.noteName = result.query.substring(0, hash).trim()
                result.query = result.query.substring(hash + 1)
            }
            return result
        }
        val tag = tagContextRegex.find(before)
        val lineStart = before.substring(before.lastIndexOf('\n') + 1)
        if (tag != null && !headingLineRegex.containsMatchIn(lineStart)) {
            result.kind = "tag"
            result.query = tag.groupValues[1]
            result.start = start - tag.groupValues[1].length - 1
            result.end = start
        }
        return result
    }

    fun candidates(context: LexiCompletionContext, notes: List<NoteItem>, currentId: String): List<LexiCompletionCandidate> {
        val results = mutableListOf<LexiCompletionCandidate>()
        val query = context.query.trim().lowercase()
        when (context.kind) {
            "heading" -> {
                val note = notes.find { n ->
                    n.trashedAt == 0L && (
                        if (context.noteName.isNotEmpty()) {
                            n.id == context.noteName || n.title.trim().lowercase() == context.noteName.lowercase()
                        } else {
                            n.id == currentId
                        }
                        )
                } ?: return results
                for (heading in MarkdownEngine.extractOutline(note.content)) {
                    if (query.isNotEmpty() && !heading.title.lowercase().contains(query)) continue
                    results.add(
                        LexiCompletionCandidate(
                            id = "${note.id}-${heading.id}",
                            label = heading.title,
                            detail = "${MarkdownEngine.displayTitle(note)} · 章节",
                            insertion = "[[${context.noteName}#${heading.title}]]"
                        )
                    )
                    if (results.size >= 6) break
                }
            }
            "note" -> {
                for (note in notes) {
                    if (note.trashedAt > 0L || note.id == currentId) continue
                    val title = MarkdownEngine.displayTitle(note)
                    if (query.isNotEmpty() && !title.lowercase().contains(query)) continue
                    results.add(
                        LexiCompletionCandidate(
                            id = note.id,
                            label = title,
                            detail = note.notebook.ifEmpty { "笔记" },
                            insertion = "[[$title]]"
                        )
                    )
                    if (results.size >= 6) break
                }
            }
            "tag" -> {
                val seen = mutableSetOf<String>()
                for (note in notes) {
                    if (note.trashedAt > 0L) continue
                    val tags = note.tags + MarkdownEngine.extractInlineTags(note.content)
                    for (tag in tags) {
                        if (seen.contains(tag) || (query.isNotEmpty() && !tag.lowercase().contains(query))) continue
                        seen.add(tag)
                        results.add(
                            LexiCompletionCandidate(
                                id = "tag-$tag",
                                label = "#$tag",
                                detail = "已有标签",
                                insertion = "#$tag "
                            )
                        )
                        if (results.size >= 6) return results
                    }
                }
            }
        }
        return results
    }

    fun apply(text: String, context: LexiCompletionContext, candidate: LexiCompletionCandidate): LexiCompletionEdit {
        var end = context.end
        if (context.kind != "tag" && end + 2 <= text.length && text.substring(end, end + 2) == "]]") {
            end += 2
        }
        return LexiCompletionEdit(
            text = text.substring(0, context.start) + candidate.insertion + text.substring(end),
            cursor = context.start + candidate.insertion.length
        )
    }

    fun findHeading(headings: List<OutlineHeading>, anchor: String): OutlineHeading? {
        val normalize = { title: String ->
            title.trim().lowercase().replace(Regex("""[*`~]"""), "").replace(Regex("""\s+"""), "-")
        }
        val target = normalize(anchor)
        return headings.find { normalize(it.title) == target }
    }

    fun linkFirstMention(markdown: String, title: String): String {
        val needle = title.trim()
        if (needle.isEmpty() || Regex("""[\[\]\n|]""").containsMatchIn(needle)) {
            return markdown
        }
        var offset = 0
        val lowerMarkdown = markdown.lowercase()
        val lowerNeedle = needle.lowercase()
        while (offset < markdown.length) {
            val found = lowerMarkdown.indexOf(lowerNeedle, offset)
            if (found < 0) return markdown
            offset = found + needle.length
            if (inCode(markdown, found)) continue
            val before = markdown.substring(0, found)
            val after = markdown.substring(offset)
            val fmEnd = if (markdown.startsWith("---\n")) markdown.indexOf("\n---", 4) else -1
            if (fmEnd >= 0 && found < fmEnd + 4) continue
            if (before.lastIndexOf("[[") > before.lastIndexOf("]]")) continue
            if (before.lastIndexOf('[') > before.lastIndexOf(']') || Regex("""\]\([^)]*$""").containsMatchIn(before)) continue
            if (Regex("""(?:https?://|file://)[^\s]*$""").containsMatchIn(before)) continue
            if ((Regex("""[A-Za-z0-9_]$""").containsMatchIn(before) && Regex("""^[A-Za-z0-9_]""").containsMatchIn(needle)) ||
                (Regex("""[A-Za-z0-9_]$""").containsMatchIn(needle) && Regex("""^[A-Za-z0-9_]""").containsMatchIn(after))
            ) {
                continue
            }
            return markdown.substring(0, found) + "[[$needle]]" + after
        }
        return markdown
    }

    private fun inCode(text: String, position: Int): Boolean {
        val before = text.substring(0, position)
        val lines = before.split("\n")
        var fence = ""
        for (line in lines) {
            val match = fenceLineRegex.find(line) ?: continue
            val marker = match.groupValues[1]
            if (fence.isEmpty()) {
                fence = marker
            } else if (marker[0] == fence[0] && marker.length >= fence.length) {
                fence = ""
            }
        }
        if (fence.isNotEmpty()) return true
        val lastLine = lines.lastOrNull() ?: ""
        return lastLine.count { it == '`' } % 2 == 1
    }
}
