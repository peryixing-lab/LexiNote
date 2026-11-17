package com.lovexjy.lexinote.core

data class LexiMathToken(
    var start: Int = 0,
    var end: Int = 0,
    var text: String = "",
    var displayMode: Boolean = false
)

data class LexiMathDisplayBlock(
    var text: String = "",
    var endLine: Int = 0
)

private val MATH_ENVIRONMENTS = setOf(
    "equation", "equation*",
    "align", "align*", "aligned",
    "alignat", "alignat*", "alignedat",
    "gather", "gather*", "gathered",
    "flalign", "flalign*",
    "multline", "multline*",
    "split",
    "cases", "cases*", "dcases", "dcases*", "rcases", "rcases*", "numcases", "subnumcases",
    "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
    "array", "subarray", "CD",
    "eqnarray", "eqnarray*"
)

/**
 * Finds math without interpreting LaTeX commands or changing the source document.
 * Exact 1:1 port of LexiMathSyntax.ets.
 */
object LexiMathSyntax {
    fun isEscaped(text: String, index: Int): Boolean {
        var slashes = 0
        var cursor = index - 1
        while (cursor >= 0 && text[cursor] == '\\') {
            slashes++
            cursor--
        }
        return slashes % 2 == 1
    }

    fun isMathEnvironment(name: String): Boolean {
        return MATH_ENVIRONMENTS.contains(name)
    }

    private fun isDisplayEnvironment(name: String): Boolean {
        return name == "equation" || name == "equation*" ||
            name == "align" || name == "align*" ||
            name == "alignat" || name == "alignat*" ||
            name == "gather" || name == "gather*" ||
            name == "flalign" || name == "flalign*" ||
            name == "multline" || name == "multline*" ||
            name == "numcases" || name == "subnumcases" ||
            name == "eqnarray" || name == "eqnarray*"
    }

    private val envOpenRegex = Regex("""^\\begin\{([A-Za-z]+\*?)\}""")

    private fun matchEnvironmentAt(text: String, index: Int): LexiMathToken? {
        if (index + 7 > text.length || text[index] != '\\' || text.substring(index, index + 7) != "\\begin{") {
            return null
        }
        val openMatch = envOpenRegex.find(text.substring(index)) ?: return null
        val envName = openMatch.groupValues[1]
        if (!isMathEnvironment(envName)) return null
        val openTag = "\\begin{$envName}"
        val closeTag = "\\end{$envName}"
        var depth = 1
        var cursor = index + openTag.length
        while (cursor < text.length) {
            val nextOpen = text.indexOf(openTag, cursor)
            val nextClose = text.indexOf(closeTag, cursor)
            if (nextClose < 0) return null
            if (nextOpen in 0 until nextClose) {
                depth++
                cursor = nextOpen + openTag.length
            } else {
                depth--
                cursor = nextClose + closeTag.length
                if (depth == 0) {
                    return LexiMathToken(
                        start = index,
                        end = cursor,
                        text = text.substring(index, cursor),
                        displayMode = true
                    )
                }
            }
        }
        return null
    }

    private val currencySpanRegex = Regex(
        """^[0-9]+(?:[.,][0-9]+)*\s*(?:[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef,.;:!?)—–\-]|and\b|or\b|to\b|per\b)""",
        RegexOption.IGNORE_CASE
    )
    private val mathCmdOrOpRegex = Regex("""\\[A-Za-z]|[=^_{}<>]""")
    private val symmetricMathRegex = Regex("""\\[A-Za-z]|[_^=<>+\-*/{}]""")
    private val numberProseRegex = Regex("""^[0-9]+(?:[.,][0-9]+)*\s+[A-Za-z\u4e00-\u9fff]""")

    private fun isValidDollarBody(rawBody: String, afterClose: String): Boolean {
        val trimmed = rawBody.trim()
        if (trimmed.isEmpty()) return false
        if (afterClose.isNotEmpty() && afterClose[0].isDigit()) return false
        if (currencySpanRegex.containsMatchIn(trimmed) && !mathCmdOrOpRegex.containsMatchIn(trimmed)) {
            return false
        }
        val hasLeadingSpace = rawBody.first().isWhitespace()
        val hasTrailingSpace = rawBody.last().isWhitespace()
        if (!hasLeadingSpace && !hasTrailingSpace) return true
        if (!hasLeadingSpace || !hasTrailingSpace) return false
        if (symmetricMathRegex.containsMatchIn(trimmed)) {
            return !numberProseRegex.containsMatchIn(trimmed)
        }
        return false
    }

    fun inlineTokens(text: String): List<LexiMathToken> {
        val tokens = mutableListOf<LexiMathToken>()
        var index = 0
        while (index < text.length) {
            if (isEscaped(text, index)) {
                index++
                continue
            }
            if (text[index] == '`') {
                var length = 1
                while (index + length < text.length && text[index + length] == '`') {
                    length++
                }
                val marker = "`".repeat(length)
                var closing = text.indexOf(marker, index + length)
                while (closing >= 0 && (
                        (closing > 0 && text[closing - 1] == '`') ||
                            (closing + length < text.length && text[closing + length] == '`')
                        )
                ) {
                    closing = text.indexOf(marker, closing + length)
                }
                if (closing >= 0) {
                    index = closing + length
                } else {
                    index += length
                }
                continue
            }
            if (index + 2 <= text.length && text.substring(index, index + 2) == "[[") {
                val closing = text.indexOf("]]", index + 2)
                if (closing >= 0) {
                    index = closing + 2
                    continue
                }
            }
            if (index + 2 <= text.length && text.substring(index, index + 2) == "](") {
                val closing = text.indexOf(")", index + 2)
                if (closing >= 0) {
                    index = closing + 1
                    continue
                }
            }
            if (index + 7 <= text.length && text.substring(index, index + 7) == "\\begin{") {
                val envToken = matchEnvironmentAt(text, index)
                if (envToken != null) {
                    tokens.add(envToken)
                    index = envToken.end
                    continue
                }
            }
            var opener = ""
            var closer = ""
            var display = false
            val pair = if (index + 2 <= text.length) text.substring(index, index + 2) else ""
            when {
                pair == "\\(" -> {
                    opener = pair
                    closer = "\\)"
                }
                pair == "\\[" -> {
                    opener = pair
                    closer = "\\]"
                    display = true
                }
                pair == "$$" -> {
                    opener = pair
                    closer = pair
                    display = true
                }
                text[index] == '$' && index + 1 < text.length && text[index + 1] != '\n' && text[index + 1] != '\r' -> {
                    opener = "$"
                    closer = "$"
                }
            }
            if (opener.isEmpty()) {
                index++
                continue
            }
            val bodyStart = index + opener.length
            var closing = bodyStart
            var found = false
            var braceDepth = 0
            var envDepth = 0
            while (closing < text.length) {
                val ch = text[closing]
                if (!isEscaped(text, closing)) {
                    if (ch == '{') {
                        braceDepth++
                        closing++
                        continue
                    }
                    if (ch == '}' && braceDepth > 0) {
                        braceDepth--
                        closing++
                        continue
                    }
                    if (ch == '\\' && closing + 7 <= text.length && text.substring(closing, closing + 7) == "\\begin{") {
                        envDepth++
                    } else if (ch == '\\' && closing + 5 <= text.length && text.substring(closing, closing + 5) == "\\end{" && envDepth > 0) {
                        envDepth--
                    }
                }
                if (!display && (ch == '\n' || ch == '\r') && envDepth == 0) {
                    break
                }
                val canClose = closer != "$" || (braceDepth == 0 && envDepth == 0)
                if (canClose &&
                    closing + closer.length <= text.length &&
                    text.substring(closing, closing + closer.length) == closer &&
                    (closer != "$" || !isEscaped(text, closing))
                ) {
                    val rawBody = text.substring(bodyStart, closing)
                    val afterClose = if (closing + 1 < text.length) text[closing + 1].toString() else ""
                    found = if (closer == "$") {
                        isValidDollarBody(rawBody, afterClose)
                    } else {
                        rawBody.trim().isNotEmpty()
                    }
                    break
                }
                closing++
            }
            if (found) {
                val tokenText = text.substring(bodyStart, closing).trim()
                if (!display) {
                    val envMatch = envOpenRegex.find(tokenText)
                    if (envMatch != null && isDisplayEnvironment(envMatch.groupValues[1])) {
                        display = true
                    }
                }
                val token = LexiMathToken(
                    start = index,
                    end = closing + closer.length,
                    text = tokenText,
                    displayMode = display
                )
                tokens.add(token)
                index = token.end
            } else {
                index += opener.length
            }
        }
        return tokens
    }

    fun hasMath(text: String): Boolean {
        return inlineTokens(text).isNotEmpty()
    }

    fun hasUnclosedMath(text: String): Boolean {
        val tokens = inlineTokens(text)
        val masked = StringBuilder()
        var cursor = 0
        for (token in tokens) {
            masked.append(text.substring(cursor, token.start))
            cursor = token.end
        }
        masked.append(text.substring(cursor))
        val maskedStr = masked.toString()
        if (Regex("""(?:^|[^\\])\$\$""").containsMatchIn(maskedStr) ||
            Regex("""(?:^|[^\\])\$[A-Za-z\\]""").containsMatchIn(maskedStr) ||
            Regex("""\\\[""").containsMatchIn(maskedStr) ||
            Regex("""\\\(""").containsMatchIn(maskedStr)
        ) {
            return true
        }
        val beginMatch = Regex("""\\begin\{([A-Za-z]+\*?)\}""").find(maskedStr)
        if (beginMatch != null && isMathEnvironment(beginMatch.groupValues[1])) {
            return true
        }
        return false
    }

    private val laterMarkdownBlockRegex = Regex("""^\s*(?:#{1,6}\s|`{3,}|~{3,})""")
    private val validTagOrCommentRegex = Regex("""^(\\tag\*?\{[^}]*\}|%.*)*$""")

    fun displayBlock(lines: List<String>, startLine: Int): LexiMathDisplayBlock? {
        if (startLine < 0 || startLine >= lines.size) return null
        val first = lines[startLine].trim()
        val envOpen = envOpenRegex.find(first)
        if (envOpen != null && isMathEnvironment(envOpen.groupValues[1])) {
            val envName = envOpen.groupValues[1]
            val openTag = "\\begin{$envName}"
            val closeTag = "\\end{$envName}"
            var depth = 0
            val body = mutableListOf<String>()
            for (lineIndex in startLine until lines.size) {
                val rawLine = lines[lineIndex].removeSuffix("\r")
                if (lineIndex > startLine && laterMarkdownBlockRegex.containsMatchIn(rawLine)) {
                    return null
                }
                body.add(rawLine)
                var cursor = 0
                while (cursor < rawLine.length) {
                    val nextOpen = rawLine.indexOf(openTag, cursor)
                    val nextClose = rawLine.indexOf(closeTag, cursor)
                    if (nextOpen < 0 && nextClose < 0) break
                    if (nextOpen >= 0 && (nextClose < 0 || nextOpen < nextClose)) {
                        depth++
                        cursor = nextOpen + openTag.length
                    } else {
                        depth--
                        cursor = nextClose + closeTag.length
                        if (depth == 0) {
                            val trailing = rawLine.substring(cursor).trim()
                            if (trailing.isNotEmpty() && !validTagOrCommentRegex.matches(trailing)) {
                                return null
                            }
                            return LexiMathDisplayBlock(
                                text = body.joinToString("\n").trim(),
                                endLine = lineIndex
                            )
                        }
                    }
                }
            }
            return null
        }
        val opener = when {
            first.startsWith("$$") -> "$$"
            first.startsWith("\\[") -> "\\["
            else -> ""
        }
        if (opener.isEmpty()) return null
        val closer = if (opener == "$$") "$$" else "\\]"
        val body = mutableListOf<String>()
        for (lineIndex in startLine until lines.size) {
            val line = if (lineIndex == startLine) first.substring(opener.length) else lines[lineIndex].removeSuffix("\r")
            var search = 0
            var closing = line.indexOf(closer, search)
            while (closing >= 0 && isEscaped(line, closing)) {
                search = closing + closer.length
                closing = line.indexOf(closer, search)
            }
            if (closing >= 0) {
                val trailing = line.substring(closing + closer.length).trim()
                if (trailing.isNotEmpty() && !trailing.startsWith("%")) {
                    return null
                }
                body.add(line.substring(0, closing))
                return LexiMathDisplayBlock(
                    text = body.joinToString("\n").trim(),
                    endLine = lineIndex
                )
            }
            if (lineIndex > startLine && laterMarkdownBlockRegex.containsMatchIn(line)) {
                return null
            }
            body.add(line)
        }
        return null
    }

    /** Formats LaTeX math into clean Unicode math symbols for native typography rendering. */
    fun formatReadableMath(latex: String): String {
        var out = latex.trim()
        val replacements = mapOf(
            "\\alpha" to "α", "\\beta" to "β", "\\gamma" to "γ", "\\delta" to "δ",
            "\\epsilon" to "ε", "\\varepsilon" to "ε", "\\zeta" to "ζ", "\\eta" to "η",
            "\\theta" to "θ", "\\iota" to "ι", "\\kappa" to "κ", "\\lambda" to "λ",
            "\\mu" to "μ", "\\nu" to "ν", "\\xi" to "ξ", "\\pi" to "π", "\\rho" to "ρ",
            "\\sigma" to "σ", "\\tau" to "τ", "\\phi" to "φ", "\\varphi" to "φ",
            "\\chi" to "χ", "\\psi" to "ψ", "\\omega" to "ω",
            "\\Delta" to "Δ", "\\Gamma" to "Γ", "\\Lambda" to "Λ", "\\Omega" to "Ω",
            "\\Phi" to "Φ", "\\Pi" to "Π", "\\Sigma" to "Σ", "\\Theta" to "Θ",
            "\\sum" to "∑", "\\prod" to "∏", "\\int" to "∫", "\\infty" to "∞",
            "\\partial" to "∂", "\\nabla" to "∇", "\\pm" to "±", "\\mp" to "∓",
            "\\times" to "×", "\\div" to "÷", "\\cdot" to "·", "\\leq" to "≤", "\\le" to "≤",
            "\\geq" to "≥", "\\ge" to "≥", "\\neq" to "≠", "\\ne" to "≠", "\\approx" to "≈",
            "\\equiv" to "≡", "\\in" to "∈", "\\notin" to "∉", "\\subset" to "⊂",
            "\\subseteq" to "⊆", "\\cup" to "∪", "\\cap" to "∩", "\\forall" to "∀",
            "\\exists" to "∃", "\\rightarrow" to "→", "\\to" to "→", "\\leftarrow" to "←",
            "\\Rightarrow" to "⇒", "\\Leftrightarrow" to "⇔", "\\sqrt" to "√"
        )
        for ((k, v) in replacements) {
            out = out.replace(k, v)
        }
        out = out.replace(Regex("""\\frac\{([^{}]+)\}\{([^{}]+)\}"""), "($1)/($2)")
        return out
    }
}
