package com.lovexjy.lexinote.core

import java.text.Collator
import java.util.Locale

data class LexiSearchTerm(
    var field: String = "",
    var text: String = "",
    var excluded: Boolean = false
)

/**
 * Shared search grammar for the library, desktop tree and quick switcher.
 * Exact 1:1 port of LexiSearch.ets.
 */
object LexiSearch {
    private val tokenRegex = Regex("""(?:[^\s"']+|"[^"]*"|'[^']*')+""")
    private val bracketFieldRegex = Regex("""^\[[^\]]+\]$""")
    private val quoteStripRegex = Regex("""^["']|["']$""")
    private val headingPrefixStripRegex = Regex("""^[#>*\-\s]+""")

    fun parse(query: String): List<LexiSearchTerm> {
        val tokens = tokenRegex.findAll(query).map { it.value }.toList()
        val result = mutableListOf<LexiSearchTerm>()
        for (token in tokens) {
            val term = LexiSearchTerm()
            var text = token
            if (text.startsWith("-") && text.length > 1) {
                term.excluded = true
                text = text.substring(1)
            }
            val colon = text.indexOf(':')
            if (colon > 0) {
                val field = text.substring(0, colon).lowercase()
                if (field in listOf("tag", "type", "notebook", "path") || bracketFieldRegex.matches(field)) {
                    term.field = field
                    text = text.substring(colon + 1)
                }
            }
            term.text = text.replace(quoteStripRegex, "").lowercase()
            if (term.text.isNotEmpty()) {
                result.add(term)
            }
        }
        return result
    }

    fun matches(note: NoteItem, query: String): Boolean {
        val haystack = "${note.title}\n${note.content}\n${note.notebook}\n${note.tags.joinToString(" ")}".lowercase()
        for (term in parse(query)) {
            val found = when {
                term.field == "tag" -> {
                    val tag = term.text.removePrefix("#")
                    note.tags.any { item ->
                        val lower = item.lowercase()
                        lower == tag || lower.startsWith("$tag/")
                    }
                }
                term.field == "type" -> note.noteType.lowercase() == term.text
                term.field == "notebook" -> note.notebook.lowercase().contains(term.text)
                term.field == "path" -> note.path.lowercase().contains(term.text)
                term.field.startsWith("[") -> {
                    val key = term.field.substring(1, term.field.length - 1)
                    note.properties.any { prop ->
                        prop.key.lowercase() == key && prop.propValue.lowercase().contains(term.text)
                    }
                }
                else -> haystack.contains(term.text)
            }
            if (if (term.excluded) found else !found) {
                return false
            }
        }
        return true
    }

    /** Lower is better; a subsequence also accepts initials typed in order. */
    fun rank(title: String, query: String): Int {
        val needle = query.trim().lowercase()
        val text = title.lowercase()
        if (needle.isEmpty()) return 0
        if (text == needle) return 0
        val offset = text.indexOf(needle)
        if (offset >= 0) return 1 + offset
        var cursor = 0
        var gaps = 0
        for (i in needle.indices) {
            val next = text.indexOf(needle[i], cursor)
            if (next < 0) return -1
            gaps += next - cursor
            cursor = next + 1
        }
        return 100 + gaps
    }

    fun highlightTerms(query: String): List<String> {
        val terms = mutableListOf<String>()
        for (term in parse(query)) {
            if (term.excluded || term.field == "type") continue
            val raw = term.text.removePrefix("#")
            val clean = raw.trim().lowercase()
            if (clean.isNotEmpty() && !terms.contains(clean)) {
                terms.add(clean)
            }
        }
        terms.sortByDescending { it.length }
        return terms
    }

    fun highlightSegments(text: String, query: String): List<LexiHighlightSpan> {
        if (text.isEmpty()) return emptyList()
        val terms = highlightTerms(query)
        if (terms.isEmpty()) {
            return listOf(LexiHighlightSpan(id = "hl-0", text = text, hit = false))
        }
        val lower = text.lowercase()
        val result = mutableListOf<LexiHighlightSpan>()
        var cursor = 0
        var index = 0
        while (cursor < text.length) {
            var bestStart = -1
            var bestLength = 0
            for (term in terms) {
                val found = lower.indexOf(term, cursor)
                if (found >= 0 && (bestStart < 0 || found < bestStart || (found == bestStart && term.length > bestLength))) {
                    bestStart = found
                    bestLength = term.length
                }
            }
            if (bestStart < 0 || bestLength <= 0) {
                result.add(LexiHighlightSpan(id = "hl-${index++}", text = text.substring(cursor), hit = false))
                break
            }
            if (bestStart > cursor) {
                result.add(LexiHighlightSpan(id = "hl-${index++}", text = text.substring(cursor, bestStart), hit = false))
            }
            result.add(
                LexiHighlightSpan(
                    id = "hl-${index++}",
                    text = text.substring(bestStart, bestStart + bestLength),
                    hit = true
                )
            )
            cursor = bestStart + bestLength
        }
        return result
    }

    fun sortNotes(notes: List<NoteItem>, sortMode: String): List<NoteItem> {
        val sorted = notes.toMutableList()
        when (sortMode) {
            "title" -> {
                val collator = Collator.getInstance(Locale.CHINA)
                val titleFor = { item: NoteItem ->
                    if (item.title.trim().isNotEmpty()) {
                        item.title.trim()
                    } else {
                        val first = item.content.split("\n")
                            .map { it.replace(headingPrefixStripRegex, "").trim() }
                            .firstOrNull { it.isNotEmpty() }
                        first?.take(28) ?: "未命名速记"
                    }
                }
                sorted.sortWith { a, b -> collator.compare(titleFor(a), titleFor(b)) }
            }
            "created" -> {
                sorted.sortWith { a, b -> b.createdAt.compareTo(a.createdAt) }
            }
            "accessed" -> {
                sorted.sortWith { a, b ->
                    val aAccess = a.lastOpenedAt
                    val bAccess = b.lastOpenedAt
                    when {
                        aAccess != bAccess -> bAccess.compareTo(aAccess)
                        a.pinned != b.pinned -> if (a.pinned) -1 else 1
                        else -> b.updatedAt.compareTo(a.updatedAt)
                    }
                }
            }
            else -> {
                sorted.sortWith { a, b ->
                    if (a.pinned != b.pinned) {
                        if (a.pinned) -1 else 1
                    } else {
                        b.updatedAt.compareTo(a.updatedAt)
                    }
                }
            }
        }
        return sorted
    }
}
