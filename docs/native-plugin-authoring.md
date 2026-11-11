# 06 · 原生插件制作规范（LexiNote Plugin API v1）

> 本文是**写一个知萤原生插件**的唯一规范。每一条都对应仓库里的真实实现，不是设想：
> 校验在 `PluginManifestService.ets` / `PluginZip.ets`，API 在 `packages/plugin-runtime-js/src/sdk.js`，
> 调度与能力校验在 `PluginRpcDispatcher.ets`。
> **API 1.1** 新增 `ai.inference`（宿主代办模型请求）与 `ui.views`（侧栏插件视图）；
> 模型密钥、HTTP 请求与超时始终留在宿主，插件拿不到网络。
> 面向 Obsidian 插件的适配规范见 `03-obsidian-compat-matrix.md`，两者**不共用**清单格式。

**一句话**：一个 ZIP，根上放 `manifest.json` + 一个 CommonJS 的 `main.js`，导出
`definePlugin({ activate, deactivate })`；所有能力都要在清单里声明、并被用户逐项授权。

---

## 1. 交付物形态

```text
hello.lexiplugin.zip
├── manifest.json         必需，根目录（或唯一顶层文件夹内）
├── main.js               必需，manifest.main 指向的 CommonJS bundle
├── styles.css            可选，仅对插件自己的 Web 界面有意义（当前版本不会加载）
└── assets/               可选，随包安装，当前版本不提供给插件读取
```

打包要求：

| 项 | 规则 |
|---|---|
| 格式 | 标准 ZIP（stored 或 deflate），不支持 ZIP64/分卷/加密 |
| 体积 | 解压后总量 ≤ **16 MiB**（`PluginLimits.MAX_ZIP_BYTES`） |
| 条目数 | ≤ **512** |
| 路径 | 只允许相对 POSIX 路径；禁止绝对路径、`\`、盘符、`..`、空段、控制字符 |
| 符号链接 | 一律拒绝 |
| 重复路径 | 大小写不敏感去重，重复即拒绝 |
| 归档元数据 | `__MACOSX/`、`.DS_Store`、`Thumbs.db`、`desktop.ini`、`._*` 会被忽略并清理 |
| 结构 | 要么全部在根，要么整体在一个顶层文件夹内。根上出现与文件夹同名的散落文件 → **按结构异常拒绝**（不猜测） |
| 入口大小 | `main.js` ≤ **2 MiB** |

> macOS 用「压缩」右键菜单生成 ZIP 完全可用；用「访达 → 压缩」把整个文件夹压进去也行，
> 只要 manifest 与 main 的相对位置满足 `main` 字段。
>
> **打包的是构建产物，不是源码工程。** 直接把仓库根目录压缩（含 `src/`、`package.json`、
> `tsconfig.json`）会被安装器拒绝并列出它看到的文件，提示「入口文件 main.js 不存在」。
>
> 校验不通过的安装**不会留下任何插件目录**（已实测）：解压只发生在 staging 目录，校验通过后
> 才整体移动到 `plugins/<id>/`。

---

## 2. `manifest.json`

```json
{
  "format": "lexinote-plugin",
  "formatVersion": 1,
  "id": "example.hello",
  "name": "每日笔记",
  "version": "1.0.0",
  "apiVersion": "1.0",
  "main": "main.js",
  "description": "创建今日笔记并统计创建次数",
  "author": "Your Name",
  "capabilities": ["vault.read", "vault.write", "ui.commands", "ui.notice", "plugin.storage"],
  "targets": ["harmonyos"],
  "minHostVersion": "1.2.0"
}
```

| 字段 | 必填 | 规则 | 违反后果 |
|---|---|---|---|
| `format` | ✅ | 恒为 `"lexinote-plugin"` | 安装被拒（会被当成 Obsidian 清单） |
| `formatVersion` | ✅ | 恒为 `1` | 安装被拒 |
| `id` | ✅ | `^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$`，全局唯一，发布后不可变 | 安装被拒 |
| `name` | ✅ | 1–128 字符，设置页与命令面板显示 | 安装被拒（空） |
| `version` | ✅ | `^\d+\.\d+\.\d+`（允许 `-` 预发布与 `+` 构建号） | 安装被拒 |
| `apiVersion` | ✅ | 以 `1.` 开头，如 `"1.0"` | 安装被拒 |
| `main` | ✅ | 插件目录内相对 `.js` 路径，禁止 `..`、`\`、`:`、绝对路径 | 安装被拒 |
| `capabilities` | 建议必填 | `§6` 的枚举；未知值 → 拒绝；含 `network` → 拒绝 | 安装被拒 |
| `targets` | 可选 | 存在时必须包含 `"harmonyos"` | 安装被拒 |
| `description` / `author` | 可选 | 展示用 | — |
| `minHostVersion` | 可选 | 展示用，当前不做硬性比较 | — |
| `isDesktopOnly` | **不要设** | 仅对 Obsidian 清单生效；原生插件设了也不会被读取 | — |

`manifest.json` 必须是**无 BOM 的 UTF-8 JSON**，未知字段不会被拒绝但也不会生效。

校验实现：`entry/src/main/ets/plugin/runtime/PluginManifestService.ets`；
Schema：`packages/plugin-contracts/manifest.schema.json`（可在编辑器里挂载以获得字段补全）。

---

## 3. 代码入口

必须是一个 **CommonJS** bundle（不要提交多文件工程，运行时只能 `require` 白名单模块）：

```js
const { definePlugin } = require('@lexinote/sdk');

module.exports = definePlugin({
  async activate(ctx) { /* ... */ },
  async deactivate() { /* 可选 */ }
});
```

| 规则 | 说明 |
|---|---|
| 导出形式 | `module.exports = definePlugin(...)`；也接受 `exports.default = definePlugin(...)`，以及裸 `{ activate, deactivate }`（容错路径） |
| 允许的 `require` | `'@lexinote/sdk'`、`'obsidian'`（仅 Obsidian 兼容插件）。**其他一律 `E_UNSUPPORTED_MODULE`**，包括 `fs`/`path`/`electron`/`process`/相对路径 |
| 打包工具 | 任意 CJS 输出即可（esbuild `--bundle --format=cjs --platform=neutral` 最省事）。**不要**输出 ESM，不要 `import` |
| 全局对象 | 运行在 ArkWeb 中，`window`/`setTimeout` 存在，但 **DOM 不是契约的一部分**：没有稳定的页面容器，插件不能渲染 UI |
| 激活失败 | `activate` 抛错 → 插件进入 `FAILED`，错误文本进入设置页诊断；可重试 |

> 运行时**不会**为插件清理由插件自己创建的 `setInterval`/`setTimeout`。
> 需要长期定时器的插件必须在 `deactivate()` 里自行 `clearInterval`，否则切到别的插件后仍会触发。

---

## 4. 上下文 API（`activate(ctx)` 的 `ctx`）

全部 I/O 返回 `Promise`；同步的只有 `ctx.editor.getValue()`。所有方法在插件被停用后调用都会
`reject` `E_CANCELLED`。

### 4.1 元信息

| 成员 | 类型 | 说明 |
|---|---|---|
| `ctx.pluginId` | `string` | 清单里的 `id` |
| `ctx.apiVersion` | `string` | `'1.1'` |
| `ctx.runtimeVersion` | `string` | 宿主运行时版本 |
| `ctx.vaultId` | `string` | 当前激活知识库 |
| `ctx.capabilities.has(cap)` | `(string) => boolean` | 本地快速判断；**真正拦截在宿主侧** |
| `ctx.capabilities.list()` | `() => string[]` | 已授权能力 |
| `ctx.log(level, message)` | `('info'\|'warn'\|'error', string) => void` | 进入设置页「能力与诊断」与 hilog |

### 4.2 `ctx.subscriptions`

| 成员 | 说明 |
|---|---|
| `add(disposable)` | 登记一个 `{ dispose() }` 或函数；`deactivate` 时**逆序**自动释放 |
| `size` / `list()` | 观测用 |
| `disposeAll()` | 提前释放全部（通常不需要手动调用） |

`ctx.commands.register`、`ctx.events.on` 的返回值都是 disposable，**应当** `add` 进去；
即使忘了，宿主停用时也会清理命令与事件订阅，但不会清理你自己创建的资源。

### 4.3 `ctx.vault` — 知识库文件

| 方法 | 返回 | 能力 |
|---|---|---|
| `listMarkdown()` | `Promise<FileRef[]>` | `vault.read` |
| `get(path)` | `Promise<FileRef \| null>` | `vault.read` |
| `read(ref \| path)` | `Promise<string>`（完整 Markdown，含 YAML） | `vault.read` |
| `create(path, content)` | `Promise<FileRef>` | `vault.write` |
| `write(ref \| path, content)` | `Promise<FileRef>` | `vault.write` |
| `rename(ref \| path, newPath)` | `Promise<FileRef>` | `vault.write` |
| `delete(ref \| path)` | `Promise<null>` | `vault.write` |

```ts
interface FileRef {
  id: string;        // 稳定 noteId，跨重命名不变
  vaultId: string;
  projectId: string;
  path: string;      // 知识库相对路径，例如 "课程/第一课.md"
  name: string;      // "第一课.md"
  extension: 'md';
  kind: 'file';
  size: number;      // UTF-8 字节
  ctime: number;     // ms
  mtime: number;     // ms
}
```

路径规则（`LexiPathRegistry.normalize`，违反即 `E_INVALID_PATH`）：

- 只允许 `知识库相对` 路径，分隔符必须是 `/`；**拿不到任何绝对路径**。
- 必须以 `.md` 结尾；≤ 512 字符；≤ 8 层目录。
- 禁止 `..`、`.`、空段（`a//b`）、`\`、`:`、`file://`、控制字符、首尾空格、段尾 `.`/空格。
- 目录段对应**项目（LexiProject）名**；`create('课程/一.md')` 要求存在名为「课程」的项目，
  否则 `E_NOT_FOUND`。不存在则先建项目或写到根目录。

写入语义：

| 情况 | 结果 |
|---|---|
| 正常写入 | `Promise` resolve 新的 `FileRef` |
| 文件被其他地方改过（`mtime` 变化） | `E_CONFLICT`，需要重新 `get` 再写 |
| 用户正在编辑器里改这篇（未保存草稿） | `E_EDITOR_CONFLICT` |
| 目标已存在（`create`） | `E_PATH_EXISTS` |
| `rename` 跨目录 | `E_UNSUPPORTED_API`（v1 只支持同目录改名） |
| `delete` | **软删除**（进回收站，可恢复），不是永久删除 |

> `write` 内部自动携带"上次读到的版本"做乐观并发核对。你不需要（也不能）自己传版本号。

### 4.4 `ctx.metadata`

```ts
await ctx.metadata.get(ref | path)
```

返回 `MetadataSnapshot`：`headings[]`、`links[]`、`embeds[]`、`tags[]`、`frontmatter`（原始 YAML 文本）、
`properties`（仅标量与扁平列表）、`hash`、`version`、`mtime`。

- **只看 `supportedFields` 里的字段**；其余在 `unsupportedFields` 中明确列出，不要猜。
- 嵌套 YAML、`sections`、`blocks`、`listItems`、`footnotes` 当前**不提供**。

### 4.5 `ctx.workspace`

| 方法 | 返回 | 能力 |
|---|---|---|
| `activeFile()` | `Promise<FileRef \| null>` | `workspace.views` |
| `openFile(ref \| path)` | `Promise<null>`，把该笔记打开到主窗口 | `workspace.views` |
| `snapshot()` | `Promise<{ windowId, vaultId, activeFileId, activeEditorId, openFileIds, revision }>` | `workspace.views` |

### 4.6 `ctx.editor`

| 方法 | 返回 | 能力 |
|---|---|---|
| `active()` | `Promise<EditorSnapshot \| null>` | `editor.read` |
| `getValue()` | `string`（**同步**，读镜像缓存） | `editor.read` |
| `replaceSelection(text)` | `Promise<{ content, version }>` | `editor.write` |
| `replaceAll(text, expectedVersion?)` | `Promise<{ content, version }>` | `editor.write` |

- `EditorSnapshot` 含 `content`/`baseContent`/`revision`/`dirty`/`readOnly`/`focused`/`cursor:{line,ch}`/`selection:{from,to}`。
- 位置是 **UTF-16 code unit 偏移**（与 JS 字符串一致；emoji 占 2）。
- 当前没有活动编辑器 → `E_EDITOR_READONLY`。
- 编辑后宿主会**立即持久化**（走页面自己的自动保存路径），所以连续调用要自己串行化。

### 4.7 `ctx.commands`

```js
const disposable = ctx.commands.register({
  id: 'create-daily-note',       // 见下方规则
  title: '创建今日笔记',           // 面板显示文本，非空
  run: async () => { /* 执行体 */ }
});
ctx.subscriptions.add(disposable);
```

| 规则 | 说明 |
|---|---|
| `id` | `^[a-z0-9][a-z0-9._-]{0,63}$`，小写开头，仅 `a-z0-9._-` |
| 唯一性 | 同一插件内唯一；宿主侧限定为 `<pluginId>:<id>`，因此**不同插件可同名** |
| 保留字 | 不能与内置命令冲突（`save`/`new`/`daily`/`palette`/`settings` 等 175 条）→ `E_INVALID_ARGUMENT` |
| 配额 | 单插件 ≤ 64 条 |
| 执行 | 用户在命令面板选中后由宿主回调 `run()`；`run` 可返回 Promise |
| 卸载 | 插件停用后命令立即从面板消失 |

`register` 的返回值额外带 `.ready: Promise<boolean>`：宿主拒绝注册时它 resolve `false`，
并在诊断里留一行 `命令 xxx 注册失败：...`。需要严格感知失败时可 `await disposable.ready`。

### 4.8 `ctx.events`

```js
const off = ctx.events.on('vault.created', async (payload) => {
  ctx.log('info', `新建：${payload.path}`);
});
ctx.subscriptions.add(off);
```

允许的事件类型（传其他值 → `E_INVALID_ARGUMENT`）：

| 事件 | 触发时机 | `payload` |
|---|---|---|
| `vault.created` | 插件自己或其它途径新建成功之后 | `{ fileId, path, vaultId, revision, at }` |
| `vault.modified` | 条件写成功之后 | 同上 |
| `vault.renamed` | 重命名成功之后 | 同上 + `oldPath` |
| `vault.deleted` | 软删除之后 | 同上（`path` 是删除前路径） |
| `workspace.active-file-changed` | 切换活动文件 | `{ fileId, vaultId, revision, at }` |

- `payload` **不是** `FileRef`；需要引用时用 `await ctx.vault.get(payload.path)`。
- `seq` 按知识库单调递增；事件按序投递，失败不重放。
- 单插件订阅 ≤ 128；`disposable.dispose()` 之后不再回调。
- 事件**只在提交成功后**发出：写入失败不会有事件。

### 4.9 `ctx.ui`

| 方法 | 说明 |
|---|---|
| `notice(message, timeoutMs?)` | 原生 toast；宿主截断到 400 字符 |
| `confirm({ title, body })` | **当前版本恒 `reject E_UNSUPPORTED_API`**（宿主未提供确认对话框）。需要用户确认请改用命令 + 通知的分步交互，或直接执行可撤销操作 |

插件**不能**创建 ArkUI 页面、不能注入宿主样式。需要在侧栏显示自己的界面时，用
`ctx.views` 在插件的 ArkWeb 视图里渲染 DOM（见 §4.12）；这不会获得任何额外宿主能力。

### 4.10 `ctx.storage`

| 方法 | 说明 |
|---|---|
| `get(key)` | 返回**已 JSON 解析**的值；不存在返回 `null` |
| `set(key, value)` | 值会被 `JSON.stringify` 后存储；支持对象/数组/数字/字符串/布尔 |
| `remove(key)` | 删除键 |

- 键名：宿主校验 `^[A-Za-z0-9_.-]{1,64}$`。
- 配额：单插件 **128 KiB / 128 键**，超限 `E_QUOTA_EXCEEDED`。
- 命名空间隔离为 `plugin.data.<pluginId>`，不会写进用户笔记，也不会与其他插件串味。
- 键值随插件数据保存；**卸载时默认清除**（选"保留设置"除外）。

### 4.11 `ctx.ai` — 宿主代办的模型推理（`ai.inference`）

| 方法 | 返回 | 说明 |
|---|---|---|
| `status()` | `Promise<AiStatus>` | `{ configured, provider, model, baseUrl, maxTokens, temperature, balanceProvider }` |
| `configure(patch)` | `Promise<AiStatus>` | 绑定/更新模型服务；`apiKey` 传空表示沿用已保存的 Key，`clear: true` 清空 |
| `chat({ messages, tools?, maxTokens?, temperature? })` | `Promise<AiReply>` | 一次非流式模型调用 |
| `models()` | `Promise<string[]>` | 当前绑定服务的模型 ID（最多 300 个） |
| `balance()` | `Promise<AiBalance>` | 适配的官方余额 / 套餐配额，成功缓存 60 秒 |

```ts
interface AiMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  toolCalls?: { id: string; name: string; arguments: string }[]; // assistant 的工具调用
  toolCallId?: string;   // tool 结果对应的调用 id
  toolName?: string;
  isError?: boolean;
}

interface AiReply {
  text: string;
  reasoning: string;
  toolCalls: { id: string; name: string; arguments: string }[];
  finishReason: string;  // 'stop' | 'tool_calls' | 'max-tokens' | ...
  model: string;
  usage: { inputTokens: number; outputTokens: number };
}
```

- 支持 `openai-compatible` 与 `anthropic-compatible` 两种线协议；`provider` 只接受这两个值，
  也兼容 `deepseek-openai` / `deepseek-anthropic` 这类旧写法。
- **API Key 只存在宿主**：`status()`/`configure()` 的返回值永远不含 Key；插件之后也读不回。
- 插件依旧没有网络：`fetch`/`XMLHttpRequest` 被 CSP 与 `blockNetwork(true)` 禁止；模型请求由宿主发出。
- 单次调用走 **120 s** 宿主预算（`PluginLimits.AI_TIMEOUT_MS`），不是普通 RPC 的 15 s。
- 单次最多 **128 条消息 / 32 个工具**；请求体仍受 512 KiB 限制。
- 未绑定、HTTP 非 2xx、网络异常统一 `E_MODEL_UNAVAILABLE`；错误文本保留服务端 message。
- 工具调用闭环由插件负责：把 assistant 的 `toolCalls` 原样带回，再追加 `role: 'tool'` 消息。
- `ctx.ai.models()` 获取当前绑定服务的模型 ID，最多 300 个；`ctx.ai.balance()` 获取已适配官方
  服务的余额或 Coding Plan 配额（成功缓存 60 秒）。两者超时 30 秒、都由宿主代发，
  不接受插件指定 URL / Header。未知余额服务返回 `supported: false`，失败抛错供 UI 重试。
- `AiStatus.balanceProvider` 返回当前识别到的余额服务名（不支持则空字符串）。Base URL / Key
  最多 8192 字符；仅切换模型可调用 `configure({ model: '...' })` 复用宿主 Key。

```js
const status = await ctx.ai.status();
if (!status.configured) {
  await ctx.ai.configure({ provider: 'openai-compatible', baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat', apiKey: 'sk-…' });
}
const reply = await ctx.ai.chat({
  messages: [{ role: 'system', content: '只回答一句话' }, { role: 'user', content: '你好' }],
  maxTokens: 256
});
await ctx.ui.notice(reply.text);
```

### 4.12 `ctx.views` — 侧栏插件视图（`ui.views`）

```js
const view = ctx.views.register({
  id: 'chat',
  title: '我的助手',
  render(container, ctx) { /* container 是插件 WebView 里的 DOM 节点 */ }
});
ctx.subscriptions.add(view);
await view.ready;              // 宿主接受注册后 resolve true
await ctx.views.open('chat');  // 让工作区打开右侧栏并显示该视图
```

- `id` 规则同命令 id：`^[a-z0-9][a-z0-9._-]{0,63}$`；单插件最多 **8** 个视图。
- `render(container, ctx)` 在下一次 `present()` 时调用；`container` 由宿主清空并交给插件，
  **不要**假设它跨挂载保留（状态放在插件闭包或 `ctx.storage` 里）。
- `render` 运行在插件的 ArkWeb 页内，只能操作自己的 DOM；不能用它创建 ArkUI 组件，
  也不能借此访问宿主页面、读取本地文件或联网。
- `views.open(id?)` 会通过宿主请求工作区展开右侧栏；**只有已安装并处于 ACTIVE 的插件**
  才可能响应。没有安装插件时，宿主不会显示任何内置入口。
- 视图声明随停用/卸载释放；`ctx.subscriptions.add(view)` 是最省心的清理方式。

> 侧栏顶部出现哪个插件入口，由**已安装的插件**决定。例如 Harness 插件的图标只有在
> `lexinote.harness` 安装后才会出现；点击它才会启用插件并渲染聊天视图。宿主没有内置的
> Harness 页面或隐藏开关。

---

## 5. 生命周期

```text
安装（VALIDATING → INSTALLED_DISABLED）
   ↓ 用户授权能力
启用：STARTING → boot WebView → activate(ctx) → ACTIVE
   ↓ 用户停用 / 启用另一个插件
停用：STOPPING → deactivate() → 逆序释放 subscriptions → 清除命令/事件 → INSTALLED_DISABLED
```

- `activate` 应**尽快返回**。宿主启动后只观察 1.2 秒内是否有失败日志：超过这个窗口仍会标记
  「已启用」，但你之后抛出的错误只会记进诊断，不会再把插件的状态改成失败。重活放到命令里做。
- `activate` 抛错 → `FAILED`，设置页显示具体错误，可重试。
- `deactivate` 抛错不会阻止卸载，但会在诊断里记一行。
- **同一时刻只有一个插件处于 ACTIVE**：启用第二个会先停用第一个。插件不应假设自己是唯一的。
- 应用重启后，工作区里标记为启用的插件会在运行时挂载完成后恢复启用；未启用的保持「已停用」。
  恢复同样要经过用户授权集合校验，不会绕过权限。

---

## 6. 能力清单

| 能力 | 解锁 |
|---|---|
| `vault.read` | `listMarkdown` / `get` / `read` |
| `vault.write` | `create` / `write` / `rename` / `delete` |
| `notes.metadata.read` | `metadata.get` |
| `editor.read` | `editor.active` / `getValue` |
| `editor.write` | `replaceSelection` / `replaceAll` |
| `workspace.views` | `activeFile` / `openFile` / `snapshot` |
| `ui.notice` | `ui.notice` |
| `ui.modal` | `ui.confirm`（当前不可用） |
| `ui.commands` | `commands.register` |
| `ai.inference` | `ctx.ai.status` / `configure` / `chat` / `models` / `balance`；宿主代办 HTTP，插件仍无网络 |
| `ui.views` | `ctx.views.register` / `unregister` / `open` |
| `plugin.storage` | `storage.*` |
| `network` | **实验版拒绝安装**，声明即被拒 |

规则：

1. **默认拒绝**：装完是 0 能力，用户逐项勾选。
2. 清单声明是**上限**；不能授予清单没有的能力。
3. 每次调用宿主都会复核；撤销后立刻失效（不是等到下次启动）。
4. 只申请真正用到的能力——多申请会让用户更难相信你。

---

## 7. 错误码

| 码 | 触发 | 作者该怎么办 |
|---|---|---|
| `E_INVALID_ARGUMENT` | 参数缺失、命令 id 非法、空标题 | 修代码 |
| `E_INVALID_PATH` | 路径规则违规 | 用相对 `.md` 路径 |
| `E_PATH_EXISTS` | 目标已存在 | 先 `get` 再决定覆盖或改名 |
| `E_NOT_FOUND` | 文件/项目/命令不存在 | 先 `get` 判空 |
| `E_VAULT_FORBIDDEN` | 知识库不在作用域 | 只用 `ctx.vaultId` |
| `E_PERMISSION_DENIED` | 能力未授权 | 提示用户去设置里授权 |
| `E_CONFLICT` | 文件已被改动 | 重新 `get` 后重试 |
| `E_EDITOR_CONFLICT` | 用户有未保存草稿 | 提示用户先保存 |
| `E_EDITOR_READONLY` | 无活动编辑器 / 只读 | 先 `editor.active()` 判空 |
| `E_UNSUPPORTED_API` | 该能力本版未实现 | 降级或提示，不要假装成功 |
| `E_MODEL_UNAVAILABLE` | 模型未绑定、HTTP 非 2xx、网络异常 | 提示用户绑定模型或检查配置；不要假装成功 |
| `E_QUOTA_EXCEEDED` | 存储/命令/源码/视图超限 | 精简数据 |
| `E_RATE_LIMITED` | 并发 >16 或请求体 >512 KiB | 串行化、分页 |
| `E_TIMEOUT` | 15s 未响应 | 拆分任务 |
| `E_CANCELLED` | 插件正在停用 | 停止后续调用 |
| `E_PLUGIN_FAILED` | 插件代码抛错 | 看诊断日志 |

错误消息统一为 `"CODE: 说明"`；`error.code` 上也带同一码。

---

## 8. 最小可用模板

`manifest.json`：

```json
{
  "format": "lexinote-plugin",
  "formatVersion": 1,
  "id": "me.quick-capture",
  "name": "快速收集",
  "version": "1.0.0",
  "apiVersion": "1.0",
  "main": "main.js",
  "description": "把一条想法追加到「收集箱」笔记",
  "author": "Me",
  "capabilities": ["vault.read", "vault.write", "ui.commands", "ui.notice"],
  "targets": ["harmonyos"]
}
```

`main.js`：

```js
const { definePlugin } = require('@lexinote/sdk');

const INBOX = '收集箱.md';

module.exports = definePlugin({
  async activate(ctx) {
    ctx.subscriptions.add(ctx.commands.register({
      id: 'capture',
      title: '追加到收集箱',
      run: async () => {
        const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
        let file = await ctx.vault.get(INBOX);
        if (!file) {
          file = await ctx.vault.create(INBOX, '# 收集箱\n');
        }
        const current = await ctx.vault.read(file);
        const next = `${current.replace(/\s*$/, '')}\n\n- [ ] ${stamp}\n`;
        try {
          await ctx.vault.write(file, next);
          await ctx.ui.notice('已追加到收集箱');
        } catch (error) {
          if (error.code === 'E_CONFLICT') {
            await ctx.ui.notice('笔记刚被改过，请重试一次');
            return;
          }
          throw error;
        }
      }
    }));
  },

  async deactivate() {
    // 没有自建定时器；订阅由 subscriptions 自动释放。
  }
});
```

构建与打包：

```sh
# 1) 安装 SDK 类型（可选，仅开发期）
# 2) 打包成单文件 CommonJS（示例用 esbuild）
npx esbuild main.js --bundle --format=cjs --platform=neutral --outfile=dist/main.js
# 3) 组装 ZIP：manifest.json 与 main.js 放在同一层
#    manifest.main 要写成 "main.js"（把 dist 的内容放根）
zip -X quick-capture.zip manifest.json main.js
```

---

## 9. 验收清单（发布前逐条打勾）

**清单与包**

- [ ] `format`/`formatVersion` 正确，`id` 全局唯一且符合正则
- [ ] `version` 为 `x.y.z`，`apiVersion` 以 `1.` 开头
- [ ] `main` 指向真实存在的 `.js`，包内没有多余顶层目录
- [ ] ZIP 用 `unzip -l` 检查无 `../`、无绝对路径、无符号链接
- [ ] 解压总量 < 16 MiB，条目 < 512，`main.js` < 2 MiB

**代码**

- [ ] `module.exports = definePlugin({ activate, deactivate })`
- [ ] 只 `require('@lexinote/sdk')`，没有相对路径或其他模块
- [ ] `activate` 里没有长耗时逻辑（建议 1.2s 内返回）
- [ ] 所有 disposable 都 `ctx.subscriptions.add(...)`
- [ ] 自建定时器在 `deactivate` 里清理
- [ ] 所有 `ctx` 调用都 `await`/`.catch`，没有未处理的 Promise
- [ ] 不假设 `ui.confirm` 可用；插件 UI 只能用 `ctx.views` 在插件自己的 WebView 里渲染
- [ ] 用 `ai.inference` 时：Key 只经 `configure` 写入、不落插件 storage；处理 `E_MODEL_UNAVAILABLE`
- [ ] 用 `ui.views` 时：`render` 不依赖跨挂载 DOM，视图登记进 `subscriptions`

**行为**

- [ ] `capabilities` 与实际调用一一对应，没有多申请
- [ ] `E_CONFLICT`/`E_EDITOR_CONFLICT` 有面向用户的提示
- [ ] `create` 前先 `get`，避免 `E_PATH_EXISTS`
- [ ] 写入的是知识库相对 `.md` 路径
- [ ] 卸载/停用后不再有日志与命令残留

**真机验证**

1. 设置 → 插件 → 从本地安装 ZIP… → 选择文件 → 卡片出现且状态「已停用」
2. 全部授权（或逐项）→ 启用 → 状态「已启用」
3. 命令面板里能找到你的命令，执行后有通知
4. 「能力与诊断」里能看到 `ctx.log` 输出，**没有 `error`**
5. 停用 → 命令从面板消失；再启用不重复注册
6. 重启应用 → 已启用的插件恢复、未启用的保持「已停用」，权限状态不变

---

## 10. 常见错误对照

| 现象 | 原因 | 处理 |
|---|---|---|
| 安装报「入口文件 main.js 不存在（插件目录内：src, package.json, …）」 | 把**源码工程**打包了，里面是 `src/`、`tsconfig.json`，没有构建产物 | 先 `esbuild --bundle`，把产物当 `main.js` 再打包 |
| 启动报 `E_UNSUPPORTED_MODULE: @lezer/common`（或任意第三方包名） | 依赖没有内联进 bundle，运行时 `require` 到了白名单外的模块 | 用 `--bundle` 把依赖打进来，不要 `--external` |
| 安装报「插件包根目录缺少 manifest.json」 | manifest 在子目录里，且不是唯一顶层目录 | 把 manifest 放根，或整体包在一个文件夹里 |
| 安装报「插件包结构异常：… 不在插件文件夹内」 | 根上有与文件夹同名的散落文件 | 重新打包，别把散落文件一起压进去 |
| 安装报「不支持的压缩方式 9/12」 | 使用了 deflate64/bzip2 等 | 用常规 deflate 重新压 |
| 安装报「未知能力 root.everything」 | 能力名写错 | 对照 `§6` |
| 启用后状态「启动失败」 | `activate` 抛错 / 代码有语法错误 | 看诊断里的 `E_PLUGIN_FAILED` 明细 |
| 命令面板里没有命令 | 未授予 `ui.commands`；或 id 与内置命令冲突 | 授权后重新启用；改 id |
| 写入报 `E_PERMISSION_DENIED` | 未授予 `vault.write` | 去设置勾选 |
| 写入报 `E_CONFLICT` | 两次写之间文件被改（含你自己没重新读） | 重新 `get` 再写 |
| 写入报 `E_EDITOR_CONFLICT` | 用户正在编辑同一篇 | 提示用户保存后重试 |
| 事件不触发 | 未授予能力 / 订阅被 dispose / 事件类型拼错 | 检查 `§4.8` |
| `storage.set` 报 `E_QUOTA_EXCEEDED` | 超过 128 KiB 或 128 键 | 精简或分片键 |
| `ai.chat` 报 `E_MODEL_UNAVAILABLE` | 未绑定模型、Key 错误、网络失败 | 先在插件视图里绑定模型；展示服务端 message |
| 侧栏没有插件图标 | 插件未安装；或 id 与宿主约定不一致 | 先安装插件；本版 Harness 的 id 是 `lexinote.harness` |
| 视图空白 / `E_UNSUPPORTED_API: 插件没有注册视图` | `activate` 里没注册，或注册失败 | 看「能力与诊断」；确认已授予 `ui.views` |

---

## 11. 版本与废弃策略

- SDK `1.x` 内保持同名字段/方法兼容；破坏性变更进入 `2.0`。
- `1.1` 只新增 `ai.inference`、`ui.views` 与 `ctx.ai` / `ctx.views`，未改动既有字段；
  用 `1.0` 清单的插件继续按原行为运行。
- `manifest.apiVersion` 是 **SDK 兼容基线**，与 App 版本不是一回事。
- `capabilities` 是**声明**，不等于已授权。
- 新增方法只会出现在 `1.x` 的次版本；把未知方法当 `E_UNSUPPORTED_API` 处理，插件就能跨版本存活。
- 该字段/方法被标废弃后，至少保留一个稳定版本周期，并在诊断里给出迁移提示。

---

## 12. 安全红线（宿主已强制，作者不要试图绕过）

- 不能读取任意本地文件、系统路径、沙箱路径、其他知识库。
- 不能访问网络（`fetch`/`XMLHttpRequest` 在页面 CSP 下被禁；`network` 能力安装即被拒）。
- `ai.inference` 不是网络能力：插件只提交消息与工具定义，URL、API Key、HTTP 与超时都由宿主持有；
  宿主只允许用户绑定的端点，且 Key 不会回传给插件。
- 不能加载 Node/Electron 模块，不能执行外部脚本。
- 不能修改用户笔记之外的数据（设置、索引、其他插件的数据）。
- 不能静默吞掉错误：写失败必须让用户看到，而不是"看起来成功"。
