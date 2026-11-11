'use strict';

const {
  createMessage,
  ensureSystem,
  buildSystemPrompt,
  historyForModel,
  saveSession,
  titleFromInput
} = require('./session');
const { TOOL_DEFINITIONS, executeTool } = require('./tools');
const { parseJson, text, errorText } = require('./util');

/**
 * The agent loop.
 *
 * One turn = one user message, then up to `MAX_STEPS` model calls. Each model reply may
 * carry tool calls; every call is executed against the plugin API and fed back as a
 * `tool` message. The loop ends when the model answers without tool calls, when the user
 * aborts, or when the step budget is exhausted.
 *
 * All hooks are optional and synchronous; the view uses them to repaint incrementally.
 * Errors from `ctx.ai.chat` are re-thrown after the session is persisted so the composer
 * can show a precise error and the user can retry.
 */

const MAX_STEPS = 8;

function normalizeCalls(rawCalls) {
  if (!Array.isArray(rawCalls)) {
    return [];
  }
  const calls = [];
  for (const raw of rawCalls) {
    if (!raw || typeof raw.name !== 'string' || raw.name.length === 0) {
      continue;
    }
    calls.push({
      id: typeof raw.id === 'string' && raw.id.length > 0 ? raw.id : `call_${calls.length}`,
      name: raw.name,
      arguments: typeof raw.arguments === 'string' ? raw.arguments : '{}'
    });
  }
  return calls;
}

function emit(hooks, event) {
  if (hooks && typeof hooks.onEvent === 'function') {
    try {
      hooks.onEvent(event);
    } catch (error) {
      // UI failures must not abort a model turn.
    }
  }
}

async function runTurn(ctx, session, input, hooks) {
  const prompt = text(input).trim();
  if (prompt.length === 0) {
    return;
  }
  titleFromInput(session, prompt);
  ensureSystem(session, buildSystemPrompt(ctx));
  session.messages.push(createMessage('user', prompt));
  session.aborted = false;
  await saveSession(ctx, session);
  emit(hooks, { kind: 'user' });

  try {
    for (let step = 0; step < MAX_STEPS; step += 1) {
      if (session.aborted) {
        emit(hooks, { kind: 'status', text: '已停止' });
        break;
      }
      emit(hooks, { kind: 'status', text: step === 0 ? '正在思考…' : `继续处理（第 ${step + 1} 轮）…` });
      const reply = await ctx.ai.chat({
        messages: historyForModel(session),
        tools: TOOL_DEFINITIONS,
        maxTokens: 4096,
        temperature: 0.3
      });
      if (session.aborted) {
        emit(hooks, { kind: 'status', text: '已停止' });
        break;
      }
      const calls = normalizeCalls(reply.toolCalls);
      const assistant = createMessage('assistant', reply.text || '', {
        reasoning: reply.reasoning || '',
        toolCalls: calls
      });
      session.messages.push(assistant);
      emit(hooks, { kind: 'assistant', message: assistant });
      await saveSession(ctx, session);
      if (calls.length === 0) {
        break;
      }
      for (const call of calls) {
        emit(hooks, { kind: 'tool-start', call });
        let args = {};
        try {
          args = parseJson(call.arguments, {});
          if (!args || typeof args !== 'object' || Array.isArray(args)) {
            args = {};
          }
        } catch (error) {
          args = {};
        }
        const outcome = await executeTool(ctx, session, call.name, args);
        const toolMessage = createMessage('tool', outcome.text, {
          toolCallId: call.id,
          toolName: call.name,
          isError: outcome.isError === true,
          title: outcome.title,
          subtitle: outcome.subtitle
        });
        session.messages.push(toolMessage);
        emit(hooks, { kind: 'tool-end', call, outcome, message: toolMessage });
        await saveSession(ctx, session);
        if (session.aborted) {
          break;
        }
      }
      if (session.aborted) {
        emit(hooks, { kind: 'status', text: '已停止' });
        break;
      }
      if (step === MAX_STEPS - 1) {
        session.messages.push(createMessage('assistant',
          '已达到单轮工具调用上限。请缩小任务范围后继续，或让我先给出当前结论。'));
        emit(hooks, { kind: 'assistant-limit' });
        await saveSession(ctx, session);
      }
    }
  } finally {
    session.aborted = false;
    await saveSession(ctx, session);
    emit(hooks, { kind: 'done' });
  }
}

function stopTurn(session) {
  session.aborted = true;
  return true;
}

module.exports = { runTurn, stopTurn, MAX_STEPS, normalizeCalls, errorText };
