# main 贡献指南与 PR 规范

**PR 的目标分支（base）为 `main`**。此分支接收 README、项目文档、PR 模板、Harness 独立插件及必要的许可声明。应用代码分别提交到 `HarmonyOS`、`Windows` 或 `macOS`。

## 选择系统规范

- [HarmonyOS PR 规范](https://github.com/peryixing-lab/LexiNote/blob/main/docs/pr/HarmonyOS.md)
- [Windows PR 规范](https://github.com/peryixing-lab/LexiNote/blob/main/docs/pr/Windows.md)
- [macOS PR 规范](https://github.com/peryixing-lab/LexiNote/blob/main/docs/pr/macOS.md)
- [PR 模板选择方法](https://github.com/peryixing-lab/LexiNote/blob/main/docs/PR_GUIDELINES.md)

不要将整个平台分支合并到 main。跨分支功能拆成对应平台与文档 / 插件 PR，互相链接，并说明依赖顺序。

## 文档 PR

- 标题建议使用 `docs: …` 或 `chore: …`，说明需要修正的内容及结果。
- 检查分支名称大小写、相对链接、代码路径、命令和下载链接；工程路径以对应平台分支为准。
- 区分提案、已实现能力与实际验证结果，按平台写明系统要求、兼容范围和差异。
- PR 模板变化需同时检查 main 上的可选模板和对应平台分支的专属模板，保持目标分支与检查项一致。
- 纯文档修改不要求运行应用构建或插件测试。

## Harness 插件 PR

在 `plugins/harness/` 执行：

```sh
npm ci
npm run build
npm test
```

模型配置、宿主凭据隔离或 RPC 交互变化还应运行：

```sh
LEXINOTE_HARMONY_ROOT=/absolute/path/to/HarmonyOS-checkout npm run test:host
```

宿主实现位于 HarmonyOS 分支；Windows / macOS 兼容性变化需关联对应平台的宿主 PR 或兼容性验证结果。缺少平台环境时如实标明未验证范围。

- 描述修改前后的插件行为、兼容宿主版本、权限 / 能力和清单变化。新增能力不得默认视作已获授权。
- 更新依赖时同步锁文件并说明版本、用途和许可证；功能或版本变化同步 `manifest.json`、`package.json` 和 `CHANGELOG.md`。
- 涉及会话、历史或配置数据时，验证旧数据读取、失败后保留、重启恢复和卸载 / 清除行为。
- 使用虚构数据与凭据测试；不在 PR、截图、日志或插件本地数据中加入真实 API Key。
- `dist/`、`node_modules/` 和插件 ZIP 不提交到源码。插件发行通过 GitHub Releases 统一安排。

## 通用提交要求

一个 PR 聚焦一个可独立评审的目标；说明触发场景、改动后的结果、关联 Issue、执行的检查及未执行项。UI / 插件视图变更附脱敏截图或录屏。保留第三方版权与许可证声明。

不提交应用工程、安装包、个人笔记、完整设备日志、签名材料、令牌或本机配置。维护者评审后合入；版本号和 Release 由维护者统一安排。
