package com.lovexjy.lexinote.core

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Date

/**
 * Exact 1:1 port of LexiTemplates.ets.
 */
object LexiTemplates {
    fun dateKey(now: Date = Date()): String {
        val cal = Calendar.getInstance().apply { time = now }
        val year = cal.get(Calendar.YEAR)
        val month = pad(cal.get(Calendar.MONTH) + 1)
        val day = pad(cal.get(Calendar.DAY_OF_MONTH))
        return "$year-$month-$day"
    }

    private fun pad(part: Int): String = if (part < 10) "0$part" else "$part"

    private val tokenRegex = Regex("""\{\{\s*(date|time|title|weekday)\s*\}\}""")
    private val weekdays = listOf("星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六")

    fun render(content: String, title: String, now: Date = Date()): String {
        val cal = Calendar.getInstance().apply { time = now }
        return tokenRegex.replace(content) { match ->
            when (match.groupValues[1]) {
                "date" -> dateKey(now)
                "time" -> "${pad(cal.get(Calendar.HOUR_OF_DAY))}:${pad(cal.get(Calendar.MINUTE))}"
                "weekday" -> weekdays[cal.get(Calendar.DAY_OF_WEEK) - 1]
                else -> title
            }
        }
    }
}

data class LexiTemplateItem(
    var id: String = "",
    var title: String = "",
    var content: String = "",
    var category: String = "自定义",
    var tags: MutableList<String> = mutableListOf(),
    var properties: MutableList<NoteProperty> = mutableListOf(),
    var builtIn: Boolean = false,
    var sourceNoteId: String = "",
    var createdAt: Long = 0L,
    var updatedAt: Long = 0L,
    var name: String = "",
    var description: String = "",
    var titlePattern: String = "{{title}}",
    var builtin: Boolean = false
) {
    init {
        if (name.isNotEmpty() && title.isEmpty()) title = name
        if (title.isNotEmpty() && name.isEmpty()) name = title
        if (builtin && !builtIn) builtIn = true
        if (builtIn && !builtin) builtin = true
    }
}

data class LexiTemplateLibraryState(
    var version: Int = 1,
    var templates: MutableList<LexiTemplateItem> = mutableListOf(),
    var defaultDailyId: String = "builtin-daily",
    var legacyImported: Boolean = false
)

/**
 * Templates are global library records, independent of any workspace or note.
 * Exact 1:1 port of LexiTemplateLibrary.ets.
 */
object LexiTemplateLibrary {
    private fun builtin(
        id: String,
        title: String,
        category: String,
        content: String,
        tags: List<String>
    ): LexiTemplateItem {
        return LexiTemplateItem(
            id = id,
            title = title,
            category = category,
            content = content,
            tags = tags.toMutableList(),
            builtIn = true
        )
    }

    fun builtins(): MutableList<LexiTemplateItem> {
        return mutableListOf(
            builtin(
                "builtin-daily",
                "每日记录",
                "日常",
                "# {{date}} {{weekday}}\n\n## 今日重点\n\n- [ ] \n\n## 随手记录\n\n\n\n## 今日回顾\n\n- 今天完成了什么：\n- 明天想继续什么：\n",
                listOf("日记")
            ),
            builtin(
                "builtin-schedule",
                "日程计划",
                "计划",
                "# {{title}}\n\n日期：{{date}} {{weekday}}\n\n## 时间安排\n\n| 时间 | 事项 | 备注 |\n| --- | --- | --- |\n| 上午 |  |  |\n| 下午 |  |  |\n| 晚间 |  |  |\n\n## 待办清单\n\n- [ ] \n\n## 调整与提醒\n\n",
                listOf("计划")
            ),
            builtin(
                "builtin-code",
                "代码笔记",
                "代码",
                "# {{title}}\n\n记录时间：{{date}} {{time}}\n\n## 问题与目标\n\n\n\n## 代码\n\n```\n\n```\n\n## 实现说明\n\n\n\n## 验证结果\n\n- 输入与环境：\n- 预期结果：\n- 实际结果：\n\n## 后续改进\n\n- [ ] \n",
                listOf("代码")
            ),
            builtin(
                "builtin-study",
                "学习笔记",
                "学习",
                "# {{title}}\n\n学习日期：{{date}} {{weekday}}\n\n## 学习目标\n\n- [ ] \n\n## 核心概念\n\n\n\n## 示例与理解\n\n\n\n## 疑问与关联\n\n\n\n## 复习清单\n\n- [ ] 用自己的话解释核心概念\n- [ ] 完成一次练习\n",
                listOf("学习")
            ),
            builtin(
                "builtin-meeting",
                "会议纪要",
                "会议",
                "# {{title}}\n\n会议时间：{{date}} {{time}}\n参会人员：\n\n## 议题\n\n1. \n\n## 讨论记录\n\n\n\n## 决定事项\n\n\n\n## 后续行动\n\n| 事项 | 负责人 | 截止时间 | 状态 |\n| --- | --- | --- | --- |\n|  |  |  | 待办 |\n\n## 下次跟进\n\n",
                listOf("会议")
            ),
            builtin(
                "builtin-project",
                "项目规划",
                "项目",
                "# {{title}}\n\n创建日期：{{date}}\n\n## 目标与范围\n\n- 项目目标：\n- 交付内容：\n- 验收标准：\n\n## 里程碑\n\n| 阶段 | 交付物 | 计划完成时间 |\n| --- | --- | --- |\n| 准备 |  |  |\n| 实施 |  |  |\n| 验收 |  |  |\n\n## 当前任务\n\n- [ ] \n\n## 风险与依赖\n\n\n\n## 进展记录\n\n### {{date}} {{time}}\n\n",
                listOf("项目")
            )
        )
    }

    fun fresh(): LexiTemplateLibraryState {
        return LexiTemplateLibraryState(templates = builtins())
    }

    fun clone(item: LexiTemplateItem): LexiTemplateItem {
        return item.copy(
            tags = item.tags.toMutableList(),
            properties = item.properties.map { it.copy() }.toMutableList()
        )
    }

    private fun validId(id: String): Boolean {
        return Regex("""^[A-Za-z0-9_-]{1,128}$""").matches(id)
    }

    fun encode(state: LexiTemplateLibraryState): String {
        val root = JSONObject()
        root.put("version", state.version)
        root.put("defaultDailyId", state.defaultDailyId)
        root.put("legacyImported", state.legacyImported)
        val arr = JSONArray()
        for (item in state.templates) {
            val obj = JSONObject()
            obj.put("id", item.id)
            obj.put("title", item.title)
            obj.put("content", item.content)
            obj.put("category", item.category)
            val tagsArr = JSONArray()
            for (tag in item.tags) tagsArr.put(tag)
            obj.put("tags", tagsArr)
            val propsArr = JSONArray()
            for (p in item.properties) {
                val pObj = JSONObject()
                pObj.put("key", p.key)
                pObj.put("propValue", p.propValue)
                propsArr.put(pObj)
            }
            obj.put("properties", propsArr)
            obj.put("builtIn", item.builtIn)
            obj.put("sourceNoteId", item.sourceNoteId)
            obj.put("createdAt", item.createdAt)
            obj.put("updatedAt", item.updatedAt)
            arr.put(obj)
        }
        root.put("templates", arr)
        return root.toString()
    }

    fun decode(raw: String): LexiTemplateLibraryState {
        val parsed = try {
            JSONObject(raw)
        } catch (_: Exception) {
            throw IllegalArgumentException("模板库数据不是有效 JSON，原始数据未修改")
        }
        val allowedFields = setOf("version", "templates", "defaultDailyId", "legacyImported")
        val keys = parsed.keys().asSequence().toList()
        if (keys.size != 4 || keys.any { !allowedFields.contains(it) } ||
            parsed.optInt("version", -1) != 1 ||
            !parsed.has("templates") || parsed.optJSONArray("templates") == null ||
            parsed.opt("defaultDailyId") !is String ||
            parsed.opt("legacyImported") !is Boolean
        ) {
            throw IllegalArgumentException("模板库格式无效或版本不受支持，原始数据未修改")
        }
        val templatesArr = parsed.getJSONArray("templates")
        val itemAllowedFields = setOf(
            "id", "title", "content", "category", "tags", "properties",
            "builtIn", "sourceNoteId", "createdAt", "updatedAt"
        )
        val ids = mutableSetOf<String>()
        val items = mutableListOf<LexiTemplateItem>()
        for (i in 0 until templatesArr.length()) {
            val itemObj = templatesArr.optJSONObject(i)
                ?: throw IllegalArgumentException("模板库包含无效模板，原始数据未修改")
            val itemKeys = itemObj.keys().asSequence().toList()
            if (itemKeys.size != 10 || itemKeys.any { !itemAllowedFields.contains(it) }) {
                throw IllegalArgumentException("模板库包含无效模板，原始数据未修改")
            }
            val id = itemObj.opt("id") as? String ?: ""
            val title = itemObj.opt("title") as? String ?: ""
            val content = itemObj.opt("content") as? String
            val category = itemObj.opt("category") as? String
            val tagsJson = itemObj.optJSONArray("tags")
            val propsJson = itemObj.optJSONArray("properties")
            val builtIn = itemObj.opt("builtIn") as? Boolean
            val sourceNoteId = itemObj.opt("sourceNoteId") as? String
            val createdAt = itemObj.optLong("createdAt", -1L)
            val updatedAt = itemObj.optLong("updatedAt", -1L)
            if (!validId(id) || title.trim().isEmpty() || content == null || category == null ||
                tagsJson == null || propsJson == null || builtIn == null || sourceNoteId == null ||
                (sourceNoteId.isNotEmpty() && !validId(sourceNoteId)) ||
                createdAt < 0L || updatedAt < 0L
            ) {
                throw IllegalArgumentException("模板库包含无效模板，原始数据未修改")
            }
            val tags = mutableListOf<String>()
            for (t in 0 until tagsJson.length()) {
                val tagVal = tagsJson.opt(t) as? String
                    ?: throw IllegalArgumentException("模板库包含无效模板，原始数据未修改")
                tags.add(tagVal)
            }
            val propertyKeys = mutableSetOf<String>()
            val props = mutableListOf<NoteProperty>()
            for (p in 0 until propsJson.length()) {
                val pObj = propsJson.optJSONObject(p)
                    ?: throw IllegalArgumentException("模板属性格式无效或键名重复，原始数据未修改")
                val pKeys = pObj.keys().asSequence().toList()
                val k = pObj.opt("key") as? String ?: ""
                val v = pObj.opt("propValue") as? String
                if (pKeys.size != 2 || pKeys.any { it != "key" && it != "propValue" } ||
                    k.trim().isEmpty() || v == null || propertyKeys.contains(k)
                ) {
                    throw IllegalArgumentException("模板属性格式无效或键名重复，原始数据未修改")
                }
                propertyKeys.add(k)
                props.add(NoteProperty(k, v))
            }
            if (ids.contains(id)) {
                throw IllegalArgumentException("模板库存在重复模板标识，原始数据未修改")
            }
            ids.add(id)
            items.add(
                LexiTemplateItem(
                    id = id,
                    title = title,
                    content = content,
                    category = category,
                    tags = tags,
                    properties = props,
                    builtIn = builtIn,
                    sourceNoteId = sourceNoteId,
                    createdAt = createdAt,
                    updatedAt = updatedAt
                )
            )
        }
        val defaultDailyId = parsed.getString("defaultDailyId")
        if (defaultDailyId.isNotEmpty() && !ids.contains(defaultDailyId)) {
            throw IllegalArgumentException("默认日记模板已不存在，请检查模板库设置，原始数据未修改")
        }
        return LexiTemplateLibraryState(
            version = 1,
            templates = items,
            defaultDailyId = defaultDailyId,
            legacyImported = parsed.getBoolean("legacyImported")
        )
    }
}
