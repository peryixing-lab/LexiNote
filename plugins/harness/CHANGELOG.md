# Harness 1.6.0

- 新增三种可选上下文范围：**当前笔记**（优先读取活动编辑器含未保存内容，退回已保存全文）、**选中内容**（提取 UTF-16 选区偏移、精确行号 `#L起-L终` 与前后文）、**指定笔记**（弹窗搜索并勾选最多 12 篇笔记，自动按预算裁剪）。
- 回答引用真实笔记：自动校验模型回答中的 `[标题](相对路径.md#L起-L终)` 与 `[[双链]]`（过滤虚构路径与未消歧重名引用），渲染为可点击的引用药丸（通过 `workspace.openFile` 在知萤中打开）。
- 绝不直接覆盖原文：所有写入及破坏性工具（`create_note`、`update_note`、`append_to_note`、`rename_note`、`delete_note`、`replace_selection`、`replace_active_editor`）只生成 Diff 修改建议卡片（`harness.changes.v1`），必须经用户点击“确认写入/确认删除”才生效。
- 新增冲突检测与一键撤销：确认写入前与撤销前均校验笔记修改时间与编辑器 revision，若发生手动后续编辑则阻止覆盖并提示冲突；每次已确认写入均支持“撤销本次写入”恢复原状。
- 全平台宿主权限控制保持严格隔离：各平台补全 `editor.active()` 选区快照、`noteId` 与 `events.on` 能力门控；插件权限继续完全由宿主颁发与实时校验。

# Harness 1.5.0

- 按 DeepSeek Harness 的凭据模型调整 API Key 处理：Key 只写入宿主的按插件密钥槽，`status`/`configure` 只返回脱敏状态，插件存储和 boot 数据不再保存 Key。
- 服务商配置改为“每插件 profile + `profileId` 引用”；`ai.configure` 支持 `action: select/remove`、`profileId`、`name`、`select`，不再需要插件保存 Key。
- 新增旧数据迁移：`harness.providers.v1` 中的 Key 会迁移到宿主并删除本地副本；旧宿主仍走兼容路径，不会因升级插件而失效。
- 公网 Base URL 仅允许 HTTPS，本地/局域网可继续用 HTTP；HTTP 请求拒绝重定向，Anthropic 兼容线只发 `x-api-key`，请求带 User-Agent。
- Key 字符集按可打印 ASCII 校验，错误信息统一脱敏；新增 `E_MISSING_CREDENTIAL` / `E_INVALID_CREDENTIAL`。
- 卸载插件时宿主清除该插件的全部模型密钥；启动 payload 也会剔除旧版 `harness.providers.v1`，迁移前不再把 Key 交给页面。

# Harness 1.4.0

- 新增“历史”入口，支持搜索、恢复和删除本地对话，新建会话保留旧对话。
- 未发送的草稿随对话保存；恢复历史后可继续发送消息，使用当前输入栏选中的模型。
- 自动兼容旧版保存的当前会话。最多保留 20 段对话，长对话保留最近内容，存储不足时优先清理最早历史。
- 保存失败会提示并阻止切换；历史、账号和模型缓存的写入在插件内串行执行。
- 此版本仅更新插件；思考强度按用户要求暂缓。

# Harness 1.3.0

- 多服务商由插件自行管理，沿用现有 `ai.configure`、`ai.chat`、`ai.models`、`ai.balance` 与 `storage` 接口，无需新增宿主 API 或升级宿主来启用此功能。
- 在“模型”页面添加、编辑、删除和选择服务商；服务商名称、模型列表和账号分别保存。
- 切换时恢复该账号的完整绑定，对话、模型获取和余额查询均使用该账号；同一地址可以配置不同 Key。
- 服务商配置及 API Key 保存在插件自己的本地工作区数据中，未加密，不写入笔记或对话记录。卸载并清除插件数据会删除这些配置。
- 原有宿主绑定只能迁移公开信息，旧 API 不提供 Key 读回。切换账号前，请在原服务商的“编辑”中补填一次 Key；未切换时仍可沿用原宿主绑定。
- 最多保存 32 个服务商，配置总量受插件存储配额限制；失败写入不会覆盖当前账号。

安装：使用 `dist/harness-lexinote-harness.zip` 更新插件。知萤应用及 SDK 无需修改。
