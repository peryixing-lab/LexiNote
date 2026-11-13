# 各平台 PR 规范与模板

按修改对象选择目标分支和规范。每个平台都有独立的构建、运行环境及验收要求。

- **HarmonyOS**：base 为 `HarmonyOS`；[规范](pr/HarmonyOS.md)；[模板](../.github/PULL_REQUEST_TEMPLATE/HarmonyOS.md)。重点是 DevEco / SDK、ArkTS / ArkUI、设备形态、系统能力、授权和插件宿主。
- **Windows**：base 为 `Windows`；[规范](pr/Windows.md)；[模板](../.github/PULL_REQUEST_TEMPLATE/Windows.md)。重点是 Electron / IPC、类型检查、x64 / ARM64 / ia32、Windows 原生验证及 NSIS 安装升级。
- **macOS**：base 为 `macOS`；[规范](pr/macOS.md)；[模板](../.github/PULL_REQUEST_TEMPLATE/macOS.md)。重点是 SwiftUI / AppKit、Xcode、自检、原生交互、系统 API 回退和 DMG / 签名状态。
- **Harness / 共享文档**：base 为 `main`；[规范](pr/main.md)；[模板](../.github/PULL_REQUEST_TEMPLATE/main.md)。重点是分支边界、文档链接、插件独立构建、权限及宿主兼容性。

## 使用对应模板

GitHub 的可选模板集中放在默认分支 main 的 `.github/PULL_REQUEST_TEMPLATE/` 中，各平台分支也保留专属的 `.github/PULL_REQUEST_TEMPLATE.md`，方便直接查阅。

在比较链接中明确 `base...head`，并通过 `template` 参数选择模板。以下示例中的 `my-fix-branch` 需要替换成实际工作分支；跨 Fork 时使用 GitHub 显示的 head 标识：

```text
https://github.com/peryixing-lab/LexiNote/compare/HarmonyOS...my-fix-branch?quick_pull=1&template=HarmonyOS.md
https://github.com/peryixing-lab/LexiNote/compare/Windows...my-fix-branch?quick_pull=1&template=Windows.md
https://github.com/peryixing-lab/LexiNote/compare/macOS...my-fix-branch?quick_pull=1&template=macOS.md
https://github.com/peryixing-lab/LexiNote/compare/main...my-fix-branch?quick_pull=1&template=main.md
```

模板参数只选择正文模板，不改变目标分支。提交前核对 base、比较差异及模板；已有草稿可从模板文件复制正文。若 GitHub 显示通用入口，按其中的链接选择系统规范和模板。

模板加载方式参见 [GitHub 模板文档](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository) 和 [比较链接参数文档](https://docs.github.com/en/pull-requests/reference/using-query-parameters-to-create-a-pull-request)。

## 共通要求

一个 PR 聚焦一个可独立评审的目标，描述具体问题和修改后的行为。应用代码分别提交对应平台；插件和共享文档提交 main，不将整个平台分支合并到 main。跨分支变更分别建 PR 并说明依赖顺序。

按实际影响选择检查，记录执行的命令、系统、架构及结果。纯文档改动无需运行应用构建。未执行的检查标明原因，模拟环境和目标系统原生验收应分开记录；偶发失败保留首次输出与重跑说明。

不提交安装包、构建缓存、个人笔记、完整设备日志、真实凭据或签名材料。版本、签名与 Release 由维护者统一安排。
