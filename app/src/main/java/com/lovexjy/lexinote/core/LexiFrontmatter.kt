package com.lovexjy.lexinote.core

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

data class LexiFrontmatterResult(
    var hasFrontmatter: Boolean = false,
    var body: String = "",
    var bodyLineOffset: Int = 0,
    var tags: MutableList<String> = mutableListOf(),
    var properties: MutableList<NoteProperty> = mutableListOf(),
    var rawHeader: String = "",
    var id: String = "",
    var title: String = "",
    var notebook: String = "",
    var noteType: String = "",
    var editorLevel: String = "",
    var pinned: Boolean? = null,
    var favorite: Boolean? = null,
    var createdAt: Long = 0L,
    var updatedAt: Long = 0L,
    var trashedAt: Long = 0L
)

private class LexiYamlField(
    var key: String = "",
    var text: String = "",
    var parsed: String = "",
    var supported: Boolean = false
)

/**
 * A deliberately bounded YAML reader: scalars and flat lists are editable;
 * nested/custom YAML is retained verbatim rather than evaluated or discarded.
 * Exact 1:1 port of LexiFrontmatter.ets.
 */
object LexiFrontmatter {
    private fun jsonQuote(value: String): String {
        return JSONObject.quote(value)
    }

    private fun scalar(raw: String): String {
        var text = raw.trim()
        var quote = '\u0000'
        for (index in text.indices) {
            val ch = text[index]
            if ((ch == '"' || ch == '\'') && (index == 0 || text[index - 1] != '\\')) {
                if (quote == '\u0000') {
                    quote = ch
                } else if (quote == ch) {
                    quote = '\u0000'
                }
            }
            if (ch == '#' && quote == '\u0000' && (index == 0 || text[index - 1].isWhitespace())) {
                text = text.substring(0, index).trim()
                break
            }
        }
        if (text.startsWith("\"") && text.endsWith("\"") && text.length >= 2) {
            return try {
                JSONArray("[$text]").getString(0)
            } catch (_: Exception) {
                text
            }
        }
        if (text.startsWith("'") && text.endsWith("'") && text.length >= 2) {
            return text.substring(1, text.length - 1).replace("''", "'")
        }
        return if (text == "null" || text == "~") "" else text
    }

    private val fieldLineRegex = Regex("""^("(?:[^"\\]|\\.)+"|'(?:[^']|'')+'|[^\s:#][^:]*):(?:\s+(.*)|\s*)$""")
    private val unsupportedScalarRegex = Regex("""^[>|{&*!]""")
    private val listRowRegex = Regex("""^\s+-\s+""")

    private fun fields(header: String): List<LexiYamlField> {
        val result = mutableListOf<LexiYamlField>()
        if (header.isEmpty()) return result
        for (line in header.split("\n")) {
            val matched = fieldLineRegex.matchEntire(line)
            if (matched == null) {
                if (result.isNotEmpty()) {
                    result[result.size - 1].text += "\n$line"
                } else {
                    result.add(LexiYamlField(text = line))
                }
                continue
            }
            val field = LexiYamlField()
            field.key = scalar(matched.groupValues[1])
            field.text = line
            val rawScalar = matched.groupValues[2]
            field.supported = !unsupportedScalarRegex.containsMatchIn(rawScalar.trim())
            field.parsed = scalar(rawScalar)
            result.add(field)
        }
        for (field in result) {
            val rows = field.text.split("\n").drop(1).filter { it.trim().isNotEmpty() && !it.trim().startsWith("#") }
            if (rows.isNotEmpty()) {
                if (rows.all { listRowRegex.containsMatchIn(it) }) {
                    val arr = JSONArray()
                    for (row in rows) {
                        arr.put(scalar(row.replaceFirst(listRowRegex, "")))
                    }
                    field.parsed = arr.toString()
                    field.supported = true
                } else {
                    field.supported = false
                }
            }
        }
        return result
    }

    private fun list(raw: String): List<String> {
        val text = raw.trim()
        if (text.startsWith("[") && text.endsWith("]")) {
            val items = mutableListOf<String>()
            val part = StringBuilder()
            var quote = '\u0000'
            for (i in 1 until text.length - 1) {
                val ch = text[i]
                if ((ch == '"' || ch == '\'') && (i == 0 || text[i - 1] != '\\')) {
                    if (quote == '\u0000') {
                        quote = ch
                    } else if (quote == ch) {
                        quote = '\u0000'
                    }
                }
                if (ch == ',' && quote == '\u0000') {
                    items.add(scalar(part.toString()))
                    part.setLength(0)
                } else {
                    part.append(ch)
                }
            }
            if (part.toString().trim().isNotEmpty()) {
                items.add(scalar(part.toString()))
            }
            return items
        }
        return if (text.isNotEmpty()) listOf(scalar(text)) else emptyList()
    }

    private fun parseDateMs(raw: String): Long {
        val clean = raw.trim()
        if (clean.isEmpty()) return 0L
        val asNum = clean.toDoubleOrNull()
        if (asNum != null && asNum.isFinite() && asNum > 0) {
            return if (asNum < 1e11) (asNum * 1000.0).toLong() else asNum.toLong()
        }
        return try {
            Instant.parse(clean).toEpochMilli()
        } catch (_: Exception) {
            try {
                LocalDate.parse(clean).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            } catch (_: Exception) {
                0L
            }
        }
    }

    private fun parsePropertyPairs(header: String): List<NoteProperty> {
        val pairs = mutableListOf<NoteProperty>()
        val lines = header.split("\n")
        var inProps = false
        var pendingKey = ""
        var hasPending = false
        for (line in lines) {
            if (!inProps) {
                if (Regex("""^properties:\s*$""").matches(line.trim())) {
                    inProps = true
                }
                continue
            }
            if (line.startsWith("  - key:")) {
                pendingKey = scalar(line.substring("  - key:".length))
                hasPending = true
                continue
            }
            if (line.startsWith("    value:") && hasPending) {
                pairs.add(NoteProperty(pendingKey, scalar(line.substring("    value:".length))))
                hasPending = false
                continue
            }
            if (line.trim().isNotEmpty() && !line[0].isWhitespace()) {
                break
            }
        }
        return pairs
    }

    fun parse(raw: String): LexiFrontmatterResult {
        val result = LexiFrontmatterResult(body = raw)
        val normalized = raw.removePrefix("\uFEFF").replace("\r\n", "\n")
        if (!normalized.startsWith("---\n")) {
            return result
        }
        val lines = normalized.split("\n")
        var end = -1
        for (i in 1 until lines.size) {
            if (lines[i] == "---" || lines[i] == "...") {
                end = i
                break
            }
        }
        if (end < 0) {
            return result
        }
        result.hasFrontmatter = true
        result.bodyLineOffset = end + 1
        result.rawHeader = lines.subList(1, end).joinToString("\n")
        result.body = lines.subList(end + 1, lines.size).joinToString("\n")
        result.properties.addAll(parsePropertyPairs(result.rawHeader))
        for (field in fields(result.rawHeader)) {
            val lower = field.key.lowercase()
            when {
                lower == "tags" || lower == "tag" -> {
                    for (tag in list(field.parsed)) {
                        val cleaned = tag.removePrefix("#").trim()
                        if (cleaned.isNotEmpty() && !result.tags.contains(cleaned)) {
                            result.tags.add(cleaned)
                        }
                    }
                }
                lower == "id" && field.parsed.isNotEmpty() -> result.id = field.parsed
                lower == "title" && field.parsed.isNotEmpty() -> result.title = field.parsed
                lower == "notebook" && field.parsed.isNotEmpty() -> result.notebook = field.parsed
                lower == "type" && field.parsed.isNotEmpty() -> result.noteType = field.parsed
                lower == "level" && field.parsed.isNotEmpty() -> result.editorLevel = field.parsed
                lower == "pinned" && field.parsed.isNotEmpty() -> result.pinned = field.parsed.lowercase() == "true"
                lower == "favorite" && field.parsed.isNotEmpty() -> result.favorite = field.parsed.lowercase() == "true"
                lower == "created" && field.parsed.isNotEmpty() -> result.createdAt = parseDateMs(field.parsed)
                lower == "updated" && field.parsed.isNotEmpty() -> result.updatedAt = parseDateMs(field.parsed)
                lower == "trashed" && field.parsed.isNotEmpty() -> result.trashedAt = parseDateMs(field.parsed)
                lower == "properties" -> { /* handled by parsePropertyPairs */ }
                field.key.isNotEmpty() && field.supported -> {
                    result.properties.add(NoteProperty(field.key, field.parsed))
                }
            }
        }
        return result
    }

    fun apply(note: NoteItem, raw: String) {
        note.content = raw
        val parsed = parse(raw)
        if (parsed.hasFrontmatter) {
            if (parsed.id.isNotEmpty()) note.id = parsed.id
            if (parsed.title.isNotEmpty()) note.title = parsed.title
            if (parsed.notebook.isNotEmpty()) note.notebook = parsed.notebook
            if (parsed.noteType in listOf("quick", "study", "markdown")) {
                note.noteType = parsed.noteType
            }
            if (parsed.editorLevel in listOf("simple", "study", "pro")) {
                note.editorLevel = parsed.editorLevel
            }
            parsed.pinned?.let { note.pinned = it }
            parsed.favorite?.let { note.favorite = it }
            if (parsed.createdAt > 0L) note.createdAt = parsed.createdAt
            if (parsed.updatedAt > 0L) note.updatedAt = parsed.updatedAt
            if (parsed.trashedAt > 0L) note.trashedAt = parsed.trashedAt
            note.tags = parsed.tags.toMutableList()
            note.properties = parsed.properties.toMutableList()
        }
    }

    fun serializeFull(note: NoteItem): String {
        val parsed = parse(note.content)
        val now = System.currentTimeMillis()
        val iso = { ms: Long ->
            Instant.ofEpochMilli(if (ms > 0L) ms else now).toString()
        }
        val tags = note.tags.filter { it.trim().isNotEmpty() }.map { it.removePrefix("#").trim() }
        val systemKeys = setOf(
            "id", "title", "notebook", "type", "level", "pinned", "favorite",
            "tags", "tag", "created", "updated", "trashed", "properties"
        )
        val lines = mutableListOf(
            "---",
            "id: ${jsonQuote(note.id)}",
            "title: ${jsonQuote(note.title.ifEmpty { "未命名笔记" })}",
            "notebook: ${jsonQuote(note.notebook.ifEmpty { "默认" })}",
            "type: ${note.noteType.ifEmpty { "markdown" }}",
            "level: ${note.editorLevel.ifEmpty { "pro" }}",
            "pinned: ${if (note.pinned) "true" else "false"}",
            "favorite: ${if (note.favorite) "true" else "false"}",
            "tags: [${tags.joinToString(", ") { jsonQuote(it) }}]",
            "created: ${iso(note.createdAt)}",
            "updated: ${iso(note.updatedAt)}"
        )
        if (note.trashedAt > 0L) {
            lines.add("trashed: ${iso(note.trashedAt)}")
        }
        for (field in fields(parsed.rawHeader)) {
            if (field.key.isEmpty() || !field.supported) {
                if (field.text.trim().isNotEmpty() && !systemKeys.contains(field.key.lowercase())) {
                    lines.add(field.text)
                }
            }
        }
        val customProps = note.properties.filter { it.key.trim().isNotEmpty() && !systemKeys.contains(it.key.lowercase()) }
        if (customProps.isNotEmpty()) {
            lines.add("properties:")
            for (prop in customProps) {
                lines.add("  - key: ${jsonQuote(prop.key)}")
                lines.add("    value: ${jsonQuote(prop.propValue)}")
            }
        }
        lines.add("---")
        lines.add("")
        lines.add(parsed.body.replaceFirst(Regex("^\n+"), ""))
        return lines.joinToString("\n")
    }

    fun serialize(note: NoteItem): String {
        val parsed = parse(note.content)
        if (!parsed.hasFrontmatter && note.tags.isEmpty() && note.properties.isEmpty()) {
            return note.content
        }
        val output = mutableListOf<String>()
        val used = mutableListOf<String>()
        val tags = note.tags.filter { it.trim().isNotEmpty() }.map { it.removePrefix("#").trim() }
        val tagsJson = JSONArray(tags).toString()
        for (field in fields(parsed.rawHeader)) {
            if (field.key == "tag" || field.key == "tags") {
                if (!used.contains("tags")) {
                    output.add("tags: $tagsJson")
                    used.add("tags")
                }
            } else if (field.key.isEmpty() || !field.supported) {
                if (field.text.trim().isNotEmpty()) {
                    output.add(field.text)
                }
                if (field.key.isNotEmpty()) {
                    used.add(field.key)
                }
            } else {
                val prop = note.properties.find { it.key == field.key }
                if (prop != null) {
                    output.add(if (prop.propValue == field.parsed) field.text else "${jsonQuote(prop.key)}: ${jsonQuote(prop.propValue)}")
                    used.add(prop.key)
                }
            }
        }
        if (tags.isNotEmpty() && !used.contains("tags")) {
            output.add("tags: $tagsJson")
        }
        for (prop in note.properties) {
            if (prop.key.trim().isNotEmpty() && prop.key != "tag" && prop.key != "tags" && !used.contains(prop.key)) {
                output.add("${jsonQuote(prop.key)}: ${jsonQuote(prop.propValue)}")
                used.add(prop.key)
            }
        }
        return "---\n${output.joinToString("\n")}\n---\n${parsed.body}"
    }
}
