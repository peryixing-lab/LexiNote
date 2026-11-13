# Windows 贡献指南与 PR 规范

本规范适用于 Electron 主进程、preload、React / TypeScript 界面、本地存储和 Windows 安装包。**PR 的目标分支（base）为 `Windows`**。

## 开发与提交

1. 从最新 `Windows` 创建工作分支，项目位于仓库根目录。按 [Windows README](https://github.com/peryixing-lab/LexiNote/blob/Windows/README.md) 准备 Node.js 和 npm，并使用锁文件安装依赖。
2. 一个 PR 聚焦一个问题。标题建议使用 `fix(windows): …`、`feat(windows): …`、`build(windows): …` 等格式。
3. 描述触发操作、修改前后的行为及受影响的主进程 / preload / 界面 / 打包范围。跨平台改动分别提交对应分支并互相链接。

## 基础检查

应用代码变化时至少执行：

```sh
npm ci
npm run typecheck
npm run build
```

界面与交互变化还应运行 `npm run smoke`。按改动范围补充：

- **保存、关闭窗口或多窗口同步**：运行 `node scripts/flush.mjs`，并检查编辑后立即关窗、工作区切换与多窗口数据同步。
- **首次启动或默认数据**：运行 `npm run empty`，确认不附带演示笔记、导图、白板或用户数据。
- **插件、IPC 或 preload**：准备 Harness 测试 ZIP 后运行 `npm run test:plugins`；夹具路径按 README 设置。
- **打包、Electron 运行时或原生依赖**：执行受影响的 `npm run package:win:x64`、`npm run package:win:arm64` 或 `npm run package:win:ia32`，说明三个支持架构中已验证和未覆盖的部分。
- **纯文档 PR**：检查链接和命令即可，无需启动 Electron 或生成安装包。

## Windows 验收

记录 Node.js / npm / Electron 版本、构建宿主系统，以及目标 Windows 版本和架构（x64 / ARM64 / ia32）。明确区分 macOS 上的 Electron 测试、交叉构建与 Windows 原生运行，不把交叉构建成功写成 Windows 安装验收通过。

- **窗口与输入**：按影响验证最小化、最大化、关闭、多窗口、Ctrl 快捷键、中文输入法及高 DPI / 缩放显示。
- **文件与保存**：涉及文件操作时覆盖中文或空格路径、目录取消选择、不可写目录，以及失败后的内容保留。
- **NSIS 安装包**：涉及安装配置时验证全新安装、升级、安装目录选择、卸载和用户数据保留；记录测试架构。无法执行的项目说明原因。

## 进程与数据边界

主进程 / preload 改动需说明 IPC 参数校验和暴露接口。保持 `contextIsolation`、`sandbox`、`nodeIntegration`、CSP 与外部链接处理的既有边界；若确需改变，在 PR 中单独说明原因及验证。

依赖变化同步 `package.json` 与 `package-lock.json`；说明 Electron / 原生模块兼容性、安装包体积或架构影响。数据格式变化说明旧数据读取、升级及失败恢复。

## PR 与文件要求

PR 必须包含目标分支、复现步骤、实际检查命令、Windows / 构建宿主环境、架构、截图或录屏（UI 改动）、未执行项目及已知限制。偶发失败需保留首次结果和重跑说明。

不提交 `node_modules/`、`dist/`、`release/`、下载缓存、测试用户数据、EXE / ZIP / MSI、签名证书或凭据。**`build/icon.ico` 和 `build/icon.png` 是受版本控制的安装图标资源**，不按构建缓存删除。

保留第三方许可证声明；安装包、代码签名、版本号和 Release 由维护者统一安排。

[返回各平台 PR 规范入口](https://github.com/peryixing-lab/LexiNote/blob/main/docs/PR_GUIDELINES.md)
