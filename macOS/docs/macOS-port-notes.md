# 从 HarmonyOS 到 macOS：移植说明

本文记录这次移植的依据、取舍与验证方式，方便继续迭代。原工程完整源码位于
仓库根目录的 `entry/` 等目录；三份自动提取的规格位于 `docs/specs/`：

- [工作区界面规格](specs/workspace-ui.md)
- [主题与设置规格](specs/theme-settings.md)
- [核心功能规格](specs/core-features.md)

## 1. 技术选择

| 层 | HarmonyOS | macOS |
| --- | --- | --- |
| UI | ArkUI 声明式组件 | SwiftUI |
| 文本编辑 | ArkUI `TextArea` / 自定义块编辑器 | `NSTextView` + `NSLayoutManager` 临时属性 |
| 窗口 | Stage 模型 + 自绘标题栏 | SwiftUI `WindowGroup` + `hiddenTitleBar` + AppKit 原生红绿灯 |
| 持久化 | 文件 + RDB 索引 | 标准 Markdown + Frontmatter + JSON（导图 / 白板） |
| 公式 | KaTeX + Web 渲染 | 原生 LaTeX→Unicode 近似 |
| 材质 | HDS 沉浸光感 / 自绘模糊 | 纯色分层 + Liquid Glass（macOS 26+）+ NSVisualEffect 回退 |
| 插件 | 原生插件宿主 + ArkWeb | 实验性 WKWebView 插件宿主 |

选择原生 SwiftUI 而不是 Electron/Web 壳的原因：窗口与菜单、文本编辑、键盘与触控板手感、
Liquid Glass 都是 macOS 的原生能力；同时避免引入浏览器运行时。

## 2. 界面还原

### 2.1 几何

| 区域 | 值 |
| --- | --- |
| 标题栏 | 52 pt |
| 图标栏（rail） | 56 pt |
| 知识库侧栏 | 默认 248 pt，可拖拽 200–420 pt |
| 右侧检查器 | 默认 280 pt，可拖拽 232–420 pt，默认关闭 |
| 文档列 | 内容 688 pt + 左右各 56 pt = 800 pt；可关闭限宽 |
| 编辑器工具条 | 48 pt |
| 底部状态栏 | 40 pt |
| 命令面板 | 720 × 560 pt，圆角 16 pt |
| 标签页 | 高 38 pt，最大宽 196 pt，顶部 8 pt 圆角，激活标签 2 pt 主题色顶边 |

窗口默认 1440 × 900，最小 1120 × 720，只构建 arm64。

### 2.2 颜色

`Core/Theme.swift` 保留了原 `LexiTheme.ets` 的算法与关键色值：

- 原始浅色：页面 `#FFFFFF`、侧栏 `#F4F0FA`、rail `#EAE4F5`、选中 `#E4D8FA`、发丝线 `#DDD5EA`、主文字 `#231B36`、品牌 `#6E44D9`。
- 原始深色：页面 `#191822`、侧栏 `#242030`、rail `#1D1A29`、选中 `#403355`、发丝线 `#3B354C`、主文字 `#F5F3FB`。
- 预设：鸢尾紫、玫瑰粉、暖杏橙、森林绿、晴空蓝、石墨灰。
- 强调色模式按原 `mix → readable / fitText` 的顺序保证正文与链接在选中行上的 4.5:1 对比度。
- 自定义模式会重算页面、表面、选中、发丝线与文字色，而不是只替换强调色。

### 2.3 字体与图标

- UI 使用系统字体（中文落到苹方），编辑器支持系统 / 衬线 / 等宽。
- 侧栏、tab、工具栏使用 SF Symbols；原工程的自绘 SVG 图标不直接复用。
- 应用图标使用原工程 `docs/design/lexinote-icon-1024.png`。

### 2.4 窗口按钮

macOS 原生红绿灯固定在左上角（系统标准位置），「知萤 LexiNote」品牌紧邻其后，
并通过让根视图延伸进原生标题栏，把品牌行与红绿灯放在同一水平线。不使用 HarmonyOS
的右上角窗口按钮，也不自绘红绿灯。全屏、最小化、关闭均走系统行为。

### 2.5 设置与回收站弹窗

设置与回收站不再生成文档标签，而是分别通过 `sheet` 以原生模态弹窗呈现：

- 设置：880 × 660，固定顶部「设置 / 关闭」栏，左侧分组导航，右侧滚动内容；⌘, 与图标栏齿轮均打开同一张 sheet。
- 回收站：760 × 560，顶部标题、删除数量、清空与关闭；正文展示笔记标题、内容摘要、恢复与永久删除。
- 关闭后回到原文档；不会在标签栏留下「设置」或「回收站」标签。

### 2.6 Liquid Glass

`UI/Common.swift` 中 `LiquidGlassLayer`：

```swift
if #available(macOS 26.0, *) {
    Rectangle().fill(.clear).glassEffect(.regular.tint(...), in: .rect(cornerRadius: ...))
} else {
    RoundedRectangle(cornerRadius: ...).fill(.ultraThinMaterial)
}
```

- 用于标题栏、命令面板与 Toast。
- 「设置 → 外观 → 材质与动效 → 使用 Liquid Glass 材质」可关闭，关闭后为纯色。
- 桌面工作区本身保持纯色分层，避免半透明影响长时间阅读。

## 3. 功能映射

| 原功能 | macOS 实现 |
| --- | --- |
| 三栏工作区 + rail | `RootView` / `TitleBarView` / `RailView` / `SidebarView` |
| 标签页 | `openTabs` / `selectedTabID`，支持关闭其他/右侧、⌘1–9、⌃⇧[ / ] |
| 实时预览 | 整页 `MarkdownPreview`；段落悬停「编辑」跳到源码对应行 |
| 整篇源码 | `NSTextView`（撤销、查找、拼写检查、列表续写、Tab 缩进） |
| 阅读视图 | 同预览布局，状态栏可切换 |
| 大纲 / 出链 / 反向链接 / 属性 | 右侧检查器三个标签；属性与标签可增删 |
| 搜索语法 | `tag:` `type:` `notebook:` `path:` `[属性]值` `-否定` |
| 命令面板 | 56 条命令，⌘K；↑↓ / Enter / Esc；支持触控板与键盘 |
| 关系图谱 | 力导向布局、拖动节点、平移缩放、筛选、双击打开、去重后的双向边 |
| 思维导图 | 向右 / 左右平衡布局、增删主题、双击编辑、关联笔记、保存 JSON |
| 白板 | 可拖动卡片、卡片关联笔记、连线、编辑、整理位置 |
| 回收站 | 软删除（Frontmatter）、恢复、永久删除、清空 |
| 模板 / 每日笔记 | 6 个内置模板，`{{date}}` `{{time}}` `{{weekday}}` `{{title}}` |
| 外观 | 6 预设 + 原始 + 自定义 + 深色；设置弹窗实时预览 |
| 导入导出 | Markdown 导入、当前笔记导出、完整 JSON 备份 |
| 自动保存 | 0.9 s 定时落盘；关标签 / 退出前强制保存 |

## 4. 数据格式

```markdown
---
id: "note-algo-complexity"
title: "时间复杂度"
notebook: "计算机课程"
type: study
level: study
pinned: true
favorite: true
tags: ["学习/算法", "考试重点"]
created: 2026-11-11T08:28:00Z
updated: 2026-11-12T14:28:00Z
properties:
  - key: "课程"
    value: "数据结构与算法"
---

# 正文…
```

- `id` 是稳定主键，重命名标题时不会断链。
- 全新安装只创建 1 个空工作区「我的工作区」，不预置笔记、导图或白板。
- 文档截图使用内存中的演示数据（`seedDemo`），不会写入用户知识库。
- 思维导图 / 白板分别保存为 `.mindmap.json` / `.canvas.json`，与 Markdown 同目录树。
- 会话保存在 `session.json`；启动时恢复标签与选中项。

## 5. 已知差异与后续方向

1. **块级内联编辑**：原版点击渲染块即可改源码；macOS 版用悬停「编辑」跳到源码行，保证预览的排版稳定。若继续迭代，可给 `MDBlock` 增加行范围并做块内 `TextEditor`。
2. **KaTeX**：为保证零依赖与原生排版，公式使用 Unicode 近似；复杂矩阵、多行环境会降级为可读文本，源码仍保留。下一步可把 KaTeX 资源与 `WKWebView` 作为可选公式渲染器。
3. **语音**：未接入离线识别；速记面板 + 系统听写是可用的替代。
4. **生态 / 表单 / 多窗口 / PDF**：未移植。
5. **中英文切换**：当前固定简体中文。
6. **冲突处理**：单窗口模型下只有自动保存；没有原版的多窗口冲突对话框。

## 6. 验证

- `scripts/selftest.sh`：覆盖空工作区首次启动、Markdown + Frontmatter 落盘、重新载入、标题/标签/路径、搜索、反链、图谱、回收站恢复、导图持久化。当前输出 `SELFTEST PASS`。
- `scripts/snapshot.sh`：用真实 `NSHostingView` 渲染 15 个工作区状态，并截取真实主窗口与设置弹窗（共 17 张）。
- `xcodebuild -project LexiNote.xcodeproj -scheme LexiNote ... build` 已通过。
- 原生窗口截图见 `docs/screenshots/00-native-window.png`，设置弹窗见 `docs/screenshots/16-settings-sheet.png`。

## 7. 继续开发建议

- 在 `Sources/LexiNoteMac/` 内按 App / Core / UI 分层添加文件，Xcode 工程会自动同步。
- 修改主题算法时同步更新 `ThemeEngine` 与设置页的预览。
- 任何涉及本地文件的改动，先跑 `scripts/selftest.sh`，再跑 `scripts/snapshot.sh` 检查界面回归。
- 如果要恢复块级编辑，建议先给 `MDBlock` 增加 `raw` 与 `lineRange`，再在 `MarkdownPreview` 内替换单块渲染。
