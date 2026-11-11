// P06 · dynamic command registry regression (does not touch the static LEXI_COMMANDS table).
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { LEXI_COMMANDS } = box.load('core/LexiCommands');
const { PluginCommandRegistry } = box.load('plugin/core/PluginCommandRegistry');
const { PluginLimits } = box.load('plugin/model/PluginModels');

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };
function throwsCode(fn, code, message) {
  assertions++;
  assert.throws(fn, (error) => String(error.message).startsWith(code), message);
}

(async () => {
  const builtinCount = LEXI_COMMANDS.length;
  const builtinIds = LEXI_COMMANDS.map((command) => command.id);
  const frozen = JSON.stringify(LEXI_COMMANDS);

  PluginCommandRegistry.reset();

  // 1. Registration is namespaced, so two plugins may reuse the same local id.
  const a = PluginCommandRegistry.register('example.a', 'today', '创建今日笔记', async () => {});
  const b = PluginCommandRegistry.register('example.b', 'today', '另一家的今日笔记', async () => {});
  eq(a, 'example.a:today', 'qualified id');
  eq(b, 'example.b:today', 'the same local id is fine for another plugin');
  eq(PluginCommandRegistry.visible().length, 2, 'both commands are visible');
  err: {
    assertions++;
    assert.throws(() => PluginCommandRegistry.register('example.a', 'today', '重复', async () => {}),
      (error) => String(error.message).startsWith('E_INVALID_ARGUMENT'));
  }
  console.log('PASS plugin commands are namespaced and duplicate qualified ids are refused');

  // 2. Built-in command ids are reserved.
  for (const reserved of ['save', 'new', 'daily', 'palette']) {
    throwsCode(() => PluginCommandRegistry.register('example.a', reserved, '抢占用', async () => {}),
      'E_INVALID_ARGUMENT', `built-in id ${reserved} must stay reserved`);
  }
  throwsCode(() => PluginCommandRegistry.register('example.a', 'Bad Id', '空格', async () => {}),
    'E_INVALID_ARGUMENT', 'invalid characters are refused');
  throwsCode(() => PluginCommandRegistry.register('example.a', 'ok-id', '  ', async () => {}),
    'E_INVALID_ARGUMENT', 'empty titles are refused');
  console.log('PASS built-in ids stay reserved and malformed ids are rejected');

  // 3. Invocation dispatches to the owning plugin.
  const calls = [];
  PluginCommandRegistry.reset();
  PluginCommandRegistry.register('example.a', 'one', '第一', async () => { calls.push('one'); });
  PluginCommandRegistry.register('example.a', 'two', '第二', async () => { calls.push('two'); });
  await PluginCommandRegistry.invoke('example.a:one');
  eq(calls, ['one'], 'only the requested command ran');
  await assert.rejects(PluginCommandRegistry.invoke('example.a:nope'),
    (error) => String(error.message).startsWith('E_NOT_FOUND'));
  console.log('PASS invoking a command runs exactly the owning handler');

  // 4. Unregistering a plugin removes every command immediately (no ghost commands).
  eq(PluginCommandRegistry.countForPlugin('example.a'), 2, 'two commands owned');
  eq(PluginCommandRegistry.unregisterPlugin('example.a'), 2, 'both removed');
  eq(PluginCommandRegistry.countForPlugin('example.a'), 0, 'none left');
  eq(PluginCommandRegistry.isPluginCommand('example.a:one'), false, 'no longer resolvable');
  PluginCommandRegistry.setAvailable('example.b', false);
  eq(PluginCommandRegistry.visible().some((entry) => entry.pluginId === 'example.b'), false, 'disabled plugins are hidden');
  console.log('PASS disabling or uninstalling a plugin removes its commands immediately');

  // 5. Per-plugin quota.
  PluginCommandRegistry.reset();
  for (let index = 0; index < PluginLimits.MAX_COMMANDS_PER_PLUGIN; index++) {
    PluginCommandRegistry.register('example.big', `cmd-${index}`, `命令 ${index}`, async () => {});
  }
  throwsCode(() => PluginCommandRegistry.register('example.big', 'overflow', '溢出', async () => {}),
    'E_QUOTA_EXCEEDED', 'command quota is enforced');
  console.log('PASS per-plugin command quota is enforced');

  // 6. The static built-in table is untouched.
  eq(LEXI_COMMANDS.length, builtinCount, 'built-in command count unchanged');
  eq(LEXI_COMMANDS.map((command) => command.id), builtinIds, 'built-in ids unchanged');
  eq(JSON.stringify(LEXI_COMMANDS), frozen, 'built-in table byte-identical');
  console.log('PASS the static LEXI_COMMANDS table is never modified');

  console.log(`\nplugin-command-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
