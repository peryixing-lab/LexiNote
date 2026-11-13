import React from 'react';

interface GlyphProps {
  size?: number;
  color?: string;
  strokeWidth?: number;
}

/** Small UI glyphs that the HarmonyOS build uses from the system symbol font. */
export function ListGlyph({ size = 17, color = 'currentColor', strokeWidth = 1.7 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round">
      <path d="M8 6h12M8 12h12M8 18h12" />
      <circle cx="4.2" cy="6" r="1.1" fill={color} stroke="none" />
      <circle cx="4.2" cy="12" r="1.1" fill={color} stroke="none" />
      <circle cx="4.2" cy="18" r="1.1" fill={color} stroke="none" />
    </svg>
  );
}

export function CloseGlyph({ size = 10, color = 'currentColor', strokeWidth = 1.8 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round">
      <path d="M5 5l14 14M19 5L5 19" />
    </svg>
  );
}

export function ChevronGlyph({
  size = 12,
  color = 'currentColor',
  strokeWidth = 1.8,
  direction = 'right'
}: GlyphProps & { direction?: 'right' | 'down' | 'left' }): JSX.Element {
  const rotate = direction === 'down' ? 90 : direction === 'left' ? 180 : 0;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ transform: `rotate(${rotate}deg)`, transition: 'transform 150ms ease' }}
    >
      <path d="M9 5l7 7-7 7" />
    </svg>
  );
}

export function GearGlyph({ size = 19, color = 'currentColor', strokeWidth = 1.6 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3.1" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1 1.55V21a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-1.11-1.55 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.55-1H3a2 2 0 1 1 0-4h.09a1.7 1.7 0 0 0 1.55-1.11 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1-1.55V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1 1.55 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9a1.7 1.7 0 0 0 1.55 1H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.55 1Z" />
    </svg>
  );
}

export function PanelGlyph({ size = 20, color = 'currentColor', strokeWidth = 1.6 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4.5" width="18" height="15" rx="2.6" />
      <path d="M15 4.5v15" />
    </svg>
  );
}

export function MicGlyph({ size = 15, color = 'currentColor', strokeWidth = 1.7 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6" />
    </svg>
  );
}

export function PlusGlyph({ size = 16, color = 'currentColor', strokeWidth = 2 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function SearchGlyph({ size = 16, color = 'currentColor', strokeWidth = 1.8 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round">
      <circle cx="10.5" cy="10.5" r="6.2" />
      <path d="M15.2 15.2L20 20" />
    </svg>
  );
}

export function MoreGlyph({ size = 16, color = 'currentColor' }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={color} stroke="none">
      <circle cx="5" cy="12" r="1.6" />
      <circle cx="12" cy="12" r="1.6" />
      <circle cx="19" cy="12" r="1.6" />
    </svg>
  );
}

export function CheckGlyph({ size = 14, color = 'currentColor', strokeWidth = 2.1 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <path d="M4.5 12.5l5 5L19.5 7" />
    </svg>
  );
}

export function RestoreGlyph({ size = 15, color = 'currentColor', strokeWidth = 1.7 }: GlyphProps): JSX.Element {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 9a8 8 0 1 1 2 8" />
      <path d="M4 4v5h5" />
    </svg>
  );
}
