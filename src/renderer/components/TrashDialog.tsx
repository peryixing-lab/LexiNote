import React, { useEffect, useState } from 'react';
import { useStore } from '../store/AppStore';
import { displayTitle } from '../core/markdown';
import { formatDateTime } from '../core/i18n';
import { Icon } from './Icon';
import { CloseGlyph, RestoreGlyph } from './Symbols';

export function TrashDialog(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const [confirmEmpty, setConfirmEmpty] = useState(false);
  const count = derived.trashNotes.length + derived.trashMaps.length;

  useEffect(() => {
    if (state.trashOpen) setConfirmEmpty(false);
  }, [state.trashOpen]);

  return (
    <>
        <div className="dialog-head">
          <div>
            <h2>{tr('回收站')}</h2>
            <p>{tr('{0} 个已删除项目', [count])}</p>
          </div>
          {count > 0 ? (
            <button type="button" className="small-btn danger trash-clear" onClick={() => setConfirmEmpty(true)}>{tr('清空')}</button>
          ) : null}
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => actions.setTrashOpen(false)}>
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>

        <div className="dialog-body">
          <p className="trash-description">{tr('已删除的笔记和导图会保留在这里，直到你永久删除。')}</p>
          {confirmEmpty && count > 0 ? (
            <div className="trash-confirm" role="alert">
              <span className="foot-hint danger-text">{tr('清空后无法恢复，确定吗？')}</span>
              <button type="button" className="small-btn danger" onClick={() => {
                setConfirmEmpty(false);
                actions.emptyTrash();
              }}>{tr('确认清空')}</button>
              <button type="button" className="small-btn" onClick={() => setConfirmEmpty(false)}>{tr('取消')}</button>
            </div>
          ) : null}
          {count === 0 ? (
            <div className="trash-empty">
              <div className="trash-empty-icon"><Icon name="trash" size={25} /></div>
              <h3>{tr('回收站是空的')}</h3>
              <p>{tr('删除的笔记会先来到这里，随时可以恢复。')}</p>
            </div>
          ) : null}

          {derived.trashNotes.map((note) => (
            <div className="trash-row" key={note.id}>
              <Icon name={note.noteType === 'study' ? 'study' : 'note'} size={16} muted />
              <div className="trash-text">
                <span className="trash-title">{displayTitle(note)}</span>
                <span className="trash-meta">
                  {note.notebook} · {formatDateTime(note.trashedAt, state.settings.language)}
                </span>
              </div>
              <button type="button" className="small-btn" onClick={() => actions.restoreNote(note.id)}>
                <RestoreGlyph size={13} /> {tr('恢复')}
              </button>
              <button type="button" className="small-btn danger" onClick={() => actions.deleteForever(note.id)}>
                {tr('永久删除')}
              </button>
            </div>
          ))}

          {derived.trashMaps.map((map) => (
            <div className="trash-row" key={map.id}>
              <Icon name="mindmap" size={16} muted />
              <div className="trash-text">
                <span className="trash-title">{map.title || tr('未命名导图')}</span>
                <span className="trash-meta">
                  {tr('思维导图')} · {formatDateTime(map.trashedAt, state.settings.language)}
                </span>
              </div>
              <button
                type="button"
                className="small-btn"
                onClick={() =>
                  actions.updateMap({ ...map, trashedAt: 0 })
                }
              >
                <RestoreGlyph size={13} /> {tr('恢复')}
              </button>
              <button type="button" className="small-btn danger" onClick={() => actions.deleteMapForever(map.id)}>
                {tr('永久删除')}
              </button>
            </div>
          ))}
        </div>

    </>
  );
}
