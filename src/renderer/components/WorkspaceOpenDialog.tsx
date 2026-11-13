import React, { useEffect, useState } from 'react';
import { useStore } from '../store/AppStore';
import { CloseGlyph, PanelGlyph } from './Symbols';
import { Icon } from './Icon';

/**
 * HarmonyOS-style "open workspace" sheet. The chosen open mode is used for this
 * action; the "don't ask again" flag is a global preference and is deliberately
 * not stored inside the workspace.
 */
export function WorkspaceOpenDialog(): JSX.Element | null {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const prompt = state.workspacePrompt;
  const [suppress, setSuppress] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setSuppress(false);
    setBusy(false);
  }, [prompt?.vaultId]);

  if (!prompt) return null;

  const open = async (mode: 'current' | 'new'): Promise<void> => {
    if (busy) return;
    setBusy(true);
    try {
      await actions.confirmWorkspaceOpen(mode, suppress);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="overlay dialog-overlay"
      onPointerDown={(event) => {
        if (event.target === event.currentTarget && !busy) actions.cancelWorkspaceOpen();
      }}
    >
      <div
        className="dialog workspace-open-dialog"
        role="dialog"
        aria-modal="true"
        aria-label={tr('打开工作区')}
      >
        <div className="dialog-head">
          <div>
            <h2>{prompt.name}</h2>
            <p>{tr('选择此工作区的打开方式。')}</p>
          </div>
          <button
            type="button"
            className="icon-btn tiny"
            aria-label={tr('关闭')}
            onClick={() => actions.cancelWorkspaceOpen()}
          >
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>

        <div className="dialog-body workspace-open-body">
          <button
            type="button"
            className="workspace-open-option workspace-open-current"
            disabled={busy}
            onClick={() => void open('current')}
          >
            <span className="workspace-open-icon">
              <Icon name="note" size={19} />
            </span>
            <span className="workspace-open-text">
              <strong>{tr('在当前窗口打开')}</strong>
              <small>{tr('当前窗口切换到该工作区，已打开的标签会被替换。')}</small>
            </span>
          </button>

          <button
            type="button"
            className="workspace-open-option brand workspace-open-new"
            disabled={busy}
            onClick={() => void open('new')}
          >
            <span className="workspace-open-icon">
              <PanelGlyph size={19} color="var(--brand-ink)" />
            </span>
            <span className="workspace-open-text">
              <strong>{tr('在新窗口打开')}</strong>
              <small>{tr('保留当前窗口，并为该工作区新建一个窗口。')}</small>
            </span>
          </button>

          <label className="workspace-open-suppress">
            <input
              type="checkbox"
              checked={suppress}
              disabled={busy}
              onChange={(event) => setSuppress(event.target.checked)}
            />
            <span>{tr('下次不再提示')}</span>
          </label>

          <p className="workspace-open-hint">
            {tr(
              '此开关对所有工作区生效，不按工作区保存。勾选后会记住本次选择（当前窗口 / 新窗口），作为未单独设置工作区的默认打开方式；每个工作区仍可在「设置 → 编辑器」中单独设置。'
            )}
          </p>
        </div>

        <div className="dialog-foot">
          <span className="foot-hint">{tr('可在「设置 → 编辑器」中重新开启询问。')}</span>
          <button type="button" className="small-btn" disabled={busy} onClick={() => actions.cancelWorkspaceOpen()}>
            {tr('取消')}
          </button>
        </div>
      </div>
    </div>
  );
}
