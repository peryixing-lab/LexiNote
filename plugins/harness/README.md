# Harness 智能体插件

当前版本：**1.5.0**。从 [LexiNote 2.0.1 Release](https://github.com/peryixing-lab/LexiNote/releases/tag/v2.0.1) 下载 `harness-lexinote-harness.zip`，在应用的「设置 → 插件」中安装。

## 构建

需要 Node.js 和 npm。在本目录执行：

```sh
npm ci
npm run build
```

构建依赖固定为 `markdown-it 14.1.0`，锁文件随源码提交。产物为 `dist/harness-lexinote-harness.zip`；`node_modules/` 和 `dist/` 不进入版本控制。构建无需应用工程。

## 测试

```sh
npm test
```

此命令运行会话与历史管理回归。模型配置与宿主密钥隔离的集成测试需要另行检出 `HarmonyOS` 分支，再运行：

```sh
LEXINOTE_HARMONY_ROOT=/absolute/path/to/HarmonyOS-checkout npm run test:host
```

集成测试使用模拟宿主与虚构凭据，不调用真实模型服务。宿主 SDK、契约和运行时见 [HarmonyOS 分支](https://github.com/peryixing-lab/LexiNote/tree/HarmonyOS/packages)。

版本变更见 [CHANGELOG.md](CHANGELOG.md)，第三方声明见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。
