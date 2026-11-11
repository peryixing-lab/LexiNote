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
const STORAGE_CHAR_BUDGET = 30000;
const MODEL_MESSAGE_LIMIT = 40;
const STORED_MESSAGE_LIMIT = 24;
const STORED_CONTENT_LIMIT = 4000;

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
    id: `session-${now.toString(36)}`,
    title: '新会话',
    createdAt: now,
    updatedAt: now,
    messages: [],
    todos: []
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

function storedSession(session) {
  const messages = Array.isArray(session.messages) ? session.messages : [];
  const system = messages[0] && messages[0].role === 'system' ? messages[0] : null;
  const rest = system ? messages.slice(1) : messages.slice();
  const selected = rest.slice(Math.max(0, rest.length - STORED_MESSAGE_LIMIT));
  const kept = [];
  if (system) {
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
        arguments: clip(call.arguments, 1200)
      }));
    }
    if (message.role === 'tool') {
      record.toolCallId = text(message.toolCallId);
      record.toolName = text(message.toolName);
      record.isError = message.isError === true;
    }
    kept.push(record);
  }
  return {
    id: session.id,
    title: session.title,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    messages: kept,
    todos: Array.isArray(session.todos) ? session.todos.slice(0, 20) : []
  };
}

async function loadSession(ctx) {
  let raw;
  try {
    raw = await ctx.storage.get(STORAGE_KEY);
  } catch (error) {
    raw = null;
  }
  if (!raw || typeof raw !== 'object') {
    return createSession();
  }
  const session = createSession();
  session.id = typeof raw.id === 'string' && raw.id.length > 0 ? raw.id : session.id;
  session.title = typeof raw.title === 'string' && raw.title.length > 0 ? raw.title : session.title;
  session.createdAt = Number(raw.createdAt) || session.createdAt;
  session.updatedAt = Number(raw.updatedAt) || session.updatedAt;
  session.messages = Array.isArray(raw.messages)
    ? raw.messages.filter((message) => message && typeof message.role === 'string')
    : [];
  session.todos = Array.isArray(raw.todos) ? raw.todos : [];
  return session;
}

async function saveSession(ctx, session) {
  session.updatedAt = Date.now();
  const payload = storedSession(session);
  let json = JSON.stringify(payload);
  while (json.length > STORAGE_CHAR_BUDGET && payload.messages.length > 3) {
    const systemOffset = payload.messages[0] && payload.messages[0].role === 'system' ? 1 : 0;
    payload.messages.splice(systemOffset, 1);
    json = JSON.stringify(payload);
  }
  try {
    await ctx.storage.set(STORAGE_KEY, payload);
  } catch (error) {
    ctx.log('warn', `会话保存失败（${(error && error.message) || error}），本会话仍保留在内存中`);
  }
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
  resetSession,
  titleFromInput,
  parseJson
};
