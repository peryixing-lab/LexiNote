<!-- base 必须为 macOS。规范：https://github.com/peryixing-lab/LexiNote/blob/macOS/CONTRIBUTING.md -->

## 问题与修改后的行为

<!-- 写明触发操作、修改前后的结果及关联 Issue。 -->

## 改动范围

- 目标分支：`macOS`
- SwiftUI / AppKit / 编辑器 / 存储 / 插件 / Xcode / DMG：
- 关联的其他平台或文档 PR（如有）：

## macOS 环境与验证

- macOS / Xcode / Swift 版本及 Apple Silicon 设备型号：
- `./scripts/build.sh`、`./scripts/selftest.sh` 结果：
- Harness ZIP 夹具来源 / 版本（运行插件自检时）：
- Xcode 构建、资源和 scheme 验证（涉及工程配置时）：
- DMG 内容、安装 / 启动 / 升级、架构与签名 / 公证状态（涉及打包时）：
- 原生窗口、菜单 / Cmd 快捷键、输入法、撤销 / 焦点与截图（按改动填写）：
- 材质可用版本、较低支持系统回退或文件授权 / 保存失败场景（按改动填写）：
- 首次失败及重跑结果、未执行项和已知限制：

## 兼容性与数据

<!-- 说明系统 API 可用性、部署目标、旧数据迁移、主线程 UI 更新、任务取消或窗口销毁后的回调；无关项可写“不涉及”。 -->

## 提交前检查

- [ ] base 为 `macOS`，已阅读本分支贡献指南。
- [ ] 已按改动执行构建与原生自检；纯文档 PR 已标注不适用项。
- [ ] 已说明未覆盖的 macOS 版本、异步失败 / 重跑和签名状态，未将 ad-hoc 签名写成 Apple 公证。
- [ ] 未包含 APP / DMG / ZIP、DerivedData、`xcuserdata/`、构建缓存、真实知识库或签名 / 公证凭据。
- [ ] 相关共享工程资源、部署兼容性、数据格式及文档已同步，或已说明不适用。
