# 知萤 LexiNote

知萤是一款本地优先的 Markdown 笔记与知识整理应用，提供 HarmonyOS、Windows 和 macOS 版本。

## 分支选择

本仓库按平台分支维护。**开发或构建应用时，请先选择对应平台分支**；每个平台分支的项目都位于仓库根目录。

- **[HarmonyOS](https://github.com/peryixing-lab/LexiNote/tree/HarmonyOS)**：鸿蒙版，使用 ArkTS / ArkUI，适配手机、平板和二合一设备。项目根目录包含 `AppScope/`、`entry/` 和 Hvigor 配置。
- **[Windows](https://github.com/peryixing-lab/LexiNote/tree/Windows)**：Windows 版，使用 Electron / React / TypeScript，支持 x64、ARM64 和 x86。项目根目录包含 `package.json`、`src/` 和 `electron-builder.yml`。
- **[macOS](https://github.com/peryixing-lab/LexiNote/tree/macOS)**：macOS 原生版，使用 SwiftUI / AppKit，面向 Apple Silicon。项目根目录包含 `LexiNote.xcodeproj`、`Sources/` 和构建脚本。
- **main（当前分支）**：项目说明、Harness 插件源码、项目文档和许可文件。

例如，克隆鸿蒙版：

```sh
git clone --branch HarmonyOS --single-branch https://github.com/peryixing-lab/LexiNote.git
cd LexiNote
```

开发 Windows 或 macOS 版时，将命令中的 `HarmonyOS` 替换为对应分支名。分支名区分大小写，构建步骤见各分支 README。现有完整克隆也可运行 `git fetch origin` 后执行 `git switch HarmonyOS`、`git switch Windows` 或 `git switch macOS`。

## 下载

[下载 LexiNote 2.0.1](https://github.com/peryixing-lab/LexiNote/releases/tag/v2.0.1)。安装包和插件 ZIP 通过 GitHub Releases 分发，不提交到源码分支。

- **HarmonyOS**：Release 模式的未签名 HAP，安装前需自行签名。
- **Windows**：按设备选择 x64、ARM64 或 x86 安装包，也可使用对应便携 ZIP；安装包未做代码签名。
- **macOS**：Apple Silicon ARM64 DMG，要求 macOS 14+；采用 ad-hoc 签名，未做 Apple 公证。
- **校验文件**：`SHA256SUMS.txt` 用于核对下载文件的完整性。

各平台功能和系统集成存在差异，请阅读对应平台说明。

## Harness 智能体插件 1.5.0

[下载 Harness 插件 ZIP](https://github.com/peryixing-lab/LexiNote/releases/download/v2.0.1/harness-lexinote-harness.zip)，在应用的「设置 → 插件」中从本地安装，并按需逐项授权。

插件源码位于 [plugins/harness](plugins/harness)。多模型配置、会话和历史管理由插件提供；API Key 由支持此能力的宿主按插件隔离保存，插件无法读回。宿主本地沙箱中的密钥未额外加密。插件宿主仍处于实验阶段，请只安装可信或已审查的插件。

插件构建与测试见 [Harness 说明](plugins/harness/README.md)。插件 SDK、契约和宿主运行时源码位于 [HarmonyOS 分支的 packages/](https://github.com/peryixing-lab/LexiNote/tree/HarmonyOS/packages)。

Harness 借鉴了 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 和 [dsh-token-usage](https://github.com/LaoYueHanNi/dsh-token-usage) 项目。

## 项目文档

- [分支布局与协作方式](docs/BRANCHES.md)
- [各平台 PR 规范与模板](docs/PR_GUIDELINES.md)
- [HarmonyOS 平台说明](docs/HarmonyOS.md)
- [Windows 平台说明](docs/Windows.md)
- [macOS 平台说明](docs/macOS.md)
- [原生插件制作规范](docs/native-plugin-authoring.md)
- [插件 API 参考](docs/plugin-api-reference.md)、[插件安全说明](docs/plugin-security.md)、[Obsidian 兼容范围](docs/obsidian-compatibility.md)
- [贡献指南](CONTRIBUTING.md)、[架构提案与实施文档](rfcs/README.md)

文档中的工程源码路径以对应平台分支为准。已有版本标签保存发布时的源码快照；`v2.0.1` 保留发布时的多平台目录结构。

## 许可证与致谢

项目采用 [GNU GPL v3.0](LICENSE)，第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。感谢 [ZhangJing-gugugaga](https://github.com/ZhangJing-gugugaga) 对插件兼容性的贡献，以及所有项目和社区贡献者。
