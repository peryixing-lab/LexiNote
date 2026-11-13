# HarmonyOS 贡献指南与 PR 规范

本规范适用于鸿蒙应用、ArkTS / ArkUI、插件宿主、SDK 和原生系统能力。**PR 的目标分支（base）为 `HarmonyOS`**；Harness 独立插件与共享文档请提交到 `main`。

## 开发与提交

1. 从最新 `HarmonyOS` 创建工作分支，项目位于仓库根目录。按 [HarmonyOS README](https://github.com/peryixing-lab/LexiNote/blob/HarmonyOS/README.md) 准备 DevEco Studio、工程指定的 SDK 和 OHPM 依赖；当前工程 SDK 为 `26.0.0`。
2. 从 `build-profile.example.json5` 创建本机构建配置。共享构建选项变化时同步更新模板，本机签名配置不提交。
3. 一个 PR 聚焦一个问题。标题建议使用 `fix(harmonyos): …`、`feat(harmonyos): …`、`docs(harmonyos): …` 等格式。
4. 描述具体触发操作、原有行为和修改后的行为，并关联 Issue。跨平台修复分别提交对应分支，互相链接 PR。

## 构建与回归

应用代码或资源发生变化时，至少完成受影响的构建与回归，并记录实际命令及结果。例如：

```sh
devecocli build --modules entry --build-mode release
node scripts/tests/core-regression.cjs
```

没有安装 DevEco CLI 时可使用 DevEco Studio 构建；`scripts/build.sh` 默认构建 Debug，应在 PR 中如实标明构建模式。回归脚本的 TypeScript 环境按 README 配置，不要求与改动无关的脚本全部运行。

- **ArkTS / ArkUI**：检查编译、组件生命周期、状态更新、导航返回和页面销毁；不要将普通 TypeScript 的动态语法直接搬入 ArkTS。
- **存储与权限**：涉及保存、迁移、导入导出时，验证授权同意、取消、拒绝或撤销，以及失败后的草稿和原文件保留。
- **插件宿主 / SDK / RPC**：运行受影响的 `scripts/tests/plugin-*.cjs`；模型配置或凭据改动还应运行 `plugin-ai-credentials-regression.cjs`。能力、契约或兼容性变化需同步文档，并关联 main 上的文档或插件 PR。
- **SDK、权限或系统能力**：说明最低兼容版本、受影响设备与回退行为。不能仅凭 Node 模拟回归宣称系统能力已验收。
- **纯文档 PR**：检查链接、命令与路径即可，无需构建 HAP。

## 设备与界面验收

填写 DevEco Studio / SDK 版本、设备型号、HarmonyOS 版本，以及真机或模拟器。UI 改动按实际影响覆盖手机、平板或二合一布局、横竖屏、浅深色和中英文，并附相关截图或录屏。

涉及服务卡片、分享剪藏、跨设备接续、词萤 / 集萤联动、语音或文件授权时，记录对应设备上的操作与结果。缺少设备或外部工程时，写明未验证项目及原因，不标记为通过。

## PR 中必须说明

- 目标分支 `HarmonyOS`、改动范围、复现步骤与修复后的结果。
- 实际执行的构建模式、回归命令、设备与系统版本；未执行项及原因。
- 涉及持久化、权限、插件契约或 SDK 时的兼容性与失败处理。
- 异步或偶发用例若需重跑，保留首次失败信息并说明重跑结果。

## 文件与发布

不提交个人笔记、数据库、完整设备日志、密钥、证书、`.idea/`、`.hvigor/`、`oh_modules/`、构建目录或 HAP / HSP / APP。`build-profile.json5`、`local.properties` 和本机路径不进入版本控制。

保留第三方版权与许可证声明。新增权限、外部请求或依赖时说明用途、数据范围和版本变化。安装包、签名、版本号和 Release 由维护者统一安排，普通源码 PR 不附安装包。

[返回各平台 PR 规范入口](https://github.com/peryixing-lab/LexiNote/blob/main/docs/PR_GUIDELINES.md)
