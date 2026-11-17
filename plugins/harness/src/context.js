'use strict';

const { clip, text, normalizePath, basename, errorText, isObject } = require('./util');

const SCOPE_ACTIVE = 'active';
const SCOPE_SELECTION = 'selection';
const SCOPE_NOTES = 'notes';
const VALID_SCOPES = new Set([SCOPE_ACTIVE, SCOPE_SELECTION, SCOPE_NOTES]);

const MAX_SELECTED_NOTES = 12;
const MAX_ACTIVE_NOTE_CHARS = 16000;
const MAX_SELECTION_CHARS = 8000;
const MAX_SELECTION_SURROUND_CHARS = 500;
const MAX_COLLECTION_TOTAL_CHARS = 24000;
const MAX_COLLECTION_PER_NOTE_CHARS = 4500;

/** Checks whether an RPC error is a host capability / scope denial. */
function isPermissionError(error) {
  if (!error) {
    return false;
  }
  const code = typeof error.code === 'string' ? error.code : '';
  if (code === 'E_PERMISSION_DENIED' || code === 'E_VAULT_FORBIDDEN') {
    return true;
  }
  const msg = errorText(error);
  return /^E_PERMISSION_DENIED|^E_VAULT_FORBIDDEN|未获得能力|缺少.*权限/.test(msg);
}

/** Normalizes user-chosen scope settings persisted in session state. */
function normalizeContextState(raw) {
  const source = isObject(raw) ? raw : {};
  const scope = VALID_SCOPES.has(source.scope) ? source.scope : SCOPE_ACTIVE;
  const ids = [];
  const seen = new Set();
  if (Array.isArray(source.selectedNoteIds)) {
    for (let i = 0; i < source.selectedNoteIds.length && ids.length < MAX_SELECTED_NOTES; i += 1) {
      const id = text(source.selectedNoteIds[i]).trim();
      if (id && !seen.has(id)) {
        seen.add(id);
        ids.push(id);
      }
    }
  }
  return { scope, selectedNoteIds: ids };
}

/** Computes 1-based line numbers covering UTF-16 offset range [from, to]. */
function lineRangeForOffsets(sourceText, fromOffset, toOffset) {
  const source = typeof sourceText === 'string' ? sourceText : '';
  const from = Math.max(0, Math.min(source.length, Math.floor(Number(fromOffset) || 0)));
  const to = Math.max(from, Math.min(source.length, Math.floor(Number(toOffset) || from)));

  let startLine = 1;
  for (let i = 0; i < from; i += 1) {
    if (source.charCodeAt(i) === 10) {
      startLine += 1;
    }
  }
  let endLine = startLine;
  const effectiveEnd = to > from && source.charCodeAt(to - 1) === 10 ? to - 1 : to;
  for (let i = from; i < effectiveEnd; i += 1) {
    if (source.charCodeAt(i) === 10) {
      endLine += 1;
    }
  }
  return { startLine, endLine };
}

function countLines(sourceText) {
  const source = typeof sourceText === 'string' ? sourceText : '';
  if (!source) {
    return 0;
  }
  return source.split(/\r\n?|\n/).length;
}

function titleFromRef(filePath, name) {
  const cleanName = text(name).trim();
  if (cleanName) {
    return cleanName.replace(/\.md$/i, '');
  }
  const base = basename(normalizePath(filePath));
  return base ? base.replace(/\.md$/i, '') : '未命名笔记';
}

async function safeLookupFileRef(ctx, noteId, activeFileFallback) {
  if (activeFileFallback && (!noteId || activeFileFallback.id === noteId)) {
    return activeFileFallback;
  }
  if (!noteId || !ctx.vault) {
    return null;
  }
  try {
    if (typeof ctx.vault.listMarkdown === 'function') {
      const list = await ctx.vault.listMarkdown();
      return list.find((item) => item.id === noteId) || null;
    }
    return null;
  } catch (_error) {
    return null;
  }
}

async function resolveActiveContext(ctx) {
  let activeFile = null;
  let workspaceErr = null;
  if (ctx.workspace && typeof ctx.workspace.activeFile === 'function') {
    try {
      activeFile = await ctx.workspace.activeFile();
    } catch (error) {
      workspaceErr = error;
    }
  }

  let editorSnap = null;
  let editorErr = null;
  if (ctx.editor && typeof ctx.editor.active === 'function') {
    try {
      editorSnap = await ctx.editor.active();
    } catch (error) {
      editorErr = error;
    }
  }

  if (workspaceErr && isPermissionError(workspaceErr) && (!editorSnap || editorErr)) {
    return {
      ok: false,
      scope: SCOPE_ACTIVE,
      code: 'E_PERMISSION_DENIED',
      message: errorText(workspaceErr),
      notes: [],
      summary: '缺少 workspace.views 权限'
    };
  }

  const useEditorSnapshot = Boolean(
    editorSnap && (!activeFile || !editorSnap.noteId || editorSnap.noteId === activeFile.id)
  );

  if (useEditorSnapshot) {
    const ref = await safeLookupFileRef(ctx, editorSnap.noteId, activeFile);
    const noteId = text(ref && ref.id) || text(editorSnap.noteId) || text(activeFile && activeFile.id);
    const notePath = normalizePath((ref && ref.path) || (activeFile && activeFile.path) || '');
    const noteName = titleFromRef(notePath, (ref && ref.name) || (activeFile && activeFile.name));
    const fullContent = typeof editorSnap.content === 'string' ? editorSnap.content : '';
    const truncated = fullContent.length > MAX_ACTIVE_NOTE_CHARS;
    const content = truncated ? clip(fullContent, MAX_ACTIVE_NOTE_CHARS) : fullContent;
    const lineCount = countLines(fullContent);

    return {
      ok: true,
      scope: SCOPE_ACTIVE,
      label: '当前笔记',
      summary: notePath ? `${noteName} (${lineCount} 行)` : `当前编辑器 (${lineCount} 行)`,
      notes: [{
        id: noteId,
        path: notePath,
        name: noteName,
        content,
        truncated,
        totalLength: fullContent.length,
        lineCount,
        revision: Number(editorSnap.revision) || 0,
        updatedAt: ref ? Number(ref.updatedAt) || 0 : 0,
        dirty: editorSnap.dirty === true,
        readOnly: editorSnap.readOnly === true
      }]
    };
  }

  if (activeFile && text(activeFile.id)) {
    try {
      const fullContent = await ctx.vault.read(activeFile);
      const notePath = normalizePath(activeFile.path);
      const noteName = titleFromRef(notePath, activeFile.name);
      const truncated = fullContent.length > MAX_ACTIVE_NOTE_CHARS;
      const content = truncated ? clip(fullContent, MAX_ACTIVE_NOTE_CHARS) : fullContent;
      const lineCount = countLines(fullContent);
      return {
        ok: true,
        scope: SCOPE_ACTIVE,
        label: '当前笔记',
        summary: `${noteName} (${lineCount} 行)`,
        notes: [{
          id: activeFile.id,
          path: notePath,
          name: noteName,
          content,
          truncated,
          totalLength: fullContent.length,
          lineCount,
          revision: 0,
          updatedAt: Number(activeFile.mtime || activeFile.updatedAt) || 0,
          dirty: false,
          readOnly: false
        }]
      };
    } catch (error) {
      return {
        ok: false,
        scope: SCOPE_ACTIVE,
        code: isPermissionError(error) ? 'E_PERMISSION_DENIED' : 'E_READ_FAILED',
        message: errorText(error),
        notes: [],
        summary: isPermissionError(error) ? '缺少 vault.read 权限' : '读取当前笔记失败'
      };
    }
  }

  if (editorErr && isPermissionError(editorErr)) {
    return {
      ok: false,
      scope: SCOPE_ACTIVE,
      code: 'E_PERMISSION_DENIED',
      message: errorText(editorErr),
      notes: [],
      summary: '缺少 editor.read 权限'
    };
  }

  return {
    ok: false,
    scope: SCOPE_ACTIVE,
    code: 'NO_ACTIVE_NOTE',
    message: '当前没有打开的笔记，请先打开一篇笔记或切换上下文范围',
    notes: [],
    summary: '未打开笔记'
  };
}

async function resolveSelectionContext(ctx) {
  let snapshot = null;
  try {
    snapshot = await ctx.editor.active();
  } catch (error) {
    return {
      ok: false,
      scope: SCOPE_SELECTION,
      code: isPermissionError(error) ? 'E_PERMISSION_DENIED' : 'E_EDITOR_ERROR',
      message: isPermissionError(error)
        ? `缺少宿主权限 editor.read，无法读取选中内容：${errorText(error)}`
        : errorText(error),
      notes: [],
      summary: isPermissionError(error) ? '缺少 editor.read 权限' : '读取编辑器失败'
    };
  }

  if (!snapshot) {
    return {
      ok: false,
      scope: SCOPE_SELECTION,
      code: 'NO_ACTIVE_EDITOR',
      message: '当前没有活动的编辑视图（或正处于阅读预览），请切换到编辑模式并选中文本',
      notes: [],
      summary: '无活动编辑器'
    };
  }

  let activeFile = null;
  if (ctx.workspace && typeof ctx.workspace.activeFile === 'function') {
    try {
      activeFile = await ctx.workspace.activeFile();
    } catch (_error) {
      activeFile = null;
    }
  }
  const ref = await safeLookupFileRef(ctx, snapshot.noteId, activeFile);
  const noteId = text(ref && ref.id) || text(snapshot.noteId);
  const notePath = normalizePath((ref && ref.path) || '');
  const noteName = titleFromRef(notePath, ref && ref.name);

  const content = typeof snapshot.content === 'string' ? snapshot.content : '';
  const sel = isObject(snapshot.selection) ? snapshot.selection : { from: 0, to: 0 };
  const from = Math.max(0, Math.min(content.length, Math.floor(Number(sel.from) || 0)));
  const to = Math.max(from, Math.min(content.length, Math.floor(Number(sel.to) || from)));
  const selectedRaw = content.slice(from, to);

  if (selectedRaw.length === 0) {
    return {
      ok: false,
      scope: SCOPE_SELECTION,
      code: 'EMPTY_SELECTION',
      readOnly: snapshot.readOnly === true,
      message: snapshot.readOnly
        ? '当前笔记处于只读视图，请切换到编辑模式并选中内容后再试'
        : '当前尚未选中任何文本，请在编辑器中框选一段内容后点击刷新',
      notes: notePath ? [{
        id: noteId,
        path: notePath,
        name: noteName,
        revision: Number(snapshot.revision) || 0,
        readOnly: snapshot.readOnly === true
      }] : [],
      summary: notePath ? `${noteName} · 未选中文本` : '未选中文本'
    };
  }

  const range = lineRangeForOffsets(content, from, to);
  const clipped = selectedRaw.length > MAX_SELECTION_CHARS;
  const selectedText = clipped ? clip(selectedRaw, MAX_SELECTION_CHARS) : selectedRaw;
  const beforeStart = Math.max(0, from - MAX_SELECTION_SURROUND_CHARS);
  const afterEnd = Math.min(content.length, to + MAX_SELECTION_SURROUND_CHARS);
  const beforeContext = (beforeStart > 0 ? '...' : '') + content.slice(beforeStart, from);
  const afterContext = content.slice(to, afterEnd) + (afterEnd < content.length ? '...' : '');
  const fragment = range.startLine === range.endLine
    ? `L${range.startLine}`
    : `L${range.startLine}-L${range.endLine}`;

  const noteRecord = {
    id: noteId,
    path: notePath,
    name: noteName,
    from,
    to,
    startLine: range.startLine,
    endLine: range.endLine,
    fragment,
    selectedText,
    selectedLength: selectedRaw.length,
    totalLength: content.length,
    clipped,
    beforeContext,
    afterContext,
    revision: Number(snapshot.revision) || 0,
    updatedAt: ref ? Number(ref.updatedAt) || 0 : 0,
    dirty: snapshot.dirty === true,
    readOnly: snapshot.readOnly === true
  };

  return {
    ok: true,
    scope: SCOPE_SELECTION,
    label: '选中内容',
    summary: `${noteName} ${fragment} (${selectedRaw.length} 字)`,
    selection: {
      noteId,
      path: notePath,
      name: noteName,
      from,
      to,
      startLine: range.startLine,
      endLine: range.endLine,
      fragment,
      selectedText,
      selectedLength: selectedRaw.length,
      clipped,
      readOnly: snapshot.readOnly === true
    },
    notes: [noteRecord]
  };
}

async function resolveNotesCollectionContext(ctx, selectedNoteIds) {
  const ids = normalizeContextState({ scope: SCOPE_NOTES, selectedNoteIds }).selectedNoteIds;
  if (ids.length === 0) {
    return {
      ok: false,
      scope: SCOPE_NOTES,
      code: 'EMPTY_COLLECTION',
      message: '尚未指定笔记集合，请点击“选择笔记”至少勾选一篇笔记',
      notes: [],
      summary: '未选择笔记 (0 篇)'
    };
  }

  let editorSnap = null;
  if (ctx.editor && typeof ctx.editor.active === 'function') {
    try {
      editorSnap = await ctx.editor.active();
    } catch (_error) {
      editorSnap = null;
    }
  }

  const rawEntries = [];
  let permissionDeniedError = null;
  let allFiles = [];
  try {
    allFiles = await ctx.vault.listMarkdown();
  } catch (error) {
    if (isPermissionError(error)) {
      permissionDeniedError = error;
    }
  }

  if (!permissionDeniedError) {
    const byId = new Map();
    for (let i = 0; i < allFiles.length; i += 1) {
      byId.set(allFiles[i].id, allFiles[i]);
    }
    for (let i = 0; i < ids.length; i += 1) {
      const ref = byId.get(ids[i]);
      if (!ref) {
        continue;
      }
      try {
        const useEditorBuffer = Boolean(editorSnap && editorSnap.noteId === ref.id);
        const fullContent = useEditorBuffer ? String(editorSnap.content || '') : await ctx.vault.read(ref);
        const notePath = normalizePath(ref.path);
        rawEntries.push({
          id: ref.id,
          path: notePath,
          name: titleFromRef(notePath, ref.name),
          fullContent,
          lineCount: countLines(fullContent),
          updatedAt: Number(ref.mtime || ref.updatedAt) || 0,
          revision: useEditorBuffer ? Number(editorSnap.revision) || 0 : 0,
          dirty: useEditorBuffer ? editorSnap.dirty === true : false
        });
      } catch (error) {
        if (isPermissionError(error)) {
          permissionDeniedError = error;
          break;
        }
      }
    }
  }

  if (permissionDeniedError) {
    return {
      ok: false,
      scope: SCOPE_NOTES,
      code: 'E_PERMISSION_DENIED',
      message: errorText(permissionDeniedError),
      notes: [],
      summary: '缺少 vault.read 权限'
    };
  }

  if (rawEntries.length === 0) {
    return {
      ok: false,
      scope: SCOPE_NOTES,
      code: 'NOTES_NOT_FOUND',
      message: '所选笔记已移动或不存在，请重新选择笔记集合',
      notes: [],
      summary: '所选笔记不存在'
    };
  }

  const perNoteLimit = Math.max(
    1200,
    Math.min(MAX_COLLECTION_PER_NOTE_CHARS, Math.floor(MAX_COLLECTION_TOTAL_CHARS / rawEntries.length))
  );
  const notes = rawEntries.map((entry) => {
    const truncated = entry.fullContent.length > perNoteLimit;
    return {
      id: entry.id,
      path: entry.path,
      name: entry.name,
      content: truncated ? clip(entry.fullContent, perNoteLimit) : entry.fullContent,
      truncated,
      totalLength: entry.fullContent.length,
      lineCount: entry.lineCount,
      updatedAt: entry.updatedAt,
      revision: entry.revision,
      dirty: entry.dirty
    };
  });

  return {
    ok: true,
    scope: SCOPE_NOTES,
    label: '指定笔记集合',
    summary: `已指定 ${notes.length} 篇笔记`,
    notes
  };
}

/** Resolves the currently configured context scope via host-gated SDK calls. */
async function resolveContextScope(ctx, rawSettings) {
  const settings = normalizeContextState(rawSettings);
  if (settings.scope === SCOPE_SELECTION) {
    return resolveSelectionContext(ctx);
  }
  if (settings.scope === SCOPE_NOTES) {
    return resolveNotesCollectionContext(ctx, settings.selectedNoteIds);
  }
  return resolveActiveContext(ctx);
}

/** Builds lightweight UI metadata attached to a user turn (safe for session storage). */
function toContextMeta(resolved) {
  if (!resolved || !isObject(resolved)) {
    return { scope: SCOPE_ACTIVE, label: '当前笔记', summary: '', refs: [] };
  }
  const refs = Array.isArray(resolved.notes)
    ? resolved.notes
      .filter((item) => isObject(item) && text(item.path))
      .slice(0, MAX_SELECTED_NOTES)
      .map((item) => ({
        id: text(item.id),
        path: normalizePath(item.path),
        name: text(item.name) || titleFromRef(item.path),
        startLine: Number(item.startLine) || 0,
        endLine: Number(item.endLine) || 0,
        from: typeof item.from === 'number' ? item.from : 0,
        to: typeof item.to === 'number' ? item.to : 0,
        fragment: text(item.fragment),
        charCount: Number(item.selectedLength || item.totalLength) || 0
      }))
    : [];
  return {
    scope: resolved.scope || SCOPE_ACTIVE,
    label: text(resolved.label) || '当前笔记',
    summary: text(resolved.summary),
    ok: resolved.ok === true,
    refs
  };
}

/** Formats scoped note content for injection into the active LLM turn. */
function formatContextForModel(resolved) {
  if (!resolved || !resolved.ok || !Array.isArray(resolved.notes) || resolved.notes.length === 0) {
    return '';
  }

  if (resolved.scope === SCOPE_SELECTION) {
    const item = resolved.notes[0];
    const header = item.path
      ? `${item.path}#${item.fragment} (UTF-16 范围 ${item.from}..${item.to}，共 ${item.selectedLength} 字${item.readOnly ? ' · 只读' : ''})`
      : `当前活动编辑器 (${item.fragment}，共 ${item.selectedLength} 字)`;
    const parts = [
      `[上下文范围: 选中内容]`,
      `来源笔记: ${header}`,
      '如建议改写该选区，请优先调用 `replace_selection`（仅生成差异建议等待用户确认，绝不直接覆盖），并在回答中用 Markdown 链接引用该笔记。',
      item.beforeContext ? `--- 选区前文 ---\n${item.beforeContext}` : '',
      `--- 用户选中内容 (${item.fragment}) ---\n${item.selectedText}${item.clipped ? '\n...(已截断)' : ''}`,
      item.afterContext ? `--- 选区后文 ---\n${item.afterContext}` : ''
    ].filter(Boolean);
    return parts.join('\n');
  }

  if (resolved.scope === SCOPE_NOTES) {
    const blocks = [
      `[上下文范围: 指定笔记集合 · 共 ${resolved.notes.length} 篇]`,
      '请在回答中仅根据真实内容作答，并用 `[标题](相对路径.md)` 格式精确引用相关笔记。如需修改请通过工具生成差异建议等待用户确认。'
    ];
    for (let i = 0; i < resolved.notes.length; i += 1) {
      const n = resolved.notes[i];
      blocks.push(
        `### [${n.name}](${n.path}) (${n.lineCount} 行, ${n.totalLength} 字${n.dirty ? ' · 含未保存编辑' : ''})\n` +
        `\`\`\`markdown\n${n.content}${n.truncated ? '\n...(单篇超限已截断，可用 read_note 查看完整内容)' : ''}\n\`\`\``
      );
    }
    return blocks.join('\n\n');
  }

  const active = resolved.notes[0];
  const loc = active.path ? `[${active.name}](${active.path})` : active.name;
  return [
    `[上下文范围: 当前笔记]`,
    `笔记: ${loc} (${active.lineCount} 行, ${active.totalLength} 字${active.dirty ? ' · 含未保存编辑' : ''}${active.readOnly ? ' · 只读模式' : ''})`,
    '回答时请使用 `[标题](相对路径.md)` 引用该笔记；若建议修改正文，请调用工具生成差异预览，由用户确认写入。',
    `\`\`\`markdown\n${active.content}${active.truncated ? '\n...(内容较长已截断，可用 read_note 查看全文)' : ''}\n\`\`\``
  ].join('\n');
}

module.exports = {
  SCOPE_ACTIVE,
  SCOPE_SELECTION,
  SCOPE_NOTES,
  MAX_SELECTED_NOTES,
  isPermissionError,
  normalizeContextState,
  lineRangeForOffsets,
  resolveContextScope,
  toContextMeta,
  formatContextForModel
};
