<!-- GitHub 默认模板入口。请先选择正确的 base，再使用相应系统模板。 -->

## 选择平台规范与模板

- **HarmonyOS**：base 选 `HarmonyOS`；[规范](https://github.com/peryixing-lab/LexiNote/blob/HarmonyOS/CONTRIBUTING.md) / [模板](https://github.com/peryixing-lab/LexiNote/blob/main/.github/PULL_REQUEST_TEMPLATE/HarmonyOS.md)
- **Windows**：base 选 `Windows`；[规范](https://github.com/peryixing-lab/LexiNote/blob/Windows/CONTRIBUTING.md) / [模板](https://github.com/peryixing-lab/LexiNote/blob/main/.github/PULL_REQUEST_TEMPLATE/Windows.md)
- **macOS**：base 选 `macOS`；[规范](https://github.com/peryixing-lab/LexiNote/blob/macOS/CONTRIBUTING.md) / [模板](https://github.com/peryixing-lab/LexiNote/blob/main/.github/PULL_REQUEST_TEMPLATE/macOS.md)
- **插件 / 共享文档**：base 选 `main`；[规范](https://github.com/peryixing-lab/LexiNote/blob/main/CONTRIBUTING.md) / [模板](https://github.com/peryixing-lab/LexiNote/blob/main/.github/PULL_REQUEST_TEMPLATE/main.md)

创建 PR 的比较链接可添加 `template=HarmonyOS.md`、`template=Windows.md`、`template=macOS.md` 或 `template=main.md` 以载入对应模板。**模板参数不会设置目标分支**，请检查 base。[选择方法与示例](https://github.com/peryixing-lab/LexiNote/blob/main/docs/PR_GUIDELINES.md)

## 问题与修改后的行为

<!-- 说明触发操作、原有行为、修改后的结果及关联 Issue。可将本正文替换为上面的系统模板。 -->

## 目标与验证

- 目标分支及改动范围：
- 系统 / 工具链 / 架构：
- 实际执行的构建、测试或文档检查与结果：
- 截图 / 录屏（如适用）：
- 未执行项、兼容性及已知限制：

## 提交前检查

- [ ] base 与所选平台一致，已阅读对应规范并补齐系统专属验证项。
- [ ] 未将整个平台工程合并到 main，跨分支改动已拆分并互相链接。
- [ ] 未包含安装包、缓存、个人数据、真实凭据或签名材料。
