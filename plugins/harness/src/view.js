'use strict';

const { runTurn, stopTurn } = require('./agent');
const { createSession, ensureSystem, buildSystemPrompt, saveSession, listConversations,
  selectConversation, deleteConversation, historyNotice } = require('./session');
const { clip, text, errorText } = require('./util');
const { renderMarkdown } = require('./markdown');
const { serviceName } = require('./providers');

/**
 * The Harness chat view.
 *
 * Rendered inside the plugin runtime WebView via `ctx.views.register`. All text is
 * written with `textContent`; Markdown is parsed into safe DOM nodes. The controller
 * survives view remounts because the session lives in the
 * plugin instance, not in the DOM.
 */

const STYLE = `
.harness-root { position:relative; display:flex; flex-direction:column; height:100%; min-height:0;
  color:var(--text-normal,#2f2b35); background:var(--background-primary,#f7f5f8);
  font:13px/1.55 -apple-system,BlinkMacSystemFont,"HarmonyOS Sans SC","PingFang SC",sans-serif; }
.harness-header { display:flex; align-items:center; gap:8px; padding:10px 12px;
  border-bottom:1px solid var(--background-modifier-border,#e1dce6); flex:0 0 auto; }
.harness-title { font-weight:600; font-size:13px; }
.harness-dot { width:7px; height:7px; border-radius:50%; background:var(--text-faint,#a9a2b3); flex:0 0 auto; }
.harness-dot.on { background:#3fa675; }
.harness-sub { color:var(--text-muted,#827b87); font-size:11px; min-width:0; overflow:hidden;
  text-overflow:ellipsis; white-space:nowrap; flex:1; }
.harness-actions { display:flex; gap:4px; flex:0 0 auto; }
.harness-btn { border:1px solid var(--background-modifier-border,#e1dce6); border-radius:6px;
  background:transparent; color:inherit; padding:4px 8px; font-size:11px; cursor:pointer; }
.harness-btn:hover { background:var(--background-secondary,#eeeaf1); }
.harness-btn.primary { background:#8c7eab; border-color:#8c7eab; color:#fff; }
.harness-btn:disabled { opacity:.45; cursor:default; }
.harness-messages { flex:1 1 auto; min-height:0; overflow-y:auto; padding:12px 12px 4px; }
.harness-empty { color:var(--text-muted,#827b87); font-size:12px; line-height:1.7; padding:6px 2px 12px; }
.harness-chips { display:flex; flex-wrap:wrap; gap:6px; margin-top:10px; }
.harness-chip { border:1px dashed var(--background-modifier-border,#d9d2e0); border-radius:999px;
  padding:4px 9px; font-size:11px; cursor:pointer; color:var(--text-accent,#807397); background:transparent; }
.harness-chip:hover { background:var(--background-secondary,#eeeaf1); }
.harness-msg { margin:0 0 10px; }
.harness-msg-user { display:flex; justify-content:flex-end; }
.harness-bubble { max-width:88%; padding:7px 10px; border-radius:10px; background:var(--background-secondary,#eeeaf1);
  white-space:pre-wrap; word-break:break-word; }
.harness-msg-user .harness-bubble { background:#8c7eab; color:#fff; }
.harness-msg-assistant .harness-bubble { background:transparent; padding:0 2px; max-width:100%; }
.harness-markdown { white-space:normal; overflow-wrap:anywhere; min-width:0; }
.harness-markdown p { margin:0 0 .7em; }
.harness-markdown > :last-child { margin-bottom:0; }
.harness-markdown h1,.harness-markdown h2,.harness-markdown h3,
.harness-markdown h4,.harness-markdown h5,.harness-markdown h6 { font-size:1.08em; line-height:1.45; margin:1em 0 .5em; }
.harness-markdown ul,.harness-markdown ol { padding-left:1.6em; margin:.4em 0 .8em; }
.harness-markdown li > p { margin:0 0 .3em; }
.harness-markdown li.harness-task-item { list-style:none; margin-left:-1.3em; }
.harness-markdown li input { margin:0 .4em 0 0; accent-color:#8c7eab; }
.harness-markdown code { font: .9em/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;
  background:var(--background-secondary,#eeeaf1); border-radius:4px; padding:.1em .3em; white-space:pre-wrap; }
.harness-markdown pre { max-width:100%; overflow:auto; padding:10px; border-radius:7px;
  background:var(--background-secondary,#eeeaf1); }
.harness-markdown pre code { white-space:pre; padding:0; background:transparent; }
.harness-markdown blockquote { margin:.7em 0; padding-left:10px; border-left:3px solid #8c7eab; color:var(--text-muted,#827b87); }
.harness-markdown a { color:var(--text-accent,#807397); text-decoration:underline; cursor:pointer; }
.harness-markdown table { display:block; overflow:auto; border-collapse:collapse; margin:.7em 0; }
.harness-markdown th,.harness-markdown td { border:1px solid var(--background-modifier-border,#e1dce6); padding:5px 8px; }
.harness-reasoning { margin:2px 0 6px; color:var(--text-muted,#827b87); font-size:11.5px; }
.harness-reasoning summary { cursor:pointer; }
.harness-tool { border:1px solid var(--background-modifier-border,#e1dce6); border-radius:8px;
  padding:6px 8px; margin:0 0 8px; background:rgba(140,126,171,.06); }
.harness-tool-head { display:flex; gap:8px; align-items:baseline; }
.harness-tool-name { font-size:11.5px; font-weight:600; color:var(--text-accent,#807397); }
.harness-tool-sub { font-size:11px; color:var(--text-muted,#827b87); overflow:hidden;
  text-overflow:ellipsis; white-space:nowrap; flex:1; }
.harness-tool-open { border:0; background:transparent; color:var(--text-muted,#827b87); font-size:11px; cursor:pointer; }
.harness-tool-body { margin:6px 0 0; padding:8px; border-radius:6px; background:var(--background-primary,#f7f5f8);
  font:11px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; white-space:pre-wrap; word-break:break-word;
  max-height:240px; overflow:auto; }
.harness-tool.error { border-color:rgba(211,75,102,.45); }
.harness-tool.error .harness-tool-name { color:#d34b66; }
.harness-status { display:flex; align-items:center; gap:6px; color:var(--text-muted,#827b87);
  font-size:11.5px; padding:0 2px 10px; }
.harness-spinner { width:8px; height:8px; border-radius:50%; background:#8c7eab;
  animation:harness-pulse 1s ease-in-out infinite; }
@keyframes harness-pulse { 0%,100%{opacity:.25;transform:scale(.8)} 50%{opacity:1;transform:scale(1)} }
.harness-error { border:1px solid rgba(211,75,102,.4); color:#b03b54; border-radius:8px;
  padding:7px 9px; font-size:11.5px; margin:0 0 10px; white-space:pre-wrap; }
.harness-todos { border-left:2px solid #8c7eab; padding:4px 0 4px 9px; margin:0 0 12px; color:var(--text-muted,#827b87); font-size:11.5px; }
.harness-todos b { color:var(--text-normal,#2f2b35); font-weight:600; }
.harness-composer { flex:0 0 auto; border-top:1px solid var(--background-modifier-border,#e1dce6);
  padding:8px 10px 10px; display:flex; flex-direction:column; gap:6px; }
.harness-input { width:100%; box-sizing:border-box; resize:none; min-height:44px; max-height:120px;
  border:1px solid var(--background-modifier-border,#e1dce6); border-radius:8px; padding:8px 9px;
  background:var(--background-primary,#f7f5f8); color:inherit; font:inherit; font-size:13px; line-height:1.5; outline:none; }
.harness-input:focus { border-color:#8c7eab; }
.harness-compose-row { display:flex; align-items:center; gap:6px; }
.harness-toolbar { display:flex; align-items:center; flex-wrap:wrap; gap:6px; }
.harness-model-trigger { display:flex; align-items:center; justify-content:space-between; gap:10px;
  flex:1; min-width:0; min-height:48px; padding:7px 10px; text-align:left; border-radius:10px;
  border:1px solid var(--background-modifier-border,#e1dce6); background:var(--background-primary,#f7f5f8); color:inherit; cursor:pointer; }
.harness-model-trigger:disabled { opacity:.55; cursor:default; }
.harness-model-trigger-copy { display:flex; flex-direction:column; gap:1px; min-width:0; }
.harness-provider-name { color:var(--text-accent,#807397); font-size:10px; line-height:1.4; font-weight:600; }
.harness-current-model { color:var(--text-normal,#2f2b35); font-size:12px; line-height:1.5;
  font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-switch-label { flex:0 0 auto; color:var(--text-muted,#827b87); font-size:10px; }
.harness-toolbar > .harness-btn { min-height:34px; border-radius:8px; padding:6px 9px; }
.harness-model-trigger:focus-visible,.harness-model-option:focus-visible,.harness-btn:focus-visible {
  outline:2px solid var(--interactive-accent,#8c7eab); outline-offset:2px; }
.harness-quota { font-size:11px; color:var(--text-muted,#827b87); padding:9px 10px;
  background:var(--background-secondary,#eeeaf1); border-radius:9px; }
.harness-quota:empty,.harness-toolbar-error:empty { display:none; }
.harness-quota p { margin:3px 0; }
.harness-quota progress { width:100%; height:5px; accent-color:#8c7eab; }
.harness-toolbar-error { font-size:11px; color:#b03b54; white-space:pre-wrap; }
.harness-hint { flex:1; color:var(--text-faint,#a9a2b3); font-size:10.5px; }
.harness-setup { border:1px solid var(--background-modifier-border,#e1dce6); border-radius:8px;
  padding:10px; margin:0 0 12px; background:var(--background-secondary,#eeeaf1); }
.harness-setup b { display:block; margin-bottom:4px; }
.harness-setup p { margin:0 0 8px; color:var(--text-muted,#827b87); font-size:11.5px; }
.harness-overlay { position:absolute; inset:0; box-sizing:border-box; background:rgba(20,18,24,.28); display:flex;
  align-items:flex-start; justify-content:center; padding:14px; z-index:5; overflow:auto; }
.harness-settings { width:100%; min-width:0; box-sizing:border-box; max-width:360px; background:var(--background-primary,#f7f5f8);
  border:1px solid var(--background-modifier-border,#e1dce6); border-radius:10px; padding:12px;
  box-shadow:0 18px 40px rgba(0,0,0,.18); }
.harness-settings h3 { margin:0 0 4px; font-size:13px; }
.harness-settings p { margin:0 0 10px; color:var(--text-muted,#827b87); font-size:11px; line-height:1.5; }
.harness-field { display:flex; flex-direction:column; gap:3px; margin:0 0 8px; }
.harness-field label { font-size:11px; color:var(--text-muted,#827b87); }
.harness-field input,.harness-field select { width:100%; min-width:0; box-sizing:border-box; border:1px solid var(--background-modifier-border,#e1dce6);
  border-radius:6px; padding:6px 7px; background:var(--background-primary,#f7f5f8); color:inherit;
  font:inherit; font-size:12px; line-height:1.4; outline:none; }
.harness-field input:focus,.harness-field select:focus { border-color:#8c7eab; }
.harness-settings-actions { display:flex; gap:6px; justify-content:flex-end; margin-top:6px; }
.harness-settings-error { color:#b03b54; font-size:11px; margin:2px 0 6px; white-space:pre-wrap; }
.harness-models { border-radius:14px; padding:16px; }
.harness-models-head { display:flex; align-items:center; justify-content:space-between; gap:8px; margin-bottom:16px; }
.harness-models-head h3 { margin:0; font-size:15px; font-weight:600; }
.harness-models-head .harness-btn { border:0; color:var(--text-muted,#827b87); }
.harness-models-service { padding:12px; border:1px solid var(--background-modifier-border,#e1dce6);
  border-radius:10px; margin-bottom:12px; background:var(--background-secondary,#eeeaf1); }
.harness-models-service b { display:block; font-size:14px; font-weight:600; overflow-wrap:anywhere; }
.harness-models-service p { margin:5px 0 0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-models-service .harness-service-protocol { font-size:10px; margin-top:2px; }
.harness-models-service .harness-service-model { color:var(--text-normal,#2f2b35); margin-top:10px; font-size:12px; }
.harness-models-actions { display:flex; gap:6px; margin-bottom:16px; }
.harness-models-actions .harness-btn { min-height:32px; padding:6px 10px; border-radius:7px; }
.harness-models-list { display:flex; flex-direction:column; gap:6px; max-height:320px; overflow:auto; }
.harness-model-option { display:flex; align-items:center; justify-content:space-between; gap:8px; width:100%;
  min-height:44px; padding:10px; border:1px solid var(--background-modifier-border,#e1dce6); border-radius:8px;
  color:inherit; background:transparent; text-align:left; cursor:pointer; }
.harness-model-option span:first-child { min-width:0; overflow-wrap:anywhere; font-size:12px; }
.harness-model-option.selected { border-color:#8c7eab; background:rgba(140,126,171,.09); }
.harness-model-option:disabled { cursor:default; opacity:.65; }
.harness-model-badge { flex:0 0 auto; font-size:10px; color:var(--text-accent,#807397); }
.harness-models-tip { margin:10px 0 0 !important; }
.harness-services-head { display:flex; align-items:center; justify-content:space-between; gap:8px; margin:0 0 8px; }
.harness-services-head b { font-size:11px; color:var(--text-muted,#827b87); font-weight:500; }
.harness-services-list { display:flex; flex-direction:column; gap:6px; max-height:190px; overflow:auto; margin:0 0 14px; }
.harness-service-row { display:flex; gap:4px; align-items:center; padding:4px; border:1px solid var(--background-modifier-border,#e1dce6); border-radius:9px; }
.harness-service-row.selected { border-color:#8c7eab; background:rgba(140,126,171,.06); }
.harness-service-choice { min-width:0; flex:1; text-align:left; border:0; background:transparent; color:inherit; cursor:pointer; padding:4px 6px; }
.harness-service-choice b,.harness-service-choice span { display:block; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-service-choice b { font-size:12px; font-weight:500; }
.harness-service-choice span { font-size:10px; color:var(--text-muted,#827b87); margin-top:2px; }
.harness-service-row > .harness-btn { padding:4px; font-size:10px; border:0; color:var(--text-muted,#827b87); }
.harness-remove-confirm { padding:10px; margin:0 0 12px; background:var(--background-secondary,#eeeaf1); border-radius:8px; }
.harness-remove-confirm p { margin:0 0 8px; }
.harness-history-search { width:100%; box-sizing:border-box; border:1px solid var(--background-modifier-border,#e1dce6);
  padding:9px 10px; margin:0 0 12px; border-radius:8px; background:transparent; color:inherit; font:inherit; outline:none; }
.harness-history-search:focus { border-color:#8c7eab; }
.harness-history-list { display:flex; flex-direction:column; gap:7px; max-height:400px; overflow:auto; }
.harness-history-row { display:flex; align-items:center; gap:4px; padding:5px;
  border:1px solid var(--background-modifier-border,#e1dce6); border-radius:10px; }
.harness-history-row.selected { border-color:#8c7eab; background:rgba(140,126,171,.06); }
.harness-history-choice { flex:1; min-width:0; border:0; padding:6px; background:transparent; color:inherit; text-align:left; cursor:pointer; }
.harness-history-choice b,.harness-history-choice span { display:block; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-history-choice b { font-size:12px; font-weight:500; }
.harness-history-choice .harness-history-preview { font-size:11px; color:var(--text-muted,#827b87); margin:4px 0; }
.harness-history-meta { font-size:10px; color:var(--text-faint,#a9a2b3); }
.harness-history-row > .harness-btn { border:0; color:var(--text-muted,#827b87); padding:6px; }
.harness-history-empty { padding:22px 8px; text-align:center; }
@media (hover:hover) and (pointer:fine) {
  .harness-model-trigger:hover,.harness-model-option:hover { background:var(--background-secondary,#eeeaf1); }
}
@media (prefers-reduced-motion:reduce) { .harness-spinner { animation:none; } }
`;

function element(tag, className, content) {
  const node = document.createElement(tag);
  if (className) { node.className = className; }
  if (content !== undefined && content !== null) { node.textContent = String(content); }
  return node;
}

function button(label, className, onClick, disabled) {
  const node = element('button', `harness-btn${className ? ` ${className}` : ''}`, label);
  node.type = 'button';
  if (disabled) { node.disabled = true; }
  node.addEventListener('click', onClick);
  return node;
}

function createViewController(ctx, holder, options) {
  const settings = options && typeof options === 'object' ? options : {};
  let container = null;
  let dom = null;
  let busy = false;
  let status = null;
  let error = '';
  let pending = '';
  let activeTool = null;
  let showSettings = false;
  let showModels = false;
  let settingsReturnToModels = false;
  let modelsError = '';
  let settingsError = '';
  let settingsDraft = null;
  let settingsDirty = false;
  let saving = false;
  let switching = false;
  let loadingModels = false;
  let toolbarError = '';
  let modelLists = {};
  let serviceNames = {};
  let quota = null;
  let quotaOpen = false;
  let quotaLoading = false;
  let quotaError = '';
  let bindingRevision = 0;
  let profiles = [];
  let profilesAvailable = false;
  let profilesError = '';
  let checkingProfiles = false;
  let editingProfileId = '';
  let addingProfile = false;
  let pendingRemovalId = '';
  let showHistory = false;
  let historyEntries = [];
  let historyQuery = '';
  let historyError = '';
  let historyWorking = false;
  let historyRemovalId = '';
  let draftTimer = null;
  let draftDirty = false;
  let draftSaving = Promise.resolve();

  function legacyRoute(profile) {
    return profile ? `${profile.provider}|${profile.baseUrl}` : '';
  }

  function routeKey(profile) {
    const selected = profile || status;
    return selected ? (selected.profileId || legacyRoute(selected)) : '';
  }

  function modelNames(value) {
    return [...new Set((Array.isArray(value) ? value : text(value).split(/[,，\n]/))
      .map((name) => text(name).trim()).filter((name) => name.length > 0 && name.length <= 128))].slice(0, 300);
  }

  function currentModels(profile) {
    const selected = profile || status;
    return modelNames([selected && selected.model, ...(modelLists[routeKey(selected)] || modelLists[legacyRoute(selected)] || [])]);
  }

  function currentService() {
    return profileName(status);
  }

  function profileName(profile) {
    return serviceName(profile, profile && profile.name || serviceNames[routeKey(profile)] || serviceNames[legacyRoute(profile)]);
  }

  async function reloadProfiles() {
    const revision = bindingRevision;
    try {
      const catalog = await ctx.ai.profiles();
      if (revision !== bindingRevision) { return; }
      if (!catalog || !Array.isArray(catalog.profiles)) { throw new Error('宿主返回的服务商列表格式不正确'); }
      profiles = catalog.profiles;
      profilesAvailable = true;
      profilesError = '';
    } catch (failure) {
      if (revision === bindingRevision) {
        profilesAvailable = false;
        const detail = errorText(failure);
        profilesError = `读取插件服务商配置失败：${detail}。请重试。`;
      }
    }
  }

  async function rememberService(name, profile) {
    const selected = profile || status;
    const key = routeKey(selected);
    const next = {};
    for (const route of Object.keys(serviceNames).filter((route) => route !== key).slice(-11)) {
      next[route] = serviceNames[route];
    }
    const label = text(name).trim().slice(0, 64);
    if (label) { next[key] = label; }
    if (selected && selected.profileId) { delete next[legacyRoute(selected)]; }
    while (JSON.stringify(next).length > 10000 && Object.keys(next).length) { delete next[Object.keys(next)[0]]; }
    serviceNames = next;
    await ctx.storage.set('harness.services.v1', next);
  }

  async function rememberModels(names, profile) {
    const key = routeKey(profile);
    modelLists[key] = modelNames(names);
    // Bound storage across service changes; keys and credentials never go here.
    const routes = Object.keys(modelLists).filter((route) => route !== key).slice(-11);
    routes.push(key);
    const next = {};
    for (const route of routes) { next[route] = modelLists[route]; }
    while (JSON.stringify(next).length > 24000 && Object.keys(next).length > 1) {
      delete next[Object.keys(next)[0]];
    }
    while (JSON.stringify(next).length > 24000 && next[key].length > 1) { next[key].pop(); }
    modelLists = next;
    await ctx.storage.set('harness.models.v1', next);
  }

  function bindingChanged(next) {
    status = next;
    bindingRevision += 1;
    quota = null;
    quotaError = '';
    quotaLoading = false;
    pendingRemovalId = '';
  }

  function session() {
    return holder.session;
  }

  function scrollToBottom() {
    if (dom && dom.messages) {
      dom.messages.scrollTop = dom.messages.scrollHeight;
    }
  }

  function statusSubtitle() {
    if (!status) { return '检查模型绑定…'; }
    if (!status.configured) { return '未绑定模型'; }
    return `${currentService()} · ${status.model || '模型'}`;
  }

  function renderTodos() {
    const todos = session().todos;
    if (!Array.isArray(todos) || todos.length === 0) { return null; }
    const box = element('div', 'harness-todos');
    box.appendChild(element('b', '', '本次任务'));
    for (const todo of todos.slice(0, 8)) {
      const mark = todo.status === 'completed' ? '✓' : (todo.status === 'in_progress' ? '~' : '·');
      box.appendChild(element('div', '', `${mark} ${todo.content}`));
    }
    return box;
  }

  function renderMessage(message) {
    if (!message || message.role === 'system') { return null; }
    if (message.role === 'user') {
      const row = element('div', 'harness-msg harness-msg-user');
      row.appendChild(element('div', 'harness-bubble', message.content));
      return row;
    }
    if (message.role === 'assistant') {
      const row = element('div', 'harness-msg harness-msg-assistant');
      const bubble = element('div', 'harness-bubble');
      if (typeof message.reasoning === 'string' && message.reasoning.length > 0) {
        const details = element('details', 'harness-reasoning');
        details.appendChild(element('summary', '', '思考过程'));
        details.appendChild(element('div', '', clip(message.reasoning, 2000)));
        bubble.appendChild(details);
      }
      if (message.content && message.content.length > 0) {
        bubble.appendChild(renderMarkdown(message.content, async (href) => {
          try {
            if (!/^[a-z][a-z\d+.-]*:/i.test(href) && /\.md(?:#.*)?$/i.test(href)) {
              const file = await ctx.vault.get(decodeURIComponent(href.split('#')[0]));
              if (file) { await ctx.workspace.openFile(file); return; }
            }
            await ctx.ui.notice(href, 5000);
          } catch (failure) { toolbarError = errorText(failure); refresh(); }
        }));
      } else {
        bubble.appendChild(element('div', 'harness-tool-sub', '（调用工具）'));
      }
      row.appendChild(bubble);
      return row;
    }
    if (message.role === 'tool') {
      const row = element('div', `harness-tool${message.isError ? ' error' : ''}`);
      const head = element('div', 'harness-tool-head');
      head.appendChild(element('span', 'harness-tool-name', message.toolName || 'tool'));
      head.appendChild(element('span', 'harness-tool-sub', message.title || message.subtitle || ''));
      const toggle = element('button', 'harness-tool-open', '展开');
      toggle.type = 'button';
      const body = element('pre', 'harness-tool-body', message.content || '');
      body.style.display = 'none';
      toggle.addEventListener('click', () => {
        const visible = body.style.display !== 'none';
        body.style.display = visible ? 'none' : 'block';
        toggle.textContent = visible ? '展开' : '收起';
      });
      head.appendChild(toggle);
      row.appendChild(head);
      row.appendChild(body);
      return row;
    }
    return null;
  }

  function renderMessages() {
    if (!dom) { return; }
    dom.messages.replaceChildren();
    const todos = renderTodos();
    if (todos) { dom.messages.appendChild(todos); }
    const messages = session().messages;
    let hasUser = false;
    if (Array.isArray(messages)) {
      for (let index = 0; index < messages.length; index += 1) {
        const message = messages[index];
        if (message.role === 'user') { hasUser = true; }
        const node = renderMessage(message);
        if (node) { dom.messages.appendChild(node); }
      }
    }
    if (!hasUser) {
      dom.messages.appendChild(renderEmpty());
    }
    if (activeTool) {
      const row = element('div', 'harness-tool');
      const head = element('div', 'harness-tool-head');
      head.appendChild(element('span', 'harness-tool-name', activeTool.name));
      head.appendChild(element('span', 'harness-tool-sub', activeTool.summary || '正在执行…'));
      row.appendChild(head);
      dom.messages.appendChild(row);
    }
    if (pending.length > 0) {
      const statusRow = element('div', 'harness-status');
      statusRow.appendChild(element('span', 'harness-spinner'));
      statusRow.appendChild(element('span', '', pending));
      dom.messages.appendChild(statusRow);
    }
    if (error.length > 0) {
      dom.messages.appendChild(element('div', 'harness-error', error));
    }
    if (status && !status.configured) {
      dom.messages.appendChild(renderSetupHint());
    }
    scrollToBottom();
  }

  function renderEmpty() {
    const box = element('div', 'harness-empty');
    box.appendChild(element('div', '', '我是运行在知萤里的 Harness。可以帮你阅读、检索、整理和改写 Markdown 笔记。'));
    box.appendChild(element('div', '', '在下面输入问题，或从这些开始：'));
    const chips = element('div', 'harness-chips');
    const starters = [
      '整理当前笔记：先给摘要，再列出行动项',
      '做一份今日回顾，按修改时间找出今天改过的笔记',
      '找出与当前笔记相关的其他笔记，并给出双链建议'
    ];
    for (const starter of starters) {
      const chip = element('button', 'harness-chip', starter);
      chip.type = 'button';
      chip.addEventListener('click', () => {
        if (dom && dom.input) {
          dom.input.value = starter;
          trackDraft();
          dom.input.focus();
        }
      });
      chips.appendChild(chip);
    }
    box.appendChild(chips);
    return box;
  }

  function renderSetupHint() {
    const box = element('div', 'harness-setup');
    box.appendChild(element('b', '', '还没有绑定模型服务'));
    box.appendChild(element('p', '', 'Harness 需要模型才能对话。可添加多个服务商，配置和 Key 保存在本插件的本地数据中。'));
    box.appendChild(button('绑定模型', 'primary', () => openSettings()));
    return box;
  }

  function renderHeader() {
    const header = element('div', 'harness-header');
    const dot = element('span', `harness-dot${status && status.configured ? ' on' : ''}`);
    header.appendChild(dot);
    header.appendChild(element('span', 'harness-title', 'Harness'));
    header.appendChild(element('span', 'harness-sub', statusSubtitle()));
    const actions = element('div', 'harness-actions');
    actions.appendChild(button('历史', '', () => openHistory(), busy || switching || saving || historyWorking));
    actions.appendChild(button('模型', '', () => openModels(), busy || switching || saving || historyWorking));
    actions.appendChild(button('新会话', '', () => resetSession(), busy || switching || saving || historyWorking));
    header.appendChild(actions);
    return header;
  }

  function renderComposer() {
    const composer = element('div', 'harness-composer');
    const toolbar = element('div', 'harness-toolbar');
    const quotaPanel = element('div', 'harness-quota');
    const toolbarMessage = element('div', 'harness-toolbar-error');
    const input = element('textarea', 'harness-input');
    input.placeholder = '问 Harness，例如：整理当前笔记并给出行动项';
    input.rows = 2;
    input.value = session().draft || '';
    input.addEventListener('input', () => trackDraft());
    input.addEventListener('blur', () => { flushDraft().catch(() => {}); });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
        event.preventDefault();
        send(input.value);
      }
    });
    const row = element('div', 'harness-compose-row');
    const hint = element('span', 'harness-hint', 'Enter 发送 · Shift+Enter 换行');
    row.appendChild(hint);
    const sendButton = button('发送', 'primary', () => busy ? stop() : send(input.value));
    row.appendChild(sendButton);
    composer.appendChild(toolbar);
    composer.appendChild(quotaPanel);
    composer.appendChild(toolbarMessage);
    composer.appendChild(input);
    composer.appendChild(row);
    return { composer, input, toolbar, quotaPanel, toolbarMessage, sendButton };
  }

  function renderToolbar() {
    if (!dom) { return; }
    dom.toolbar.replaceChildren();
    const trigger = button('', 'harness-model-trigger', () => openModels(), busy || switching || saving || historyWorking);
    const configured = status && status.configured;
    const provider = configured ? currentService() : '模型服务';
    const model = configured ? status.model : '选择并配置模型';
    trigger.setAttribute('aria-label', `切换模型，服务商 ${provider}，当前模型 ${model}`);
    trigger.setAttribute('aria-haspopup', 'dialog');
    trigger.setAttribute('aria-expanded', String(showModels));
    trigger.setAttribute('title', `${provider} · ${model}`);
    const copy = element('span', 'harness-model-trigger-copy');
    copy.appendChild(element('span', 'harness-provider-name', provider));
    copy.appendChild(element('span', 'harness-current-model', model));
    trigger.appendChild(copy);
    trigger.appendChild(element('span', 'harness-switch-label', '切换'));
    dom.toolbar.appendChild(trigger);
    dom.toolbar.appendChild(button('余额 / 配额', '', () => {
      quotaOpen = !quotaOpen;
      refresh();
      if (quotaOpen) { fetchQuota(); }
    }, !status || !status.configured));
    dom.toolbarMessage.textContent = [toolbarError, historyNotice(ctx)].filter(Boolean).join('\n');
    dom.sendButton.textContent = busy ? '停止' : '发送';
    dom.sendButton.disabled = !busy && (switching || saving || historyWorking || !status || !status.configured);
    dom.quotaPanel.replaceChildren();
    if (!quotaOpen) { return; }
    if (quotaLoading) { dom.quotaPanel.appendChild(element('p', '', '正在查询余额 / 配额…')); }
    else if (quotaError) { dom.quotaPanel.appendChild(element('p', 'harness-toolbar-error', quotaError)); }
    else if (quota && quota.supported) {
      dom.quotaPanel.appendChild(element('p', '', quota.provider));
      for (const window of quota.windows || []) {
        const amount = typeof window.remainingValue === 'number'
          ? `${window.unit || ''} ${window.remainingValue.toFixed(4)}`
          : `剩余 ${Math.max(0, 100 - window.usedPercent).toFixed(1)}%`;
        dom.quotaPanel.appendChild(element('p', '', `${window.label}：${amount}`));
        if (typeof window.usedPercent === 'number') {
          const progress = element('progress');
          progress.max = 100;
          progress.value = Math.max(0, 100 - window.usedPercent);
          progress.setAttribute('aria-label', `${window.label}剩余`);
          dom.quotaPanel.appendChild(progress);
        }
        if (window.resetAt) {
          dom.quotaPanel.appendChild(element('p', '', `重置：${new Date(window.resetAt).toLocaleString()}`));
        }
      }
      dom.quotaPanel.appendChild(element('p', '', `更新：${new Date(quota.updatedAt).toLocaleTimeString()} · 查询缓存 60 秒`));
    } else if (quota) {
      dom.quotaPanel.appendChild(element('p', '', '此服务暂不支持余额查询。支持 DeepSeek、OpenRouter，以及 GLM / Kimi / MiniMax Coding Plan 官方地址。'));
    } else {
      dom.quotaPanel.appendChild(element('p', '', '点击刷新查询当前服务的余额 / 配额。'));
    }
    dom.quotaPanel.appendChild(button('刷新', '', () => fetchQuota(true), quotaLoading || switching || saving));
  }

  async function fetchModels() {
    if (loadingModels || busy || switching || saving) { return; }
    loadingModels = true;
    modelsError = '';
    const revision = bindingRevision;
    refresh();
    try {
      if (typeof ctx.ai.models !== 'function') { throw new Error('请更新知萤宿主以获取模型列表；也可在设置中填写常用模型'); }
      const models = await ctx.ai.models();
      if (revision !== bindingRevision) { return; }
      const names = modelNames(models);
      if (names.length === 0) { throw new Error('服务未返回模型，可在设置中手动填写常用模型'); }
      await rememberModels([...currentModels(), ...names]);
    } catch (failure) {
      if (revision === bindingRevision) { modelsError = errorText(failure); }
    } finally { loadingModels = false; refresh(); }
  }

  async function switchModel(model) {
    if (busy || switching || saving || !status || model === status.model) { return; }
    switching = true;
    toolbarError = '';
    modelsError = '';
    refresh();
    try {
      bindingChanged(await ctx.ai.configure({ model }));
      await reloadProfiles();
      if (quotaOpen) { fetchQuota(); }
    } catch (failure) {
      if (showModels) { modelsError = errorText(failure); }
      else { toolbarError = errorText(failure); }
    }
    finally { switching = false; refresh(); }
  }

  async function fetchQuota(force) {
    if (quotaLoading || !status || !status.configured) { return; }
    quotaLoading = true;
    quotaError = '';
    const revision = bindingRevision;
    refresh();
    try {
      if (typeof ctx.ai.balance !== 'function') { throw new Error('请更新知萤宿主以支持余额查询'); }
      const result = await ctx.ai.balance({ force: force === true });
      if (revision === bindingRevision) { quota = result; }
    } catch (failure) { if (revision === bindingRevision) { quotaError = errorText(failure); } }
    finally { if (revision === bindingRevision) { quotaLoading = false; refresh(); } }
  }

  function renderHistoryRows(list) {
    list.replaceChildren();
    const query = historyQuery.trim().toLowerCase();
    const entries = historyEntries.filter(entry => `${entry.title} ${entry.preview}`.toLowerCase().includes(query));
    if (!entries.length) {
      list.appendChild(element('p', 'harness-history-empty', historyWorking ? '正在读取…' : query ? '没有匹配的对话' : '发送消息后会自动保存，也会保留有内容的草稿。'));
    }
    for (const entry of entries) {
      const row = element('div', `harness-history-row${entry.current ? ' selected' : ''}`);
      const choice = element('button', 'harness-history-choice');
      choice.type = 'button';
      choice.disabled = historyWorking;
      choice.setAttribute('aria-label', `打开对话 ${entry.title}`);
      if (entry.current) { choice.setAttribute('aria-current', 'true'); }
      choice.appendChild(element('b', '', `${entry.current ? '当前 · ' : ''}${entry.title}`));
      choice.appendChild(element('span', 'harness-history-preview', `${entry.draft ? '有草稿 · ' : ''}${entry.preview}`));
      const date = new Date(entry.updatedAt).toLocaleString();
      choice.appendChild(element('span', 'harness-history-meta', `${date}${entry.model ? ` · ${entry.model}` : ''}${entry.trimmed ? ' · 部分内容已压缩' : ''}`));
      choice.addEventListener('click', () => resumeHistory(entry.id));
      row.appendChild(choice);
      const remove = button('删除', '', () => {
        historyRemovalId = entry.id; settingsDirty = true; refresh();
      }, historyWorking);
      remove.setAttribute('aria-label', `删除对话 ${entry.title}`);
      row.appendChild(remove);
      list.appendChild(row);
    }
  }

  function renderHistory() {
    const overlay = element('div', 'harness-overlay');
    const panel = element('div', 'harness-settings harness-models harness-history');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', '对话历史');
    const head = element('div', 'harness-models-head');
    head.appendChild(element('h3', '', '对话历史'));
    head.appendChild(button('关闭', '', () => { showHistory = false; settingsDirty = true; refresh(); }));
    panel.appendChild(head);
    const search = element('input', 'harness-history-search');
    search.type = 'search'; search.placeholder = '搜索对话'; search.value = historyQuery;
    search.setAttribute('aria-label', '搜索对话');
    panel.appendChild(search);
    const actions = element('div', 'harness-models-actions');
    actions.appendChild(button('新建对话', 'primary', () => resetSession(), historyWorking));
    panel.appendChild(actions);
    if (historyError) { panel.appendChild(element('div', 'harness-settings-error', historyError)); }
    const deleting = historyEntries.find(entry => entry.id === historyRemovalId);
    if (deleting) {
      const confirmation = element('div', 'harness-remove-confirm');
      confirmation.appendChild(element('p', '', `删除对话「${deleting.title}」？此操作不可恢复。`));
      confirmation.appendChild(button('取消删除', '', () => { historyRemovalId = ''; settingsDirty = true; refresh(); }, historyWorking));
      confirmation.appendChild(button('确认删除对话', '', () => removeHistory(deleting.id), historyWorking));
      panel.appendChild(confirmation);
    }
    const list = element('div', 'harness-history-list');
    list.setAttribute('aria-label', '已保存的对话');
    search.addEventListener('input', () => { historyQuery = search.value; renderHistoryRows(list); });
    renderHistoryRows(list);
    panel.appendChild(list);
    panel.appendChild(element('p', 'harness-models-tip', '本地最多保留 20 段对话；长对话保留最近内容，空间不足时清理最早历史。恢复后使用输入栏当前模型继续。'));
    overlay.appendChild(panel);
    return overlay;
  }

  function renderModels() {
    const overlay = element('div', 'harness-overlay');
    const panel = element('div', 'harness-settings harness-models');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', '模型管理');
    const head = element('div', 'harness-models-head');
    head.appendChild(element('h3', '', '模型'));
    head.appendChild(button('关闭', '', () => closeModels()));
    panel.appendChild(head);
    const servicesHead = element('div', 'harness-services-head');
    servicesHead.appendChild(element('b', '', '服务商'));
    servicesHead.appendChild(button(checkingProfiles ? '正在检查…' : '添加服务商', '', () => openAddProfile(),
      busy || switching || saving || checkingProfiles));
    panel.appendChild(servicesHead);
    const services = element('div', 'harness-services-list');
    services.setAttribute('aria-label', '已保存的服务商');
    for (const profile of profiles) {
      const selected = status && profile.profileId === status.profileId;
      const row = element('div', `harness-service-row${selected ? ' selected' : ''}`);
      const choice = element('button', 'harness-service-choice');
      choice.type = 'button';
      choice.disabled = busy || switching || saving;
      choice.setAttribute('aria-label', `使用服务商 ${profileName(profile)}`);
      choice.setAttribute('aria-pressed', String(!!selected));
      choice.appendChild(element('b', '', profileName(profile)));
      choice.appendChild(element('span', '', `${selected ? '当前使用 · ' : ''}${profile.model}${profile.needsApiKey ? ' · 需补填 Key' : ''}`));
      choice.addEventListener('click', () => selectProfile(profile.profileId));
      row.appendChild(choice);
      row.appendChild(button('编辑', '', () => openSettings(profile.profileId), busy || switching || saving));
      const remove = button('删除', '', () => { pendingRemovalId = profile.profileId; refresh(); }, busy || switching || saving);
      remove.setAttribute('aria-label', `删除服务商 ${profileName(profile)}`);
      row.appendChild(remove);
      services.appendChild(row);
    }
    if (profiles.length) { panel.appendChild(services); }
    const removing = profiles.find((profile) => profile.profileId === pendingRemovalId);
    if (removing) {
      const confirmation = element('div', 'harness-remove-confirm');
      confirmation.appendChild(element('p', '', `删除「${profileName(removing)}」及保存的 API Key？`));
      confirmation.appendChild(button('取消删除', '', () => { pendingRemovalId = ''; refresh(); }, saving));
      confirmation.appendChild(button('确认删除', '', () => removeProfile(removing.profileId), saving));
      panel.appendChild(confirmation);
    }
    const service = element('div', 'harness-models-service');
    service.appendChild(element('b', '', status && status.configured ? currentService() : '尚未绑定模型服务'));
    if (status && status.configured) {
      service.appendChild(element('p', 'harness-service-protocol', status.provider === 'anthropic-compatible' ? 'Anthropic 兼容接口' : 'OpenAI 兼容接口'));
      service.appendChild(element('p', '', status.baseUrl));
      service.appendChild(element('p', 'harness-service-model', `当前使用 · ${status.model}`));
    }
    panel.appendChild(service);
    const actions = element('div', 'harness-models-actions');
    actions.appendChild(button('配置服务', '', () => openSettings(), busy || switching || saving));
    actions.appendChild(button(loadingModels ? '获取中…' : '获取模型', 'primary', () => fetchModels(),
      busy || switching || loadingModels || saving || !status || !status.configured));
    panel.appendChild(actions);
    if (modelsError) { panel.appendChild(element('div', 'harness-settings-error', modelsError)); }
    if (modelsError && !profilesAvailable) {
      panel.appendChild(button('重试读取配置', '', () => openAddProfile(), busy || switching || saving || checkingProfiles));
    }
    const list = element('div', 'harness-models-list');
    list.setAttribute('aria-label', '可用模型');
    if (status && status.configured) {
      for (const model of currentModels()) {
        const selected = model === status.model;
        const row = element('button', `harness-model-option${selected ? ' selected' : ''}`);
        row.type = 'button';
        row.disabled = busy || switching || saving;
        row.setAttribute('aria-label', `切换到 ${model}`);
        row.setAttribute('aria-pressed', String(selected));
        row.appendChild(element('span', '', model));
        row.appendChild(element('span', 'harness-model-badge', selected ? '当前使用' : '切换'));
        row.addEventListener('click', () => switchModel(model));
        list.appendChild(row);
      }
    } else {
      list.appendChild(element('p', '', '先配置模型服务，再获取和选择模型。'));
    }
    panel.appendChild(list);
    panel.appendChild(element('p', 'harness-models-tip', '选择模型用于下一轮对话。也可在配置中手动填写常用模型。'));
    overlay.appendChild(panel);
    return overlay;
  }

  function renderOverlay() {
    if (showHistory) { return renderHistory(); }
    if (showModels) { return renderModels(); }
    if (!showSettings) { return null; }
    const overlay = element('div', 'harness-overlay');
    const panel = element('div', 'harness-settings harness-config');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', '模型服务设置');
    panel.appendChild(element('h3', '', addingProfile ? '添加服务商' : '编辑服务商'));
    const editing = addingProfile ? null : (profiles.find((profile) => profile.profileId === editingProfileId) || status);
    panel.appendChild(element('p', '',
      editing && editing.needsApiKey
        ? '此服务商还没有可用的 API Key。请补填一次；新宿主上 Key 只写不读回。'
        : '新宿主上 API Key 只写入宿主、保存后不可读回；旧宿主会保存在插件本地数据中。插件仅保存服务商配置。编辑时留空沿用；更换 Base URL 请重新填写。'));
    const draft = settingsDraft || {
      provider: editing && editing.provider ? editing.provider : 'openai-compatible',
      baseUrl: editing && editing.baseUrl ? editing.baseUrl : '',
      model: editing && editing.model ? editing.model : '',
      apiKey: '',
      quickModels: editing ? currentModels(editing).join(', ') : '',
      serviceName: editing && (editing.name || serviceNames[routeKey(editing)] || serviceNames[legacyRoute(editing)]) || ''
    };
    settingsDraft = draft;
    function track(node, name, event) {
      const labels = { serviceName: '服务商名称', provider: '接口类型', baseUrl: 'Base URL', model: '模型名称', apiKey: 'API Key', quickModels: '常用模型' };
      node.setAttribute('aria-label', labels[name] || name);
      node.addEventListener(event || 'input', () => { draft[name] = node.value; });
      node.disabled = saving;
    }

    const nameField = element('div', 'harness-field');
    nameField.appendChild(element('label', '', '服务商名称（可选）'));
    const providerName = element('input');
    providerName.type = 'text';
    providerName.maxLength = 64;
    providerName.value = draft.serviceName || '';
    providerName.placeholder = '自动识别，也可填写中转服务名称';
    track(providerName, 'serviceName');
    nameField.appendChild(providerName);
    panel.appendChild(nameField);

    const providerField = element('div', 'harness-field');
    providerField.appendChild(element('label', '', '接口类型'));
    const provider = element('select');
    const options = [
      { value: 'openai-compatible', label: 'OpenAI 兼容（DeepSeek /v1）' },
      { value: 'anthropic-compatible', label: 'Anthropic 兼容（/v1/messages）' }
    ];
    for (const option of options) {
      const node = element('option', '', option.label);
      node.value = option.value;
      if (draft.provider === option.value) { node.selected = true; }
      provider.appendChild(node);
    }
    providerField.appendChild(provider);
    provider.value = draft.provider;
    track(provider, 'provider', 'change');
    panel.appendChild(providerField);

    const baseField = element('div', 'harness-field');
    baseField.appendChild(element('label', '', 'Base URL'));
    const baseUrl = element('input');
    baseUrl.type = 'url';
    baseUrl.inputMode = 'url';
    baseUrl.setAttribute('inputmode', 'url');
    baseUrl.setAttribute('autocapitalize', 'off');
    baseUrl.value = draft.baseUrl;
    baseUrl.placeholder = 'https://api.deepseek.com';
    baseUrl.maxLength = 8192;
    baseUrl.autocomplete = 'off';
    baseUrl.spellcheck = false;
    track(baseUrl, 'baseUrl');
    baseField.appendChild(baseUrl);
    panel.appendChild(baseField);

    const modelField = element('div', 'harness-field');
    modelField.appendChild(element('label', '', '模型名称'));
    const model = element('input');
    model.type = 'text';
    model.value = draft.model;
    model.placeholder = 'deepseek-chat';
    model.maxLength = 128;
    track(model, 'model');
    modelField.appendChild(model);
    panel.appendChild(modelField);

    const keyField = element('div', 'harness-field');
    keyField.appendChild(element('label', '', 'API Key'));
    const apiKey = element('input');
    apiKey.type = 'password';
    apiKey.value = draft.apiKey || '';
    apiKey.placeholder = editing && editing.needsApiKey ? '请补填此服务商的 Key' : editing && editing.configured ? '此服务已保存，留空则不修改' : 'sk-…';
    apiKey.maxLength = 8192;
    apiKey.autocomplete = 'new-password';
    track(apiKey, 'apiKey');
    keyField.appendChild(apiKey);
    panel.appendChild(keyField);

    const quickField = element('div', 'harness-field');
    quickField.appendChild(element('label', '', '常用模型（逗号分隔，可手动填写）'));
    const quickModels = element('input');
    quickModels.type = 'text';
    quickModels.value = draft.quickModels || '';
    quickModels.placeholder = 'deepseek-chat, deepseek-reasoner';
    track(quickModels, 'quickModels');
    quickField.appendChild(quickModels);
    panel.appendChild(quickField);

    if (settingsError.length > 0) {
      panel.appendChild(element('div', 'harness-settings-error', settingsError));
    }

    const actions = element('div', 'harness-settings-actions');
    if (!profilesAvailable && status && status.configured) {
      actions.appendChild(button('清除绑定', '', () => clearBinding(), saving));
    }
    actions.appendChild(button('取消', '', () => {
      showSettings = false;
      showModels = settingsReturnToModels;
      settingsError = '';
      settingsDraft = null;
      settingsDirty = true;
      refresh();
    }, saving));
    actions.appendChild(button(saving ? '保存中…' : (addingProfile ? '保存并使用' : '保存'), 'primary', () => saveSettings({
      provider: provider.value,
      baseUrl: baseUrl.value,
      model: model.value,
      apiKey: apiKey.value,
      quickModels: quickModels.value,
      serviceName: providerName.value
    }), saving));
    panel.appendChild(actions);
    overlay.appendChild(panel);
    return overlay;
  }

  function build() {
    container.replaceChildren();
    container.classList.add('harness-root');
    const style = document.createElement('style');
    style.textContent = STYLE;
    container.appendChild(style);
    const header = renderHeader();
    const messages = element('div', 'harness-messages');
    const composerParts = renderComposer();
    container.appendChild(header);
    container.appendChild(messages);
    container.appendChild(composerParts.composer);
    dom = {
      header,
      messages,
      input: composerParts.input,
      composerNode: composerParts.composer,
      toolbar: composerParts.toolbar,
      quotaPanel: composerParts.quotaPanel,
      toolbarMessage: composerParts.toolbarMessage,
      sendButton: composerParts.sendButton,
      root: container
    };
    const overlay = renderOverlay();
    if (overlay) { container.appendChild(overlay); }
    settingsDirty = false;
    renderToolbar();
    renderMessages();
  }

  function refresh() {
    if (!container) { return; }
    if (!dom) {
      build();
      return;
    }
    // Keep text inputs and the settings overlay alive across async status/turn events.
    // Replacing them drops ArkWeb's focus, caret and active IME composition.
    const header = renderHeader();
    container.replaceChild(header, dom.header);
    dom.header = header;
    if (settingsDirty || showModels) {
      const oldOverlay = container.querySelector('.harness-overlay');
      if (oldOverlay) { oldOverlay.remove(); }
      const overlay = renderOverlay();
      if (overlay) { container.appendChild(overlay); }
      settingsDirty = false;
    }
    renderToolbar();
    renderMessages();
  }

  async function refreshStatus() {
    const revision = bindingRevision;
    try {
      const next = await ctx.ai.status();
      if (revision === bindingRevision && !saving && !switching) { status = next; }
      await reloadProfiles();
    } catch (failure) {
      if (revision === bindingRevision) { error = errorText(failure); }
    }
    refresh();
  }

  function onTurnEvent(event) {
    if (!event) { return; }
    if (event.kind === 'status') {
      pending = event.text || '';
    } else if (event.kind === 'tool-start') {
      activeTool = {
        name: event.call.name,
        summary: event.call.arguments
      };
    } else if (event.kind === 'tool-end') {
      activeTool = null;
    } else if (event.kind === 'done') {
      pending = '';
      activeTool = null;
    }
    refresh();
  }

  async function send(value) {
    const prompt = text(value).trim();
    if (prompt.length === 0 || busy || saving || switching || historyWorking) { return; }
    busy = true;
    error = '';
    pending = '正在思考…';
    if (draftTimer) { clearTimeout(draftTimer); draftTimer = null; }
    draftDirty = false;
    session().draft = '';
    session().service = currentService();
    session().model = status && status.model || '';
    if (dom && dom.input) { dom.input.value = ''; }
    refresh();
    try {
      await runTurn(ctx, session(), prompt, { onEvent: onTurnEvent });
    } catch (failure) {
      error = errorText(failure);
    } finally {
      busy = false;
      pending = '';
      activeTool = null;
      refresh();
    }
  }

  function stop() {
    stopTurn(session());
    pending = '正在停止…';
    refresh();
  }

  async function resetSession() {
    if (busy || saving || switching || historyWorking) { return false; }
    let created = false;
    historyWorking = true; historyError = '';
    refresh();
    try {
      await persistCurrent();
      const next = createSession();
      ensureSystem(next, buildSystemPrompt(ctx));
      await saveSession(ctx, next, { strict: true });
      setConversation(next);
      showHistory = false; showModels = false; showSettings = false; settingsDirty = true;
      created = true;
    } catch (failure) { historyError = errorText(failure); error = `新建对话失败：${historyError}`; }
    finally { historyWorking = false; settingsDirty = true; refresh(); }
    return created;
  }

  function trackDraft() {
    if (!dom || !dom.input) { return; }
    session().draft = dom.input.value;
    draftDirty = true;
    if (draftTimer) { clearTimeout(draftTimer); }
    draftTimer = setTimeout(() => { flushDraft().then(() => refresh()).catch(() => refresh()); }, 450);
  }

  async function flushDraft() {
    if (draftTimer) { clearTimeout(draftTimer); draftTimer = null; }
    if (!draftDirty) { return draftSaving; }
    const current = session();
    if (dom && dom.input) { current.draft = dom.input.value; }
    draftDirty = false;
    draftSaving = saveSession(ctx, current, { strict: true }).catch(failure => {
      if (session() === current) { draftDirty = true; }
      throw failure;
    });
    return draftSaving;
  }

  async function persistCurrent() {
    if (draftTimer) { clearTimeout(draftTimer); draftTimer = null; }
    if (dom && dom.input) { session().draft = dom.input.value; }
    draftDirty = false;
    draftSaving = saveSession(ctx, session(), { strict: true });
    try { await draftSaving; }
    catch (failure) { draftDirty = true; throw failure; }
  }

  function setConversation(next) {
    holder.session = next;
    ensureSystem(next, buildSystemPrompt(ctx));
    if (dom && dom.input) { dom.input.value = next.draft || ''; }
    error = ''; pending = ''; activeTool = null; historyRemovalId = '';
  }

  async function openHistory() {
    if (busy || saving || switching || historyWorking) { return; }
    showHistory = true; showModels = false; showSettings = false;
    historyQuery = ''; historyError = ''; historyRemovalId = ''; historyWorking = true;
    settingsDirty = true; refresh();
    try { await persistCurrent(); historyEntries = await listConversations(ctx); }
    catch (failure) { historyError = errorText(failure); }
    finally { historyWorking = false; settingsDirty = true; refresh(); }
  }

  async function resumeHistory(id) {
    if (busy || saving || switching || historyWorking) { return; }
    historyWorking = true; historyError = ''; settingsDirty = true; refresh();
    try {
      await persistCurrent();
      const next = await selectConversation(ctx, id);
      setConversation(next);
      showHistory = false;
    } catch (failure) { historyError = errorText(failure); }
    finally { historyWorking = false; settingsDirty = true; refresh(); }
  }

  async function removeHistory(id) {
    if (busy || saving || switching || historyWorking) { return; }
    historyWorking = true; historyError = ''; settingsDirty = true; refresh();
    try {
      await persistCurrent();
      setConversation(await deleteConversation(ctx, id));
      historyEntries = await listConversations(ctx);
    } catch (failure) { historyError = errorText(failure); }
    finally { historyWorking = false; settingsDirty = true; refresh(); }
  }

  function openSettings(profileId) {
    if (busy || saving || switching || historyWorking) { return; }
    showHistory = false;
    settingsReturnToModels = showModels;
    addingProfile = false;
    editingProfileId = typeof profileId === 'string' ? profileId : (status && status.profileId || '');
    showModels = false;
    settingsDraft = null;
    settingsError = '';
    showSettings = true;
    settingsDirty = true;
    refresh();
    if (!settingsReturnToModels) { refreshStatus().catch(() => {}); }
  }

  async function openAddProfile() {
    if (busy || saving || switching || checkingProfiles) { return; }
    if (!profilesAvailable) {
      checkingProfiles = true;
      modelsError = '';
      refresh();
      await reloadProfiles();
      checkingProfiles = false;
    }
    if (!profilesAvailable) {
      modelsError = profilesError || '服务商配置尚未读取完成，请重试读取配置。';
      refresh();
      return;
    }
    // The user may have closed the manager while the host was being checked.
    if (!showModels) {
      return;
    }
    openSettings();
    addingProfile = true;
    editingProfileId = '';
    settingsDraft = null;
    settingsDirty = true;
    refresh();
  }

  async function selectProfile(profileId) {
    if (busy || saving || switching || !profilesAvailable || status && profileId === status.profileId) { return; }
    switching = true;
    modelsError = '';
    refresh();
    try {
      bindingChanged(await ctx.ai.configure({ action: 'select', profileId }));
      await reloadProfiles();
      if (quotaOpen) { fetchQuota(); }
    } catch (failure) { modelsError = errorText(failure); }
    finally { switching = false; refresh(); }
  }

  async function removeProfile(profileId) {
    if (busy || saving || switching || !profilesAvailable) { return; }
    saving = true;
    modelsError = '';
    refresh();
    try {
      bindingChanged(await ctx.ai.configure({ action: 'remove', profileId }));
      await reloadProfiles();
      if (quotaOpen && status.configured) { fetchQuota(); }
    } catch (failure) { modelsError = errorText(failure); }
    finally { saving = false; refresh(); }
  }

  function openModels() {
    if (busy || saving || switching || historyWorking) { return; }
    showHistory = false;
    showSettings = false;
    showModels = true;
    settingsDraft = null;
    modelsError = '';
    settingsDirty = true;
    refresh();
    refreshStatus().catch(() => {});
  }

  function closeModels() {
    showModels = false;
    settingsDirty = true;
    refresh();
  }

  async function saveSettings(patch) {
    if (saving || busy || switching) { return; }
    settingsError = '';
    settingsDraft = Object.assign({}, patch);
    const payload = {
      provider: text(patch.provider),
      baseUrl: text(patch.baseUrl).trim(),
      model: text(patch.model).trim()
    };
    const editing = profiles.find((profile) => profile.profileId === editingProfileId) || status;
    if (profilesAvailable) {
      payload.action = addingProfile ? 'create' : 'save';
      if (!addingProfile && editingProfileId) { payload.profileId = editingProfileId; }
      payload.name = text(patch.serviceName).trim();
    }
    if (!payload.baseUrl || !payload.model) {
      settingsError = '请填写完整的 Base URL 和模型名称';
      settingsDirty = true;
      refresh();
      return;
    }
    if (text(patch.apiKey).trim().length > 0) {
      payload.apiKey = text(patch.apiKey).trim();
    } else if (addingProfile || !editing || !editing.configured || editing.needsApiKey) {
      settingsError = '首次绑定需要填写 API Key';
      settingsDirty = true;
      refresh();
      return;
    }
    saving = true;
    settingsDirty = true;
    refresh();
    try {
      bindingChanged(await ctx.ai.configure(payload));
      const savedProfileId = addingProfile ? status.profileId : editingProfileId;
      await reloadProfiles();
      showSettings = false;
      showModels = settingsReturnToModels;
      modelsError = '';
      settingsDraft = null;
      try {
        const savedProfile = profiles.find((profile) => profile.profileId === savedProfileId);
        // Saving an inactive profile must not write its model list into the active service.
        await rememberService(patch.serviceName, savedProfile);
        await rememberModels([payload.model, ...modelNames(patch.quickModels)], savedProfile);
      }
      catch (failure) { toolbarError = `模型已绑定，常用列表保存失败：${errorText(failure)}`; }
      try { await ctx.ui.notice('模型服务已绑定', 2000); } catch (ignored) { /* notice is optional */ }
    } catch (failure) {
      settingsError = errorText(failure);
    }
    saving = false;
    settingsDirty = true;
    refresh();
    if (!showSettings && quotaOpen && status && status.configured) { fetchQuota(); }
  }

  async function clearBinding() {
    if (saving || busy || switching) { return; }
    settingsError = '';
    saving = true;
    settingsDirty = true;
    refresh();
    try {
      bindingChanged(await ctx.ai.configure({ clear: true }));
      settingsDraft = null;
      showSettings = false;
      showModels = settingsReturnToModels;
      try { await ctx.ui.notice('已清除模型绑定', 2000); } catch (ignored) { /* notice is optional */ }
    } catch (failure) {
      settingsError = errorText(failure);
    }
    saving = false;
    settingsDirty = true;
    refresh();
  }

  function mount(root) {
    container = root;
    dom = null;
    build();
    refreshStatus().catch(() => {});
    ctx.storage.get('harness.models.v1').then((stored) => {
      if (stored && typeof stored === 'object' && !Array.isArray(stored) && Object.keys(modelLists).length === 0) {
        const next = {};
        for (const key of Object.keys(stored).slice(-12)) { next[key] = modelNames(stored[key]); }
        modelLists = next;
        refresh();
      }
    }).catch(() => {});
    ctx.storage.get('harness.services.v1').then((stored) => {
      if (stored && typeof stored === 'object' && !Array.isArray(stored) && Object.keys(serviceNames).length === 0) {
        const next = {};
        for (const key of Object.keys(stored).slice(-12)) { next[key] = text(stored[key]).slice(0, 64); }
        serviceNames = next;
        refresh();
      }
    }).catch(() => {});
    if (settings.onMounted) { settings.onMounted(controller); }
  }

  const controller = {
    mount,
    refresh,
    refreshStatus,
    send,
    stop,
    resetSession,
    openSettings,
    openModels,
    openHistory,
    async dispose() {
      if (busy) { stopTurn(session()); }
      await flushDraft().catch(() => {});
      container = null; dom = null;
    },
    isBusy() { return busy; },
    session() { return session(); },
    notify(message) {
      if (typeof ctx.ui.notice === 'function') {
        ctx.ui.notice(message, 2500).catch(() => {});
      }
    }
  };

  return controller;
}

module.exports = { createViewController, STYLE };
