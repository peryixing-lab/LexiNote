'use strict';
const assert = require('node:assert/strict');
const { STORAGE_KEY, STORAGE_CHAR_BUDGET, createSession, createMessage, loadSession, saveSession,
  listConversations, selectConversation, deleteConversation, historyNotice, ensureSystem } = require('../src/session');
const { createLocalContext, compactLookups } = require('../src/local-store');
const copy = value => JSON.parse(JSON.stringify(value));
const data = new Map();
let failWrites = false;
let writing = 0;
let maxWriting = 0;
const makeContext = () => createLocalContext({ log() {}, storage: {
  async get(key) { return data.has(key) ? copy(data.get(key)) : null; },
  async set(key, value) {
    writing++; maxWriting = Math.max(maxWriting, writing);
    try {
      await new Promise(resolve => setTimeout(resolve, 1));
      if (failWrites) { throw Error('测试存储不可写'); }
      data.set(key, copy(value));
    } finally { writing--; }
  },
  async remove(key) { data.delete(key); }
} });
const conversation = label => {
  const session = createSession(); session.title = label;
  ensureSystem(session, '系统提示');
  session.messages.push(createMessage('user', label), createMessage('assistant', `${label} 的回答`));
  return session;
};
(async () => {
  const legacy = conversation('旧版对话');
  data.set(STORAGE_KEY, copy(legacy));
  let ctx = makeContext();
  let first = await loadSession(ctx);
  assert.equal(first.id, legacy.id);
  assert.equal((await listConversations(ctx)).length, 1);
  first.draft = '稍后继续的问题';
  await saveSession(ctx, first, { strict: true });
  const second = conversation('第二段');
  await saveSession(ctx, second, { strict: true });
  assert.equal((await listConversations(ctx)).length, 2);
  const resumed = await selectConversation(ctx, first.id);
  assert.equal(resumed.draft, first.draft);
  assert.ok(resumed.messages.some(message => message.content === '旧版对话 的回答'));
  // Restored sessions must not mutate the persisted/cached snapshot before a save.
  resumed.messages[0].content = '尚未保存的系统提示';
  assert.notEqual((await loadSession(ctx)).messages[0].content, resumed.messages[0].content);
  ctx = makeContext();
  assert.equal((await loadSession(ctx)).draft, first.draft, 'current conversation and draft survive plugin restart');
  failWrites = true;
  await assert.rejects(selectConversation(ctx, second.id), /存储不可写/);
  assert.equal((await loadSession(ctx)).id, first.id);
  await assert.rejects(deleteConversation(ctx, first.id), /存储不可写/);
  assert.equal((await listConversations(ctx)).length, 2);
  assert.equal(await saveSession(ctx, conversation('失败的新对话')), false);
  assert.ok(historyNotice(ctx).includes('保存失败'));
  failWrites = false;
  await saveSession(ctx, await loadSession(ctx), { strict: true });
  assert.equal(historyNotice(ctx), '');
  await deleteConversation(ctx, second.id);
  assert.equal((await listConversations(ctx)).length, 1);
  await deleteConversation(ctx, first.id);
  assert.equal((await listConversations(ctx)).length, 0);
  ctx = makeContext();
  assert.equal((await listConversations(ctx)).length, 0, 'deleted conversations stay deleted after restart');

  for (let index = 0; index < 25; index++) { await saveSession(ctx, conversation(`短对话${index}`), { strict: true }); }
  assert.equal((await listConversations(ctx)).length, 20);
  assert.ok(data.get(STORAGE_KEY).evicted >= 5);
  for (let index = 0; index < 10; index++) {
    const session = conversation(`长对话${index}`);
    session.messages.push(createMessage('assistant', '', { toolCalls: [{ id: 'tool-1', name: 'read_note', arguments: JSON.stringify({ path: 'a'.repeat(5000) }) }] }),
      createMessage('tool', '结果'.repeat(9000), { toolCallId: 'tool-1', toolName: 'read_note' }),
      createMessage('assistant', '最后回答'.repeat(3000)));
    await saveSession(ctx, session, { strict: true });
  }
  const record = data.get(STORAGE_KEY);
  assert.ok(JSON.stringify(record).length <= STORAGE_CHAR_BUDGET);
  for (const entry of [record, ...record.history]) {
    const calls = new Set();
    for (const message of entry.messages) {
      for (const call of message.toolCalls || []) { JSON.parse(call.arguments); calls.add(call.id); }
      if (message.role === 'tool') { assert.ok(calls.has(message.toolCallId), 'trimming never leaves orphan tool results'); }
    }
  }
  data.set('harness.models.v1', { old: ['m'.repeat(26000)], keep: ['model'] });
  data.set('harness.services.v1', { old: 'a'.repeat(11000), keep: '名称' });
  await compactLookups(ctx);
  assert.deepEqual(data.get('harness.models.v1'), { keep: ['model'] });
  assert.deepEqual(data.get('harness.services.v1'), { keep: '名称' });
  await Promise.all([ctx.storage.set('one', {}), ctx.storage.set('two', {}), saveSession(ctx, conversation('并行保存'), { strict: true })]);
  assert.equal(maxWriting, 1, 'all plugin storage writes are serialized across keys');
  data.set(STORAGE_KEY, { messages: 'damaged', title: '不要覆盖' });
  await assert.rejects(loadSession(makeContext()), /格式损坏/);
  assert.equal(data.get(STORAGE_KEY).title, '不要覆盖');
  assert.notEqual(createSession().id, createSession().id);
  console.log('PASS history: legacy migration, draft restore, restart, atomic failures, deletion, retention, tool pairing, quotas and serialized writes');
})().catch(error => { console.error(error); process.exitCode = 1; });
