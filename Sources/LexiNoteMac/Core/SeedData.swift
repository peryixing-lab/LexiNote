import Foundation

enum SeedData {
    static func vaults(now: Date = Date()) -> [Vault] {
        [
            Vault(id: "default-vault", name: "个人知识库",
                  detail: "日常灵感、大学课程笔记与个人知识网络",
                  createdAt: now.addingTimeInterval(-86400 * 7)),
            Vault(id: "dev-vault", name: "开发项目库",
                  detail: "HarmonyOS 架构设计与技术复盘文档",
                  createdAt: now.addingTimeInterval(-86400 * 3))
        ]
    }

    static func notes(now: Date = Date()) -> [Note] {
        var result: [Note] = []

        result.append(Note(
            id: "note-algo-complexity", vaultID: "default-vault",
            notebook: "计算机课程", type: .study, level: .study,
            title: "时间复杂度",
            content: #"""
# 时间复杂度核心笔记

> [!NOTE] 核心定理
> 算法的时间复杂度衡量输入规模 $n$ 趋近无穷时，基本操作执行次数的增长率。

## 1. 主定理与递推公式

$$T(n) = aT(n/b) + f(n)$$

常见分治递归如归并排序满足 $a=2, b=2$，对应复杂度为 $O(n \log n)$。

## 2. 与其他结构的关联

- 树形查找请结合 [[二叉树与递归遍历]] 一起复习
- 状态转移空间优化参见 [[动态规划核心模型]]
- 工程性能基线在 [[知萤 LexiNote 架构设计规范]] 中也有应用

## 3. 自测清单

- [x] 推导主定理三种情况
- [x] 整理常见排序算法最坏与平均复杂度
- [ ] 完成红黑树旋转摊还分析 #学习/算法
"""#,
            tags: ["学习/算法", "考试重点"],
            properties: [NoteProperty(key: "课程", value: "数据结构与算法"),
                         NoteProperty(key: "章节", value: "第 1 章 渐近分析"),
                         NoteProperty(key: "掌握度", value: "熟练")],
            pinned: true, favorite: true,
            createdAt: now.addingTimeInterval(-3600 * 36),
            updatedAt: now.addingTimeInterval(-3600 * 2),
            path: "计算机课程/时间复杂度.md"))

        result.append(Note(
            id: "note-binary-tree", vaultID: "default-vault",
            notebook: "计算机课程", type: .study, level: .study,
            title: "二叉树与递归遍历",
            content: #"""
# 二叉树与递归遍历

> [!TIP] 记忆线索
> 前序定根、中序分左右、后序自底向上汇总子树信息。

## 1. 遍历框架代码

```typescript
function traverse(node: TreeNode | undefined): void {
  if (!node) return;
  // 前序位置
  traverse(node.left);
  // 中序位置
  traverse(node.right);
  // 后序位置
}
```

## 2. 复杂度与拓展

每个节点恰好被访问常数次，整体满足 [[时间复杂度]] 中的线性阶 $O(n)$。当树退化为链表时，高度变为 $O(n)$。

子树最优解汇总可自然过渡到 [[动态规划核心模型]]（树形 DP）。
"""#,
            tags: ["学习/算法", "树结构"],
            properties: [NoteProperty(key: "课程", value: "数据结构与算法"),
                         NoteProperty(key: "关联导图", value: "数据结构与算法体系")],
            favorite: true,
            createdAt: now.addingTimeInterval(-3600 * 28),
            updatedAt: now.addingTimeInterval(-3600 * 5),
            path: "计算机课程/二叉树与递归遍历.md"))

        result.append(Note(
            id: "note-dp-model", vaultID: "default-vault",
            notebook: "计算机课程", type: .study, level: .pro,
            title: "动态规划核心模型",
            content: #"""
# 动态规划核心模型

## 1. 状态转移三步法

1. 明确状态变量（如容量、前 $i$ 个元素）
2. 推导状态转移方程：

$$dp[i][w] = \max(dp[i-1][w], dp[i-1][w-c_i] + v_i)$$

3. 利用滚动数组降低 [[时间复杂度]] 与空间开销。

## 2. 树形与图论结合

在树上进行状态转移时，必须先完成 [[二叉树与递归遍历]] 的后序收集。
"""#,
            tags: ["学习/算法", "动态规划"],
            properties: [NoteProperty(key: "状态定义", value: "重叠子问题 + 最优子结构")],
            createdAt: now.addingTimeInterval(-3600 * 20),
            updatedAt: now.addingTimeInterval(-3600 * 8),
            path: "计算机课程/动态规划核心模型.md"))

        result.append(Note(
            id: "note-lexinote-arch", vaultID: "default-vault",
            notebook: "产品与架构", type: .markdown, level: .pro,
            title: "知萤 LexiNote 架构设计规范",
            content: #"""
# 知萤 LexiNote 架构设计规范

> 想记就记，需要时足够专业。让每一条笔记，成为可以连接、组织与重访的知识。

## 1. 核心一致性原则

- **不可变主键**：笔记以 UUID 标识，重命名标题时自动修复全文 [[双向链接]]，绝不断链。
- **文件优先 + RDB 索引**：正文保存为标准 Markdown，随时可导出迁移。
- **工具分层不割裂**：同一篇文档可在「简洁 / 学习 / 专业」三级工具间自由切换。

## 2. 算法与性能基线

大纲树与导图布局控制在目标 [[时间复杂度]] 之内，树形遍历采用 [[二叉树与递归遍历]] 的原子子树计算。

## 3. 桌面工作区的区域划分

| 区域 | 宽度 | 职责 |
| --- | --- | --- |
| 图标栏 | 56 | 知识库、搜索、图谱、模板与回收站 |
| 侧栏 | 244 | 文件夹、笔记、可视化空间 |
| 编辑区 | 弹性 | 标签页、标题、正文与状态栏 |
| 检查器 | 280 | 大纲、出链、反向链接与属性 |
"""#,
            tags: ["开发/鸿蒙", "知识管理"],
            properties: [NoteProperty(key: "架构原则", value: "本地优先 · 文件为事实来源"),
                         NoteProperty(key: "视觉体系", value: "紫色沉浸光感 HDS")],
            pinned: true, favorite: true,
            createdAt: now.addingTimeInterval(-3600 * 14),
            updatedAt: now.addingTimeInterval(-3600 * 1),
            path: "产品与架构/知萤 LexiNote 架构设计规范.md"))

        result.append(Note(
            id: "note-quick-today", vaultID: "default-vault",
            notebook: "速记收件箱", type: .quick, level: .simple,
            title: "今日灵感与待办速记",
            content: #"""
# 今日灵感与待办速记

- [x] 用 10 秒快速记录把散落的课堂想法收拢到知萤
- [x] 把数据结构课程笔记连接到「数据结构与算法体系」思维导图
- [ ] 周五前复盘一次时间复杂度与动态规划核心模型

> 记下第一句话时不需要纠结分类，知识会在连接中自然生长。

今天还想整理一下桌面端的快捷键：命令面板、快速切换与阅读视图。
"""#,
            tags: ["日常/灵感", "待办"],
            createdAt: now.addingTimeInterval(-3600 * 4),
            updatedAt: now.addingTimeInterval(-1800),
            path: "速记收件箱/今日灵感与待办速记.md"))

        result.append(Note(
            id: "note-desktop-recap", vaultID: "dev-vault",
            notebook: "设计复盘", type: .markdown, level: .pro,
            title: "桌面工作区交互复盘",
            content: #"""
# 桌面工作区交互复盘

> [!IMPORTANT] 目标
> 在宽屏上保持「左手结构、中间写作、右手关系」的稳定三段式，同时让每一段都可以收起。

## 1. 保留的交互

- 标签页在标题栏中横向滚动，新建入口固定在右侧
- 侧栏同时承担文件夹树与笔记列表，减少一次跳转
- 检查器默认收起，用大纲按钮随时召回
- 命令面板覆盖在内容之上，不打断当前文档

## 2. 需要重做的部分

桌面端不再有 HDS 沉浸光感材质，macOS 版改用：

1. 标题栏与侧栏的纯色分层
2. 浮层的系统半透明材质（可关闭）
3. 0.5pt 的 workspace_line 分隔线

## 3. 验收标准

- [x] 1120 × 720 窗口下侧栏与编辑区不重叠
- [x] 深色与浅色主题的正文对比度 ≥ 4.5
- [ ] 图谱在 200 个节点内的拖动帧率

关联：[[知萤 LexiNote 架构设计规范]]。
"""#,
            tags: ["开发/鸿蒙", "交互"],
            properties: [NoteProperty(key: "阶段", value: "桌面端还原"),
                         NoteProperty(key: "验收", value: "布局 / 主题 / 性能")],
            pinned: true,
            createdAt: now.addingTimeInterval(-3600 * 30),
            updatedAt: now.addingTimeInterval(-3600 * 6),
            path: "设计复盘/桌面工作区交互复盘.md"))

        result.append(Note(
            id: "note-local-files", vaultID: "dev-vault",
            notebook: "工程实践", type: .markdown, level: .pro,
            title: "本地文件与链接解析约定",
            content: #"""
# 本地文件与链接解析约定

## 1. 文件组织

```text
个人知识库/
  计算机课程/
    时间复杂度.md
  思维导图/
    数据结构与算法体系.mindmap.json
  白板/
    算法与架构灵感白板.canvas.json
```

## 2. Frontmatter

每篇笔记开头保存稳定主键与元信息：

```yaml
---
id: note-algo-complexity
title: 时间复杂度
notebook: 计算机课程
type: study
tags: ["学习/算法"]
---
```

## 3. 双链解析

`[[时间复杂度]]` 先按标题匹配，再按主键回退；解析失败时保留原文并标为「未创建」。

延伸阅读：[[桌面工作区交互复盘]]。
"""#,
            tags: ["开发/工程", "本地优先"],
            properties: [NoteProperty(key: "存储", value: "Markdown + Frontmatter"),
                         NoteProperty(key: "索引", value: "启动时全量扫描")],
            createdAt: now.addingTimeInterval(-3600 * 18),
            updatedAt: now.addingTimeInterval(-3600 * 9),
            path: "工程实践/本地文件与链接解析约定.md"))

        return result
    }

    static func mindMaps(now: Date = Date()) -> [MindMap] {
        let map1 = MindMap(
            id: "map-ds-system", vaultID: "default-vault",
            title: "数据结构与算法体系", layout: .right, rootNodeID: "root",
            nodes: [
                MindNode(id: "root", parentID: "", text: "数据结构与算法体系", order: 0, colorTag: .purple,
                         noteRefID: "note-algo-complexity", noteRefTitle: "时间复杂度", note: "期末核心复习总纲"),
                MindNode(id: "b1", parentID: "root", text: "复杂度分析", order: 1, colorTag: .purple,
                         noteRefID: "note-algo-complexity", noteRefTitle: "时间复杂度", note: "渐近上界 O 与主定理"),
                MindNode(id: "b1-1", parentID: "b1", text: "大 O 渐近记号", order: 1, colorTag: .purple),
                MindNode(id: "b1-2", parentID: "b1", text: "Master 主定理", order: 2, colorTag: .purple),
                MindNode(id: "b2", parentID: "root", text: "非线性树结构", order: 2, colorTag: .indigo,
                         noteRefID: "note-binary-tree", noteRefTitle: "二叉树与递归遍历", note: "递归序与平衡树"),
                MindNode(id: "b2-1", parentID: "b2", text: "前/中/后序递归框架", order: 1, colorTag: .indigo,
                         noteRefID: "note-binary-tree", noteRefTitle: "二叉树与递归遍历"),
                MindNode(id: "b2-2", parentID: "b2", text: "二叉搜索树与 AVL", order: 2, colorTag: .indigo),
                MindNode(id: "b3", parentID: "root", text: "动态规划模型", order: 3, colorTag: .teal,
                         noteRefID: "note-dp-model", noteRefTitle: "动态规划核心模型", note: "状态定义与空间压缩"),
                MindNode(id: "b3-1", parentID: "b3", text: "背包与区间 DP", order: 1, colorTag: .teal),
                MindNode(id: "b3-2", parentID: "b3", text: "树形 DP 状态汇总", order: 2, colorTag: .teal,
                         noteRefID: "note-dp-model", noteRefTitle: "动态规划核心模型")
            ],
            favorite: true,
            createdAt: now.addingTimeInterval(-3600 * 24),
            updatedAt: now.addingTimeInterval(-3600 * 1),
            trashedAt: nil)

        let map2 = MindMap(
            id: "map-lexi-product", vaultID: "default-vault",
            title: "知萤个人知识工作流", layout: .balanced, rootNodeID: "root",
            nodes: [
                MindNode(id: "root", parentID: "", text: "知萤知识工作流", order: 0, colorTag: .purple,
                         noteRefID: "note-lexinote-arch", noteRefTitle: "知萤 LexiNote 架构设计规范"),
                MindNode(id: "p1", parentID: "root", text: "1. 随手速记", order: 1, colorTag: .purple,
                         noteRefID: "note-quick-today", noteRefTitle: "今日灵感与待办速记", note: "10 秒无负担记录"),
                MindNode(id: "p2", parentID: "root", text: "2. 深度整理", order: 2, colorTag: .indigo,
                         noteRefID: "note-algo-complexity", noteRefTitle: "时间复杂度", note: "公式、高亮与代码块"),
                MindNode(id: "p3", parentID: "root", text: "3. 双链成网", order: 3, colorTag: .teal,
                         noteRefID: "note-binary-tree", noteRefTitle: "二叉树与递归遍历", note: "双向引用与局部图谱"),
                MindNode(id: "p4", parentID: "root", text: "4. 本地导出备份", order: 4, colorTag: .amber, note: "Markdown 与 JSON 自由迁移")
            ],
            favorite: false,
            createdAt: now.addingTimeInterval(-3600 * 12),
            updatedAt: now.addingTimeInterval(-3600 * 3),
            trashedAt: nil)

        return [map1, map2]
    }

    static func canvas(now: Date = Date()) -> CanvasBoard {
        CanvasBoard(
            id: "canvas-main", vaultID: "default-vault", title: "算法与架构灵感白板",
            cards: [
                CanvasCard(id: "card-1", title: "渐近复杂度基石",
                           content: "先明确输入规模 n，再衡量递归分治与状态空间。",
                           noteRefID: "note-algo-complexity", noteRefTitle: "时间复杂度",
                           x: 36, y: 42, colorTag: .purple),
                CanvasCard(id: "card-2", title: "递归子树思维",
                           content: "把原问题拆解成左子树与右子树的信息汇总。",
                           noteRefID: "note-binary-tree", noteRefTitle: "二叉树与递归遍历",
                           x: 310, y: 46, colorTag: .indigo),
                CanvasCard(id: "card-3", title: "重叠子问题记忆化",
                           content: "从递归树剪枝自然导出自底向上的状态转移表。",
                           noteRefID: "note-dp-model", noteRefTitle: "动态规划核心模型",
                           x: 170, y: 205, colorTag: .teal)
            ],
            edges: [
                CanvasEdge(id: "edge-1", fromID: "card-1", toID: "card-2", label: "分治递推"),
                CanvasEdge(id: "edge-2", fromID: "card-2", toID: "card-3", label: "树形 DP")
            ],
            createdAt: now.addingTimeInterval(-3600 * 10),
            updatedAt: now.addingTimeInterval(-3600 * 2))
    }
}
