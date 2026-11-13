# 界面截图

由 `npm run shots` 在真实 Electron 窗口中自动生成。
除 `empty-workspace.png` 外，截图使用 `LEXI_DEMO_DATA=1` 注入的演示工作区；正式安装不包含这些示例文件。
字体在不同 Windows 版本上会使用本机系统字体。

| 文件 | 说明 |
| --- | --- |
| `workspace.png` | 浅色工作区（演示数据）：功能区、知识库侧栏、标签栏、实时预览、状态栏 |
| `empty-workspace.png` | 全新安装：空知识库、无笔记/导图/白板 |
| `workspace-open.png` | 选择工作区时的打开方式询问（当前窗口 / 新窗口 / 下次不再提示） |
| `workspace-modes.png` | 设置 → 编辑器中的全局提示开关与每个工作区的打开方式 |
| `right-sidebar.png` | 右侧栏：大纲、出链、反向链接 |
| `command-palette.png` | 命令面板（Ctrl+P） |
| `settings-about.png` | 设置 · 关于 |
| `settings-appearance.png` | 设置 · 外观（主题色与预览） |
| `workspace-dark.png` | 深色主题 |
| `mindmap.png` | 思维导图（向右树布局） |
| `graph.png` | 关系图谱与未连接提及 |
| `library.png` | 文档管理（卡片视图） |
| `canvas.png` | 白板 |
| `templates.png` | 模板库 |
| `workspaces.png` | 工作区与项目管理 |
| `help.png` | 使用帮助与快捷键 |
| `trash.png` | 回收站 |
| `reading.png` | 阅读视图 |
| `source.png` | Markdown 源码模式 |
| `welcome-note.png` | 内置欢迎笔记（表格、链接与相对差异说明） |
| `english.png` | English interface |
| `english-settings.png` | English settings |

重新生成：

```sh
npm run shots
# 或只生成部分状态：
node scripts/screenshot.mjs workspace palette mindmap
```
