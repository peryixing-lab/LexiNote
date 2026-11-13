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
