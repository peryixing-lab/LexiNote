import React, { useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { CanvasBoard, CanvasCard, MindMapColor } from '../../shared/types';
import { Icon } from './Icon';
import { PlusGlyph } from './Symbols';

const TAG_COLORS: Record<MindMapColor, string> = {
  purple: '#6E44D9',
  indigo: '#5566C9',
  teal: '#2E8F8A',
  amber: '#C9822B',
  rose: '#C44D62'
};

function newId(): string {
  return `card-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

export function CanvasView(): JSX.Element {
  const { actions, derived } = useStore();
  const { tr } = derived;
  const board = derived.currentCanvas as CanvasBoard | undefined;
  const [drag, setDrag] = useState<{ id: string; x: number; y: number; baseX: number; baseY: number } | null>(null);
  const [editing, setEditing] = useState('');

  const width = useMemo(
    () => Math.max(760, ...(board?.cards.map((card) => card.x + 300) ?? [])) + 80,
    [board?.cards]
  );
  const height = useMemo(
    () => Math.max(520, ...(board?.cards.map((card) => card.y + 220) ?? [])) + 80,
    [board?.cards]
  );

  const save = (next: CanvasBoard): void => actions.updateCanvas({ ...next, updatedAt: Date.now() });

  const updateCard = (id: string, patch: Partial<CanvasCard>): void => {
    if (!board) return;
    save({ ...board, cards: board.cards.map((card) => (card.id === id ? { ...card, ...patch } : card)) });
  };

  const addCard = (): void => {
    if (!board) return;
    const card: CanvasCard = {
      id: newId(),
      title: tr('新卡片'),
      content: '',
      noteRefId: '',
      noteRefTitle: '',
      x: 60 + (board.cards.length % 4) * 40,
      y: 60 + (board.cards.length % 4) * 36,
      colorTag: 'purple'
    };
    save({ ...board, cards: [...board.cards, card] });
    setEditing(card.id);
  };

  if (!board) {
    return (
      <div className="editor-empty">
        <Icon name="canvas" size={32} />
        <h2>{tr('选择一个白板')}</h2>
        <p>{tr('从左侧「可视化空间」打开白板，或新建一个。')}</p>
      </div>
    );
  }

  return (
    <div className="canvas-view">
      <div className="mindmap-header">
        <input
          className="mindmap-title"
          value={board.title}
          placeholder={tr('未命名白板')}
          onChange={(event) => save({ ...board, title: event.target.value })}
          aria-label={tr('白板标题')}
        />
        <div className="mindmap-actions">
          <button type="button" className="small-btn" onClick={addCard}>
            <PlusGlyph size={13} /> {tr('卡片')}
          </button>
          <button
            type="button"
            className="small-btn"
            onClick={() => {
              void navigator.clipboard.writeText(
                board.cards.map((card) => `## ${card.title}\n\n${card.content}`).join('\n\n')
              );
              actions.showToast('白板内容已复制');
            }}
          >
            {tr('复制内容')}
          </button>
          <button
            type="button"
            className="small-btn"
            onClick={() => {
              const id = actions.createNote('markdown', board.title);
              actions.updateNote(id, {
                notebook: '白板',
                content: `# ${board.title}\n\n${board.cards
                  .map((card) => `## ${card.title}\n\n${card.content}${card.noteRefTitle ? `\n\n关联：[[${card.noteRefTitle}]]` : ''}`)
                  .join('\n\n')}`
              });
            }}
          >
            {tr('转为笔记')}
          </button>
        </div>
      </div>

      <div className="canvas-board-wrap">
        <div
          className="canvas-board"
          style={{ width, height }}
          onPointerMove={(event) => {
            if (!drag) return;
            updateCard(drag.id, {
              x: Math.round(drag.baseX + (event.clientX - drag.x)),
              y: Math.round(drag.baseY + (event.clientY - drag.y))
            });
          }}
          onPointerUp={() => setDrag(null)}
          onDoubleClick={(event) => {
            if (event.target === event.currentTarget) addCard();
          }}
        >
          <svg className="canvas-edges" width={width} height={height}>
            {board.edges.map((edge) => {
              const from = board.cards.find((card) => card.id === edge.fromId);
              const to = board.cards.find((card) => card.id === edge.toId);
              if (!from || !to) return null;
              const x1 = from.x + 130;
              const y1 = from.y + 80;
              const x2 = to.x + 130;
              const y2 = to.y + 80;
              return (
                <g key={edge.id}>
                  <line x1={x1} y1={y1} x2={x2} y2={y2} className="canvas-edge" />
                  <text x={(x1 + x2) / 2} y={(y1 + y2) / 2 - 6} className="canvas-edge-label" textAnchor="middle">
                    {edge.label}
                  </text>
                </g>
              );
            })}
          </svg>

          {board.cards.map((card) => (
            <div
              key={card.id}
              className="canvas-card"
              style={{ left: card.x, top: card.y, borderTopColor: TAG_COLORS[card.colorTag] }}
              onPointerDown={(event) => {
                if ((event.target as HTMLElement).closest('textarea, input, button')) return;
                setDrag({ id: card.id, x: event.clientX, y: event.clientY, baseX: card.x, baseY: card.y });
                (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
              }}
              onDoubleClick={() => setEditing(card.id)}
            >
              <div className="canvas-card-head">
                {editing === card.id ? (
                  <input
                    autoFocus
                    className="canvas-card-title-input"
                    value={card.title}
                    onChange={(event) => updateCard(card.id, { title: event.target.value })}
                    onBlur={() => setEditing('')}
                  />
                ) : (
                  <h4>{card.title}</h4>
                )}
                <button
                  type="button"
                  className="canvas-card-delete"
                  aria-label={tr('删除卡片')}
                  onClick={() =>
                    save({
                      ...board,
                      cards: board.cards.filter((item) => item.id !== card.id),
                      edges: board.edges.filter((edge) => edge.fromId !== card.id && edge.toId !== card.id)
                    })
                  }
                >
                  ×
                </button>
              </div>
              <textarea
                className="canvas-card-body"
                value={card.content}
                placeholder={tr('写下想法…')}
                onChange={(event) => updateCard(card.id, { content: event.target.value })}
              />
              {card.noteRefTitle ? (
                <button
                  type="button"
                  className="canvas-card-ref"
                  onClick={() => card.noteRefId && actions.openDocument(card.noteRefId)}
                >
                  <Icon name="link" size={11} muted />
                  <span>{card.noteRefTitle}</span>
                </button>
              ) : null}
            </div>
          ))}

          {board.cards.length === 0 ? (
            <button type="button" className="canvas-empty" onClick={addCard}>
              <Icon name="canvas" size={28} />
              <span>{tr('双击或点击这里添加第一张卡片')}</span>
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
