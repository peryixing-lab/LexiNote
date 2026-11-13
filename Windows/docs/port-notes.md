# 移植说明：从 HarmonyOS 到 Windows

本文记录 Windows 版与上游 ArkTS 工程的对应关系、刻意保持一致的行为，以及无法一一对应的系统能力。
上游工程：`/DevecostudioProjects/LexiNote`（未修改）。

## 技术栈选择

上游使用 ArkTS + ArkUI，界面与系统能力（HDS 材质、ArkWeb、服务卡片、分享、离线语音）都依赖鸿蒙运行时。
Windows 版采用 **Electron 36 + React 18 + TypeScript**：

- Chromium 能原生运行上游用于阅读视图与公式的 KaTeX 资源；
- 单个代码库即可产出 x64 / ARM64 / x86 三个 Windows 构建；
- 无原生扩展（native addon），因此三种架构共用同一份 JS 产物，架构差异只来自 Electron；
- 渲染进程完全沙箱化，主进程负责所有文件访问。

## 模块映射

| 上游 ArkTS | Windows TypeScript | 说明 |
| --- | --- | --- |
| `core/LexiTheme.ets` | `core/theme.ts` | 逐行移植混色、对比度修正与全部工作区颜色令牌 |
| `core/MarkdownEngine.ets` | `core/markdown.ts` | 块解析、行内 span、表格、大纲、双向链接、导图布局、导图转 Markdown |
| `core/LexiFrontmatter.ets` | `core/markdown.ts` | YAML 子集解析/序列化 |
| `core/LexiMathSyntax.ets` | `core/math.ts` | `$…$`、`$$…$$`、`\(…\)`、环境与货币符号防误判 |
| `core/LexiSearch.ets` | `core/search.ts` | `tag:` / `type:` / `notebook:` / `path:` / `[属性]:` / 排除词 |
| `core/LexiI18n.ets`、`core/LexiEnglish.ets` | `core/i18n.ts`、`core/english.ts`、`core/ui-english.ts` | 512 条上游文案 + Windows 新增文案 |
| `core/LexiSeedData.ets` | `core/seed.ts` | 初始空状态；测试/截图用演示数据夹具（正式安装不注入） |
| `components/LexiDesktopWorkspace.ets` | `App.tsx`、`TitleBar.tsx`、`Sidebar.tsx`、`Rail.tsx` | 工作区拆分为布局、标题栏、侧栏、功能区 |
| `components/LexiWorkspaceEditor.ets` | `components/Editor.tsx` | 标题、实时块编辑、源码、阅读、查找替换、状态栏 |
| `components/LexiEditorPanels.ets` | `components/MarkdownView.tsx` | 预览、标注、代码、公式、表格、图片、嵌入 |
| `components/LexiWorkspaceRightSidebar.ets` | `components/RightSidebar.tsx` | 大纲、出链、反向链接、属性 |
| `components/LexiCommandPalette.ets` | `components/CommandPalette.tsx` | 命令与文档两种模式 |
| `components/LexiSettingsWindow.ets` | `components/SettingsDialog.tsx` | 关于、外观、界面、编辑器、文件与链接、插件、快捷键 |
| `components/LexiExploreTab.ets`、`core/LexiGraphForce.ets` | `components/GraphView.tsx` | 确定性力导向布局，支持标签、导图与未连接提及 |
| `components/LexiVaultTab.ets` | `components/LibraryView.tsx` | 卡片/列表、标签筛选、排序 |
| `components/LexiWorkspaceMindMap.ets` | `components/MindMapView.tsx` | 三种布局、拖拽、折叠、颜色、转笔记 |
| `pages/CanvasPage.ets` | `components/CanvasView.tsx` | 卡片白板 |
| `core/LexiStorageService.ets` | `store/AppStore.tsx` + `src/main/main.ts` | 渲染进程内存状态 + 主进程 JSON 原子写入 |
| `entryability/EntryAbility.ets`、窗口材质 | `src/main/main.ts` | 无边框窗口、自绘按钮、窗口状态记忆 |
| `rawfile/lexi-math`（ArkWeb + KaTeX） | `katex` npm 包直接渲染 | 不再需要 WebView 与消息桥 |
| `plugin/*`、`packages/*` | 未移植 | 见下文 |

## 保持一致的部分

- **配色算法**：同一套 `mix` / `contrast` / `readable` 计算，主题色变化会得到与鸿蒙版相同的工作区色板。
- **Markdown 语义**：同一 block 语法、同一标注类型、同一任务清单与表格解析、同一 LaTeX 识别规则。
- **链接**：`[[标题#小节|显示文本]]` 的解析、出链/反向链接/未连接提及的判定一致。
- **导图布局**：向右树 / 平衡图 / 组织结构的节点尺寸、负坐标与偏移算法逐行移植。
- **文案**：界面文案优先使用上游中英文目录，Windows 新增界面补充在 `ui-english.ts`。
- **图标**：直接使用上游 SVG 图标，通过 CSS mask 复刻 ArkUI `colorFilter` 的着色方式。

## 材质替换

| 鸿蒙 | Windows |
| --- | --- |
| HDS 沉浸光感 / `hdsMaterial` / 系统模糊 | 纯色 `--surface`、半透明仅用于个别浮层，不使用 `backdrop-filter`；阴影为普通 CSS 阴影 |
| 系统标题栏 / 沉浸安全区 | `frame: false` + 自绘标题栏；窗口按钮位于右上角 |
| 系统圆角与裁剪 | CSS `border-radius` |
| 系统字体 | `Segoe UI` / `Microsoft YaHei UI` 等系统字体栈 |
| 桌面卡片 | 无 |
| 分享与接续 | 本地导入/导出 |

## 有意未移植

- ArkWeb 插件宿主、Obsidian 兼容层、插件权限与沙箱 RPC；
- 系统服务卡片、系统分享剪藏、跨设备接续、原生标签拖出为新窗口（改以「在新窗口打开工作区」提供）；
- 语音识别（改为调用系统语音输入）、拼写检查、多光标；
- 外部文件夹实时同步；当前以导入/导出替代；
- PDF 直接生成：导出可打印 HTML，由浏览器另存为 PDF。

## 工作区打开方式与多窗口

- `VaultItem.openMode` 是**工作区自身**的字段：`ask` / `current` / `new`，随工作区一起备份与恢复。
- `AppSettings.workspacePromptSuppressed` 是**全局**的「下次不再提示」开关，
  `workspaceDefaultOpenMode` 记录关闭提示后使用的默认方式；二者都不写入工作区。
- 选择工作区时：若该工作区已明确设置打开方式，直接按设置执行；若为 `ask` 且全局提示开启，弹出询问；
  若全局提示关闭，则使用该工作区的模式，`ask` 时回落到全局默认方式。
- 新窗口通过带 `vaultId` 查询参数重新加载渲染进程；主进程维护 `masterState` 与 `revision`，
  各窗口保存时按 `updatedAt` 合并笔记 / 导图 / 白板，并广播给其他窗口；删除只在基于最新 revision
  的快照中生效，避免旧窗口把已删除内容写回。
- 初始安装使用空状态（一个空工作区），演示数据仅在 `LEXI_DEMO_DATA=1` 的测试/截图模式下注入。

## 数据兼容

Windows 版把数据保存为单个 JSON（`%APPDATA%\LexiNote\lexinote-data.json`），结构与上游 `NoteItem` /
`MindMapDoc` / `CanvasBoard` 字段保持一致（`properties` 的字段名为 `key`/`value`，上游为
`key`/`propValue`）。笔记正文是标准 Markdown，含 YAML frontmatter，可直接迁移到其他编辑器。
