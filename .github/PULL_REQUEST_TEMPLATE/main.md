<!-- base 必须为 main。规范：https://github.com/peryixing-lab/LexiNote/blob/main/CONTRIBUTING.md -->

## 问题与修改后的行为

<!-- 写明文档错误或插件触发场景、修改前后的结果及关联 Issue。 -->

## 改动范围

- 目标分支：`main`
- README / 项目文档 / PR 模板 / Harness / 许可声明：
- 关联的平台宿主 PR 和兼容宿主版本（如适用）：

## 验证结果

- 文档链接、分支大小写、代码路径和命令检查：
- Harness 改动的 `npm ci`、`npm run build`、`npm test` 结果：
- 模型配置 / 凭据 / RPC 改动的 `npm run test:host` 结果和 HarmonyOS checkout：
- 插件清单、权限、数据迁移与受影响平台兼容性结果（按改动填写）：
- 视图截图、未执行项及已知限制：

## 提交前检查

- [ ] base 为 `main`，只包含插件、文档或相关许可 / 模板变化，未混入应用工程。
- [ ] 纯文档 PR 已检查链接和路径；插件 PR 已记录对应构建与测试，未执行项如实说明。
- [ ] 跨分支依赖、宿主 API / 权限兼容性、版本清单和变更记录已同步，或已说明不适用。
- [ ] 未包含插件 ZIP、安装包、`dist/`、`node_modules/`、真实 API Key、个人数据或本机配置。
- [ ] 已保留第三方版权与许可证声明，并使用虚构数据及凭据测试。
