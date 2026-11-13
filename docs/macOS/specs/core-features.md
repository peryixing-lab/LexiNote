# LexiNote 核心功能与数据规格（HarmonyOS → macOS 移植基线）

- 版本：v1（2026-11-12）
- 源码基线：`entry/src/main/ets/`
- 目标读者：macOS（SwiftUI）移植实现者
- 说明：本文只做事实抽取与规格记录，不含应用代码。字段名、默认值、阈值、文案均按源码原样记录；凡属“源码未实现/仅占位”的地方会显式标注。

---

## 0. 源码清单与职责

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| `core/LexiModels.ets` | 251 | 全部核心数据模型与创建入口表 |
| `core/LexiWorkspaceModels.ets` | 34 | 工作区标签页、编辑器控制器、检查器快照 |
| `core/MarkdownEngine.ets` | 802 | 块/行内解析、表格、双链、大纲、摘要、导图布局与互转 |
| `core/LexiFrontmatter.ets` | 138 | 受限 YAML frontmatter 解析与序列化 |
| `core/LexiLiveMarkdown.ets` | 139 | 实时预览的块范围、光标映射、回车推进规则 |
| `core/LexiMathSyntax.ets` | 292 | 公式定界符与环境扫描（不做排版） |
| `core/LexiMathBitmapCache.ets` | 109 | 公式位图缓存（KaTeX / WebView 渲染） |
| `core/LexiCodeHighlight.ets` | 171 | 有界词法高亮 |
| `core/LexiSearch.ets` | 71 | 搜索语法、过滤、排序权重 |
| `core/GraphLayout.ets` | 193 | 图谱拓扑构建、局部子图、后台布局 |
| `core/LexiGraphForce.ets` | 99 | 确定性力导向布局 |
| `core/LexiStorageService.ets` | 2329 | 文件 + RDB 双存储、保存、回收站、备份、导入 |
| `core/LexiFolderStore.ets` | 477 | 外部文件夹绑定、原子写、目录索引 |
| `core/LexiFolderPolicy.ets` | 17 | 路径与文件名清洗规则 |
| `core/LexiCommands.ets` | 185 | 174 条命令表 |
| `core/LexiHotkeySettings.ets` | 161 | 默认快捷键、覆盖、按键规范化 |
| `core/LexiFileActions.ets` | 150 | 路径/复制/重命名/移动/复制作用域 |
| `core/LexiExportService.ets` | 44 | 字节保存与 PDF 导出 |
| `core/LexiSeedData.ets` | 241 | 首启种子内容 |
| `components/LexiWorkspaceMindMap.ets` | 1205 | 导图画布、布局切换、节点操作、导出 |
| `components/LexiGraphView.ets` | 154 | 图谱 Canvas 绘制与点选 |
| `pages/CanvasPage.ets` | 644 | 白板画布、卡片/连线、PNG/JSON 导出 |
| `components/LexiEditorPanels.ets` | 534 | Markdown 块渲染、行内样式、表格/公式/代码 |

---

## 1. 数据模型

### 1.1 关系总览

```
VaultItem(工作区) 1 ── n LexiProject(项目/子文件夹)
      │                     │
      │                     └── n NoteItem / MindMapDoc / CanvasBoard（projectId 可空）
      └── n NoteItem / MindMapDoc / CanvasBoard

NoteItem 1 ── n NoteProperty（写入 frontmatter）
NoteItem 1 ── n NoteLink（[[双链]]，运行期由正文解析，不持久化）
NoteItem 1 ── n NoteRevision（KV 中 history:<noteId>，最多 20 条）

MindMapDoc 1 ── n MindMapNode（parentId 组成树，rootNodeId 指向根）
MindMapNode n ── 1 NoteItem（noteRefId/noteRefTitle，弱引用，可空）
CanvasBoard 1 ── n CanvasCard；1 ── n CanvasEdge（fromId/toId 指向卡片）
CanvasCard n ── 1 NoteItem（noteRefId/noteRefTitle，弱引用，可空）

GraphNode/GraphEdge 为运行期投影：note、map:<id>、tag:<name> 三类节点；
link、mapRef、tag 三类边。不落盘。
```

**通用约定**

- 所有时间戳为**毫秒** `number`；`0` 表示“未设置/未删除”。
- 主键为字符串。笔记 `id` 为 UUID（`util.generateRandomUUID(true)`，无连字符），导入的历史数据可能是 `note-algo-complexity` 之类可读 id，校验正则为 `^[A-Za-z0-9_-]{1,128}$`。
- 软删除统一用 `trashedAt > 0`（笔记）；导图/白板虽有该字段，但删除实现是**直接从索引移除**，见 §7.6。
- `vaultId` 缺省 `'default-vault'`，`projectId` 缺省 `''`（表示工作区根）。

### 1.2 VaultItem（工作区）

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `archived` | boolean | `false` | 归档后不出现在常规列表 |
| `favorite` | boolean | `false` | 收藏 |
| `id` | string | `'default-vault'` | 主键 |
| `name` | string | `'个人知识库'` | 显示名 |
| `description` | string | `'日常记录、课程学习与技术文档'` | 副标题 |
| `createdAt` | number | `0` | 创建时间 |
| `version` | number | `1` | 结构版本 |
| `folderUri` | string | `''` | 绑定的外部文件夹 URI；空 = 仅沙箱存储 |
| `permissionUri` | string | `''` | 持久化授权 URI（HarmonyOS 文件分享权限） |

### 1.3 LexiProject（项目 / 子文件夹）

| 字段 | 类型 | 默认值 |
| --- | --- | --- |
| `archived` | boolean | `false` |
| `favorite` | boolean | `false` |
| `id` | string | `''` |
| `vaultId` | string | `''` |
| `name` | string | `''` |
| `folderUri` | string | `''` |
| `permissionUri` | string | `''` |
| `createdAt` | number | `0` |

关系：`LexiProject.vaultId` 必填；项目可绑定自己的子文件夹（`folderUri`），未绑定时落回工作区目录。

### 1.4 NoteItem（笔记，核心实体）

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | string | `''` | UUID；新建时生成 |
| `vaultId` | string | `'default-vault'` | 所属工作区 |
| `projectId` | string | `''` | 所属项目；`''` = 工作区根 |
| `sourceMissing` | boolean | `false` | 绑定文件夹中的源文件消失时置 `true`（并软删除） |
| `title` | string | `''` | 可空；展示时回退到正文首行 |
| `notebook` | string | `'速记收件箱'` | 笔记本（分组）名，自由文本 |
| `content` | string | `''` | **完整 Markdown（含 frontmatter）**，文件即真相 |
| `path` | string | `''` | 物理文件绝对路径；外部文件夹模式指向用户目录 |
| `noteType` | string | `'quick'` | `quick` / `study` / `markdown`（源码注释三值） |
| `editorLevel` | string | `'simple'` | `simple` / `study` / `pro`（工具密度档位） |
| `tags` | string[] | `[]` | 内存态标签；保存时与正文 `#tag` 合并 |
| `properties` | NoteProperty[] | `[]` | 结构化属性，序列化进 frontmatter |
| `pinned` | boolean | `false` | 置顶；列表排序优先 |
| `favorite` | boolean | `false` | 收藏 |
| `trashedAt` | number | `0` | 软删除时间；>0 即回收站 |
| `createdAt` | number | `0` | 首次保存时补 `Date.now()` |
| `updatedAt` | number | `0` | 每次保存覆盖为 `Date.now()` |

**标题回退规则**（`MarkdownEngine.displayTitle`）：`title.trim()` 非空则用它；否则取 frontmatter 之后正文中第一条非空行，去掉行首 `# > * - 空白`，截断 28 字符；仍为空则 `'未命名速记'`。

**标签合并规则**（保存时）：`note.tags` 去空去重 → 追加正文行内标签（同一去重）→ 写回 `tags`，再序列化进 frontmatter。

### 1.5 NoteProperty（笔记属性）

| 字段 | 类型 | 默认值 |
| --- | --- | --- |
| `key` | string | `''` |
| `propValue` | string | `''` |

构造函数：`new NoteProperty(key = '', propValue = '')`。值一律字符串化（数字/布尔/列表在 YAML 中以文本保存）。

### 1.6 OutlineHeading（大纲标题）

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | string | `''` | 解析时生成 `h-<行号>` |
| `level` | number | `1` | 1..6（源码支持到 6） |
| `title` | string | `''` | 去掉结尾 `#` 的标题文本 |
| `lineIndex` | number | `0` | 在原文中的 0 基行号（含 frontmatter 偏移） |

### 1.7 NoteLink / UnlinkedMention（双链投影）

| 类 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| NoteLink | `sourceId` | string | 引用方笔记 id |
| | `sourceTitle` | string | 引用方展示标题 |
| | `targetId` | string | 被引笔记 id；**未解析为 `''`** |
| | `targetTitle` | string | 已解析为对方展示标题；未解析为原文目标 |
| | `anchor` | string | `#` 后锚点（可为 `''`） |
| | `displayText` | string | 竖线后的别名；无别名时等于目标文本 |
| UnlinkedMention | `sourceId`/`sourceTitle` | string | 提及方 |
| | `targetId`/`targetTitle` | string | 被提及笔记 |
| | `snippet` | string | 命中位置前后各 16 / 24 字符，换行替换为空格 |

### 1.8 MindMapDoc（思维导图文档）

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | string | `''` | 新建为 `map-<uuid>`，存储层兜底 `map-<Date.now()>` |
| `vaultId` | string | `'default-vault'` | |
| `projectId` | string | `''` | |
| `title` | string | `''` | 同时作为根节点默认文本 |
| `layoutKind` | string | `'right'` | `right` / `balanced` / `org` |
| `rootNodeId` | string | `'root'` | 根节点 id |
| `nodes` | MindMapNode[] | `[]` | 扁平数组，父子由 `parentId` 表达 |
| `favorite` | boolean | `false` | |
| `trashedAt` | number | `0` | 仅用于过滤（导图无真正回收站） |
| `createdAt` / `updatedAt` | number | `0` | |

### 1.9 MindMapNode

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | string | `''` | 根为 `root`；其余 `node-<uuid>` 或 `node-<n>` |
| `parentId` | string | `''` | 根为空串 |
| `text` | string | `''` | 节点标题（长度 >11 时显示前 10 字符 + `…`，否则原样） |
| `note` | string | `''` | 节点备注（纯文本，显示为副标题） |
| `noteRefId` | string | `''` | 关联笔记 id（弱引用） |
| `noteRefTitle` | string | `''` | 关联笔记标题快照（重命名时批量更新） |
| `order` | number | `0` | 同级排序，从 1 起 |
| `collapsed` | boolean | `false` | 折叠子分支 |
| `colorTag` | string | `'purple'` | `purple` / `indigo` / `teal` / `amber` / `rose` |
| `level` | number | `0` | 布局输出，根为 0 |
| `x` / `y` | number | `0` | 布局输出中心坐标（含用户偏移） |
| `boxWidth` | number | `136` | 布局输出宽度（默认值仅占位） |
| `boxHeight` | number | `44` | 布局输出高度 |
| `offsetX` / `offsetY` | number | `0` | 用户拖拽累计偏移；布局时叠加到 `x/y` |

不变量（导入校验）：节点数 ≤ 10000；恰好一个 `parentId === ''` 的根且 `id === rootNodeId`；无环、父节点存在、id 唯一；`order`/`offsetX`/`offsetY` 必须有限数。

### 1.10 CanvasBoard / CanvasCard / CanvasEdge（白板）

| 类 | 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| CanvasBoard | `id` | string | `''` | 新建 `canvas-<uuid>` / 兜底 `canvas-<Date.now()>` |
| | `vaultId` | string | `'default-vault'` | |
| | `projectId` | string | `''` | |
| | `title` | string | `''` | |
| | `cards` | CanvasCard[] | `[]` | |
| | `edges` | CanvasEdge[] | `[]` | |
| | `createdAt` / `updatedAt` | number | `0` | |
| CanvasCard | `id` | string | `''` | `card-<uuid>` |
| | `title` | string | `''` | 画布上最多 10 字符 |
| | `content` | string | `''` | 画布上最多 13 字符（超出加省略号） |
| | `noteRefId` | string | `''` | 关联笔记 |
| | `noteRefTitle` | string | `''` | |
| | `x` / `y` | number | `60` / `60` | 卡片左上角坐标（非中心） |
| | `colorTag` | string | `'purple'` | 五色同导图；当前绘制未按色区分 |
| CanvasEdge | `id` | string | `''` | 新建 `edge-<Date.now()>` |
| | `fromId` / `toId` | string | `''` | 必须指向已存在卡片 |
| | `label` | string | `''` | 新建时取输入框，默认 `'关联'` |

### 1.11 GraphNode / GraphEdge（图谱投影）

| 类 | 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| GraphNode | `id` | string | `''` | 笔记 id / `map:<mapId>` / `tag:<tag>` |
| | `label` | string | `''` | 笔记展示标题 / 导图标题 / `#tag` |
| | `kind` | string | `'note'` | `note` / `mindmap` / `tag` |
| | `noteType` | string | `'quick'` | 仅 note 节点用于配色 |
| | `degree` | number | `0` | 建边时双方 +1 |
| | `x` / `y` | number | `0` | 归一化到 `[0,1]` |
| | `tags` | string[] | `[]` | 笔记标签副本 |
| | `snippet` | string | `''` | `extractSnippet(note).slice(0,72)` |
| GraphEdge | `sourceId` / `targetId` | string | `''` | |
| | `kind` | string | `'link'` | 实际取值 `link` / `mapRef` / `tag` |

### 1.12 MarkdownBlock（解析结果）

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | string | `''` | `block-<起始行>` / `live-block-<行>` |
| `kind` | string | `'paragraph'` | 见 §2.2；注释列了 h1..h3，实际还有 `hr`/`image`/`embed`/`ordered`/`table`/`formula` |
| `text` | string | `''` | 纯文本内容（表格为表头拼接，公式为 LaTeX 源） |
| `checked` | boolean | `false` | 仅 todo 使用 |
| `meta` | string | `''` | 语言名 / 标题级别数字 / 有序列表序号 / callout 类型 / 表格 JSON |
| `lineIndex` | number | `0` | 0 基行号（含 frontmatter 偏移） |

### 1.13 LexiWorkspaceTab 与编辑器控制器

| 类 | 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| LexiWorkspaceTab | `noteId` | string | 构造参数 | 标签页唯一标识（= 笔记 id） |
| | `controller` | LexiWorkspaceEditorController | `new` | 每个标签页独立编辑器实例与保存边界 |
| LexiWorkspaceEditorController | `ownerId` | string | `''` | 所属容器/面板 |
| | `flush` | `() => Promise<void>` | 空实现 | 立即落盘 |
| | `toggleReading` | `() => void` | 空实现 | 编辑/阅读切换 |
| | `format` | `(action: string) => void` | 空实现 | 走 `LexiEditingActions` |
| | `selection` | `() => string` | `''` | 当前选中文本 |
| | `selectionRange` | `() => LexiWorkspaceSelection` | `{0,0}` | 选区偏移 |
| | `focus` | `() => void` | 空实现 | 聚焦编辑区 |
| | `inspectorSnapshot` | `() => LexiWorkspaceInspectorSnapshot` | 空快照 | 右侧检查器数据 |
| | `revealHeading` | `(heading) => void` | 空实现 | 大纲跳转 |
| | `openTarget` | `(target: string) => Promise<void>` | 空实现 | 打开链接目标 |

`LexiWorkspaceSelection { start, end }` 均为 number，默认 0。
`LexiWorkspaceInspectorSnapshot { noteId, title, headings: OutlineHeading[], outgoing: NoteLink[], backlinks: NoteLink[], properties: NoteProperty[] }`。
关键设计约束（源码注释）：**每个打开的文档拥有自己的编辑器与保存边界；切换标签页绝不重新加载草稿。**

### 1.14 其他模型

| 类 | 字段 | 说明 |
| --- | --- | --- |
| `NoteRevision` | `id: string`、`savedAt: number`、`snapshot: NoteItem` | 历史快照（完整笔记副本） |
| `TagCount` | `name: string`、`count: number` | 标签云按 count 降序 |
| `LexiCollectionBackup` | `vaultId`、`bookmarks`（JSON 字符串）、`databases`（JSON 字符串） | 备份中的书签/数据库集合 |
| `LexiBackupPackage` | `format='LexiNote.Backup'`、`version=1`、`exportedAt`、`vaults`、`projects`、`notes`、`mindMaps`、`canvases`、`templateLibrary`（JSON 字符串）、`collections` | 全量备份包 |
| `NoteEditorRouteParam` | `restoreSelectionStart=-1`、`restoreSelectionEnd=-1`、`restoreSourceMode=false`、`launchAssistant=false`、`templateId`、`vaultId`、`projectId`、`noteId`、`createNew=false`、`deferCreationUntilInput=false`、`initialType='quick'`、`initialTier='simple'`、`initialTitle`、`initialNotebook`、`initialContent`、`externalFileMode=false`、`externalFileUri` | 编辑器路由参数 |
| `MindMapRouteParam` | `projectId`、`mapId`、`createNew=false`、`fromNoteId` | |
| `CanvasRouteParam` | `projectId`、`canvasId`、`createNew=false` | |
| `LexiCapture...` 系列 | 见 `LexiCapturedNoteSaveResult` | 分享剪藏，非本次移植必需 |

### 1.15 创建入口（`CREATE_ENTRIES`）

| kind | icon | 标题 | 说明文案 |
| --- | --- | --- | --- |
| `quick` | `note` | 快速笔记 | 灵感 · 待办 · 日记 |
| `study` | `study` | 学习笔记 | 公式 · 代码 · 大纲 |
| `markdown` | `markdown` | 专业 Markdown | 源码 · 双链 · 属性 |
| `mindmap` | `mindmap` | 思维导图 | 树形结构 · 大纲切换 |
| `canvas` | `canvas` | 自由白板 | 卡片 · 连线 · 拼贴 |
| `explore` | `graph` | 笔记关联 | 查看相关笔记与引用 |

### 1.16 种子数据（首启演示内容，摘要）

- 工作区 2 个：`个人知识库`（`default-vault`，日常灵感/课程/知识网络）、`开发项目库`（`dev-vault`，HarmonyOS 架构与技术复盘）。
- 思维导图 2 幅：`数据结构与算法体系`（right，10 节点，3 个分支带笔记引用）、`知萤个人知识工作流`（balanced，5 节点）。
- 白板 1 张：`算法与架构灵感白板`（3 卡片 / 2 连线，卡片位置 36,42 / 310,46 / 170,205）。
- 内置模板 6 个：每日记录、日程计划、代码笔记、学习笔记、会议纪要、项目规划；占位符 `{{date}} {{time}} {{title}} {{weekday}}`（weekday 为“星期X”，date 为 `YYYY-MM-DD`）。
- 种子笔记 5 篇（正文含双链、公式、代码块、callout、任务列表），标题与归属见下表。
- 笔记正文内容需由移植者逐篇搬运，本规格不再复述。

| 标题 | 笔记本 | noteType / editorLevel | 标签 | 置顶/收藏 |
| --- | --- | --- | --- | --- |
| 时间复杂度 | 计算机课程 | study / study | 学习/算法、考试重点 | 是 / 是 |
| 二叉树与递归遍历 | 计算机课程 | study / study | 学习/算法、树结构 | 否 / 是 |
| 动态规划核心模型 | 计算机课程 | study / pro | 学习/算法、动态规划 | 否 / 否 |
| 知萤 LexiNote 架构设计规范 | 产品与架构 | markdown / pro | 开发/鸿蒙、知识管理 | 是 / 是 |
| 今日灵感与待办速记 | 速记收件箱 | quick / simple | 日常/灵感、待办 | 否 / 否 |

---

## 2. Markdown 能力清单

### 2.1 解析管线（顺序很重要）

1. `LexiFrontmatter.parse` 切出 YAML 头，得到 `bodyLineOffset`（正文起始行）。
2. 块解析 `MarkdownEngine.parseBlocks`：**逐行**识别，不合并多行段落（每个非空行是独立段落）。
3. 行内解析 `MarkdownEngine.inlineSpans`：先用 `LexiMathSyntax.inlineTokens` 把公式替换为等长占位符 `\uFFFC`，再跑行内正则，最后把占位区间还原成 `math` / `math-display` 片段。
4. 大纲 `extractOutline` 与正文解析共享同一套围栏跳过规则（围栏内的 `#` 不算标题）。

### 2.2 块级语法

| 语法 | 识别规则 | block.kind | meta | 备注 |
| --- | --- | --- | --- | --- |
| ATX 标题 | `^(#{1,6})\s+(.+)`，`#` 后必须有空格；允许结尾 `###` 被吞掉 | `h1`/`h2`/`h3` | 实际级别数字 | **h4~h6 一律降级为 `h3` 渲染**，级别存在 `meta` |
| 代码围栏 | 行首连续 ≥3 个反引号或 ≥3 个波浪号，可带语言 | `code` | 语言（首个空白前） | 语言为 `math`/`katex` 时转为 `formula`；未知语言原样保留并走纯文本高亮 |
| 公式块（围栏） | 同上，lang = math/katex | `formula` | — | 围栏内若再包 `$$…$$`/`\[…\]` 会剥离外层 |
| 公式块（定界） | 行首 `$$` 或 `\[`，可跨行；遇 `#`/围栏提前终止 | `formula` | — | 结束符后只允许空白或 `%` 注释 |
| 公式块（环境） | 行首 `\begin{env}`，env ∈ §2.8 列表 | `formula` | — | 支持同名嵌套；结束行尾只允许 `\tag{...}` 与 `%` 注释的任意组合 |
| 表格 | 当前行含竖线，下一行每格匹配 `^:?-{3,}:?$`，且表头格数 = 分隔行格数 | `table` | 表格 JSON（`rows`+`alignments`） | 对齐：`:--:` 居中、`--:` 右、其余左；正文行补/截到表头列数 |
| 分隔线 | 整行由 `*`/`-`/`_` 组成且 ≥3 个（允许中间空格） | `hr` | — | 卡片摘要里跳过 |
| 图片 | 整行 `![alt](src "title")` | `image` | src | 支持 `<...>` 包裹 URL、`"title"` |
| 嵌入 | 整行 `![[target]]`（可带别名，见 §2.9） | `image` 或 `embed` | target | target 以图片扩展名结尾（png/jpg/jpeg/gif/webp/svg/bmp/avif）→ image，否则 embed |
| 有序列表 | `^(\d{1,9})[.)]\s+(.+)` | `ordered` | 序号字符串 | 不解析层级，缩进被 trim 掉 |
| 待办 | `^[-*+]\s+\[[xX]\]` 或 `\[ \]` | `todo` | — | `checked` 布尔；标记后必须有空白或行尾 |
| 无序列表 | 行首 `- ` / `* ` / `+ ` | `bullet` | — | 同上，不保留缩进层级 |
| 标注 | 行首 `> [!Type]` | `callout` | Type（原样大小写） | 连续 `>` 行并入正文 |
| 引用 | 行首 `>` 或 `> ` | `quote` | — | 遇到 `> [!` 即停止（交给 callout） |
| 段落 | 其他非空行 | `paragraph` | — | 每行独立成块 |
| 空行 | — | 跳过 | — | |

**明确未支持**：Setext 标题、缩进式代码块（4 空格）、定义列表、脚注定义与引用渲染、HTML 块、多行段落合并、列表嵌套层级、引用内嵌块；除 frontmatter 外没有其他元数据块（`---` 只作分隔线）。

### 2.3 行内语法

正则按以下顺序匹配（前者优先；`id` 形如 `mark-<偏移>`）：

| 序号 | 语法 | kind | 说明 |
| --- | --- | --- | --- |
| 1 | `` `code` `` | `code` | 单反引号，不跨行；反引号内不解析其他语法 |
| 2 | `[[target]]`（可带别名，见 §2.9） | `link` | `target` 可含 `#anchor`；别名取竖线之后全部内容，可含多个竖线 |
| 3 | `[text](url "title")` | `url` | url 内不允许空白和 `)`；title 可选 |
| 4 | `**bold**` | `bold` | |
| 5 | `__bold__` | `bold` | |
| 6 | `==highlight==` | `highlight` | 默认高亮（brand_soft） |
| 7 | `~~strike~~` | `strike` | |
| 8 | `*italic*` | `italic` | 不跨行 |
| 9 | `_italic_` | `italic` | 不跨行 |
| 10 | `<mark data-color="颜色">text</mark>` | `highlight` + `target=颜色` | 六色：red、orange、yellow、green、blue、purple |
| — | `$...$`、`\(...\)`、`$$...$$`、`\[...\]`、`\begin{env}` | `math` / `math-display` | 先于上面的规则被遮罩 |
| — | `%%注释%%` | 无 | 仅插入语法，**渲染层不特殊处理**（按普通文本显示） |

**行内高亮色值**（渲染透明度为 0x40 叠加）：

| 颜色 | ARGB |
| --- | --- |
| red | `#40F87171` |
| orange | `#40FB923C` |
| yellow | `#60FACC15` |
| green | `#404ADE80` |
| blue | `#4060A5FA` |
| purple | `#40C084FC` |

**链接样式**：`link`/`url` 片段用主题强调色 + 下划线；`strike` 删除线；`code` 用等宽字体 + `soft_surface` 背景；`highlight` 用上表底色。公式片段在 `LexiMathView` 中渲染为位图。

`target` 的跳转只对 `link`（`[[...]]`）与 `url` 生效：`link` 直接作为内部目标（id 或标题）；`url` 先尝试按知萤协议 `lexinote://<host>[/<path>][?query]` 解析为内部动作，命中生态深链（http/https、mailto、`lexiglow://`、`lumikit://` 等）则交系统打开，其余一律当内部目标并去掉 `.md` 后缀；URI 含空白/反斜杠/控制字符或超过 4096 字符时直接拒绝。打开失败提示 `无法打开此链接`。

### 2.4 Callout（标注）

- 语法：`> [!TYPE]` 可带标题文本，后续 `>` 行为正文。
- `TYPE` 捕获 `[A-Za-z]+`，**不做大小写归一**；缺失时 `meta = 'NOTE'`。
- 渲染：统一卡片（`brand_soft` 背景、圆角 12、内边距 14），首行显示 `✦ <TYPE>`（11pt 粗体、brand 色），正文 14/23。
- **所有类型样式完全相同**：没有按 NOTE/TIP/WARNING/IMPORTANT/CAUTION 区分颜色、图标或折叠。“折叠提示框”只出现在英文本地化文案里，当前渲染不折叠。
- 已知类型（种子与代码使用）：`NOTE`、`TIP`；解析器接受任意字母串。

### 2.5 任务列表

- 仅支持 `- [ ]` / `- [x]`（`*`、`+` 亦可），必须行首；`[xX]` 为勾选。
- 渲染为 `Checkbox` + 文本；勾选后文本加删除线并降为次要色。
- 交互：点击复选框回调 `onToggleTodo(lineIndex)`，由外层按行号改写原文标记。
- 不支持嵌套子任务、任务优先级、截止日期等扩展。

### 2.6 表格

- 表头 + 分隔行必需；分隔行每格 `:?-{3,}:?`，据此得到 `left|center|right`。
- 单元格拆分 `splitTableRow`：去首尾 `|`（`\|` 结尾不算），支持 `\|` 转义、反引号内 `|` 不拆分、公式 token 整体跳过。
- 行内格式在单元格内仍生效（复用行内解析器）。
- 渲染：横向滚动、单元格最小高 46、表头 `brand_soft`、斑马纹 `soft_surface`、单元格宽 156。
- 卡片摘要：取前 3 行，每行用 ` · ` 连接，行间用 `；`。

### 2.7 代码块与高亮

- 围栏信息串：语言 = 首个空白前文本，其余保留在 `extra`；`LexiCodeFence.update` 在改写正文时会自动加长围栏，避免正文中出现同级围栏。
- 归一化别名 → 21 种已知语言：
  `javascript`(js/jsx/node/mjs/cjs)、`typescript`(ts/tsx)、`arkts`(ets)、`python`(py/python3)、`shell`(sh/bash/zsh/console)、`cpp`(c++/cc/cxx/hpp)、`csharp`(c#/cs)、`yaml`(yml)、`html`(htm)、`xml`、`svg`、`go`(golang)、`rust`(rs)、`kotlin`(kt)、`ruby`(rb)、`json`、`sql`、`java`、`c`、`css`、`swift`。
- 空/`code`/`auto`/`text`/`txt`/`plain`/`plaintext`/`none` → 无语言（纯文本，标签“未指定语言”）。
- 高亮 token 类型：`keyword`、`string`、`number`、`comment`、`function`、`tag`、`property`、`punctuation`、`text`。
- 词法约束：单次最多 4000 token、扫描前 60000 字符；触顶后其余源码并入一个 `text` token（视觉上等同纯文本）；注释支持 `//`、`/* */`、`#`（python/shell/yaml/ruby）、`--`（sql）、`<!-- -->`（markup）；字符串支持单/双/反引号与 Python 三引号；JS/TS/ArkTS 额外识别正则字面量。
- 代码块渲染：卡片（`soft_surface`、圆角 12、内边距 14），带语言标签与“复制/编辑”动作。

高亮色值（亮/暗）：

| kind | 亮色 | 暗色 |
| --- | --- | --- |
| keyword | `#6532A3` | `#CEB5FF` |
| string | `#176544` | `#9AD8B2` |
| number | `#8C3B0E` | `#F4BC83` |
| comment | `#596273` | `#AAB2C7` |
| function / tag | `#1C4F91` | `#96CAFF` |
| property | `#8A3460` | `#F0B2CC` |
| text | `#231B36` | `#F5F3FB` |

### 2.8 公式（`LexiMathSyntax`）

**定界符**

- 行内：`$...$`、`\(...\)`
- 块级：`$$...$$`、`\[...\]`、`\begin{env}...\end{env}`

**`$` 的防误判规则**（重要，必须照搬，否则中文货币/价格会变成公式）：

1. 内容 trim 后为空 → 不是公式。
2. 结束 `$` 之后紧跟数字 → 不是公式（`$5 and $10`）。
3. 形如“数字 + 量词/标点/中文/and|or|to|per”，且内部没有任何 `\命令` 或 `= ^ _ { } < >` → 不是公式。
4. 首尾都无空格 → 是公式；只有一侧有空格 → 不是；两侧都有空格时，内部需含 `\命令` 或 `_ ^ = < > + - * / { }`，且不是“数字 + 空格 + 英文/中文”这种货币写法。
5. 单 `$` 不跨行；花括号与 `\begin/\end` 深度必须配平才允许闭合；反斜杠转义的 `$` 不闭合。
6. 反引号内、`[[...]]` 内、`](...)` 内不识别 `$`。

**支持的环境名**（扫描器接受，渲染器能力另计）：
`equation`、`equation*`、`align`、`align*`、`aligned`、`alignat`、`alignat*`、`alignedat`、`gather`、`gather*`、`gathered`、`flalign`、`flalign*`、`multline`、`multline*`、`split`、`cases`、`cases*`、`dcases`、`dcases*`、`rcases`、`rcases*`、`numcases`、`subnumcases`、`matrix`、`pmatrix`、`bmatrix`、`Bmatrix`、`vmatrix`、`Vmatrix`、`smallmatrix`、`array`、`subarray`、`CD`、`eqnarray`、`eqnarray*`。
其中 `alignment/display` 类环境（equation/align/alignat/gather/flalign/multline/numcases/eqnarray 及其带星版本）即使写在 `\(...\)` 内也按块级（displayMode）渲染。

**渲染实现**：`rawfile/lexi-math/renderer.html` + **KaTeX**（`output: 'htmlAndMathml'`、`throwOnError: true`、`strict: 'ignore'`、`trust: false`、`maxExpand: 1000`、`maxSize: 20`、每次渲染独立 `macros: {}`）。失败时降级为 `math-error` 并原样显示 LaTeX 文本。
产物经 WebView `window.lexiBitmap()` 回传 PNG（base64），按 `SHA256("mathjax-3.2.2-v2\n<display>\n<dark>\n<source>")` 内容寻址缓存：内存 128 条，磁盘 `filesDir/math-bitmap-cache-v2/<hash>.json`；单条上限 4096×2048、Base64 ≤ 16000000 字符，12 秒超时。
注意：缓存 key 文案写着 mathjax，实际渲染器是 KaTeX；KaTeX 覆盖矩阵/对齐/分段等常用环境，但 `CD`、`numcases`、`eqnarray` 等少数环境并不实现，会走错误降级（具体以随包 KaTeX 版本为准）。

### 2.9 双链、嵌入与反链

**语法**：`[[目标]]`、`[[目标|显示名]]`、`[[目标#锚点]]`、`[[目标#锚点|显示名]]`、`![[目标]]`（嵌入）。

**解析（`buildNoteLinks`）**

- 只处理 `trashedAt === 0` 的笔记。
- 目标匹配：同 `vaultId` 内，`candidate.id === targetText` **或** `candidate.title.trim().toLowerCase() === targetText.toLowerCase()`。
- 未命中仍产出一条 link（`targetId = ''`，`targetTitle = 原文目标`），用于“未解析链接”展示。
- 去重键：`sourceId + targetTitle + anchor`（同文重复链接只留一条）。
- `anchor` 存 `#` 之后全部内容；`displayText` 存 `|` 之后全部内容，无别名时等于 target。

**反链**：`links.filter(l => l.targetId === noteId)`（仅已解析）。出链：`links.filter(l => l.sourceId === noteId)`。

**未链接提及（`findUnlinkedMentions`）**

- 目标标题 `trim().length >= 2`，同工作区，且源笔记正文包含该标题（区分大小写的子串匹配）。
- 已被显式链接（`targetId` 或 `targetTitle` 命中）则跳过。
- 摘要：命中前 16 字符、后 24 字符，换行替换为空格；最多返回 16 条。

**重命名修复（`renameLinksInMarkdown`）**

- 保存时若标题变化，扫描同工作区其他笔记：`[[旧标题...]]` 中 target（`#`/`|` 之前部分）忽略大小写等于旧标题时，替换为新标题，保留 `#锚点` 与 `|别名`。
- 同时把导图节点 `noteRefTitle` 批量更新为新标题（按 `noteRefId` 匹配）。

**嵌入（embed）渲染**

- 解析目标正文：无锚点时取 body 前 800 字符；有锚点时按标题文本（小写、空白转 `-`）匹配大纲标题，取该标题到下一个同级或更高级标题之间的正文前 800 字符。
- 卡片显示 `↗ 标题` + 摘要，点击打开目标笔记。

**链接点击**：`link` 片段直接调 `onOpenTarget(target)`（id 或标题，由外层解析）；`url` 片段按 §2.3 的知萤协议/外部深链规则分流；非链接片段点击则进入该块编辑。

### 2.10 Frontmatter（受限 YAML）

| 规则 | 内容 |
| --- | --- |
| 起始 | 文件必须以 `---\n` 开头（先去掉 BOM、统一 CRLF→LF） |
| 结束 | 单独一行 `---` 或 `...` |
| 字段行 | `key: value`；key 可为裸串、单引号或双引号串 |
| 标量解析 | 去空白；`#`（前面是空白）后为注释；双引号走 `JSON.parse`；单引号内 `''` → `'`；`null` / `~` → 空串 |
| 列表 | 行内 `[a, b, "c"]`（按引号外的逗号切分）或块状 `  - a`；一律转为 JSON 数组字符串存入 `properties` |
| 特殊键 | `tags` 与 `tag` 合并为标签（去掉开头 `#`，去重）；不进入 `properties` |
| 不支持（保留原文、只读） | 块标量（`>` 或竖线）、流式映射 `{}`、锚点/别名 `&`/`*`、标签 `!`、嵌套映射 |
| 序列化 | 始终输出 `---\n…\n---\n<body>`；`tags` 输出为 JSON 数组；值被修改的属性输出为 `"key": "value"`（JSON 引号）；未修改的字段保留原始行；未知/不支持字段原样保留；`properties` 中不存在且非 tags 的标量字段会被**丢弃** |
| 应用 | 有 frontmatter 时用解析结果覆盖 `note.tags` / `note.properties`；从有到无则清空两者 |

示例（输出形态）：

```
---
tags: ["学习/算法","待办"]
"课程": "数据结构"
自定义字段: 保留原样
---
# 标题
```

### 2.11 实时预览编辑行为（`LexiLiveMarkdown`）

| 能力 | 规则 |
| --- | --- |
| 块范围 | `rangeAt(offset)`：按解析块定位，范围**不含尾随换行**，避免替换段落时吞并相邻块；找不到块时退化为当前行 |
| 行范围 | `rangeForLine(lineIndex)` |
| 区间块解析 | `blocksBetween(start,end)` 结果行号加偏移，id 前缀 `live-block-` |
| 替换 | `replace(content,start,end,snippet)` 返回新内容与新光标（`start + snippet.length`） |
| 光标映射 | `changedCaret` 以“公共前缀/后缀”算最小变更点；`mapOffset` 在保存后正文被规范化（如 frontmatter 重写）时映射选区 |
| 回车推进 | `shouldAdvance(source, kind)`：普通块回车即新建；表格/callout/引用/竖线开头要**空行**才退出；围栏要闭合围栏；`$$`/`\[`/`\begin{}` 要公式块真正结束 |
| 正文判空 | `hasBody(content)`：frontmatter 之后 trim 非空 |
| 源码坐标 | 始终基于原始 Markdown（含被隐藏的 YAML），保证替换不漂移 |

### 2.12 编辑器三级（simple / study / pro）

仅影响工具条密度与排版（`editorLevel`）；解析与存储完全一致。`noteType` 影响默认层级与列表配色/图标（`quick`/`study`/`markdown`）。三种编辑器视图：**实时预览（live）/ Markdown 源码（source）/ 阅读视图（reading）**，由 `editor-default-mode`、`editor-default-view` 设置默认值。

---

## 3. 搜索

### 3.1 查询语法（`LexiSearch.parse`）

- 分词：按空白切分，支持双引号/单引号包裹短语（正则 `(?:[^\s"']+|"[^"]*"|'[^']*')+`）。
- 排除：`-term` → `excluded = true`。
- 字段限定：`field:term`，仅当 field ∈ `tag`、`type`、`notebook`、`path` 或形如 `[属性名]` 时生效；否则整个 `field:term` 当作普通文本。
- 词面统一 `toLowerCase()` 并去掉首尾引号。
- 空词丢弃；无有效词 → 匹配全部。

### 3.2 匹配字段与规则（`LexiSearch.matches`）

| 查询 | 匹配逻辑 |
| --- | --- |
| 普通词 | `title \n content \n notebook \n tags.join(' ')` 拼接后小写包含 |
| `tag:x` | 标签小写**等于** `x` 或以 `x/` 开头（层级标签） |
| `type:x` | `noteType` 小写等于 `x` |
| `notebook:x` | `notebook` 小写包含 |
| `path:x` | `path` 小写包含 |
| `[key]:v` | `properties` 中存在 `key`（小写全等）且 `propValue` 小写包含 `v` |
| `-term` | 上述结果取反 |

多个词为 AND；任一词不满足即整体不匹配。大小写全部折叠（中文不受影响）。不做分词/词干化/拼音/模糊匹配。

### 3.3 排序（`LexiSearch.rank`，越小越靠前）

| 情形 | 分值 |
| --- | --- |
| 查询为空 | 0 |
| 完全相等 | 0 |
| 子串命中 | `1 + 命中位置` |
| 字符按顺序出现在标题中（子序列/首字母） | `100 + 间隔总数` |
| 不命中 | `-1` |

命令面板（`LexiCommandPalette`）：命令按 `rank(标题)` 或 `id.includes(query)` 过滤；文件结果合并笔记/导图/白板后按 rank 升序（`-1` 视为 1000），截断 60 条。笔记额外允许 `matches()` 命中（正文命中也能出现）。

### 3.4 库/列表排序

- 默认（`updated`）：`pinned` 优先，再按 `updatedAt` 降序。
- `title`：按 `displayTitle` 的 `localeCompare`。
- `created`：按 `createdAt` 降序。
- 标签云：按 `count` 降序。
- 回收站：按 `trashedAt` 降序。
- 导图/白板：按 `updatedAt` 降序。

### 3.5 摘要截取（`previewSpans` / `extractSnippet`）

1. 依次消费块；跳过 `hr`；若首个块是 `h1` 且文本等于标题则跳过。
2. 块文本变换：表格 → 前 3 行（` · ` 连接，`；` 分隔）；todo → `☑/☐ + 文本`；bullet → `• 文本`；ordered → `序号. 文本`；image → alt 或 `图片`（按字面量）；embed → `引用：标题或target`；formula → `数学公式`；code → 原样（literal）。
3. 折叠空白、trim；块间用单空格连接；无查询时累计 ≥128 字符即停。
4. 有关键词时：在拼接纯文本上做小写查找；命中则窗口 `[match-18, match+len+42]`，未命中则 `[0,86]`；两端越界处补 `…`。
5. 按 span 边界裁剪，保留行内样式；无内容时回退文案 `点击继续记录内容…`。
6. `extractSnippet` 即拼接后的纯文本（图谱节点再截 72 字符）。

---

## 4. 知识图谱

### 4.1 节点与边生成（`GraphLayout.topology`）

- 仅取 `trashedAt === 0` 的笔记，全部生成 `kind: 'note'` 节点；`label = displayTitle`，`snippet = extractSnippet().slice(0,72)`，`tags` 复制。
- 双链边：仅当 `link.targetId` 非空时加边，`kind: 'link'`。
- 导图（`includeMaps`，默认开）：未删除导图生成 `map:<id>` 节点，`label = title || '未命名导图'`，`snippet = '<n> 个节点的思维导图'`；遍历其节点，`noteRefId` 非空则加 `mapRef` 边（导图 → 笔记）。
- 标签（`includeTags`，默认关，持久化键 `graphShowTags`）：每个标签生成 `tag:<name>` 节点，`label = '#name'`，`snippet = '标签'`，笔记与标签之间加 `tag` 边。
- 加边规则：`source === target` 跳过；两端节点必须存在；**以无序对 `<a>|<b>` 去重**（先生成的 kind 生效）；成功后双方 `degree++`。
- 常见默认规模：节点上限未硬编码，但布局在 >320 节点时采样；力导向为 O(n²) 的近似。

### 4.2 力导向参数（`LexiGraphForce.layout`）

| 参数 | 取值 |
| --- | --- |
| 初始位置 | 黄金角螺旋：`angle = π(3-√5)`，`r = sqrt((i+0.5)/n)`，`(cos, sin)`；n=1 时半径 0 |
| 弹簧常数 | `spring = sqrt(4/n) * 0.9` |
| 迭代次数 | n>320 → 90；n>160 → 120；n>80 → 160；否则 260 |
| 斥力 | 每对节点 `f = spring² / d`（沿连线方向） |
| 采样（n>320） | 每个节点访问 `samples = min(96, n-1)` 个邻居，距离步长 `(n-1)/samples`，并按 `iteration*17` 轮转；力乘以 `(n-1)/(2*samples)` |
| 引力（边） | `f = d² / spring`，沿连线方向 |
| 向心 | 每轮位移减去 `pos * 0.6 * spring` |
| 温度 | 初值 `0.18`，每轮 `*= 0.975`，下限 `0.004`；单步位移不超过温度 |
| 归零距离 | `< 0.0001` 时以 `0.001*(i-j), 0.001` 扰动 |
| 归一化 | 取 x/y 各自 min/max，线性映射到 `[0,1]`（span 最小 0.0001） |
| 确定性 | 全流程无随机数；同输入必得同布局 |
| 后台执行 | `taskpool` 传入 `{nodeIds, edges}` JSON，返回坐标数组；失败/超时回退黄金角布局，**绝不在 UI 线程跑 O(n²)** |

### 4.3 绘制（`LexiGraphView`）

- 画布内边距 34；`px = 34 + x*(w-68)`，`py = 34 + y*(h-68)`。
- 节点颜色：`mindmap` → `brand_ink`；`tag` → `text_secondary`；`study` → `success`；`markdown` → `warning`；其余（quick）→ `brand`。
- 半径：`base = tag ? 4 : 6`，`r = base + min(degree, 8) * 1.3`。
- 选中态：外圈半径 `r+8`，填 `brand_soft`。
- 标签：节点数 ≤26 时全显；否则仅选中或 `degree >= 3` 显示；超过 12 字符截断加 `…`；字号 11（选中 12 粗体），居中于节点下方 `r+14`。
- 边：默认 `text_secondary @0.28`、线宽 1.1；与选中节点相连时 `brand @0.85`、线宽 2；`link` 实线，`mapRef`/`tag` 虚线 `[4,4]`。
- 命中测试：取距圆心（扣除半径）最近且 <26px 的节点。

### 4.4 交互

| 交互 | 现状 |
| --- | --- |
| 点击节点 | 选中（`onSelect(id)`），高亮关联边 |
| 点击空白 | `hitTest` 返回空串 → 清空选择 |
| 全局/局部 | `graphScope` 取 `global` 或 `local`；局部模式取“焦点 + 一跳邻居”子图并**重新布局**（`GraphLayout.local`） |
| 显示导图/标签 | 菜单开关；开关状态只有 `graphShowTags` 持久化，`graphShowMaps` 仅会话内 |
| 拖拽节点 | **未实现** |
| 缩放/平移 | **未实现**（画布随容器尺寸重算） |
| 双击/右键 | 未实现 |
| 无障碍 | `accessibilityText` 播报节点/边数量 |

> 移植提示：macOS 上若要加拖拽/缩放，应在归一化坐标之外引入视图变换，避免破坏 `[0,1]` 持久语义（当前坐标不落盘，可自由扩展）。

---

## 5. 思维导图

### 5.1 布局（`MarkdownEngine.computeMindMapLayout`）

先算可见节点：从 `rootNodeId`（找不到则 `nodes[0]`）开始；子节点按 `order` 升序；`collapsed` 节点自身保留、子树不展开。叶子权重 `measureLeaves`：折叠或无子节点记 1，否则子节点权重和。

**right（默认，向右树）**

- `vGap = 68`，`hGap = 206`
- `x = 124 + level * 206`
- `y = 64 + (startLeaf + span/2) * 68`
- 宽度 `clamp(len*14 + 34, 118, 192)`；高度：有 note 或 noteRef → 52，否则 42

**balanced（双向）**

- 根的一级子节点按索引奇偶分组：偶数 → 右，奇数 → 左
- `vGap = 68`，`hGap = 205`，`centerX = 480`
- `centerY = max(210, max(3, 右叶数, 左叶数) * 68 / 2 + 48)`
- 根：宽度 `clamp(len*15 + 36, 132, 196)`、高 48、位于 `(480, centerY)`
- 子节点：`x = 480 ± level * 205`，`y = 该侧顶部 + (startLeaf + span/2) * 68`；宽 `clamp(len*13+34, 114, 184)`，高 52/42

**org（组织架构，自上而下）**

- `hStep = 166`，`vStep = 92`
- `x = 80 + (startLeaf + span/2) * 166`
- `y = 76 + level * 92`
- 宽 `clamp(len*14 + 34, 116, 184)`；高 54/42

**统一收尾**：所有可见节点叠加 `offsetX/offsetY`（非有限数按 0）。布局结果写回节点并成为视图坐标（中心点坐标，不是左上角）。

### 5.2 配色与绘制

| 语义 | 色值 |
| --- | --- |
| 根节点强调 / 根填充 | 强调 `#6E44D9`，填充 `palette.brand` |
| purple（紫晶） | `#6E44D9` |
| indigo（靛蓝） | `#5258E8` |
| teal（青翠） | `#2C8C7C` |
| amber（琥珀） | `#C7812C` |
| rose（暮粉） | `#C44D78` |

- 画布：点阵背景（间距 32、点 2px）；`translate(panX,panY)` + `scale(zoomScale)`。
- 连线：2.2px，子节点强调色。`org` 用贝塞尔，控制点为 `(父x, 中点y)` 与 `(子x, 中点y)`，形成“父底 → 子顶”的竖直进出；其余布局用水平进出，控制点为 `(中点x, 父y)` 与 `(中点x, 子y)`。
- 节点：圆角 12；根填 `brand`、选中填 `workspace_selection`、其余 `surface`；边框 1.3（选中 2.5，选中加 12px 阴影）；根文字 `inverse_text` 粗 14，其余 `text_primary` medium 13，标题超 11 字符截断为 10 + `…`。
- 有 note/noteRef 时文字上移 6，下方 10px 显示 `🔗 笔记标题(前9字)` 或 `✦ 备注(前9字)`。
- 折叠且有子节点：节点右侧 10px 处画半径 10 的圆，显示 `+N`。

### 5.3 交互

| 操作 | 行为 |
| --- | --- |
| 点击节点 | 选中（`selectNode`），检查器联动 |
| 拖拽节点 | 命中节点则移动**整个分支**（子树所有节点累加 `offsetX/offsetY`）；拖拽开始记录快照，取消则回滚快照与撤销栈 |
| 拖拽空白 | 平移画布（`panX/panY`） |
| 缩放 | 按钮 ±0.15，范围 `0.1 ~ 1.6`；点百分比按钮 = 适配全部节点（`scale = clamp(min((w-64)/宽, (h-64)/高), 0.1, 1)`，居中） |
| 新增子主题 | 新建 `node-<uuid>`，`parentId=选中`，文本 `子主题 N`，展开父节点；根的一级子节点按 5 色轮转，更深层继承父色 |
| 新增同级 | 根节点上执行时退化为“新增子主题”；文本 `同级主题 N`，`order = 当前+1`，继承当前色 |
| 删除 | 删除整棵子树（含自身），根节点禁止（提示 `中心根节点不能删除`） |
| 折叠/展开 | 仅有子节点时可切换；根节点不可折叠 |
| 调序 | 与相邻同级交换 `order`；相等时先重排 1..n 再交换 |
| 改文字 | 检查器 `TextInput` 实时写 `text`；同时改文档标题时根节点文本跟随 |
| 改配色 | 检查器五色按钮，直接改 `colorTag` |
| 关联笔记 | 从笔记选择器写入 `noteRefId` + `noteRefTitle` |
| 由节点建笔记 | 新建笔记：标题=节点文字、笔记本 `导图衍生笔记`、`noteType/editorLevel=study`、标签 `['导图关联']`、正文为 `# 标题` + 可选 `> 备注` + 来源说明；随后自动关联并打开 |
| 撤销/重做 | 节点 JSON 快照栈，上限 40，600ms 内合并；拖拽也入栈 |
| 大纲视图 | 列表模式：左侧 8px 色点、层级缩进 `12 + level*18`、根 16pt 其余 14pt、显示备注、带 `🔗 标题` 跳转按钮 |
| 保存 | 变更后 280ms 防抖；结构性操作立即保存；状态文案 `正在自动保存…` / `已保存到本机` / `保存失败 · 点击重试` |

### 5.4 与笔记的关系

- 单向弱引用：节点 → 笔记（`noteRefId`/`noteRefTitle`），不写入笔记正文，也不产生 `NoteLink`。
- 笔记重命名会同步所有导图节点的 `noteRefTitle`；笔记删除**不会**清理引用（悬空引用保留，点击时按“笔记不存在”处理）。
- 图谱把 `mapRef` 作为关系边；复制工作区/项目时会按 id 映射重写 `noteRefId`。
- “将当前笔记转为思维导图”（命令 `convert`，`markdownToMindMapNodes`）：
  - 根 = `title || '核心主题'`，`rootNodeId='root'`，`noteRefId=noteId`，`noteRefTitle=title`，`colorTag='purple'`。
  - `# H1` → 根的子节点；`## H2` → 最近一个 H1 的子节点；`### H3` 或 `- 列表` → 最近一个 H2 的子节点。
  - 跳过空行与三反引号**分隔行**（不跟踪围栏状态，代码块内的 `#`/`- ` 行仍会被解析成节点）；节点文本截断 32 字符；待办前缀 `[ ]`/`[x]` 去掉；总节点数上限 48（不含根）。
  - 颜色按 `order % 5` 循环；`order` 从 1 递增。
  - 若除根外没有节点，生成 3 个默认分支：`核心要点`、`关联知识`、`行动清单`。

### 5.5 导出

- `导出导图 JSON`：`JSON.stringify(doc, null, 2)`，文件名 `<title>.json`。
- `导出 Markdown 大纲`（`mindMapToMarkdownOutline`）：首行 `# <doc.title>`；深度 ≥1 的节点按 `  `×（depth-1）缩进输出 `- <text>`，有笔记引用追加 ` → [[noteRefTitle]]`，有备注追加 ` （note）`；先序遍历（同 `order`）。
- 导图还会随外部文件夹写到 `<root>/思维导图/<id>.mindmap.json`（见 §7.2）。

---

## 6. 白板

### 6.1 数据与结构

见 §1.10。`CanvasBoard` 是卡片与连线的唯一容器；卡片坐标是**左上角**（与导图中心坐标不同），尺寸固定 `154 × 74`、圆角 14。

### 6.2 渲染

- 画布点阵：间距 28、点 2px。
- 空态文案：`点击上方「新增卡片」开始`（画布中心，14px）。
- 自适应：首次加载且 `!viewFitted` 且有卡片时，按卡片包围盒计算 `scale = min(1, (w-32)/宽, (h-32)/高)` 并居中；之后保持用户缩放。
- 卡片：选中填 `workspace_selection`、描边 2.4 brand；否则 `surface`、描边 1.2 divider。标题粗 12（截 10 字，左上 12/22），正文 10（截 13 字，12/42），有 `noteRefTitle` 时在 12/60 显示 `🔗 标题(前9字)`。
- 连线：从源卡片中心到目标卡片中心的直线（无箭头），`brand` 2px；`label` 非空时在两点中点上方 6px 居中显示（10px）。

### 6.3 交互

| 操作 | 规则 |
| --- | --- |
| 新增卡片 | 标题 `灵感卡片 N`；内容占位；位置=当前视口中心换算到画布坐标，先减 `(77, 37)` 回到左上角，再按 `cards.length % 4` 乘以 `(42, 86)` 递增；颜色按 `purple/indigo/teal` 轮转 |
| 选择卡片 | 命中测试：矩形包含点（`x..x+154`、`y..y+74`），逆序遍历 |
| 拖拽卡片 | 更新 `x/y`，触摸取消则回滚到按下时坐标 |
| 拖拽空白 | 平移画布 |
| 缩放 | 适配按钮（重新 fit）；当前没有独立缩放按钮 |
| 编辑卡片 | 检查器改标题/内容（内容为纯文本，画布只显示截断） |
| 关联笔记 | 选择笔记写入 `noteRefId/noteRefTitle` |
| 连线 | 选中卡片 A → 选择目标卡片 B → 若已存在 A↔B 的边（**无向判断**）则删除并提示 `已移除卡片连线`；否则以输入框文字（空则 `关联`）为 label 新建，提示 `已建立卡片连线` |
| 删除卡片 | 需同步删除引用该卡片的边（导入校验要求边两端卡片存在） |
| 自动保存 | 变更后 320ms 防抖；立即保存用于结构操作；状态 `已保存 · N 张卡片` / `保存失败，请重试` |

### 6.4 导出

- PNG：对当前视口执行 `getPixelMap(0,0,w,h)` → `image/png` 质量 100 → 文件名 `<board.title>.png`（`LexiExportService.saveBytes` 会清洗 `\/:*?"<>|`）。
- JSON：`<board.title>.json`，内容 `JSON.stringify(board, null, 2)`，走文档选择器。

---

## 7. 存储

### 7.1 双层结构

1. **文件即真相**：正文以标准 Markdown 落盘；外部文件夹可绑定时写到用户目录，未绑定时写到应用沙箱。
2. **RDB 镜像/索引**：`lexinote.db`（securityLevel S2）保存可查询元数据、正文副本与 KV 配置，用于快速列表与事务。文件是主副本，索引可由文件重建；反之索引缺失时列表会回退到 `kv_store.notes` 的全量 JSON。老版本仅有 `kv_store` + `link_index`，v2 起有 `notes_meta` / `notes_content`。

| 表 | 列 |
| --- | --- |
| `kv_store` | `key TEXT PK`、`value TEXT`、`updated_at INTEGER` |
| `link_index` | `source_id`、`target_id`、`target_title`、`anchor`、`display_text`（无主键，按 source 先删后插） |
| `notes_meta` | `id PK`、`vault_id`、`project_id`、`title`、`path`、`tags_json`、`properties_json`、`snippet`、`updated_at`、`metadata_json` |
| `notes_content` | `id PK`、`content` |

索引：`notes_scope(vault_id, project_id, updated_at)`、`links_by_source(source_id)`。

KV 键（重要）：`notes`（旧版全量 JSON）、`mindmaps`、`canvases`、`projects`、`vaults`、`bookmarks:<vaultId>`、`databases:<vaultId>`、`history:<noteId>`、`templateLibrary:v1`、`hotkeyOverrides`、`graphShowTags`、`lastBackup`、`noteRedirect:<oldId>`、以及按工作区加前缀的偏好（`LexiWorkspacePreferences.key(vaultId, key)`，如 `lastEditedNoteId`）。

### 7.2 目录与命名

**沙箱内（无文件夹绑定）**

```
<filesDir>/vaults/<vaultId>/
    notes/<noteId>.md
    maps/<mapId>.json
    canvases/<canvasId>.json
    backups/<uuid>_<fileName>        # 非 .md 导出（如备份 JSON）的内部副本
<filesDir>/math-bitmap-cache-v2/<sha256>.json
<filesDir>/lexinote-mutation.lock     # 跨进程锁，禁止重命名/删除
<filesDir>/backups/file-action-recovery-<uuid>.json
```

**外部文件夹（工作区/项目绑定）**

```
<root>/<清洗后标题>-<noteId 前 8 位>.md      # 冲突时追加 -1、-2…
<root>/.lexinote/catalog.json                # 目录索引，见下
<root>/.lexinote/历史副本/<标题>.md           # Markdown 历史副本，内容相同则复用同名文件
<root>/思维导图/<mapId>.mindmap.json          # id 必须匹配 ^[A-Za-z0-9_-]{1,128}$
```

文件名清洗（`LexiFolderPolicy.fileName`）：`<>:"/\|?*` 与控制字符 → `_`；去掉结尾的 `.` 和空格；trim；空或 `.`/`..` → `未命名笔记`；最长 80 字符。
路径安全：`within(root, path)` 要求 `root/` 前缀，且相对路径每段非空、非 `.`、非 `..`、不含 `\`。

`catalog.json`（`LexiFolderCatalog`）：

| 字段 | 说明 |
| --- | --- |
| `format` | `'LexiNote.Folder'` |
| `version` | `1` |
| `notes` | 全套 `NoteItem`，但 `content` 置空、`path` 改为相对 root 的路径 |
| `mindMaps` | 全套导图（含节点） |
| `canvases` | 全套白板 |
| `documents` 扫描 | 递归收集 `*.md`/`*.markdown`；跳过任意以 `.` 开头的名字、`.lexinote`、`.git`、`node_modules`、符号链接，以及其他嵌套工作区/项目根；单文件 ≤8 MB，最多 5000 篇；`mtime*1000` 作为修改时间；遇到 `*.md.lexinote-recovery` 先做中断恢复 |

注意两处非对称行为：
- 白板在外部文件夹模式**没有独立 JSON 文件**，只存在于 `catalog.json`（沙箱始终写 `canvases/<id>.json`）。
- 导图两种都写：文件夹 `思维导图/<id>.mindmap.json` + catalog。

### 7.3 原子写与锁

- 沙箱：先写 `<path>.tmp` → `fsync` → `rename` 覆盖。
- 文件夹：`writeAtomic` 另带恢复文件（`LexiNote.PendingWrite`：target/existed/previous/next），中断后可恢复；写前 `guardPath` 校验在 root 内。
- 进程内队列：`writeQueue`（KV/索引）、`mutationQueue`（笔记/导图/白板写）、`templateQueue`（模板）。
- 跨进程锁：`file.tryLock(true)`，最多 101 次 × 40ms（≈4s），失败抛出“知识库正在处理其他操作，请稍后重试。当前内容仍然保留。”；关闭 fd 亦释放内核锁。
- 每次写后 240ms 调度一次桌面卡片/表单元数据同步（`LexiFormService.sync`）。

### 7.4 自动保存

| 场景 | 防抖 | 落盘动作 |
| --- | --- | --- |
| 笔记编辑器 | 400ms | `saveNoteIfCurrent`（条件保存）→ 写 `.md` + 更新索引 + 链接索引 + 历史 + 目录索引 |
| 思维导图 | 280ms（结构操作立即） | `saveMindMap` |
| 白板 | 320ms（结构操作立即） | `saveCanvas` |

编辑器撤销栈：50 步，600ms 内合并为一步。保存状态文案：`正在自动保存…` / `已保存到本机` / `保存失败 · 点击重试`。

### 7.5 冲突处理

- `saveNoteIfCurrent(snapshot, expectedTitle, expectedContent)`：读取最新记录，若不存在、已进回收站、或 `title`/`content` 与编辑器基线不一致 → 抛 `DOCUMENT_CHANGED_ELSEWHERE`。
- UI 弹窗：标题 `笔记已在其他位置更新`，正文 `当前草稿仍然保留，可另存为副本，避免覆盖另一个窗口的修改。`，按钮 `保留草稿` / `另存为副本`。
- “另存为副本”：复制为新笔记（新 id、清空 path/时间），标题 `<原标题>（冲突副本）`，保存后切换到副本，并把当前编辑器基线重置为最新原文。
- 保存后若正文被规范化（如 frontmatter 重写）且编辑器无新改动，则用 `mapOffset` 映射选区并回填编辑器，避免光标跳动。
- 外部文件夹冲突：以文件为准；文件夹中消失的文件 → `trashedAt=now` + `sourceMissing=true`（进回收站，但说明是“源文件缺失”）；文件重新出现 → 恢复 `trashedAt=0`、`sourceMissing=false`。内容有差异时以文件内容覆盖内存并更新 `updatedAt`。

### 7.6 回收站

- 笔记：`trashedAt = Date.now()`，同时 `pinned=false`；列表按 `trashedAt` 降序；恢复置 0；**无自动过期清理**。
- “清空回收站”逐篇 `deleteNotePermanently`：删除物理文件（文件夹模式 `removeNote`，沙箱 `unlink`）→ 从索引移除 → 清空 `history:<id>` → 清空 `noteRedirect:<id>` → 重建链接表 → 刷新目录索引。
- 导图/白板：`deleteMindMap` / `deleteCanvas` 只从 KV 索引移除记录并刷新 catalog，**不删磁盘文件**；UI 文案为“已移除，原文件保留”。`trashedAt` 目前不参与删除流程，只用于过滤。

### 7.7 历史版本

- 每次内容或标题变化且已有旧版本时，把**旧快照**（`savedAt = previous.updatedAt`）插入 `history:<noteId>` 头部，保留最近 20 条。
- 恢复：用快照的 `title`/`content` 覆盖当前记录后正常保存（会再产生一条历史）。
- 合并笔记时，源笔记 `trashedAt` 设为当前时间；目标笔记写入合并内容并保存。

### 7.8 备份与恢复

- 备份包：`LexiBackupPackage`（见 §1.14），包含归档工作区/项目、**含回收站**的全部笔记、导图、白板、模板库 JSON、每个工作区的书签/数据库 JSON。
- 校验（`LexiBackupValidation`）：`format`/`version` 必须匹配；vault id 合法且唯一；导图结构（单根、无环、≤10000 节点、深度 ≤512、字段类型、`order` 有限）；白板卡片 id 唯一、数值有限、边两端存在；模板库可解码。
- 恢复流程（`restoreValidatedSnapshot`）：
  1. 校验后**清除所有 `folderUri`/`permissionUri`**（备份不携带外部目录授权），笔记 `sourceMissing` 置 false，若 `projectId` 不属于包内项目则重置为 `''`。
  2. 若指定了恢复目录：为每个工作区建 `<清洗名>-<8位随机>` 子文件夹，项目建 `<清洗名>-<projectId>`，写全部 md/导图/白板。
  3. 未指定目录：写到 `filesDir/restores/<uuid>/<vaultId>/{notes,maps,canvases}`，笔记 path 指向该代目录。
  4. 用包内容整体替换 KV：`vaults`、`projects`、`notes`、`mindmaps`、`canvases`；模板库解码后标记 `legacyImported=true`；逐工作区写回 `bookmarks:` / `databases:`。
- 迁移前自动归档：`before-notes-index-v2.json`、`before-clean-start-v2.json`。

### 7.9 限制

- 单文件导入上限 8 MB；一次最多 10 个文件。
- 导入 JSON 若为 `LexiNote.Backup` 且含 `notes` 数组 → 全量恢复；若含 `nodes` 数组 → 作为单幅导图导入（重新生成 id）。
- Markdown 正文大小无显式上限，但高亮扫描限制 60000 字符 / 4000 token。

---

## 8. 命令系统

### 8.1 模型

```
LexiCommand { id: string; title: string; hint: string }   // hint 默认 ''
```

- **源码没有 category 字段**；下表“分类”是本规格按语义归纳的移植分组（可直接用作 macOS 菜单分组），不是源码数据。
- `title` 会经 `LexiI18n` 翻译（`LexiEnglish.ets` 提供中→英映射）。
- 命令面板展示时 `hint` 被替换为当前绑定（`bindings.join(' / ')`）。
- 面板过滤：`rank(title) >= 0` 或 `id.includes(query)`；插件命令追加在内置命令之后。
- 命令 id 是稳定契约（快捷键覆盖、插件 `qualifiedId` 依赖它），移植时应原样保留。

### 8.2 快捷键格式与保留键

- 规范串：按 `Ctrl`、`Meta`、`Alt`、`Shift` 的顺序拼接 + 大写物理键名，用 `+` 连接，如 `Ctrl+Alt+Shift+ENTER`、`Ctrl+Alt+ARROWLEFT`。
- 按键名：字母 `A-Z`、数字 `0-9`、`F1-F12`、`ARROWUP/DOWN/LEFT/RIGHT`、`,` `.` `` ` `` `-` `=` `[` `]` `\` `;` `'` `/`、`BACKSPACE`、`DELETE`、`INSERT`、`HOME`、`END`、`PAGEUP`、`PAGEDOWN`、`TAB`、`ENTER`、`SPACE`、`ESCAPE`、`PRINTSCREEN`。
- 修饰键不能单独成绑定；无修饰且非功能键一律忽略。
- 保留（录制时警告）：`Alt+F4`、`Alt+TAB`、`Alt+Shift+TAB`、`Alt+SPACE`、`Ctrl+Alt+DELETE`、`Ctrl+Shift+ESCAPE`、`Ctrl+SPACE`、`PRINTSCREEN`、`Ctrl+C/V/X/Z/Shift+Z/Y/A`；所有 `Meta+…` 视为系统按键。
- 覆盖存储：`hotkeyOverrides = [{ id, bindings: string[] }]`，按工作区存储；同一组合被多条命令占用时 `commandFor` 返回空（避免歧义）。

### 8.3 完整命令清单（174 条，按源码顺序）

> 快捷键列为默认值；`—` 表示默认无绑定。`hint` 仅 `switcher`（`Ctrl / Cmd + O`）与 `reading`（`Ctrl / Cmd + E`）有值。

| # | ID | 名称 | 分类 | 默认快捷键 |
| --- | --- | --- | --- | --- |
| 1 | `palette` | 打开命令面板 | 核心 | Ctrl+P |
| 2 | `save` | 保存当前文件 | 核心 | Ctrl+S |
| 3 | `new` | 新建 Markdown 笔记 | 核心 | Ctrl+N |
| 4 | `quick` | 新建快速笔记 | 核心 | — |
| 5 | `study` | 新建学习笔记 | 核心 | — |
| 6 | `daily` | 打开今日笔记 | 核心 | — |
| 7 | `templates` | 从模板新建笔记 | 核心 | — |
| 8 | `save-template` | 将当前笔记保存为模板 | 核心 | — |
| 9 | `switcher` | 快速切换文档 | 核心 | Ctrl+O |
| 10 | `editor-bold` | 加粗/取消加粗 | 编辑器 | Ctrl+B |
| 11 | `editor-italic` | 倾斜/取消倾斜 | 编辑器 | Ctrl+I |
| 12 | `editor-strike` | 添加删除线 | 编辑器 | — |
| 13 | `editor-highlight` | 高亮 | 编辑器 | — |
| 14 | `editor-h1` | 设为小标题 1 | 编辑器 | — |
| 15 | `editor-h2` | 设为小标题 2 | 编辑器 | — |
| 16 | `editor-todo` | 插入待办事项 | 编辑器 | Ctrl+L |
| 17 | `editor-hr` | 插入分隔线 | 编辑器 | — |
| 18 | `editor-table` | 插入表格 | 编辑器 | — |
| 19 | `editor-code` | 插入代码块 | 编辑器 | — |
| 20 | `editor-formula` | 插入数学块 | 编辑器 | — |
| 21 | `editor-callout` | 插入标注 | 编辑器 | — |
| 22 | `reading` | 切换编辑与阅读 | 视图 | Ctrl+E |
| 23 | `split` | 在右侧分屏打开当前文档 | 标签页/窗口 | — |
| 24 | `close-split` | 关闭右侧分屏 | 标签页/窗口 | — |
| 25 | `sidebar` | 显示或隐藏侧边栏 | 视图 | — |
| 26 | `close-tab` | 保存并关闭当前标签 | 标签页/窗口 | Ctrl+W |
| 27 | `tab-prev` | 转到上一个标签页 | 标签页/窗口 | Ctrl+Shift+TAB |
| 28 | `tab-next` | 转到下一个标签页 | 标签页/窗口 | Ctrl+TAB |
| 29 | `tab-1` | 转到标签页 #1 | 标签页/窗口 | Ctrl+1 |
| 30 | `tab-2` | 转到标签页 #2 | 标签页/窗口 | Ctrl+2 |
| 31 | `tab-3` | 转到标签页 #3 | 标签页/窗口 | Ctrl+3 |
| 32 | `tab-4` | 转到标签页 #4 | 标签页/窗口 | Ctrl+4 |
| 33 | `tab-5` | 转到标签页 #5 | 标签页/窗口 | Ctrl+5 |
| 34 | `tab-6` | 转到标签页 #6 | 标签页/窗口 | Ctrl+6 |
| 35 | `tab-7` | 转到标签页 #7 | 标签页/窗口 | Ctrl+7 |
| 36 | `tab-8` | 转到标签页 #8 | 标签页/窗口 | Ctrl+8 |
| 37 | `tab-9` | 转到最后一个标签页 | 标签页/窗口 | Ctrl+9 |
| 38 | `map` | 新建思维导图 | 空间文件 | — |
| 39 | `canvas-export-image` | 白板：导出图片 | 空间文件 | — |
| 40 | `canvas-export-file` | 白板：转换为文件… | 空间文件 | — |
| 41 | `canvas` | 新建白板 | 空间文件 | — |
| 42 | `convert` | 将当前笔记转为思维导图 | 空间文件 | — |
| 43 | `graph` | 打开笔记关联 | 空间文件 | Ctrl+G |
| 44 | `library` | 打开文档管理 | 空间文件 | — |
| 45 | `workspaces` | 管理工作区与项目 | 空间文件 | — |
| 46 | `light` | 使用浅色外观 | 外观 | — |
| 47 | `dark` | 使用深色外观 | 外观 | — |
| 48 | `system` | 跟随系统外观 | 外观 | — |
| 49 | `export-md` | 导出工作区 Markdown | 导入导出 | — |
| 50 | `backup` | 导出完整备份 | 导入导出 | — |
| 51 | `import` | 导入文件 | 导入导出 | — |
| 52 | `settings` | 打开设置 | 核心 | Ctrl+, |
| 53 | `export-pdf` | 导出为 PDF | 导入导出 | — |
| 54 | `open-window` | 在新窗口中打开当前标签页 | 标签页/窗口 | — |
| 55 | `move-window` | 将当前标签页移动至新窗口 | 标签页/窗口 | — |
| 56 | `window-pin` | 将当前窗口置顶 | 标签页/窗口 | — |
| 57 | `help` | 打开使用说明 | 核心 | F1 |
| 58 | `rename` | 编辑文件名 | 文件操作 | F2 |
| 59 | `duplicate` | 复制当前文件 | 文件操作 | — |
| 60 | `copy-path` | 复制当前文件绝对路径 | 文件操作 | — |
| 61 | `copy-relative-path` | 复制当前文件的路径 | 文件操作 | — |
| 62 | `copy-uri` | 复制知萤 URI | 文件操作 | — |
| 63 | `delete-file` | 删除当前文件 | 文件操作 | — |
| 64 | `open-external` | 使用默认应用打开 | 文件操作 | — |
| 65 | `reveal-file` | 在文件管理器中显示 | 文件操作 | — |
| 66 | `move-file` | 将文件移动到其他文件夹 | 文件操作 | — |
| 67 | `trash` | 打开回收站 | 文件操作 | — |
| 68 | `search-all` | 搜索：在所有文件中搜索 | 搜索 | Ctrl+Shift+F |
| 69 | `spellcheck` | 开启/关闭英文拼写检查 | 编辑器 | — |
| 70 | `cursor-above` | 在上方添加光标 | 编辑器 | — |
| 71 | `cursor-below` | 在下方添加光标 | 编辑器 | — |
| 72 | `heading-rename` | 重命名当前小标题 | 结构 | — |
| 73 | `compose-heading` | 笔记重组：移动当前章节 | 结构 | — |
| 74 | `link-open` | 打开光标处的链接 | 链接 | Alt+ENTER |
| 75 | `link-open-tab` | 在新标签页中打开光标处链接 | 链接 | Ctrl+ENTER |
| 76 | `link-open-group` | 在新标签组中打开光标处链接 | 链接 | Ctrl+Alt+ENTER |
| 77 | `link-open-window` | 在新窗口中打开光标处链接 | 链接 | Ctrl+Alt+Shift+ENTER |
| 78 | `find` | 在当前笔记中查找 | 搜索 | Ctrl+F |
| 79 | `replace` | 在当前笔记中查找并替换 | 搜索 | Ctrl+Alt+F |
| 80 | `focus-editor` | 将焦点切换至编辑区 | 视图 | — |
| 81 | `lock` | 解锁/锁定 | 核心 | — |
| 82 | `outline` | 大纲：打开当前文件的大纲 | 面板 | — |
| 83 | `backlinks` | 反向链接：显示反向链接列表 | 面板 | — |
| 84 | `outgoing` | 出链：显示出链列表 | 面板 | — |
| 85 | `properties` | 属性列表：显示当前笔记的属性列表 | 面板 | — |
| 86 | `properties-all` | 属性列表：显示所有笔记属性 | 面板 | — |
| 87 | `property-add` | 增加笔记属性 | 属性 | Ctrl+; |
| 88 | `property-clear` | 清除笔记属性 | 属性 | — |
| 89 | `tag-add` | 添加标签 | 属性 | — |
| 90 | `alias-add` | 添加别名 | 属性 | — |
| 91 | `tags-list` | 标签列表：显示标签列表 | 面板 | — |
| 92 | `bookmarks` | 书签：显示书签列表 | 书签 | — |
| 93 | `bookmark-file` | 书签：收藏 | 书签 | — |
| 94 | `bookmark-block` | 书签：收藏当前块 | 书签 | — |
| 95 | `bookmark-heading` | 书签：收藏当前章节 | 书签 | — |
| 96 | `bookmark-search` | 书签：收藏当前搜索 | 书签 | — |
| 97 | `bookmark-tabs` | 书签：收藏所有标签页 | 书签 | — |
| 98 | `bookmark-remove` | 书签：移除当前文件的书签 | 书签 | — |
| 99 | `database-list` | 数据库：更改视图 | 数据库 | — |
| 100 | `database-new` | 数据库：新建数据库 | 数据库 | — |
| 101 | `database-insert` | 数据库：新建数据库并插入 | 数据库 | — |
| 102 | `database-view` | 数据库：添加视图 | 数据库 | — |
| 103 | `database-record` | 数据库：添加项目 | 数据库 | — |
| 104 | `database-copy` | 数据库：复制表格到剪贴板 | 数据库 | — |
| 105 | `compose-merge` | 笔记重组：将当前笔记合并到其他笔记中 | 结构 | — |
| 106 | `compose-selection` | 笔记重组：将所选内容移动到其他笔记中 | 结构 | — |
| 107 | `history` | 文件恢复：打开快照列表 | 文件操作 | — |
| 108 | `daily-prev` | 日记：打开前一天日记 | 核心 | — |
| 109 | `daily-next` | 日记：打开后一天日记 | 核心 | — |
| 110 | `back` | 返回 | 导航 | Ctrl+Alt+ARROWLEFT |
| 111 | `forward` | 前进 | 导航 | Ctrl+Alt+ARROWRIGHT |
| 112 | `tab-reopen` | 重新打开标签页 | 标签页/窗口 | Ctrl+Shift+T |
| 113 | `close-others` | 关闭其他标签页 | 标签页/窗口 | — |
| 114 | `close-all` | 关闭所有标签页 | 标签页/窗口 | — |
| 115 | `split-vertical` | 上下分屏 | 标签页/窗口 | — |
| 116 | `split-horizontal` | 左右分屏 | 标签页/窗口 | — |
| 117 | `ribbon-toggle` | 显示/隐藏功能区 | 视图 | — |
| 118 | `zoom-in` | 放大 | 视图 | — |
| 119 | `zoom-out` | 缩小 | 视图 | — |
| 120 | `zoom-reset` | 重置缩放 | 视图 | — |
| 121 | `font-increase` | 增大字体 | 视图 | — |
| 122 | `font-decrease` | 缩小字体 | 视图 | — |
| 123 | `theme-toggle` | 切换浅色/深色模式 | 外观 | — |
| 124 | `theme-picker` | 更换主题… | 外观 | — |
| 125 | `width-toggle` | 切换限制行宽 | 视图 | — |
| 126 | `default-view-toggle` | 切换新标签页的默认视图 | 视图 | — |
| 127 | `source-toggle` | 切换实时预览/源码模式 | 视图 | — |
| 128 | `inspector-toggle` | 折叠/展开右侧边栏 | 视图 | — |
| 129 | `fold` | 折叠所有标题和列表 | 视图 | — |
| 130 | `unfold` | 展开所有标题和列表 | 视图 | — |
| 131 | `template-date` | 模板：插入当前日期 | 模板 | — |
| 132 | `template-time` | 模板：插入当前时间 | 模板 | — |
| 133 | `editor-h3` | 设为小标题 3 | 编辑器 | — |
| 134 | `editor-h4` | 设为小标题 4 | 编辑器 | — |
| 135 | `editor-h5` | 设为小标题 5 | 编辑器 | — |
| 136 | `editor-h6` | 设为小标题 6 | 编辑器 | — |
| 137 | `editor-heading-clear` | 移除小标题格式 | 编辑器 | — |
| 138 | `editor-bullet` | 无序列表 | 编辑器 | — |
| 139 | `editor-ordered` | 有序列表 | 编辑器 | — |
| 140 | `editor-indent` | 缩进列表 | 编辑器 | — |
| 141 | `editor-outdent` | 取消列表缩进 | 编辑器 | — |
| 142 | `editor-quote` | 引用块 | 编辑器 | — |
| 143 | `editor-inline-code` | 行内代码 | 编辑器 | — |
| 144 | `editor-inline-math` | 行内数学公式 | 编辑器 | — |
| 145 | `editor-comment` | 注释/取消注释 | 编辑器 | Ctrl+/ |
| 146 | `editor-wiki` | 插入内部链接 | 编辑器 | — |
| 147 | `editor-link` | 插入链接 | 编辑器 | Ctrl+K |
| 148 | `editor-embed` | 嵌入内容 | 编辑器 | — |
| 149 | `editor-footnote` | 插入脚注 | 编辑器 | — |
| 150 | `editor-clear-format` | 清除格式 | 编辑器 | — |
| 151 | `editor-line-up` | 与上一行互换 | 编辑器 | — |
| 152 | `editor-line-down` | 与下一行互换 | 编辑器 | — |
| 153 | `editor-delete-paragraph` | 删除段落 | 编辑器 | Ctrl+D |
| 154 | `editor-table-row-copy` | 表格：复制行 | 表格 | — |
| 155 | `editor-table-col-copy` | 表格：复制列 | 表格 | — |
| 156 | `editor-table-row-delete` | 表格：删除行 | 表格 | — |
| 157 | `editor-table-col-delete` | 表格：删除列 | 表格 | — |
| 158 | `editor-table-row-up` | 表格：向上移动行 | 表格 | — |
| 159 | `editor-table-row-down` | 表格：向下移动行 | 表格 | — |
| 160 | `editor-table-col-left` | 表格：向左移动列 | 表格 | — |
| 161 | `editor-table-col-right` | 表格：向右移动列 | 表格 | — |
| 162 | `editor-table-row-before` | 表格：在上方新增行 | 表格 | — |
| 163 | `editor-table-row-after` | 表格：在下方新增行 | 表格 | — |
| 164 | `editor-table-col-before` | 表格：在左侧新增列 | 表格 | — |
| 165 | `editor-table-col-after` | 表格：在右侧新增列 | 表格 | — |
| 166 | `editor-table-align-left` | 表格：左对齐 | 表格 | — |
| 167 | `editor-table-align-center` | 表格：居中对齐 | 表格 | — |
| 168 | `editor-table-align-right` | 表格：右对齐 | 表格 | — |
| 169 | `editor-highlight-red` | 切换红色高亮 | 高亮 | — |
| 170 | `editor-highlight-orange` | 切换橙色高亮 | 高亮 | — |
| 171 | `editor-highlight-yellow` | 切换黄色高亮 | 高亮 | — |
| 172 | `editor-highlight-green` | 切换绿色高亮 | 高亮 | — |
| 173 | `editor-highlight-blue` | 切换蓝色高亮 | 高亮 | — |
| 174 | `editor-highlight-purple` | 切换紫色高亮 | 高亮 | — |

### 8.4 命令到编辑动作的映射（`LexiEditingActions.apply`）

| action | 行为 |
| --- | --- |
| `bold/italic/strike/highlight/inline-code/inline-math/comment` | 对称包裹 `**`、`*`、`~~`、`==`、`` ` ``、`$`、`%%` |
| `highlight-<color>` | 包裹 `<mark data-color="color">…</mark>`，颜色必须在上表六色内 |
| `code` | 替换为“换行 + 三反引号围栏 + 空行 + 围栏”的代码块模板 |
| `formula` | 包裹 `\n$$\n … \n$$\n` |
| `link` | `[选中](https://)` |
| `wiki` / `embed` | `[[选中]]` / `![[选中]]` |
| `hr` | 替换为 `\n\n---\n\n` |
| `table` | 插入 3 行 2 列表格：表头 `名称`／`内容`，分隔行 `---`，1 行空数据 |
| `footnote` | `[^<时间戳>]: 选中` |
| `callout` | 包裹 `\n> [!NOTE]\n> …` |
| `clear-format` | 去掉 `**`/`~~`/`==`/`` ` ``，并把 `*x*` 还原为 `x` |
| `line-up`/`line-down` | 交换整行 |
| `delete-paragraph` | 删除当前段落块 |
| `table-*` | 见 `LexiEditingActions.table`：复制/删除/上下左右移动行或列、前后插入、三种对齐；重排后按单元格内容逐行以竖线包裹重建整表 |

### 8.5 命令状态

源码的命令表是**静态全集**，没有 `enabled/when` 条件；命令面板始终展示全部内置命令（仅按查询过滤）。上下文可用性由各页面处理（例如 `canvas-*` 只在白板生效）。移植到 macOS 菜单时需要自行补 `validateMenuItem`。

---

## 9. 导入导出

### 9.1 导出

| 功能 | 内容 | 文件名 |
| --- | --- | --- |
| 导出工作区 Markdown（`export-md`） | 遍历该工作区未删除笔记，逐篇拼 `---\ntitle:…\nid:…\nnotebook:…\ntype:…\ntags: #a #b\n---\n\n<note.content>`，篇间 3 个换行 | `知萤_知识库导出_YYYY-MM-DD.md`（UTC 日期） |
| 导出完整备份（`backup`） | `JSON.stringify(LexiBackupPackage, null, 2)` | `知萤_完整知识库备份_YYYY-MM-DD.json` |
| 导出为 PDF（`export-pdf`） | 标题 + 空行 + 正文，纯文本换行 | `<note.title>.pdf` |
| 白板导出图片 | 视口 PNG（quality 100） | `<board.title>.png` |
| 白板转换为文件 | 白板 JSON | `<board.title>.json` |
| 导图导出 | 导图 JSON / Markdown 大纲 | `<map.title>.json` / `<map.title>.md` |

**导出注意（需在 macOS 侧决策）**

- Markdown 打包是“外层 frontmatter + 原文”的叠加，而 `note.content` 本身可能已带 YAML 头 → 导出文件会出现两段 `---`。若要与 Obsidian/其他工具互通，建议移植时改为“只输出一份合并后的 frontmatter”。
- 文件名清洗仅替换 `\/:*?"<>|` 为 `_`，不做长度截断与隐藏文件前缀处理。
- 保存路径统一走系统文档选择器（`DocumentViewPicker.save`）；用户取消时抛错。
- 经 `saveViaDocumentPicker` 的文本导出（备份 JSON、白板 JSON、导图 JSON/MD）会额外在本地 `backups/` 留一份 `<uuid>_<filename>` 内部副本；`.md/.markdown` 不留，PNG/PDF 走 `saveBytes` 也不留。

**PDF 排版参数**（`LexiExportService.pdf`）：A4 `595×842`，字体 `HarmonyOS Sans SC` 12pt，左边距 48，首行基线 790，行距 20，每页 37 行；折行按“字符宽度单位”：`charCode > 255` 记 2，否则记 1，每行上限 78 单位（中英混排近似半角/全角）。仅纯文本，不解析 Markdown 样式。

### 9.2 导入

- 选择器后缀过滤：`知萤笔记与备份|.md,.txt,.json`，最多 10 个文件，单文件 ≤8 MB，UTF-8 解码并去 BOM。
- 分支：
  1. `.json` 且 `format === 'LexiNote.Backup'` 且有 `notes` 数组 → 全量恢复，返回 `已恢复完整备份（N 篇笔记，M 幅导图）`。
  2. `.json` 且有非空 `nodes` 数组 → 校验导图后导入，id 改为 `map-<Date.now()>-<序号>`，`vaultId` 设为当前工作区。
  3. 其他 → 新建笔记：`title` = 文件名去扩展名，`notebook = '导入资料'`，`.md` → `noteType=markdown`/`editorLevel=pro`，否则 `quick`/`simple`；`LexiFrontmatter.apply` 吸收 frontmatter；追加标签 `导入`。
- 结果文案：`成功导入 N 篇笔记、M 幅思维导图`。
- 无外部依赖的粘贴/拖拽导入：源码未见统一实现（分享入口为 `LexiShareAbility`，属另一条链路）。

### 9.3 跨平台数据契约（给 macOS 侧）

- 笔记文件 = UTF-8 Markdown + 可选 YAML frontmatter；不要引入自定义二进制封装。
- 结构化数据（导图/白板/备份）为 UTF-8 JSON，字段名与 §1 完全一致。
- `LexiBackupPackage.format = 'LexiNote.Backup'`、`version = 1` 必须保持，否则无法双向迁移。
- 若新增字段，旧版读取时应忽略未知字段（当前实现按白名单拷贝，见 `importFolderNote`），因此新增字段要在 macOS 侧自行补默认值。

---

## 10. 建议的 macOS 原生实现取舍

### 10.1 必须保留（数据/语义/用户可感知）

1. **数据模型与字段名**：`NoteItem`/`MindMapDoc`/`MindMapNode`/`CanvasBoard`/`CanvasCard`/`CanvasEdge` 原样映射为 Swift `struct` + `Codable`；字段名已是 camelCase，`CodingKeys` 保持默认即可（仅当字段名与 Swift 关键字冲突时再改名）。
2. **文件即真相 + 外部文件夹**：`.md` 落盘、目录索引 `catalog.json`、原子写、按标题+id 前 8 位命名、`思维导图/<id>.mindmap.json`。macOS 用 security-scoped bookmark 替代 `folderUri`/`permissionUri`，用 `NSFileCoordinator` + `replaceItemAt` 实现原子替换。
3. **Frontmatter 兼容性**：受限 YAML 的解析/序列化行为（tags 归并、未知字段保留、块列表归一）直接影响 Obsidian 互操作，建议保留语义；可换成熟 YAML 库，但必须复现“单行标量 + 平铺列表可编辑，嵌套只读”的边界。
4. **双链解析与重命名修复**：按 id 或标题（忽略大小写）解析、同工作区限定、未解析链接保留、去重键 `source+targetTitle+anchor`、重命名时保留 `#锚点`/`|别名` 并同步导图 `noteRefTitle`。
5. **搜索 rank 与摘要窗口**：`0/1+offset/100+gaps` 与 `-18/+42`（默认 86）窗口是用户肌肉记忆，建议逐字复刻。
6. **力导向参数与归一化**：确定性布局、`spring=sqrt(4/n)*0.9`、迭代档位、`temperature 0.18/0.975/0.004`、`[0,1]` 归一化。这样同一份数据两端图形一致，也便于截图对比回归。
7. **导图布局坐标公式**：`x/y/boxWidth/boxHeight/offsetX/offsetY` 会随 JSON 落盘，若要读取旧文件必须复刻 `right/balanced/org` 的间距与 clamp。
8. **命令 id 与默认快捷键表**：id 是插件与快捷键覆盖的契约；默认绑定至少保留一份映射表用于迁移。
9. **条件保存与冲突副本**：以“基线 title/content”比较的乐观并发，配 `DOCUMENT_CHANGED_ELSEWHERE` 等价错误与“保留草稿/另存为副本”两条出路。
10. **版本历史 20 条**、**软删除 `trashedAt`**、**备份包格式**：数据兼容与可回滚的底线。
11. **KaTeX 语义边界**：`throwOnError`、`trust:false`、`maxExpand:1000`、`maxSize:20` 决定哪些公式会降级为原文；换渲染器必须保留“失败显示 LaTeX 源”的兜底。

### 10.2 可以简化或替换

| 现状 | macOS 建议 | 理由 |
| --- | --- | --- |
| RDB 镜像（`notes_meta`/`notes_content`/`link_index`） | 直接用文件 + 内存索引；量大时上 SQLite FTS5 或 GRDB | 单机笔记量下文件扫描足够；避免双写不一致 |
| 手写 `lexinote-mutation.lock` 跨进程锁 | `NSFileCoordinator` / actor 串行队列 / 单实例窗口 | 多进程场景在 macOS 上主要来自多窗口，`NSDocument` 体系已处理 |
| `writeTextAtomic` + 恢复文件 | `Data.write(to:options:.atomic)` 或 `replaceItemAt` | 系统级原子替换 |
| 自研代码高亮（21 语言） | Highlightr / Splash / Tree-sitter | 现实现是“有界词法”，无嵌套语法，维护成本高收益低 |
| 隐藏 WebView + KaTeX 位图 | WKWebView + KaTeX（保留同一套 HTML）或 SwiftMath/LaTeXSwiftUI | 位图缓存与批量调度可省；小公式用原生排版更流畅 |
| 手写 PDF 折行 | `NSPrintOperation` / PDFKit / CoreText | 现实现不解析 Markdown，导出观感差；原生排版可顺带支持样式 |
| Canvas 2D 手绘导图/白板/图谱 | SwiftUI `Canvas` + `MagnifyGesture`/`DragGesture` | 代码量下降，且能自然加入缩放/拖拽 |
| “每标签页一个编辑器控制器” | `NSDocument`/`DocumentGroup` 或自管 `EditorSession` | 保留“切换标签不重载草稿”的语义即可 |
| 多窗口/分屏/标签组命令 | `NSWindow` + `NSWindowTabGroup` | 系统能力，无需自研 |
| `Ctrl` 系默认快捷键 | 映射为 `⌘`（保留 `⌃` 作为备选） | macOS 上 `Ctrl+F` 等与文本导航冲突 |
| 工作区/项目双层 | 首版可先做“单一库 + 文件夹”，模型保留 `vaultId/projectId` | 降低首版复杂度，字段不丢 |
| 插件系统、分享剪藏、离线语音、表单、数据库视图、书签 | 首版可不做 | 与本规格的笔记/导图/白板核心闭环解耦 |

### 10.3 关键技术风险

1. **实时预览编辑器**：HarmonyOS 侧是“按块替换 + 选区映射”的自研方案（`LexiLiveMarkdown`）。macOS 用 `NSTextView` 时建议采用“属性化文本 + 隐藏标记”的方案，并复刻 `rangeAt`（块范围不含尾随换行）与 `shouldAdvance`（表格/引用/围栏需空行退出）两条规则，否则回车行为会明显不同。
2. **行内公式混排**：`Text`+`ImageSpan` 的基线对齐在 SwiftUI 里需用 `AttributedString` 的 attachment 或自绘 `Layout`；`$` 的货币防误判规则（§2.8）必须照搬，否则中文笔记会被大量误判。
3. **中文排版**：原实现字体 `HarmonyOS Sans`/`HarmonyOS Sans SC`，macOS 用 `PingFang SC` + `SF Mono` 替代；行高（14/23、16/28）与 `noteFontSize` 缩放比例（文本尺寸 × `noteFontSize/16`）建议保留。
4. **表格渲染**：原实现固定列宽 156 + 横向滚动，长表格体验一般；macOS 可用 `Grid` 自适应列宽，但需保留对齐语义与表头底色。
5. **`#tag` 提取**：正则 `(?:^|\s)#([\u4e00-\u9fa5A-Za-z0-9_\/-]{1,28})`，会跳过围栏内文本；`#` 前必须是行首或空白，避免 URL 片段误判。标签保存时与 `properties`/frontmatter 合并，重复保存不得产生重复标签。
6. **多窗口一致性**：原实现用“条件保存 + 文件锁 + 每次写后重读”保证；macOS 若用 `NSDocument`，需关闭自动版本冲突弹窗并映射到“另存副本”流程，避免两套冲突 UX 打架。
7. **i18n**：`LexiEnglish.ets`（37 KB）是整句中英映射表，命令标题、提示、错误文案都在其中；若首版只做中文，可先内联中文，但命令 id 与文案的对应关系建议保留成表，便于后续补英文。

### 10.4 建议的 Swift 模块切分

| 模块 | 职责 | 对应源码 |
| --- | --- | --- |
| `LexiModel` | `Codable` 模型、枚举、默认值、不变量 | `LexiModels`, `LexiWorkspaceModels` |
| `MarkdownKit` | 块/行内解析、表格、frontmatter、大纲、摘要 | `MarkdownEngine`, `LexiFrontmatter`, `LexiLiveMarkdown` |
| `MathKit` | 定界符/环境扫描、KaTeX 容器、缓存 | `LexiMathSyntax`, `LexiMathBitmapCache` |
| `SearchKit` | 查询解析、匹配、rank、摘要窗口 | `LexiSearch`, `MarkdownEngine.previewSpans` |
| `GraphKit` | 拓扑、力导向、局部子图 | `GraphLayout`, `LexiGraphForce` |
| `MindMapKit` | 三种布局、节点操作、Markdown 互转 | `MarkdownEngine` 后半 + `LexiWorkspaceMindMap` |
| `CanvasKit` | 卡片/连线、命中测试、导出 | `CanvasPage`, `LexiSpatialEditor` |
| `StoreKit` | 文件/索引/回收站/历史/备份/冲突 | `LexiStorageService`, `LexiFolderStore`, `LexiFolderPolicy` |
| `CommandKit` | 命令表、快捷键、菜单校验 | `LexiCommands`, `LexiHotkeySettings` |
| `ExportKit` | Markdown/JSON/PDF/PNG 导出、导入 | `LexiExportService`, `LexiStorageService` 导入段 |

---

## 附录 A：症状 → 源码位置速查

| 想确认的行为 | 位置 |
| --- | --- |
| 为什么 h4 显示成 h3 | `MarkdownEngine.parseBlocks`（`Math.min(3, level)`） |
| 为什么段落不合并 | 同上：逐行生成 block |
| 为什么 callout 没有颜色 | `LexiEditorPanels.ets` 491–501（统一 `brand_soft`） |
| 为什么 `$5` 不是公式 | `LexiMathSyntax.isValidDollarBody` |
| 为什么公式显示原文 | `renderer.js` 的 `throwOnError` + `math-error` |
| 为什么搜索能搜到正文但排序靠后 | `LexiCommandPalette.results`（`rank` 为 -1 记 1000） |
| 为什么拖拽导图节点后 `x/y` 没变 | `LexiSpatialEditor.moveBranch` 只改 `offsetX/offsetY`，每次布局再叠加到 `x/y` |
| 为什么删除导图后文件还在 | `deleteMindMapUnlocked` 只移除索引 |
| 为什么外部文件夹里没有白板 JSON | `saveCanvasSnapshot` 始终写沙箱，folder 只写 catalog |
| 为什么重命名后双链没断 | `saveNoteSnapshot` 里的 `renameLinksInMarkdown` |
| 为什么两段 frontmatter | `exportMarkdownBundle` 外层拼接 + `note.content` 自带 YAML |
| 为什么快捷键按了没反应 | 可能命中保留键（`LexiSystemShortcuts`）或被多条命令占用（`commandFor` 返回空） |

## 附录 B：规模与阈值速查

| 项 | 值 |
| --- | --- |
| 命令数 | 174 |
| 高亮语言 | 21（+ 纯文本） |
| 高亮 token 上限 | 4000 / 60000 字符 |
| 导图节点上限（导入校验） | 10000；树深上限 512；转换生成上限 48 |
| 历史版本 | 20 |
| 编辑器撤销 | 50（600ms 合并） |
| 导图撤销 | 40（600ms 合并） |
| 自动保存防抖 | 笔记 400ms / 导图 280ms / 白板 320ms |
| 图谱迭代 | 260 / 160 / 120 / 90（阈值 80 / 160 / 320） |
| 图谱边采样 | n>320 时 96 个样本 |
| 摘要长度 | 128 字符（无查询）；窗口 18 前 / 42 后；默认 86 |
| 未链接提及 | 最多 16 条；标题长度 ≥2 |
| 导入限制 | 10 文件 × 8 MB |
| 公式缓存 | 内存 128；12s 超时；4096×2048；16 MB Base64 |
| 文件锁 | 101 次 × 40ms |
| 文件名 | ≤80 字符；id 前缀 8 位 |
