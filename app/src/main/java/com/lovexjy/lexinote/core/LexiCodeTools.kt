package com.lovexjy.lexinote.core

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import kotlin.math.max
import kotlin.math.min

data class LexiCodeToken(
    var id: String = "",
    var text: String = "",
    var kind: String = "text"
)

object LexiCodeHighlight {
    fun normalizeLanguage(language: String): String {
        val name = language.trim().lowercase().split(Regex("""\s+""")).firstOrNull()?.removePrefix("language-") ?: ""
        return when (name) {
            "", "code", "auto", "text", "txt", "plain", "plaintext", "none" -> ""
            "js", "jsx", "javascript", "node", "nodejs", "mjs", "cjs" -> "javascript"
            "ts", "tsx", "typescript" -> "typescript"
            "ets", "arkts" -> "arkts"
            "py", "python", "python3" -> "python"
            "sh", "bash", "zsh", "shell", "console" -> "shell"
            "c++", "cpp", "cc", "cxx", "hpp" -> "cpp"
            "c#", "cs", "csharp" -> "csharp"
            "yml", "yaml" -> "yaml"
            "htm" -> "html"
            "html", "xml", "svg" -> name
            "golang" -> "go"
            "rs" -> "rust"
            "kt" -> "kotlin"
            "rb" -> "ruby"
            else -> name
        }
    }

    fun label(language: String): String {
        val name = normalizeLanguage(language)
        if (name.isEmpty()) return "未指定语言"
        return when (name) {
            "javascript" -> "JavaScript"
            "typescript" -> "TypeScript"
            "arkts" -> "ArkTS"
            "python" -> "Python"
            "java" -> "Java"
            "shell" -> "Shell"
            "cpp" -> "C++"
            "csharp" -> "C#"
            "kotlin" -> "Kotlin"
            "swift" -> "Swift"
            "rust" -> "Rust"
            "ruby" -> "Ruby"
            "go" -> "Go"
            else -> name.uppercase()
        }
    }

    fun color(kind: String, dark: Boolean): String {
        return when (kind) {
            "keyword" -> if (dark) "#CEB5FF" else "#6532A3"
            "string" -> if (dark) "#9AD8B2" else "#176544"
            "number" -> if (dark) "#F4BC83" else "#8C3B0E"
            "comment" -> if (dark) "#AAB2C7" else "#596273"
            "function", "tag" -> if (dark) "#96CAFF" else "#1C4F91"
            "property" -> if (dark) "#F0B2CC" else "#8A3460"
            else -> if (dark) "#F5F3FB" else "#231B36"
        }
    }

    private fun keywords(language: String): String {
        return when (language) {
            "json" -> " true false null "
            "python" -> " and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield match case "
            "sql" -> " select from where insert into values update set delete create alter drop table view index join left right inner outer full on as and or not null is in exists like between group by order having limit offset distinct union all case when then else end asc desc with over partition true false count sum avg min max "
            "shell" -> " if then else elif fi for while do done in case esac function select until time coproc return break continue export local readonly declare typeset unset source alias unalias echo printf cd exit true false "
            "yaml" -> " true false null yes no on off "
            "go" -> " break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil make new "
            "rust" -> " as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while bool char f32 f64 i32 i64 u32 u64 usize "
            "ruby" -> " alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield "
            "css" -> " important inherit initial unset revert auto none solid block inline flex grid absolute relative fixed sticky hidden visible "
            "html", "xml", "svg" -> ""
            "swift" -> " actor any as async associatedtype await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil open operator override private protocol public repeat required rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while "
            "kotlin" -> " abstract actual annotation as break by catch class companion const constructor continue data delegate do dynamic else enum expect external false field file final finally for fun get if import in infix init inline inner interface internal is lateinit noinline null object open operator out override package private protected public reified return sealed set super suspend tailrec this throw true try typealias typeof val var vararg when where while "
            "javascript", "typescript", "arkts", "java", "c", "cpp", "csharp" ->
                " abstract alignas alignof as async await auto bool boolean break byte case catch char class const constexpr continue debugger declare default delete do double else enum export extends extern false final finally float for friend from function get goto if implements import in infer inline instanceof int interface keyof let long namespace native new null nullptr number of operator override package private protected public readonly record register requires return satisfies set short signed sizeof static string struct super switch synchronized template this throw throws true try type typedef typename typeof undefined union unsigned using var virtual void volatile while with yield "
            else -> ""
        }
    }

    private fun quotedEnd(source: String, start: Int, delimiter: String, multiline: Boolean): Int {
        var cursor = start + delimiter.length
        while (cursor < source.length) {
            if (source[cursor] == '\\') {
                cursor = min(source.length, cursor + 2)
                continue
            }
            if (cursor + delimiter.length <= source.length && source.substring(cursor, cursor + delimiter.length) == delimiter) {
                return cursor + delimiter.length
            }
            if (!multiline && (source[cursor] == '\n' || source[cursor] == '\r')) {
                return cursor
            }
            cursor++
        }
        return source.length
    }

    fun tokenize(source: String, language: String): List<LexiCodeToken> {
        if (source.isEmpty()) return emptyList()
        val name = normalizeLanguage(language)
        val known = setOf(
            "javascript", "typescript", "arkts", "python", "json", "sql", "java", "c", "cpp",
            "csharp", "shell", "css", "html", "xml", "svg", "yaml", "go", "rust", "ruby", "swift", "kotlin"
        ).contains(name)
        if (!known) {
            return listOf(LexiCodeToken(id = "code-0", text = source))
        }
        val tokens = mutableListOf<LexiCodeToken>()
        val cStyle = setOf("javascript", "typescript", "arkts", "java", "c", "cpp", "csharp", "go", "rust", "swift", "kotlin").contains(name)
        val hashStyle = setOf("python", "shell", "yaml", "ruby").contains(name)
        val markup = setOf("html", "xml", "svg").contains(name)
        val vocabulary = keywords(name)
        var inTag = false
        var cursor = 0
        val numberRegex = Regex("""^(?:0[xX][\da-fA-F]+|0[bB][01]+|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)(?:[nNlLfFdD])?""")
        val wordMarkupRegex = Regex("""^[${'$'}A-Za-z_][\w${'$'}-]*""")
        val wordCodeRegex = Regex("""^[${'$'}A-Za-z_][\w${'$'}]*""")

        while (cursor < source.length) {
            val start = cursor
            var kind = "text"
            val character = source[cursor]
            val next = if (cursor + 1 < source.length) source[cursor + 1] else '\u0000'
            val rest = source.substring(cursor)
            when {
                cursor >= 60000 || tokens.size >= 4000 -> cursor = source.length
                markup && rest.startsWith("<!--") -> {
                    val closing = source.indexOf("-->", cursor + 4)
                    cursor = if (closing < 0) source.length else closing + 3
                    kind = "comment"
                }
                (cStyle || name == "css" || name == "sql") && rest.startsWith("/*") -> {
                    val closing = source.indexOf("*/", cursor + 2)
                    cursor = if (closing < 0) source.length else closing + 2
                    kind = "comment"
                }
                (cStyle && rest.startsWith("//")) ||
                    (name == "sql" && rest.startsWith("--")) ||
                    (hashStyle && character == '#' && (name != "yaml" || cursor == 0 || source[cursor - 1].isWhitespace())) -> {
                    val newline = source.indexOf('\n', cursor)
                    cursor = if (newline < 0) source.length else newline
                    kind = "comment"
                }
                name == "python" && (rest.startsWith("\"\"\"") || rest.startsWith("'''")) -> {
                    cursor = quotedEnd(source, cursor, rest.substring(0, 3), true)
                    kind = "string"
                }
                character == '"' || (character == '\'' && name != "json") ||
                    (character == '`' && setOf("javascript", "typescript", "arkts", "shell", "go").contains(name)) -> {
                    cursor = quotedEnd(
                        source,
                        cursor,
                        character.toString(),
                        character == '`' || setOf("sql", "shell", "yaml", "ruby").contains(name)
                    )
                    kind = "string"
                    if (name == "json" && Regex("""^\s*:""").containsMatchIn(source.substring(cursor))) {
                        kind = "property"
                    }
                }
                markup && character == '<' && (next.isLetter() || next == '/' || next == '!' || next == '?') -> {
                    inTag = true
                    cursor++
                    kind = "punctuation"
                }
                markup && character == '>' -> {
                    inTag = false
                    cursor++
                    kind = "punctuation"
                }
                character.isDigit() || (character == '.' && next.isDigit()) -> {
                    val number = numberRegex.find(rest)
                    cursor += number?.value?.length ?: 1
                    kind = if (markup && !inTag) "text" else "number"
                }
                character == '$' || character == '_' || character.isLetter() -> {
                    val word = (if (markup || name == "css" || name == "yaml") wordMarkupRegex else wordCodeRegex).find(rest)
                    val wordText = word?.value ?: character.toString()
                    cursor += wordText.length
                    val lower = if (name == "sql" || name == "yaml") wordText.lowercase() else wordText
                    val tail = source.substring(cursor)
                    kind = when {
                        vocabulary.contains(" $lower ") -> "keyword"
                        markup && inTag -> if (Regex("""^\s*=""").containsMatchIn(tail)) "property" else "tag"
                        !markup && name != "json" && Regex("""^\s*\(""").containsMatchIn(tail) -> "function"
                        name == "yaml" && Regex("""^\s*:""").containsMatchIn(tail) -> "property"
                        else -> "text"
                    }
                }
                character.isWhitespace() -> {
                    cursor++
                    while (cursor < source.length && source[cursor].isWhitespace()) cursor++
                }
                "{}[]();:.,=+*/<>!?&|%~^-".contains(character) -> {
                    cursor++
                    kind = "punctuation"
                }
                else -> cursor++
            }
            if (cursor <= start) cursor = start + 1
            val text = source.substring(start, cursor)
            val previous = tokens.lastOrNull()
            if (previous != null && previous.kind == kind && kind == "text") {
                previous.text += text
            } else {
                tokens.add(LexiCodeToken(id = "code-$start", kind = kind, text = text))
            }
        }
        return tokens
    }
}

object LexiCodeTools {
    private const val MAX_CODE_LENGTH = 262144

    fun detect(code: String): String {
        if (code.trim().isEmpty() || code.length > MAX_CODE_LENGTH) return ""
        val raw = code.trim()
        if (Regex("""^#![^\r\n]*\bpython[\d.]*\b""").containsMatchIn(raw)) return "python"
        if (Regex("""^#![^\r\n]*\b(?:ba|z|k|da)?sh\b""").containsMatchIn(raw)) return "shell"
        if (raw.startsWith("{") || raw.startsWith("[")) {
            try {
                if (raw.startsWith("{")) JSONObject(raw) else JSONArray(raw)
                return "json"
            } catch (_: Exception) {
            }
        }
        if (Regex("""(?:^|\n)\s*@(?:Entry|Component|ComponentV2)\b""").containsMatchIn(raw) &&
            Regex("""\bstruct\s+[A-Za-z_]\w*\s*\{""").containsMatchIn(raw)
        ) {
            return "arkts"
        }
        if (Regex("""^<!doctype\s+html\b""", RegexOption.IGNORE_CASE).containsMatchIn(raw)) return "html"
        if (Regex("""^(?:SELECT\s+[\s\S]+\s+FROM\s+|INSERT\s+INTO\s+|UPDATE\s+|DELETE\s+FROM\s+|CREATE\s+TABLE\s+)""", RegexOption.IGNORE_CASE).containsMatchIn(raw)) {
            return "sql"
        }
        if (Regex("""^(?:async\s+)?def\s+[A-Za-z_]\w*\s*\(""", RegexOption.MULTILINE).containsMatchIn(raw) ||
            Regex("""^from\s+[\w.]+\s+import\s+\w""", RegexOption.MULTILINE).containsMatchIn(raw)
        ) {
            return "python"
        }
        if (Regex("""^(?:export\s+)?(?:interface|type)\s+[A-Za-z_]\w*""", RegexOption.MULTILINE).containsMatchIn(raw)) {
            return "typescript"
        }
        if (Regex("""^(?:export\s+)?(?:async\s+)?function\s+[A-Za-z_$][\w$]*\s*\(""", RegexOption.MULTILINE).containsMatchIn(raw) ||
            Regex("""^\s*console\.(?:log|warn|error|info)\s*\(""", RegexOption.MULTILINE).containsMatchIn(raw)
        ) {
            return "javascript"
        }
        return ""
    }

    fun format(code: String, lang: String): String {
        if (code.isEmpty() || code.length > MAX_CODE_LENGTH) return code
        val normalized = if (lang.trim().isEmpty() || lang.trim().lowercase() in listOf("auto", "code")) {
            detect(code)
        } else {
            LexiCodeHighlight.normalizeLanguage(lang)
        }
        if (normalized == "json") {
            return try {
                val trimmed = code.trim()
                if (trimmed.startsWith("{")) JSONObject(trimmed).toString(2)
                else if (trimmed.startsWith("[")) JSONArray(trimmed).toString(2)
                else code
            } catch (_: Exception) {
                code
            }
        }
        if (normalized.isEmpty() || normalized in listOf("html", "shell")) return code
        return code.split("\n").joinToString("\n") { it.trimEnd(' ', '\t') }
    }
}

data class LexiCodeFenceInfo(
    var raw: String = "",
    var newline: String = "\n",
    var marker: String = "```",
    var header: String = "```",
    var language: String = "",
    var extra: String = "",
    var body: String = "",
    var bodyOffset: Int = 4,
    var closing: String = "```",
    var closed: Boolean = false
)

object LexiCodeFence {
    private val headerRegex = Regex("""^(\s*)(`{3,}|~{3,})(.*)$""")

    fun parse(raw: String): LexiCodeFenceInfo {
        val result = LexiCodeFenceInfo(raw = raw)
        result.newline = if (raw.contains("\r\n")) "\r\n" else "\n"
        val lines = raw.split(result.newline)
        result.header = lines.firstOrNull() ?: "```"
        val match = headerRegex.matchEntire(result.header)
        if (match != null) {
            result.marker = match.groupValues[2]
            val info = match.groupValues[3].trim()
            val split = info.indexOfFirst { it.isWhitespace() }
            result.language = if (split < 0) info else info.substring(0, split)
            result.extra = if (split < 0) "" else info.substring(split)
        }
        result.bodyOffset = result.header.length + if (lines.size > 1) result.newline.length else 0
        val closing = if (lines.size > 1) lines.last() else ""
        val closePattern = Regex("""^\s*${result.marker[0]}{${result.marker.length},}\s*$""")
        result.closed = lines.size > 1 && closePattern.matches(closing)
        result.closing = if (result.closed) closing else ""
        val endIdx = if (result.closed) lines.size - 1 else lines.size
        result.body = if (lines.size > 1) lines.subList(1, endIdx).joinToString(result.newline) else ""
        return result
    }

    fun update(raw: String, body: String, language: String): String {
        val old = parse(raw)
        if (old.body == body && old.language == language) return raw
        val prefix = old.header.substring(0, old.header.indexOf(old.marker).coerceAtLeast(0))
        var length = old.marker.length
        val markerChar = old.marker[0]
        val linePattern = Regex("""^\s*($markerChar{3,})\s*$""")
        for (line in body.split(Regex("""\r?\n"""))) {
            val m = linePattern.matchEntire(line)
            if (m != null && m.groupValues[1].length >= length) {
                length = m.groupValues[1].length + 1
            }
        }
        val marker = markerChar.toString().repeat(length)
        val header = "$prefix$marker$language${old.extra}"
        if (!old.closed) return "$header${old.newline}$body"
        val closing = if (length == old.marker.length) {
            old.closing
        } else {
            old.closing.replaceFirst(Regex("""$markerChar{3,}"""), marker)
        }
        return "$header${old.newline}$body${old.newline}$closing"
    }
}

data class LexiLiveRange(
    var start: Int = 0,
    var end: Int = 0,
    var kind: String = "paragraph"
)

data class LexiLiveEdit(
    var content: String = "",
    var cursor: Int = 0
)

object LexiLiveMarkdown {
    fun lineOffsets(content: String): List<Int> {
        val offsets = mutableListOf(0)
        for (i in content.indices) {
            if (content[i] == '\n') offsets.add(i + 1)
        }
        return offsets
    }

    fun lineAt(content: String, offset: Int): Int {
        var line = 0
        for (i in 0 until min(offset, content.length)) {
            if (content[i] == '\n') line++
        }
        return line
    }

    fun rangeAt(content: String, offset: Int): LexiLiveRange {
        val cursor = max(0, min(content.length, offset))
        val offsets = lineOffsets(content)
        val blocks = MarkdownEngine.parseBlocks(content)
        for (index in blocks.indices) {
            val start = offsets.getOrElse(blocks[index].lineIndex) { 0 }
            var end = if (index + 1 < blocks.size) {
                offsets.getOrElse(blocks[index + 1].lineIndex) { content.length }
            } else {
                content.length
            }
            while (end > start && (content[end - 1] == '\n' || content[end - 1] == '\r')) {
                end--
            }
            if (cursor in start..end) {
                return LexiLiveRange(start = start, end = end, kind = blocks[index].kind)
            }
        }
        val start = if (cursor > 0) content.lastIndexOf('\n', cursor - 1) + 1 else 0
        val newline = content.indexOf('\n', cursor)
        var end = if (newline < 0) content.length else newline
        if (end > start && content[end - 1] == '\r') end--
        return LexiLiveRange(start = start, end = end, kind = "paragraph")
    }

    fun rangeForLine(content: String, lineIndex: Int): LexiLiveRange {
        val offsets = lineOffsets(content)
        return rangeAt(content, offsets.getOrElse(lineIndex) { content.length })
    }

    fun blocksBetween(content: String, start: Int, end: Int): List<MarkdownBlock> {
        val safeStart = max(0, min(content.length, start))
        val safeEnd = max(safeStart, min(content.length, end))
        val lineOffset = lineAt(content, safeStart)
        return MarkdownEngine.parseBlocks(content.substring(safeStart, safeEnd)).map { block ->
            val newLine = block.lineIndex + lineOffset
            block.copy(lineIndex = newLine, id = "live-block-$newLine")
        }
    }

    fun replace(content: String, start: Int, end: Int, snippet: String): LexiLiveEdit {
        val first = max(0, min(content.length, min(start, end)))
        val last = max(first, min(content.length, max(start, end)))
        return LexiLiveEdit(
            content = content.substring(0, first) + snippet + content.substring(last),
            cursor = first + snippet.length
        )
    }

    fun hasBody(content: String): Boolean {
        return MarkdownEngine.parseFrontmatter(content).body.trim().isNotEmpty()
    }
}

data class LexiDeepLinkRequest(
    var action: String = "",
    var noteId: String = "",
    var title: String = "",
    var notebook: String = ""
)

object LexiEcosystemLink {
    private val unsafeCharsRegex = Regex("""[\s\\\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]""")
    private val uriRegex = Regex("""^lexinote://([a-z0-9_-]+)(?:/([a-z0-9_-]+))?(?:\?([^#]*))?$""", RegexOption.IGNORE_CASE)

    private fun hasUnsafeChars(raw: String): Boolean {
        return raw.isEmpty() || raw.length > 4096 || unsafeCharsRegex.containsMatchIn(raw)
    }

    private fun decodeParam(raw: String): String {
        return try {
            URLDecoder.decode(raw.replace("+", "%20"), "UTF-8")
                .replace(Regex("""[\r\n\u0000-\u001f]"""), "")
                .trim()
        } catch (_: Exception) {
            ""
        }
    }

    private fun parseQuery(queryString: String): Map<String, String> {
        val map = mutableMapOf<String, String>()
        if (queryString.isEmpty()) return map
        for (pair in queryString.split("&")) {
            if (pair.isEmpty()) continue
            val eq = pair.indexOf('=')
            val key = if (eq >= 0) decodeParam(pair.substring(0, eq)) else decodeParam(pair)
            val value = if (eq >= 0) decodeParam(pair.substring(eq + 1)) else ""
            if (key.isNotEmpty()) map[key] = value
        }
        return map
    }

    fun parseLexiNoteUri(rawUri: String): LexiDeepLinkRequest? {
        if (hasUnsafeChars(rawUri)) return null
        val match = uriRegex.matchEntire(rawUri) ?: return null
        val host = match.groupValues[1].lowercase()
        val pathSeg = match.groupValues[2].lowercase()
        val query = parseQuery(match.groupValues[3])
        val routeKey = if (pathSeg.isNotEmpty()) "$host/$pathSeg" else host
        return when (routeKey) {
            "daily", "note/daily" -> LexiDeepLinkRequest(action = "daily")
            "quick", "note/quick" -> LexiDeepLinkRequest(action = "quick")
            "open", "note/open", "note" -> {
                val noteId = (query["noteId"] ?: query["id"] ?: "").take(128)
                val title = (query["title"] ?: "").take(160)
                val notebook = (query["notebook"] ?: "").take(80)
                if (noteId.isNotEmpty() && !Regex("""^[A-Za-z0-9_-]{1,128}$""").matches(noteId)) return null
                if (noteId.isEmpty() && title.isEmpty()) return null
                LexiDeepLinkRequest(action = "open", noteId = noteId, title = title, notebook = notebook)
            }
            else -> null
        }
    }

    fun isExternalDeepLink(target: String): Boolean {
        if (hasUnsafeChars(target)) return false
        if (Regex("""^(?:https?://|mailto:)""", RegexOption.IGNORE_CASE).containsMatchIn(target)) return true
        if (Regex("""^lexiglow://(?:study/(?:plan|mistakes|sentences)|word\?id=[1-9]\d{0,9}|article\?id=-?[1-9]\d{0,9})$""", RegexOption.IGNORE_CASE).matches(target)) return true
        if (Regex("""^lumikit://(?:inventory\?itemId=[A-Za-z0-9_-]{1,128}|tool\?id=[a-z0-9-]{1,64})$""", RegexOption.IGNORE_CASE).matches(target)) return true
        return false
    }
}
