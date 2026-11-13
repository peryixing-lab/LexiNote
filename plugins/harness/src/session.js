'use strict';

const { clip, stamp, parseJson, text } = require('./util');
const { catalog } = require('./skills');

/**
 * Session state and its persistence.
 *
 * The plugin storage quota is 128 KiB / 128 keys, so an active session is aggressively
 * trimmed before every write. The model history sent in a request is trimmed separately
 * (drop oldest turns, never leave a tool result without its assistant call).
 */

const STORAGE_KEY = 'harness.session.v1';
const STORAGE_CHAR_BUDGET = 50000;
const ACTIVE_CHAR_BUDGET = 24000;
const ARCHIVE_CHAR_BUDGET = 10000;
const MAX_CONVERSATIONS = 20;
const MODEL_MESSAGE_LIMIT = 40;
const STORED_MESSAGE_LIMIT = 24;
const STORED_CONTENT_LIMIT = 4000;
const books = new Map();

function createMessage(role, content, extra) {
  const message = {
    role,
    content: typeof content === 'string' ? content : '',
    at: Date.now()
  };
  if (extra && typeof extra === 'object') {
    Object.assign(message, extra);
  }
  return message;
}

function createSession() {
  const now = Date.now();
  const session = {
    id: `session-${now.toString(36)}-${Math.floor(Math.random() * 1e9).toString(36)}`,
    title: '新会话',
    createdAt: now,
    updatedAt: now,
    messages: [],
    todos: [],
    draft: ''
  };
  return session;
}

function buildSystemPrompt(ctx) {
  return [
    '你是知萤（LexiNote）里的 Harness 智能体，运行在一个受限的原生插件沙箱中。',
    '你可以通过工具读取、检索、创建和修改当前知识库里的 Markdown 笔记；模型请求由知萤宿主代办，你不能直接访问网络。',
    '',
    '## 工作规则',
    '1. 不要编造笔记、路径或引用。引用笔记前先用 list_notes / search_notes / read_note 核实。',
    '2. 默认只给建议，不修改原文。只有用户明确说“写回去 / 应用 / 修改 / 删除”时才写笔记。',
    '3. 修改前用一句话说明要改什么；删除或大段替换前先请求用户确认。',
    '4. 工具失败时先读错误码：E_CONFLICT 需重新读取，E_PATH_EXISTS 改用 update_note，E_EDITOR_READONLY 说明没有活动编辑器。',
    '5. 路径必须是知识库相对路径并以 .md 结尾；跨目录改名不支持。',
    '6. 用中文回答，简洁，先结论后依据；给出可执行的下一步。',
    '7. 需要专项流程时调用 skill 工具加载技能，不要凭空假设步骤。',
    '',
    `当前时间：${stamp()}`,
    `当前知识库：${ctx.vaultId || '未知'}`,
    '',
    '## 可用技能',
    catalog()
  ].join('\n');
}

function ensureSystem(session, prompt) {
  if (session.messages.length > 0 && session.messages[0].role === 'system') {
    session.messages[0].content = prompt;
    return;
  }
  session.messages.unshift(createMessage('system', prompt));
}

/** History for one model request: system + the most recent whole turns. */
function historyForModel(session) {
  const messages = Array.isArray(session.messages) ? session.messages : [];
  if (messages.length === 0) {
    return [];
  }
  const system = messages[0] && messages[0].role === 'system' ? messages[0] : null;
  const rest = system ? messages.slice(1) : messages.slice();
  let start = Math.max(0, rest.length - (MODEL_MESSAGE_LIMIT - 1));
  while (start < rest.length && rest[start].role === 'tool') {
    start += 1;
  }
  const selected = rest.slice(start);
  const output = [];
  if (system) {
    output.push({ role: 'system', content: clip(system.content, 12000) });
  }
  for (const message of selected) {
    const record = {
      role: message.role,
      content: clip(message.content, 8000)
    };
    if (message.role === 'assistant' && Array.isArray(message.toolCalls) && message.toolCalls.length > 0) {
      record.toolCalls = message.toolCalls.map((call) => ({
        id: call.id,
        name: call.name,
        arguments: call.arguments
      }));
    }
    if (message.role === 'tool') {
      record.toolCallId = message.toolCallId || '';
      record.toolName = message.toolName || '';
      record.isError = message.isError === true;
    }
    output.push(record);
  }
  return output;
}

function storedSession(session, budget = ACTIVE_CHAR_BUDGET, includeSystem = true) {
  const messages = Array.isArray(session.messages) ? session.messages : [];
  const system = messages[0] && messages[0].role === 'system' ? messages[0] : null;
  const rest = system ? messages.slice(1) : messages.slice();
  let start = Math.max(0, rest.length - STORED_MESSAGE_LIMIT);
  while (start > 0 && rest[start] && rest[start].role !== 'user') { start -= 1; }
  const selected = rest.slice(start);
  const kept = [];
  let trimmed = session.historyTrimmed === true || start > 0;
  if (system && includeSystem) {
    kept.push({
      role: 'system',
      content: clip(system.content, 4000),
      at: system.at || session.createdAt
    });
  }
  for (const message of selected) {
    const record = {
      role: message.role,
      content: clip(message.content, STORED_CONTENT_LIMIT),
      at: message.at || session.updatedAt
    };
    if (typeof message.reasoning === 'string' && message.reasoning.length > 0) {
      record.reasoning = clip(message.reasoning, 1500);
    }
    if (Array.isArray(message.toolCalls) && message.toolCalls.length > 0) {
      record.toolCalls = message.toolCalls.slice(0, 8).map((call) => ({
        id: text(call.id),
        name: text(call.name),
        arguments: text(call.arguments).length <= 1200 ? text(call.arguments) : '{"_history_truncated":true}'
      }));
    }
    if (message.role === 'tool') {
      record.toolCallId = text(message.toolCallId);
      record.toolName = text(message.toolName);
      record.isError = message.isError === true;
    }
    kept.push(record);
  }
  const payload = {
    id: session.id,
    title: session.title,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    messages: kept,
    todos: Array.isArray(session.todos) ? session.todos.slice(0, 20).map(todo => ({
      content: clip(todo.content, 200), status: text(todo.status).slice(0, 24)
    })) : [],
    draft: text(session.draft).slice(0, includeSystem ? 8000 : 4000),
    service: text(session.service).slice(0, 64),
    model: text(session.model).slice(0, 128),
    historyTrimmed: trimmed
  };
  if (messages.some(message => text(message.content).length > STORED_CONTENT_LIMIT || text(message.reasoning).length > 1500) ||
    messages.some(message => (message.toolCalls || []).some(call => text(call.arguments).length > 1200)) ||
    text(session.draft).length > payload.draft.length) { trimmed = true; }
  // Drop whole old turns first, preserving assistant tool calls with their results.
  while (JSON.stringify(payload).length > budget) {
    const first = payload.messages[0] && payload.messages[0].role === 'system' ? 1 : 0;
    const nextUser = payload.messages.findIndex((message, index) => index > first && message.role === 'user');
    if (nextUser < 0) { break; }
    payload.messages.splice(first, nextUser - first);
    trimmed = true;
  }
  for (let limit = 1500; JSON.stringify(payload).length > budget && limit >= 48; limit = Math.floor(limit / 2)) {
    trimmed = true;
    for (const message of payload.messages) {
      message.content = clip(message.content, limit);
      if (message.reasoning) { message.reasoning = clip(message.reasoning, Math.floor(limit / 2)); }
      for (const call of message.toolCalls || []) {
        call.id = text(call.id).slice(0, 128); call.name = text(call.name).slice(0, 128);
        if (text(call.arguments).length > limit) { call.arguments = '{"_history_truncated":true}'; }
      }
    }
  }
  if (JSON.stringify(payload).length > budget) {
    // A single very long tool turn: keep its user request and latest complete step.
    const firstUser = payload.messages.find(message => message.role === 'user');
    let lastAssistant = -1;
    payload.messages.forEach((message, index) => { if (message.role === 'assistant') { lastAssistant = index; } });
    payload.messages = firstUser ? [firstUser, ...(lastAssistant >= 0 ? payload.messages.slice(lastAssistant) : [])] : [];
    payload.todos = payload.todos.slice(0, 5);
    payload.draft = payload.draft.slice(0, 4000);
    trimmed = true;
  }
  payload.historyTrimmed = trimmed;
  return payload;
}

function restoreSession(raw) {
  raw = JSON.parse(JSON.stringify(raw));
  const session = createSession();
  session.id = typeof raw.id === 'string' && raw.id.length > 0 ? raw.id : session.id;
  session.title = typeof raw.title === 'string' && raw.title.length > 0 ? raw.title : session.title;
  session.createdAt = Number(raw.createdAt) || session.createdAt;
  session.updatedAt = Number(raw.updatedAt) || session.updatedAt;
  session.messages = Array.isArray(raw.messages)
    ? raw.messages.filter((message) => message && typeof message.role === 'string')
    : [];
  session.todos = Array.isArray(raw.todos) ? raw.todos : [];
  session.draft = text(raw.draft);
  session.service = text(raw.service);
  session.model = text(raw.model);
  session.historyTrimmed = raw.historyTrimmed === true;
  return session;
}

function meaningful(session) {
  return !!text(session.draft).trim() || (session.messages || []).some(message => message.role === 'user');
}

async function bookFor(ctx) {
  let book = books.get(ctx);
  if (!book) {
    book = { current: null, history: [], writes: Promise.resolve(), loading: null, error: '', evicted: 0 };
    books.set(ctx, book);
    book.loading = (async () => {
      const raw = await ctx.storage.get(STORAGE_KEY);
      if (raw && (typeof raw !== 'object' || !Array.isArray(raw.messages))) {
        throw new Error('对话记录格式损坏，请恢复插件数据后重试');
      }
      book.current = raw ? restoreSession(raw) : createSession();
      const ids = new Set([book.current.id]);
      book.history = (raw && Array.isArray(raw.history) ? raw.history : []).filter(entry => {
        if (!entry || typeof entry.id !== 'string' || !Array.isArray(entry.messages) || ids.has(entry.id)) { return false; }
        ids.add(entry.id); return true;
      }).map(restoreSession);
      book.evicted = Number(raw && raw.evicted) || 0;
    })();
  }
  try { await book.loading; return book; }
  catch (failure) { books.delete(ctx); throw failure; }
}

async function loadSession(ctx) {
  const book = await bookFor(ctx);
  return restoreSession(book.current);
}

async function commit(ctx, book, current, history) {
  const payload = storedSession(current);
  const sorted = history.filter(entry => entry.id !== current.id && meaningful(entry))
    .sort((left, right) => right.updatedAt - left.updatedAt);
  payload.history = sorted.slice(0, MAX_CONVERSATIONS - 1).map(entry => storedSession(entry, ARCHIVE_CHAR_BUDGET, false));
  payload.evicted = book.evicted + Math.max(0, sorted.length - payload.history.length);
  while (JSON.stringify(payload).length > STORAGE_CHAR_BUDGET && payload.history.length) {
    payload.history.pop(); payload.evicted += 1;
  }
  if (JSON.stringify(payload).length > STORAGE_CHAR_BUDGET) { throw new Error('当前对话过长，无法保存'); }
  await ctx.storage.set(STORAGE_KEY, payload);
  book.current = restoreSession(payload);
  book.history = payload.history.map(restoreSession);
  book.evicted = payload.evicted;
  book.error = '';
}

async function changeBook(ctx, operation) {
  const book = await bookFor(ctx);
  const task = book.writes.catch(() => {}).then(() => operation(book));
  book.writes = task;
  return task;
}

async function saveSession(ctx, session, options) {
  session.updatedAt = Date.now();
  const snapshot = storedSession(session);
  try {
    await changeBook(ctx, book => {
      const history = book.history.filter(entry => entry.id !== snapshot.id);
      if (book.current.id !== snapshot.id && meaningful(book.current)) { history.unshift(book.current); }
      return commit(ctx, book, snapshot, history);
    });
    return true;
  } catch (error) {
    const book = books.get(ctx);
    if (book) { book.error = '对话保存失败，当前内容仅保留在内存中。请重试后再切换。'; }
    ctx.log('warn', `会话保存失败（${(error && error.message) || error}），本会话仍保留在内存中`);
    if (options && options.strict) { throw error; }
    return false;
  }
}

async function listConversations(ctx) {
  const book = await bookFor(ctx);
  await book.writes.catch(() => {});
  return [book.current, ...book.history].filter(meaningful).sort((left, right) => right.updatedAt - left.updatedAt).map(entry => {
    const last = [...entry.messages].reverse().find(message => ['user', 'assistant'].includes(message.role) && text(message.content).trim());
    return { id: entry.id, title: entry.title, updatedAt: entry.updatedAt,
      current: entry.id === book.current.id, preview: text(last && last.content || entry.draft).replace(/\s+/g, ' ').slice(0, 100),
      draft: !!text(entry.draft).trim(), trimmed: entry.historyTrimmed, service: entry.service, model: entry.model };
  });
}

async function selectConversation(ctx, id) {
  return changeBook(ctx, async book => {
    if (book.current.id === id) { return restoreSession(book.current); }
    const next = book.history.find(entry => entry.id === id);
    if (!next) { throw new Error('对话记录不存在，请重新打开历史记录'); }
    await commit(ctx, book, next, [book.current, ...book.history.filter(entry => entry.id !== id)]);
    return restoreSession(book.current);
  });
}

async function deleteConversation(ctx, id) {
  return changeBook(ctx, async book => {
    const remaining = book.history.filter(entry => entry.id !== id);
    let next = book.current;
    if (next.id === id) { next = [...remaining].sort((left, right) => right.updatedAt - left.updatedAt)[0] || createSession(); }
    await commit(ctx, book, next, remaining);
    return restoreSession(book.current);
  });
}

function historyNotice(ctx) {
  const book = books.get(ctx);
  return book && book.error || '';
}

function resetSession() {
  return createSession();
}

/** Title derived from the first user line, so the UI has a stable label. */
function titleFromInput(session, input) {
  if (session.title && session.title !== '新会话') {
    return;
  }
  const firstLine = text(input).trim().split(/\r?\n/)[0] || '';
  if (firstLine.length > 0) {
    session.title = firstLine.slice(0, 24);
  }
}

module.exports = {
  STORAGE_KEY,
  createMessage,
  createSession,
  buildSystemPrompt,
  ensureSystem,
  historyForModel,
  loadSession,
  saveSession,
  listConversations,
  selectConversation,
  deleteConversation,
  historyNotice,
  STORAGE_CHAR_BUDGET,
  resetSession,
  titleFromInput,
  parseJson
};
