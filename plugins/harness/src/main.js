'use strict';

const { definePlugin } = require('@lexinote/sdk');
const {
  loadSession,
  saveSession,
  createSession,
  ensureSystem,
  buildSystemPrompt
} = require('./session');
const { createViewController } = require('./view');
const { loadChanges } = require('./changes');
const { createProfileContext } = require('./profile-store');
const { createLocalContext, compactLookups } = require('./local-store');
let cleanupController = null;

/**
 * Harness — a standalone LexiNote agent plugin.
 *
 * What lives here: the agent loop, tools, skills, session persistence and chat view.
 * What lives in the host: model transport (`ai.inference`), the active API binding, the plugin
 * WebView and the sidebar surface (`ui.views`). Removing this plugin removes the agent;
 * the host has no fallback chat.
 */
module.exports = definePlugin({
  async activate(ctx) {
    // Fail fast with the code the plugin panel already understands, instead of booting
    // without the capabilities that make the view/commands useful.
    const required = ['ai.inference', 'ui.views', 'plugin.storage'];
    const missing = required.filter((capability) => !ctx.capabilities.has(capability));
    if (missing.length > 0) {
      throw new Error(`E_PERMISSION_DENIED: Harness 需要能力 ${missing.join('、')}；` +
        '请在 设置 → 插件 → Harness → 能力与诊断 中授权后重试');
    }

    ctx = createProfileContext(createLocalContext(ctx));
    await compactLookups(ctx);

    const holder = {
      session: await loadSession(ctx),
      changesStore: await loadChanges(ctx)
    };
    ensureSystem(holder.session, buildSystemPrompt(ctx));
    const controller = createViewController(ctx, holder);
    cleanupController = controller;

    function subscribeContextEvent(eventName, requiredCapability) {
      if (!ctx.events || typeof ctx.events.on !== 'function') { return; }
      if (requiredCapability && !ctx.capabilities.has(requiredCapability)) { return; }
      try {
        const sub = ctx.events.on(eventName, () => {
          controller.scheduleContextRefresh();
        });
        if (sub && sub.ready && typeof sub.ready.catch === 'function') {
          sub.ready.catch(() => {});
        }
        ctx.subscriptions.add(sub);
      } catch (_error) {}
    }

    subscribeContextEvent('workspace.active-file-changed', 'workspace.views');
    subscribeContextEvent('editor.changed', 'editor.read');
    subscribeContextEvent('vault.created', 'vault.read');
    subscribeContextEvent('vault.modified', 'vault.read');
    subscribeContextEvent('vault.renamed', 'vault.read');
    subscribeContextEvent('vault.deleted', 'vault.read');

    const view = ctx.views.register({
      id: 'harness',
      title: 'Harness',
      render(container) {
        return controller.mount(container);
      }
    });
    ctx.subscriptions.add(view);

    if (ctx.capabilities.has('ui.commands')) {
      ctx.subscriptions.add(ctx.commands.register({
        id: 'harness-open',
        title: 'Harness：打开对话',
        run: async () => {
          await view.ready;
          await ctx.views.open('harness');
        }
      }));

      ctx.subscriptions.add(ctx.commands.register({
        id: 'harness-new-session',
        title: 'Harness：新建会话',
        run: async () => {
          const created = await controller.resetSession();
          await view.ready;
          await ctx.views.open('harness');
          if (created) { controller.notify('已新建 Harness 会话'); }
        }
      }));

      ctx.subscriptions.add(ctx.commands.register({
        id: 'harness-organize-active',
        title: 'Harness：整理当前笔记',
        run: async () => {
          await view.ready;
          await ctx.views.open('harness');
          let prompt = '请先调用 get_workspace_status 了解当前工作区，再告诉我可以从哪里开始。';
          try {
            const active = await ctx.workspace.activeFile();
            if (active && active.path) {
              prompt = `请先读取并引用「${active.path}」，给出摘要、结构问题与行动项。`;
            }
          } catch (error) {
            ctx.log('warn', `读取活动笔记失败：${(error && error.message) || error}`);
          }
          await controller.send(prompt);
          controller.notify('Harness 已完成本轮整理');
        }
      }));
    }

    await saveSession(ctx, holder.session);
    ctx.log('info', 'Harness 已启用：模型请求由宿主代办，插件不联网');
  },

  async deactivate() {
    if (cleanupController) { await cleanupController.dispose(); cleanupController = null; }
    // Subscriptions (view, commands) are released by the SDK in reverse order.
  }
});
