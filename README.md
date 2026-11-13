# 知萤 LexiNote

知萤是一款本地优先的 Markdown 笔记与知识整理应用，提供 HarmonyOS、macOS 和 Windows 版本。三个平台共享写作、知识连接与可视化整理的产品方向，具体功能及系统集成以各平台说明为准。

## 分支选择

当前为 **HarmonyOS** 分支，应用项目位于仓库根目录。

- [HarmonyOS：鸿蒙工程](https://github.com/peryixing-lab/LexiNote/tree/HarmonyOS)
- [Windows：Windows 工程](https://github.com/peryixing-lab/LexiNote/tree/Windows)
- [macOS：macOS 原生工程](https://github.com/peryixing-lab/LexiNote/tree/macOS)
- [main：项目概览、Harness 插件和共享文档](https://github.com/peryixing-lab/LexiNote/tree/main)

克隆当前平台：

```sh
git clone --branch HarmonyOS --single-branch https://github.com/peryixing-lab/LexiNote.git
cd LexiNote
```


## 下载

[LexiNote 2.0.1 Release](https://github.com/peryixing-lab/LexiNote/releases/tag/v2.0.1) 提供 Release 模式构建的未签名 HAP，安装前需自行签名。

## 2.0.1 更新

- 新增 macOS 原生版和 Windows 桌面版源码及安装包，三个平台统一使用 2.0.1 版本号。
- HarmonyOS 新增主题选择与自定义配色，调整设置、命令面板和工作区界面，补齐内置命令的英文名称。
- 增加设置与插件配置的导入导出，完善工作区偏好与本地存储相关操作。
- 更新 **Harness 智能体 1.5.0**：多模型配置、会话与历史管理；API Key 由宿主隔离保存，插件无法读回。

完整说明与安装文件见 [2.0.1 Release](https://github.com/peryixing-lab/LexiNote/releases/tag/v2.0.1)。

## HarmonyOS 功能

- **记录与写作**：快速记录、Markdown 编辑和预览、LaTeX 公式、代码块、每日笔记与模板。
- **组织知识**：知识库、工作区和文件夹、标签与搜索，支持双向链接、反向链接和关系图谱。
- **可视化整理**：思维导图与基础白板，可引用笔记并导出相关数据。
- **数据管理**：Markdown 导入与导出、JSON 备份和恢复、回收站。
- **系统集成**：桌面服务卡片支持速记、语音入口和今日待办；支持系统分享剪藏及单篇编辑状态跨设备接续。
- **词萤与集萤联动**：接收单词卡、摘录、错题、OCR 识别稿、数据报告、物品档案和表单汇总，并归档到专属工作区；可从编辑器进入词萤伴读或调用集萤 OCR，也可通过笔记内链接回到对应应用。联动需要词萤和集萤 1.3.0 及以上版本。
- **本地辅助**：支持设备离线能力时可使用中文语音识别和本地整理；具体能力取决于设备及其离线服务。
- **智能助手（插件）**：安装 **Harness** 插件并在右侧栏绑定模型后，可与笔记对话、检索和整理；模型请求由宿主代办，插件本身不联网。

笔记和索引保存在本机，无需账号。跨设备接续传递的是单篇编辑状态，不是整个工作区的云同步。建议定期导出备份；使用外部文件夹前请了解系统的文件授权要求。

多窗口、桌面卡片和编辑器之间的保存操作会协调处理；遇到内容冲突时保留草稿，并支持另存副本。

在「工作区与项目」中，可将现有应用内工作区或项目「保存到本地」。选择保存位置后，笔记会写为 `.md` 文件，思维导图会写入 `思维导图/` 下的 `.mindmap.json` 文件，后续编辑继续保存到该目录。原有工作区、项目归属和笔记引用保持关联；导图菜单支持复制路径和在文件管理中显示。

首次启动不申请存储授权。创建第一篇笔记后，应用会请求选择本地保存目录；取消或拒绝授权时，笔记继续保存在应用内部，并明确提示保存位置。之后仍可在「工作区与项目」中选择本地文件夹，将已有笔记转存到外部目录。

公式使用内置 KaTeX 离线排版，支持行内 `$…$`、`\(...\)` 和块级 `$$…$$`、`\[…\]`，包括分式、根号、求和、积分、矩阵、分段函数和多行推导。支持范围见 [KaTeX 文档](https://katex.org/docs/supported.html)；语法错误或不支持的公式保留 LaTeX 原文，点击公式仍可编辑源码。

## 插件（实验性）

知萤 2.0.1 提供一套**实验性**插件体系：一套共享内核之上，同时提供知萤自有插件 API 与
Obsidian API 兼容层。

- 入口：**设置 → 插件**。用户自行下载插件，通过「从本地安装 ZIP…」导入；应用不附带 Harness 安装包或专属安装入口。
- 安装后默认**不授予任何能力**，需要逐项授权再启用；停用会立即释放事件、命令与运行时资源。
- 插件只能通过受控 RPC 访问当前授权的知识库；拿不到物理路径、Node.js/Electron 模块或网络能力。
  模型能力（`ai.inference`）由宿主代发 HTTP 请求；侧栏视图（`ui.views`）渲染在插件
  自己的 ArkWeb 页内。
- 已测试范围：`Plugin` / `Notice` / `Vault` / `TFile` / `Events` / `Commands` / `Metadata` 子集。
  未实现的能力返回明确的 `E_UNSUPPORTED_API`，不会假装成功。
- 安全边界尚未完成专项验证，**目前只应安装你自己编写或已审查的插件**；`isDesktopOnly` 的插件会被拒绝。

**Harness 智能体 1.5.0**：[下载最新插件 ZIP](https://github.com/peryixing-lab/LexiNote/releases/download/v2.0.1/harness-lexinote-harness.zip)，然后在「设置 → 插件」中从本地安装。插件借鉴了 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 和 [dsh-token-usage](https://github.com/LaoYueHanNi/dsh-token-usage) 项目。多服务商配置的 API Key 只写入宿主并按插件隔离保存（应用沙箱内，未额外加密），插件读不回，也不再写入插件本地数据；卸载插件会清除这些密钥。

开发原生插件请阅读 [LexiNote 原生插件制作规范](docs/native-plugin-authoring.md)，其中包含包结构、清单、
SDK API、错误码、模板与验收清单。Obsidian 兼容范围见 [兼容性说明](docs/obsidian-compatibility.md)。

## 开发环境

- DevEco Studio，以及 HarmonyOS SDK **26.0.0**（工程的 target 和 compatible SDK 版本）。
- 支持 HarmonyOS 的手机、平板或二合一设备，或相应模拟器。
- 安装项目依赖需要 DevEco Studio 自带的 OHPM；运行回归脚本需要 Node.js 和 TypeScript。

## 构建与运行

1. 克隆仓库，复制公开构建配置：

   ```sh
   git clone --branch HarmonyOS --single-branch https://github.com/peryixing-lab/LexiNote.git
   cd LexiNote
   cp build-profile.example.json5 build-profile.json5
   ```

2. 用 DevEco Studio 打开项目，安装或同步 OHPM 依赖，并确保已安装 HarmonyOS SDK 26.0.0。
3. 在 **File → Project Structure → Signing Configs** 中为本机配置签名，再选择设备或模拟器运行。未配置签名时可构建未签名包，但安装到设备需要有效签名。

`build-profile.json5`、`local.properties`、证书和密钥均被忽略。请不要将本机签名信息提交到仓库。仓库中的 `build-profile.example.json5` 不含签名信息，需要变更共享构建选项时也请同步更新模板。

安装了 DevEco CLI 的开发者也可以在项目目录运行 `devecocli build` 或 `devecocli run`。macOS 上的 `scripts/build.sh` 使用默认位置的 DevEco Studio；可通过 `DEVECO_APP_PATH` 指定其他安装路径。

## 回归检查

核心回归脚本会转译并运行非 UI 的 ArkTS 代码，使用模拟的文件系统和数据库，不替代真机或模拟器测试。例如，在 macOS 的默认 DevEco Studio 安装位置：

```sh
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node scripts/tests/core-regression.cjs
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node scripts/tests/markdown-110-regression.cjs
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node scripts/tests/math-parser-regression.cjs
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node scripts/tests/math-renderer-regression.cjs
```

多数脚本支持通过 `LEXI_TYPESCRIPT` 指定 TypeScript 模块路径；部分脚本目前仍使用上述默认安装路径。其他回归脚本见 `scripts/tests/`。


## 项目结构

```text
AppScope/                    HarmonyOS 应用元信息与图标
entry/src/main/ets/          ArkUI 页面、组件与核心逻辑
entry/src/main/resources/    应用资源
entry/src/test/              单元测试
entry/src/ohosTest/          设备测试
entry/src/main/ets/plugin/   插件宿主（model / adapters / core / runtime / ui）
packages/                    插件 JS 运行时、SDK、Obsidian 兼容层（开发机侧）
docs/                        公开的插件制作规范及插件生态文档
scripts/tests/               Node.js 回归脚本（含 plugin-*.cjs）
build-profile.example.json5  不含本地签名的构建配置模板
```

## 参与贡献

欢迎使用 [Issue 模板](https://github.com/peryixing-lab/LexiNote/issues/new/choose)反馈问题或提出建议，也欢迎提交 Pull Request。提交前请阅读 [贡献指南与 PR 规范](CONTRIBUTING.md)，说明改动范围、测试环境和验证结果；界面改动请附相关截图或录屏。请勿提交个人笔记、完整设备日志、签名材料或其他敏感信息。

感谢 [ZhangJing-gugugaga](https://github.com/ZhangJing-gugugaga) 对 LexiNote 插件兼容性作出的贡献。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)。
