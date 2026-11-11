'use strict';

const { clip, text, normalizePath, basename, dirname, errorText, previewArguments } = require('./util');
const { findSkill, catalog } = require('./skills');

/**
 * Harness tool layer over the LexiNote plugin API.
 *
 * Every tool is a thin, explicit wrapper over `ctx.vault` / `ctx.workspace` / `ctx.editor`.
 * Tools return a plain transcript record `{ title, subtitle, text, isError }`; they never
 * throw, because the model needs a readable failure message to recover in the next step.
 */

const MAX_LIST = 60;
const MAX_READ = 20000;
const MAX_SEARCH_READS = 36;

const TOOL_DEFINITIONS = [
  {
    name: 'get_workspace_status',
    description: '读取当前知识库、活动笔记、编辑器状态与笔记总数。整理前先调用它了解上下文。',
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
    description: '新建一篇 Markdown 笔记。目标已存在时返回错误，不会覆盖。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '知识库相对路径，必须以 .md 结尾' },
        content: { type: 'string', description: '完整 Markdown 内容' }
      },
      required: ['path', 'content']
    }
  },
  {
    name: 'update_note',
    description: '更新笔记：传 content 整体替换；或传 find/replace 做定点替换。写入前会重新读取。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' },
        content: { type: 'string', description: '完整新内容；与 find/replace 二选一' },
        find: { type: 'string', description: '要查找的原文片段' },
        replace: { type: 'string', description: '替换后的文本' },
        replaceAll: { type: 'boolean', description: '是否替换所有匹配，默认 false' }
      },
      required: ['path']
    }
  },
  {
    name: 'append_to_note',
    description: '在笔记末尾追加 Markdown（自动补空行），不改动原文。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' },
        markdown: { type: 'string', description: '要追加的 Markdown' }
      },
      required: ['path', 'markdown']
    }
  },
  {
    name: 'rename_note',
    description: '重命名笔记。v1 只支持同一目录内改名。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '原路径' },
        newPath: { type: 'string', description: '新路径，目录必须与原路径相同' }
      },
      required: ['path', 'newPath']
    }
  },
  {
    name: 'delete_note',
    description: '把笔记移入回收站（软删除，可恢复）。删除前先向用户确认。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' }
      },
      required: ['path']
    }
  },
  {
    name: 'open_note',
    description: '在知萤中打开一篇笔记。',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: '目标笔记路径' }
      },
      required: ['path']
    }
  },
  {
    name: 'replace_active_editor',
    description: '整体替换当前活动编辑器的内容。仅在用户明确要求改写正在编辑的笔记时使用。',
    parameters: {
      type: 'object',
      properties: {
        text: { type: 'string', description: '新的完整编辑器内容' }
      },
      required: ['text']
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

async function getWorkspaceStatus(ctx) {
  const files = await ctx.vault.listMarkdown();
  let activePath = '';
  try {
    const active = await ctx.workspace.activeFile();
    activePath = active ? active.path : '';
  } catch (error) {
    activePath = '';
  }
  let editorLine = '没有打开编辑器';
  try {
    const snapshot = await ctx.editor.active();
    if (snapshot) {
      editorLine = `${snapshot.noteId}（${snapshot.content.length} 字符${snapshot.dirty ? '，有未保存改动' : ''}）`;
    }
  } catch (error) {
    editorLine = '无法读取编辑器';
  }
  return result('工作区状态', `${files.length} 篇笔记`, [
    `知识库：${ctx.vaultId || '当前知识库'}`,
    `笔记总数：${files.length}`,
    `活动笔记：${activePath || '无'}`,
    `活动编辑器：${editorLine}`
  ].join('\n'), false);
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

async function searchNotes(ctx, args) {
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

async function readNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('read_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('read_note', `笔记不存在：${path}`);
  }
  const content = await ctx.vault.read(file);
  const body = clip(content, MAX_READ);
  return result('读取笔记', `${path} · ${content.length} 字符`, `# ${path}\n\n${body}`, false);
}

async function createNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('create_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  if (typeof args.content !== 'string') {
    return failure('create_note', '缺少 content');
  }
  const existing = await ctx.vault.get(path);
  if (existing) {
    return failure('create_note', `目标已存在：${path}。请改用 update_note 或换一个路径`);
  }
  try {
    const file = await ctx.vault.create(path, args.content);
    return result('新建笔记', path, `已创建 ${file.path}（${args.content.length} 字符）。`, false);
  } catch (error) {
    return failure('create_note', errorText(error));
  }
}

async function updateNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('update_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('update_note', `笔记不存在：${path}`);
  }
  let current = '';
  try {
    current = await ctx.vault.read(file);
  } catch (error) {
    return failure('update_note', errorText(error));
  }
  let next = '';
  let summary = '';
  if (typeof args.content === 'string') {
    next = args.content;
    summary = '整体替换';
  } else if (typeof args.find === 'string' && args.find.length > 0 && typeof args.replace === 'string') {
    if (current.indexOf(args.find) < 0) {
      return failure('update_note', '没有找到要替换的原文片段，请先 read_note 确认内容');
    }
    next = args.replaceAll === true
      ? current.split(args.find).join(args.replace)
      : current.replace(args.find, args.replace);
    summary = args.replaceAll === true ? '替换全部匹配片段' : '替换一处片段';
  } else {
    return failure('update_note', '需要 content，或同时提供 find 与 replace');
  }
  if (next === current) {
    return result('更新笔记', path, '内容没有变化，未写入。', false);
  }
  try {
    await ctx.vault.write(file, next);
    return result('更新笔记', `${path} · ${summary}`, `已写入 ${next.length} 字符（原 ${current.length} 字符）。`, false);
  } catch (error) {
    return failure('update_note', errorText(error));
  }
}

async function appendToNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('append_to_note', '缺少 path');
  }
  if (typeof args.markdown !== 'string' || args.markdown.length === 0) {
    return failure('append_to_note', '缺少 markdown');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('append_to_note', `笔记不存在：${path}`);
  }
  try {
    const current = await ctx.vault.read(file);
    const separator = current.replace(/\s+$/, '').length === 0 ? '' : (current.endsWith('\n') ? '\n' : '\n\n');
    const next = `${current.replace(/\s+$/, '')}${separator}${args.markdown.replace(/^\s+/, '')}\n`;
    await ctx.vault.write(file, next);
    return result('追加内容', path, `已在末尾追加 ${args.markdown.length} 字符。`, false);
  } catch (error) {
    return failure('append_to_note', errorText(error));
  }
}

async function renameNote(ctx, args) {
  if (!isValidPath(args.path) || !isValidPath(args.newPath)) {
    return failure('rename_note', '需要 path 与 newPath');
  }
  const path = normalizePath(args.path);
  const newPath = normalizePath(args.newPath);
  if (dirname(path) !== dirname(newPath)) {
    return failure('rename_note', 'v1 只支持同一目录内改名；跨目录请新建后删除原文件');
  }
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('rename_note', `笔记不存在：${path}`);
  }
  try {
    const renamed = await ctx.vault.rename(file, newPath);
    return result('重命名', `${path} → ${newPath}`, `已重命名为 ${renamed.path}。`, false);
  } catch (error) {
    return failure('rename_note', errorText(error));
  }
}

async function deleteNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('delete_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('delete_note', `笔记不存在：${path}`);
  }
  try {
    await ctx.vault.delete(file);
    return result('删除笔记', path, `已把 ${path} 移入回收站，可在知萤中恢复。`, false);
  } catch (error) {
    return failure('delete_note', errorText(error));
  }
}

async function openNote(ctx, args) {
  if (!isValidPath(args.path)) {
    return failure('open_note', '缺少 path');
  }
  const path = normalizePath(args.path);
  const file = await ctx.vault.get(path);
  if (!file) {
    return failure('open_note', `笔记不存在：${path}`);
  }
  await ctx.workspace.openFile(file);
  return result('打开笔记', path, `已在知萤中打开 ${path}。`, false);
}

async function replaceActiveEditor(ctx, args) {
  if (typeof args.text !== 'string') {
    return failure('replace_active_editor', '缺少 text');
  }
  try {
    const written = await ctx.editor.replaceAll(args.text);
    return result('改写编辑器', `${written.content.length} 字符`, '已整体替换当前编辑器内容。', false);
  } catch (error) {
    return failure('replace_active_editor', errorText(error));
  }
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
async function executeTool(ctx, session, name, args) {
  const toolName = text(name);
  if (!TOOL_NAMES.has(toolName)) {
    return failure(toolName || 'unknown', '未知工具');
  }
  const input = args && typeof args === 'object' ? args : {};
  try {
    if (toolName === 'get_workspace_status') { return await getWorkspaceStatus(ctx); }
    if (toolName === 'list_notes') { return await listNotes(ctx, input); }
    if (toolName === 'search_notes') { return await searchNotes(ctx, input); }
    if (toolName === 'read_note') { return await readNote(ctx, input); }
    if (toolName === 'create_note') { return await createNote(ctx, input); }
    if (toolName === 'update_note') { return await updateNote(ctx, input); }
    if (toolName === 'append_to_note') { return await appendToNote(ctx, input); }
    if (toolName === 'rename_note') { return await renameNote(ctx, input); }
    if (toolName === 'delete_note') { return await deleteNote(ctx, input); }
    if (toolName === 'open_note') { return await openNote(ctx, input); }
    if (toolName === 'replace_active_editor') { return await replaceActiveEditor(ctx, input); }
    if (toolName === 'todo_write') { return todoWrite(session, input); }
    if (toolName === 'skill') { return loadSkill(input); }
  } catch (error) {
    return failure(toolName, errorText(error));
  }
  return failure(toolName, '工具没有实现');
}

module.exports = { TOOL_DEFINITIONS, TOOL_NAMES, executeTool, previewArguments };
