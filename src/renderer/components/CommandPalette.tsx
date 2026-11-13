import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from '../store/AppStore';
import { usePluginHost } from '../plugins/PluginHostController';
import { COMMANDS } from '../core/commands';
import { displayTitle, extractSnippet } from '../core/markdown';
import { rankTitle } from '../core/search';
import { CloseGlyph } from './Symbols';
import { Icon } from './Icon';

interface PaletteItem {
  id: string;
  title: string;
  hint: string;
  kind: 'command' | 'note' | 'map' | 'canvas' | 'create';
  icon: string;
  group?: string;
}

export function CommandPalette(): JSX.Element {
  const { state, actions, derived } = useStore();
  const pluginHost = usePluginHost();
  const { tr } = derived;
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setQuery('');
    setIndex(0);
    window.setTimeout(() => inputRef.current?.focus(), 30);
  }, [state.paletteMode]);

  const items = useMemo<PaletteItem[]>(() => {
    const needle = query.trim();
    if (state.paletteMode === 'commands') {
      const builtIn = COMMANDS.map<PaletteItem>((command) => ({
        id: command.id,
        title: tr(command.title),
        hint: command.shortcut ?? '',
        kind: 'command',
        icon: '',
        group: tr(command.group)
      }));
      const pluginItems = pluginHost.commands
        .filter((cmd) => cmd.available)
        .map<PaletteItem>((cmd) => {
          const pluginName =
            pluginHost.records.find((record) => record.id === cmd.pluginId)?.name || cmd.pluginId;
          return {
            id: `plugin-cmd:${cmd.qualifiedId}`,
            title: cmd.title,
            hint: pluginName,
            kind: 'command',
            icon: 'sidebar_plugin',
            group: tr('插件')
          };
        });
      return builtIn
        .concat(pluginItems)
        .filter((item) => {
          if (!needle) return true;
          const rank = rankTitle(`${item.title} ${item.group ?? ''} ${item.hint}`, needle);
          return rank >= 0;
        })
        .sort((a, b) => rankTitle(a.title, needle) - rankTitle(b.title, needle));
    }

    const notes = state.notes
      .filter((note) => note.vaultId === state.activeVaultId && note.trashedAt === 0)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .map<PaletteItem>((note) => ({
        id: note.id,
        title: displayTitle(note),
        hint: extractSnippet(note).slice(0, 42),
        kind: 'note',
        icon: note.noteType === 'study' ? 'study' : 'note'
      }));
    const maps = state.maps
      .filter((map) => map.vaultId === state.activeVaultId && map.trashedAt === 0)
      .map<PaletteItem>((map) => ({
        id: `map:${map.id}`,
        title: map.title,
        hint: tr('思维导图'),
        kind: 'map',
        icon: 'mindmap'
      }));
    const canvases = state.canvases
      .filter((board) => board.vaultId === state.activeVaultId)
      .map<PaletteItem>((board) => ({
        id: `canvas:${board.id}`,
        title: board.title,
        hint: tr('白板'),
        kind: 'canvas',
        icon: 'canvas'
      }));
    const all = [...notes, ...maps, ...canvases];
    const filtered = needle
      ? all
          .map((item) => ({ item, rank: rankTitle(item.title, needle) }))
          .filter((entry) => entry.rank >= 0)
          .sort((a, b) => a.rank - b.rank)
          .map((entry) => entry.item)
      : all;
    if (needle) {
      filtered.unshift({
        id: `create:${needle}`,
        title: tr('新建笔记：{0}', [needle]),
        hint: tr('按 Enter 创建并打开'),
        kind: 'create',
        icon: 'plus'
      });
    }
    return filtered;
  }, [
    state.paletteMode,
    state.notes,
    state.maps,
    state.canvases,
    state.activeVaultId,
    pluginHost.commands,
    pluginHost.records,
    query,
    tr
  ]);

  useEffect(() => {
    setIndex(0);
  }, [query]);

  useEffect(() => {
    const list = listRef.current;
    const active = list?.querySelector<HTMLElement>('.palette-row.active');
    active?.scrollIntoView({ block: 'nearest' });
  }, [index]);

  const activate = (item: PaletteItem | undefined): void => {
    if (!item) return;
    actions.closePalette();
    if (item.kind === 'command') {
      if (item.id.startsWith('plugin-cmd:')) {
        void pluginHost.runCommand(item.id.slice('plugin-cmd:'.length));
      } else {
        void actions.executeCommand(item.id);
      }
    } else if (item.kind === 'create') {
      actions.createNote('markdown', item.id.substring('create:'.length));
    } else {
      actions.openDocument(item.id);
    }
  };

  const onKeyDown = (event: React.KeyboardEvent): void => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setIndex((current) => (items.length === 0 ? 0 : (current + 1) % items.length));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setIndex((current) => (items.length === 0 ? 0 : (current + items.length - 1) % items.length));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      activate(items[index]);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      actions.closePalette();
    }
  };

  return (
    <div className="overlay palette-overlay" onPointerDown={(event) => {
      if (event.target === event.currentTarget) actions.closePalette();
    }}>
      <div className="palette" role="dialog" aria-modal="true" aria-label={state.paletteMode === 'commands' ? tr('命令面板') : tr('快速切换文档')}>
        <div className="palette-head">
          <div>
            <h2>{state.paletteMode === 'commands' ? tr('命令面板') : tr('快速切换文档')}</h2>
            <p className="palette-count">
              {state.paletteMode === 'commands'
                ? tr('{0} 命令', [items.length])
                : tr('{0} 个文档', [items.length])}
            </p>
          </div>
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => actions.closePalette()}>
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>

        <div className="palette-search">
          <input
            ref={inputRef}
            value={query}
            placeholder={state.paletteMode === 'commands' ? tr('搜索命令…') : tr('搜索文档…')}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={onKeyDown}
            aria-label={tr('搜索')}
          />
        </div>
        <div className="palette-hint">
          <span>↑↓ {tr('选择')}</span>
          <span>·</span>
          <span>Enter {state.paletteMode === 'commands' ? tr('执行') : tr('打开')}</span>
          <span>·</span>
          <span>Esc {tr('关闭')}</span>
        </div>

        <div className="palette-list" ref={listRef} role="listbox">
          {items.length === 0 ? <div className="palette-empty">{tr('没有匹配的结果')}</div> : null}
          {items.map((item, rowIndex) => (
            <div
              key={`${item.kind}-${item.id}`}
              className={`palette-row${rowIndex === index ? ' active' : ''}`}
              role="option"
              aria-selected={rowIndex === index}
              onPointerMove={() => setIndex(rowIndex)}
              onClick={() => activate(item)}
            >
              {item.kind === 'command' ? (
                <span className="palette-command-glyph">
                  {rowIndex === index ? '›' : ''}
                </span>
              ) : (
                <Icon name={item.icon} size={15} muted={rowIndex !== index} />
              )}
              <span className="palette-row-text">
                <span className="palette-row-title">{item.title}</span>
                {item.hint ? <span className="palette-row-hint">{item.hint}</span> : null}
              </span>
            </div>
          ))}
        </div>

        <div className="palette-foot">
          <span>{state.paletteMode === 'commands' ? tr('命令面板') : tr('快速切换')}</span>
          <span>{tr('Enter 打开 · Esc 关闭')}</span>
        </div>
      </div>
    </div>
  );
}
