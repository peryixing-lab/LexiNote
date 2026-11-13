import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useStore, EditorMode, EditorApi } from '../store/AppStore';
import { useOptionalPluginHost } from '../plugins/PluginHostController';
import type { NoteItem } from '../../shared/types';
import type { PluginEditorDraft } from '../../shared/pluginTypes';
import { displayTitle, parseBlocks, parseFrontmatter, tableData } from '../core/markdown';
import { Icon } from './Icon';
import {
  BlockView,
  InlineContent,
  MarkdownBlocks
} from './MarkdownView';
import { ChevronGlyph, CloseGlyph, MicGlyph, MoreGlyph } from './Symbols';
import { FloatingMenu, MenuEntry } from './FloatingMenu';

interface EditingBlock {
  start: number;
  end: number;
  base: string;
  text: string;
}

function replaceLines(content: string, start: number, end: number, text: string): string {
  const lines = content.split('\n');
  const next = [...lines.slice(0, start), ...text.split('\n'), ...lines.slice(end)];
  return next.join('\n');
}

function autoSize(textarea: HTMLTextAreaElement | null, min = 24): void {
  if (!textarea) return;
  textarea.style.height = 'auto';
  textarea.style.height = `${Math.max(min, textarea.scrollHeight)}px`;
}

function setNativeValue(textarea: HTMLTextAreaElement, value: string, start: number, end: number): void {
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
  setter?.call(textarea, value);
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  textarea.focus();
  textarea.setSelectionRange(start, end);
}

export function Editor(): JSX.Element {
  const { state, actions, derived } = useStore();
  const pluginHost = useOptionalPluginHost();
  const note = derived.currentNote;
  const { tr } = derived;
  const scrollRef = useRef<HTMLDivElement>(null);
  const sourceRef = useRef<HTMLTextAreaElement>(null);
  const titleRef = useRef<HTMLTextAreaElement>(null);
  const liveRef = useRef<HTMLTextAreaElement>(null);
  const [titleDraft, setTitleDraft] = useState('');
  const [editing, setEditing] = useState<EditingBlock | null>(null);
  const [toolsAnchor, setToolsAnchor] = useState<{ x: number; y: number } | null>(null);
  const [moreAnchor, setMoreAnchor] = useState<{ x: number; y: number } | null>(null);
  const [findOpen, setFindOpen] = useState(false);
  const [replaceOpen, setReplaceOpen] = useState(false);
  const [findText, setFindText] = useState('');
  const [replaceText, setReplaceText] = useState('');
  const [findIndex, setFindIndex] = useState(0);
  const titleBeforeRef = useRef('');
  const [flashLine, setFlashLine] = useState<number | null>(null);

  const content = note?.content ?? '';
  const latestContentRef = useRef(content);
  const revisionRef = useRef<{ noteId: string; rev: number; content: string }>({
    noteId: '',
    rev: 0,
    content: ''
  });
  const lastSelectionRef = useRef<{ noteId: string; from: number; to: number }>({
    noteId: '',
    from: 0,
    to: 0
  });
  const noteRef = useRef(note);
  noteRef.current = note;
  const editingRef = useRef(editing);
  editingRef.current = editing;
  const saveStatusRef = useRef(state.saveStatus);
  saveStatusRef.current = state.saveStatus;

  if (!note) {
    latestContentRef.current = '';
  } else {
    if (revisionRef.current.noteId !== note.id) {
      revisionRef.current = {
        noteId: note.id,
        rev: revisionRef.current.rev + 1,
        content
      };
      latestContentRef.current = content;
    } else if (revisionRef.current.content !== content) {
      revisionRef.current = {
        noteId: note.id,
        rev: revisionRef.current.rev + 1,
        content
      };
      latestContentRef.current = content;
    }
  }
  const bodyText = useMemo(() => (note ? parseFrontmatter(note.content).body : ''), [note]);
  const mode: EditorMode =
    (note && state.editorModes[note.id]) ||
    (state.settings.editorDefaultView === 'reading'
      ? 'reading'
      : state.settings.editorDefaultView === 'source'
        ? 'source'
        : 'live');

  useEffect(() => {
    setTitleDraft(note ? displayTitle(note) : '');
  }, [note?.id]);

  useEffect(() => {
    autoSize(titleRef.current, 44);
  }, [titleDraft]);

  useEffect(() => {
    autoSize(sourceRef.current, 460);
  }, [content, mode]);

  const matches = useMemo(() => {
    const needle = findText.trim().toLowerCase();
    if (!needle) return [] as number[];
    const haystack = content.toLowerCase();
    const result: number[] = [];
    let index = haystack.indexOf(needle);
    while (index >= 0 && result.length < 500) {
      result.push(index);
      index = haystack.indexOf(needle, index + needle.length);
    }
    return result;
  }, [content, findText]);

  const lineForOffset = useCallback(
    (offset: number): number => content.substring(0, offset).split('\n').length - 1,
    [content]
  );

  const revealLine = useCallback(
    (line: number): void => {
      if (mode === 'source' && sourceRef.current) {
        const lines = content.split('\n');
        const start = lines.slice(0, line).join('\n').length + (line > 0 ? 1 : 0);
        sourceRef.current.focus();
        sourceRef.current.setSelectionRange(start, start + (lines[line]?.length ?? 0));
        return;
      }
      const container = scrollRef.current;
      const element = container?.querySelector<HTMLElement>(`[data-line="${line}"]`);
      if (element && container) {
        element.scrollIntoView({ block: 'center', behavior: 'smooth' });
        setFlashLine(line);
        window.setTimeout(() => setFlashLine(null), 1200);
      }
    },
    [content, mode]
  );

  useEffect(() => {
    const handler = (event: Event): void => {
      const detail = (event as CustomEvent<{ line: number }>).detail;
      if (detail && typeof detail.line === 'number') revealLine(detail.line);
    };
    window.addEventListener('lexi:reveal-line', handler);
    return () => window.removeEventListener('lexi:reveal-line', handler);
  }, [revealLine]);

  useEffect(() => {
    const handler = (): void => {
      if (!note) return;
      titleRef.current?.focus();
      titleRef.current?.select();
    };
    window.addEventListener('lexi:rename-title', handler);
    return () => window.removeEventListener('lexi:rename-title', handler);
  }, [note?.id]);

  const commitTitle = (): void => {
    if (!note) return;
    const next = titleDraft.replace(/\r?\n/g, ' ').trim();
    if (next !== titleBeforeRef.current) {
      actions.renameNote(note.id, next || '未命名笔记');
    }
    setTitleDraft(next);
  };

  const toggleTodo = (line: number): void => {
    if (!note) return;
    const lines = note.content.split('\n');
    const raw = lines[line];
    if (raw === undefined) return;
    lines[line] = /\[[xX]\]/.test(raw)
      ? raw.replace(/\[[xX]\]/, '[ ]')
      : raw.replace(/\[ \]/, '[x]');
    actions.updateNote(note.id, { content: lines.join('\n') });
  };

  const openTarget = (target: string): void => {
    if (!target) return;
    if (/^(https?:|mailto:)/i.test(target)) {
      void window.lexi?.openExternal(target);
      return;
    }
    const [name, anchor] = target.split('#');
    const found = state.notes.find(
      (item) =>
        item.vaultId === state.activeVaultId &&
        item.trashedAt === 0 &&
        (item.id === name || displayTitle(item).trim().toLowerCase() === name.trim().toLowerCase())
    );
    if (!found) {
      actions.showToast(`链接对应的笔记不存在：${name}`);
      return;
    }
    actions.openDocument(found.id);
    if (anchor) {
      const blocks = parseBlocks(found.content);
      const heading = blocks.find(
        (block) =>
          block.kind.startsWith('h') &&
          block.text.trim().toLowerCase().replace(/\s+/g, '-') === anchor.trim().toLowerCase().replace(/\s+/g, '-')
      );
      if (heading) window.setTimeout(() => revealLine(heading.lineIndex), 250);
    }
  };

  const activateBlock = (start: number, end: number, base: string): void => {
    const lines = base.split('\n');
    const text = lines.slice(start, end).join('\n').replace(/\s+$/, '');
    setEditing({ start, end, base, text });
    window.setTimeout(() => {
      autoSize(liveRef.current, 26);
      liveRef.current?.focus();
      liveRef.current?.setSelectionRange(text.length, text.length);
    }, 0);
  };

  const beginBlockEdit = (blockLine: number): void => {
    if (!note) return;
    const blocks = parseBlocks(note.content);
    const index = blocks.findIndex((block) => block.lineIndex === blockLine);
    if (index < 0) return;
    const start = blocks[index].lineIndex;
    const end = index + 1 < blocks.length ? blocks[index + 1].lineIndex : note.content.split('\n').length;
    activateBlock(start, end, note.content);
  };

  const appendParagraph = (): void => {
    if (!note) return;
    const lines = note.content.split('\n');
    const empty = note.content.trim().length === 0;
    activateBlock(empty ? 0 : lines.length, empty ? 0 : lines.length, note.content);
  };

  const updateEditing = (value: string): void => {
    if (!note || !editing) return;
    const hasFollowing = editing.end < editing.base.split('\n').length;
    const suffix = hasFollowing && value.trim().length > 0 ? '\n' : '';
    const nextContent = replaceLines(editing.base, editing.start, editing.end, value + suffix);
    setEditing({ ...editing, text: value });
    actions.updateNote(note.id, { content: nextContent });
    requestAnimationFrame(() => autoSize(liveRef.current, 26));
  };

  const finishEditing = (): void => {
    window.setTimeout(() => {
      setEditing((current) => (current ? null : current));
    }, 120);
  };

  const setMode = (next: EditorMode): void => {
    if (!note) return;
    setEditing(null);
    actions.setEditorMode(note.id, next);
  };

  const format = useCallback(
    (command: string): void => {
      const raw = command.replace(/^editor-/, '');
      const active = document.activeElement;
      let textarea: HTMLTextAreaElement | null = null;
      if (active instanceof HTMLTextAreaElement && active.dataset.role === 'body') textarea = active;
      else if (active instanceof HTMLTextAreaElement && active.closest('.editor-pane')) textarea = active;
      else if (mode === 'source') textarea = sourceRef.current;
      else textarea = liveRef.current;
      if (!textarea) {
        if (mode === 'live' && !editing) {
          actions.showToast('点按正文中的任意段落开始编辑，再使用格式命令');
          return;
        }
        actions.showToast('请先将光标放到正文中');
        return;
      }
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      const value = textarea.value;
      const selected = value.slice(start, end);
      const wrap = (prefix: string, suffix: string, placeholder: string): void => {
        const insert = `${prefix}${selected || placeholder}${suffix}`;
        const next = value.slice(0, start) + insert + value.slice(end);
        const caret = start + prefix.length + (selected ? selected.length : placeholder.length);
        setNativeValue(textarea, next, caret, caret);
      };
      const prefixLine = (prefix: string): void => {
        const lineStart = value.lastIndexOf('\n', Math.max(0, start - 1)) + 1;
        const lineText = value.slice(lineStart, value.indexOf('\n', start) === -1 ? value.length : value.indexOf('\n', start));
        const stripped = lineText.replace(/^(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)/, '');
        const next = value.slice(0, lineStart) + prefix + stripped + value.slice(lineStart + lineText.length);
        setNativeValue(textarea, next, start + prefix.length, end + prefix.length);
      };
      const insertBlock = (snippet: string): void => {
        const before = value.slice(0, start);
        const after = value.slice(end);
        const leading = before.length === 0 || before.endsWith('\n\n') ? '' : before.endsWith('\n') ? '\n' : '\n\n';
        const insert = `${leading}${snippet}`;
        const next = before + insert + after;
        const caret = before.length + insert.length;
        setNativeValue(textarea, next, caret, caret);
      };
      switch (raw) {
        case 'bold':
          wrap('**', '**', '加粗文字');
          return;
        case 'italic':
          wrap('*', '*', '斜体文字');
          return;
        case 'strike':
          wrap('~~', '~~', '删除线');
          return;
        case 'highlight':
          wrap('==', '==', '高亮');
          return;
        case 'h1':
          prefixLine('# ');
          return;
        case 'h2':
          prefixLine('## ');
          return;
        case 'todo':
          prefixLine('- [ ] ');
          return;
        case 'hr':
          insertBlock('---\n');
          return;
        case 'table':
          insertBlock('| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n');
          return;
        case 'code':
          insertBlock(`\`\`\`\n${selected || '// 代码'}\n\`\`\`\n`);
          return;
        case 'formula':
          insertBlock(`$$\n${selected || 'E = mc^2'}\n$$\n`);
          return;
        case 'callout':
          insertBlock('> [!NOTE]\n> 在这里写下标注内容\n');
          return;
        default:
          return;
      }
    },
    [actions, editing, mode]
  );

  const editorApiRef = useRef<EditorApi | null>(null);
  useEffect(() => {
    if (!note) return;
    const readSelection = (currentNoteId: string, fullText: string): { from: number; to: number } => {
      if (mode === 'source' && sourceRef.current) {
        const from = Math.max(0, Math.min(fullText.length, sourceRef.current.selectionStart ?? fullText.length));
        const to = Math.max(from, Math.min(fullText.length, sourceRef.current.selectionEnd ?? from));
        return { from, to };
      }
      const activeEdit = editingRef.current;
      if (mode === 'live' && activeEdit && liveRef.current) {
        const lines = activeEdit.base.split('\n');
        const prefix = lines.slice(0, activeEdit.start).join('\n').length + (activeEdit.start > 0 ? 1 : 0);
        const from = Math.max(0, Math.min(fullText.length, prefix + (liveRef.current.selectionStart ?? 0)));
        const to = Math.max(from, Math.min(fullText.length, prefix + (liveRef.current.selectionEnd ?? 0)));
        return { from, to };
      }
      if (lastSelectionRef.current.noteId === currentNoteId) {
        const from = Math.max(0, Math.min(fullText.length, lastSelectionRef.current.from));
        const to = Math.max(from, Math.min(fullText.length, lastSelectionRef.current.to));
        return { from, to };
      }
      return { from: fullText.length, to: fullText.length };
    };

    const cursorFrom = (text: string, offset: number): { line: number; ch: number } => {
      const clamped = Math.max(0, Math.min(text.length, offset));
      const before = text.slice(0, clamped).split('\n');
      return {
        line: Math.max(0, before.length - 1),
        ch: before[before.length - 1]?.length ?? 0
      };
    };

    const buildDraft = (): PluginEditorDraft | null => {
      const currentNote = noteRef.current;
      if (!currentNote) return null;
      const text = latestContentRef.current;
      const sel = readSelection(currentNote.id, text);
      return {
        editorId: `editor-${currentNote.id}`,
        noteId: currentNote.id,
        vaultId: currentNote.vaultId,
        windowId: 'main',
        revision: Math.max(1, revisionRef.current.rev),
        baseContent: text,
        content: text,
        dirty: saveStatusRef.current === 'saving',
        readOnly: mode === 'reading',
        focused:
          (sourceRef.current !== null && document.activeElement === sourceRef.current) ||
          (liveRef.current !== null && document.activeElement === liveRef.current),
        selection: sel,
        cursor: cursorFrom(text, sel.to)
      };
    };

    const api: EditorApi = {
      focus: () => {
        if (mode === 'source') sourceRef.current?.focus();
        else if (mode === 'live') {
          const first = parseBlocks(latestContentRef.current)[0];
          if (first) beginBlockEdit(first.lineIndex);
        } else sourceRef.current?.focus();
      },
      format,
      toggleSource: () => {
        setMode(mode === 'source' ? 'live' : 'source');
      },
      toggleReading: () => {
        setMode(mode === 'reading' ? (state.settings.editorDefaultMode === 'source' ? 'source' : 'live') : 'reading');
      },
      find: (replace) => {
        setFindOpen(true);
        setReplaceOpen(replace);
        window.setTimeout(() => document.getElementById('editor-find-input')?.focus(), 60);
      },
      getDraft: buildDraft,
      replaceSelectionText: (text: string): PluginEditorDraft | null => {
        const currentNote = noteRef.current;
        if (!currentNote || mode === 'reading') return null;
        const cur = latestContentRef.current;
        const sel = readSelection(currentNote.id, cur);
        const next = cur.slice(0, sel.from) + text + cur.slice(sel.to);
        const caret = sel.from + text.length;
        latestContentRef.current = next;
        revisionRef.current = {
          noteId: currentNote.id,
          rev: Math.max(1, revisionRef.current.rev) + 1,
          content: next
        };
        lastSelectionRef.current = { noteId: currentNote.id, from: caret, to: caret };
        if (editingRef.current) setEditing(null);
        actions.updateVaultNoteSync(currentNote.id, { content: next });
        return {
          editorId: `editor-${currentNote.id}`,
          noteId: currentNote.id,
          vaultId: currentNote.vaultId,
          windowId: 'main',
          revision: revisionRef.current.rev,
          baseContent: next,
          content: next,
          dirty: true,
          readOnly: false,
          focused: false,
          selection: { from: caret, to: caret },
          cursor: cursorFrom(next, caret)
        };
      },
      replaceAllText: (text: string, expectedRevision?: number) => {
        const currentNote = noteRef.current;
        if (!currentNote || mode === 'reading') return { ok: false, draft: null };
        const currentDraft = buildDraft();
        if (
          typeof expectedRevision === 'number' &&
          expectedRevision > 0 &&
          currentDraft &&
          expectedRevision !== currentDraft.revision
        ) {
          return { ok: false, draft: currentDraft, conflict: true };
        }
        latestContentRef.current = text;
        revisionRef.current = {
          noteId: currentNote.id,
          rev: Math.max(1, revisionRef.current.rev) + 1,
          content: text
        };
        lastSelectionRef.current = { noteId: currentNote.id, from: text.length, to: text.length };
        if (editingRef.current) setEditing(null);
        actions.updateVaultNoteSync(currentNote.id, { content: text });
        return { ok: true, draft: buildDraft() };
      }
    };
    editorApiRef.current = api;
    actions.registerEditor(api);
    return () => {
      const current = editorApiRef.current;
      editorApiRef.current = null;
      if (current) actions.unregisterEditor(current);
    };
  }, [note?.id, mode, format, state.settings.editorDefaultMode, actions.updateVaultNoteSync]);

  useEffect(() => {
    if (mode !== 'source') setEditing(null);
  }, [mode]);

  const jumpToMatch = (forward = true): void => {
    if (matches.length === 0) return;
    const next = (findIndex + (forward ? 1 : matches.length - 1)) % matches.length;
    setFindIndex(next);
    const offset = matches[next];
    if (mode === 'source' && sourceRef.current) {
      sourceRef.current.focus();
      sourceRef.current.setSelectionRange(offset, offset + findText.length);
      return;
    }
    revealLine(lineForOffset(offset));
  };

  const replaceCurrent = (): void => {
    if (!note || matches.length === 0) return;
    const offset = matches[findIndex] ?? matches[0];
    const next = content.slice(0, offset) + replaceText + content.slice(offset + findText.length);
    actions.updateNote(note.id, { content: next });
  };

  const replaceAll = (): void => {
    if (!note || !findText.trim()) return;
    const next = content.split(findText).join(replaceText);
    actions.updateNote(note.id, { content: next });
    actions.showToast(`已替换 ${matches.length} 处`);
  };

  if (!note) {
    return (
      <div className="editor-empty">
        <Icon name="note" size={32} />
        <h2>{tr('选择或新建一篇笔记')}</h2>
        <p>{tr('从左侧打开已有笔记，或点击右上角“新建”开始记录。')}</p>
        <div className="empty-actions">
          <button type="button" className="primary-btn" onClick={() => actions.createNote('markdown')}>
            {tr('新建笔记')}
          </button>
          <button type="button" className="small-btn" onClick={() => actions.setTemplatesOpen(true)}>
            {tr('从模板新建')}
          </button>
        </div>
      </div>
    );
  }

  const toolEntries: MenuEntry[] = [
    {
      id: 'outline',
      label: tr('大纲'),
      onSelect: () => actions.setRightSidebar(true, 'outline')
    },
    {
      id: 'backlinks',
      label: tr('反向链接'),
      onSelect: () => actions.setRightSidebar(true, 'outline')
    },
    {
      id: 'properties',
      label: tr('笔记属性'),
      onSelect: () => actions.setRightSidebar(true, 'properties')
    },
    { separator: true },
    {
      id: 'reading',
      label: mode === 'reading' ? tr('返回编辑') : tr('阅读视图'),
      onSelect: () => setMode(mode === 'reading' ? 'live' : 'reading')
    },
    {
      id: 'find',
      label: tr('查找与替换'),
      shortcut: 'Ctrl+F',
      onSelect: () => {
        setFindOpen(true);
        setReplaceOpen(true);
      }
    },
    { separator: true },
    {
      id: 'convert',
      label: tr('转为思维导图'),
      onSelect: () => actions.createMap(note.id)
    },
    {
      id: 'template',
      label: tr('保存为模板'),
      onSelect: () => void actions.executeCommand('save-template')
    }
  ];

  const moreEntries: MenuEntry[] = [
    {
      id: 'rename',
      label: tr('重命名'),
      shortcut: 'F2',
      onSelect: () => {
        titleRef.current?.focus();
        titleRef.current?.select();
      }
    },
    {
      id: 'duplicate',
      label: tr('创建副本'),
      onSelect: () => actions.duplicateNote(note.id)
    },
    {
      id: 'copy-uri',
      label: tr('复制知萤 URI'),
      onSelect: () => void actions.executeCommand('copy-uri')
    },
    { separator: true },
    {
      id: 'export-md',
      label: tr('导出 Markdown'),
      onSelect: () => void actions.exportNote('md')
    },
    {
      id: 'export-pdf',
      label: tr('导出为 HTML / PDF'),
      onSelect: () => void actions.executeCommand('export-pdf')
    },
    { separator: true },
    {
      id: 'delete',
      label: tr('移到回收站'),
      danger: true,
      disabled: false,
      onSelect: () => actions.trashNote(note.id)
    }
  ];

  const typeLabel =
    note.noteType === 'study' ? tr('学习笔记') : note.noteType === 'quick' ? tr('快速笔记') : 'Markdown';

  return (
    <div className="editor-pane" onKeyDown={(event) => {
      const mod = event.ctrlKey || event.metaKey;
      if (!mod) return;
      const key = event.key.toLowerCase();
      if (key === 'b') {
        event.preventDefault();
        format('bold');
      } else if (key === 'i') {
        event.preventDefault();
        format('italic');
      }
    }}>
      <div className="editor-header">
        {state.settings.showTabHeaders ? (
          <>
            <Icon name="folder" size={15} />
            <span className="editor-crumb">{note.notebook || tr('知识库')}</span>
            <span className="editor-crumb-sep">/</span>
            <span className="editor-crumb title">{displayTitle(note) || tr('无标题笔记')}</span>
          </>
        ) : (
          <span className="editor-crumb title">{displayTitle(note)}</span>
        )}
        <div className="editor-header-actions">
          <button
            type="button"
            className={`toolbar-btn${mode === 'source' ? ' active' : ''}`}
            title={mode === 'source' ? tr('当前为整篇源码编辑，切换到实时预览') : tr('当前为实时预览，切换到整篇源码编辑')}
            onClick={() => setMode(mode === 'source' ? 'live' : 'source')}
          >
            {mode === 'source' ? tr('实时预览') : tr('源码')}
          </button>
          <button
            type="button"
            className="toolbar-btn active"
            onClick={(event) => {
              const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
              setToolsAnchor({ x: rect.left, y: rect.bottom + 6 });
            }}
          >
            {tr('工具')}
          </button>
          <button
            type="button"
            className="toolbar-btn"
            onClick={(event) => {
              const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
              setMoreAnchor({ x: rect.right, y: rect.bottom + 6 });
            }}
          >
            {tr('更多')}
            <MoreGlyph size={14} color="var(--text-2)" />
          </button>
        </div>
      </div>

      {findOpen ? (
        <div className="find-bar">
          <div className="find-fields">
            <input
              id="editor-find-input"
              className="find-input"
              placeholder={tr('查找内容')}
              value={findText}
              onChange={(event) => {
                setFindText(event.target.value);
                setFindIndex(0);
              }}
              onKeyDown={(event) => {
                if (event.key === 'Enter') {
                  event.preventDefault();
                  jumpToMatch(!event.shiftKey);
                }
                if (event.key === 'Escape') setFindOpen(false);
              }}
            />
            {replaceOpen ? (
              <input
                className="find-input"
                placeholder={tr('替换为')}
                value={replaceText}
                onChange={(event) => setReplaceText(event.target.value)}
              />
            ) : null}
          </div>
          <span className="find-count">
            {findText ? `${Math.min(findIndex + 1, matches.length)} / ${matches.length}` : '0 / 0'}
          </span>
          <button type="button" className="small-btn" onClick={() => jumpToMatch(false)}>
            {tr('上一个')}
          </button>
          <button type="button" className="small-btn" onClick={() => jumpToMatch(true)}>
            {tr('下一个')}
          </button>
          {replaceOpen ? (
            <>
              <button type="button" className="small-btn" onClick={replaceCurrent}>
                {tr('替换')}
              </button>
              <button type="button" className="small-btn" onClick={replaceAll}>
                {tr('全部替换')}
              </button>
            </>
          ) : null}
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => setFindOpen(false)}>
            <CloseGlyph size={9} color="var(--text-2)" />
          </button>
        </div>
      ) : null}

      <div className="editor-body" ref={scrollRef}>
        <div
          className={`document${state.settings.editorLimitWidth ? ' limited' : ' wide'}`}
          style={{ fontSize: state.settings.fontSize }}
        >
          {state.settings.editorShowTitle ? (
            <textarea
              ref={titleRef}
              className="document-title"
              rows={1}
              value={titleDraft}
              placeholder={tr('无标题笔记')}
              spellCheck={false}
              onFocus={() => {
                titleBeforeRef.current = displayTitle(note);
              }}
              onChange={(event) => {
                const clean = event.target.value.replace(/\r?\n/g, ' ');
                setTitleDraft(clean);
                autoSize(event.currentTarget, 44);
              }}
              onBlur={commitTitle}
              onKeyDown={(event) => {
                if (event.key === 'Enter' || event.key === 'Escape') {
                  event.preventDefault();
                  commitTitle();
                  event.currentTarget.blur();
                }
              }}
            />
          ) : null}

          <div className="document-meta">
            <span className="meta-type">{typeLabel}</span>
            <span className="meta-dot">·</span>
            <span>{tr('{0} 字符', [bodyText.length])}</span>
            {note.tags.slice(0, 3).map((tag) => (
              <span key={tag} className="meta-tag">
                #{tag}
              </span>
            ))}
          </div>

          {mode === 'reading' ? (
            <MarkdownBlocks
              content={content}
              notes={state.notes}
              onOpenTarget={openTarget}
              onToggleTodo={toggleTodo}
              anchorPrefix={`reading-${note.id}`}
            />
          ) : mode === 'source' ? (
            <textarea
              ref={sourceRef}
              data-role="body"
              className="source-editor"
              value={content}
              spellCheck={false}
              placeholder={tr('从一个想法开始。支持 Markdown、#标签与 [[双向链接]]。')}
              onChange={(event) => {
                latestContentRef.current = event.target.value;
                lastSelectionRef.current = {
                  noteId: note.id,
                  from: event.currentTarget.selectionStart ?? 0,
                  to: event.currentTarget.selectionEnd ?? 0
                };
                actions.updateNote(note.id, { content: event.target.value });
                autoSize(event.currentTarget, 460);
              }}
              onSelect={(event) => {
                lastSelectionRef.current = {
                  noteId: note.id,
                  from: event.currentTarget.selectionStart ?? 0,
                  to: event.currentTarget.selectionEnd ?? 0
                };
              }}
              onKeyDown={(event) => {
                if (event.key === 'Tab') {
                  event.preventDefault();
                  const textarea = event.currentTarget;
                  const start = textarea.selectionStart;
                  const next = `${textarea.value.slice(0, start)}  ${textarea.value.slice(textarea.selectionEnd)}`;
                  setNativeValue(textarea, next, start + 2, start + 2);
                }
              }}
            />
          ) : (
            <div className="live-editor">
              {parseBlocks(content).map((block) => {
                if (editing && editing.start === block.lineIndex) {
                  return (
                    <textarea
                      key={`editing-${block.id}`}
                      ref={liveRef}
                      data-role="body"
                      className="live-block-editor"
                      style={{ fontSize: state.settings.fontSize, lineHeight: 1.75 }}
                      value={editing.text}
                      spellCheck={false}
                      rows={1}
                      onChange={(event) => {
                        const lines = editing.base.split('\n');
                        const prefix =
                          lines.slice(0, editing.start).join('\n').length + (editing.start > 0 ? 1 : 0);
                        lastSelectionRef.current = {
                          noteId: note.id,
                          from: prefix + (event.currentTarget.selectionStart ?? 0),
                          to: prefix + (event.currentTarget.selectionEnd ?? 0)
                        };
                        updateEditing(event.target.value);
                      }}
                      onSelect={(event) => {
                        const lines = editing.base.split('\n');
                        const prefix =
                          lines.slice(0, editing.start).join('\n').length + (editing.start > 0 ? 1 : 0);
                        lastSelectionRef.current = {
                          noteId: note.id,
                          from: prefix + (event.currentTarget.selectionStart ?? 0),
                          to: prefix + (event.currentTarget.selectionEnd ?? 0)
                        };
                      }}
                      onBlur={finishEditing}
                      onKeyDown={(event) => {
                        if (event.key === 'Escape' || (event.key === 'Enter' && (event.ctrlKey || event.metaKey))) {
                          event.preventDefault();
                          event.currentTarget.blur();
                        }
                      }}
                    />
                  );
                }
                return (
                  <div key={block.id} className={flashLine === block.lineIndex ? 'flash-target' : undefined}>
                    <BlockView
                      block={block}
                      notes={state.notes}
                      notesById={new Map(state.notes.map((item) => [item.id, item]))}
                      onOpenTarget={openTarget}
                      onToggleTodo={toggleTodo}
                      readOnly={false}
                      onActivate={() => beginBlockEdit(block.lineIndex)}
                    />
                  </div>
                );
              })}
              <button type="button" className="live-tail" onClick={appendParagraph}>
                {parseBlocks(content).length === 0 ? tr('点按这里开始记录。支持 Markdown、#标签与 [[双向链接]]。') : ''}
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="editor-status">
        <button
          type="button"
          className="status-voice"
          title={tr('语音记录，打开离线语音速记')}
          onClick={() => actions.showToast('Windows 版请使用系统语音输入（Win+H）或输入法语音键')}
        >
          <MicGlyph size={15} color="var(--brand-ink)" />
          <span>{tr('语音记录')}</span>
        </button>
        {state.settings.editorViewStatus ? (
          <button
            type="button"
            className="status-text"
            onClick={() => setMode(mode === 'reading' ? 'live' : 'reading')}
          >
            {mode === 'reading' ? tr('阅读视图') : mode === 'source' ? tr('Markdown 源码') : tr('实时预览')}
          </button>
        ) : null}
        <button
          type="button"
          className="status-text"
          onClick={() => actions.setRightSidebar(true, 'outline')}
        >
          {derived.tr('{0} 个反向链接', [derived.links.filter((link) => link.targetId === note.id).length])}
        </button>
        <span className="status-text">{tr('{0} 字符', [bodyText.length])}</span>
        {pluginHost?.statusBarItems.map((item) => (
          <span key={`${item.pluginId}:${item.id}`} className="status-text plugin-status-item">
            {item.text}
          </span>
        ))}
        <button
          type="button"
          className={`save-status ${state.saveStatus}`}
          onClick={() => void actions.saveNow()}
        >
          {state.saveStatus === 'saving'
            ? tr('正在保存…')
            : state.saveStatus === 'error'
              ? tr('保存失败 · 点击重试')
              : tr('已保存到本机')}
        </button>
      </div>

      {toolsAnchor ? (
        <FloatingMenu x={toolsAnchor.x} y={toolsAnchor.y} width={224} entries={toolEntries} onClose={() => setToolsAnchor(null)} />
      ) : null}
      {moreAnchor ? (
        <FloatingMenu x={moreAnchor.x} y={moreAnchor.y} width={228} align="right" entries={moreEntries} onClose={() => setMoreAnchor(null)} />
      ) : null}
    </div>
  );
}
