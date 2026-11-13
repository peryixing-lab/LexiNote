import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from '../store/AppStore';
import { displayTitle, extractSnippet } from '../core/markdown';
import { Icon } from './Icon';

interface GraphNode {
  id: string;
  label: string;
  kind: 'note' | 'map' | 'tag';
  noteType?: string;
  degree: number;
  x: number;
  y: number;
}

interface GraphEdge {
  source: string;
  target: string;
  kind: 'link' | 'map' | 'tag';
}

const WIDTH = 1000;
const HEIGHT = 680;

function hash(text: string): number {
  let value = 2166136261;
  for (let index = 0; index < text.length; index++) {
    value ^= text.charCodeAt(index);
    value = Math.imul(value, 16777619);
  }
  return (value >>> 0) / 4294967295;
}

function layoutGraph(nodes: GraphNode[], edges: GraphEdge[]): GraphNode[] {
  if (nodes.length === 0) return [];
  const positions = new Map<string, { x: number; y: number; vx: number; vy: number }>();
  nodes.forEach((node, index) => {
    const angle = (index / nodes.length) * Math.PI * 2;
    const radius = Math.min(WIDTH, HEIGHT) * 0.32 + hash(node.id) * 40;
    positions.set(node.id, {
      x: WIDTH / 2 + Math.cos(angle) * radius,
      y: HEIGHT / 2 + Math.sin(angle) * radius,
      vx: 0,
      vy: 0
    });
  });
  const iterations = nodes.length > 80 ? 160 : 280;
  for (let step = 0; step < iterations; step++) {
    const cooling = 1 - step / iterations;
    for (let i = 0; i < nodes.length; i++) {
      const a = positions.get(nodes[i].id);
      if (!a) continue;
      for (let j = i + 1; j < nodes.length; j++) {
        const b = positions.get(nodes[j].id);
        if (!b) continue;
        let dx = a.x - b.x;
        let dy = a.y - b.y;
        let distance = Math.sqrt(dx * dx + dy * dy);
        if (distance < 0.01) {
          dx = 0.6;
          dy = 0.4;
          distance = 0.72;
        }
        const minDistance = nodes[i].kind === 'note' && nodes[j].kind === 'note' ? 96 : 82;
        const force = (14000 / (distance * distance)) * cooling + (distance < minDistance ? (minDistance - distance) * 0.9 : 0);
        const fx = (dx / distance) * force;
        const fy = (dy / distance) * force;
        a.vx += fx;
        a.vy += fy;
        b.vx -= fx;
        b.vy -= fy;
      }
    }
    for (const edge of edges) {
      const a = positions.get(edge.source);
      const b = positions.get(edge.target);
      if (!a || !b) continue;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy));
      const ideal = edge.kind === 'tag' ? 96 : 128;
      const force = (distance - ideal) * 0.014 * cooling;
      const fx = (dx / distance) * force;
      const fy = (dy / distance) * force;
      a.vx += fx;
      a.vy += fy;
      b.vx -= fx;
      b.vy -= fy;
    }
    for (const node of nodes) {
      const p = positions.get(node.id);
      if (!p) continue;
      p.vx += (WIDTH / 2 - p.x) * 0.0022 * cooling;
      p.vy += (HEIGHT / 2 - p.y) * 0.0022 * cooling;
      p.x += Math.max(-16, Math.min(16, p.vx));
      p.y += Math.max(-16, Math.min(16, p.vy));
      p.vx *= 0.72;
      p.vy *= 0.72;
      p.x = Math.max(56, Math.min(WIDTH - 56, p.x));
      p.y = Math.max(48, Math.min(HEIGHT - 48, p.y));
    }
  }
  return nodes.map((node) => {
    const p = positions.get(node.id);
    return { ...node, x: p?.x ?? WIDTH / 2, y: p?.y ?? HEIGHT / 2 };
  });
}

export function GraphView(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const [showMaps, setShowMaps] = useState(true);
  const [showTags, setShowTags] = useState(true);
  const [selected, setSelected] = useState('');
  const [scale, setScale] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const dragRef = useRef<{ x: number; y: number; ox: number; oy: number } | null>(null);

  const graph = useMemo(() => {
    const notes = state.notes.filter((note) => note.vaultId === state.activeVaultId && note.trashedAt === 0);
    const maps = state.maps.filter(
      (map) => map.vaultId === state.activeVaultId && map.trashedAt === 0 && showMaps
    );
    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];
    const pushEdge = (source: string, target: string, kind: GraphEdge['kind']): void => {
      if (!edges.some((edge) => edge.source === source && edge.target === target)) {
        edges.push({ source, target, kind });
      }
    };
    const degree = new Map<string, number>();
    const bump = (id: string): void => {
      degree.set(id, (degree.get(id) || 0) + 1);
    };

    for (const note of notes) {
      nodes.push({
        id: note.id,
        label: displayTitle(note),
        kind: 'note',
        noteType: note.noteType,
        degree: 0,
        x: 0,
        y: 0
      });
    }
    for (const map of maps) {
      nodes.push({ id: `map:${map.id}`, label: map.title, kind: 'map', degree: 0, x: 0, y: 0 });
    }
    const noteIds = new Set(notes.map((note) => note.id));
    for (const link of derived.links) {
      if (noteIds.has(link.sourceId) && link.targetId && noteIds.has(link.targetId)) {
        pushEdge(link.sourceId, link.targetId, 'link');
        bump(link.sourceId);
        bump(link.targetId);
      }
    }
    for (const map of maps) {
      for (const node of map.nodes) {
        if (node.noteRefId && noteIds.has(node.noteRefId)) {
          pushEdge(`map:${map.id}`, node.noteRefId, 'map');
          bump(`map:${map.id}`);
          bump(node.noteRefId);
        }
      }
    }
    if (showTags) {
      const tags = new Map<string, string[]>();
      for (const note of notes) {
        for (const tag of note.tags) {
          const list = tags.get(tag) ?? [];
          list.push(note.id);
          tags.set(tag, list);
        }
      }
      for (const [tag, ids] of tags) {
        if (ids.length < 1) continue;
        nodes.push({ id: `tag:${tag}`, label: `#${tag}`, kind: 'tag', degree: ids.length, x: 0, y: 0 });
        for (const id of ids) {
          pushEdge(`tag:${tag}`, id, 'tag');
          bump(id);
        }
      }
    }
    for (const node of nodes) node.degree = degree.get(node.id) || 0;
    return { nodes: layoutGraph(nodes, edges), edges };
  }, [state.notes, state.maps, state.activeVaultId, derived.links, showMaps, showTags]);

  const selectedNode = graph.nodes.find((node) => node.id === selected);
  const selectedNote = selectedNode?.kind === 'note'
    ? state.notes.find((note) => note.id === selectedNode.id)
    : undefined;
  const related = graph.edges.filter((edge) => edge.source === selected || edge.target === selected);

  useEffect(() => {
    setSelected('');
  }, [state.activeVaultId]);

  const openNode = (id: string): void => {
    if (id.startsWith('tag:')) {
      actions.setSearchText(`tag:${id.substring(4)}`);
      actions.setSection(1);
      actions.setSidebarOpen(true);
      return;
    }
    actions.openDocument(id);
  };

  return (
    <div className="graph-view">
      <div className="aux-header">
        <div>
          <h1>{tr('笔记关联')}</h1>
          <p>
            {derived.activeVault?.name ?? tr('工作区')}
            {derived.activeProject ? ` · ${derived.activeProject.name}` : ''} · {graph.nodes.length}{' '}
            {tr('个节点')} · {graph.edges.length} {tr('条连接')}
          </p>
        </div>
        <div className="graph-controls">
          <label className="check-chip">
            <input type="checkbox" checked={showMaps} onChange={(event) => setShowMaps(event.target.checked)} />
            {tr('显示导图')}
          </label>
          <label className="check-chip">
            <input type="checkbox" checked={showTags} onChange={(event) => setShowTags(event.target.checked)} />
            {tr('显示标签')}
          </label>
          <button type="button" className="small-btn" onClick={() => setScale((value) => Math.min(2, value + 0.15))}>
            +
          </button>
          <button type="button" className="small-btn" onClick={() => setScale((value) => Math.max(0.5, value - 0.15))}>
            −
          </button>
          <button
            type="button"
            className="small-btn"
            onClick={() => {
              setScale(1);
              setOffset({ x: 0, y: 0 });
            }}
          >
            {tr('重置')}
          </button>
        </div>
      </div>

      <div className="graph-body">
        <div
          className={`graph-canvas${dragRef.current ? ' dragging' : ''}`}
          onPointerDown={(event) => {
            if ((event.target as SVGElement).closest('.graph-node')) return;
            dragRef.current = { x: event.clientX, y: event.clientY, ox: offset.x, oy: offset.y };
            (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
          }}
          onPointerMove={(event) => {
            if (!dragRef.current) return;
            setOffset({
              x: dragRef.current.ox + (event.clientX - dragRef.current.x),
              y: dragRef.current.oy + (event.clientY - dragRef.current.y)
            });
          }}
          onPointerUp={() => {
            dragRef.current = null;
          }}
          onWheel={(event) => {
            event.preventDefault();
            setScale((value) => Math.max(0.5, Math.min(2, value - event.deltaY * 0.0012)));
          }}
        >
          <svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} className="graph-svg">
            <g transform={`translate(${offset.x} ${offset.y}) scale(${scale})`}>
              {graph.edges.map((edge, index) => {
                const source = graph.nodes.find((node) => node.id === edge.source);
                const target = graph.nodes.find((node) => node.id === edge.target);
                if (!source || !target) return null;
                const active = selected === edge.source || selected === edge.target;
                return (
                  <line
                    key={`${edge.source}-${edge.target}-${index}`}
                    x1={source.x}
                    y1={source.y}
                    x2={target.x}
                    y2={target.y}
                    className={`graph-edge ${edge.kind}${active ? ' active' : ''}`}
                  />
                );
              })}
              {graph.nodes.map((node) => {
                const radius =
                  node.kind === 'note'
                    ? 13 + Math.min(9, node.degree * 1.5)
                    : node.kind === 'map'
                      ? 11
                      : 8;
                const active = selected === node.id;
                return (
                  <g
                    key={node.id}
                    className={`graph-node ${node.kind}${active ? ' active' : ''}`}
                    transform={`translate(${node.x} ${node.y})`}
                    onClick={(event) => {
                      event.stopPropagation();
                      setSelected(node.id);
                    }}
                    onDoubleClick={(event) => {
                      event.stopPropagation();
                      openNode(node.id);
                    }}
                  >
                    {node.kind === 'map' ? (
                      <rect x={-radius} y={-radius} width={radius * 2} height={radius * 2} rx={3} transform="rotate(45)" className="node-shape" />
                    ) : (
                      <circle r={radius} className="node-shape" />
                    )}
                    <text className="graph-label" y={radius + 15} textAnchor="middle">
                      {node.label.length > 14 ? `${node.label.slice(0, 13)}…` : node.label}
                    </text>
                  </g>
                );
              })}
            </g>
          </svg>
          {graph.nodes.length === 0 ? (
            <div className="graph-empty">
              <Icon name="graph" size={28} />
              <p>{tr('还没有可展示的连接')}</p>
              <span>{tr('用 [[双向链接]] 连接笔记，或打开已有的思维导图。')}</span>
            </div>
          ) : null}
        </div>

        <aside className="graph-panel">
          {selectedNote ? (
            <>
              <button type="button" className="graph-open" onClick={() => actions.openDocument(selectedNote.id)}>
                {tr('打开笔记')}
              </button>
              <h3>{displayTitle(selectedNote)}</h3>
              <p className="graph-snippet">{extractSnippet(selectedNote).slice(0, 180)}</p>
              <div className="graph-meta">
                <span>{selectedNote.notebook}</span>
                <span>·</span>
                <span>{related.length} {tr('条连接')}</span>
              </div>
              {selectedNote.tags.length > 0 ? (
                <div className="tag-wrap">
                  {selectedNote.tags.map((tag) => (
                    <span className="tag-pill" key={tag}>
                      #{tag}
                    </span>
                  ))}
                </div>
              ) : null}
              <div className="right-section-title spaced">{tr('连接的笔记')}</div>
              {related.map((edge) => {
                const other = edge.source === selected ? edge.target : edge.source;
                const node = graph.nodes.find((item) => item.id === other);
                if (!node) return null;
                return (
                  <button key={other} type="button" className="right-link" onClick={() => setSelected(other)}>
                    {node.label}
                  </button>
                );
              })}
            </>
          ) : (
            <div className="graph-hint">
              <h3>{tr('关系图谱')}</h3>
              <p>{tr('点击节点查看连接的笔记，双击直接打开。拖动空白处平移，滚轮缩放。')}</p>
              <div className="graph-legend">
                <span>
                  <i className="legend-dot note" />
                  {tr('笔记')}
                </span>
                <span>
                  <i className="legend-dot map" />
                  {tr('思维导图')}
                </span>
                <span>
                  <i className="legend-dot tag" />
                  {tr('标签')}
                </span>
              </div>
              {derived.mentions.length > 0 ? (
                <>
                  <div className="right-section-title spaced">{tr('未连接的提及')}</div>
                  {derived.mentions.slice(0, 6).map((mention) => (
                    <button
                      key={`${mention.sourceId}-${mention.targetId}`}
                      type="button"
                      className="mention-row"
                      onClick={() => actions.openDocument(mention.sourceId)}
                    >
                      <span>{mention.sourceTitle}</span>
                      <small>{tr('提及「{0}」', [mention.targetTitle])}</small>
                    </button>
                  ))}
                </>
              ) : null}
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}
