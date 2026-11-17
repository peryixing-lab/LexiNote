'use strict';

const { clip, text, normalizePath, dirname, errorText, previewArguments, isObject } = require('./util');
const { findSkill, catalog } = require('./skills');
const { formatDiffText } = require('./diff');
const { loadChanges, stageProposal, applyProposal, describeProposal } = require('./changes');
const { lineRangeForOffsets, isPermissionError } = require('./context');

/**
 * Harness tool layer over the LexiNote plugin API.
 *
 * Every tool is a thin, explicit wrapper over `ctx.vault`, `ctx.workspace`, `ctx.editor`,
 * `ctx.mindmap`, `ctx.canvas`, `ctx.appSettings`, and `ctx.commands`.
 * Tools return a plain transcript record `{ title, subtitle, text, isError }`; they never
 * throw, because the model needs a readable failure message to recover in the next step.
 */

const MAX_LIST = 60;
const MAX_READ = 20000;
const MAX_SEARCH_READS = 36;

const TOOL_DEFINITIONS = [
  {
    name: 'get_workspace_status',
    description: '读取当前知识库、活动笔记、编辑器状态、笔记总数、思维导图总数、自由白板总数与软件外观概要。',
    parameters: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'list_notes',
    description: '列出知识库中的 Markdown 笔记，按修改时间倒序。可用 prefix 过滤目录。',
    parameters: {
      type: 'object',
      properties: {
        prefix: { type: 'string', description: '可选的路径前缀，例如 “课程” 或 “课程/第一课”' },
        limit: { type: 'number', description: '返回条数，默认 30，最大 60' }
      },
      required: []
    }
  },
  {
    name: 'search_notes',
    description: '按关键词搜索笔记标题与正文，返回最相关的笔记路径和片段。找关联笔记时使用。',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: '搜索关键词，可用空格分隔多个词' },
        limit: { type: 'number', description: '返回条数，默认 8，最大 20' }
      },
      required: ['query']
    }
  },
  {
    name: 'read_note',
    description: '读取一篇笔记的完整 Markdown（含 YAML frontmatter），过长会截断。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '知识库相对路径，例如 “课程/第一课.md”' }
      },
      required: ['path']
    }
  },
  {
    name: 'create_note',
    description: '直接在知识库中新建一篇 Markdown 笔记并立即生效（同时记录可撤销历史，默认创建后在工作区打开）。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '知识库相对路径，必须以 .md 结尾' },
        content: { type: 'string', description: '完整 Markdown 内容' },
        open: { type: 'boolean', description: '创建后是否立即在工作区打开，默认 true' },
        reason: { type: 'string', description: '新建说明（可选）' }
      },
      required: ['path', 'content']
    }
  },
  {
    name: 'update_note',
    description: '直接更新笔记内容并立即生效（传 content 整体替换，或传 find/replace 定点替换；同时保留可撤销记录）。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' },
        content: { type: 'string', description: '完整新内容；与 find/replace 二选一' },
        find: { type: 'string', description: '要查找的原文片段' },
        replace: { type: 'string', description: '替换后的文本' },
        replaceAll: { type: 'boolean', description: '是否替换所有匹配，默认 false' },
        reason: { type: 'string', description: '修改说明（可选）' }
      },
      required: ['path']
    }
  },
  {
    name: 'append_to_note',
    description: '直接在笔记末尾追加 Markdown 内容并立即生效（同时保留可撤销记录）。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' },
        markdown: { type: 'string', description: '要追加的 Markdown' },
        reason: { type: 'string', description: '追加说明（可选）' }
      },
      required: ['path', 'markdown']
    }
  },
  {
    name: 'rename_note',
    description: '直接重命名笔记（支持同目录改名，立即生效并支持撤销）。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '原路径' },
        newPath: { type: 'string', description: '新路径，目录必须与原路径相同' },
        reason: { type: 'string', description: '重命名原因（可选）' }
      },
      required: ['path', 'newPath']
    }
  },
  {
    name: 'delete_note',
    description: '直接将笔记移入回收站（软删除，立即生效并支持恢复撤销）。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' },
        reason: { type: 'string', description: '删除原因（可选）' }
      },
      required: ['path']
    }
  },
  {
    name: 'open_note',
    description: '在知萤工作区中打开一篇笔记。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' }
      },
      required: ['path']
    }
  },
  {
    name: 'replace_selection',
    description: '直接改写当前活动编辑器中用户选中的文本片段（立即生效并支持撤销）。',
    parameters: {
      type: 'object',
      properties: {
        content: { type: 'string', description: '替换当前选区的文本（也兼容 text 字段）' },
        text: { type: 'string', description: 'content 的别名' },
        reason: { type: 'string', description: '修改说明（可选）' }
      },
      required: []
    }
  },
  {
    name: 'replace_active_editor',
    description: '直接整体替换当前活动编辑器的内容（立即生效并支持撤销）。',
    parameters: {
      type: 'object',
      properties: {
        text: { type: 'string', description: '新的完整编辑器内容' },
        reason: { type: 'string', description: '修改说明（可选）' }
      },
      required: ['text']
    }
  },
  {
    name: 'list_mindmaps',
    description: '列出当前知识库中的所有思维导图（含 ID、标题、布局方向、节点数量）。',
    parameters: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'read_mindmap',
    description: '读取一张思维导图的完整节点树结构（可按 id 或 title 查询）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '思维导图 ID（与 title 二选一）' },
        title: { type: 'string', description: '思维导图标题（与 id 二选一）' }
      },
      required: []
    }
  },
  {
    name: 'create_mindmap',
    description: '直接创建一张思维导图并在知萤中打开。支持用 markdown 大纲（推荐，如 "# 核心主题\\n## 分支1\\n- 要点"）、嵌套 nodes 数组，或从现有笔记（fromNotePath）生成。',
    parameters: {
      type: 'object',
      properties: {
        title: { type: 'string', description: '思维导图标题' },
        layoutKind: { type: 'string', enum: ['right', 'both', 'down'], description: '布局方向：right（向右辐射，默认）、both（左右对称）、down（向下树图）' },
        markdown: { type: 'string', description: '用 Markdown 标题（# / ## / ###）或无序列表（- ）描述导图结构，宿主会自动解析为思维导图节点树' },
        nodes: {
          type: 'array',
          description: '可选：节点列表，支持嵌套树 [{ text: "中心主题", children: [{ text: "子分支" }] }] 或扁平节点 [{ id, parentId, text, note, colorTag }]',
          items: { type: 'object' }
        },
        fromNotePath: { type: 'string', description: '可选：根据指定 Markdown 笔记路径自动转换生成思维导图' },
        open: { type: 'boolean', description: '创建后是否立即在工作区打开该思维导图，默认 true' }
      },
      required: ['title']
    }
  },
  {
    name: 'update_mindmap',
    description: '直接修改现有思维导图的标题、布局方向或节点树结构（通过 id 或 title 指定目标导图）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '目标思维导图 ID（可与 title 二选一）' },
        title: { type: 'string', description: '目标思维导图标题（或新标题）' },
        newTitle: { type: 'string', description: '可选：要修改为的新标题' },
        layoutKind: { type: 'string', enum: ['right', 'both', 'down'], description: '可选：新的布局方向（right / both / down）' },
        markdown: { type: 'string', description: '可选：新的 Markdown 大纲结构，将更新导图节点' },
        nodes: { type: 'array', description: '可选：新的节点树或节点列表', items: { type: 'object' } },
        open: { type: 'boolean', description: '修改后是否在工作区打开，默认 true' }
      },
      required: []
    }
  },
  {
    name: 'delete_mindmap',
    description: '删除指定的思维导图（通过 id 或 title 指定）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '思维导图 ID' },
        title: { type: 'string', description: '思维导图标题' }
      },
      required: []
    }
  },
  {
    name: 'open_mindmap',
    description: '在知萤工作区中打开指定的思维导图（通过 id 或 title 指定）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '思维导图 ID' },
        title: { type: 'string', description: '思维导图标题' }
      },
      required: []
    }
  },
  {
    name: 'list_canvases',
    description: '列出当前知识库中的所有自由白板（Canvas，含 ID、标题、卡片数与连线数）。',
    parameters: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'read_canvas',
    description: '读取指定自由白板（Canvas）的卡片与连线详情（可按 id 或 title 查询）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '白板 ID' },
        title: { type: 'string', description: '白板标题' }
      },
      required: []
    }
  },
  {
    name: 'create_canvas',
    description: '直接创建一张自由白板（Canvas）并在知萤中打开，可同时创建多张卡片（cards）与连线（edges）。',
    parameters: {
      type: 'object',
      properties: {
        title: { type: 'string', description: '自由白板标题' },
        cards: {
          type: 'array',
          description: '卡片列表，每项形如 { id: "c1", title: "卡片标题", body: "卡片正文", colorTag: "purple|indigo|teal|amber|rose", x: 80, y: 100, width: 220, height: 140 }',
          items: { type: 'object' }
        },
        edges: {
          type: 'array',
          description: '卡片连线列表，每项形如 { fromCardId: "c1", toCardId: "c2", label: "关联说明" }',
          items: { type: 'object' }
        },
        open: { type: 'boolean', description: '创建后是否立即在工作区打开，默认 true' }
      },
      required: ['title']
    }
  },
  {
    name: 'update_canvas',
    description: '直接更新现有自由白板（Canvas）的标题、卡片列表或连线列表。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '目标白板 ID' },
        title: { type: 'string', description: '目标白板标题' },
        newTitle: { type: 'string', description: '可选：新标题' },
        cards: { type: 'array', description: '更新后的完整卡片列表', items: { type: 'object' } },
        edges: { type: 'array', description: '更新后的完整连线列表', items: { type: 'object' } },
        open: { type: 'boolean', description: '更新后是否打开，默认 true' }
      },
      required: []
    }
  },
  {
    name: 'delete_canvas',
    description: '删除指定的自由白板（通过 id 或 title 指定）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '白板 ID' },
        title: { type: 'string', description: '白板标题' }
      },
      required: []
    }
  },
  {
    name: 'open_canvas',
    description: '在知萤工作区中打开指定的自由白板（通过 id 或 title 指定）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '白板 ID' },
        title: { type: 'string', description: '白板标题' }
      },
      required: []
    }
  },
  {
    name: 'get_app_settings',
    description: '读取知萤（LexiNote）当前的全部软件设置（外观主题、强调色、正文字号、界面缩放、语言、编辑器视图与模式、可读行宽、显示标题、拼写检查、功能栏与标签栏显隐、侧边栏宽度等）。',
    parameters: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'update_app_settings',
    description: '直接修改知萤（LexiNote）的软件设置并立即生效。支持修改浅色/深色/跟随系统主题、强调色、正文字号、界面缩放、界面语言、编辑器默认视图/模式、行宽限制、拼写检查、左侧功能栏、标签栏及侧边栏宽度等。',
    parameters: {
      type: 'object',
      properties: {
        theme: { type: 'string', enum: ['light', 'dark', 'system'], description: '外观主题：light（浅色）、dark（深色）、system（跟随系统）' },
        language: { type: 'string', enum: ['zh-Hans', 'en'], description: '界面语言：zh-Hans（简体中文）或 en（English）' },
        defaultTier: { type: 'string', enum: ['simple', 'study', 'pro'], description: '默认工作区层级：simple（极简）、study（学习）、pro（专业）' },
        vaultViewMode: { type: 'string', enum: ['list', 'card', 'folder'], description: '笔记列表视图模式：list / card / folder' },
        graphShowTags: { type: 'boolean', description: '关系图谱是否显示标签节点' },
        workspaceOpenMode: { type: 'string', enum: ['ask', 'replace', 'split'], description: '打开文档方式：ask / replace / split' },
        accent: { type: 'string', description: '主题强调色（支持 #RRGGBB 或 purple / indigo / blue / teal / green / amber / rose）' },
        resetColors: { type: 'boolean', description: '是否重置为默认主题配色' },
        fontSize: { type: 'number', description: '编辑器正文字号（10 - 32）' },
        quickZoom: { type: 'boolean', description: '是否开启 Ctrl+滚轮快速缩放字号' },
        editorDefaultView: { type: 'string', enum: ['edit', 'preview'], description: '默认打开视图：edit（编辑视图）或 preview（阅读视图）' },
        editorDefaultMode: { type: 'string', enum: ['live', 'source'], description: '默认编辑模式：live（实时预览）或 source（源码模式）' },
        editorShowTitle: { type: 'boolean', description: '是否在笔记顶部显示内联标题' },
        editorLimitWidth: { type: 'boolean', description: '是否限制正文最大可读行宽' },
        editorViewStatus: { type: 'boolean', description: '是否显示编辑器底部状态栏' },
        editorSpellcheck: { type: 'boolean', description: '是否启用拼写检查' },
        interfaceTabHeaders: { type: 'boolean', description: '是否显示顶部标签页栏' },
        interfaceRibbon: { type: 'boolean', description: '是否显示最左侧功能图标栏（Ribbon）' },
        interfaceZoom: { type: 'number', description: '界面整体缩放比例（75 - 150，默认 100）' },
        interfaceSidebarWidth: { type: 'number', description: '左侧文件栏宽度（200 - 480）' },
        interfaceRightSidebarWidth: { type: 'number', description: '右侧面板宽度（232 - 560）' }
      },
      required: []
    }
  },
  {
    name: 'list_app_commands',
    description: '列出知萤宿主内置的所有全局软件命令（如打开今日日记、新建笔记/导图/白板、切换主题、调整字号等）。',
    parameters: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'run_app_command',
    description: '直接执行知萤宿主的内置软件命令（例如 id="daily" 打开今日笔记、id="dark" 切换深色外观、id="map" 新建思维导图、id="canvas" 新建白板等）。',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '要执行的宿主命令 ID，例如 daily、new、map、canvas、light、dark、system、theme-toggle、font-increase、font-decrease、zoom-in、zoom-out、zoom-reset、width-toggle、source-toggle、ribbon-toggle' },
        title: { type: 'string', description: '可选：新建笔记/导图/白板时的标题参数' }
      },
      required: ['id']
    }
  },
  {
    name: 'todo_write',
    description: '更新本次任务的待办清单，用于展示多步进度。不写入用户笔记。',
    parameters: {
      type: 'object',
      properties: {
        todos: {
          type: 'array',
          description: '待办列表',
          items: {
            type: 'object',
            properties: {
              content: { type: 'string' },
              status: { type: 'string', enum: ['pending', 'in_progress', 'completed'] }
            },
            required: ['content']
          }
        }
      },
      required: ['todos']
    }
  },
  {
    name: 'skill',
    description: `加载专项技能说明。可用技能：\n${catalog()}`,
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string', description: '技能名，例如 note-organizer' }
      },
      required: ['name']
    }
  }
];

const TOOL_NAMES = new Set(TOOL_DEFINITIONS.map((tool) => tool.name));

function result(title, subtitle, body, isError) {
  return {
    title: title || '',
    subtitle: subtitle || '',
    text: text(body),
    isError: isError === true
  };
}

function failure(name, message) {
  return result(name, '执行失败', `${name} 失败：${message}`, true);
}

function isValidPath(path) {
  return typeof path === 'string' && normalizePath(path).length > 0;
}

function tokenize(query) {
  const seen = new Set();
  const tokens = [];
  const raw = text(query).toLowerCase().split(/[\s,，。；;、/|]+/);
  for (const part of raw) {
    const value = part.trim();
    if (value.length === 0 || seen.has(value)) {
      continue;
    }
    seen.add(value);
    tokens.push(value);
    if (tokens.length >= 8) {
      break;
    }
  }
  return tokens;
}

function scoreOf(tokens, haystack) {
  if (tokens.length === 0) {
    return 0;
  }
  let score = 0;
  for (const token of tokens) {
    if (haystack.indexOf(token) >= 0) {
      score += 1;
    }
  }
  return score;
}

function snippetOf(content, tokens) {
  const lower = content.toLowerCase();
  let index = -1;
  for (const token of tokens) {
    const found = lower.indexOf(token);
    if (found >= 0 && (index < 0 || found < index)) {
      index = found;
    }
  }
  if (index < 0) {
    return content.slice(0, 160).replace(/\s+/g, ' ').trim();
  }
  const start = Math.max(0, index - 60);
  return content.slice(start, Math.min(content.length, index + 160)).replace(/\s+/g, ' ').trim();
}

function fileLine(ref) {
  return `- ${ref.path}（${Math.max(1, Math.round((ref.size || 0) / 1024))} KB，修改于 ${new Date(ref.mtime).toISOString().slice(0, 16).replace('T', ' ')}）`;
}

function recordNote(hooks, ref) {
  if (hooks && typeof hooks.recordNote === 'function' && ref && ref.path) {
    try { hooks.recordNote(ref); } catch (_error) {}
  }
}

function requireCapability(ctx, capability, toolName) {
  if (ctx && ctx.capabilities && typeof ctx.capabilities.has === 'function' && !ctx.capabilities.has(capability)) {
    return failure(
      toolName,
      `E_PERMISSION_DENIED: 缺少能力 ${capability}，宿主禁止该操作；请在插件设置中授予权限后再试`
    );
  }
  return null;
}

async function resolveChangesStore(ctx, hooks) {
  if (hooks && hooks.changesStore && Array.isArray(hooks.changesStore.proposals)) {
    return hooks.changesStore;
  }
  const store = await loadChanges(ctx);
  if (hooks && typeof hooks === 'object') {
    hooks.changesStore = store;
  }
  return store;
}

function stagedOutcome(proposal, hooks) {
  if (hooks && typeof hooks.onProposal === 'function') {
    try { hooks.onProposal(proposal); } catch (_error) {}
  }
  const desc = describeProposal(proposal);
  const diffPreview = proposal.kind === 'rename_note'
    ? `- ${proposal.oldPath}\n+ ${proposal.newPath}`
    : formatDiffText(proposal.beforeContent, proposal.afterContent, 48);
  return result(
    `待确认 · ${desc.title}`,
    `${desc.targetLabel} · ${desc.statsLabel}`,
    [
      `已生成修改建议（${proposal.id}），原文尚未被修改。`,
      `类型：${desc.title}（${desc.statsLabel}）`,
      proposal.reason ? `说明：${proposal.reason}` : '',
      '请提示用户在界面下方的 Diff 差异卡片中核对并点击“确认写入/确认删除”，生效后仍支持撤销。',
      '',
      '```diff',
      diffPreview,
      '```'
    ].filter(Boolean).join('\n'),
    false
  );
}

function appliedOutcome(proposal, hooks) {
  if (hooks && typeof hooks.onProposal === 'function') {
    try { hooks.onProposal(proposal); } catch (_error) {}
  }
  const desc = describeProposal(proposal);
  const diffPreview = proposal.kind === 'rename_note'
    ? `- ${proposal.oldPath}\n+ ${proposal.newPath}`
    : formatDiffText(proposal.beforeContent, proposal.afterContent, 48);
  return result(
    `已完成 · ${desc.title}`,
    `${desc.targetLabel} · ${desc.statsLabel}`,
    [
      `已直接执行${desc.title}（${proposal.id}）：${desc.targetLabel}（${desc.statsLabel}），更改已生效。`,
      proposal.reason ? `说明：${proposal.reason}` : '',
      '用户也可在对话下方的变更卡片中随时点击“撤销本次写入”恢复原状。',
      '',
      '```diff',
      diffPreview,
      '```'
    ].filter(Boolean).join('\n'),
    false
  );
}

async function executeMutation(ctx, hooks, spec) {
  const store = await resolveChangesStore(ctx, hooks);
  if (hooks && hooks.stageOnly === true) {
    const staged = await stageProposal(ctx, store, spec);
    return stagedOutcome(staged, hooks);
  }
  const applied = await applyProposal(ctx, store, spec);
  if (spec.kind === 'create_note' && spec.open !== false && ctx.workspace && typeof ctx.workspace.openFile === 'function') {
    try {
      if (!ctx.capabilities || typeof ctx.capabilities.has !== 'function' || ctx.capabilities.has('workspace.views')) {
        const createdRef = await ctx.vault.get(spec.path);
        if (createdRef) {
          recordNote(hooks, createdRef);
          await ctx.workspace.openFile(createdRef);
        }
      }
    } catch (_error) {}
  }
  return appliedOutcome(applied, hooks);
}

async function getWorkspaceStatus(ctx, hooks) {
  const files = await ctx.vault.listMarkdown();
  let activePath = '';
  try {
    const active = await ctx.workspace.activeFile();
    if (active && active.path) {
      activePath = active.path;
      recordNote(hooks, active);
    }
  } catch (error) {
    activePath = isPermissionError(error) ? `受限（${errorText(error)}）` : '';
  }
  let editorLine = '没有打开编辑器';
  try {
    const snapshot = await ctx.editor.active();
    if (snapshot) {
      const content = typeof snapshot.content === 'string' ? snapshot.content : '';
      const sel = snapshot.selection && typeof snapshot.selection === 'object' ? snapshot.selection : null;
      const from = sel ? Math.max(0, Math.min(content.length, Math.floor(Number(sel.from) || 0))) : 0;
      const to = sel ? Math.max(from, Math.min(content.length, Math.floor(Number(sel.to) || from))) : 0;
      let selLabel = '';
      if (to > from) {
        const range = lineRangeForOffsets(content, from, to);
        selLabel = `，已选中 ${to - from} 字符 (L${range.startLine}-L${range.endLine})`;
      }
      const modeLabel = snapshot.readOnly ? '，只读模式' : '';
      editorLine = `${snapshot.noteId || 'active'}（${content.length} 字符${snapshot.dirty ? '，有未保存改动' : ''}${modeLabel}${selLabel}）`;
    }
  } catch (error) {
    editorLine = isPermissionError(error) ? `无权读取（${errorText(error)}）` : '无法读取编辑器';
  }

  const lines = [
    `知识库：${ctx.vaultId || '当前知识库'}`,
    `笔记总数：${files.length}`,
    `活动笔记：${activePath || '无'}`,
    `活动编辑器：${editorLine}`
  ];

  if (ctx.mindmap && typeof ctx.mindmap.list === 'function') {
    try {
      const maps = await ctx.mindmap.list();
      if (Array.isArray(maps)) {
        const preview = maps.slice(0, 5).map((m) => m.title || m.id).join('、');
        lines.push(`思维导图总数：${maps.length}${preview ? `（最近：${preview}）` : ''}`);
      }
    } catch (_error) {}
  }

  if (ctx.canvas && typeof ctx.canvas.list === 'function') {
    try {
      const boards = await ctx.canvas.list();
      if (Array.isArray(boards)) {
        const preview = boards.slice(0, 5).map((b) => b.title || b.id).join('、');
        lines.push(`自由白板总数：${boards.length}${preview ? `（最近：${preview}）` : ''}`);
      }
    } catch (_error) {}
  }

  if (ctx.appSettings && typeof ctx.appSettings.get === 'function') {
    try {
      const s = await ctx.appSettings.get();
      if (s && typeof s === 'object') {
        const fontSize = s.appearance && s.appearance.fontSize ? `${s.appearance.fontSize}px` : '默认';
        const zoom = s.interface && s.interface.zoom ? `${s.interface.zoom}%` : '100%';
        lines.push(`软件设置概要：主题=${s.theme || 'system'}，语言=${s.language || 'zh-Hans'}，字号=${fontSize}，缩放=${zoom}`);
      }
    } catch (_error) {}
  }

  return result('工作区状态', `${files.length} 篇笔记`, lines.join('\n'), false);
}

async function listNotes(ctx, args) {
  const prefix = normalizePath(args.prefix || '');
  const limit = Math.max(1, Math.min(MAX_LIST, Number(args.limit) || 30));
  const files = await ctx.vault.listMarkdown();
  const filtered = files
    .filter((file) => prefix.length === 0 || file.path === prefix || file.path.startsWith(`${prefix}/`))
    .sort((left, right) => (right.mtime || 0) - (left.mtime || 0));
  if (filtered.length === 0) {
    return result('列出笔记', '0 篇', prefix.length > 0 ? `没有找到前缀为 “${prefix}” 的笔记。` : '知识库里还没有 Markdown 笔记。', false);
  }
  const lines = filtered.slice(0, limit).map(fileLine);
  return result('列出笔记', `${filtered.length} 篇匹配，显示 ${Math.min(limit, filtered.length)} 篇`,
    lines.join('\n'), false);
}

async function searchNotes(ctx, args, hooks) {
  const query = text(args.query).trim();
  if (query.length === 0) {
    return failure('search_notes', '缺少 query');
  }
  const limit = Math.max(1, Math.min(20, Number(args.limit) || 8));
  const tokens = tokenize(query);
  const files = await ctx.vault.listMarkdown();
  const ranked = files
    .map((file) => ({ file, pathScore: scoreOf(tokens, file.path.toLowerCase()) }))
    .sort((left, right) => {
      if (right.pathScore !== left.pathScore) { return right.pathScore - left.pathScore; }
      return (right.file.mtime || 0) - (left.file.mtime || 0);
    });
  const candidates = ranked.slice(0, MAX_SEARCH_READS);
  const hits = [];
  for (const candidate of candidates) {
    let content = '';
    try {
      content = await ctx.vault.read(candidate.file);
    } catch (error) {
      continue;
    }
    const contentScore = scoreOf(tokens, content.toLowerCase());
    const score = candidate.pathScore * 3 + contentScore;
    if (score <= 0) {
      continue;
    }
    recordNote(hooks, candidate.file);
    hits.push({
      path: candidate.file.path,
      score,
      snippet: snippetOf(content, tokens)
    });
  }
  hits.sort((left, right) => right.score - left.score);
  if (hits.length === 0) {
    return result('搜索笔记', '0 篇匹配', `没有找到与 “${query}” 相关的笔记。`, false);
  }
  const lines = hits.slice(0, limit).map((hit) => `- ${hit.path}\n  > ${hit.snippet}`);
  return result('搜索笔记', `${hits.length} 篇匹配`, lines.join('\n'), false);
}

async function readNote(ctx, args, hooks) {
  if (!isValidPath(args.path)) {
    return failure('read_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('read_note', `笔记不存在：${path}`);
  }
  recordNote(hooks, file);
  const content = await ctx.vault.read(file);
  const body = clip(content, MAX_READ);
  return result('读取笔记', `${path} · ${content.length} 字符`, `# ${path}\n\n${body}`, false);
}

async function createNote(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'vault.write', 'create_note');
  if (denied) { return denied; }
  if (!isValidPath(args.path)) {
    return failure('create_note', '缺少 path');
  }
  let path = normalizePath(args.path);
  if (!/\.markdown$|\.md$/i.test(path)) {
    path = `${path}.md`;
  }
  if (typeof args.content !== 'string') {
    return failure('create_note', '缺少 content');
  }
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'create_note',
      path,
      content: args.content,
      open: args.open !== false,
      reason: args.reason
    });
  } catch (error) {
    return failure('create_note', errorText(error));
  }
}

async function updateNote(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'vault.write', 'update_note');
  if (denied) { return denied; }
  if (!isValidPath(args.path)) {
    return failure('update_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('update_note', `笔记不存在：${path}`);
  }
  recordNote(hooks, file);
  let current = '';
  try {
    current = await ctx.vault.read(file);
    if (ctx.editor && typeof ctx.editor.active === 'function') {
      const live = await ctx.editor.active().catch(() => null);
      if (live && live.noteId === file.id && live.dirty && typeof live.content === 'string') {
        current = live.content;
      }
    }
  } catch (error) {
    return failure('update_note', errorText(error));
  }
  let next = '';
  if (typeof args.content === 'string') {
    next = args.content;
  } else if (typeof args.find === 'string' && args.find.length > 0 && typeof args.replace === 'string') {
    if (current.indexOf(args.find) < 0) {
      return failure('update_note', '没有找到要替换的原文片段，请先 read_note 确认内容');
    }
    next = args.replaceAll === true
      ? current.split(args.find).join(args.replace)
      : current.replace(args.find, args.replace);
  } else {
    return failure('update_note', '需要 content，或同时提供 find 与 replace');
  }
  if (next === current) {
    return result('更新笔记', path, '内容没有变化，无需修改。', false);
  }
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'update_note',
      path,
      content: next,
      reason: args.reason
    });
  } catch (error) {
    return failure('update_note', errorText(error));
  }
}

async function appendToNote(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'vault.write', 'append_to_note');
  if (denied) { return denied; }
  if (!isValidPath(args.path)) {
    return failure('append_to_note', '缺少 path');
  }
  const markdown = typeof args.markdown === 'string'
    ? args.markdown
    : (typeof args.content === 'string' ? args.content : '');
  if (markdown.length === 0) {
    return failure('append_to_note', '缺少 markdown');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('append_to_note', `笔记不存在：${path}`);
  }
  recordNote(hooks, file);
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'append_to_note',
      path,
      content: markdown,
      reason: args.reason
    });
  } catch (error) {
    return failure('append_to_note', errorText(error));
  }
}

async function renameNote(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'vault.write', 'rename_note');
  if (denied) { return denied; }
  if (!isValidPath(args.path) || !isValidPath(args.newPath)) {
    return failure('rename_note', '需要 path 与 newPath');
  }
  const path = normalizePath(args.path);
  const newPath = normalizePath(args.newPath);
  if (dirname(path) !== dirname(newPath)) {
    return failure('rename_note', 'v1 只支持同一目录内改名；跨目录请新建后删除原文件');
  }
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'rename_note',
      path,
      newPath,
      reason: args.reason
    });
  } catch (error) {
    return failure('rename_note', errorText(error));
  }
}

async function deleteNote(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'vault.write', 'delete_note');
  if (denied) { return denied; }
  if (!isValidPath(args.path)) {
    return failure('delete_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('delete_note', `笔记不存在：${path}`);
  }
  recordNote(hooks, file);
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'delete_note',
      path,
      reason: args.reason
    });
  } catch (error) {
    return failure('delete_note', errorText(error));
  }
}

async function openNote(ctx, args, hooks) {
  if (!isValidPath(args.path)) {
    return failure('open_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('open_note', `笔记不存在：${path}`);
  }
  recordNote(hooks, file);
  try {
    await ctx.workspace.openFile(file);
    return result('打开笔记', path, `已在知萤中打开 ${path}。`, false);
  } catch (error) {
    return failure('open_note', errorText(error));
  }
}

async function replaceSelection(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'editor.write', 'replace_selection');
  if (denied) { return denied; }
  const replacement = typeof args.content === 'string'
    ? args.content
    : (typeof args.text === 'string' ? args.text : null);
  if (replacement === null) {
    return failure('replace_selection', '缺少 content');
  }
  try {
    const snapshot = await ctx.editor.active();
    if (!snapshot) {
      return failure('replace_selection', '当前没有活动编辑器，无法替换选区');
    }
    if (snapshot.readOnly) {
      return failure('replace_selection', 'E_EDITOR_READONLY: 当前处于只读视图，请切换到编辑模式后再试');
    }
    const liveSel = snapshot.selection && typeof snapshot.selection === 'object' ? snapshot.selection : null;
    const hasLiveSel = liveSel && Number(liveSel.to) > Number(liveSel.from);
    let fallbackSelection = null;
    let pathHint = '';
    const ctxNotes = hooks && hooks.contextResult && hooks.contextResult.ok && Array.isArray(hooks.contextResult.notes)
      ? hooks.contextResult.notes
      : [];
    if (ctxNotes.length > 0) {
      const first = ctxNotes[0];
      if (first && first.path && (!snapshot.noteId || !first.id || first.id === snapshot.noteId)) {
        pathHint = first.path;
        if (!hasLiveSel && hooks.contextResult.scope === 'selection' && typeof first.from === 'number' && typeof first.to === 'number' && first.to > first.from) {
          const content = typeof snapshot.content === 'string' ? snapshot.content : '';
          if (content.slice(first.from, first.to) === first.selectedText) {
            fallbackSelection = { from: first.from, to: first.to };
          }
        }
      }
    }
    return await executeMutation(ctx, hooks, {
      kind: 'replace_selection',
      path: pathHint,
      content: replacement,
      selection: fallbackSelection,
      reason: args.reason
    });
  } catch (error) {
    return failure('replace_selection', errorText(error));
  }
}

async function replaceActiveEditor(ctx, args, hooks) {
  const denied = requireCapability(ctx, 'editor.write', 'replace_active_editor');
  if (denied) { return denied; }
  const nextText = typeof args.text === 'string'
    ? args.text
    : (typeof args.content === 'string' ? args.content : null);
  if (nextText === null) {
    return failure('replace_active_editor', '缺少 text');
  }
  try {
    return await executeMutation(ctx, hooks, {
      kind: 'replace_active_editor',
      content: nextText,
      reason: args.reason
    });
  } catch (error) {
    return failure('replace_active_editor', errorText(error));
  }
}

function normalizeMindMapLayout(raw) {
  const val = text(raw).trim().toLowerCase();
  if (val === 'both' || val === 'balanced' || val === 'center') { return 'both'; }
  if (val === 'down' || val === 'tree' || val === 'org' || val === 'vertical') { return 'down'; }
  return 'right';
}

function formatMindMapOutline(doc) {
  if (!doc || typeof doc !== 'object') { return ''; }
  const nodes = Array.isArray(doc.nodes) ? doc.nodes : [];
  const childrenByParent = new Map();
  for (let i = 0; i < nodes.length; i += 1) {
    const n = nodes[i];
    if (!n || typeof n !== 'object') { continue; }
    const pid = text(n.parentId);
    if (!childrenByParent.has(pid)) { childrenByParent.set(pid, []); }
    childrenByParent.get(pid).push(n);
  }
  const lines = [
    `# 思维导图：${doc.title || '未命名'}`,
    `- ID：${doc.id}`,
    `- 布局方向：${doc.layoutKind || 'right'}`,
    `- 节点数量：${nodes.length}`,
    ''
  ];
  const visited = new Set();
  function walk(parentId, depth) {
    const list = childrenByParent.get(parentId) || [];
    for (let i = 0; i < list.length; i += 1) {
      const item = list[i];
      if (!item || visited.has(item.id)) { continue; }
      visited.add(item.id);
      const indent = '  '.repeat(depth);
      const noteSuffix = item.note ? ` — 备注：${item.note}` : '';
      lines.push(`${indent}- ${item.text || '节点'} (id: ${item.id})${noteSuffix}`);
      walk(item.id, depth + 1);
    }
  }
  walk('', 0);
  if (visited.size === 0 && nodes.length > 0) {
    for (let i = 0; i < nodes.length; i += 1) {
      lines.push(`- ${nodes[i].text || '节点'} (id: ${nodes[i].id})`);
    }
  }
  return lines.join('\n');
}

async function resolveMindMapDoc(ctx, args) {
  const id = text(args.id || args.mapId).trim();
  const title = text(args.title).trim();
  if (!id && !title) { return null; }
  return ctx.mindmap.get({ id, title });
}

async function listMindMaps(ctx) {
  const denied = requireCapability(ctx, 'vault.read', 'list_mindmaps');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.list !== 'function') {
    return failure('list_mindmaps', '当前宿主不支持思维导图接口');
  }
  const maps = await ctx.mindmap.list();
  if (!Array.isArray(maps) || maps.length === 0) {
    return result('列出思维导图', '0 张', '当前知识库中还没有思维导图。可使用 create_mindmap 创建。', false);
  }
  const lines = maps.map((m) => {
    const count = Array.isArray(m.nodes) ? m.nodes.length : (Number(m.nodeCount) || 0);
    return `- ${m.title || '未命名思维导图'}（id: ${m.id}，布局: ${m.layoutKind || 'right'}，${count} 个节点）`;
  });
  return result('列出思维导图', `${maps.length} 张思维导图`, lines.join('\n'), false);
}

async function readMindMap(ctx, args) {
  const denied = requireCapability(ctx, 'vault.read', 'read_mindmap');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.get !== 'function') {
    return failure('read_mindmap', '当前宿主不支持思维导图接口');
  }
  const doc = await resolveMindMapDoc(ctx, args);
  if (!doc) {
    return failure('read_mindmap', `找不到思维导图：${args.id || args.title || '(未提供 id 或 title)'}`);
  }
  const nodes = Array.isArray(doc.nodes) ? doc.nodes : [];
  return result('读取思维导图', `${doc.title} · ${nodes.length} 个节点`, formatMindMapOutline(doc), false);
}

async function createMindMap(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'create_mindmap');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.create !== 'function') {
    return failure('create_mindmap', '当前宿主不支持思维导图接口');
  }
  const title = text(args.title).trim() || '新建思维导图';
  const layoutKind = normalizeMindMapLayout(args.layoutKind);
  let fromNoteId = text(args.fromNoteId).trim();
  if (!fromNoteId && isValidPath(args.fromNotePath)) {
    const noteRef = await ctx.vault.get(normalizePath(args.fromNotePath));
    if (!noteRef) {
      return failure('create_mindmap', `找不到来源笔记：${normalizePath(args.fromNotePath)}`);
    }
    fromNoteId = noteRef.id;
  }
  const created = await ctx.mindmap.create({
    title,
    layoutKind,
    markdown: typeof args.markdown === 'string' ? args.markdown : '',
    nodes: Array.isArray(args.nodes) ? args.nodes : [],
    fromNoteId,
    open: args.open !== false
  });
  const nodeCount = created && Array.isArray(created.nodes) ? created.nodes.length : 1;
  return result(
    '创建思维导图',
    `${created.title} · ${nodeCount} 个节点`,
    `已创建思维导图「${created.title}」（id: ${created.id}）${args.open !== false ? '并在工作区中打开' : ''}。\n\n${formatMindMapOutline(created)}`,
    false
  );
}

async function updateMindMap(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'update_mindmap');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.update !== 'function') {
    return failure('update_mindmap', '当前宿主不支持思维导图接口');
  }
  let targetId = text(args.id || args.mapId).trim();
  if (!targetId && text(args.title).trim()) {
    const found = await ctx.mindmap.get({ title: text(args.title).trim() });
    if (found && found.id) { targetId = found.id; }
  }
  if (!targetId) {
    return failure('update_mindmap', '请提供有效的思维导图 id 或已存在的 title');
  }
  const payload = {
    id: targetId,
    open: args.open !== false
  };
  if (typeof args.newTitle === 'string' && args.newTitle.trim()) {
    payload.title = args.newTitle.trim();
  } else if (typeof args.title === 'string' && args.title.trim() && (args.id || args.mapId)) {
    payload.title = args.title.trim();
  }
  if (typeof args.layoutKind === 'string' && args.layoutKind.trim()) {
    payload.layoutKind = normalizeMindMapLayout(args.layoutKind);
  }
  if (typeof args.markdown === 'string' && args.markdown.trim()) {
    payload.markdown = args.markdown;
  }
  if (Array.isArray(args.nodes) && args.nodes.length > 0) {
    payload.nodes = args.nodes;
  }
  const updated = await ctx.mindmap.update(payload);
  const nodeCount = updated && Array.isArray(updated.nodes) ? updated.nodes.length : 0;
  return result(
    '更新思维导图',
    `${updated.title} · ${nodeCount} 个节点`,
    `已更新思维导图「${updated.title}」（id: ${updated.id}）。\n\n${formatMindMapOutline(updated)}`,
    false
  );
}

async function deleteMindMap(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'delete_mindmap');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.delete !== 'function') {
    return failure('delete_mindmap', '当前宿主不支持思维导图接口');
  }
  const doc = await resolveMindMapDoc(ctx, args);
  if (!doc || !doc.id) {
    return failure('delete_mindmap', `找不到要删除的思维导图：${args.id || args.title || ''}`);
  }
  await ctx.mindmap.delete(doc.id);
  return result('删除思维导图', doc.title || doc.id, `已删除思维导图「${doc.title || doc.id}」（id: ${doc.id}）。`, false);
}

async function openMindMap(ctx, args) {
  const denied = requireCapability(ctx, 'workspace.views', 'open_mindmap');
  if (denied) { return denied; }
  if (!ctx.mindmap || typeof ctx.mindmap.open !== 'function') {
    return failure('open_mindmap', '当前宿主不支持思维导图接口');
  }
  const doc = await resolveMindMapDoc(ctx, args);
  if (!doc || !doc.id) {
    return failure('open_mindmap', `找不到思维导图：${args.id || args.title || ''}`);
  }
  await ctx.mindmap.open(doc.id);
  return result('打开思维导图', doc.title || doc.id, `已在知萤工作区中打开思维导图「${doc.title || doc.id}」。`, false);
}

function formatCanvasSummary(board) {
  if (!board || typeof board !== 'object') { return ''; }
  const cards = Array.isArray(board.cards) ? board.cards : [];
  const edges = Array.isArray(board.edges) ? board.edges : [];
  const lines = [
    `# 自由白板：${board.title || '未命名白板'}`,
    `- ID：${board.id}`,
    `- 卡片数：${cards.length}，连线数：${edges.length}`,
    ''
  ];
  if (cards.length > 0) {
    lines.push('## 卡片');
    for (let i = 0; i < cards.length; i += 1) {
      const c = cards[i];
      const textBody = c.content || c.body || '';
      lines.push(`- [${c.id}] **${c.title || '未命名卡片'}** (${c.colorTag || 'purple'}, x=${c.x || 0}, y=${c.y || 0})${textBody ? `：${String(textBody).replace(/\s+/g, ' ').slice(0, 120)}` : ''}`);
    }
  }
  if (edges.length > 0) {
    lines.push('', '## 连线');
    for (let i = 0; i < edges.length; i += 1) {
      const e = edges[i];
      const from = e.fromId || e.fromCardId || '';
      const to = e.toId || e.toCardId || '';
      lines.push(`- ${from} -> ${to}${e.label ? ` (${e.label})` : ''}`);
    }
  }
  return lines.join('\n');
}

async function resolveCanvasBoard(ctx, args) {
  const id = text(args.id || args.canvasId).trim();
  const title = text(args.title).trim();
  if (!id && !title) { return null; }
  return ctx.canvas.get({ id, title });
}

async function listCanvases(ctx) {
  const denied = requireCapability(ctx, 'vault.read', 'list_canvases');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.list !== 'function') {
    return failure('list_canvases', '当前宿主不支持自由白板接口');
  }
  const boards = await ctx.canvas.list();
  if (!Array.isArray(boards) || boards.length === 0) {
    return result('列出自由白板', '0 张', '当前知识库中还没有自由白板。可使用 create_canvas 创建。', false);
  }
  const lines = boards.map((b) => {
    const cardCount = Array.isArray(b.cards) ? b.cards.length : 0;
    const edgeCount = Array.isArray(b.edges) ? b.edges.length : 0;
    return `- ${b.title || '未命名白板'}（id: ${b.id}，${cardCount} 张卡片，${edgeCount} 条连线）`;
  });
  return result('列出自由白板', `${boards.length} 张自由白板`, lines.join('\n'), false);
}

async function readCanvas(ctx, args) {
  const denied = requireCapability(ctx, 'vault.read', 'read_canvas');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.get !== 'function') {
    return failure('read_canvas', '当前宿主不支持自由白板接口');
  }
  const board = await resolveCanvasBoard(ctx, args);
  if (!board) {
    return failure('read_canvas', `找不到自由白板：${args.id || args.title || '(未提供 id 或 title)'}`);
  }
  const cardCount = Array.isArray(board.cards) ? board.cards.length : 0;
  return result('读取自由白板', `${board.title} · ${cardCount} 张卡片`, formatCanvasSummary(board), false);
}

async function createCanvas(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'create_canvas');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.create !== 'function') {
    return failure('create_canvas', '当前宿主不支持自由白板接口');
  }
  const title = text(args.title).trim() || '新建自由白板';
  const created = await ctx.canvas.create({
    title,
    cards: Array.isArray(args.cards) ? args.cards : [],
    edges: Array.isArray(args.edges) ? args.edges : [],
    open: args.open !== false
  });
  const cardCount = created && Array.isArray(created.cards) ? created.cards.length : 0;
  return result(
    '创建自由白板',
    `${created.title} · ${cardCount} 张卡片`,
    `已创建自由白板「${created.title}」（id: ${created.id}）${args.open !== false ? '并在工作区中打开' : ''}。\n\n${formatCanvasSummary(created)}`,
    false
  );
}

async function updateCanvas(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'update_canvas');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.update !== 'function') {
    return failure('update_canvas', '当前宿主不支持自由白板接口');
  }
  let targetId = text(args.id || args.canvasId).trim();
  if (!targetId && text(args.title).trim()) {
    const found = await ctx.canvas.get({ title: text(args.title).trim() });
    if (found && found.id) { targetId = found.id; }
  }
  if (!targetId) {
    return failure('update_canvas', '请提供有效的自由白板 id 或已存在的 title');
  }
  const payload = {
    id: targetId,
    open: args.open !== false
  };
  if (typeof args.newTitle === 'string' && args.newTitle.trim()) {
    payload.title = args.newTitle.trim();
  } else if (typeof args.title === 'string' && args.title.trim() && (args.id || args.canvasId)) {
    payload.title = args.title.trim();
  }
  if (Array.isArray(args.cards)) { payload.cards = args.cards; }
  if (Array.isArray(args.edges)) { payload.edges = args.edges; }
  const updated = await ctx.canvas.update(payload);
  const cardCount = updated && Array.isArray(updated.cards) ? updated.cards.length : 0;
  return result(
    '更新自由白板',
    `${updated.title} · ${cardCount} 张卡片`,
    `已更新自由白板「${updated.title}」（id: ${updated.id}）。\n\n${formatCanvasSummary(updated)}`,
    false
  );
}

async function deleteCanvas(ctx, args) {
  const denied = requireCapability(ctx, 'vault.write', 'delete_canvas');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.delete !== 'function') {
    return failure('delete_canvas', '当前宿主不支持自由白板接口');
  }
  const board = await resolveCanvasBoard(ctx, args);
  if (!board || !board.id) {
    return failure('delete_canvas', `找不到要删除的自由白板：${args.id || args.title || ''}`);
  }
  await ctx.canvas.delete(board.id);
  return result('删除自由白板', board.title || board.id, `已删除自由白板「${board.title || board.id}」（id: ${board.id}）。`, false);
}

async function openCanvas(ctx, args) {
  const denied = requireCapability(ctx, 'workspace.views', 'open_canvas');
  if (denied) { return denied; }
  if (!ctx.canvas || typeof ctx.canvas.open !== 'function') {
    return failure('open_canvas', '当前宿主不支持自由白板接口');
  }
  const board = await resolveCanvasBoard(ctx, args);
  if (!board || !board.id) {
    return failure('open_canvas', `找不到自由白板：${args.id || args.title || ''}`);
  }
  await ctx.canvas.open(board.id);
  return result('打开自由白板', board.title || board.id, `已在知萤工作区中打开自由白板「${board.title || board.id}」。`, false);
}

function formatSettingsSummary(s) {
  if (!isObject(s)) { return JSON.stringify(s || {}); }
  const app = isObject(s.appearance) ? s.appearance : {};
  const ed = isObject(s.editor) ? s.editor : {};
  const iface = isObject(s.interface) ? s.interface : {};
  return [
    '### 外观与通用',
    `- 外观主题 (theme)：${s.theme || 'system'}`,
    `- 界面语言 (language)：${s.language || 'zh-Hans'}`,
    `- 主题强调色 (accent)：${app.accent || '#6C5CE7'}`,
    `- 正文字号 (fontSize)：${app.fontSize || 16}px`,
    `- 快速滚轮缩放 (quickZoom)：${Boolean(app.quickZoom)}`,
    `- 默认界面层级 (defaultTier)：${s.defaultTier || 'simple'}`,
    `- 笔记列表视图 (vaultViewMode)：${s.vaultViewMode || 'list'}`,
    `- 图谱显示标签 (graphShowTags)：${Boolean(s.graphShowTags)}`,
    `- 打开文档方式 (workspaceOpenMode)：${s.workspaceOpenMode || 'ask'}`,
    '',
    '### 编辑器设置',
    `- 默认打开视图 (editorDefaultView)：${ed.defaultView || 'edit'}`,
    `- 默认编辑模式 (editorDefaultMode)：${ed.defaultMode || 'live'}`,
    `- 显示内联标题 (editorShowTitle)：${ed.showTitle !== false}`,
    `- 限制可读行宽 (editorLimitWidth)：${ed.limitWidth !== false}`,
    `- 显示状态栏 (editorViewStatus)：${ed.viewStatus !== false}`,
    `- 拼写检查 (editorSpellcheck)：${Boolean(ed.spellcheck)}`,
    '',
    '### 界面与布局',
    `- 界面缩放 (interfaceZoom)：${iface.zoom || 100}%`,
    `- 显示标签页栏 (interfaceTabHeaders)：${iface.tabHeaders !== false}`,
    `- 显示左侧功能栏 (interfaceRibbon)：${iface.showRibbon !== false}`,
    `- 左侧边栏宽度 (interfaceSidebarWidth)：${iface.sidebarWidth || 244}px`,
    `- 右侧边栏宽度 (interfaceRightSidebarWidth)：${iface.rightSidebarWidth || 280}px`
  ].join('\n');
}

function normalizeSettingsPatch(args) {
  const patch = {};
  if (typeof args.theme === 'string') {
    const raw = args.theme.trim().toLowerCase();
    if (raw === 'light' || raw.includes('浅') || raw.includes('亮') || raw.includes('日间')) { patch.theme = 'light'; }
    else if (raw === 'dark' || raw.includes('深') || raw.includes('暗') || raw.includes('夜间')) { patch.theme = 'dark'; }
    else if (raw === 'system' || raw.includes('系统') || raw.includes('自动')) { patch.theme = 'system'; }
  }
  if (typeof args.language === 'string') {
    const raw = args.language.trim().toLowerCase();
    if (raw === 'en' || raw === 'en-us' || raw.includes('英') || raw.includes('english')) { patch.language = 'en'; }
    else if (raw.startsWith('zh') || raw.includes('中')) { patch.language = 'zh-Hans'; }
  }
  if (typeof args.defaultTier === 'string') {
    const raw = args.defaultTier.trim().toLowerCase();
    if (raw === 'simple' || raw === 'tier1' || raw.includes('极简')) { patch.defaultTier = 'simple'; }
    else if (raw === 'study' || raw === 'tier2' || raw.includes('学习')) { patch.defaultTier = 'study'; }
    else if (raw === 'pro' || raw === 'tier3' || raw.includes('专业')) { patch.defaultTier = 'pro'; }
  }
  if (typeof args.vaultViewMode === 'string') {
    const raw = args.vaultViewMode.trim().toLowerCase();
    if (raw === 'list' || raw === 'card' || raw === 'folder') { patch.vaultViewMode = raw; }
  }
  if (typeof args.graphShowTags === 'boolean') { patch.graphShowTags = args.graphShowTags; }
  if (typeof args.workspaceOpenMode === 'string') {
    const raw = args.workspaceOpenMode.trim().toLowerCase();
    if (raw === 'ask' || raw === 'replace' || raw === 'split') { patch.workspaceOpenMode = raw; }
  }
  if (typeof args.accent === 'string' && args.accent.trim()) {
    patch.accent = args.accent.trim();
  }
  if (args.resetColors === true) { patch.resetColors = true; }
  if (typeof args.fontSize === 'number' && Number.isFinite(args.fontSize)) {
    patch.fontSize = Math.max(10, Math.min(32, Math.round(args.fontSize)));
  }
  if (typeof args.quickZoom === 'boolean') { patch.quickZoom = args.quickZoom; }
  if (typeof args.editorDefaultView === 'string') {
    const raw = args.editorDefaultView.trim().toLowerCase();
    patch.editorDefaultView = (raw === 'preview' || raw === 'read' || raw === 'reading' || raw.includes('阅读')) ? 'preview' : 'edit';
  }
  if (typeof args.editorDefaultMode === 'string') {
    const raw = args.editorDefaultMode.trim().toLowerCase();
    patch.editorDefaultMode = (raw === 'source' || raw.includes('源码')) ? 'source' : 'live';
  }
  if (typeof args.editorShowTitle === 'boolean') { patch.editorShowTitle = args.editorShowTitle; }
  if (typeof args.editorLimitWidth === 'boolean') { patch.editorLimitWidth = args.editorLimitWidth; }
  if (typeof args.editorViewStatus === 'boolean') { patch.editorViewStatus = args.editorViewStatus; }
  if (typeof args.editorSpellcheck === 'boolean') { patch.editorSpellcheck = args.editorSpellcheck; }
  if (typeof args.interfaceTabHeaders === 'boolean') { patch.interfaceTabHeaders = args.interfaceTabHeaders; }
  if (typeof args.interfaceRibbon === 'boolean') { patch.interfaceRibbon = args.interfaceRibbon; }
  if (typeof args.interfaceZoom === 'number' && Number.isFinite(args.interfaceZoom)) {
    patch.interfaceZoom = Math.max(75, Math.min(150, Math.round(args.interfaceZoom)));
  }
  if (typeof args.interfaceSidebarWidth === 'number' && Number.isFinite(args.interfaceSidebarWidth)) {
    patch.interfaceSidebarWidth = Math.max(200, Math.min(480, Math.round(args.interfaceSidebarWidth)));
  }
  if (typeof args.interfaceRightSidebarWidth === 'number' && Number.isFinite(args.interfaceRightSidebarWidth)) {
    patch.interfaceRightSidebarWidth = Math.max(232, Math.min(560, Math.round(args.interfaceRightSidebarWidth)));
  }
  return patch;
}

async function getAppSettings(ctx) {
  if (!ctx.appSettings || typeof ctx.appSettings.get !== 'function') {
    return failure('get_app_settings', '当前宿主不支持读取软件设置');
  }
  const current = await ctx.appSettings.get();
  return result(
    '读取软件设置',
    `主题: ${current && current.theme || 'system'} · 字号: ${current && current.appearance && current.appearance.fontSize || 16}px`,
    formatSettingsSummary(current),
    false
  );
}

async function updateAppSettings(ctx, args) {
  const denied = requireCapability(ctx, 'ui.commands', 'update_app_settings');
  if (denied) { return denied; }
  if (!ctx.appSettings || typeof ctx.appSettings.set !== 'function') {
    return failure('update_app_settings', '当前宿主不支持修改软件设置');
  }
  const patch = normalizeSettingsPatch(args);
  const keys = Object.keys(patch);
  if (keys.length === 0) {
    return failure('update_app_settings', '未提供任何有效的设置项，请检查参数名（如 theme, fontSize, accent, interfaceZoom, editorLimitWidth 等）');
  }
  const updated = await ctx.appSettings.set(patch);
  return result(
    '更新软件设置',
    `已更新 ${keys.join(', ')}`,
    `已修改软件设置（${keys.join(', ')}）并立即生效：\n\n${formatSettingsSummary(updated)}`,
    false
  );
}

async function listAppCommands(ctx) {
  if (!ctx.commands || typeof ctx.commands.listHost !== 'function') {
    return failure('list_app_commands', '当前宿主不支持列出内置命令');
  }
  const list = await ctx.commands.listHost();
  if (!Array.isArray(list) || list.length === 0) {
    return result('软件命令列表', '0 项', '当前没有可用的宿主命令。', false);
  }
  const lines = list.map((cmd) => `- \`${cmd.id}\`：${cmd.title}${cmd.hint ? ` (${cmd.hint})` : ''}`);
  return result('软件命令列表', `${list.length} 项内置命令`, lines.join('\n'), false);
}

async function runAppCommand(ctx, args) {
  const denied = requireCapability(ctx, 'ui.commands', 'run_app_command');
  if (denied) { return denied; }
  if (!ctx.commands || typeof ctx.commands.executeHost !== 'function') {
    return failure('run_app_command', '当前宿主不支持执行内置命令');
  }
  const id = text(args.id || args.commandId).trim();
  if (!id) {
    return failure('run_app_command', '缺少命令 id');
  }
  const res = await ctx.commands.executeHost({ id, title: text(args.title).trim() });
  return result('执行软件命令', `${res && res.title || id}`, `已执行知萤命令：${res && res.title || id} (${id})。`, false);
}

function todoWrite(session, args) {
  const todos = Array.isArray(args.todos) ? args.todos : [];
  const next = [];
  for (const item of todos) {
    if (!item || typeof item.content !== 'string' || item.content.trim().length === 0) {
      continue;
    }
    const status = item.status === 'in_progress' || item.status === 'completed' ? item.status : 'pending';
    next.push({ content: item.content.trim().slice(0, 200), status });
  }
  if (next.length === 0) {
    return failure('todo_write', 'todos 为空');
  }
  session.todos = next;
  const marks = { pending: ' ', in_progress: '~', completed: 'x' };
  const lines = next.map((item) => `- [${marks[item.status]}] ${item.content}`);
  return result('更新待办', `${next.length} 项`, lines.join('\n'), false);
}

function loadSkill(args) {
  const name = text(args.name).trim();
  const skill = findSkill(name);
  if (!skill) {
    return failure('skill', `未知技能：${name || '(空)'}。可用技能：\n${catalog()}`);
  }
  return result(`技能：${skill.name}`, skill.description,
    `# ${skill.name}\n\n${skill.whenToUse}\n\n${skill.content}`, false);
}

/** Executes one tool call. Always resolves; failures become transcript text. */
async function executeTool(ctx, session, name, args, hooks) {
  const toolName = text(name);
  if (!TOOL_NAMES.has(toolName)) {
    return failure(toolName || 'unknown', '未知工具');
  }
  const input = args && typeof args === 'object' ? args : {};
  try {
    if (toolName === 'get_workspace_status') { return await getWorkspaceStatus(ctx, hooks); }
    if (toolName === 'list_notes') { return await listNotes(ctx, input); }
    if (toolName === 'search_notes') { return await searchNotes(ctx, input, hooks); }
    if (toolName === 'read_note') { return await readNote(ctx, input, hooks); }
    if (toolName === 'create_note') { return await createNote(ctx, input, hooks); }
    if (toolName === 'update_note') { return await updateNote(ctx, input, hooks); }
    if (toolName === 'append_to_note') { return await appendToNote(ctx, input, hooks); }
    if (toolName === 'rename_note') { return await renameNote(ctx, input, hooks); }
    if (toolName === 'delete_note') { return await deleteNote(ctx, input, hooks); }
    if (toolName === 'open_note') { return await openNote(ctx, input, hooks); }
    if (toolName === 'replace_selection') { return await replaceSelection(ctx, input, hooks); }
    if (toolName === 'replace_active_editor') { return await replaceActiveEditor(ctx, input, hooks); }
    if (toolName === 'list_mindmaps') { return await listMindMaps(ctx); }
    if (toolName === 'read_mindmap') { return await readMindMap(ctx, input); }
    if (toolName === 'create_mindmap') { return await createMindMap(ctx, input); }
    if (toolName === 'update_mindmap') { return await updateMindMap(ctx, input); }
    if (toolName === 'delete_mindmap') { return await deleteMindMap(ctx, input); }
    if (toolName === 'open_mindmap') { return await openMindMap(ctx, input); }
    if (toolName === 'list_canvases') { return await listCanvases(ctx); }
    if (toolName === 'read_canvas') { return await readCanvas(ctx, input); }
    if (toolName === 'create_canvas') { return await createCanvas(ctx, input); }
    if (toolName === 'update_canvas') { return await updateCanvas(ctx, input); }
    if (toolName === 'delete_canvas') { return await deleteCanvas(ctx, input); }
    if (toolName === 'open_canvas') { return await openCanvas(ctx, input); }
    if (toolName === 'get_app_settings') { return await getAppSettings(ctx); }
    if (toolName === 'update_app_settings') { return await updateAppSettings(ctx, input); }
    if (toolName === 'list_app_commands') { return await listAppCommands(ctx); }
    if (toolName === 'run_app_command') { return await runAppCommand(ctx, input); }
    if (toolName === 'todo_write') { return todoWrite(session, input); }
    if (toolName === 'skill') { return loadSkill(input); }
  } catch (error) {
    return failure(toolName, errorText(error));
  }
  return failure(toolName, '工具没有实现');
}

module.exports = { TOOL_DEFINITIONS, TOOL_NAMES, executeTool, previewArguments };
