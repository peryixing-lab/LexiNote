import type {
  AppSettings,
  CanvasBoard,
  LexiProject,
  MindMapDoc,
  MindMapNode,
  NoteItem,
  NoteProperty,
  PersistedState,
  VaultItem
} from '../../shared/types';
import { DEFAULT_ACCENT } from './theme';

const HOUR = 3600_000;

function note(
  id: string,
  title: string,
  notebook: string,
  type: NoteItem['noteType'],
  content: string,
  options: Partial<NoteItem> = {}
): NoteItem {
  const now = Date.now();
  return {
    id,
    vaultId: 'default-vault',
    projectId: '',
    title,
    notebook,
    content,
    noteType: type,
    editorLevel: type === 'study' ? 'study' : type === 'markdown' ? 'pro' : 'simple',
    tags: [],
    properties: [],
    pinned: false,
    favorite: false,
    trashedAt: 0,
    createdAt: now - HOUR * 20,
    updatedAt: now - HOUR,
    path: '',
    ...options
  };
}

function prop(key: string, value: string): NoteProperty {
  return { key, value };
}

function mapNode(
  id: string,
  parentId: string,
  text: string,
  order: number,
  colorTag: MindMapNode['colorTag'],
  noteRefId = '',
  noteRefTitle = '',
  noteText = ''
): MindMapNode {
  return {
    id,
    parentId,
    text,
    note: noteText,
    noteRefId,
    noteRefTitle,
    order,
    collapsed: false,
    colorTag,
    level: 0,
    x: 0,
    y: 0,
    boxWidth: 136,
    boxHeight: 44,
    offsetX: 0,
    offsetY: 0
  };
}

export function defaultSettings(): AppSettings {
  return {
    theme: 'light',
    accent: DEFAULT_ACCENT,
    paletteMode: 'original',
    language: 'zh-Hans',
    fontSize: 16,
    showRibbon: true,
    sidebarWidth: 244,
    rightSidebarWidth: 280,
    showTabHeaders: true,
    editorLimitWidth: true,
    editorShowTitle: true,
    editorViewStatus: true,
    editorDefaultView: 'live',
    editorDefaultMode: 'live',
    zoom: 100,
    workspacePromptSuppressed: false,
    workspaceDefaultOpenMode: 'current',
    settingsUpdatedAt: 0,
    lastVaultId: 'default-vault',
    lastNoteId: '',
    hotkeys: {}
  };
}

/** A brand-new installation: one empty workspace and no notes/files. */
export function initialState(): PersistedState {
  const now = Date.now();
  return {
    version: 2,
    vaults: [
      {
        id: 'default-vault',
        name: '个人知识库',
        description: '',
        createdAt: now,
        archived: false,
        favorite: false,
        folderUri: '',
        openMode: 'ask'
      }
    ],
    projects: [],
    notes: [],
    maps: [],
    canvases: [],
    settings: defaultSettings()
  };
}

/** Demo fixture used by tests and documentation screenshots only. */
export function demoState(): PersistedState {
  const now = Date.now();
  const vaults: VaultItem[] = [
    {
      id: 'default-vault',
      name: '个人知识库',
      description: '日常灵感、大学课程笔记与个人知识网络',
      createdAt: now - HOUR * 24 * 7,
      archived: false,
      favorite: true,
      folderUri: '',
      openMode: 'ask'
    },
    {
      id: 'dev-vault',
      name: '开发项目库',
      description: 'HarmonyOS 架构设计与技术复盘文档',
      createdAt: now - HOUR * 24 * 3,
      archived: false,
      favorite: false,
      folderUri: '',
      openMode: 'ask'
    }
  ];

  const projects: LexiProject[] = [];

  const notes: NoteItem[] = [
    note(
      'note-algo-complexity',
      '时间复杂度',
      '计算机课程',
      'study',
      `
> [!NOTE] 核心定理
> 算法的时间复杂度衡量输入规模 $n$ 趋近无穷时，基本操作执行次数的增长率。

## 1. 主定理与递推公式

$$T(n) = aT(n/b) + f(n)$$

常见分治递归如归并排序满足 $a=2, b=2$，对应复杂度为 $O(n \\log n)$。

## 2. 与其他结构的关联

- 树形查找请结合 [[二叉树与递归遍历]] 一起复习
- 状态转移空间优化参见 [[动态规划核心模型]]
- 工程性能基线在 [[知萤 LexiNote 架构设计规范]] 中也有应用

## 3. 自测清单

- [x] 推导主定理三种情况
- [x] 整理常见排序算法最坏与平均复杂度
- [ ] 完成红黑树旋转摊还分析 #学习/算法`,
      {
        tags: ['学习/算法', '考试重点'],
        properties: [prop('课程', '数据结构与算法'), prop('章节', '第 1 章 渐近分析'), prop('掌握度', '熟练')],
        pinned: true,
        favorite: true,
        createdAt: now - HOUR * 36,
        updatedAt: now - HOUR * 2
      }
    ),
    note(
      'note-binary-tree',
      '二叉树与递归遍历',
      '计算机课程',
      'study',
      `
> [!TIP] 记忆线索
> 前序定根、中序分左右、后序自底向上汇总子树信息。

## 1. 遍历框架代码

\`\`\`typescript
function traverse(node: TreeNode | undefined): void {
  if (!node) return;
  // 前序位置
  traverse(node.left);
  // 中序位置
  traverse(node.right);
  // 后序位置
}
\`\`\`

## 2. 复杂度与拓展

每个节点恰好被访问常数次，整体满足 [[时间复杂度]] 中的线性阶 $O(n)$。当树退化为链表时，高度变为 $O(n)$。

子树最优解汇总可自然过渡到 [[动态规划核心模型]]（树形 DP）。`,
      {
        tags: ['学习/算法', '树结构'],
        properties: [prop('课程', '数据结构与算法'), prop('关联导图', '数据结构与算法体系')],
        favorite: true,
        createdAt: now - HOUR * 28,
        updatedAt: now - HOUR * 5
      }
    ),
    note(
      'note-dp-model',
      '动态规划核心模型',
      '计算机课程',
      'study',
      `
## 1. 状态转移三步法

1. 明确状态变量（如容量、前 $i$ 个元素）
2. 推导状态转移方程：

$$dp[i][w] = \\max(dp[i-1][w], dp[i-1][w-c_i] + v_i)$$

3. 利用滚动数组降低 [[时间复杂度]] 与空间开销。

## 2. 树形与图论结合

在树上进行状态转移时，必须先完成 [[二叉树与递归遍历]] 的后序收集。`,
      {
        tags: ['学习/算法', '动态规划'],
        properties: [prop('状态定义', '重叠子问题 + 最优子结构')],
        createdAt: now - HOUR * 20,
        updatedAt: now - HOUR * 8
      }
    ),
    note(
      'note-lexinote-arch',
      '知萤 LexiNote 架构设计规范',
      '产品与架构',
      'markdown',
      `
> 想记就记，需要时足够专业。让每一条笔记，成为可以连接、组织与重访的知识。

## 1. 核心一致性原则

- **不可变主键**：笔记以 UUID 标识，重命名标题时自动修复全文 [[双向链接]]，绝不断链。
- **文件优先 + RDB 索引**：正文保存为标准 Markdown，随时可导出迁移。
- **工具分层不割裂**：同一篇文档可在「简洁 / 学习 / 专业」三级工具间自由切换。

## 2. 算法与性能基线

大纲树与导图布局控制在目标 [[时间复杂度]] 之内，树形遍历采用 [[二叉树与递归遍历]] 的原子子树计算。

## 3. Windows 版本说明

Windows 版沿用同一套 Markdown 语法、双向链接与思维导图布局。鸿蒙的系统材质（沉浸光感、液态玻璃）在 Windows 上不可用，已统一替换为纯色与半透明普通材质；KaTeX 公式、代码块和标注在本地离线渲染。`,
      {
        tags: ['开发/鸿蒙', '知识管理'],
        properties: [prop('架构原则', '本地优先 · 文件为事实来源'), prop('视觉体系', '紫色 · 普通材质替代 HDS')],
        pinned: true,
        favorite: true,
        createdAt: now - HOUR * 14,
        updatedAt: now - HOUR
      }
    ),
    note(
      'note-quick-today',
      '今日灵感与待办速记',
      '速记收件箱',
      'quick',
      `
- [x] 用 10 秒快速记录把散落的课堂想法收拢到知萤
- [x] 把数据结构课程笔记连接到「数据结构与算法体系」思维导图
- [ ] 周五前复盘一次时间复杂度与动态规划核心模型

> 记下第一句话时不需要纠结分类，知识会在连接中自然生长。`,
      {
        tags: ['日常/灵感', '待办'],
        createdAt: now - HOUR * 4,
        updatedAt: now - HOUR * 0.5
      }
    ),
    note(
      'note-welcome-windows',
      '欢迎使用知萤 Windows 版',
      '速记收件箱',
      'markdown',
      `
这是知萤 HarmonyOS 项目的 Windows 桌面版本，保留同一套本地优先的笔记体验。

## 与鸿蒙版一致

- **Markdown 写作**：标题、列表、任务、引用、标注、表格、代码块与 \`$$…$$\` 公式。
- **知识连接**：\`[[双向链接]]\`、反向链接、关系图谱与思维导图。
- **工作区**：知识库、文件夹、收藏、搜索与回收站。
- **外观**：浅色 / 深色 / 跟随系统，六种主题色与自定义强调色。

## Windows 上的替换

| 鸿蒙能力 | Windows 实现 |
| --- | --- |
| HDS 沉浸光感材质 | 纯色与半透明普通材质 |
| 系统分享剪藏 | 导入 Markdown 文件 / 剪贴板 |
| 桌面服务卡片 | 托盘化窗口与快速新建（后续版本） |
| 离线语音识别 | 系统输入法语音输入 |

> 提示：按 **Ctrl+P** 打开命令面板，按 **Ctrl+O** 快速切换文档。

键盘快捷键在「设置 → 快捷键」中查看。`,
      {
        tags: ['使用说明'],
        favorite: true,
        createdAt: now - HOUR * 6,
        updatedAt: now - HOUR * 0.2
      }
    )
  ];

  const maps: MindMapDoc[] = [
    {
      id: 'map-ds-system',
      vaultId: 'default-vault',
      projectId: '',
      title: '数据结构与算法体系',
      layoutKind: 'right',
      rootNodeId: 'root',
      favorite: true,
      trashedAt: 0,
      createdAt: now - HOUR * 24,
      updatedAt: now - HOUR,
      nodes: [
        mapNode('root', '', '数据结构与算法体系', 0, 'purple', 'note-algo-complexity', '时间复杂度', '期末核心复习总纲'),
        mapNode('b1', 'root', '复杂度分析', 1, 'purple', 'note-algo-complexity', '时间复杂度', '渐近上界 O 与主定理'),
        mapNode('b1-1', 'b1', '大 O 渐近记号', 1, 'purple'),
        mapNode('b1-2', 'b1', 'Master 主定理', 2, 'purple'),
        mapNode('b2', 'root', '非线性树结构', 2, 'indigo', 'note-binary-tree', '二叉树与递归遍历', '递归序与平衡树'),
        mapNode('b2-1', 'b2', '前/中/后序递归框架', 1, 'indigo', 'note-binary-tree', '二叉树与递归遍历'),
        mapNode('b2-2', 'b2', '二叉搜索树与 AVL', 2, 'indigo'),
        mapNode('b3', 'root', '动态规划模型', 3, 'teal', 'note-dp-model', '动态规划核心模型', '状态定义与空间压缩'),
        mapNode('b3-1', 'b3', '背包与区间 DP', 1, 'teal'),
        mapNode('b3-2', 'b3', '树形 DP 状态汇总', 2, 'teal', 'note-dp-model', '动态规划核心模型')
      ]
    },
    {
      id: 'map-lexi-product',
      vaultId: 'default-vault',
      projectId: '',
      title: '知萤个人知识工作流',
      layoutKind: 'balanced',
      rootNodeId: 'root',
      favorite: false,
      trashedAt: 0,
      createdAt: now - HOUR * 12,
      updatedAt: now - HOUR * 3,
      nodes: [
        mapNode('root', '', '知萤知识工作流', 0, 'purple', 'note-lexinote-arch', '知萤 LexiNote 架构设计规范'),
        mapNode('p1', 'root', '1. 随手速记', 1, 'purple', 'note-quick-today', '今日灵感与待办速记', '10 秒无负担记录'),
        mapNode('p2', 'root', '2. 深度整理', 2, 'indigo', 'note-algo-complexity', '时间复杂度', '公式、高亮与代码块'),
        mapNode('p3', 'root', '3. 双链成网', 3, 'teal', 'note-binary-tree', '二叉树与递归遍历', '双向引用与局部图谱'),
        mapNode('p4', 'root', '4. 本地导出备份', 4, 'amber', '', '', 'Markdown 与 JSON 自由迁移')
      ]
    }
  ];

  const canvases: CanvasBoard[] = [
    {
      id: 'canvas-main',
      vaultId: 'default-vault',
      projectId: '',
      title: '算法与架构灵感白板',
      createdAt: now - HOUR * 10,
      updatedAt: now - HOUR * 2,
      cards: [
        {
          id: 'card-1',
          title: '渐近复杂度基石',
          content: '先明确输入规模 n，再衡量递归分治与状态空间。',
          noteRefId: 'note-algo-complexity',
          noteRefTitle: '时间复杂度',
          x: 44,
          y: 52,
          colorTag: 'purple'
        },
        {
          id: 'card-2',
          title: '递归子树思维',
          content: '把原问题拆解成左子树与右子树的信息汇总。',
          noteRefId: 'note-binary-tree',
          noteRefTitle: '二叉树与递归遍历',
          x: 392,
          y: 58,
          colorTag: 'indigo'
        },
        {
          id: 'card-3',
          title: '重叠子问题记忆化',
          content: '从递归树剪枝自然导出自底向上的状态转移表。',
          noteRefId: 'note-dp-model',
          noteRefTitle: '动态规划核心模型',
          x: 214,
          y: 268,
          colorTag: 'teal'
        }
      ],
      edges: [
        { id: 'edge-1', fromId: 'card-1', toId: 'card-2', label: '分治递推' },
        { id: 'edge-2', fromId: 'card-2', toId: 'card-3', label: '树形 DP' }
      ]
    }
  ];

  return {
    version: 2,
    vaults,
    projects,
    notes,
    maps,
    canvases,
    settings: defaultSettings()
  };
}
