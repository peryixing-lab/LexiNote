package com.lovexjy.lexinote

import com.lovexjy.lexinote.core.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

class LexiConsistencyTest {
    private lateinit var tempDir: File

    @Before
    fun setUp() {
        tempDir = createTempDirectory("lexinote_test_").toFile()
        LexiStorageService.initForTest(tempDir)
    }

    @Test
    fun testThemePresetsAndWcagContrastConsistency() {
        assertEquals(6, LexiTheme.PRESETS.size)
        val presetIds = LexiTheme.PRESETS.map { it.id }
        assertEquals(listOf("purple", "rose", "amber", "emerald", "sky", "slate"), presetIds)

        for (preset in LexiTheme.PRESETS) {
            val light = LexiTheme.resolvePalette(preset.id, "light", false)
            val dark = LexiTheme.resolvePalette(preset.id, "dark", true)

            assertTrue(
                "Light primary contrast for ${preset.id}",
                LexiTheme.contrast(light.text_primary, light.surface_card) >= 4.5
            )
            assertTrue(
                "Dark primary contrast for ${preset.id}",
                LexiTheme.contrast(dark.text_primary, dark.surface_card) >= 4.5
            )
        }

        val accented = LexiTheme.resolveAccent(
            LexiTheme.resolvePalette("purple", "light", false),
            "#2B6CB0"
        )
        assertTrue(LexiTheme.contrast(accented.brand, accented.surface_card) >= 3.0)
    }

    @Test
    fun testFrontmatterParseApplyAndRoundtripConsistency() {
        val raw = """
            ---
            title: 鸿蒙与安卓一致性
            status: in-progress
            tags:
              - 架构
              - 跨端/移动端
            ---
            # 正文标题
            这里是正文内容。
        """.trimIndent()

        val parsed = LexiFrontmatter.parse(raw)
        assertTrue(parsed.hasBlock)
        assertTrue(parsed.tags.contains("架构"))
        assertTrue(parsed.tags.contains("跨端/移动端"))
        assertEquals("in-progress", parsed.properties.firstOrNull { it.key == "status" }?.value)
        assertTrue(parsed.body.startsWith("# 正文标题"))

        val updated = LexiFrontmatter.apply(
            parsed.body,
            parsed.properties + NoteProperty("priority", "number", "1"),
            parsed.tags + "已验证",
            true
        )
        val reparsed = LexiFrontmatter.parse(updated)
        assertTrue(reparsed.tags.contains("已验证"))
        assertEquals("1", reparsed.properties.firstOrNull { it.key == "priority" }?.value)
    }

    @Test
    fun testMathSyntaxInlineAndDisplayBlockConsistency() {
        val line = "欧拉公式 \$e^{i\\pi} + 1 = 0\$ 与积分 \$\\int_0^1 x^2 dx\$"
        assertTrue(LexiMathSyntax.hasMath(line))
        assertFalse(LexiMathSyntax.hasUnclosedMath(line))
        assertTrue(LexiMathSyntax.hasUnclosedMath("未闭合公式 \$a + b"))

        val tokens = LexiMathSyntax.inlineTokens(line)
        val mathTokens = tokens.filter { it.isMath }
        assertEquals(2, mathTokens.size)

        val readable = LexiMathSyntax.formatReadableMath("\\alpha + \\beta \\rightarrow \\frac{1}{2}")
        assertTrue(readable.contains("α"))
        assertTrue(readable.contains("β"))
        assertTrue(readable.contains("→"))
        assertTrue(readable.contains("(1)/(2)"))

        val display = LexiMathSyntax.displayBlock(
            """
            \begin{aligned}
            f(x) &= x^2 + 1 \\
            g(x) &= 2x
            \end{aligned}
            \tag{2.1}
            """.trimIndent()
        )
        assertEquals("aligned", display.envLabel)
        assertEquals("2.1", display.tag)
        assertEquals(2, display.lines.size)
    }

    @Test
    fun testMarkdownEngineWikiLinksTagsBlocksAndMindMapConversion() {
        val md = """
            # 知识图谱设计
            参考 [[双向链接规范#核心算法|双链算法]] 与 ![[嵌入章节#简介]]
            标签测试 #知识管理 #鸿蒙/ArkTS 忽略颜色 #6E44D9

            ```kotlin
            // 代码块中的 [[伪链接]] 与 #伪标签 应被忽略
            val x = "[[ignored]] #ignored"
            ```

            > [!TIP]
            > 这是一个提示块

            - [x] 已完成任务
            - [ ] 待办任务

            | 模块 | 状态 |
            | --- | --- |
            | 引擎 | 完成 |
        """.trimIndent()

        val links = MarkdownEngine.extractWikiLinks(md)
        assertEquals(1, links.size)
        assertEquals("双向链接规范", links[0].targetTitle)
        assertEquals("核心算法", links[0].heading)
        assertEquals("双链算法", links[0].alias)

        val tags = MarkdownEngine.extractInlineTags(md)
        assertTrue(tags.contains("知识管理"))
        assertTrue(tags.contains("鸿蒙/ArkTS"))
        assertFalse(tags.contains("6E44D9"))
        assertFalse(tags.contains("ignored"))

        val blocks = MarkdownEngine.parseBlocks(md)
        assertTrue(blocks.any { it.type == "heading" && it.text == "知识图谱设计" })
        assertTrue(blocks.any { it.type == "callout" && it.meta == "TIP" })
        assertTrue(blocks.any { it.type == "task" && it.checked })
        assertTrue(blocks.any { it.type == "task" && !it.checked })
        assertTrue(blocks.any { it.type == "code" })
        assertTrue(blocks.any { it.type == "table" })

        val mmNodes = MarkdownEngine.markdownToMindMapNodes("知识图谱设计", md)
        assertTrue(mmNodes.size >= 2)
        val laidOut = MarkdownEngine.computeMindMapLayout(mmNodes, "both")
        assertEquals(mmNodes.size, laidOut.size)
        val outlineMd = MarkdownEngine.mindMapToMarkdownOutline("知识图谱设计", laidOut)
        assertTrue(outlineMd.contains("# 知识图谱设计"))
    }

    @Test
    fun testSearchAndHighlightAndRelationsConsistency() {
        val notes = LexiStorageService.listNotes()
        assertTrue(notes.size >= 3)

        val ranked = LexiSearch.rank(notes, "#欢迎")
        assertTrue(ranked.isNotEmpty())

        val terms = LexiSearch.highlightTerms("知萤 #欢迎")
        assertEquals(listOf("知萤", "欢迎"), terms)
        val spans = LexiSearch.highlightSegments("欢迎使用知萤 LexiNote", terms)
        assertTrue(spans.any { it.matched && it.text == "欢迎" })
        assertTrue(spans.any { it.matched && it.text == "知萤" })

        val links = LexiStorageService.listLinks()
        val mindMaps = LexiStorageService.listMindMaps()
        val unconnected = LexiRelations.unconnectedNotes(notes, links, mindMaps)
        assertNotNull(unconnected)
    }

    @Test
    fun testNoteHistoryFnv1aDiffAndRetentionConsistency() {
        val hash1 = LexiNoteHistory.fnv1aHex("知萤 LexiNote")
        val hash2 = LexiNoteHistory.fnv1aHex("知萤 LexiNote")
        assertEquals(hash1, hash2)
        assertEquals(8, hash1.length)

        val oldText = "第一行\n第二行\n第三行"
        val newText = "第一行\n修改后的第二行\n第三行\n新增第四行"
        val diff = LexiNoteHistory.diffVersions(oldText, newText)
        assertEquals(2, diff.addedCount)
        assertEquals(1, diff.removedCount)
        assertTrue(diff.lines.any { it.kind == "add" && it.text == "修改后的第二行" })
        assertTrue(diff.lines.any { it.kind == "remove" && it.text == "第二行" })
    }

    @Test
    fun testCompletionLocalAssistantAndEcosystemLinkConsistency() {
        val notes = LexiStorageService.listNotes()
        val tags = LexiStorageService.listTags()

        val text = "正在输入双链 [[欢迎"
        val ctx = LexiCompletion.context(text, text.length)
        assertNotNull(ctx)
        assertEquals("note", ctx!!.kind)
        val candidates = LexiCompletion.candidates(ctx, notes, tags, "", 5)
        assertTrue(candidates.isNotEmpty())
        val applied = LexiCompletion.apply(text, ctx, candidates.first())
        assertTrue(applied.text.contains("[[${candidates.first().insertText}]]"))

        val arrangement = LexiLocalAssistant.arrange(
            "项目周会纪要",
            "# 项目周会纪要\n- [ ] 完成鸿蒙与安卓双端对齐\nMust: 编写一致性测试\n欢迎使用知萤",
            notes
        )
        assertTrue(arrangement.summaryBullets.isNotEmpty())
        assertTrue(arrangement.actionItems.isNotEmpty())

        val url = LexiEcosystemLink.buildOpenNoteUrl("note_1", "欢迎使用知萤")
        val parsed = LexiEcosystemLink.parse(url)
        assertNotNull(parsed)
        assertEquals("open", parsed!!.action)
        assertEquals("note_1", parsed.noteId)
    }

    @Test
    fun testStorageWorkspaceIsolationAndFirstNotePromptAndBackupRoundtrip() {
        // Workspace settings isolation
        val vaultA = LexiStorageService.getActiveVaultId()
        LexiStorageService.setNoteSortMode("title", vaultA)
        val vaultB = LexiStorageService.createVault("第二工作区", "隔离测试").id
        LexiStorageService.setNoteSortMode("links", vaultB)

        assertEquals("title", LexiStorageService.getNoteSortMode(vaultA))
        assertEquals("links", LexiStorageService.getNoteSortMode(vaultB))

        // First note creation triggers storage access prompt when local root is unconfigured
        LexiStorageService.setActiveVaultId(vaultA)
        val created = LexiStorageService.createNote(
            title = "第一篇用户笔记",
            content = "# 第一篇用户笔记\n\n测试内容",
            tags = listOf("测试"),
            vaultId = vaultA
        )
        assertTrue(LexiStorageService.takeStorageAccessPrompt())
        assertFalse(LexiStorageService.takeStorageAccessPrompt())

        // Revision creation & restore
        val manualRev = LexiStorageService.createManualRevision(created.id)
        assertNotNull(manualRev)
        LexiStorageService.saveNote(created.copy(content = "# 第一篇用户笔记\n\n修改后内容"))
        val restored = LexiStorageService.restoreNoteRevision(created.id, manualRev!!.id)
        assertNotNull(restored)
        assertTrue(restored!!.content.contains("测试内容"))

        // Export & Import JSON backup roundtrip
        val jsonBackup = LexiStorageService.exportBackupJson()
        assertTrue(jsonBackup.contains("第一篇用户笔记"))
        assertTrue(LexiStorageService.importBackupJson(jsonBackup))
    }
}
