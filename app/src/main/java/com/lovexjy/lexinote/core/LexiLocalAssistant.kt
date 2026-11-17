package com.lovexjy.lexinote.core

data class LexiLocalSuggestion(
    var id: String = "",
    var label: String = "",
    var detail: String = "",
    var markdown: String = ""
)

data class LexiLocalArrangement(
    var summary: String = "",
    var actions: MutableList<LexiLocalSuggestion> = mutableListOf(),
    var links: MutableList<LexiLocalSuggestion> = mutableListOf(),
    var tags: MutableList<LexiLocalSuggestion> = mutableListOf(),
    var method: String = "按本地规则摘录原文与匹配已有笔记，不调用生成式模型。"
)

/**
 * Deterministic local organization. Results are suggestions and never mutate notes.
 * Exact 1:1 port of LexiLocalAssistant.ets.
 */
object LexiLocalAssistant {
    private val backtickFenceRegex = Regex("""```[\s\S]*?(?:```|$)""")
    private val tildeFenceRegex = Regex("""~~~[\s\S]*?(?:~~~|$)""")
    private val embedRegex = Regex("""!\[\[([^\]]+)\]\]""")
    private val aliasedWikiRegex = Regex("""\[\[([^\]|]+)\|([^\]]+)\]\]""")
    private val plainWikiRegex = Regex("""\[\[([^\]]+)\]\]""")
    private val mdImageRegex = Regex("""!\[[^\]]*\]\([^)]*\)""")
    private val mdLinkRegex = Regex("""\[([^\]]+)\]\([^)]*\)""")
    private val headingQuoteLineRegex = Regex("""^[#>\s]+""", RegexOption.MULTILINE)
    private val inlineMarksRegex = Regex("""(?:\*\*|__|==|~~|`)""")
    private val listBulletLineRegex = Regex("""^\s*[-*+]\s+(?:\[[ xX]\]\s*)?""", RegexOption.MULTILINE)
    private val spacesRegex = Regex("""[ \t]+""")
    private val sentenceSplitRegex = Regex("""[\n。！？!?]+""")
    private val tableDividerRegex = Regex("""^[-:|\s]+$""")
    private val checkedTaskRegex = Regex("""^\s*[-*+]\s+\[[xX]\]""")
    private val uncheckedTaskRegex = Regex("""^\s*[-*+]\s+\[ \]\s*(.+)$""")
    private val proseTaskRegex = Regex(
        """^(?:\s*[-*+]\s+)?\s*(?:(?:待办|TODO|行动项|下一步)\s*[:：]\s*|(?:需要|计划|记得|明天要)\s*)(.+)$""",
        RegexOption.IGNORE_CASE
    )
    private val validTagRegex = Regex("""^[\u4e00-\u9fa5A-Za-z0-9_/-]{1,28}$""")

    private fun body(content: String): String {
        return MarkdownEngine.parseFrontmatter(content).body.take(50000)
            .replace(backtickFenceRegex, "")
            .replace(tildeFenceRegex, "")
    }

    private fun plain(text: String): String {
        return text
            .replace(embedRegex, "$1")
            .replace(aliasedWikiRegex, "$2")
            .replace(plainWikiRegex, "$1")
            .replace(mdImageRegex, "")
            .replace(mdLinkRegex, "$1")
            .replace(headingQuoteLineRegex, "")
            .replace(inlineMarksRegex, "")
            .replace(listBulletLineRegex, "")
            .replace(spacesRegex, " ")
            .trim()
    }

    private fun suggestion(id: String, label: String, markdown: String, detail: String): LexiLocalSuggestion {
        return LexiLocalSuggestion(id = id, label = label, detail = detail, markdown = markdown)
    }

    fun arrange(content: String, notes: List<NoteItem>): LexiLocalArrangement {
        val result = LexiLocalArrangement()
        val bodyText = body(content)
        val plainText = plain(bodyText)
        val candidates = plainText.split(sentenceSplitRegex)
            .map { it.trim() }
            .filter { it.length >= 10 && !tableDividerRegex.matches(it) }
        val selected = mutableListOf<String>()
        for (candidate in candidates) {
            val truncated = candidate.take(140)
            if (!selected.contains(truncated)) {
                selected.add(truncated)
            }
            if (selected.size >= 3) break
        }
        result.summary = selected.joinToString("；").take(360).ifEmpty { plainText.take(240) }

        val actionKeys = mutableSetOf<String>()
        for (raw in bodyText.split("\n")) {
            if (checkedTaskRegex.containsMatchIn(raw)) continue
            val task = uncheckedTaskRegex.matchEntire(raw)
            val prose = proseTaskRegex.matchEntire(raw)
            val rawExtract = task?.groupValues?.get(1) ?: prose?.groupValues?.get(1) ?: ""
            val text = plain(rawExtract).take(180)
            val key = text.lowercase()
            if (text.isEmpty() || actionKeys.contains(key)) continue
            actionKeys.add(key)
            result.actions.add(
                suggestion(
                    "action-${result.actions.size}",
                    text,
                    "- [ ] $text",
                    "从未完成任务或行动提示语摘录"
                )
            )
            if (result.actions.size >= 8) break
        }

        val lower = plainText.lowercase()
        val existingTargets = MarkdownEngine.extractWikiLinks(bodyText).map { it.targetText.lowercase() }
        val existingTags = MarkdownEngine.parseFrontmatter(content).tags + MarkdownEngine.extractInlineTags(bodyText)
        val tagCounts = mutableMapOf<String, Int>()
        val linkTitles = mutableSetOf<String>()

        for (note in notes.take(3000)) {
            if (note.trashedAt > 0L) continue
            val title = note.title.trim()
            val titleKey = title.lowercase()
            if (title.length in 2..80 &&
                !Regex("""[\[\]|#\r\n]""").containsMatchIn(title) &&
                lower.contains(titleKey) &&
                note.content != content &&
                !existingTargets.contains(titleKey) &&
                !existingTargets.contains(note.id.lowercase()) &&
                !linkTitles.contains(titleKey) &&
                result.links.size < 8
            ) {
                linkTitles.add(titleKey)
                result.links.add(
                    suggestion(
                        "link-${note.id}",
                        title,
                        "[[$title]]",
                        "正文提到了这篇已有笔记的标题"
                    )
                )
            }
            for (tag in note.tags) {
                if (validTagRegex.matches(tag) && lower.contains(tag.lowercase()) && !existingTags.contains(tag)) {
                    tagCounts[tag] = (tagCounts[tag] ?: 0) + 1
                }
            }
        }

        val tags = tagCounts.keys.sortedByDescending { tagCounts[it] ?: 0 }.toMutableList()
        val topicTags = listOf(
            "学习" to "学习|课程|复习|考试",
            "会议" to "会议|议程|纪要",
            "读书" to "读书|阅读|书评",
            "项目" to "项目|迭代|需求",
            "计划" to "计划|日程|安排",
            "灵感" to "灵感|创意|想法"
        )
        for ((topic, pattern) in topicTags) {
            if (!tags.contains(topic) && !existingTags.contains(topic) && Regex(pattern).containsMatchIn(plainText)) {
                tags.add(topic)
            }
        }
        result.tags = tags.take(8).map { tag ->
            suggestion("tag-$tag", "#$tag", "#$tag", "按正文关键词与现有标签匹配")
        }.toMutableList()
        return result
    }

    fun selectedMarkdown(
        result: LexiLocalArrangement,
        selectedIds: List<String>,
        summary: String,
        includeSummary: Boolean
    ): String {
        val sections = mutableListOf<String>()
        if (includeSummary && summary.trim().isNotEmpty()) {
            sections.add("## 摘要（本地整理）\n\n${summary.trim()}")
        }
        val actions = result.actions.filter { selectedIds.contains(it.id) }
        if (actions.isNotEmpty()) {
            sections.add("## 行动项\n\n" + actions.joinToString("\n") { it.markdown })
        }
        val links = result.links.filter { selectedIds.contains(it.id) }
        if (links.isNotEmpty()) {
            sections.add("相关笔记：" + links.joinToString(" · ") { it.markdown })
        }
        val tags = result.tags.filter { selectedIds.contains(it.id) }
        if (tags.isNotEmpty()) {
            sections.add(tags.joinToString(" ") { it.markdown })
        }
        return if (sections.isNotEmpty()) "\n\n${sections.joinToString("\n\n")}\n" else ""
    }
}
