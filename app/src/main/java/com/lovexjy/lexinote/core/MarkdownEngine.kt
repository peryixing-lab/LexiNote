package com.lovexjy.lexinote.core

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import kotlin.math.max
import kotlin.math.min

data class RawWikiLink(
    var targetText: String = "",
    var anchor: String = "",
    var displayText: String = ""
) {
    val targetTitle: String
        get() = targetText
    val heading: String
        get() = anchor
    val alias: String
        get() = displayText
}

data class LexiMarkdownTable(
    var rows: MutableList<MutableList<String>> = mutableListOf(),
    var alignments: MutableList<String> = mutableListOf()
)

data class LexiMarkdownInlineSpan(
    var id: String = "",
    var text: String = "",
    var kind: String = "text",
    var target: String = "",
    var searchMatch: Boolean = false
)

/**
 * Exact 1:1 port of MarkdownEngine.ets.
 */
object MarkdownEngine {
    fun parseFrontmatter(markdown: String): LexiFrontmatterResult {
        return LexiFrontmatter.parse(markdown)
    }

    fun serializeFrontmatter(note: NoteItem): String {
        return LexiFrontmatter.serialize(note)
    }

    private val inlinePattern = Regex(
        """`([^`]+)`|\[\[([^\[\]]+)\]\]|\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)|\*\*([^*]+)\*\*|__([^_]+)__|==([^=]+)==|~~([^~]+)~~|\*([^*\n]+)\*|_([^_\n]+)_|<mark data-color="(red|orange|yellow|green|blue|purple)">([^<]+)</mark>"""
    )

    fun inlineSpans(text: String): List<LexiMarkdownInlineSpan> {
        val spans = mutableListOf<LexiMarkdownInlineSpan>()
        val protectedBuilder = StringBuilder()
        var protectedCursor = 0
        for (token in LexiMathSyntax.inlineTokens(text)) {
            protectedBuilder.append(text.substring(protectedCursor, token.start))
            protectedBuilder.append("\uFFFC".repeat(token.end - token.start))
            protectedCursor = token.end
        }
        protectedBuilder.append(text.substring(protectedCursor))
        val protectedText = protectedBuilder.toString()

        var cursor = 0
        for (match in inlinePattern.findAll(protectedText)) {
            val matchIndex = match.range.first
            val matchLen = match.value.length
            if (matchIndex > cursor) {
                appendMathSpans(spans, text.substring(cursor, matchIndex), cursor, "text")
            }
            val segment = LexiMarkdownInlineSpan(id = "mark-$matchIndex")
            val raw = text.substring(matchIndex, matchIndex + matchLen)
            var contentOffset = matchIndex + 1
            val groups = match.groupValues
            when {
                groups[1].isNotEmpty() -> {
                    segment.kind = "code"
                    segment.text = raw.substring(1, raw.length - 1)
                }
                groups[2].isNotEmpty() -> {
                    val parts = raw.substring(2, raw.length - 2).split("|")
                    segment.kind = "link"
                    segment.target = parts[0].trim()
                    segment.text = if (parts.size > 1) parts.drop(1).joinToString("|").trim() else segment.target
                }
                groups[3].isNotEmpty() -> {
                    segment.kind = "url"
                    segment.text = raw.substring(1, 1 + groups[3].length)
                    segment.target = groups[4]
                }
                groups[5].isNotEmpty() || groups[6].isNotEmpty() -> {
                    segment.kind = "bold"
                    segment.text = raw.substring(2, raw.length - 2)
                    contentOffset++
                }
                groups[7].isNotEmpty() -> {
                    segment.kind = "highlight"
                    segment.text = raw.substring(2, raw.length - 2)
                    contentOffset++
                }
                groups[8].isNotEmpty() -> {
                    segment.kind = "strike"
                    segment.text = raw.substring(2, raw.length - 2)
                    contentOffset++
                }
                groups[11].isNotEmpty() -> {
                    segment.kind = "highlight"
                    segment.target = groups[11]
                    val gtIndex = raw.indexOf('>')
                    val closeMark = raw.lastIndexOf("</mark>")
                    segment.text = if (gtIndex >= 0 && closeMark > gtIndex) {
                        raw.substring(gtIndex + 1, closeMark)
                    } else {
                        groups[12]
                    }
                    contentOffset = matchIndex + gtIndex + 1
                }
                else -> {
                    segment.kind = "italic"
                    segment.text = raw.substring(1, raw.length - 1)
                }
            }
            if (segment.kind != "code" && segment.kind != "link" && segment.kind != "url" && LexiMathSyntax.hasMath(segment.text)) {
                appendMathSpans(spans, segment.text, contentOffset, segment.kind)
            } else {
                spans.add(segment)
            }
            cursor = matchIndex + matchLen
        }
        if (cursor < text.length) {
            appendMathSpans(spans, text.substring(cursor), cursor, "text")
        }
        return spans
    }

    private fun appendMathSpans(
        spans: MutableList<LexiMarkdownInlineSpan>,
        text: String,
        offset: Int,
        kind: String
    ) {
        var cursor = 0
        for (token in LexiMathSyntax.inlineTokens(text)) {
            if (token.start > cursor) {
                spans.add(
                    LexiMarkdownInlineSpan(
                        id = "text-${offset + cursor}",
                        kind = kind,
                        text = text.substring(cursor, token.start)
                    )
                )
            }
            spans.add(
                LexiMarkdownInlineSpan(
                    id = "math-${offset + token.start}",
                    text = token.text,
                    kind = if (token.displayMode) "math-display" else "math"
                )
            )
            cursor = token.end
        }
        if (cursor < text.length) {
            spans.add(
                LexiMarkdownInlineSpan(
                    id = "text-${offset + cursor}",
                    kind = kind,
                    text = text.substring(cursor)
                )
            )
        }
    }

    fun splitTableRow(line: String): MutableList<String> {
        var raw = line.trim()
        if (raw.startsWith("|")) raw = raw.substring(1)
        if (raw.endsWith("|") && !raw.endsWith("\\|")) raw = raw.substring(0, raw.length - 1)
        val cells = mutableListOf<String>()
        val mathTokens = LexiMathSyntax.inlineTokens(raw)
        var mathIndex = 0
        val cell = StringBuilder()
        var inCode = false
        var index = 0
        while (index < raw.length) {
            val ch = raw[index]
            val mathToken = mathTokens.getOrNull(mathIndex)
            if (mathToken != null && index == mathToken.start) {
                cell.append(raw.substring(mathToken.start, mathToken.end))
                index = mathToken.end
                mathIndex++
                continue
            } else if (ch == '\\' && index + 1 < raw.length && raw[index + 1] == '|') {
                cell.append('|')
                index += 2
                continue
            } else if (ch == '`') {
                inCode = !inCode
                cell.append(ch)
            } else if (ch == '|' && !inCode) {
                cells.add(cell.toString().trim())
                cell.setLength(0)
            } else {
                cell.append(ch)
            }
            index++
        }
        cells.add(cell.toString().trim())
        return cells
    }

    fun encodeTableData(table: LexiMarkdownTable): String {
        val obj = JSONObject()
        val rowsArr = JSONArray()
        for (row in table.rows) {
            val r = JSONArray()
            for (c in row) r.put(c)
            rowsArr.put(r)
        }
        val alignArr = JSONArray()
        for (a in table.alignments) alignArr.put(a)
        obj.put("rows", rowsArr)
        obj.put("alignments", alignArr)
        return obj.toString()
    }

    fun tableData(block: MarkdownBlock): LexiMarkdownTable {
        return try {
            val obj = JSONObject(block.meta)
            val rowsArr = obj.optJSONArray("rows") ?: JSONArray()
            val alignArr = obj.optJSONArray("alignments") ?: JSONArray()
            val table = LexiMarkdownTable()
            for (i in 0 until rowsArr.length()) {
                val r = rowsArr.optJSONArray(i) ?: continue
                val rowList = mutableListOf<String>()
                for (j in 0 until r.length()) {
                    rowList.add(r.optString(j, ""))
                }
                table.rows.add(rowList)
            }
            for (i in 0 until alignArr.length()) {
                table.alignments.add(alignArr.optString(i, "left"))
            }
            table
        } catch (_: Exception) {
            LexiMarkdownTable()
        }
    }

    fun resolveImageSource(uri: String, notePath: String): String {
        var source = uri.trim()
        if (source.startsWith("<") && source.endsWith(">") && source.length >= 2) {
            source = source.substring(1, source.length - 1)
        }
        if (Regex("""^(https?://|file://|data:image/|resource://)""", RegexOption.IGNORE_CASE).containsMatchIn(source)) {
            return source
        }
        if (Regex("""^[A-Za-z][A-Za-z0-9+.-]*:""").containsMatchIn(source)) {
            return ""
        }
        try {
            source = URLDecoder.decode(source, "UTF-8")
        } catch (_: Exception) {
        }
        if (source.startsWith("/")) {
            return "file://$source"
        }
        if (notePath.isEmpty() || source.isEmpty()) {
            return ""
        }
        val localPath = notePath.replaceFirst(Regex("""^file://(?:[^/]+)?"""), "")
        val lastSlash = localPath.lastIndexOf('/')
        val base = if (lastSlash >= 0) localPath.substring(0, lastSlash) else ""
        val components = "$base/$source".split("/")
        val normalized = mutableListOf<String>()
        for (comp in components) {
            if (comp == "..") {
                if (normalized.isNotEmpty()) normalized.removeAt(normalized.size - 1)
            } else if (comp != "." && comp.isNotEmpty()) {
                normalized.add(comp)
            }
        }
        return "file:///${normalized.joinToString("/")}"
    }

    fun extractEmbeddedSection(markdown: String, anchor: String = ""): String {
        val parsed = LexiFrontmatter.parse(markdown)
        if (anchor.trim().isEmpty()) {
            return parsed.body.trim().take(800)
        }
        val headings = extractOutline(markdown)
        val normalized = anchor.trim().lowercase().replace(Regex("""\s+"""), "-")
        val heading = headings.find {
            it.title.trim().lowercase().replace(Regex("""\s+"""), "-") == normalized
        } ?: return ""
        val next = headings.find {
            it.lineIndex > heading.lineIndex && it.level <= heading.level
        }
        val allLines = markdown.split("\n")
        val endIdx = next?.lineIndex ?: allLines.size
        val startIdx = min(heading.lineIndex + 1, endIdx)
        return allLines.subList(startIdx, endIdx).joinToString("\n").trim().take(800)
    }

    private val wikiLinkRegex = Regex("""(?<!!)\[\[([^\[\]]+)\]\]""")
    private val inlineTagRegex = Regex("""(?:^|\s)#([\u4e00-\u9fa5A-Za-z0-9_/-]{1,28})""")
    private val hexColorTagRegex = Regex("""^[0-9a-fA-F]{3,8}$""")
    private val fenceOpenLineRegex = Regex("""^\s*(`{3,}|~{3,})""")

    fun extractWikiLinks(markdown: String): List<RawWikiLink> {
        val results = mutableListOf<RawWikiLink>()
        val lines = markdown.split("\n")
        var fence = ""
        for (line in lines) {
            if (fence.isNotEmpty()) {
                if (Regex("""^\s*${fence[0]}{${fence.length},}\s*$""").matches(line)) {
                    fence = ""
                }
                continue
            }
            val fenceMatch = fenceOpenLineRegex.find(line)
            if (fenceMatch != null) {
                fence = fenceMatch.groupValues[1]
                continue
            }
            for (match in wikiLinkRegex.findAll(line)) {
                val inner = match.groupValues[1].trim()
                if (inner.isNotEmpty()) {
                    val pipeParts = inner.split("|")
                    val left = pipeParts[0].trim()
                    val display = if (pipeParts.size > 1) pipeParts.drop(1).joinToString("|").trim() else left
                    val hashParts = left.split("#")
                    val target = hashParts[0].trim()
                    val anchor = if (hashParts.size > 1) hashParts.drop(1).joinToString("#").trim() else ""
                    if (target.isNotEmpty()) {
                        results.add(RawWikiLink(targetText = target, anchor = anchor, displayText = display))
                    }
                }
            }
        }
        return results
    }

    fun extractInlineTags(markdown: String): List<String> {
        val tags = mutableListOf<String>()
        val lines = markdown.split("\n")
        var fence = ""
        for (line in lines) {
            if (fence.isNotEmpty()) {
                if (Regex("""^\s*${fence[0]}{${fence.length},}\s*$""").matches(line)) {
                    fence = ""
                }
                continue
            }
            val fenceMatch = fenceOpenLineRegex.find(line)
            if (fenceMatch != null) {
                fence = fenceMatch.groupValues[1]
                continue
            }
            for (match in inlineTagRegex.findAll(line)) {
                val tag = match.groupValues[1].trim()
                if (tag.isNotEmpty() && !hexColorTagRegex.matches(tag) && !tags.contains(tag)) {
                    tags.add(tag)
                }
            }
        }
        return tags
    }

    fun buildNoteLinks(notes: List<NoteItem>): List<NoteLink> {
        val activeNotes = notes.filter { it.trashedAt == 0L }
        val links = mutableListOf<NoteLink>()
        for (source in activeNotes) {
            val rawLinks = extractWikiLinks(source.content)
            for (raw in rawLinks) {
                val target = activeNotes.find { candidate ->
                    candidate.vaultId == source.vaultId && (
                        candidate.id == raw.targetText ||
                            candidate.title.trim().lowercase() == raw.targetText.lowercase()
                        )
                }
                val link = NoteLink(
                    sourceId = source.id,
                    sourceTitle = displayTitle(source),
                    targetId = target?.id ?: "",
                    targetTitle = target?.let { displayTitle(it) } ?: raw.targetText,
                    anchor = raw.anchor,
                    displayText = raw.displayText
                )
                val duplicate = links.any { existing ->
                    existing.sourceId == link.sourceId &&
                        existing.targetTitle == link.targetTitle &&
                        existing.anchor == link.anchor
                }
                if (!duplicate) {
                    links.add(link)
                }
            }
        }
        return links
    }

    fun findUnlinkedMentions(notes: List<NoteItem>, links: List<NoteLink>): List<UnlinkedMention> {
        val active = notes.filter { it.trashedAt == 0L && it.title.trim().length >= 2 }
        val mentions = mutableListOf<UnlinkedMention>()
        for (target in active) {
            val targetTitle = target.title.trim()
            for (source in active) {
                if (source.id == target.id || source.vaultId != target.vaultId) continue
                val alreadyLinked = links.any { l ->
                    l.sourceId == source.id && (l.targetId == target.id || l.targetTitle == targetTitle)
                }
                if (alreadyLinked) continue
                val idx = source.content.indexOf(targetTitle)
                if (idx >= 0) {
                    val start = max(0, idx - 16)
                    val end = min(source.content.length, idx + targetTitle.length + 24)
                    mentions.add(
                        UnlinkedMention(
                            sourceId = source.id,
                            sourceTitle = displayTitle(source),
                            targetId = target.id,
                            targetTitle = targetTitle,
                            snippet = source.content.substring(start, end).replace("\n", " ")
                        )
                    )
                    if (mentions.size >= 16) return mentions
                }
            }
        }
        return mentions
    }

    fun renameLinksInMarkdown(content: String, oldTitle: String, newTitle: String): String {
        val cleanOld = oldTitle.trim()
        val cleanNew = newTitle.trim()
        if (cleanOld.isEmpty() || cleanNew.isEmpty() || cleanOld == cleanNew) {
            return content
        }
        return wikiLinkRegex.replace(content) { matchResult ->
            val inner = matchResult.groupValues[1]
            val pipeParts = inner.split("|")
            val left = pipeParts[0].trim()
            val hashParts = left.split("#")
            val target = hashParts[0].trim()
            if (target.lowercase() != cleanOld.lowercase()) {
                "[[$inner]]"
            } else {
                val anchorSuffix = if (hashParts.size > 1) "#${hashParts.drop(1).joinToString("#")}" else ""
                val displaySuffix = if (pipeParts.size > 1) "|${pipeParts.drop(1).joinToString("|")}" else ""
                "[[$cleanNew$anchorSuffix$displaySuffix]]"
            }
        }
    }

    private val stripHeadingCharsRegex = Regex("""^[#>*\-\s]+""")

    fun displayTitle(note: NoteItem): String {
        if (note.title.trim().isNotEmpty()) {
            return note.title.trim()
        }
        val firstLine = LexiFrontmatter.parse(note.content).body
            .split("\n")
            .map { it.replace(stripHeadingCharsRegex, "").trim() }
            .firstOrNull { it.isNotEmpty() }
        if (!firstLine.isNullOrEmpty()) {
            return firstLine.take(28)
        }
        return "未命名速记"
    }

    fun previewSpans(note: NoteItem, query: String = ""): List<LexiMarkdownInlineSpan> {
        val segments = mutableListOf<LexiMarkdownInlineSpan>()
        var length = 0
        val title = displayTitle(note)
        for (block in parseBlocks(note.content)) {
            if (block.kind == "hr") continue
            if (segments.isEmpty() && block.kind == "h1" && block.text.trim() == title) continue
            var text = block.text
            var literal = false
            when (block.kind) {
                "table" -> {
                    text = tableData(block).rows.take(3).joinToString("；") { it.joinToString(" · ") }
                }
                "todo" -> text = "${if (block.checked) "☑" else "☐"} $text"
                "bullet" -> text = "• $text"
                "ordered" -> text = "${block.meta}. $text"
                "image" -> {
                    text = block.text.ifEmpty { "图片" }
                    literal = true
                }
                "embed" -> {
                    text = "引用：${block.text.ifEmpty { block.meta }}"
                    literal = true
                }
                "formula" -> {
                    text = "数学公式"
                    literal = true
                }
                "code" -> literal = true
            }
            text = text.replace(Regex("""\s+"""), " ").trim()
            if (text.isEmpty()) continue
            if (segments.isNotEmpty()) {
                segments.add(LexiMarkdownInlineSpan(text = " "))
                length++
            }
            if (literal) {
                segments.add(
                    LexiMarkdownInlineSpan(
                        text = text,
                        kind = if (block.kind == "code") "code" else "text"
                    )
                )
            } else {
                segments.addAll(inlineSpans(text))
            }
            length += text.length
            if (query.trim().isEmpty() && length >= 128) break
        }
        val plain = segments.joinToString("") { it.text }
        val plainLower = plain.lowercase()
        val terms = LexiSearch.highlightTerms(query)
        var match = -1
        var matchLength = 0
        for (term in terms) {
            val idx = plainLower.indexOf(term)
            if (idx >= 0 && (match < 0 || idx < match)) {
                match = idx
                matchLength = term.length
            }
        }
        val start = if (match >= 0) max(0, match - 18) else 0
        val end = min(plain.length, if (match >= 0) match + matchLength + 42 else 86)
        val sliced = mutableListOf<LexiMarkdownInlineSpan>()
        if (start > 0) {
            sliced.add(LexiMarkdownInlineSpan(text = "…"))
        }
        var offset = 0
        for (span in segments) {
            val spanEnd = offset + span.text.length
            if (spanEnd > start && offset < end) {
                val sub = span.copy(
                    text = span.text.substring(max(0, start - offset), min(span.text.length, end - offset))
                )
                sliced.add(sub)
            }
            offset = spanEnd
            if (offset >= end) break
        }
        if (end < plain.length) {
            sliced.add(LexiMarkdownInlineSpan(text = "…"))
        }
        val preview = mutableListOf<LexiMarkdownInlineSpan>()
        if (terms.isNotEmpty() && sliced.isNotEmpty()) {
            for (span in sliced) {
                val parts = LexiSearch.highlightSegments(span.text, query)
                for (part in parts) {
                    preview.add(
                        LexiMarkdownInlineSpan(
                            text = part.text,
                            kind = span.kind,
                            target = span.target,
                            searchMatch = part.hit
                        )
                    )
                }
            }
        } else {
            preview.addAll(sliced)
        }
        if (preview.isEmpty()) {
            preview.add(LexiMarkdownInlineSpan(text = "点击继续记录内容…"))
        }
        preview.forEachIndexed { index, span ->
            span.id = "preview-$index-${span.kind}-${if (span.searchMatch) "1" else "0"}-${span.text}"
        }
        return preview
    }

    fun extractSnippet(note: NoteItem, query: String = ""): String {
        return previewSpans(note, query).joinToString("") { it.text }
    }

    fun linkTargetPreview(
        rawTarget: String,
        notes: List<NoteItem>,
        links: List<NoteLink> = emptyList(),
        vaultId: String = ""
    ): LexiLinkTargetPreview {
        val preview = LexiLinkTargetPreview()
        val cleaned = rawTarget.trim()
        val hashIdx = cleaned.indexOf('#')
        val targetName = (if (hashIdx >= 0) cleaned.substring(0, hashIdx) else cleaned)
            .replace(Regex("""\.md$""", RegexOption.IGNORE_CASE), "")
            .trim()
        val anchor = if (hashIdx >= 0) cleaned.substring(hashIdx + 1).trim() else ""
        preview.targetName = targetName
        preview.anchor = anchor
        if (targetName.isEmpty()) return preview
        val lower = targetName.lowercase()
        val active = notes.filter { it.trashedAt == 0L }
        val scoped = if (vaultId.isNotEmpty()) active.filter { it.vaultId == vaultId } else active
        val matchIn = { pool: List<NoteItem> ->
            pool.find { n ->
                n.id == targetName ||
                    n.title.trim().lowercase() == lower ||
                    displayTitle(n).lowercase() == lower
            }
        }
        val found = matchIn(scoped) ?: matchIn(active)
        if (found == null) {
            preview.title = targetName
            preview.snippet = "目标笔记尚未创建，点击可新建并打开。"
            return preview
        }
        preview.exists = true
        preview.noteId = found.id
        preview.title = displayTitle(found)
        preview.notebook = found.notebook.ifEmpty { "笔记" }
        preview.tags = found.tags.take(4).toMutableList()
        preview.updatedAt = found.updatedAt
        preview.lastOpenedAt = found.lastOpenedAt
        val allLinks = links.ifEmpty { buildNoteLinks(active) }
        preview.outgoingCount = allLinks.count { it.sourceId == found.id }
        preview.backlinkCount = allLinks.count { it.targetId == found.id }
        if (anchor.isNotEmpty()) {
            val section = extractEmbeddedSection(found.content, anchor)
            preview.snippet = if (section.isNotEmpty()) section.take(220) else extractSnippet(found)
        } else {
            val fullPlain = parseBlocks(found.content)
                .filter { it.kind != "hr" }
                .map { it.text.replace(Regex("""\s+"""), " ").trim() }
                .filter { it.isNotEmpty() }
                .joinToString(" · ")
            preview.snippet = when {
                fullPlain.isEmpty() -> "这篇笔记还没有正文内容。"
                fullPlain.length > 180 -> fullPlain.take(180) + "…"
                else -> fullPlain
            }
        }
        return preview
    }

    private val headingLineRegex = Regex("""^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$""")
    private val fenceTrimRegex = Regex("""^(`{3,}|~{3,})""")

    fun extractOutline(markdown: String): List<OutlineHeading> {
        val headings = mutableListOf<OutlineHeading>()
        val lines = markdown.split("\n")
        val firstBodyLine = LexiFrontmatter.parse(markdown).bodyLineOffset
        var fence = ""
        for (i in firstBodyLine until lines.size) {
            val line = lines[i].trim()
            if (fence.isNotEmpty()) {
                if (Regex("""^${fence[0]}{${fence.length},}\s*$""").matches(line)) {
                    fence = ""
                }
                continue
            }
            val fenceMatch = fenceTrimRegex.find(line)
            if (fenceMatch != null) {
                fence = fenceMatch.groupValues[1]
                continue
            }
            val match = headingLineRegex.matchEntire(line)
            if (match != null) {
                headings.add(
                    OutlineHeading(
                        id = "h-$i",
                        level = match.groupValues[1].length,
                        title = match.groupValues[2].trim(),
                        lineIndex = i
                    )
                )
            }
        }
        return headings
    }

    private val fenceOpenWithLangRegex = Regex("""^(`{3,}|~{3,})(.*)$""")
    private val orderedLineRegex = Regex("""^(\d{1,9})[.)]\s+(.+)$""")
    private val imageLineRegex = Regex("""^!\[([^\]]*)\]\((<[^>]+>|[^)]+?)(?:\s+"[^"]*")?\)$""")
    private val embedLineRegex = Regex("""^!\[\[([^\[\]]+)\]\]$""")
    private val tableSepCellRegex = Regex("""^:?-{3,}:?$""")
    private val hrLineRegex = Regex("""^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$""")
    private val imageExtRegex = Regex("""\.(?:png|jpe?g|gif|webp|svg|bmp|avif)$""", RegexOption.IGNORE_CASE)
    private val todoCheckedRegex = Regex("""^[-*+]\s+\[[xX]\](?:\s|$)""")
    private val todoUncheckedRegex = Regex("""^[-*+]\s+\[ \](?:\s|$)""")
    private val calloutHeaderRegex = Regex("""^>\s*\[!([A-Za-z]+)\]""")

    fun parseBlocks(markdown: String): List<MarkdownBlock> {
        val blocks = mutableListOf<MarkdownBlock>()
        val lines = markdown.split("\n")
        var i = LexiFrontmatter.parse(markdown).bodyLineOffset
        while (i < lines.size) {
            val raw = lines[i]
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) {
                i++
                continue
            }
            val fenceOpen = fenceOpenWithLangRegex.matchEntire(trimmed)
            if (fenceOpen != null) {
                val fence = fenceOpen.groupValues[1]
                val lang = fenceOpen.groupValues[2].trim().split(Regex("""\s+""")).firstOrNull()?.ifEmpty { "code" } ?: "code"
                val codeLines = mutableListOf<String>()
                val startLine = i
                i++
                val closePattern = Regex("""^${fence[0]}{${fence.length},}\s*$""")
                while (i < lines.size && !closePattern.matches(lines[i].trim())) {
                    codeLines.add(lines[i])
                    i++
                }
                i++
                val fenceText = codeLines.joinToString("\n")
                val langLower = lang.lowercase()
                val isMathFence = langLower == "math" || langLower == "katex"
                val block = MarkdownBlock(id = "block-$startLine", lineIndex = startLine)
                if (isMathFence) {
                    block.kind = "formula"
                    block.text = fenceText.trim()
                        .replace(Regex("""^(?:\$\$|\\\[)\s*([\s\S]*?)\s*(?:\$\$|\\\])$"""), "$1")
                        .trim()
                } else {
                    block.kind = "code"
                    block.meta = lang
                    block.text = fenceText
                }
                blocks.add(block)
                continue
            }
            val formula = LexiMathSyntax.displayBlock(lines, i)
            if (formula != null) {
                val startLine = i
                i = formula.endLine + 1
                blocks.add(
                    MarkdownBlock(
                        id = "block-$startLine",
                        kind = "formula",
                        text = formula.text,
                        lineIndex = startLine
                    )
                )
                continue
            }
            val block = MarkdownBlock(id = "block-$i", lineIndex = i)
            val heading = headingLineRegex.matchEntire(trimmed)
            val ordered = orderedLineRegex.matchEntire(trimmed)
            val image = imageLineRegex.matchEntire(trimmed)
            val embed = embedLineRegex.matchEntire(trimmed)
            val separator = if (i + 1 < lines.size) splitTableRow(lines[i + 1]) else mutableListOf()
            if (trimmed.contains("|") && separator.isNotEmpty() && separator.all { tableSepCellRegex.matches(it) }) {
                val table = LexiMarkdownTable()
                val headers = splitTableRow(trimmed)
                if (headers.size == separator.size) {
                    table.rows.add(headers)
                    table.alignments = separator.map { cell ->
                        when {
                            cell.startsWith(":") && cell.endsWith(":") -> "center"
                            cell.endsWith(":") -> "right"
                            else -> "left"
                        }
                    }.toMutableList()
                    i += 2
                    while (i < lines.size && lines[i].trim().contains("|") && lines[i].trim().isNotEmpty()) {
                        val cells = splitTableRow(lines[i])
                        while (cells.size < headers.size) cells.add("")
                        table.rows.add(cells.take(headers.size).toMutableList())
                        i++
                    }
                    block.kind = "table"
                    block.text = headers.joinToString(" | ")
                    block.meta = encodeTableData(table)
                    blocks.add(block)
                    continue
                }
            }
            when {
                heading != null -> {
                    block.kind = "h${min(3, heading.groupValues[1].length)}"
                    block.meta = heading.groupValues[1].length.toString()
                    block.text = heading.groupValues[2].trim()
                }
                hrLineRegex.matches(trimmed) -> {
                    block.kind = "hr"
                }
                image != null -> {
                    block.kind = "image"
                    block.text = image.groupValues[1]
                    block.meta = image.groupValues[2]
                }
                embed != null -> {
                    val rawInner = embed.groupValues[1]
                    val targetPart = rawInner.split("|")[0].trim()
                    block.kind = if (imageExtRegex.containsMatchIn(targetPart)) "image" else "embed"
                    block.meta = targetPart
                    block.text = rawInner.split("|").drop(1).joinToString("|").trim().ifEmpty { block.meta }
                }
                ordered != null -> {
                    block.kind = "ordered"
                    block.meta = ordered.groupValues[1]
                    block.text = ordered.groupValues[2]
                }
                todoCheckedRegex.containsMatchIn(trimmed) -> {
                    block.kind = "todo"
                    block.checked = true
                    block.text = trimmed.replaceFirst(Regex("""^[-*+]\s+\[[xX]\]\s*"""), "")
                }
                todoUncheckedRegex.containsMatchIn(trimmed) -> {
                    block.kind = "todo"
                    block.checked = false
                    block.text = trimmed.replaceFirst(Regex("""^[-*+]\s+\[ \]\s*"""), "")
                }
                trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ") -> {
                    block.kind = "bullet"
                    block.text = trimmed.substring(2).trim()
                }
                trimmed.startsWith("> [!") -> {
                    block.kind = "callout"
                    val calloutMatch = calloutHeaderRegex.find(trimmed)
                    block.meta = calloutMatch?.groupValues?.get(1) ?: "NOTE"
                    val bodyLines = mutableListOf(trimmed.replaceFirst(Regex("""^>\s*\[![A-Za-z]+\]\s*"""), ""))
                    while (i + 1 < lines.size && lines[i + 1].trim().startsWith(">")) {
                        i++
                        bodyLines.add(lines[i].trim().replaceFirst(Regex("""^>\s?"""), ""))
                    }
                    block.text = bodyLines.filter { it.isNotEmpty() }.joinToString("\n")
                }
                trimmed == ">" || trimmed.startsWith("> ") -> {
                    block.kind = "quote"
                    val quoteLines = mutableListOf(trimmed.replaceFirst(Regex("""^>\s?"""), ""))
                    while (i + 1 < lines.size &&
                        (lines[i + 1].trim() == ">" || lines[i + 1].trim().startsWith("> ")) &&
                        !lines[i + 1].trim().startsWith("> [!")
                    ) {
                        i++
                        quoteLines.add(lines[i].trim().replaceFirst(Regex("""^>\s?"""), ""))
                    }
                    block.text = quoteLines.filter { it.isNotEmpty() }.joinToString("\n")
                }
                else -> {
                    block.kind = "paragraph"
                    block.text = trimmed
                }
            }
            blocks.add(block)
            i++
        }
        return blocks
    }

    fun computeMindMapLayout(doc: MindMapDoc): List<MindMapNode> {
        val nodes = doc.nodes
        val root = nodes.find { it.id == doc.rootNodeId } ?: nodes.firstOrNull() ?: return emptyList()
        val visible = mutableListOf<MindMapNode>()
        val childrenOf = { parentId: String ->
            nodes.filter { it.parentId == parentId }.sortedBy { it.order }
        }
        fun measureLeaves(node: MindMapNode): Int {
            if (node.collapsed) return 1
            val ch = childrenOf(node.id)
            if (ch.isEmpty()) return 1
            var sum = 0
            for (c in ch) {
                sum += measureLeaves(c)
            }
            return max(1, sum)
        }

        if (doc.layoutKind == "org") {
            val hStep = 166.0
            val vStep = 92.0
            fun placeOrg(node: MindMapNode, level: Int, startLeaf: Int): Int {
                val span = measureLeaves(node)
                node.level = level
                node.boxWidth = min(184.0, max(116.0, node.text.length * 14.0 + 34.0))
                node.boxHeight = if (node.note.isNotEmpty() || node.noteRefId.isNotEmpty()) 54.0 else 42.0
                node.x = (80.0 + (startLeaf + span / 2.0) * hStep).toFloat()
                node.y = (76.0 + level * vStep).toFloat()
                visible.add(node)
                if (!node.collapsed) {
                    val ch = childrenOf(node.id)
                    var cursor = startLeaf
                    for (c in ch) {
                        cursor += placeOrg(c, level + 1, cursor)
                    }
                }
                return span
            }
            placeOrg(root, 0, 0)
            applyMindMapOffsets(visible)
            return visible
        }

        if (doc.layoutKind == "balanced") {
            val topChildren = childrenOf(root.id)
            val rightGroup = mutableListOf<MindMapNode>()
            val leftGroup = mutableListOf<MindMapNode>()
            for (i in topChildren.indices) {
                if (i % 2 == 0) rightGroup.add(topChildren[i]) else leftGroup.add(topChildren[i])
            }
            val vGap = 68.0
            val hGap = 205.0
            var rightLeaves = 0
            for (c in rightGroup) rightLeaves += measureLeaves(c)
            var leftLeaves = 0
            for (c in leftGroup) leftLeaves += measureLeaves(c)
            val totalLeaves = max(3, max(rightLeaves, leftLeaves))
            val centerY = max(210.0, (totalLeaves * vGap) / 2.0 + 48.0)
            val centerX = 480.0

            root.level = 0
            root.boxWidth = min(196.0, max(132.0, root.text.length * 15.0 + 36.0))
            root.boxHeight = 48.0
            root.x = centerX.toFloat()
            root.y = centerY.toFloat()
            visible.add(root)

            if (!root.collapsed) {
                fun placeSide(node: MindMapNode, level: Int, startLeaf: Int, dir: Int, baseTop: Double): Int {
                    val span = measureLeaves(node)
                    node.level = level
                    node.boxWidth = min(184.0, max(114.0, node.text.length * 13.0 + 34.0))
                    node.boxHeight = if (node.note.isNotEmpty() || node.noteRefId.isNotEmpty()) 52.0 else 42.0
                    node.x = (centerX + dir * level * hGap).toFloat()
                    node.y = (baseTop + (startLeaf + span / 2.0) * vGap).toFloat()
                    visible.add(node)
                    if (!node.collapsed) {
                        val ch = childrenOf(node.id)
                        var cursor = startLeaf
                        for (c in ch) {
                            cursor += placeSide(c, level + 1, cursor, dir, baseTop)
                        }
                    }
                    return span
                }

                val rightTop = centerY - (max(1, rightLeaves) * vGap) / 2.0
                var rCursor = 0
                for (c in rightGroup) {
                    rCursor += placeSide(c, 1, rCursor, 1, rightTop)
                }

                val leftTop = centerY - (max(1, leftLeaves) * vGap) / 2.0
                var lCursor = 0
                for (c in leftGroup) {
                    lCursor += placeSide(c, 1, lCursor, -1, leftTop)
                }
            }
            applyMindMapOffsets(visible)
            return visible
        }

        val vGap = 68.0
        val hGap = 206.0
        fun placeRight(node: MindMapNode, level: Int, startLeaf: Int): Int {
            val span = measureLeaves(node)
            node.level = level
            node.boxWidth = min(192.0, max(118.0, node.text.length * 14.0 + 34.0))
            node.boxHeight = if (node.note.isNotEmpty() || node.noteRefId.isNotEmpty()) 52.0 else 42.0
            node.x = (124.0 + level * hGap).toFloat()
            node.y = (64.0 + (startLeaf + span / 2.0) * vGap).toFloat()
            visible.add(node)
            if (!node.collapsed) {
                val ch = childrenOf(node.id)
                var cursor = startLeaf
                for (c in ch) {
                    cursor += placeRight(c, level + 1, cursor)
                }
            }
            return span
        }
        placeRight(root, 0, 0)
        applyMindMapOffsets(visible)
        return visible
    }

    private fun applyMindMapOffsets(nodes: List<MindMapNode>) {
        for (node in nodes) {
            node.x += (if (node.offsetX.isFinite()) node.offsetX else 0.0).toFloat()
            node.y += (if (node.offsetY.isFinite()) node.offsetY else 0.0).toFloat()
        }
    }

    fun mindMapToMarkdownOutline(doc: MindMapDoc): String {
        val lines = mutableListOf("# ${doc.title}")
        val childrenOf = { parentId: String ->
            doc.nodes.filter { it.parentId == parentId }.sortedBy { it.order }
        }
        fun walk(node: MindMapNode, depth: Int) {
            if (depth > 0) {
                val indent = "  ".repeat(max(0, depth - 1))
                val linkSuffix = if (node.noteRefTitle.isNotEmpty()) " → [[${node.noteRefTitle}]]" else ""
                val noteSuffix = if (node.note.isNotEmpty()) " （${node.note}）" else ""
                lines.add("$indent- ${node.text}$linkSuffix$noteSuffix")
            }
            for (c in childrenOf(node.id)) {
                walk(c, depth + 1)
            }
        }
        val root = doc.nodes.find { it.id == doc.rootNodeId } ?: doc.nodes.firstOrNull()
        if (root != null) {
            walk(root, 0)
        }
        return lines.joinToString("\n")
    }

    fun markdownToMindMapNodes(title: String, markdown: String, noteId: String = ""): MutableList<MindMapNode> {
        val nodes = mutableListOf<MindMapNode>()
        val root = MindMapNode(
            id = "root",
            parentId = "",
            text = title.trim().ifEmpty { "核心主题" },
            noteRefId = noteId,
            noteRefTitle = title.trim(),
            colorTag = "purple",
            order = 0
        )
        nodes.add(root)

        val lines = markdown.split("\n")
        var lastH1Id = "root"
        var lastH2Id = "root"
        var orderCounter = 1
        val colors = listOf("purple", "indigo", "teal", "amber", "rose")

        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("```")) continue
            when {
                trimmed.startsWith("# ") -> {
                    val node = MindMapNode(
                        id = "node-$orderCounter",
                        parentId = "root",
                        text = trimmed.substring(2).trim().take(32),
                        order = orderCounter,
                        colorTag = colors[orderCounter % colors.size]
                    )
                    nodes.add(node)
                    lastH1Id = node.id
                    lastH2Id = node.id
                    orderCounter++
                }
                trimmed.startsWith("## ") -> {
                    val node = MindMapNode(
                        id = "node-$orderCounter",
                        parentId = lastH1Id,
                        text = trimmed.substring(3).trim().take(32),
                        order = orderCounter,
                        colorTag = colors[orderCounter % colors.size]
                    )
                    nodes.add(node)
                    lastH2Id = node.id
                    orderCounter++
                }
                trimmed.startsWith("### ") || trimmed.startsWith("- ") -> {
                    val text = if (trimmed.startsWith("### ")) trimmed.substring(4).trim() else trimmed.substring(2).trim()
                    if (text.isNotEmpty() && nodes.size < 48) {
                        val node = MindMapNode(
                            id = "node-$orderCounter",
                            parentId = lastH2Id,
                            text = text.replaceFirst(Regex("""^\[[ xX]\]\s*"""), "").take(32),
                            order = orderCounter,
                            colorTag = colors[orderCounter % colors.size]
                        )
                        nodes.add(node)
                        orderCounter++
                    }
                }
            }
        }

        if (nodes.size == 1) {
            val branches = listOf("核心要点", "关联知识", "行动清单")
            for (i in branches.indices) {
                nodes.add(
                    MindMapNode(
                        id = "node-${i + 1}",
                        parentId = "root",
                        text = branches[i],
                        order = i + 1,
                        colorTag = colors[i % colors.size]
                    )
                )
            }
        }
        return nodes
    }
}
