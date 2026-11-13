import React from 'react';

const ICON_URLS = import.meta.glob('../assets/icons/*.svg', {
  eager: true,
  query: '?url',
  import: 'default'
}) as Record<string, string>;

const NAME_ALIASES: Record<string, string> = {
  vault: 'dock_vault',
  home: 'dock_home',
  explore: 'dock_explore',
  profile: 'dock_profile',
  spark: 'star',
  'chevron-right': 'chevron',
  'chevron_left': 'back',
  back: 'back',
  panel_shown: 'dock_panel_shown',
  panel_hidden: 'dock_panel_hidden'
};

function urlFor(name: string): string | undefined {
  const file = NAME_ALIASES[name] ?? name;
  const direct = ICON_URLS[`../assets/icons/ic_${file}.svg`];
  if (direct) return direct;
  const muted = ICON_URLS[`../assets/icons/ic_${file}_muted.svg`];
  return muted;
}

export interface IconProps {
  name: string;
  size?: number;
  muted?: boolean;
  color?: string;
  className?: string;
  style?: React.CSSProperties;
  title?: string;
}

/**
 * Icons come from the HarmonyOS project's own SVG set. They are painted with a
 * CSS mask so one asset can take the brand or muted color, matching the
 * original LexiIcon colorFilter behavior without duplicating files.
 */
export function Icon({ name, size = 18, muted = false, color, className = '', style, title }: IconProps): JSX.Element | null {
  const url = urlFor(name.replace(/_muted$/, ''));
  if (!url) return null;
  const tint = color ?? (muted ? 'var(--text-2)' : 'var(--brand)');
  return (
    <span
      className={`lexi-icon ${className}`}
      title={title}
      style={{
        width: size,
        height: size,
        backgroundColor: tint,
        maskImage: `url("${url}")`,
        WebkitMaskImage: `url("${url}")`,
        ...style
      }}
    />
  );
}
