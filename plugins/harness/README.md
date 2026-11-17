# Harness 智能体插件 (lexinote-Harness)

当前版本：**1.6.0**。知萤（LexiNote）智能体的独立插件工程：对话、上下文范围（当前笔记 / 选中内容 / 指定笔记集合）、真实笔记引用跳转、非破坏性 Diff 修改建议确认与一键撤销、技能与多会话持久化。

模型请求由宿主代办，API Key 只写入宿主的按插件隔离密钥槽，插件本身不直接联网。

## 目录结构

- `manifest.json`：插件清单（`id: lexinote.harness`）
- `src/`：插件核心源码（`main.js`、`agent.js`、`tools.js`、`context.js`、`citations.js`、`diff.js`、`changes.js`、`view.js`、`ui-context-diff.js`、`session.js`、`profile-store.js` 等）
- `dist/`：构建产物（`main.js`、`manifest.json`、`harness-lexinote-harness.zip`）
- `tests/`：独立单元测试与宿主集成测试
- `build.cjs`：零外部打包器的独立构建与 ZIP 打包脚本

## 构建

需要 Node.js 和 npm。在本目录执行：

```sh
npm ci
npm run build
```

校验构建产物是否最新：

```sh
npm run build:check
```

产物为 `dist/harness-lexinote-harness.zip`，可在知萤应用的「设置 → 插件 → 从本地安装 ZIP…」中导入安装。

## 测试

运行插件独立单元测试（会话历史、上下文范围、引用解析、Diff 计算与 7 类变更确认/撤销状态机）：

```sh
npm test
```

运行与宿主密钥隔离的集成测试，通过 `LEXINOTE_HARMONY_ROOT` 指向单独检出的 HarmonyOS 分支工程：

```sh
LEXINOTE_HARMONY_ROOT=/path/to/LexiNote-HarmonyOS npm run test:host
```

版本变更见 [CHANGELOG.md](CHANGELOG.md)，第三方声明见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。
