# 分支布局与协作方式

- **main**：README、Harness 插件源码、项目文档、贡献指南和许可文件。此分支不包含应用工程或安装包。
- **HarmonyOS**：完整的鸿蒙工程，`AppScope/`、`entry/`、Hvigor 配置、插件 SDK、宿主运行时和相关测试位于根目录。
- **Windows**：完整的 Windows 工程，`package.json`、`src/`、`build/` 图标资源、`tests/` 和打包脚本位于根目录。
- **macOS**：完整的 macOS 工程，Xcode 工程、`Sources/`、`Resources/`、`Assets/` 和构建脚本位于根目录。

## 选择与克隆

```sh
git clone --branch HarmonyOS --single-branch https://github.com/peryixing-lab/LexiNote.git LexiNote-HarmonyOS
git clone --branch Windows --single-branch https://github.com/peryixing-lab/LexiNote.git LexiNote-Windows
git clone --branch macOS --single-branch https://github.com/peryixing-lab/LexiNote.git LexiNote-macOS
```

分支名区分大小写。每个目录都可以直接作为对应平台的项目根目录打开，构建步骤以分支 README 为准。

## 插件测试夹具

Windows 和 macOS 分支的插件测试可通过环境变量 `LEXINOTE_HARNESS_ZIP` 指向本地 Harness ZIP。也可将下载或自行构建的 ZIP 放在对应工程的 `tests/fixtures/harness-lexinote-harness.zip`。ZIP 文件被 Git 忽略，不随源码提交。

Harness 的独立构建和单元测试在 main 的 `plugins/harness/` 下运行。涉及真实宿主实现的集成回归使用 `LEXINOTE_HARMONY_ROOT` 指向单独检出的 HarmonyOS 工程。

## 提交与发布

各系统的构建、设备验收和专属模板见 [PR 规范入口](PR_GUIDELINES.md)。

应用代码的 PR 以对应平台分支为目标，插件和共享文档的 PR 以 main 为目标。请勿将整个平台分支合并到 main；需要同步通用修复时，选取相关提交或文件，并分别验证。

安装文件统一发布到 GitHub Releases。已发布的版本标签保持原有快照，`v2.0.1` 仍采用发布时的多平台目录结构，不随此次分支整理而改写。
