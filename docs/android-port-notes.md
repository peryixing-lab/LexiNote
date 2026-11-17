# 知萤 LexiNote — Android 手机版移植与鸿蒙手机版一致性检验报告

本文件记录 `/Users/thousandmiles/Lexinote/lexinote-Android` 针对 `/Users/thousandmiles/Lexinote/LexiNote-Harmony`（鸿蒙手机端 `viewportWidth < 840`）进行 1:1 移植的模块映射、核心算法对齐与一致性检验结果。

---

## 一、 架构与核心引擎层（Core Layer）1:1 对齐清单

| 鸿蒙手机端源码 (`LexiNote-Harmony/entry/src/main/ets/core/`) | Android 端源码 (`lexinote-Android/app/src/main/java/com/lovexjy/lexinote/core/`) | 对齐状态 | 一致性检验说明 |
| :--- | :--- | :---: | :--- |
| `LexiModels.ets` | `LexiModels.kt` | ✅ 100% | 完整对齐 `VaultItem`、`LexiProject`、`NoteProperty`、`NoteItem`、`NoteLink`、`UnlinkedMention`、`MindMapNode`、`MindMapDoc`、`CanvasCard`、`CanvasEdge`、`CanvasBoard`、`GraphNode`、`GraphEdge`、`MarkdownBlock`、`OutlineHeading`、`LexiBackupPackage`、`CREATE_ENTRIES`、`NoteRevision`、`LexiShareDraft` 等全部 26 个核心模型与默认常量。 |
| `LexiTheme.ets` | `LexiTheme.kt` | ✅ 100% | 完整复刻 6 套预设主题（`purple` 鸢尾紫、`rose` 玫瑰粉、`amber` 暖杏橙、`emerald` 森林绿、`sky` 晴空蓝、`slate` 石墨灰）深浅色板，以及 WCAG 2.1 相对亮度 `luminance`、对比度 `contrast`、自动前景补偿 `fitText`（正文对比度 `>= 4.5`，次要文本 `>= 3.0`）与 `resolveAccent` 算法。 |
| `LexiFrontmatter.ets` | `LexiFrontmatter.kt` | ✅ 100% | 完整复刻 YAML Frontmatter 解析器 `parse`、写回器 `apply` 与序列化器 `serialize` / `serializeFull`，支持多行列表 `tags`、布尔/数字/日期/列表属性识别与双向同步。 |
| `LexiMathSyntax.ets` | `LexiMathSyntax.kt` | ✅ 100% | 完整复刻行内 `$...$` 与块级 `$$...$$` 公式扫描器、转义符 `\$` 识别、未闭合公式检测 `hasUnclosedMath`、`aligned`/`matrix`/`cases` 环境与 `\tag{...}` 编号解析，以及 Unicode 数学符号可读化 `formatReadableMath`。 |
| `MarkdownEngine.ets` | `MarkdownEngine.kt` | ✅ 100% | 完整复刻 `[[笔记#章节|别名]]` 双链提取、代码块防误判、`#多级/标签` 提取（过滤 `#6E44D9` 十六进制颜色）、潜在提及 `findUnlinkedMentions`、重命名自动更新双链、块级 AST 解析 `parseBlocks`（标题/提示块/引用/任务/代码块/公式块/表格/嵌入笔记/图片/分割线），以及思维导图布局 `computeMindMapLayout` 与 Markdown 双向互转。 |
| `LexiSearch.ets` | `LexiSearch.kt` | ✅ 100% | 完整复刻 `#tag`、`tag:`、`path:`、`prop:key=val` 结构化搜索词解析、多维相关性打分排序 `rank`、高亮切片 `highlightSegments` 与 4 种笔记排序模式（最近更新、最近创建、标题 A-Z、反向链接数）。 |
| `LexiRelations.ets` | `LexiRelations.kt` | ✅ 100% | 完整复刻正向链接、反向链接、关联导图计数 `counts`、未连接孤岛笔记检测 `unconnectedNotes` 与智能关联推荐 `suggestLinkCandidates`。 |
| `GraphLayout.ets` + `LexiGraphForce.ets` | `GraphLayout.kt` | ✅ 100% | 完整复刻黄金角螺旋初始分布 `golden` 与弹簧斥力/引力迭代布局算法 `LexiGraphForce.layout`，支持全局图谱 `build` 与单篇局部邻域图谱 `local`。 |
| `LexiTemplates.ets` + `LexiTemplateLibrary.ets` | `LexiTemplates.kt` | ✅ 100% | 完整复刻 6 套内置模板（每日笔记、康奈尔学习笔记、会议纪要、项目复盘、读书笔记、问题排查记录）、动态占位符替换（`{{date}}`、`{{time}}`、`{{datetime}}`、`{{title}}`、`{{vault}}`、`{{project}}`）与自定义模板持久化。 |
| `LexiNoteHistory.ets` | `LexiNoteHistory.kt` | ✅ 100% | 完整复刻 32 位 FNV-1a 快照哈希 `fnv1aHex`、版本去重与保留期裁剪策略 `appendAndPrune`、动态规划 LCS 逐行差异对比 `diffVersions` 与崩溃恢复草稿日志（WAL）。 |
| `LexiCompletion.ets` | `LexiCompletion.kt` | ✅ 100% | 完整复刻光标处 `[[`（笔记与 `#` 章节补全）与 `#`（标签补全）上下文识别、候选打分排序、补全写回 `apply` 与首次提及自动转双链 `linkFirstMention`。 |
| `LexiLocalAssistant.ets` | `LexiLocalAssistant.kt` | ✅ 100% | 完整复刻离线启发式整理引擎 `arrange`：自动提取核心摘要、行动待办项、推荐双链笔记与建议标签。 |
| `LexiCodeHighlight.ets` + `LexiLiveMarkdown.ets` + `LexiEcosystemLink.ets` | `LexiCodeTools.kt` | ✅ 100% | 完整复刻代码块语法高亮分词、代码块折叠/自动折行/行号控制、行级实时预览分类 `classifyLine`、任务勾选切换 `toggleTaskLine` 与 `lexinote://` 跨应用深链协议。 |
| `LexiI18n.ets` + `LexiEnglish.ets` | `LexiI18n.kt` | ✅ 100% | 完整复刻中英双语词典与动态文案映射。 |
| `LexiStorageService.ets` | `LexiStorageService.kt` | ✅ 100% | 完整复刻工作区隔离偏好存储、首次保存笔记后的本地目录引导状态机 `takeStorageAccessPrompt`、本地真实 `.md` 文件双向同步、JSON/ZIP 全量备份导入导出与回收站生命周期。 |

---

## 二、 手机端界面与交互层（Phone UI Layer）1:1 对齐清单

| 鸿蒙手机端页面 / 组件 | Android 端页面 / 组件 | 视觉与交互一致性检验 |
| :--- | :--- | :--- |
| `Index.ets`（手机窄屏模式 `!wide()`） | `MainActivity.kt` (`LexiNotePhoneApp`) | 顶部可随滚动折叠的品牌标题栏 + 右上角圆形 `+` 新建菜单（笔记、思维导图、自由白板）+ 底部悬浮胶囊四栏导航栏（`height = 62.dp`, `RoundedCornerShape(31.dp)`：首页、知识库、探索、我的）。 |
| `Index.ets` — 首页 Tab | `LexiPhoneTabs.kt` (`LexiHomeTab`) | 时段问候语、`今日笔记` / `从模板新建` / `插件` 快捷按钮、`随手记` 灵感速记卡片（保存时弹出目标工作区与项目选择器）、4 项核心指标卡片（笔记、导图、白板、链接）、`置顶` 笔记区、`最近笔记`（支持 `最近访问` / `最近编辑` 切换）。 |
| `Index.ets` — 知识库 Tab | `LexiPhoneTabs.kt` (`LexiVaultTab`) | 顶部 `工作区与项目` 切换入口、全文搜索框、四栏分段切换（`笔记` / `导图` / `白板` / `标签`）、笔记筛选胶囊（`全部笔记` / `置顶` / `收藏` / `未连接`）、项目下拉与排序下拉、列表/网格切换、标签筛选横幅与长按菜单。 |
| `Index.ets` — 探索 Tab | `LexiPhoneTabs.kt` (`LexiExploreTab`) | `关联列表` / `关系图` 切换、力导向关系图谱 `LexiGraphView`（支持手势缩放平移、`重排`/`居中`、`只看这篇`/`查看全部`、`显示` 导图与标签开关）、已连接笔记列表、`未连接笔记` 引导卡片（`预览`、`一键关联`、`打开并连接`）与 `可能有关` 潜在提及卡片。 |
| `Index.ets` — 我的 Tab | `LexiPhoneTabs.kt` (`LexiProfileTab`) | 知萤品牌身份卡（Logo、当前工作区名称、笔记篇数徽标）、`设置` 入口卡、`回收站` 入口卡（带已删除数量角标）、`使用指南` 入口卡与底部工作区位置提示。 |
| `NoteEditorPage.ets`（手机布局） | `NoteEditorScreen.kt` | 顶部返回栏、未同步草稿恢复横幅、置顶/收藏/历史/整理快捷胶囊、行内大标题编辑、4 种视图模式（实时预览、源码编辑、分栏对照、沉浸阅读）、`[[` 与 `#` 智能补全条、可折叠三大底部面板（属性与标签、文档结构大纲、知识关联与反向引用）、手机端专属底部写作栏（`工具`、`语音记录`、`大纲`、字数统计、`阅读`/`继续编辑`）以及三档可切换工具弹窗（`简洁` / `学习` / `专业`）。 |
| `MindMapPage.ets` | `MindMapAndCanvasScreens.kt` (`MindMapScreen`) | 导图标题编辑、`导图` / `大纲` 视图切换、`+ 子主题` / `+ 同级主题`、`向右` / `双向` / `组织` 三种自动布局、撤销/重做、2D 点阵画布与贝塞尔曲线连线、节点拖拽与缩放、选中节点属性面板（展开/折叠、删除、5 色标签、关联或新建笔记）与一键转为笔记。 |
| `CanvasPage.ets` | `MindMapAndCanvasScreens.kt` (`CanvasScreen`) | 白板标题编辑、`+ 新增卡片`、缩放与适应画布、2D 点阵白板与卡片拖拽、连线绘制、选中卡片属性面板（四向微调、底色切换、卡片连线/断开、关联或新建知识库笔记）。 |
| `SettingsPage.ets` + `LexiSettingsWindow.ets` | `SecondaryScreens.kt` (`SettingsScreen`) | 手机端两级导航：根列表展示搜索框与 `选项`（外观、编辑器、文件与链接、插件）+ `关于`（关于）；点击进入子页面后左上角返回按钮优先返回设置根列表，再返回上一页。 |
| `WorkspacesPage.ets` / `TrashPage.ets` / `HelpPage.ets` / `ShareCapturePage.ets` | `SecondaryScreens.kt` | 完整实现多工作区与项目管理、回收站恢复/彻底删除/清空、10 节使用指南卡片与系统级分享剪藏收件箱。 |
| `LexiIcon.ets` + `base/media/*.svg` | `LexiIcon.kt` + `res/drawable/lexi_logo.xml` | 全部 29 个 SVG 线性图标与品牌萤火 Logo 均按原 SVG `viewBox="0 0 24 24"` 路径精确复刻。 |

---

## 三、 自动化一致性检验与构建验证结果

通过 `LexiConsistencyTest.kt` 执行 8 组核心一致性测试套件及 Debug APK 打包验证：

1. `testThemePresetsAndWcagContrastConsistency`：验证 6 套预设主题 ID、深浅色模式及自定义强调色下的 WCAG 对比度（正文 `>= 4.5`，品牌色 `>= 3.0`）与 `LexiTheme.ets` 完全一致。
2. `testFrontmatterParseApplyAndRoundtripConsistency`：验证 YAML Frontmatter 解析、属性/标签追加写回与二次解析往返一致性。
3. `testMathSyntaxInlineAndDisplayBlockConsistency`：验证行内公式 `$...$`、未闭合公式检测、Unicode 可读化渲染与 `aligned` 块级公式及 `\tag{2.1}` 提取一致性。
4. `testMarkdownEngineWikiLinksTagsBlocksAndMindMapConversion`：验证 `[[笔记#章节|别名]]` 双链提取、代码块防误判、`#多级/标签` 提取（过滤十六进制色值）、块级 AST 解析及 Markdown 与思维导图双向转换一致性。
5. `testSearchAndHighlightAndRelationsConsistency`：验证结构化搜索排序、高亮分词切片与孤岛笔记关系检测一致性。
6. `testNoteHistoryFnv1aDiffAndRetentionConsistency`：验证 32 位 FNV-1a 快照签名与 LCS 逐行差异对比（新增/删除/保留行）一致性。
7. `testCompletionLocalAssistantAndEcosystemLinkConsistency`：验证 `[[` 双链智能补全、本地离线整理助手（摘要/待办提取）与 `lexinote://` 深链解析一致性。
8. `testStorageWorkspaceIsolationAndFirstNotePromptAndBackupRoundtrip`：验证多工作区配置隔离、首次新建笔记的存储引导状态机、手动历史快照创建与恢复、以及全量 JSON 备份导出/导入往返一致性。

- **验证命令**：`./gradlew testDebugUnitTest assembleDebug`
- **构建产物**：`app/build/outputs/apk/debug/app-debug.apk`
- **结果**：`BUILD SUCCESSFUL`（全部单元测试与一致性校验 100% 通过）
