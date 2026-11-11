# Harness 插件

1.1.2：修正宿主的键盘事件分发，插件获焦时不触发笔记快捷键；Base URL 使用 URL 输入模式，
支持数字域名、IP、端口和 `/v1` 等路径。此输入修复需要同步更新宿主 HAP。

模型切换区显示「服务商 + 模型」，点击后打开统一的模型管理页面，支持获取和选择模型，
点击「配置服务」才进入 API 配置。服务商按地址识别；中转服务可以自定义名称。
对话输入区保留余额入口，使用自定义选择面板，不再使用系统下拉菜单。

支持最多 8192 字符的 Base URL/Key，设置刷新保留输入内容与光标；
聊天回复支持 Markdown，可保存常用模型并快速切换。
「余额 / 配额」支持 DeepSeek、OpenRouter 金额，以及 GLM、Kimi、MiniMax Coding Plan
官方地址的配额。自定义网关暂不支持余额查询，不会向第三方探测或发送 Key。

升级时需要同步更新知萤宿主（新增 `ai.models` / `ai.balance`），再安装本目录 ZIP。
仅替换旧版宿主中的 ZIP 仍可手动配置模型，但无法使用新增的宿主查询接口。

Harness 独立分发为 ZIP，由用户自行下载并从知萤的插件设置导入；应用不附带安装包或专属安装按钮。
原生插件的包结构、能力和限制见 [LexiNote 原生插件制作规范](../../docs/native-plugin-authoring.md)。

```sh
# 首次准备构建依赖（复用阅读器锁定的 markdown-it 14.1.0）
npm ci --prefix tools/reading-bundle

# 构建独立分发的 dist/main.js + manifest.json + ZIP，不写入应用资源
node plugins/harness/build.cjs

# 只校验产物是否过期
node plugins/harness/build.cjs --check

# 端到端回归（真实 runtime + 假宿主 + 假 DOM）
node scripts/tests/plugin-harness-regression.cjs
node scripts/tests/plugin-harness-ui-regression.cjs
node scripts/tests/plugin-ai-catalog-regression.cjs
node scripts/tests/plugin-input-regression.cjs
node scripts/tests/plugin-harness-providers-regression.cjs
```

- `src/`：可读源码（CommonJS，相对 `require` 由构建脚本内联）。
- `dist/`：构建产物；`harness-lexinote-harness.zip` 可直接从「设置 → 插件 → 从本地安装 ZIP…」安装。
- 插件只 `require('@lexinote/sdk')`；模型请求由宿主代办，插件本身不联网。
