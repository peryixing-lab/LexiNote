<!-- base 必须为 Windows。规范：https://github.com/peryixing-lab/LexiNote/blob/Windows/CONTRIBUTING.md -->

## 问题与修改后的行为

<!-- 写明触发操作、修改前后的结果及关联 Issue。 -->

## 改动范围

- 目标分支：`Windows`
- 主进程 / preload / React 界面 / 存储 / 打包：
- 关联的其他平台或文档 PR（如有）：

## Windows 环境与验证

- Node.js / npm / Electron 版本：
- 构建宿主系统与架构：
- 实际运行的 Windows 版本与架构（x64 / ARM64 / ia32；未运行请注明）：
- `npm run typecheck`、`npm run build` 结果：
- 按改动运行的 smoke / flush / empty / test:plugins 及结果：
- 打包架构与安装、升级、卸载、用户数据保留结果（涉及打包时）：
- Ctrl 快捷键、输入法、窗口 / DPI 或路径场景与截图（按改动填写）：
- 未执行项、原因及已知限制：

## 兼容性与数据

<!-- 主进程 / preload 变化说明 IPC 与隔离边界；依赖变化说明锁文件、Electron / 原生模块和架构影响；数据变化说明旧数据及恢复。 -->

## 提交前检查

- [ ] base 为 `Windows`，已阅读本分支贡献指南。
- [ ] 已区分交叉构建、macOS 上的 Electron 测试与 Windows 原生运行，未把未覆盖的架构标为通过。
- [ ] 已按改动范围记录检查、截图和未执行项；纯文档 PR 已标注不适用项。
- [ ] 未包含安装包、便携 ZIP、`node_modules/`、`dist/`、`release/`、缓存、测试用户数据或签名凭据。
- [ ] 依赖锁文件、文档、IPC / 数据兼容性和第三方声明已同步，或已说明不适用；安装图标资源已保留。
