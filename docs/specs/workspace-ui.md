# LexiNote 桌面工作区 · SwiftUI 复刻规格

> 调研对象：`entry/src/main/ets/`
> 核心：`components/LexiDesktopWorkspace.ets`（1287 行）、`components/LexiWorkspaceEditor.ets`（1198 行）、
> `components/LexiWorkspaceRightSidebar.ets`、`components/LexiCommandPalette.ets`、`components/LexiEditorPanels.ets`、
> `components/LexiNoteCard.ets`、`components/LexiLiveMarkdownEditor.ets`、`components/LexiCaptureAssistantPanel.ets`、
> `components/LexiTemplatePicker.ets`、`components/LexiTrashPanel.ets`、`core/LexiCommands.ets`、`core/LexiTheme.ets`、
> `core/LexiInterfaceSettings.ets`、`core/LexiTabStripLayout.ets`、`core/LexiModels.ets`、`core/LexiWorkspaceModels.ets`。
>
> 本文只做规格提取，不含实现代码。所有尺寸单位在原工程中为 **vp**（ArkUI 密度无关像素）；
> macOS 版按 **pt** 1:1 取值即可（1 vp ≈ 1 pt @1x；原工程可用 75%–150% 的界面缩放整体改变物理大小）。

---

## 0. 测量基线与前置结论

| 项 | 值 | 依据 |
|---|---|---|
| 桌面工作区启用条件 | 窗口宽 ≥ **840 vp** | `pages/Index.ets:337 wide()`；< 840 走 `Tabs` 手机布局 |
| 窗口标题栏（装饰）高度 | **52 vp** | `EntryAbility.ets` 中 `setWindowDecorHeight(52)` |
| 默认侧栏宽度 | **244 vp**（可 200–480） | `LexiInterfaceSettings.clampSidebarWidth` |
| 默认右栏宽度 | **280 vp**（可 232–560） | `clampRightSidebarWidth` |
| 默认正文字号 | **16 vp**，行高 **1.75×** = 28 | `@StorageProp('lexiFontSize') 16` |
| 正文最大宽度 | 外层 **800 vp**，左右各 56 内边距 → 文本 **688 vp** | `LexiWorkspaceEditor.ets:1142-1143` |
| 全局行宽限制开关 | `editorLimitWidth` 默认 true；关掉后 maxWidth = 10000 | 同上 |
| 主分隔线 | 统一 **0.5 vp**、色 `workspace_line` | 全文件 |
| 动效 | 仅侧栏文件夹箭头 150ms EaseOut 等极少数 | 见 §10 |
| 材质/模糊 | 桌面工作区**完全无模糊/玻璃**，全部为纯色 + 0.5 发丝线 | 全文件 |

**结论先行（移植时最容易踩的 5 个点）**

1. HarmonyOS 把窗口按钮（红绿灯）放在**右上角**，用 `windowButtonsInset` 在标签条**右侧**留白；macOS 在**左上角**，留白必须改到品牌区左侧，且总高度仍保持 52 pt。
2. 「源码」按钮的文案是**目标状态**（当前在实时预览时显示"源码"，当前在源码时显示"实时预览"），而底部状态栏的视图标签显示的是**当前状态**（"阅读视图 / Markdown 源码 / 实时预览"）。二者语义相反，不要一起抄。
3. 编辑器有**三态**：阅读（reading）、整篇源码（editing）、实时预览（默认）。工具栏按钮只在"源码↔实时预览"之间切换，底部标签只在"阅读"上切换。
4. 标签页**没有未保存圆点**。脏状态只体现在底部状态栏文本（"正在自动保存…"→"已保存到本机"，失败"保存失败 · 点击重试"）与关标签时的阻断 Toast。
5. 笔记行**不显示置顶图标**；`pinned` 只影响排序（置顶优先，其后按 `updatedAt` 降序）。收藏才显示星标。

---

## 1. 整体布局几何

### 1.1 结构树

```
LexiDesktopWorkspace (Row, 100%×100%, bg workspace_page)
├─ LexiKnowledgePanel                      // 0×0 的 sheet 宿主，不参与布局
├─ Stack(align: End)  width = rail + 侧栏内容
│  ├─ Column 100%×100%
│  │  ├─ brandRow      h = 52 + topInset   bg workspace_sidebar，底边 0.5
│  │  └─ Row（剩余高度）
│  │     ├─ rail       w = 56（showRibbon 时）  bg workspace_rail，右边 0.5
│  │     └─ sidebar    w = 244（sidebarOpen 时）bg workspace_sidebar，左右 padding 12
│  └─ sidebarResizeHandle   w = 10，贴右边缘
└─ Column  layoutWeight(1)   bg workspace_page
   ├─ tabStrip         h = 52 + topInset   bg workspace_tabs，底边 0.5
   └─ Row（剩余高度）
      ├─ Navigation / Flex（layoutWeight 1）
      │  ├─ Stack（documents，layoutWeight 1）
      │  └─ 分组面板（groupTabs 存在且左右分屏时，layoutWeight 1，左边框 1）
      └─ Stack  width = 右栏宽（280）
         ├─ LexiWorkspaceRightSidebar
         └─ rightSidebarResizeHandle  w = 10，贴左边缘
```

### 1.2 尺寸总表

| 区域 | 宽度 | 高度 | 内边距 | 背景 palette 键 |
|---|---|---|---|---|
| 品牌区（左上） | 与左侧整列同宽 = 56 + 侧栏宽 | **52 + topInset** | left 14, right 18, top topInset | `workspace_sidebar` |
| 功能区 rail | **56** | 100% | top 16, bottom **14**（桌面/2in1；触屏内联菜单形态 10）；元素间距 8 | `workspace_rail` |
| 知识库侧栏 | **244**（200–480，窗口约束） | 100% | left 12, right 12 | `workspace_sidebar` |
| 标签条 tabStrip | 剩余宽 | **52 + topInset** | left 8；right = `windowButtonsInset>0 ? inset+4 : 12`；top topInset | `workspace_tabs` |
| 编辑器容器 | layoutWeight(1) | 剩余高 | — | `workspace_page` |
| 编辑器顶部工具条 | 100% | **48** | left 28, right 16 | 继承 `workspace_page` |
| 文档滚动列 | ≤ 800（限宽时） | 100% | left 56, right 56, top 42, bottom 80 | 透明（父 `workspace_page`） |
| 编辑器底部状态栏 | 100% | **40**（桌面/2in1；触屏 **44**） | left/right = 24/20（pane≥600）否则 12/12；bottom **0**（桌面/2in1；触屏 4） | 透明 |
| 右侧检查器 | **280**（232–560，窗口约束） | 100% | 内容 left 16, right 16, top 20, bottom 24；工具条 left 12, right 12 | `workspace_inspector` |
| 右栏工具条 | 100% | **48** | left 12, right 12 | `workspace_inspector` |
| 侧栏拖拽热区 | **10** | 100% | 内部线宽 0.5（悬停/拖拽时 2） | 透明 |
| 分组分屏面板 | layoutWeight(1) | 100% | 标题行 left 16, right 8 | `workspace_page`，左边框 1 |

### 1.3 分隔线（全部 0.5 vp，色 `workspace_line`，除注明）

| 位置 | 线宽 | 备注 |
|---|---|---|
| 品牌区底部 | 0.5 | 与标签条底边同高，形成横贯全窗的一条线 |
| 标签条底部 | 0.5 | 激活标签用 2 vp 的 `brand` 顶边，而不是白底压线 |
| rail 右缘 | 0.5 | 在左侧整列内部 |
| 左侧整列右缘 | 0.5 | 侧栏与编辑器的分界 |
| 侧栏搜索框 | 0.5 | 四边，圆角 7 |
| 侧栏底部切换器顶边 | 0.5 | 仅 top |
| 编辑器工具条底部 | 0.5 | |
| 状态栏顶边 | 0.5 | |
| 右栏整体左边框 | 0.5 | |
| 右栏工具条底部 | 0.5 | |
| 分组分屏左边框 | **1.0** | 唯一 1 vp 的分隔线 |

### 1.4 响应式断点

| 判定 | 阈值 | 行为 |
|---|---|---|
| 桌面工作区 | 窗口 ≥ 840 | 否则 Tabs 手机布局 |
| 编辑器窗格 paneWidth ≥ 600 | 600 | 状态栏元素间距 16（否则 8）、左右 padding 24/20（否则 12/12）、显示视图状态标签（阅读视图 / Markdown 源码 / 实时预览） |
| paneWidth ≥ 480 | 480 | 显示"{n} 字符" |
| paneWidth ≥ 900 | 900 | 显示"{n} 个反向链接"；内置检查器（非桌面路径）默认展开 |
| paneWidth ≥ 680 | 680 | 内置检查器可显示（桌面用外部右栏，`externalInspector: true`，此路不生效） |
| 双栏自动折叠 | 可用宽 − 侧栏 − 右栏 < **420** | 打开右栏时关侧栏；窗口变窄时关侧栏 |
| 侧栏极限 | max(200, 宽 − rail − 右栏 − 420) | `sidebarWidthForWindow` |
| 右栏极限 | max(232, 宽 − rail − 侧栏基准 200 − 420) | `rightSidebarWidthForWindow` |

### 1.5 Palette 键（`core/LexiTheme.ets`）

桌面工作区只使用下表 16 个键。**默认主题为 `original` 模式**（`lexiThemeColors` 为空且 accent = `#6E44D9`）。

#### original · 浅色

| 键 | 值 | 用途 |
|---|---|---|
| `workspace_page` | `#FFFFFF` | 编辑区/阅读区底、激活标签底、空状态底、命令面板底 |
| `workspace_tabs` | `#F0EBF8` | 标签条底 |
| `workspace_rail` | `#EAE4F5` | 最左图标栏 |
| `workspace_sidebar` | `#F4F0FA` | 知识库侧栏 + 品牌区 + 命令面板头部 + 回收站头部 |
| `workspace_inspector` | `#FCFAFF` | 右侧检查器 |
| `workspace_selection` | `#E4D8FA` | 选中行/激活按钮底（拉宽按钮、新建按钮、分段选中） |
| `workspace_line` | `#DDD5EA` | 全部发丝线 |
| `text_primary` | `#231B36` | 主文字 |
| `text_secondary` | `#6E6385` | 次要文字/图标 muted |
| `brand` | `#6E44D9` | 强调、激活标签顶边、拖拽高亮线、caret |
| `brand_ink` | `#4E2B9E` | 选中行文字、按钮文字、链接文字 |
| `brand_soft` | `#E9E0FF` | 命令面板选中行、chips |
| `soft_surface` | `#EEEAF8` | 语音按钮底、工具格底、搜索输入底 |
| `surface` | `#FFFFFF` | 弹层/菜单/工具面板底 |
| `divider` | `#E4DDF2` | 面板内部 Divider |
| `error` | `#C44D62` | 危险操作文字 |

#### original · 深色

| 键 | 值 |
|---|---|
| `workspace_page` | `#191822` |
| `workspace_tabs` | `#211E2C` |
| `workspace_rail` | `#1D1A29` |
| `workspace_sidebar` | `#242030` |
| `workspace_inspector` | `#1E1C29` |
| `workspace_selection` | `#403355` |
| `workspace_line` | `#3B354C` |
| `text_primary` | `#F5F3FB` |
| `text_secondary` | `#C6C2D4` |
| `brand` | `#C7B3FF` |
| `brand_ink` | `#E0D4FF` |
| `brand_soft` | `#3A3157` |
| `soft_surface` | `#2D2F3E` |
| `surface` | `#20212D` |
| `divider` | `#4B465F` |
| `error` | `#FF9EAB` |

#### 强调色模式（mode = preset，accent = `#6E44D9`）— 算法实算值

由 `LexiTheme.palette()` 以混色公式生成（`mix(base, tint, amount)` 逐通道线性插值并做 4.5:1 可读性校正）：

| 键 | 浅色 | 深色 |
|---|---|---|
| `workspace_page` | `#FEFEFF` | `#1C1C2A` |
| `workspace_tabs` | `#E6E6F2` | `#252339` |
| `workspace_rail` | `#DFDFEE` | `#242139` |
| `workspace_sidebar` | `#EDECF5` | `#29263C` |
| `workspace_inspector` | `#FBFAFE` | `#232234` |
| `workspace_selection` | `#D4D2EA` | `#43386A` |
| `workspace_line` | `#D7D3EA` | `#46445E` |
| `text_primary` | `#212032` | `#F2F2F9` |
| `text_secondary` | `#56566F` | `#BDBDD5` |
| `brand` / `brand_ink` | `#663FCA` | `#B5A0EC` |
| `brand_soft` | `#E3E2F3` | `#39325A` |
| `soft_surface` | `#E8E7F3` | `#322F45` |
| `surface` | `#FDFDFF` | `#262537` |
| `divider` | `#D7D3EA` | `#46445E` |

> 若做自定义背景/前景（mode = custom），`workspace_*` 会以「背景 + accent 的 4.5%/6.5%/9% 混色」重新推导，`divider = mix(背景, 前景, 0.16)`。移植建议：把 16 个键固化成 `Color` token 集，主题切换只替换 token。

---

## 2. 标题栏（顶部 52 vp）

整窗顶部实际由**两块并排的 52 高条**拼成，背景不同，形成双色标题栏：

- 左侧（宽 = 56 + 侧栏宽）：品牌区，`workspace_sidebar`
- 右侧（剩余宽）：标签条，`workspace_tabs`
- 两者底边各有一条 0.5 `workspace_line`，视觉上连成一条横线

### 2.1 品牌区

| 元素 | 规格 |
|---|---|
| 容器 | Row，宽 100%，高 52 + topInset，padding left 14 / right 18 / top topInset，bg `workspace_sidebar`，底边 0.5 |
| Logo | `app.media.lexi_logo`，**28×28**，圆角 **7** |
| 中文名 | "知萤"，**17**，**Bold**，`text_primary` |
| 英文名 | "LexiNote"，**12**，Medium，`brand_ink` |
| 间距 | Row space 10（logo→中文→英文） |
| 折叠态 | 侧栏收起时**只显示 Logo**（中文/英文/Blank 全隐藏） |

**坑**：折叠时该列宽 = 56，而 14 + 28 + 18 = 60 > 56，Logo 会被容器 `.clip(true)` 裁掉约 4 vp。macOS 版应在折叠态改为「隐藏品牌文字 + Logo 居中（56 宽内居中）」，或把折叠宽改成 64。

### 2.2 功能区（rail）

- 容器：Column，宽 **56**，高 100%，space **8**，padding top **16**，bottom **14**（触屏形态 **10**），bg `workspace_rail`，右边框 0.5。
- 按钮：**40×40**，圆角 **9**，padding 0，图标 **19**；选中态底色 `workspace_selection`，未选中透明。
- 图标颜色：选中 = `brand`，未选中 = `text_secondary`（`LexiIcon` 的 `muted`）。

从上到下（`Blank()` 之前的都在顶部，之后贴底）：

| # | 图标 | accessibility 文案 | 行为 | 选中条件 |
|---|---|---|---|---|
| 1 | `dock-vault` | 知识库 | `onSelectSection(1)`，清空路由栈 | `activeSection ≤ 1` |
| 2 | `search` | 快速切换文档 | 打开命令面板 switcher 模式 | 无 |
| 3 | 文本 "⌘"（**22**，`text_secondary`） | 命令面板 | 打开命令面板 commands 模式 | 无 |
| 4 | `note` | 切换编辑与阅读 | 执行命令 `reading` | 无 |
| 5 | `graph` | 笔记关联 | `showAuxiliary(2)` | `activeSection === 2` |
| — | `Blank()` 撑开 | | | |
| 6 | `trash` | 回收站 | 打开回收站 sheet | 无（永远 false） |
| 7 | `sys.symbol.gearshape`（19，`text_secondary`） | 设置 | 打开设置 | 无 |

- 第 1、2、3、4、5 项均可被设置项 `interfaceHiddenCommands` 隐藏（`commandVisible(id)`）；回收站与设置**始终显示**。
- 设置项 `interfaceRibbon = false` 时整个 rail 隐藏，设置齿轮会移到标签条最左侧（见 2.3）。

### 2.3 标签条（tabStrip）

容器：

| 属性 | 值 |
|---|---|
| 高 | **52 + topInset** |
| padding | left **8**；right = `windowButtonsInset > 0 ? windowButtonsInset + 4 : 12`；top = topInset |
| bg | `workspace_tabs` |
| 边框 | 底边 0.5 `workspace_line` |
| 子元素间距 | Row space **4** |

从左到右：

1. **侧栏开关**：40×40，圆角 7，透明底，`sys.symbol.list_bullet` **17**，`text_secondary`；accessibility "展开或收起知识库侧栏"。
2. **（可选）设置齿轮**：仅 `showRibbon === false` 时出现，40×40，`sys.symbol.gearshape` 19。
3. **标签滚动区**：`layoutWeight(1)`，高 100%，水平滚动、隐藏滚动条、`clip(true)`，内部 Row space **3**，底部对齐。
4. **新建按钮**：**76×36**，圆角 **7**，bg `workspace_selection`，padding left/right 8；内容 = `plus` 图标 17 + "新建"（**12**，Medium，`brand_ink`），间距 6；accessibility "新建内容"；点击弹原生 Menu。
5. **右侧栏开关**：**36×36**，圆角 7，透明底；图标 22×22，用 `app.media.ic_dock_panel_shown` / `ic_dock_panel_hidden`，`colorFilter(text_secondary)`；accessibility "收起右侧栏"/"展开右侧栏"。

#### 标签页尺寸计算（`core/LexiTabStripLayout.ets`）

```
gap = 3, minimum = 104, preferred = 196
tabWidth(viewport, count)  = clamp((viewport - (count-1)*3) / count, 104, 196)
contentWidth(viewport, n)  = n * tabWidth + (n-1) * 3
```

- viewport = 标签滚动区实测宽度（已扣掉 40 + 36 + 76 + 3×4 的间距与左右 padding）。
- 例：窗口 1440、侧栏 244 + rail 56、右栏关 → 标签条宽 1140，内宽 1120，viewport ≈ 1120 − 40 − 36 − 76 − 12 = **956**。
  - 3 个标签：(956−6)/3 = 316.7 → 封顶 **196**，总宽 594。
  - 8 个标签：(956−21)/8 = 116.9 → **116.9**，总宽 956（刚好铺满）。
  - 10 个标签：93.5 → 落到下限 **104**，总宽 1067 > 956，出现横向滚动。
- 自动滚动到激活标签：`revealOffset` 保证 `left ≥ offset` 且 `right ≤ offset + viewport`，带 0.5 vp 死区，用 frame callback 在下一帧执行。

#### 标签页外观

| 部分 | 规格 |
|---|---|
| 单个标签容器 | 宽 = tabWidth，高 **40**，圆角 **topLeft 8 / topRight 8**，`clip(true)` |
| 激活态 | bg `workspace_page`；顶边 **2 vp** `brand` 边框（其余边 0） |
| 非激活 | 透明底，无边框 |
| 标签主体按钮 | 高 **38**，`layoutWeight(1)`，padding left **14** / right **4**；内部 Row space **8** |
| 图标 | `mindmap`（`map:` 开头）或 `note`，**14**；未激活时 `muted` |
| 标题 | **12**，`text_primary`，单行，尾部省略；`layoutWeight(1)` |
| 关闭按钮 | **30×34**，透明底，`sys.symbol.xmark` **10**，`text_secondary`；accessibility "关闭 {0}" |
| 未保存点 | **不存在**（原工程没有实现） |

标签标题解析顺序：

- `map:` 前缀 → 导图标题，空则"未命名导图"；导图不存在时"思维导图"。
- 笔记 → `MarkdownEngine.displayTitle(note)`：`title.trim()` 非空用之；否则取正文第一行非空、剥掉 `# > * -` 前缀，截 **28 字符**；仍为空则"未命名速记"。
- 找不到笔记 → "无标题笔记"。

#### 新建菜单（原生 Menu）

| 项 | 行为 |
|---|---|
| 笔记 | `onCreateNote()`（宿主用 `createNote('markdown')`） |
| 思维导图 | `onCreateMap()` |
| 白板 | `onCreateCanvas()` |

### 2.4 窗口按钮留白（HarmonyOS 实现 → macOS 必须反向）

原工程（`EntryAbility.ets:150-215`）：

- `setWindowDecorVisible(false)` 隐藏系统装饰，`setWindowDecorHeight(52)` 让原生标题热区覆盖自绘 52 条。
- 窗口按钮样式：`buttonBackgroundSize = 32`、`buttonIconSize = 18`、`buttonBackgroundCornerRadius = 6`、`spacingBetweenButtons = 8`、`closeButtonRightMargin = 8`。
- 预留宽度 = `3*32 + 2*8 + 8 = 120`，再与 `getTitleButtonRect()` 上报值取 min，写入 `lexiWindowButtonsInset`（最大 120）。
- 标签条右侧 padding = `inset + 4`，即最大 **124**，紧贴红绿灯左侧。
- **按钮在窗口右上角**（HarmonyOS PC 习惯）。

macOS 移植要求：

- 红绿灯在**左上角**（3 个约 12 pt 的圆点 + 20 pt 间距 + 约 20 pt 前导）；建议标题条左起预留 **78–84 pt**，窗口化时启用，全屏时归零。
- 左侧 52 高品牌区会被红绿灯覆盖（Logo 现在 x = 14..42）。两种可行处理：
  1. 窗口化时把品牌区 leading 从 14 改为 **88**，Logo 右移，红绿灯下方留空；全屏时回到 14。
  2. 用 `NSWindow.standardWindowButton(.closeButton)` 等把红绿灯整体下移居中到 52 条内（需 AppKit 桥接），品牌区保持 14。
- 标签条右侧**不再需要 124 留白**，可回到 12–16；「右侧栏开关」将成为最右元素（右 padding 建议 12）。
- 若采用 `NSToolbar` / `.windowToolbarStyle(.unified)`，建议直接以 52 pt 高的自定义 titlebar accessory 承载「品牌区 + 标签条」，并保留 0.5 pt（1 px @2x）底部分隔线。
- 全屏/无边框/窗口化三态都要重算留白，且要在窗口满屏时隐藏圆角裁切（HarmonyOS 由系统处理）。

---

## 3. 左侧栏（知识库）

容器：宽 = `sidebarContentWidth()`，高 100%，padding **left 12 / right 12**，bg `workspace_sidebar`。
整列（含 rail）右侧有 0.5 `workspace_line`，外层 `clip(true)`，`zIndex(2)`。

### 3.1 自上而下结构（顺序即视觉顺序）

| # | 区块 | 高度 | 关键尺寸 |
|---|---|---|---|
| 1 | 标题行「知识库」+ 数量 | **48** | 文字 14 Medium；数量 11；padding left 6，right 0（触屏内联菜单时 44） |
| 2 | 搜索框 | 34（容器） | 圆角 7，bg `workspace_page`，0.5 边框；下边距 **14** |
| 3 | 「今日笔记」「模板」 | **34** | 12 号字，透明底，间距 6；下边距 **8** |
| 4 | 「全部笔记 / 收藏」分段 | **30** | 12 号字，圆角 6，padding 左右 10；下边距 **12** |
| 5 | 滚动列表（项目 → 文件夹 → 笔记 → 可视化空间） | layoutWeight(1) | 见 3.2–3.4，列表 Column space **4** |
| 6 | 底部工作区切换器 | **62**（桌面/2in1；触屏 **56**） | 顶边 0.5；padding left 10 / right **10**（触屏 48）/ bottom **0**（触屏 4） |

### 3.2 各区块细节

#### ① 标题行

- Row space 8，高 **48**，padding left **6**，right `inlineContextMenus() ? 44 : 0`。
- 「知识库」：**14**，Medium，`text_primary`，`layoutWeight(1)`。
- 数量：`visibleNotes().length`，**11**，`text_secondary`（筛选后计数，会随搜索/收藏联动）。
- 整行被 `LexiContextSurface` 包裹 → 右键出「工作区」上下文菜单（见 §9.8）。

#### ② 搜索框

- 外容器 Row space 6，宽 100%，padding left **10** / right **8**，圆角 **7**，bg `workspace_page`，四边 **0.5** `workspace_line`，下边距 14。
- 左图标 `search` **15**。
- `TextInput`：高 **34**，`layoutWeight(1)`，padding 0，字号 **12**，`text_primary`，placeholder `搜索 · tag: type: notebook:`（`text_secondary`），caret `brand`，背景透明。
- 清除按钮：仅输入非空时出现，**28×32**，`sys.symbol.xmark` **10**，`text_secondary`，accessibility "清空搜索"。
- 支持查询语法（`core/LexiSearch.ets`）：`tag:#标签`、`type:study`、`notebook:分类`、`path:`、`[属性名]值`、`-否定`。

#### ③ 今日笔记 / 模板

- Row space 6，宽 100%，下边距 8。
- 两个 `ButtonStyleMode.TEXTUAL` 按钮：高 **34**，字号 **12**，无背景、无圆角（走系统 TEXTUAL 样式，文字色取主题 `brand`）。
- 文案："今日笔记"、"模板"；分别执行命令 `daily`、`templates`。
- 未设宽度/权重 → **按内容自适应宽度，左对齐**（不是等分）。

#### ④ 全部笔记 / 收藏

- Row space 6，宽 100%，下边距 12。
- 两个按钮：高 **30**，字号 **12**，圆角 **6**，padding left/right **10**（触屏 48）。
- 选中（`favoritesOnly === false` 时"全部笔记"；`true` 时"收藏"）：文字 `brand_ink`，底 `workspace_selection`；未选中：文字 `text_secondary`，透明底。
- 仍是**内容自适应宽度**，不铺满（视觉上像两个 pills）。

#### ⑤ 列表容器

- `Scroll`，`layoutWeight(1)`，`scrollBar Off`，顶部对齐；内部 Column space **4**，宽 100%，左对齐。

### 3.3 文件夹树与笔记行

**项目行**（仅当未选中项目且无搜索词时显示，位于列表最上方）

| 属性 | 值 |
|---|---|
| 高度 | **40**，宽 100%，圆角 **7**，透明底 |
| padding | left **10**，right 10（触屏 48） |
| 内容 | `folder` 16 → 项目名 13 `text_primary` `layoutWeight(1)` 单行 → （收藏时）`star` 12 → `chevron` 12 |
| 点击 | `selectProject(id)`（会先 flush 全部文档） |

**文件夹组**（每个 notebook 一组）

| 属性 | 值 |
|---|---|
| 组容器 | Column space **2**，宽 100%，下边距 **8** |
| 组标题行 | 高 **36**，圆角 **6**，padding left **5** / right 10（触屏 48），透明底 |
| 箭头 | `sys.symbol.chevron_right` **9**，`text_secondary`；展开时 `rotate(90°)`，动画 **150ms EaseOut**；收起时 0° |
| 图标 | `folder` **15** |
| 组名 | 字号 **12**，`text_secondary`，单行省略，`layoutWeight(1)`（注意：组名是次要色，不是主色） |
| 计数 | 该组笔记数，字号 **10**，`text_secondary` |
| 行间距 | Row space **7**（箭头→图标→名字） |
| 折叠 | 点击切换；折叠时笔记行隐藏，**但搜索词非空时强制展开** |

文件夹名 = `note.notebook || '未分类'`；分组顺序 = 笔记数组首次出现顺序（即置顶优先、其余 `updatedAt` 降序）。未选中项目且无搜索时，带 `projectId` 的笔记**不进文件夹组**（只在项目行里）。

**笔记行**（`documentRow`）

| 属性 | 值 |
|---|---|
| 高度 | **38**，宽 100%，圆角 **7** |
| padding | left **14**，right 10（触屏 48） |
| 图标 | `study`（noteType==='study'）或 `note`，**15**；未选中时 `muted` |
| 标题 | 字号 **13**，单行省略，`layoutWeight(1)` |
| 选中态 | 底 `workspace_selection`；文字 `brand_ink` + **Medium**；且仅当 `activeSection ≤ 1` |
| 未选中 | 透明底；文字 `text_primary` + Regular |
| 收藏标记 | `favorite === true` → 行尾 `star` **12**（彩色 `brand`，不是 muted） |
| 置顶标记 | **无**（`pinned` 只影响排序） |
| 无日期/摘要 | 行内不显示时间、不显示预览 |
| 点击 | `onNoteOpenRequest(id)` 返回 false 时在本工作区开标签 |
| 右键 | 继承笔记上下文菜单（打开/副本/移动/收藏/路径/历史/模板/分享/重命名/移到回收站） |
| Row 间距 | space **8**（图标→标题） |

**空状态**（列表为空时，紧跟文件夹组之后）

- 单行 `Text`，字号 **12**，行高 **22**，`text_secondary`，宽 100%，padding **12**。
- 三种文案按优先级：有搜索词 → "没有找到匹配的笔记"；否则仅收藏 → "收藏的笔记会出现在这里"；否则 → "写下第一条笔记"。

### 3.4 可视化空间

仅当**无搜索词且未选中"收藏"**时显示：

| 部分 | 规格 |
|---|---|
| 分隔线 | `Divider`，色 `workspace_line`，上下边距各 **12** |
| 小标题 | "可视化空间"，**11**，`text_secondary`，宽 100%，padding left **6** / bottom **6** |
| 导图行 | 高 **38**，宽 100%，圆角 **6**，padding left **10** / right 10（触屏 48），Row space 8；图标 `mindmap` **15**；标题 **12**；选中 → 底 `workspace_selection` + 文字 `brand_ink` + Medium |
| 白板行 | 高 **38**，宽 100%，圆角 **6**，padding left **10**；图标 `canvas` **15**；标题 **12** `text_primary`；**白板行没有选中态**（点击是打开独立窗口/路由） |
| 排序 | 导图按传入顺序，白板按传入顺序（均先按当前项目过滤；导图还过滤 `trashedAt === 0`） |
| 空标题回退 | 导图"未命名导图"、白板"未命名白板" |

### 3.5 底部工作区切换器

| 属性 | 值 |
|---|---|
| 容器 | Button 包行，宽 100%，高 **62**（桌面/2in1；触屏 **56**） |
| padding | left **10**，right **10**（触屏 48），bottom **0**（触屏 **4**） |
| 边框 | 顶边 **0.5** `workspace_line`；圆角 0；透明底 |
| 图标 | `folder` **17** |
| 主行 | 工作区名，**12**，Medium，`text_primary`，单行省略 |
| 副行 | 项目名，**10**，`text_secondary`，无省略设置 |
| 行间距 | Column space **3**（一个 Column 内两行），整体 Row space **8** |
| 尾部 | `sys.symbol.chevron_right` **10**，`text_secondary` |
| 交互 | `bindMenu` 打开工作区菜单；同时绑定"打开工作区"sheet |
| accessibility | "工作区与项目" |
| id | `workspace-switcher` |

工作区菜单内容（原生 Menu）：

```
[MenuItemGroup header: 选择工作区]
  {vault.name}                       ← 当前项显示 "{name} · 当前"
  ...（每个 workspace）
[MenuItemGroup header: 当前工作区的项目]
  全部项目                            ← 当前项显示 "全部项目 · 当前"
  {project.name}                     ← 当前项显示 "{name} · 当前"
[MenuItem] 工作区与项目…               ← id: workspace-manager-entry
[MenuItem] 文档管理
```

### 3.6 侧栏拖拽调宽

- 热区：**10 vp** 宽，覆盖在侧栏右缘，`zIndex` 默认（右侧栏的是 1），透明底。
- 可见线：默认 **0.5** `workspace_line`；hover 或拖拽中 → **2 vp** `brand`。
- 拖拽：`PanGesture` 水平方向、distance 1；起始值 = 当前内容宽，`newWidth = start + offsetX`。
- 结束写入设置（clamp 200–480）；失败 Toast "侧栏宽度保存失败，请重试。"。
- 光标：hover/拖拽时 `RESIZE_LEFT_RIGHT`，否则恢复默认。
- 右栏同理，方向相反：`newWidth = start - offsetX`，clamp 232–560，写入失败同一句 Toast。
- accessibility："拖动调整知识库侧栏宽度" / "拖动调整右侧栏宽度"。

---

## 4. 编辑器顶部（工具条 48 vp）

容器：Row space **6**，高 **48**，宽 100%，padding left **28** / right **16**，底边 0.5 `workspace_line`，id `workspace-editor-toolbar`。

### 4.1 面包屑（可被设置关闭）

设置项 `interfaceTabHeaders`（默认 true）为 true 时显示：

| 元素 | 规格 |
|---|---|
| 文件夹图标 | `folder` **15** |
| 笔记本名 | `note.notebook || '知识库'`，**12**，`text_secondary`，单行省略（**无 `layoutWeight`**，长名可能挤压后面） |
| 分隔符 | "/" **12**，`text_secondary` |
| 当前标题 | `titleText || '无标题笔记'`，**12**，`text_primary`，单行省略，`layoutWeight(1)` |

为 false 时：用一个 `Blank().layoutWeight(1)` 顶掉左侧，右侧按钮不变。注意关闭的只是**面包屑**，标签条不受影响（尽管开关名叫 tabHeaders）。

### 4.2 三个按钮的真实语义（已核对源码）

| 按钮 | 文案逻辑 | 尺寸 | 颜色/背景 | 真实行为 |
|---|---|---|---|---|
| 源码/预览 | `editing ? '实时预览' : '源码'` | 高 **34**，padding L/R **14**，圆角 **7** | 文字 `brand_ink`；`editing` 时底 `workspace_selection`，否则透明 | 调用 `toggleSourceMode()`：`reading = false`，`editing = !editing`，清空补全、关闭工具弹层与语音面板；退出源码时先 `refreshDocument(true)` |
| 工具 | "工具" | 高 **34**，padding L/R **12**，圆角 **7** | 文字 `brand_ink`；底 **始终** `workspace_selection` | 打开 `bindPopup` 工具弹层（见 4.3）；未加载完成或冲突中时禁用 |
| 更多 | "更多" | 高 **34**，padding L/R **10**，圆角 **7** | 文字 `text_secondary`；透明底 | `bindMenu` 文档菜单（见 4.5） |
| （可选）大纲 | 仅图标 | **36×36**，圆角 7 | 图标 `list_bullet` 17 `text_secondary`；展开且 pane≥680 时底 `workspace_selection` | 仅 `externalInspector === false` 时存在；桌面工作区传 `true`，**所以桌面看不到这个按钮** |

accessibility 文案：

- 源码按钮：`当前为整篇源码编辑，切换到实时预览` / `当前为实时预览，切换到整篇源码编辑`
- 大纲按钮：`展开或收起大纲`

> 语义重点：按钮文字是**动作**（点击后去哪），不是状态。若在 macOS 用 segmented control 显示当前态，必须换成"实时预览 | 源码"的两段式并统一状态，或保留按钮形态但把文案改成"切换到源码"。

### 4.3 「工具」弹层

承载方式：`bindPopup`，`Placement.BottomRight`（锚在按钮右下），`enableArrow: true`，`autoCancel: true`，`focusable: true`，`popupColor = surface`。

| 属性 | 值 |
|---|---|
| 宽 | `min(312, max(236, paneWidth − 32))` |
| 高 | **320**（固定） |
| 内边距 | **12** |
| 背景 | `surface` |
| 圆角 | **16** |
| 内容 Column | space **8** |

**头部**：Row space 6

- 返回按钮（仅"链接"页）：**62×32**，圆角 8，`back` 图标 13 + "返回" 12 `brand_ink`，居中；accessibility "返回工具列表"。
- 标题：**14**，Medium，`text_primary`，单行省略，`layoutWeight(1)`；"笔记工具" / "插入笔记链接"。
- 关闭：`ButtonStyleMode.TEXTUAL`，高 30，字号 **11**，`brand_ink`，文案"关闭"。

**格式页**：`Flex(wrap)`，14 个格子；每格

| 属性 | 值 |
|---|---|
| 宽 | **32%**（+ 右外边距 1% → 每行 3 个） |
| 高 | **40** |
| 字号 | **12** |
| 圆角 | **8** |
| 外边距 | right 1%，bottom **6** |
| 颜色 | 文字 `brand_ink`，底 `soft_surface` |
| padding | 2 |

格子（按顺序）：

| 文案 | action | 插入内容（选中文本 S；无选中用占位词） |
|---|---|---|
| 粗体 | bold | `**S**`，占位 `粗体内容` |
| 斜体 | italic | `*S*`，占位 `强调内容` |
| 删除线 | strike | `~~S~~`，占位 `待修订内容` |
| 高亮 | highlight | `==S==`，占位 `重点内容` |
| 一级标题 | h1 | `\n# S\n`，占位 `章节标题` |
| 二级标题 | h2 | `\n## S\n`，占位 `核心小节` |
| 待办清单 | todo | `\n- [ ] S\n`，占位 `待完成事项` |
| 分割线 | hr | `\n\n---\n\n` |
| 表格 | table | `\n| 项目 | 内容 |\n| --- | --- |\n|  |  |\n` |
| 代码块 | code | `\n```\nS\n```\n` |
| 公式 | formula | `\n$$\nS$$\n`，占位 `f(n) = O(n \log n)` |
| 提示框 | callout | `\n> [!NOTE] 知识要点\n> S\n`，占位 `在此记录要点` |
| 笔记链接 | link | 切到"链接"页 |
| 语音 / 整理 | assistant | 关闭弹层 → 打开语音/整理 sheet |

**链接页**：

- 搜索输入：高 **36**，字号 **12**，bg `soft_surface`，placeholder "搜索笔记或输入新标题"。
- 候选列表：最多 **8** 条（排除当前笔记、已删除、按标题模糊匹配），每行 `width 100%`、高 **34**、字号 **12**、`brand_ink`，点击插入 `[[标题]]`。
- 若查询非空，末尾追加"插入此标题链接"（高 34、12 号），插入 `[[查询词]]`。

**关键时序**：点击格子不是立即插入，而是先记录选区快照、把 snippet 挂到 `pendingToolSnippet`、关闭弹层；等弹层的 `onDisappear` 再插入（避免弹层抢焦点导致选区丢失）。若动作是"语音/整理"，则 `onDisappear` 后再开 sheet。

### 4.4 代码块内工具条（唯一的"随内容浮动"条）

只在**实时预览模式点到代码块内部**时出现（`editingCode === true`），固定在源码输入框正上方，不跟随选区漂浮：

- Row space 4，宽 100%。
- 语言下拉 `Select`：字号 12，高 **36**，`layoutWeight(1)`，16 个选项（自动识别 / 纯文本 / ArkTS / TypeScript / JavaScript / JSON / Python / HTML / CSS / SQL / Java / C / C++ / Shell / Go / Rust）。
  - 显示文案：显式指定 → 语言名；未指定 → `自动：{检测语言}`；空 → "选择语言"。
- 按钮「代码 / 源码」：高 36，字号 12，padding L/R 6（切源码视图）。
- 按钮「格式化」：高 36，字号 12，padding L/R 6；源码视图下禁用。
- 按钮「完成」：高 36，字号 12，padding L/R 6；结束块编辑并回到整篇渲染。
- 源码框：`TextArea`，字号 `noteFontSize`，行高 1.75×，bg `soft_surface`，圆角 **10**，padding **12**；高度按内容估算：
  `columns = max(8, floor((contentWidth − 24) / (8.5 × fontSize/16)))`；
  `lines = Σ ceil(宽字符数 / columns)`（CJK 记 2 宽）；
  `height = max(56, min(contentWidth > 700 ? 600 : 360, lines × fontSize × 1.75 + 24))`。
- placeholder："在这里输入代码" / 普通段落用 "从一个想法开始。支持 Markdown、#标签与 [[双向链接]]。"（源码整篇模式）或实时预览的 "点按这里开始记录。支持 Markdown、#标签与 [[双向链接]]。"。

> **没有**基于文本选区的浮动工具条（无 "B / I / U" 气泡）。若 macOS 版想加，属于新增设计，不是复刻。

### 4.5 「更多」菜单（原生 Menu）

| 菜单项 | 行为 |
|---|---|
| 撤销正文编辑 | 自定义撤销栈回退；`historyCount > 0` 才可用 |
| 文档属性与高级编辑 | flush 后跳「高级编辑」路由（`onOpenAdvancedNote`） |
| 导出 Markdown | flush 后走文档选择器导出 `{title}.md` |
| 系统分享文件 | 调 `LexiShareService.shareDraftNote`，锚点 id `workspace-document-more` |
| 在文件管理中显示 | `LexiFileActions.reveal` |
| 生成思维导图 | flush 后 `onConvertMap(noteId)` |

### 4.6 条件出现的三个条（非默认）

- **拼写检查面板**：`spellingOpen` 时，高 **140**，padding 8，可滚动；头部 "英文拼写检查" 12 + "重新检查" 12；每条问题 = 单词 12 + 若干建议按钮 11。
- **查找替换条**：`findOpen` 时，Row space 8，padding 8；两个 `TextInput` 各 `layoutWeight(1)` 高 **36**（placeholder "查找内容" / "替换为"），按钮「下一个」「替换」「全部替换」「关闭」均 12 号。
- **多光标提示条**：`extraCarets.length > 0` 时，Row space 8，文案 "{n} 个输入光标" 12 + 按钮"取消多光标" 12。

---

## 5. 编辑器正文

### 5.1 文档列

- 滚动容器 `Scroll`，`layoutWeight(1)`，高 100%，滚动条 Auto，顶部对齐；`enableScrollInteraction` 受 `wheelZoomLock` 控制（锁定时禁用滚动）。
- 内容 Column：`width 100%`，`constraintSize({ maxWidth: editorLimitWidth ? 800 : 10000 })`，**居中**，padding **left 56 / right 56 / top 42 / bottom 80**，左对齐。
- 字号缩放：正文所有字号/行高都按 `noteFontSize / 16` 比例乘算（`LexiMarkdownPreview` 内统一处理）。
- 段落块纵向间距 **12**（预览最外层 Column space 12）。

### 5.2 标题与元信息

**标题**

- `TextArea`，`enabled(!conflictResolving && !locked)`，宽 100%，`minHeight 44`，padding 0，背景透明，圆角 0。
- 字号 **30**，行高 **40**，**Bold**，`text_primary`；placeholder "无标题笔记"（`text_secondary`）；caret = 主题 accent。
- 输入中的换行被替换为空格（标题永远单行）。
- 设置项 `editorShowTitle`（默认 true）为 false 时整块隐藏（此时只能靠面包屑/标签页看标题）。

**元信息行**（标题下方）

- Row space **8**，宽 100%，下边距 **14**。
- 类型标签：`noteType === 'study'` → "学习笔记"；`'quick'` → "快速笔记"；其他 → "Markdown"。字号 **11**，色 `brand_ink`。
- 分隔点 "·"，**11**，`text_secondary`。
- 字符数："`{bodyText.length} 字符`"，**11**，`text_secondary`。注意这是 UTF-16 长度（emoji 记 2），与底部状态栏同一个数值口径。
- 最多 **3** 个标签：`#{tag}`，**11**，`brand_ink`，无底色、无圆角（与卡片版不同）。

### 5.3 三种显示模式与切换逻辑

| 模式 | 触发 | 渲染 | 编辑能力 |
|---|---|---|---|
| **实时预览**（默认） | `reading=false, editing=false` | `LexiLiveMarkdownEditor`：整篇按块渲染；点击某块 → 该块替换为源码输入框，其余块保持渲染 | 块级就地编辑 |
| **整篇源码** | `editing=true` | 单个 `TextArea` 覆盖全文 | 全文源码 |
| **阅读视图** | `reading=true` | `LexiMarkdownPreview`（`frameless: true`），只读 | 待办可勾选、链接可跳转 |

状态来源与互斥规则：

- 初始化：`editing = (editorDefaultMode === 'source')`；`reading = (editorDefaultView === 'preview')`。默认 `live` + `edit` → 实时预览。
- `toggleSourceMode()`：强制 `reading = false`，翻转 `editing`；退出源码时刷新一次文档（含链接）。
- `toggleReading()`（命令 `reading` / 状态栏标签）：`reading = !reading`；先把块编辑收尾。
- 任何格式动作、跳转大纲、查找命中都会 `reading = false`。
- 折叠态（`folded`）优先于以上三者：显示所有标题按钮 + "展开当前笔记"。
- 加载失败态优先：显示"文档暂时无法打开" 24 号 + "重新读取"按钮。

**块级编辑细节**（实时预览）

- 进入：点击某块（`editable` 且非数学块，且距上次交互 > 150ms）。
- 编辑时该块前/后的内容分别渲染为 `leadingBlocks` / `trailingBlocks`，中间是源码 `TextArea`。
- 失焦自动 `finishEditing()`（代码块除外，需要"完成"按钮）。
- 光标推进：若输入的是块起始标记（如连续 `#`、`-`、`>` 等，由 `shouldAdvance` 判定），自动重新选中该块。
- 代码块进入时自动解析 fence、识别语言、可格式化。

### 5.4 实时预览块样式（`LexiEditorPanels.ets`，frameless = true）

| 块 | 字号 / 行高 | 额外样式 |
|---|---|---|
| 段落 | **16 / 28** | — |
| H1 | **24 / 34** | 加粗 |
| H2 | **20 / 28** | 加粗 |
| H3 | **17 / 28** | 加粗 |
| 待办 | 16 / 26 | `Checkbox` 选中色 = accent，方块与文字间距 10；勾选后文字加删除线并转 `text_secondary` |
| 无序 / 有序 | 16 / 26 | 前缀 "•" 或 "{n}."，**15** Medium，`brand`，与正文间距 9 |
| 引用 | 14 / 23 | 块 padding **14**，底 `brand_soft`，圆角 **12**，文字 `text_secondary` |
| 提示框 | 14 / 23 | 同上；顶部多一行 `✦ {meta || 'NOTE'}`，**11** Bold，`brand` |
| 代码块 | **13 / 21**（等宽） | 块 padding 14，底 `soft_surface`，圆角 12；头部语言标签 11 + "复制代码" 11（高 28） |
| 公式块 | 16 / 依赖渲染 | 同上容器 |
| 分割线 | — | `Divider` 1 vp，`divider`，上下边距 10 |
| 表格 | 单元格 **13 / 21** | 单元格宽 **156**、padding **12**、`minHeight 46`、边框 0.5 `divider`；表头底 `brand_soft`，斑马纹 `soft_surface`（偶数行）与 `surface`；整表横向滚动 |
| 图片 | — | 宽 100%，`maxHeight 420`，`contain`，圆角 10；alt 文字 12 `text_secondary`；外层 padding 8、底 `soft_surface`、圆角 12；失败显示 "图片暂时无法显示" 13 |
| 嵌入笔记 | 14 / 23 | padding **16**，底 `soft_surface`，1 vp `divider` 边框，圆角 **12**；头部 `↗ {title}` 13 Bold `brand_ink` + "引用笔记" 10 `text_secondary` |
| 行内代码 / 高亮 / 删除线 / 链接 | 继承所在块 | 行内代码：等宽 + `soft_surface` 底 + 圆角 3；高亮：按颜色 `#40F87171 / #40FB923C / #60FACC15 / #404ADE80 / #4060A5FA / #40C084FC`，未指定用 `brand_soft`；链接：accent 色 + 下划线 |

列表/待办/引用/代码/表格的块容器 `id` = `workspace-block-{noteId}-{owner}-{lineIndex}`，用于大纲跳转定位。

### 5.5 源码模式与实时预览的源码框

- 整篇源码：`TextArea`，`minHeight 460`，字号 `noteFontSize`（16），行高 `fontSize × 1.75`，背景透明，padding 0，caret = accent。
- 块内源码：见 4.4（有底色 `soft_surface`、圆角 10、padding 12）。
- 自动补全：在 `[[` 后弹 **笔记/章节** 候选、`#` 后弹 **标签** 候选，最多 6 条。
  - 面板：宽 100%，padding 6，圆角 **12**，底 `surface`，1 vp `divider` 边框。
  - 顶部提示："↑↓ 选择 · Enter 插入 · Esc 收起"，**10**，`text_secondary`，padding left 12 / top 7 / bottom 5。
  - 候选行：高 **36**，圆角 6，padding L/R 12，space 8；label **13** `text_primary`，detail **10** `text_secondary`（最大宽 140）；选中底 `brand_soft`。
  - 键盘：↑↓ 循环、Enter/Tab 插入、Esc 关闭。

### 5.6 自动保存与状态

- 正文每次变更：`revision++`，状态置 **"正在自动保存…"**。
- 防抖 **400 ms** 后 flush；成功后状态 **"已保存到本机"**；失败 **"保存失败 · 点击重试"**（点击状态文字可手动 flush）。
- 标题变更走同一路径。
- 冲突（其他窗口先保存）：弹系统对话框
  - 标题："笔记已在其他位置更新"
  - 正文："当前草稿仍然保留，可另存为副本，避免覆盖另一个窗口的修改。"
  - 主按钮 "保留草稿"，次按钮 "另存为副本"（副本标题 `{title}（冲突副本）` 或 `未命名笔记（冲突副本）`）
- 关标签：先 `flush()`；失败 Toast **"保存未完成，文档仍保留在标签页中。"** 并中止关闭。
- 自定义撤销：最多 **50** 步，600 ms 内合并；菜单项 "撤销正文编辑"。
- 锁定（命令 `lock`）：`locked = true` 后编辑区只读；再做格式动作抛 "当前笔记已锁定，请先解锁"。

### 5.7 底部状态栏

容器：Row space `paneWidth ≥ 600 ? 16 : 8`，高 **40**（桌面/2in1；触屏 44），宽 100%；padding left/right = pane≥600 ? **24/20** : **12/12**；bottom = 桌面 0（触屏 **4**）；顶边 0.5 `workspace_line`。

元素（从左到右，条件显示）：

| 元素 | 显示条件 | 尺寸 / 字号 | 内容 |
|---|---|---|---|
| 语音记录按钮 | 始终 | **104×32**，圆角 **8**，bg `soft_surface`，padding L/R 8，Row space 6 | `sys.symbol.mic` **15** `brand_ink` + "语音记录" **12** `brand_ink`；未加载/失败/冲突时禁用；accessibility "语音记录，打开离线语音速记" |
| 视图标签 | `editorViewStatus`（默认 true）**且** pane ≥ 600 | 高 32，字号 **11**，`text_secondary`，透明底 | 当前状态：`reading` → "阅读视图"；`editing` → "Markdown 源码"；否则 "实时预览"。点击切换 `reading`（**不切源码**） |
| 反向链接数 | pane ≥ 900 | 11，`text_secondary`，单行 | "{n} 个反向链接" |
| 字符数 | pane ≥ 480 | 11，`text_secondary`，单行 | "{n} 字符" |
| 保存状态 | 始终 | 11，`text_secondary`，`layoutWeight(1)`，尾部省略，右对齐 | 见 5.6；点击可重试 |

状态文案全集：`正在打开文档…`、`已保存到本机`、`正在自动保存…`、`保存失败 · 点击重试`、`文档读取失败`、`没有匹配内容`、`已替换 {n} 处`、`副本保存失败，当前草稿已保留`、`未找到章节「{anchor}」`（Toast）。

---

## 6. 右侧检查器

容器：宽 **280**（clamp 232–560，受窗口约束），高 100%，bg `workspace_inspector`，左边框 0.5 `workspace_line`，id `workspace-right-sidebar`。默认**关闭**（`rightSidebarOpen = false`）。

### 6.1 结构

1. **模式工具条**：高 **48**，水平 Scroll，scrollBar Off，Row space **4**，padding L/R **12**，底边 0.5。
   - 按钮：**30×30**，圆角 **5**，padding **6**，图标 **18**，`colorFilter(text_secondary)`。
   - 选中态底 `workspace_selection`，否则透明。
   - 顺序：Harness（仅插件已安装时）→ 大纲 → 其他插件（按安装顺序）。
2. **内容区**：`Scroll`，`layoutWeight(1)`，align Top，bg `workspace_inspector`；内部 Column padding **left 16 / right 16 / top 20 / bottom 24**，整体 space **6**。

### 6.2 模式清单（真实实现）

| 内部 mode 值 | 界面名称 | 如何进入 | 工具条高亮 |
|---|---|---|---|
| `outline` | 大纲 | 点大纲图标；或命令 `outline` | 大纲图标高亮 |
| `properties` | 笔记属性 | 命令 `properties` / 编辑器 `format('properties')` | **大纲图标仍高亮**（条件只判断是否以 `plugin:` 开头） |
| `outgoing` | 出链 | 命令 `outgoing` | 同上 |
| `backlinks` | 反向链接 | 命令 `backlinks` | 同上 |
| `plugin:<id>` | 插件视图 | 点插件图标 / `ctx.views.open()` | 对应插件图标高亮 |

> 这是原实现的**不一致点**：工具条实际只有"大纲 + 插件"入口，`properties/outgoing/backlinks` 三个模式没有独立图标，且进入后视觉上仍显示"大纲"被选中。macOS 版建议改成 4 个明确标签（大纲 / 出链 / 反向链接 / 属性）或合并进大纲页的折叠区。

### 6.3 各模式的字段与交互

**通用（所有模式）**

- 无打开笔记（`snapshot.noteId` 为空）→ 单行 "打开一篇笔记以查看大纲。"，**12**，行高 21，`text_secondary`。
- 有笔记 → 顶部标题：`snapshot.title || '未命名笔记'`，**13**，Medium，`text_primary`，最多 2 行，下边距 **12**。

**大纲 `outline`**

- 空 → "用 Markdown 标题梳理思路，大纲会出现在这里。"，12 / 21，`text_secondary`。
- 每个标题一行：
  - 高 `minHeight 34`，宽 100%，圆角 **6**，透明底；
  - padding：left = `8 + (level − 1) × 12`，right 8，top/bottom **7**；
  - 文字 **12 / 19**，最多 2 行，省略，左对齐，`text_primary`；
  - 点击 → `onRevealHeading`（编辑器滚动到该标题，偏移 -24）。
  - id：`workspace-right-heading-{headingId}`。
- 大纲下方（`outline` 与 `outgoing` 共用）：
  - 小标题 "出链 · {n}"，**12** Medium，`text_secondary`，margin top **22** / bottom **4**；
  - 每个出链：`targetTitle`，**12**，`brand_ink`，`minHeight 34`，padding L/R 8，透明底；点击打开 `targetId#anchor`。
- 反向链接区（`outline` 与 `backlinks` 共用）：
  - 小标题 "反向链接 · {n}"，同上；
  - 每行显示 `sourceTitle`，样式同上，点击打开来源笔记。

**属性 `properties`**

- 小标题 "笔记属性"，**12** Medium，`text_primary`。
- 空 → "暂无属性"，12，`text_secondary`。
- 每条：`{key}: {propValue}`，**12 / 20**，`text_secondary`，宽 100%。

**出链 `outgoing`**：只显示标题块 + 出链区（不出大纲）。
**反向链接 `backlinks`**：只显示标题块 + 反向链接区。

**插件 `plugin:<id>`**

- 未就绪：居中 Column（padding 16，space 12）。
  - 加载中 → "正在加载插件…"，12，`text_secondary`。
  - 出错 → 错误信息 12 / 20，`error`；若含 `E_PERMISSION_DENIED`，额外显示按钮 "设置插件权限"（12）；始终显示 "重试"（12）。
- 就绪：整块区域交给插件运行时（`PluginRuntimeHost`），宿主不绘制内容。

### 6.4 打开/关闭与联动

- 打开：点标题条右侧栏开关；命令 `inspector-toggle`；编辑器请求 `outline/backlinks/outgoing/properties`；插件 `views.open`。
- 打开时若 `可用宽 − 侧栏 − 右栏 < 420` → **自动收起侧栏**。
- 关闭：再点开关（toggle）。
- 侧栏重新展开时若剩余 < 420 → **自动关闭右栏**（`sidebarVisibilityChanged`）。
- 拖拽：见 3.6（热区 10，贴左缘，`zIndex 1`）。

---

## 7. 命令面板 / 快速切换

### 7.1 承载

宿主用 `bindSheet` 居中呈现（`preferType: SheetType.CENTER`，`dragBar: false`，`showClose: false`，`backgroundColor: workspace_page`，`radius: 16`，`keyboardAvoidMode: RESIZE_ONLY`）：

| 属性 | 计算 |
|---|---|
| 高 | `max(280, min(560, viewportHeight − 140))` |
| 宽 | `max(420, min(720, viewportWidth − 96))` |
| 圆角 | **16** |
| 面板自身 | 宽高 100%，bg `workspace_page`，`clip(true)` |

例：窗口 1440×900 → **720 × 560**。

### 7.2 头部

- Row space 12，padding **left 24 / right 18 / top 18 / bottom 14**，bg `workspace_sidebar`，底边 0.5。
- 左侧 Column space 3：
  - 标题：**18** Bold，`text_primary` — "命令面板" / "快速切换"。
  - 计数：**11**，`text_secondary` — "{n} 个命令" / "{n} 个文档"（实时随查询变化）。
- 右侧关闭按钮：**34×34** 圆形，透明底，`sys.symbol.xmark` **16**，`text_secondary`，accessibility "关闭命令面板"。

### 7.3 主体

- Column space 12，宽 100%，`layoutWeight(1)`，padding **left 24 / right 24 / top 16 / bottom 24 + bottomInset**，左对齐。
- **搜索框**：高 **44**，宽 100%，字号 **15**，圆角 **10**，bg `soft_surface`，caret `brand`，`defaultFocus(true)`，id `command-palette-input`。
  - placeholder：commands → "搜索命令…"；switcher → "搜索笔记、导图或白板…"。
  - 每次输入：选中索引归 0，结果列表滚回顶部。
- **操作提示**：**12 / 18**，`text_secondary`，最多 2 行。
  - commands → `↑ ↓ 选择 · Enter 执行 · Esc 关闭`
  - switcher → `支持 tag:#标签 type:study notebook:分类 · Enter 打开`
- **结果列表**：`Scroll`，`layoutWeight(1)`，scrollBar Auto，顶部对齐；Column space **2**。

### 7.4 结果行

| 属性 | 值 |
|---|---|
| 高 | **52** |
| 行间距 | **2** |
| 宽 | 100% |
| padding | L/R **12** |
| 圆角 | **8** |
| 选中底 | `brand_soft`；未选中透明 |
| 主文字 | **14**，选中 Medium / 未选中 Regular，`text_primary`，单行省略 |
| 次文字（hint） | **11**，`text_secondary`，单行省略；无 hint 则不占位 |
| 内部 | Column space 3，左对齐，宽 100% |
| id | `palette-result-{id}` |

> 面板**没有分组标题**：命令与插件命令、笔记/导图/白板都是平铺在一个列表里，没有 section header、没有类型分节。macOS 若要分组属于新增设计。

**行内容来源**

- commands 模式：
  - 主文字 = 命令标题（经 i18n）；
  - hint = 该命令的快捷键绑定，多个用 " / " 连接（如 `Ctrl+P`）；
  - 插件命令 hint 固定为 **"插件"**，标题原样显示不翻译；
  - 排序 = `LEXI_COMMANDS` 原顺序 + 插件命令追加在后。
- switcher 模式：
  - 笔记：主文字 = 显示标题，hint = "笔记 · {notebook}"；
  - 导图：主文字 = 标题（空则"未命名导图"），hint = "思维导图"；
  - 白板：主文字 = 标题（空则"未命名白板"），hint = "白板"；
  - 排序：按 `LexiSearch.rank` 升序（完全匹配 0、包含匹配 1+位置、子序列 100+间隙、不匹配 -1→1000），**截断到 60 条**。

### 7.5 空状态

- Column space 12，宽 100%，padding **top 48 / bottom 48**，居中。
- 主文案：**15**，`text_secondary`，居中 — "没有匹配的命令" / "没有匹配的文档"。
- 仅 switcher 且查询非空时：按钮 "新建「{query}」"，高 **44**，文字 `brand`，底 `brand_soft`，id `palette-create-note`。

### 7.6 键盘交互

| 键 | 行为 |
|---|---|
| ↑ / ↓ | 在结果中循环移动（取模），并把列表滚动到 `index × (52 + 2)`；阻止事件冒泡 |
| Esc | 关闭面板（`onClose`）；阻止冒泡 |
| Enter | 提交：有结果 → 执行当前选中项；无结果且 switcher 且有查询 → 用查询词新建笔记 |
| 输入任意字符 | 重置选中为 0、滚回顶部 |

打开时序：先置 `showPalette = true`，**180 ms** 后 `requestFocus('command-palette-input')`。从命令面板里再次打开面板时，先关再延迟 **120 ms** 重开。

### 7.7 相关全局命令

- 点击 rail 的 `search` 图标 → switcher 模式；`⌘` 图标 → commands 模式。
- 快捷键默认：`Ctrl+P` = 命令面板，`Ctrl+O` = 快速切换（macOS 建议改 `⌘P` / `⌘O`）。

---

## 8. 其他浮层、对话框与可复用文案

### 8.1 「打开工作区」sheet

- 尺寸：高 **410**，宽 **440**，`SheetType.CENTER`，`dragBar: false`，`showClose: false`，标题 "打开工作区"，bg `surface`。
- 内容：Column space 16，padding left/right 24 / top 12 / bottom 16，左对齐。
  - 工作区名：**20** Medium，最多 2 行省略。
  - 说明：**13**，`text_secondary` — "选择此工作区的打开方式。"
  - 按钮「在当前窗口打开」：宽 100%，高 **42**，圆角 **10**。
  - 按钮「在新窗口打开」：宽 100%，高 **42**，圆角 **10**，底 `brand_soft`，字 `brand`。
  - 复选行：`Checkbox` + "下次不再提示"（13，`text_primary`），Row space 8。
  - 脚注：**12**，`text_secondary` — "所有工作区共用此选择，可在“设置 → 编辑器”中重新选择。"
  - 文字按钮「取消」。

### 8.2 语音 / 本地整理 sheet

- 由底部状态栏「语音记录」或工具格「语音 / 整理」打开。
- 尺寸：高 `max(1, min(720, viewportHeight − 96))`；宽 = `viewportWidth ≥ 840 ? 680 : 100%`；宽屏居中、圆角 **24**、无拖拽条；窄屏从底部弹出、显示拖拽条；`showClose: true`；bg `surface`。
- 内容：Column space 14，padding **left 20 / right 20 / top 12 / bottom 20**。
  - 头部：标题 "语音与本地整理" **18** Medium + "关闭" 13 / 高 38。
  - 分段：两个文字按钮各 `layoutWeight(1)`、高 **40**、字号 **14**；选中底 `brand_soft`，文字 `brand_ink` — "语音速记" / "本地整理"。
  - 滚动内容：
    - 语音页：标题 "中文离线语音速记" 17 Medium；说明 13/21；按钮行「开始录音 / 正在识别…」「停止」「取消」各高 42、13 号；状态行 12/20（错误时 `error`）；文本框 高 **220**、15/25、bg `soft_surface`、圆角 12、padding 12；主按钮「插入文字到笔记」高 42、14 号。
    - 整理页：标题 "本地整理" 17；两段说明 13/21、12/20；按钮「整理当前笔记 / 重新整理当前笔记 / 正在匹配相关笔记…」高 40、13 号；状态 12/20；结果区含"摘录摘要（可编辑）"（复选框 + 14 Medium）、`TextArea` 高 140、14/23；"行动项" / "已有笔记链接" / "标签建议" 分节（14 Medium），链接 chip 高 **36**、标签 chip 高 **34**，圆角 9，选中底 `brand_soft`；主按钮「插入所选建议」高 42、14 号。
  - 底部固定说明：**11 / 18**，`text_secondary` — "语音与笔记内容均在本机处理。选择“插入”才会写入正文。"

### 8.3 模板选择器（`LexiTemplatePicker`）

> 桌面工作区里通过命令 `templates` 打开（宿主以 sheet 承载），组件本身不含窗口壳。

- Column space 16，宽高 100%，padding **left 24 / right 24 / top 8 / bottom 24**。
- 说明：13 / 20，`text_secondary` — "选择一个模板开始记录，也可以编辑内置模板，或创建自己的模板。"
- 错误行：12 / 19，`error`。
- 标题输入：高 **44**，圆角 **12**，padding L/R 14，bg `surface`，placeholder "新笔记标题（可选）"。
- 操作行：按钮「新建模板」高 **38**、13 号、圆角 12、底 `brand_soft`、字 `brand_ink`、右外边距 8；「清除日记默认」高 38、12 号、`text_secondary`。
- 模板卡：宽 100%，padding **18**，圆角 **20**，bg `surface`，0.5 `workspace_line` 边框；内部 space 12。
  - 标题 16 Medium，最多 2 行。
  - 徽标行：`内置`/`自建`（10，`brand_ink`，底 `brand_soft`，padding 7/3，圆角 6）、`{category || 通用}`（10，`text_secondary`，底 `surface`）、`日记默认`（10，`brand_ink`，底 `brand_soft`）。
  - 摘要：12 / 19，最多 3 行，`text_secondary`。
  - 按钮行：「使用模板」`layoutWeight(1)` 高 38、13 号、圆角 10、底 `brand_soft`；「编辑」高 38、12 号；「删除」高 38、12 号、`error`。
  - 底部整行：「设为日记默认」/「日记默认 ✓」，高 **34**，12 号。
- 空库：14 / 22，"模板库还没有内容。点击「新建模板」开始，或将已有笔记保存为模板。"，padding 20。

### 8.4 回收站 sheet

- 头部：Row space 12，padding **left 24 / right 18 / top 18 / bottom 14**，bg `workspace_sidebar`，底边 0.5。
  - 标题 "回收站" 18 Bold；副标题 "{n} 篇已删除笔记" 11 `text_secondary`。
  - 「清空」按钮（有内容且非忙）：高 **38**，12 号，`brand`，底 `brand_soft`，圆角 **19**，padding L/R 16。
  - 关闭：34×34 圆形，xmark 16。
- 内容：Scroll，Column space 14，padding **left 24 / right 24 / top 16 / bottom 24 + bottomInset**。
  - 说明：13 / 22，"删除的笔记会保留在这里，可恢复或永久删除。"
  - 空态：`trash` 图标 36（muted）+ "回收站是空的" 18 Medium；padding 上下 72。
  - 卡片：padding **20**，圆角 **20**，bg `surface`，space 12；标题 17 Medium 最多 2 行；摘要 13 / 21 最多 3 行；按钮「恢复」（44 高，`brand`）「永久删除」（44 高，`error`），space 12。

### 8.5 删除确认（五套，文案不同）

1. **笔记 / 文件夹（移到回收站）**
   - 标题："移到回收站？"
   - 正文："「{标题}」中的笔记可从回收站恢复。"
   - 按钮："取消"（`text_secondary`） / "移到回收站"（`error`）
2. **导图 / 白板（空间文件）**
   - 标题："删除这个文件？"
   - 正文："「{标题}」将被删除，此操作无法撤销。"
   - 按钮："取消" / "删除"（`error`）
3. **工作区 / 项目（从列表移除）**
   - 标题："从列表移除？"
   - 正文："原文件与内容保留。可在工作区管理的“已移除”区域重新启用。"
   - 按钮："取消" / "移除"（`error`）
4. **回收站内永久删除**
   - 单篇："永久删除这篇笔记？" + "「{标题}」将被永久删除，此操作无法撤销。"
   - 清空："{n} 篇笔记将被永久删除，此操作无法撤销。"
   - 按钮："取消" / "永久删除"（`error`）
5. **删除模板**
   - 标题："删除「{模板名}」？"（空名用 "未命名模板"）
   - 正文："此操作只删除模板，不影响已经用它创建的笔记。" +（内置时）"内置模板删除后也不会自动恢复。" +（是日记默认时）"当前日记默认模板也会被清除。"
   - 按钮："取消" / "删除模板"（`error`）

### 8.6 Toast 文案（`promptAction.showToast`）

| 场景 | 原文 |
|---|---|
| 侧栏/右栏宽度保存失败 | 侧栏宽度保存失败，请重试。 |
| 关标签时保存失败 | 保存未完成，文档仍保留在标签页中。 |
| 通用保存失败 | 保存未完成，请重试。 |
| 切换项目失败 | 切换项目失败，文档已保留。 |
| 切辅助视图失败 | 保存未完成，文档已保留，请重试。 |
| 工作区不存在 | 工作区不存在或已归档 |
| 打开方式未保存 | 工作区已打开，但打开方式未保存，请在设置中重试。 |
| 切换工作区失败 | 保存或切换失败，当前文档已保留，请重试。 |
| 读取打开方式失败 | 读取工作区打开方式失败，请重试。 |
| 命令异常兜底 | 操作未完成，当前文档已保留，请重试。 |
| 复制代码成功/失败 | 代码已复制 / 复制失败，请重试 |
| 找不到章节 | 未找到章节「{anchor}」 |
| 无法打开链接 | 无法打开此链接 |
| 导出失败 | 导出未完成 |
| 分享失败 | 系统分享未完成 |
| 打开文件夹失败 | 无法打开笔记所在文件夹 |
| 搜索面板打开失败 | 保存未完成，请重试。 |

### 8.7 空状态 / 加载态 / 错误态一览

| 场景 | 呈现 | 原文 |
|---|---|---|
| 工作区无打开文档 | 居中 Column（space 12），图标 32 + 标题 20 Medium + 说明 13 | `选择或新建一篇笔记` / `从左侧打开已有笔记，或点击右上角“新建”开始记录。` |
| 侧栏无匹配 | 单行 12 / 22，padding 12 | `没有找到匹配的笔记` |
| 侧栏仅收藏为空 | 同上 | `收藏的笔记会出现在这里` |
| 侧栏完全为空 | 同上 | `写下第一条笔记` |
| 右栏无打开笔记 | 单行 12 / 21 | `打开一篇笔记以查看大纲。` |
| 右栏大纲为空 | 单行 12 / 21 | `用 Markdown 标题梳理思路，大纲会出现在这里。` |
| 右栏属性为空 | 单行 12 | `暂无属性` |
| 命令面板无结果 | 15 号居中，padding 上下 48 | `没有匹配的命令` / `没有匹配的文档` |
| 回收站为空 | 图标 36（muted）+ 18 Medium，padding 上下 72 | `回收站是空的` |
| 回收站读取失败 | 可点击按钮（整条错误文案） | `读取回收站失败，请重试` |
| 模板库为空 | 14 / 22，padding 20 | `模板库还没有内容。点击「新建模板」开始，或将已有笔记保存为模板。` |
| 插件加载中 | 12，居中 | `正在加载插件…` |
| 插件加载失败 | 12 / 20，`error`；可附按钮 | `{错误信息}` + `设置插件权限`（权限类）/ `重试` |
| 文档加载中 | 状态栏文本 | `正在打开文档…` |
| 文档读取失败 | 24 号标题 + 按钮 | `文档暂时无法打开` / `重新读取`（状态栏同时变 `文档读取失败`） |
| 保存失败 | 状态栏 11 号，可点击重试 | `保存失败 · 点击重试` |
| 查找无结果 | 状态栏 | `没有匹配内容` |
| 图片加载失败 | 13 号，padding 18 | `图片暂时无法显示` |
| 嵌入笔记缺失 | 预览内 14 号正文 | `未找到引用的笔记，点击查找或创建。` / `未找到对应章节，点击打开原笔记。` / `这篇笔记还没有正文。` |
| 语音不可用 | 12 / 20 | `这台设备未提供离线语音识别，可在下方手动输入。` |
| 语义匹配失败 | 12 / 20（追加在建议后） | `语义匹配暂不可用，已保留原文摘录与规则建议。` |

---

## 9. 全部可复用中文文案（原文照抄）

> 所有文案均走 `LexiI18n.text()`，`en` 环境下查 `core/LexiEnglish.ets`；上表与下表给的是**中文源串**。

### 9.1 桌面骨架 / 标签条

```
知识库
设置
新建
新建内容
笔记
思维导图
白板
标签组
关闭分组
选择或新建一篇笔记
从左侧打开已有笔记，或点击右上角“新建”开始记录。
展开或收起知识库侧栏
展开右侧栏
收起右侧栏
关闭 {0}
```

### 9.2 左侧栏

```
知识库
搜索 · tag: type: notebook:
清空搜索
今日笔记
模板
全部笔记
收藏
未分类
未命名导图
未命名白板
可视化空间
没有找到匹配的笔记
收藏的笔记会出现在这里
写下第一条笔记
工作区与项目
全部项目
全部项目 · 当前
{0} · 当前
选择工作区
当前工作区的项目
工作区与项目…
文档管理
拖动调整知识库侧栏宽度
拖动调整右侧栏宽度
```

### 9.3 编辑器

```
无标题笔记
知识库
源码
实时预览
工具
更多
笔记工具
插入笔记链接
返回
返回工具列表
关闭
搜索笔记或输入新标题
插入此标题链接
粗体
斜体
删除线
高亮
一级标题
二级标题
待办清单
分割线
表格
代码块
公式
提示框
笔记链接
语音 / 整理
撤销正文编辑
文档属性与高级编辑
导出 Markdown
系统分享文件
在文件管理中显示
生成思维导图
英文拼写检查
重新检查
{0} 个输入光标
取消多光标
查找内容
替换为
下一个
替换
全部替换
文档暂时无法打开
重新读取
学习笔记
快速笔记
Markdown
{0} 字符
语音记录
语音记录，打开离线语音速记
阅读视图
Markdown 源码
{0} 个反向链接
正在打开文档…
已保存到本机
正在自动保存…
保存失败 · 点击重试
文档读取失败
没有匹配内容
已替换 {0} 处
副本保存失败，当前草稿已保留
当前笔记已锁定，请先解锁
请将光标放在需要重命名的标题行
文档尚未保存
从一个想法开始。支持 Markdown、#标签与 [[双向链接]]。
点按这里开始记录。支持 Markdown、#标签与 [[双向链接]]。
在这里输入代码
自动识别
选择语言
自动：{0}
代码
源码
格式化
完成
↑↓ 选择 · Enter 插入 · Esc 收起
```

预览块内文案：

```
未找到引用的笔记，点击查找或创建。
未找到对应章节，点击打开原笔记。
这篇笔记还没有正文。
图片暂时无法显示
笔记图片
引用笔记
未指定语言
 · 自动识别
复制代码
代码已复制
复制失败，请重试
```

冲突对话框：

```
笔记已在其他位置更新
当前草稿仍然保留，可另存为副本，避免覆盖另一个窗口的修改。
保留草稿
另存为副本
未命名笔记（冲突副本）
```

### 9.4 右侧检查器

```
打开一篇笔记以查看大纲。
未命名笔记
大纲
笔记属性
暂无属性
用 Markdown 标题梳理思路，大纲会出现在这里。
出链                     （渲染为「出链 · {n}」）
反向链接                 （渲染为「反向链接 · {n}」）
正在加载插件…
设置插件权限
重试
```

### 9.5 命令面板

```
命令面板
快速切换
{0} 个命令
{0} 个文档
搜索命令…
搜索笔记、导图或白板…
↑ ↓ 选择 · Enter 执行 · Esc 关闭
支持 tag:#标签 type:study notebook:分类 · Enter 打开
没有匹配的命令
没有匹配的文档
新建「{0}」
关闭命令面板
笔记 · {0}
思维导图
白板
插件
```

### 9.6 工作区 / 回收站 / 模板

```
打开工作区
选择此工作区的打开方式。
在当前窗口打开
在新窗口打开
下次不再提示
所有工作区共用此选择，可在“设置 → 编辑器”中重新选择。
取消
回收站
{0} 篇已删除笔记
清空
回收站是空的
删除的笔记会保留在这里，可恢复或永久删除。
恢复
永久删除
笔记已恢复
恢复失败，请重试
已永久删除
未能完成删除，请重试
读取回收站失败，请重试
选择一个模板开始记录，也可以编辑内置模板，或创建自己的模板。
新笔记标题（可选）
新建模板
清除日记默认
内置
自建
通用
日记默认
日记默认 ✓
设为日记默认
使用模板
编辑
删除
模板库还没有内容。点击「新建模板」开始，或将已有笔记保存为模板。
空白模板
模板删除失败，请重试。
```

### 9.7 语音 / 本地整理

```
语音与本地整理
语音速记
本地整理
中文离线语音速记
使用设备内置离线模型识别普通话，单次最长 60 秒。录音期间可预览，结束后可编辑文字。
开始录音
正在识别…
停止
取消
点击录音后才会请求麦克风权限。也可以直接输入文字。
这台设备未提供离线语音识别，可在下方手动输入。
离线识别未能启动，可继续手动输入。
识别结果会出现在这里，也可以手动输入 Markdown…
插入文字到笔记
文字已插入笔记。此处保留一份，便于继续修改。
本地整理
摘录原文摘要与行动项，并匹配已有笔记和标签。设备支持时会用离线语义模型对比最近 24 篇可用笔记。请检查后选择插入。
摘要和行动项为原文摘录、规则提取，不是生成式 AI 回答。
整理当前笔记
重新整理当前笔记
正在匹配相关笔记…
建议已生成，请勾选需要的内容，再插入笔记。
当前内容不足以整理，可先补充一些正文。
语义匹配暂不可用，已保留原文摘录与规则建议。
摘录摘要（可编辑）
行动项
已有笔记链接
标签建议
插入所选建议
所选内容已插入笔记，原正文保留。
语音与笔记内容均在本机处理。选择“插入”才会写入正文。
```

### 9.8 右键菜单文案（`LexiContextBridge.actions`）

```
新建笔记
新建文件夹
新建白板
新建数据库（表格笔记）
在新标签页中打开
在新标签组中打开
在新窗口中打开
打开笔记
打开思维导图
打开白板
创建副本
移动到…
在文件夹中查找
收藏
取消收藏
将该笔记合并到…
复制完整路径
复制相对路径
复制知萤 URI
打开版本历史
设为模板
系统分享文件
使用默认应用打开
在文件管理中显示
重命名
移到回收站
移除（保留原文件）
删除…
更多操作
```

> 桌面（2in1）使用分组上下文菜单，分组标题固定为：`打开`、`创建`、`整理`、`文件`、`管理`；菜单宽 **220**，圆角 **14**，背景 `surface`；`delete` 项文字为 `error` 色。菜单内行高在触屏形态为 48、圆角 0、底部 0.5 分隔线。

---

## 10. 面向 macOS 的移植注意事项

### 10.1 必须替换的 HarmonyOS 专有能力

| HarmonyOS 能力 | 用在哪 | macOS 替代方案 | 注意 |
|---|---|---|---|
| `bindSheet`（CENTER / BOTTOM，`dragBar`，`radius`，`backgroundColor`） | 命令面板、工作区打开方式、语音面板、回收站、模板 | SwiftUI `.sheet` / 自定义居中浮层（`NSPanel`） | 原设计是**居中卡片**而非底部抽屉；`radius` 需自绘（16 / 24），系统 sheet 圆角不同 |
| `bindPopup` + `enableArrow` | 「工具」弹层 | `NSPopover`（有箭头）/ SwiftUI `.popover` | 宽度随窗格变化：`min(312, max(236, pane−32))`；高度固定 320 |
| `bindMenu` / `Menu` / `MenuItemGroup` | 新建菜单、工作区菜单、更多菜单、右键菜单 | `NSMenu` / SwiftUI `Menu` / `.contextMenu` | 分组头（"选择工作区"、"当前工作区的项目"）用 `NSMenuItem.sectionHeader` 或 `Divider` |
| `showAlertDialog` / `showDialog` | 冲突、删除确认 | `NSAlert` / `.alert` | 原实现主按钮常是**取消**、次按钮是危险动作（顺序与 macOS 相反），移植时按 macOS HIG 调整顺序 |
| `promptAction.showToast` | 全部轻提示 | 自绘 HUD（顶部/底部浮层，1.6s） | 无系统等价物；原样式为系统短 Toast，无自定义尺寸 |
| `SymbolGlyph($r('sys.symbol.*'))` | xmark / gearshape / chevron_right / list_bullet / mic | SF Symbols | 见 10.4 映射表 |
| `Image($r('app.media.ic_*')).supportSvg2(true).colorFilter(...)` | 全部自绘图标 | SF Symbols（template rendering）或 PDF/PNG template asset | 原图标是单色 SVG，靠 `colorFilter` 二值着色，对应 `.renderingMode(.template)` + `.foregroundStyle` |
| 窗口装饰整合（`setWindowDecorVisible(false)`、`setWindowDecorHeight(52)`、`setDecorButtonStyle`、`getTitleButtonRect`） | 52 高自绘标题条 + 右侧留白 | `.windowStyle(.hiddenTitleBar)` / `titlebarAppearsTransparent` + `fullSizeContentView` | 红绿灯从右上改到左上，留白方向反转（详见 2.4） |
| 自定义密度缩放（`stage.setCustomDensity(density × zoom/100)`，75–150%） | 全局界面缩放 | 缩放根 `dynamicTypeSize` 或给根视图加 `scaleEffect` + 调整窗口最小尺寸 | 原实现连窗口 chrome 一起缩放；macOS 建议只缩放内容并保留原生 chrome |
| `pointer.PointerStyle.RESIZE_LEFT_RIGHT` + `onHover` | 侧栏/右栏拖拽手柄 | `onHover` + `NSCursor.resizeLeftRight` | 热区 10 pt，可见线 0.5→2 pt `brand` |
| `onKeyPreIme` 全局按键路由（Ctrl/Meta/Alt/Shift + 键名） | 全局快捷键 | `Commands` / `NSEvent.addLocalMonitorForEvents` | 原默认大量使用 `Ctrl`，macOS 需改 `⌘`（见 10.5） |
| `deviceInfo.deviceType === '2in1'` 分支 | 状态栏 40（触屏 44）、rail 底距 14（触屏 10）、切换器 62（触屏 56）、内联 `⋯` 菜单 44/48 | 固定取"桌面/2in1"分支 | 桌面工作区本来就跑在 2in1；直接采用 2in1 值（40、14、62、内联菜单 44，但 macOS 建议改右键） |
| 长按振动 / `vibrator` | 手机上下文菜单 | 删除 | 与桌面无关 |
| `Navigation` + `NavPathStack` 栈式路由 | 工作区把文档实例保活 | `ZStack` + `Visibility`（隐藏而非销毁） | 切标签**不能重建**编辑器实例（草稿、撤销栈、选区都在实例里） |
| `Flex(direction: Column/Row)` 分屏 | 上下/左右分屏 | `HSplitView` / `VSplitView` 或自定义 `HStack/VStack` | 见 10.6 命名陷阱 |

### 10.2 材质与动效

- **没有玻璃/模糊/渐变**：桌面工作区完全是纯色块 + 0.5 发丝线；`workspace_page / sidebar / rail / tabs / inspector` 五个面靠 4–6% 的亮度差分层。macOS 版建议**保持纯色**，不要引入 `NSVisualEffectView`，否则层级关系会变。
- 唯一渐变（`LexiTitleBackdrop`，56 高 scrim）**未在工作区使用**，只在手机页标题背景用到；不要误抄。
- 半透明色 token（`title_chip_active`、`title_chip_surface`、`dock_*`）也不在工作区使用，可忽略。
- 显式动效只有：
  - 文件夹三角 `rotate(0° ↔ 90°)`，**150 ms `Curve.EaseOut`** → SwiftUI `.rotationEffect(.degrees(90)).animation(.easeOut(duration: 0.15), value: expanded)`。
  - 手机端 Hero 标题 opacity 160 ms（不在工作区）。
  - 其余全靠系统 sheet/menu/popup 的默认转场。
- macOS 建议：标签切换**不加**滑动动画（原实现是瞬时 `visibility` 切换）；侧栏收起展开也建议瞬时或 ≤120 ms，避免与窗口 resize 抢帧。
- 焦点环：原实现按钮无自定义 focus ring（依赖系统）。macOS 上「工具」弹层 `focusable: true` → 需要保证 popover 可键盘操作。

### 10.3 字体与排版

| 用途 | 原字体 | macOS 建议 |
|---|---|---|
| 界面正文 | 系统默认（`HarmonyOS Sans` 被显式指定于预览 Span） | `SF Pro Text` / `.body` 体系 |
| 代码/行内代码 | 字符串 `'monospace'` | `SF Mono` / `.monospaced` |
| 笔记标题 | 30 Bold | `.system(size: 30, weight: .bold)`，行高 40 |
| 正文 | 16 / 28（1.75×） | `.system(size: 16)` + 调整 `.lineSpacing` 使行盒为 28（具体增量依赖字体度量，约 +9～12） |
| 文章最大宽度 | 800 外宽 / 688 文本宽 | 688 pt 文本列，居中 |

- 原实现所有预览字号按 `noteFontSize/16` 比例乘算；macOS 若支持字号设置，需同样对 24/20/17/14/13/12/11 全部按比例缩放，否则层级会乱。
- 中文字重：原工程用 `FontWeight.Medium`（500）与 `Bold`（700）；SwiftUI 对应 `.medium` / `.bold`，不要用 `.semibold` 替代 Medium。
- 字符数统计是 UTF-16 长度；macOS 若用 `String.count`（grapheme）会与「{n} 字符」对不上，需统一口径（建议改用 `utf16.count` 或在设置里说明）。

### 10.4 图标映射（SF Symbols 建议）

| 原 icon name | 资源 | SF Symbol 建议 | 尺寸 |
|---|---|---|---|
| `dock-vault` | ic_dock_vault | `books.vertical` | 19 |
| `search` | ic_search | `magnifyingglass` | 15 / 19 |
| `note` | ic_note | `doc.text` | 14 / 15 / 19 / 32 |
| `study` | ic_study | `graduationcap` | 15 |
| `markdown` | ic_markdown | `text.document` / `number` | 15 |
| `mindmap` | ic_mindmap | `point.topleft.down.to.point.bottomright.curvepath` | 14 / 15 |
| `canvas` | ic_canvas | `rectangle.3.group` | 15 |
| `graph` | ic_graph | `circle.hexagongrid` | 19 |
| `folder` | ic_folder | `folder` | 15 / 16 / 17 |
| `star` | ic_star | `star.fill` | 12 / 14 |
| `pin` | ic_pin | `pin.fill` | 14（仅卡片版用） |
| `trash` | ic_trash | `trash` | 19 / 36 |
| `chevron` | ic_chevron | `chevron.right` | 12 |
| `plus` | ic_plus | `plus` | 17 |
| `back` | ic_back | `chevron.left` | 13 |
| `link` | ic_link | `link` | 18 |
| （sys）`xmark` | 系统符号 | `xmark` | 10 / 16 |
| （sys）`gearshape` | 系统符号 | `gearshape` | 19 |
| （sys）`list_bullet` | 系统符号 | `sidebar.leading`（语义是"侧栏开关"）或 `list.bullet` | 17 |
| （sys）`chevron_right` | 系统符号 | `chevron.right` | 9 / 10 / 12 |
| （sys）`mic` | 系统符号 | `mic` | 15 |
| 右侧栏开关 | ic_dock_panel_shown / hidden | `sidebar.trailing` | 22 |
| rail 命令面板 | 文本 "⌘" | `command` | 22 |

> 原图标是**单色着色**：选中/强调 = `brand`，未选中 = `text_secondary`。SF Symbols 用 `.symbolRenderingMode(.monochrome)` + `.foregroundStyle`。注意原实现里「sidebar 开关」和「右侧栏开关」是**两个不同图标**，不要复用同一个。

### 10.5 键盘与菜单命令

原默认绑定（`LexiHotkeySettings.defaults`）多数以 `Ctrl` 开头（另有 `F1`/`F2`/`Alt+ENTER` 等），展示文本形如 `Ctrl+P`、`Ctrl+Alt+ARROWLEFT`。macOS 必须映射为 `⌘`，并处理冲突：

| 原绑定 | 建议 macOS | 命令 |
|---|---|---|
| `Ctrl+P` | `⌘P` | 命令面板（palette） |
| `Ctrl+O` | `⌘O` | 快速切换（switcher） |
| `Ctrl+N` | `⌘N` | 新建 Markdown 笔记 |
| `Ctrl+S` | `⌘S` | 保存当前文件 |
| `Ctrl+W` | `⌘W` | 保存并关闭当前标签 |
| `Ctrl+E` | `⌘E` | 切换编辑与阅读 |
| `Ctrl+F` / `Ctrl+Alt+F` | `⌘F` / `⌥⌘F` | 查找 / 替换 |
| `Ctrl+Shift+F` | `⇧⌘F` | 全局搜索 |
| `Ctrl+B` / `Ctrl+I` | `⌘B` / `⌘I` | 加粗 / 斜体 |
| `Ctrl+K` | `⌘K` | 插入链接 |
| `Ctrl+L` | `⌘⇧L` | 待办（`⌘L` 在 macOS 常被占用，建议改） |
| `Ctrl+/` | `⌘/` | 注释 |
| `Ctrl+;` | `⌘;` | 增加笔记属性 |
| `Ctrl+D` | `⌘⇧D` | 删除段落（避开 macOS 的"Duplicate"） |
| `F2` | `↩`（重命名） | 编辑文件名 |
| `Ctrl+G` | `⌥⌘G` | 笔记关联（`⌘G` 是"查找下一个"） |
| `Ctrl+,` | `⌘,` | 打开设置 |
| `Ctrl+Shift+T` / `Ctrl+TAB` / `Ctrl+Shift+TAB` | `⇧⌘T` / `⌃⇥` / `⌃⇧⇥` | 重开标签 / 下一个 / 上一个标签 |
| `Ctrl+1…8` / `Ctrl+9` | `⌘1…⌘8` / `⌘9` | 第 n 个 / 最后一个标签 |
| `Alt+ENTER` / `Ctrl+ENTER` / `Ctrl+Alt+ENTER` / `Ctrl+Alt+Shift+ENTER` | `⌥↩` / `⌘↩` / `⌥⌘↩` / `⇧⌥⌘↩` | 打开光标处链接（4 种打开方式） |
| `Ctrl+Alt+←/→` | `⌘[` / `⌘]` | 后退 / 前进 |
| `F1` | `⌘?` | 使用说明 |

其它：

- 命令面板的快捷键展示直接读绑定数组并用 `" / "` 连接；macOS 版应换成 `⌘` 符号键帽（不要显示 `Ctrl+P`）。
- 原实现支持 META 修饰键检测（`event.metaKey === 1` → "Meta"），但没有默认绑定用到；移植后所有原 `Ctrl` 建议统一改 `⌘`。
- 菜单命令应迁移到 macOS 主菜单栏（File / Edit / View / Format / Window / Help），并保留命令面板作为可搜索入口（共 **174** 条命令，见 `LEXI_COMMANDS`）。

### 10.6 术语/命名陷阱（会直接影响行为）

1. `split-vertical` 命令实际是 **`splitVertical = true` → `FlexDirection.Column` → 上下分屏**；`split-horizontal` 才是左右分屏。命名与直觉相反，macOS 菜单项文案是"上下分屏 / 左右分屏"，实现时按文案走。
2. 左右分屏时 `editorPaneWidth = 可用宽 / 2`；上下分屏时**不折半**（因为宽度不变）。
3. 切标签靠 `visibility` 隐藏而非销毁，所有标签的编辑器实例常驻；`editorController` 是每标签一个。macOS 需同等保活（`ZStack` + `.opacity(0)/.allowsHitTesting(false)`，不要用 `if` 重建）。
4. 关标签顺序：先 flush → 成功才从 `tabs` 移除，并把 id 压入 `closedTabIds`（供 `tab-reopen`）；失败只 Toast 不关。
5. 重新打开标签按 `closedTabIds.pop()` 后进先出；目标已失效（被删/项目不匹配）则静默忽略。
6. 命令 `link-open*` 会解析光标所在位置的 `[[...]]` 或 `[...](...)`；`Ctrl+Alt+Shift+ENTER` 是"新窗口打开"。
7. 「更多 → 生成思维导图」与命令 `convert` 都是把当前笔记转成导图（`onConvertMap`）。
8. 大纲跳转偏移固定 **−24**：滚动到「目标块相对视口的偏移 − 24」，即标题最终停在视口顶部下方 24 pt 处（留呼吸空间）。
9. 阅读视图的待办勾选会直接改正文并触发自动保存；不是只读。
10. 侧栏底部切换器中"全部项目"是默认值（`activeProjectName` 初值即"全部项目"）。

### 10.7 状态与数据契约（影响 UI 呈现）

| 状态 | 影响 |
|---|---|
| `tabs` 为空或 `selectedId` 为空 | 编辑区显示空状态（图标 32 + 20 号标题 + 13 号说明），底 `workspace_page` |
| `activeSection > 1` | 编辑区整体替换为 `auxiliaryContent()`（关联图 / 文档管理），标签/侧栏选中态全部失效（选中行底色条件含 `activeSection ≤ 1`） |
| `routeActive` | 整个编辑区 `visibility: hidden`（路由页面覆盖），快捷键路由被禁用 |
| `showPalette` | 快捷键路由暂停 |
| `conflictResolving` | 标题/正文输入禁用 |
| `locked` | 标题/正文禁用，格式动作抛错 |
| 侧栏折叠 | 品牌区只留 Logo；rail 保留；`sidebarWidth` 变为 56 |
| 右栏折叠 | 宽度归 0（不占位） |
| `groupTabs.length > 0` | 右侧出现"标签组 / 关闭分组"分屏面板 |

---

## 11. 已知不一致点与移植决策建议

| # | 现象 | 源码位置 | 建议 |
|---|---|---|---|
| 1 | 标签页没有未保存指示 | `LexiDesktopWorkspace.tabStrip` | macOS 建议在标题左侧加 6 pt 圆点（`brand`），脏状态取 `revision != savedRevision \|\| pendingSave != nil`；这是新增设计，需产品确认 |
| 2 | 属性/出链/反向链接模式没有独立入口，且高亮仍停在"大纲" | `LexiWorkspaceRightSidebar` | 改成 4 个明确标签，或把三块合并进"大纲"页做分区 |
| 3 | 侧栏折叠时 Logo 被裁 4 vp | `width 56` vs `14+28+18` | 见 2.1 |
| 4 | 侧栏搜索框占位符以 `notebook:` 结尾，无示例值也无省略号，视觉上像被截断 | `placeholder: '搜索 · tag: type: notebook:'` | 照抄会显得像漏字；macOS 建议改 "搜索 · 支持 tag: type: notebook:" 或补一个示例、加省略号 |
| 5 | 「今日笔记 / 模板」「全部笔记 / 收藏」都是内容自适应宽度，不成组居中 | `Row` 内无 `layoutWeight` | macOS 若做 segmented control，需明确是等分还是自适应 |
| 6 | 笔记行不显示置顶 | `documentRow` | 若产品需要，加 `pin` 图标（12）在星标前 |
| 7 | 关闭确认顺序：取消在前、危险动作在后 | 全部 `showAlertDialog` | macOS HIG 通常危险动作在右但需明确标注，且默认按钮应为"取消" |
| 8 | 空状态标题 20 号而无插画 | `选择或新建一篇笔记` | 可加 48–64 pt 的 SF Symbol 插画（原实现只有 32 号 `note` 线稿图标） |
| 9 | 命令面板行高 52 + 2 间距，信息密度偏低 | `PALETTE_ROW_HEIGHT 52` | 若命令多（174 条），macOS 可降到 44（仍保留两行结构） |
| 10 | 面板宽高硬编码 420–720 / 280–560 | `paletteSheet` | 多显示器下建议按屏幕尺寸取比例（如 40% 宽，上限 720） |
| 11 | 面包屑缺少 `layoutWeight`，长笔记本名会挤压右侧按钮 | 编辑工具条 | 给面包屑文字加 `layoutWeight(1)` + 省略 |
| 12 | 右栏 `properties` 模式只显示属性，不显示出链/反向链接（这两块被限定在 outline/outgoing/backlinks） | 条件 `selectedMode === 'outline' \|\| ...` | 保持即可，但要确认产品预期 |
| 13 | 状态栏视图标签点击只切"阅读"，不切"源码" | `workspace-view-status` | 两个状态入口语义不同，需在 UI 上区分（一个是阅读态，一个是编辑态） |
| 14 | 工具栏"源码"按钮文字是目标态 | 4.2 | 见 4.2 建议 |

---

## 附录 A：关键可访问性标识 / 测试 id

| id | 元素 |
|---|---|
| `workspace-sidebar-toggle` | 标签条左侧栏开关 |
| `workspace-settings-gear` / `workspace-settings-without-ribbon` | 设置入口（rail / 标签条） |
| `workspace-tab-{noteId}` / `workspace-close-{noteId}` | 标签 / 关闭 |
| `workspace-create-menu` | 新建按钮 |
| `workspace-right-sidebar-toggle` | 右栏开关 |
| `workspace-tab-scroll` | 标签滚动区 |
| `workspace-switcher` | 底部工作区切换器 |
| `workspace-search` / `workspace-search-clear` | 侧栏搜索 / 清除 |
| `workspace-daily-note` / `workspace-templates` | 今日笔记 / 模板 |
| `workspace-note-{id}` / `workspace-map-{id}` / `workspace-project-{id}` | 侧栏行 |
| `workspace-sidebar-resize` / `workspace-right-sidebar-resize` | 拖拽手柄 |
| `workspace-editor-toolbar` | 编辑器工具条 |
| `workspace-edit-toggle` | 源码/实时预览 |
| `workspace-tools-{noteId}` | 工具按钮 |
| `workspace-document-more` | 更多 |
| `workspace-title-input-*` / `workspace-body-input-*` | 标题 / 源码输入 |
| `workspace-document-*` | 文档滚动容器 |
| `workspace-save-status` / `workspace-view-status` / `workspace-voice-record-*` | 状态栏元素 |
| `workspace-right-toolbar` / `workspace-right-outline-tab` / `workspace-right-heading-{id}` | 右栏 |
| `command-palette-input` / `command-palette-close` / `palette-result-{id}` / `palette-create-note` | 命令面板 |
| `template-*` / `trash-window-*` / `capture-*` | 模板 / 回收站 / 语音面板 |

## 附录 B：命令面板将展示的命令（标题原文，`core/LexiCommands.ets` 共 174 条）

按源码顺序节选（约前 40 条；完整表见源文件）：

```
打开命令面板 / 保存当前文件 / 新建 Markdown 笔记 / 新建快速笔记 / 新建学习笔记 / 打开今日笔记 /
从模板新建笔记 / 将当前笔记保存为模板 / 快速切换文档 / 加粗/取消加粗 / 倾斜/取消倾斜 / 添加删除线 /
高亮 / 设为小标题 1 / 设为小标题 2 / 插入待办事项 / 插入分隔线 / 插入表格 / 插入代码块 /
插入数学块 / 插入标注 / 切换编辑与阅读 / 在右侧分屏打开当前文档 / 关闭右侧分屏 / 显示或隐藏侧边栏 /
保存并关闭当前标签 / 转到上一个标签页 / 转到下一个标签页 / 转到标签页 #1… / 转到最后一个标签页 /
新建思维导图 / 白板：导出图片 / 白板：转换为文件… / 新建白板 / 将当前笔记转为思维导图 /
打开笔记关联 / 打开文档管理 / 管理工作区与项目 / 使用浅色外观 / 使用深色外观 / 跟随系统外观
```

完整 174 条（含编辑器格式、表格行列操作、书签、数据库、分屏、缩放、模板日期等）见
`core/LexiCommands.ets:10-185`，标题均为中文源串，英文环境走 `LexiEnglish`。
