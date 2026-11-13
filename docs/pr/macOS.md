# macOS 贡献指南与 PR 规范

本规范适用于 SwiftUI / AppKit、原生编辑器、文件存储、插件宿主、Xcode 工程和 DMG 打包。**PR 的目标分支（base）为 `macOS`**。

## 开发与提交

1. 从最新 `macOS` 创建工作分支，项目位于仓库根目录。按 [macOS README](https://github.com/peryixing-lab/LexiNote/blob/macOS/README.md) 准备工具链；当前支持 Apple Silicon、macOS 14+。
2. 一个 PR 聚焦一个问题。标题建议使用 `fix(macos): …`、`feat(macos): …`、`build(macos): …` 等格式。
3. 说明触发操作、修改前后的行为，以及 SwiftUI / AppKit / 存储 / 插件 / 工程配置的受影响范围。其他平台的同类修复分别提交对应分支并互相链接。

## 构建与自检

应用代码变化时执行：

```sh
./scripts/build.sh
./scripts/selftest.sh
```

自检包含插件测试，运行前按 README 设置 `LEXINOTE_HARNESS_ZIP`，或将 Harness ZIP 放在 `tests/fixtures/`。测试数据使用 `build/selftest-vault`，不要指向真实知识库。

- **Xcode 工程、scheme 或资源**：补充 `./scripts/build-xcode.sh`，检查直接构建和 Xcode 构建均包含所需资源。
- **DMG 或应用元数据**：补充 `./scripts/package-dmg.sh`，核对应用与工程的版本号、Bundle ID、图标、目标架构、DMG 内容和签名状态；按影响检查从 DMG 安装、启动和升级。
- **纯文档 PR**：检查链接、命令与路径即可，无需编译应用。

记录 macOS、Xcode、Swift 版本及 Apple Silicon 设备型号。新的系统 API 应说明可用版本，并验证最低支持系统的回退行为；不要因开发机系统较新而无说明地提高部署目标。

## 原生交互验收

按实际改动覆盖相关操作，并在 UI PR 中附截图或录屏：

- 原生红绿灯、窗口关闭 / 最小化 / 全屏、设置与回收站弹窗、原生菜单和 Cmd 快捷键。
- NSTextView 编辑、中文输入法、撤销 / 重做、焦点切换、选区、阅读与源码模式。
- 浅深色、系统材质、macOS 26+ Liquid Glass 及较低支持版本的回退（涉及对应效果时）。
- Finder 显示、中文或空格路径、目录选择取消、不可写位置，以及保存失败后的内容保留（涉及文件操作时）。

Swift 并发或生命周期改动需说明主线程 UI 更新、异步任务取消及窗口销毁后的回调处理。涉及多窗口或全局偏好时记录跨窗口验证；异步测试首次失败和重跑结果均应保留，不以反复重跑代替说明。

## 数据、文件与发布

数据模型变化应验证已有 Markdown / Frontmatter、`library.json`、`session.json` 和导图 / 白板数据的读取或迁移，并说明失败恢复方式。

不提交 `build/`、`.build-cache/`、DerivedData、`xcuserdata/`、`.xcuserstate`、自检知识库、APP / DMG / ZIP、Developer ID 证书、公证凭据或个人 Team 配置。保留共享 scheme、必要图标与源码资源。

PR 中必须记录实际检查结果、签名类型（如涉及打包）、未覆盖的系统版本和已知限制。ad-hoc 签名、Developer ID 签名和 Apple 公证应明确区分，不将本机构建成功等同于已公证发行。

版本号、签名、公证与 Release 由维护者统一安排。

[返回各平台 PR 规范入口](https://github.com/peryixing-lab/LexiNote/blob/main/docs/PR_GUIDELINES.md)
