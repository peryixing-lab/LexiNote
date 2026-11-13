import React, { useEffect, useRef } from 'react';

export interface MenuEntry {
  id?: string;
  label?: string;
  shortcut?: string;
  danger?: boolean;
  disabled?: boolean;
  separator?: boolean;
  header?: string;
  checked?: boolean;
  onSelect?: () => void;
}

interface FloatingMenuProps {
  x: number;
  y: number;
  width?: number;
  entries: MenuEntry[];
  onClose: () => void;
  align?: 'left' | 'right';
}

/** A small anchored menu; the desktop build uses plain DOM popovers instead of system menus. */
export function FloatingMenu({ x, y, width = 228, entries, onClose, align = 'left' }: FloatingMenuProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onPointerDown = (event: PointerEvent): void => {
      if (!ref.current?.contains(event.target as Node)) onClose();
    };
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('pointerdown', onPointerDown, true);
    window.addEventListener('keydown', onKeyDown);
    return () => {
      window.removeEventListener('pointerdown', onPointerDown, true);
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [onClose]);

  const left = Math.min(Math.max(8, align === 'left' ? x : x - width), window.innerWidth - width - 8);
  const top = Math.min(y, window.innerHeight - 16 - entries.length * 34);

  return (
    <div ref={ref} className="floating-menu" style={{ left, top, width }} role="menu">
      {entries.map((entry, index) => {
        if (entry.separator) return <div key={`sep-${index}`} className="menu-separator" />;
        if (entry.header) {
          return (
            <div key={`h-${index}`} className="menu-header">
              {entry.header}
            </div>
          );
        }
        return (
          <button
            key={entry.id ?? `${entry.label}-${index}`}
            type="button"
            className={`menu-item${entry.danger ? ' danger' : ''}${entry.checked ? ' checked' : ''}`}
            disabled={entry.disabled}
            role="menuitem"
            onClick={() => {
              onClose();
              entry.onSelect?.();
            }}
          >
            <span className="menu-check">{entry.checked ? '✓' : ''}</span>
            <span className="menu-label">{entry.label}</span>
            {entry.shortcut ? <span className="menu-shortcut">{entry.shortcut}</span> : null}
          </button>
        );
      })}
    </div>
  );
}
