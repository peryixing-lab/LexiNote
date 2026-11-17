import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { formatDateTime } from '../core/i18n';
import { resolveLinkTargetPreview } from '../core/markdown';
import { useStore } from '../store/AppStore';

export interface LinkPreviewPopoverProps {
  target: string;
  vaultId?: string;
  children: React.ReactNode;
  onOpenTarget?: (target: string) => void;
  showTriggerButton?: boolean;
  className?: string;
}

/**
 * Hover and click-triggered quick preview card for internal [[wiki]] links,
 * graph nodes, backlinks, and candidate link suggestions.
 */
export const LinkPreviewPopover: React.FC<LinkPreviewPopoverProps> = ({
  target,
  vaultId,
  children,
  onOpenTarget,
  showTriggerButton = false,
  className = ''
}) => {
  const { state, derived, actions } = useStore();
  const tr = derived.tr;
  const anchorRef = useRef<HTMLSpanElement | null>(null);
  const cardRef = useRef<HTMLDivElement | null>(null);
  const openTimerRef = useRef<number | null>(null);
  const closeTimerRef = useRef<number | null>(null);
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<{ left: number; top: number; origin: string }>({
    left: 16,
    top: 16,
    origin: 'top left'
  });

  const preview = useMemo(
    () =>
      resolveLinkTargetPreview(
        target,
        derived.hydratedNotes,
        derived.links,
        vaultId ?? state.activeVaultId
      ),
    [target, derived.hydratedNotes, derived.links, vaultId, state.activeVaultId]
  );

  const clearTimers = useCallback(() => {
    if (openTimerRef.current !== null) {
      window.clearTimeout(openTimerRef.current);
      openTimerRef.current = null;
    }
    if (closeTimerRef.current !== null) {
      window.clearTimeout(closeTimerRef.current);
      closeTimerRef.current = null;
    }
  }, []);

  const updatePosition = useCallback(() => {
    const el = anchorRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const width = 324;
    const estHeight = 200;
    const left = Math.max(12, Math.min(window.innerWidth - width - 12, rect.left));
    const preferBelow = rect.bottom + 8 + estHeight <= window.innerHeight - 12;
    const top = preferBelow ? rect.bottom + 8 : Math.max(12, rect.top - estHeight - 8);
    setPos({ left, top, origin: preferBelow ? 'top left' : 'bottom left' });
  }, []);

  const scheduleOpen = useCallback(() => {
    clearTimers();
    openTimerRef.current = window.setTimeout(() => {
      updatePosition();
      setOpen(true);
    }, 180);
  }, [clearTimers, updatePosition]);

  const scheduleClose = useCallback(() => {
    clearTimers();
    closeTimerRef.current = window.setTimeout(() => {
      setOpen(false);
    }, 140);
  }, [clearTimers]);

  useEffect(() => clearTimers, [clearTimers]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    const onDown = (e: MouseEvent) => {
      const node = e.target as Node | null;
      if (!node) return;
      if (anchorRef.current?.contains(node) || cardRef.current?.contains(node)) return;
      setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('mousedown', onDown);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('mousedown', onDown);
    };
  }, [open]);

  const handleOpen = () => {
    setOpen(false);
    if (onOpenTarget) {
      onOpenTarget(target);
      return;
    }
    if (preview.exists && preview.noteId) {
      actions.openDocument(preview.noteId);
    } else if (preview.targetName) {
      actions.createNote('markdown', preview.targetName);
    }
  };

  return (
    <span
      ref={anchorRef}
      className={`link-preview-anchor ${className}`.trim()}
      onMouseEnter={scheduleOpen}
      onMouseLeave={scheduleClose}
    >
      {children}
      {showTriggerButton && (
        <button
          type="button"
          className="link-preview-trigger"
          title={tr('快速预览')}
          aria-label={tr('快速预览')}
          onClick={(e) => {
            e.stopPropagation();
            clearTimers();
            if (!open) updatePosition();
            setOpen((v) => !v);
          }}
        >
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none" aria-hidden="true">
            <path
              d="M1.5 8s2.4-4.2 6.5-4.2S14.5 8 14.5 8s-2.4 4.2-6.5 4.2S1.5 8 1.5 8Z"
              stroke="currentColor"
              strokeWidth="1.35"
              strokeLinejoin="round"
            />
            <circle cx="8" cy="8" r="1.9" stroke="currentColor" strokeWidth="1.35" />
          </svg>
        </button>
      )}
      {open &&
        createPortal(
          <div
            ref={cardRef}
            className="link-preview-popover"
            role="dialog"
            aria-label={preview.title || target}
            style={{ left: `${pos.left}px`, top: `${pos.top}px`, transformOrigin: pos.origin }}
            onMouseEnter={clearTimers}
            onMouseLeave={scheduleClose}
          >
            <div className="link-preview-head">
              <strong className="link-preview-title">{preview.title || preview.targetName || target}</strong>
              <span className={`link-preview-badge ${preview.exists ? '' : 'missing'}`}>
                {preview.exists ? preview.notebook : tr('未创建')}
              </span>
            </div>
            {preview.anchor && <div className="link-preview-sub">#{preview.anchor}</div>}
            <p className="link-preview-snippet">{preview.snippet}</p>
            {preview.exists && preview.tags.length > 0 && (
              <div className="link-preview-tags">
                {preview.tags.map((tag) => (
                  <span key={tag} className="tag-pill">
                    #{tag}
                  </span>
                ))}
              </div>
            )}
            <div className="link-preview-foot">
              <span className="link-preview-meta">
                {preview.exists
                  ? tr('链接 {0} · 反链 {1} · {2}', [
                      preview.outgoingCount,
                      preview.backlinkCount,
                      formatDateTime(
                        preview.lastOpenedAt > 0 ? preview.lastOpenedAt : preview.updatedAt,
                        state.settings.language
                      )
                    ])
                  : tr('目标笔记尚不存在')}
              </span>
              <button type="button" className="btn-inline accent" onClick={handleOpen}>
                {preview.exists ? tr('打开笔记') : tr('创建并打开')}
              </button>
            </div>
          </div>,
          document.body
        )}
    </span>
  );
};
