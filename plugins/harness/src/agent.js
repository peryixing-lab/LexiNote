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
const { formatContextForModel, toContextMeta } = require('./context');
const { extractCitations, mergeCitationsWithContext } = require('./citations');
const { parseJson, text, errorText, normalizePath } = require('./util');

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

function injectTurnContext(modelMessages, formattedContext) {
  if (!formattedContext || !Array.isArray(modelMessages) || modelMessages.length === 0) {
    return modelMessages;
  }
  for (let i = modelMessages.length - 1; i >= 0; i -= 1) {
    if (modelMessages[i] && modelMessages[i].role === 'user') {
      const original = text(modelMessages[i].content);
      const combined = `${formattedContext}\n\n---\n用户请求：\n${original}`;
      modelMessages[i].content = combined.length > 32000 ? combined.slice(0, 32000) : combined;
      break;
    }
  }
  return modelMessages;
}

async function runTurn(ctx, session, input, hooks) {
  const prompt = text(input).trim();
  if (prompt.length === 0) {
    return;
  }
  titleFromInput(session, prompt);
  ensureSystem(session, buildSystemPrompt(ctx));

  const ctxRes = hooks && hooks.contextResult ? hooks.contextResult : null;
  const contextMeta = ctxRes ? toContextMeta(ctxRes) : null;
  const formattedContext = ctxRes && ctxRes.ok ? formatContextForModel(ctxRes) : '';
  const contextRefs = ctxRes && ctxRes.ok && Array.isArray(ctxRes.notes) ? ctxRes.notes : [];

  const knownNotes = new Map();
  function registerKnown(ref) {
    if (!ref || typeof ref !== 'object' || typeof ref.path !== 'string') { return; }
    const cleanPath = normalizePath(ref.path);
    if (!cleanPath) { return; }
    knownNotes.set(cleanPath.toLowerCase(), {
      id: text(ref.id),
      path: cleanPath,
      name: text(ref.name),
      fragment: text(ref.fragment)
    });
  }
  for (const item of contextRefs) {
    registerKnown(item);
  }

  const turnProposalIds = [];
  const seenProposalIds = new Set();
  function onProposal(proposal) {
    if (proposal && proposal.id && !seenProposalIds.has(proposal.id)) {
      seenProposalIds.add(proposal.id);
      turnProposalIds.push(proposal.id);
    }
  }

  const toolHooks = {
    changesStore: hooks && hooks.changesStore,
    contextResult: ctxRes,
    recordNote: registerKnown,
    onProposal
  };

  session.messages.push(createMessage('user', prompt, contextMeta ? { contextMeta } : undefined));
  session.aborted = false;
  await saveSession(ctx, session);
  emit(hooks, { kind: 'user' });

  let lastAssistantMsg = null;
  let attachedProposals = false;

  try {
    for (let step = 0; step < MAX_STEPS; step += 1) {
      if (session.aborted) {
        emit(hooks, { kind: 'status', text: '已停止' });
        break;
      }
      emit(hooks, { kind: 'status', text: step === 0 ? '正在思考…' : `继续处理（第 ${step + 1} 轮）…` });
      const modelMessages = injectTurnContext(historyForModel(session), formattedContext);
      const reply = await ctx.ai.chat({
        messages: modelMessages,
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
      lastAssistantMsg = assistant;

      if (calls.length === 0) {
        let vaultFiles = [];
        if (ctx.vault && typeof ctx.vault.listMarkdown === 'function') {
          try {
            vaultFiles = await ctx.vault.listMarkdown();
          } catch (_error) {
            vaultFiles = [];
          }
        }
        const knownList = Array.from(knownNotes.values());
        const extracted = extractCitations(assistant.content, knownList, vaultFiles);
        const fallbackNotes = contextRefs.filter((n) => n && n.path);
        const citations = mergeCitationsWithContext(extracted, fallbackNotes.length > 0 ? fallbackNotes : knownList);
        if (citations.length > 0) {
          assistant.citations = citations;
        }
        if (turnProposalIds.length > 0 && !attachedProposals) {
          assistant.proposalIds = turnProposalIds.slice();
          attachedProposals = true;
        }
      }

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
        const outcome = await executeTool(ctx, session, call.name, args, toolHooks);
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
        const limitExtra = turnProposalIds.length > 0 && !attachedProposals
          ? { proposalIds: turnProposalIds.slice() }
          : undefined;
        if (limitExtra) { attachedProposals = true; }
        session.messages.push(createMessage('assistant',
          '已达到单轮工具调用上限。请缩小任务范围后继续，或让我先给出当前结论。', limitExtra));
        emit(hooks, { kind: 'assistant-limit' });
        await saveSession(ctx, session);
      }
    }
  } finally {
    if (!attachedProposals && turnProposalIds.length > 0 && lastAssistantMsg) {
      lastAssistantMsg.proposalIds = turnProposalIds.slice();
      attachedProposals = true;
    }
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
