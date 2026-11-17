import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';

/** Shared bottom-up presentation for settings and trash, matching the desktop ports. */
export function WorkspaceSheet({
  open,
  onDismiss,
  label,
  className,
  children
}: {
  open: boolean;
  onDismiss: () => void;
  label: string;
  className: string;
  children: React.ReactNode;
}): JSX.Element | null {
  const [present, setPresent] = useState(open);
  const panelRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (open) setPresent(true);
  }, [open]);

  useEffect(() => {
    if (!present || open) return;
    // Read the exit duration from CSS. An end event from an interrupted entrance
    // must not unmount a panel that has just started sliding back down.
    const style = panelRef.current ? getComputedStyle(panelRef.current) : null;
    const milliseconds = (value: string): number => parseFloat(value) * (value.trim().endsWith('ms') ? 1 : 1000);
    const durations = style?.transitionDuration.split(',').map(milliseconds) ?? [0];
    const delays = style?.transitionDelay.split(',').map(milliseconds) ?? [0];
    const duration = Math.max(...durations.map((value, index) => value + delays[index % delays.length]));
    const timeout = window.setTimeout(() => setPresent(false), duration + 30);
    return () => window.clearTimeout(timeout);
  }, [open, present]);

  useLayoutEffect(() => {
    if (!present) return;
    const previousFocus = document.activeElement;
    const panel = panelRef.current;
    panel?.focus({ preventScroll: true });
    return () => {
      if (previousFocus instanceof HTMLElement && previousFocus.isConnected &&
          (panel?.contains(document.activeElement) || document.activeElement === document.body)) {
        previousFocus.focus({ preventScroll: true });
      }
    };
  }, [present]);

  if (!present) return null;

  return (
    <div
      className="workspace-sheet"
      data-open={open}
      onPointerDown={(event) => {
        if (event.target === event.currentTarget) onDismiss();
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          event.stopPropagation();
          onDismiss();
        }
        if (event.key !== 'Tab') return;
        const panel = panelRef.current;
        const focusable = Array.from(panel?.querySelectorAll<HTMLElement>(
          'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href], [tabindex="0"]'
        ) ?? []).filter((element) => element.getClientRects().length > 0);
        const first = focusable[0];
        const last = focusable.at(-1);
        if (!first) {
          event.preventDefault();
          panel?.focus();
        } else if (event.shiftKey && (document.activeElement === first || document.activeElement === panel)) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && (document.activeElement === last || document.activeElement === panel)) {
          event.preventDefault();
          first.focus();
        }
      }}
    >
      <div
        ref={panelRef}
        className={`workspace-sheet-panel ${className}`}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        tabIndex={-1}
      >
        {children}
      </div>
    </div>
  );
}
