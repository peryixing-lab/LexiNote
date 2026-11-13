import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { MindMapColor, MindMapDoc, MindMapNode } from '../../shared/types';
import { computeMindMapLayout, mindMapToMarkdownOutline } from '../core/markdown';
import { Icon } from './Icon';
import { PlusGlyph } from './Symbols';

const COLOR_TAGS: MindMapColor[] = ['purple', 'indigo', 'teal', 'amber', 'rose'];

const TAG_COLORS: Record<MindMapColor, string> = {
  purple: '#6E44D9',
  indigo: '#5566C9',
  teal: '#2E8F8A',
  amber: '#C9822B',
  rose: '#C44D62'
};

function newId(): string {
  return `node-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function descendantIds(nodes: MindMapNode[], rootId: string): Set<string> {
  const result = new Set<string>([rootId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const node of nodes) {
      if (result.has(node.parentId) && !result.has(node.id)) {
        result.add(node.id);
        changed = true;
      }
    }
  }
  return result;
}

export function MindMapView(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const doc = derived.currentMap;
  const [selectedId, setSelectedId] = useState('');
  const [editingId, setEditingId] = useState('');
  const [draft, setDraft] = useState('');
  const [zoom, setZoom] = useState(1);
  const [drag, setDrag] = useState<{ id: string; x: number; y: number; baseX: number; baseY: number } | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const layout = useMemo(() => (doc ? computeMindMapLayout(doc) : []), [doc]);
  const selected = layout.find((node) => node.id === selectedId);

  useEffect(() => {
    setSelectedId('');
    setEditingId('');
    setZoom(1);
  }, [doc?.id]);

  useEffect(() => {
    if (editingId) {
      window.setTimeout(() => {
        inputRef.current?.focus();
        inputRef.current?.select();
      }, 20);
    }
  }, [editingId]);

  const save = useCallback(
    (next: MindMapDoc): void => {
      actions.updateMap({ ...next, updatedAt: Date.now() });
    },
    [actions]
  );

  const updateNode = useCallback(
    (id: string, patch: Partial<MindMapNode>): void => {
      if (!doc) return;
      save({ ...doc, nodes: doc.nodes.map((node) => (node.id === id ? { ...node, ...patch } : node)) });
    },
    [doc, save]
  );

  const addNode = (parentId: string, mode: 'child' | 'sibling'): void => {
    if (!doc) return;
    const parent = mode === 'sibling'
      ? doc.nodes.find((node) => node.id === parentId)
      : undefined;
    const realParentId = mode === 'sibling' ? parent?.parentId || doc.rootNodeId : parentId;
    const siblings = doc.nodes.filter((node) => node.parentId === realParentId);
    const order = siblings.reduce((max, node) => Math.max(max, node.order), 0) + 1;
    const id = newId();
    const node: MindMapNode = {
      id,
      parentId: realParentId,
      text: tr('新节点'),
      note: '',
      noteRefId: '',
      noteRefTitle: '',
      order,
      collapsed: false,
      colorTag: 'purple',
      level: 0,
      x: 0,
      y: 0,
      boxWidth: 136,
      boxHeight: 44,
      offsetX: 0,
      offsetY: 0
    };
    save({ ...doc, nodes: [...doc.nodes, node] });
    setSelectedId(id);
    setEditingId(id);
    setDraft(node.text);
  };

  const removeNode = (id: string): void => {
    if (!doc || id === doc.rootNodeId) return;
    const doomed = descendantIds(doc.nodes, id);
    save({ ...doc, nodes: doc.nodes.filter((node) => !doomed.has(node.id)) });
    if (doomed.has(selectedId)) setSelectedId('');
    if (doomed.has(editingId)) setEditingId('');
  };

  const commitText = (): void => {
    if (!doc || !editingId) return;
    const clean = draft.trim() || tr('未命名节点');
    updateNode(editingId, { text: clean });
    setEditingId('');
  };

  const cycleColor = (): void => {
    if (!doc || !selected) return;
    const index = COLOR_TAGS.indexOf(selected.colorTag);
    updateNode(selected.id, { colorTag: COLOR_TAGS[(index + 1) % COLOR_TAGS.length] });
  };

  const cycleLayout = (): void => {
    if (!doc) return;
    const order: MindMapDoc['layoutKind'][] = ['right', 'balanced', 'org'];
    const next = order[(order.indexOf(doc.layoutKind) + 1) % order.length];
    save({ ...doc, layoutKind: next });
  };

  const exportOutline = (): void => {
    if (!doc) return;
    const markdown = mindMapToMarkdownOutline(doc);
    void navigator.clipboard.writeText(markdown);
    actions.showToast('大纲已复制到剪贴板');
  };

  const convertToNote = (): void => {
    if (!doc) return;
    const markdown = mindMapToMarkdownOutline(doc);
    const id = actions.createNote('markdown', doc.title);
    actions.updateNote(id, { content: markdown, notebook: '思维导图' });
  };

  const onKeyDown = (event: React.KeyboardEvent): void => {
    if (!selected || editingId) return;
    if (event.key === 'Tab') {
      event.preventDefault();
      addNode(selected.id, 'child');
    } else if (event.key === 'Enter') {
      event.preventDefault();
      addNode(selected.id, 'sibling');
    } else if (event.key === 'F2') {
      event.preventDefault();
      setEditingId(selected.id);
      setDraft(selected.text);
    } else if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault();
      removeNode(selected.id);
    } else if (event.key === ' ') {
      event.preventDefault();
      updateNode(selected.id, { collapsed: !selected.collapsed });
    }
  };

  if (!doc) {
    return (
      <div className="editor-empty">
        <Icon name="mindmap" size={32} />
        <h2>{tr('选择一个思维导图')}</h2>
        <p>{tr('从左侧「可视化空间」打开导图，或新建一个。')}</p>
      </div>
    );
  }

  const bounds = layout.reduce(
    (acc, node) => ({
      width: Math.max(acc.width, node.x + node.boxWidth + 140),
      height: Math.max(acc.height, node.y + node.boxHeight + 120)
    }),
    { width: 640, height: 420 }
  );

  const edgePath = (parent: MindMapNode, child: MindMapNode): string => {
    const parentLeft = parent.x;
    const parentRight = parent.x + parent.boxWidth;
    const parentCenter = parent.y + parent.boxHeight / 2;
    const childLeft = child.x;
    const childRight = child.x + child.boxWidth;
    const childCenter = child.y + child.boxHeight / 2;
    const toLeft = child.x + child.boxWidth / 2 < parent.x + parent.boxWidth / 2;
    const x1 = toLeft ? parentLeft : parentRight;
    const x2 = toLeft ? childRight : childLeft;
    const bend = Math.max(28, Math.abs(x2 - x1) * 0.45);
    return `M ${x1} ${parentCenter} C ${x1 + (toLeft ? -bend : bend)} ${parentCenter}, ${x2 + (toLeft ? bend : -bend)} ${childCenter}, ${x2} ${childCenter}`;
  };

  return (
    <div className="mindmap-view" tabIndex={0} onKeyDown={onKeyDown}>
      <div className="mindmap-header">
        <input
          className="mindmap-title"
          value={doc.title}
          placeholder={tr('未命名导图')}
          onChange={(event) => save({ ...doc, title: event.target.value })}
          aria-label={tr('导图标题')}
        />
        <div className="mindmap-actions">
          <button type="button" className="small-btn" onClick={cycleLayout} title={tr('切换布局')}>
            {doc.layoutKind === 'right' ? tr('向右树') : doc.layoutKind === 'balanced' ? tr('平衡图') : tr('组织结构')}
          </button>
          <span className="toolbar-separator" />
          <button
            type="button"
            className="small-btn"
            disabled={!selected}
            onClick={() => selected && addNode(selected.id, 'child')}
          >
            <PlusGlyph size={13} /> {tr('子节点')}
          </button>
          <button
            type="button"
            className="small-btn"
            disabled={!selected || selected.id === doc.rootNodeId}
            onClick={() => selected && addNode(selected.id, 'sibling')}
          >
            {tr('同级')}
          </button>
          <button
            type="button"
            className="small-btn"
            disabled={!selected || selected.id === doc.rootNodeId}
            onClick={() => selected && removeNode(selected.id)}
          >
            {tr('删除')}
          </button>
          <button type="button" className="small-btn" disabled={!selected} onClick={cycleColor}>
            {tr('颜色')}
          </button>
          <span className="toolbar-separator" />
          <button type="button" className="small-btn" onClick={convertToNote}>
            {tr('转为笔记')}
          </button>
          <button type="button" className="small-btn" onClick={exportOutline}>
            {tr('复制大纲')}
          </button>
          <span className="toolbar-separator" />
          <button type="button" className="small-btn" onClick={() => setZoom((value) => Math.max(0.5, value - 0.1))}>
            −
          </button>
          <span className="zoom-value">{Math.round(zoom * 100)}%</span>
          <button type="button" className="small-btn" onClick={() => setZoom((value) => Math.min(1.8, value + 0.1))}>
            +
          </button>
          <button type="button" className="small-btn" onClick={() => setZoom(1)}>
            {tr('重置')}
          </button>
        </div>
      </div>

      <div className="mindmap-canvas-wrap" ref={scrollRef}>
        <div
          className="mindmap-canvas"
          style={{
            width: bounds.width,
            height: bounds.height,
            transform: `scale(${zoom})`,
            transformOrigin: '0 0'
          }}
          onPointerDown={(event) => {
            if (event.target === event.currentTarget) setSelectedId('');
          }}
          onPointerMove={(event) => {
            if (!drag) return;
            updateNode(drag.id, {
              offsetX: Math.round(drag.baseX + (event.clientX - drag.x) / zoom),
              offsetY: Math.round(drag.baseY + (event.clientY - drag.y) / zoom)
            });
          }}
          onPointerUp={() => setDrag(null)}
          onPointerLeave={() => setDrag(null)}
        >
          <svg className="mindmap-edges" width={bounds.width} height={bounds.height}>
            {layout.map((node) => {
              const parent = layout.find((item) => item.id === node.parentId);
              if (!parent) return null;
              return (
                <path
                  key={`edge-${node.id}`}
                  d={edgePath(parent, node)}
                  stroke={TAG_COLORS[node.colorTag]}
                  className="mindmap-edge"
                />
              );
            })}
          </svg>

          {layout.map((node) => {
            const color = TAG_COLORS[node.colorTag];
            const isRoot = node.id === doc.rootNodeId;
            const isSelected = selectedId === node.id;
            const children = doc.nodes.filter((item) => item.parentId === node.id);
            return (
              <div
                key={node.id}
                className={`mindmap-node${isRoot ? ' root' : ''}${isSelected ? ' selected' : ''}`}
                style={{
                  left: node.x,
                  top: node.y,
                  width: node.boxWidth,
                  minHeight: node.boxHeight,
                  borderColor: color
                }}
                onPointerDown={(event) => {
                  if ((event.target as HTMLElement).closest('button, input')) return;
                  (event.currentTarget.closest('.mindmap-view') as HTMLElement | null)?.focus();
                  setSelectedId(node.id);
                  setDrag({ id: node.id, x: event.clientX, y: event.clientY, baseX: node.offsetX, baseY: node.offsetY });
                  (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
                }}
                onDoubleClick={() => {
                  setEditingId(node.id);
                  setDraft(node.text);
                }}
              >
                {editingId === node.id ? (
                  <input
                    ref={inputRef}
                    className="mindmap-node-input"
                    value={draft}
                    onChange={(event) => setDraft(event.target.value)}
                    onBlur={commitText}
                    onKeyDown={(event) => {
                      if (event.key === 'Enter') {
                        event.preventDefault();
                        commitText();
                      }
                      if (event.key === 'Escape') setEditingId('');
                    }}
                  />
                ) : (
                  <div className="mindmap-node-label">{node.text}</div>
                )}
                {node.noteRefTitle ? (
                  <button
                    type="button"
                    className="mindmap-note-ref"
                    title={tr('打开关联笔记：{0}', [node.noteRefTitle])}
                    onClick={(event) => {
                      event.stopPropagation();
                      if (node.noteRefId) actions.openDocument(node.noteRefId);
                    }}
                  >
                    <Icon name="link" size={11} muted />
                    <span>{node.noteRefTitle}</span>
                  </button>
                ) : node.note ? (
                  <div className="mindmap-note">{node.note}</div>
                ) : null}
                {children.length > 0 ? (
                  <button
                    type="button"
                    className="mindmap-collapse"
                    aria-label={node.collapsed ? tr('展开分支') : tr('收起分支')}
                    onClick={(event) => {
                      event.stopPropagation();
                      updateNode(node.id, { collapsed: !node.collapsed });
                    }}
                  >
                    {node.collapsed ? `+${children.length}` : '−'}
                  </button>
                ) : null}
                <span className="mindmap-add" aria-hidden>
                  <button
                    type="button"
                    title={tr('添加子节点')}
                    onClick={(event) => {
                      event.stopPropagation();
                      addNode(node.id, 'child');
                    }}
                  >
                    +
                  </button>
                </span>
              </div>
            );
          })}
        </div>
      </div>

      <div className="mindmap-footer">
        <span>{tr('Tab 子节点 · Enter 同级 · F2 重命名 · Delete 删除 · 双击编辑')}</span>
        <span>{tr('拖动节点可调整位置，滚轮上方按钮缩放')}</span>
      </div>
    </div>
  );
}
