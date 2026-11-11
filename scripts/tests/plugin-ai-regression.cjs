// P16 · Host-brokered model inference: binding, OpenAI/Anthropic wires, error mapping.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const S = box.prepareStorage();
const { PluginAiService } = box.load('plugin/ai/PluginAiService');
const { PluginErrorCode } = box.load('plugin/model/PluginErrors');
const { PluginCapability } = box.load('plugin/model/PluginModels');
const { PluginRpcMethod, PluginRpcRequest } = box.load('plugin/model/PluginContracts');
const { PluginRpcDispatcher, PluginSession } = box.load('plugin/runtime/PluginRpcDispatcher');

let assertions = 0;
const ok = (value, message) => { assertions++; assert.ok(value, message); };
const eq = (left, right, message) => { assertions++; assert.deepEqual(left, right, message); };
async function rejects(promise, code, message) {
  assertions++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}

function chat(params) {
  return PluginAiService.chat(JSON.stringify(params));
}

(async () => {
  PluginAiService.resetForTests();

  // 1. Nothing is bound by default and the status never leaks a key.
  const initial = JSON.parse(await PluginAiService.status());
  eq(initial.configured, false, 'model is unbound by default');
  ok(!Object.prototype.hasOwnProperty.call(initial, 'apiKey'), 'status never contains apiKey');
  await rejects(chat({ messages: [{ role: 'user', content: 'hi' }] }), PluginErrorCode.MODEL_UNAVAILABLE,
    'chat without a key fails explicitly');
  console.log('PASS an unbound model refuses to chat and never exposes a key');

  // 2. Binding validates provider, URL and model.
  await rejects(PluginAiService.configure(JSON.stringify({ provider: 'carrier-pigeon' })),
    PluginErrorCode.INVALID_ARGUMENT, 'unknown provider');
  await rejects(PluginAiService.configure(JSON.stringify({ baseUrl: 'ftp://example.test' })),
    PluginErrorCode.INVALID_ARGUMENT, 'non-http base URL');
  await rejects(PluginAiService.configure(JSON.stringify({ provider: 'openai-compatible', model: 'm' })),
    PluginErrorCode.INVALID_ARGUMENT, 'first binding requires a key');
  const bound = JSON.parse(await PluginAiService.configure(JSON.stringify({
    provider: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com/',
    model: 'deepseek-chat',
    apiKey: 'sk-test-1'
  })));
  eq(bound.configured, true, 'configured after binding');
  eq(bound.baseUrl, 'https://api.deepseek.com', 'trailing slash removed');
  eq(bound.model, 'deepseek-chat', 'model stored');
  ok(!Object.prototype.hasOwnProperty.call(bound, 'apiKey'), 'configure result hides the key');
  console.log('PASS provider/baseUrl validation and key confinement');

  // 3. OpenAI-compatible wire: request shape and tool-call parsing.
  box.expectHttp({
    status: 200,
    body: JSON.stringify({
      choices: [{
        message: {
          content: '我先读一下。',
          reasoning_content: '需要先读原文',
          tool_calls: [{
            id: 'call-1',
            type: 'function',
            function: { name: 'read_note', arguments: '{"path":"课程/一.md"}' }
          }]
        },
        finish_reason: 'tool_calls'
      }],
      usage: { prompt_tokens: 11, completion_tokens: 7 }
    })
  });
  const openAiReply = JSON.parse(await chat({
    messages: [
      { role: 'system', content: '你是助手' },
      { role: 'user', content: '读一读' },
      { role: 'assistant', content: '', toolCalls: [{ id: 'call-0', name: 'list_notes', arguments: '{}' }] },
      { role: 'tool', content: '结果', toolCallId: 'call-0', toolName: 'list_notes' }
    ],
    tools: [{
      name: 'read_note',
      description: '读笔记',
      parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] }
    }],
    maxTokens: 1024,
    temperature: 0.2
  }));
  eq(openAiReply.text, '我先读一下。', 'assistant text');
  eq(openAiReply.reasoning, '需要先读原文', 'reasoning content');
  eq(openAiReply.toolCalls.length, 1, 'one tool call');
  eq(openAiReply.toolCalls[0].name, 'read_note', 'tool name');
  eq(openAiReply.finishReason, 'tool_calls', 'finish reason');
  eq(openAiReply.usage.inputTokens, 11, 'input tokens');
  eq(openAiReply.usage.outputTokens, 7, 'output tokens');

  const openAiRequest = box.state.httpRequests[0];
  eq(openAiRequest.url, 'https://api.deepseek.com/v1/chat/completions', 'OpenAI endpoint');
  eq(openAiRequest.options.header['Authorization'], 'Bearer sk-test-1', 'bearer header');
  const openAiBody = JSON.parse(openAiRequest.options.extraData);
  eq(openAiBody.stream, false, 'non-streaming request');
  eq(openAiBody.messages[2].tool_calls[0].function.name, 'list_notes', 'assistant tool call serialized');
  eq(openAiBody.messages[3].tool_call_id, 'call-0', 'tool result correlation');
  eq(openAiBody.tools[0].type, 'function', 'tool wrapped');
  eq(openAiBody.tools[0].function.parameters.required[0], 'path', 'schema preserved');
  eq(openAiBody.max_tokens, 1024, 'per-call max tokens');
  eq(openAiBody.temperature, 0.2, 'per-call temperature');
  console.log('PASS OpenAI wire request/response including tool calls and usage');

  // 4. Anthropic-compatible wire.
  const anthropic = JSON.parse(await PluginAiService.configure(JSON.stringify({
    provider: 'anthropic-compatible',
    baseUrl: 'https://api.deepseek.com/anthropic',
    model: 'deepseek-flash',
    apiKey: 'sk-test-2'
  })));
  eq(anthropic.provider, 'anthropic-compatible', 'provider switched');
  box.expectHttp({
    status: 200,
    body: JSON.stringify({
      content: [
        { type: 'thinking', thinking: '思考中' },
        { type: 'text', text: '你好' },
        { type: 'tool_use', id: 'toolu-1', name: 'list_notes', input: { limit: 5 } }
      ],
      stop_reason: 'tool_use',
      usage: { input_tokens: 9, output_tokens: 4 }
    })
  });
  const anthropicReply = JSON.parse(await chat({
    messages: [
      { role: 'system', content: '系统提示' },
      { role: 'user', content: '列一下' },
      { role: 'assistant', content: '', toolCalls: [{ id: 'toolu-0', name: 'search_notes', arguments: '{"query":"x"}' }] },
      { role: 'tool', content: '搜索完成', toolCallId: 'toolu-0' }
    ],
    tools: [{ name: 'list_notes', description: '列出', parameters: { type: 'object', properties: {} } }]
  }));
  eq(anthropicReply.text, '你好', 'anthropic text');
  eq(anthropicReply.reasoning, '思考中', 'anthropic thinking');
  eq(anthropicReply.toolCalls[0].name, 'list_notes', 'anthropic tool name');
  eq(JSON.parse(anthropicReply.toolCalls[0].arguments).limit, 5, 'tool input serialized');
  eq(anthropicReply.finishReason, 'tool_calls', 'tool_use mapped to tool_calls');

  const anthropicRequest = box.state.httpRequests[1];
  eq(anthropicRequest.url, 'https://api.deepseek.com/anthropic/v1/messages', 'Anthropic endpoint');
  eq(anthropicRequest.options.header['x-api-key'], 'sk-test-2', 'anthropic key header');
  const anthropicBody = JSON.parse(anthropicRequest.options.extraData);
  eq(anthropicBody.system, '系统提示', 'system is a top-level field');
  eq(anthropicBody.messages[1].content[0].type, 'tool_use', 'assistant tool_use block');
  eq(anthropicBody.messages[2].content[0].type, 'tool_result', 'tool result block');
  eq(anthropicBody.tools[0].input_schema.type, 'object', 'input_schema preserved');
  console.log('PASS Anthropic wire request/response including tool_use and tool_result');

  // 5. HTTP failures keep the server message and use E_MODEL_UNAVAILABLE.
  box.expectHttp({
    status: 401,
    body: JSON.stringify({ error: { message: 'invalid api key' } })
  });
  await rejects(chat({ messages: [{ role: 'user', content: 'hi' }] }), PluginErrorCode.MODEL_UNAVAILABLE,
    'HTTP 401 mapped');
  box.expectHttp({
    status: 401,
    body: JSON.stringify({ error: { message: 'invalid api key' } })
  });
  await assert.rejects(chat({ messages: [{ role: 'user', content: 'hi' }] }), (error) => {
    ok(String(error.message).includes('invalid api key'), 'server detail is preserved');
    return true;
  });
  box.expectHttp({ throws: 'socket hang up' });
  await rejects(chat({ messages: [{ role: 'user', content: 'hi' }] }), PluginErrorCode.MODEL_UNAVAILABLE,
    'network failure mapped');
  console.log('PASS HTTP and transport failures map to E_MODEL_UNAVAILABLE');

  // 6. Quotas and argument validation happen before any network call.
  const before = box.state.httpRequests.length;
  await rejects(chat({ messages: [] }), PluginErrorCode.INVALID_ARGUMENT, 'empty messages');
  const tooMany = [];
  for (let index = 0; index < 200; index += 1) {
    tooMany.push({ role: 'user', content: `m${index}` });
  }
  await rejects(chat({ messages: tooMany }), PluginErrorCode.RATE_LIMITED, 'message cap');
  eq(box.state.httpRequests.length, before, 'no HTTP request for rejected input');
  console.log('PASS message quotas are enforced before the network call');

  // 7. Capability gate: ai.* requires ai.inference before the service runs.
  PluginRpcDispatcher.setContext(box.contexts);
  const session = new PluginSession();
  session.pluginId = 'example.ai';
  session.capabilities = [PluginCapability.UI_NOTICE];
  const request = new PluginRpcRequest();
  request.id = 'ai-1'; request.pluginId = 'example.ai'; request.method = PluginRpcMethod.AI_STATUS; request.params = '{}';
  await rejects(PluginRpcDispatcher.dispatch(session, request), PluginErrorCode.PERMISSION_DENIED,
    'ai.status needs ai.inference');
  console.log('PASS ai.* is capability gated');

  // 8. Clearing the binding removes the key.
  const cleared = JSON.parse(await PluginAiService.configure(JSON.stringify({ clear: true })));
  eq(cleared.configured, false, 'clear resets the binding');
  await rejects(chat({ messages: [{ role: 'user', content: 'hi' }] }), PluginErrorCode.MODEL_UNAVAILABLE,
    'chat refuses again');
  console.log('PASS clearing the binding revokes model access');

  console.log(`\nplugin-ai-regression: ${assertions} assertions passed`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
