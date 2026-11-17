/**
 * Theme engine ported from the HarmonyOS app (core/LexiTheme.ets).
 * The palette is computed from the accent color with WCAG contrast checks, then
 * published as CSS custom properties so every surface reacts to one state change.
 */

export interface LexiThemePalette {
  background: string;
  surface: string;
  soft_surface: string;
  text_primary: string;
  text_secondary: string;
  brand: string;
  brand_soft: string;
  brand_ink: string;
  inverse_text: string;
  divider: string;
  success: string;
  warning: string;
  error: string;
  hero: string;
  dock_light: string;
  dock_fallback: string;
  dock_surface: string;
  title_chip_active: string;
  title_chip_surface: string;
  title_scrim: string;
  canvas_surface: string;
  workspace_rail: string;
  workspace_sidebar: string;
  workspace_tabs: string;
  workspace_page: string;
  workspace_inspector: string;
  workspace_selection: string;
  workspace_line: string;
}

export const DEFAULT_ACCENT = '#6E44D9';

export const THEME_PRESETS: { color: string; label: string; labelEn: string }[] = [
  { color: '#6E44D9', label: '鸢尾紫', labelEn: 'Iris' },
  { color: '#D94B73', label: '玫瑰粉', labelEn: 'Rose' },
  { color: '#DC8137', label: '暖杏橙', labelEn: 'Apricot' },
  { color: '#308F70', label: '森林绿', labelEn: 'Forest' },
  { color: '#3688CD', label: '晴空蓝', labelEn: 'Sky' },
  { color: '#68738A', label: '石墨灰', labelEn: 'Graphite' }
];

export function validAccent(color: string): boolean {
  return /^#[0-9a-fA-F]{6}$/.test(color);
}

export function mix(base: string, tint: string, amount: number): string {
  let result = '#';
  for (let channel = 0; channel < 3; channel++) {
    const offset = 1 + channel * 2;
    const first = parseInt(base.substring(offset, offset + 2), 16);
    const second = parseInt(tint.substring(offset, offset + 2), 16);
    result += Math.round(first * (1 - amount) + second * amount)
      .toString(16)
      .padStart(2, '0');
  }
  return result.toUpperCase();
}

function luminance(color: string): number {
  const channels: number[] = [];
  for (let index = 0; index < 3; index++) {
    const channel = parseInt(color.substring(1 + index * 2, 3 + index * 2), 16) / 255;
    channels.push(channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4));
  }
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}

export function contrast(first: string, second: string): number {
  const a = luminance(first);
  const b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

function readable(accent: string, background: string, dark: boolean): string {
  const target = dark ? '#FFFFFF' : '#000000';
  for (let step = 0; step <= 100; step++) {
    const adjusted = mix(accent, target, step / 100);
    if (contrast(adjusted, background) >= 4.5) return adjusted;
  }
  return target;
}

function emptyPalette(): LexiThemePalette {
  return {
    background: '',
    surface: '',
    soft_surface: '',
    text_primary: '',
    text_secondary: '',
    brand: '',
    brand_soft: '',
    brand_ink: '',
    inverse_text: '',
    divider: '',
    success: '',
    warning: '',
    error: '',
    hero: '',
    dock_light: '',
    dock_fallback: '',
    dock_surface: '',
    title_chip_active: '',
    title_chip_surface: '',
    title_scrim: '',
    canvas_surface: '',
    workspace_rail: '',
    workspace_sidebar: '',
    workspace_tabs: '',
    workspace_page: '',
    workspace_inspector: '',
    workspace_selection: '',
    workspace_line: ''
  };
}

export function paletteFor(accent: string = DEFAULT_ACCENT, dark = false): LexiThemePalette {
  const tint = validAccent(accent) ? accent : DEFAULT_ACCENT;
  const palette = emptyPalette();
  palette.background = mix(dark ? '#111318' : '#F7F8FA', tint, dark ? 0.07 : 0.035);
  palette.surface = mix(dark ? '#202229' : '#FFFFFF', tint, dark ? 0.08 : 0.012);
  palette.soft_surface = mix(dark ? '#2B2D35' : '#EEF0F4', tint, dark ? 0.1 : 0.05);
  palette.text_primary = mix(dark ? '#F5F6FA' : '#1A1D24', tint, dark ? 0.025 : 0.08);
  palette.text_secondary = mix(dark ? '#C6CAD4' : '#535863', tint, 0.1);
  palette.brand_soft = mix(dark ? '#292C34' : '#EDF0F5', tint, dark ? 0.23 : 0.08);
  palette.workspace_selection = mix(dark ? '#30333B' : '#E2E5EC', tint, dark ? 0.3 : 0.12);
  palette.text_primary = readable(readable(palette.text_primary, palette.workspace_selection, dark), palette.soft_surface, dark);
  palette.text_secondary = readable(readable(palette.text_secondary, palette.workspace_selection, dark), palette.soft_surface, dark);
  palette.brand = readable(readable(tint, palette.workspace_selection, dark), palette.soft_surface, dark);
  palette.brand_ink = palette.brand;
  palette.inverse_text = contrast('#FFFFFF', palette.brand) >= 4.5 ? '#FFFFFF' : '#111318';
  palette.divider = mix(dark ? '#41444D' : '#E5E7EC', tint, 0.12);
  palette.success = dark ? '#86CDB5' : '#348672';
  palette.warning = dark ? '#F0B86E' : '#C9822B';
  palette.error = dark ? '#FF9EAB' : '#C44D62';
  palette.hero = palette.brand_soft;
  palette.dock_light = mix(tint, '#FFFFFF', dark ? 0.45 : 0.68);
  palette.dock_fallback = (dark ? '#F0' : '#EE') + palette.surface.substring(1);
  palette.dock_surface = (dark ? '#D9' : '#70') + palette.surface.substring(1);
  palette.title_chip_active = (dark ? '#CC' : '#38') + tint.substring(1);
  palette.title_chip_surface = (dark ? '#CC' : '#66') + palette.surface.substring(1);
  palette.title_scrim = (dark ? '#E6' : '#00') + palette.background.substring(1);
  palette.canvas_surface = palette.background;
  palette.workspace_rail = mix(dark ? '#1A1C23' : '#E8EBF0', tint, dark ? 0.12 : 0.07);
  palette.workspace_sidebar = mix(dark ? '#21232B' : '#F4F5F7', tint, dark ? 0.1 : 0.05);
  palette.workspace_tabs = mix(dark ? '#1D1F27' : '#EEF0F4', tint, dark ? 0.1 : 0.06);
  palette.workspace_page = mix(dark ? '#17191F' : '#FFFFFF', tint, dark ? 0.06 : 0.004);
  palette.workspace_inspector = mix(dark ? '#1D1F26' : '#FFFFFF', tint, dark ? 0.08 : 0.025);
  palette.workspace_line = palette.divider;
  return palette;
}

/** The brand "original" palette keeps the purple-black identity in dark mode. */
export function originalPalette(dark = false): LexiThemePalette {
  const palette = emptyPalette();
  if (dark) {
    Object.assign(palette, {
      background: '#12131B',
      surface: '#20212D',
      soft_surface: '#2D2F3E',
      text_primary: '#F5F3FB',
      text_secondary: '#C6C2D4',
      brand: '#C7B3FF',
      brand_soft: '#3A3157',
      brand_ink: '#E0D4FF',
      inverse_text: '#20162E',
      divider: '#4B465F',
      success: '#86CDB5',
      warning: '#F0B86E',
      error: '#FF9EAB',
      hero: '#29233D',
      dock_light: '#B9A1EB',
      dock_fallback: '#F020212D',
      dock_surface: '#D920212D',
      title_chip_active: '#CC4B396E',
      title_chip_surface: '#CC2A2B3A',
      title_scrim: '#E612131B',
      canvas_surface: '#181A24',
      workspace_rail: '#1D1A29',
      workspace_sidebar: '#242030',
      workspace_tabs: '#211E2C',
      workspace_page: '#191822',
      workspace_inspector: '#1E1C29',
      workspace_selection: '#403355',
      workspace_line: '#3B354C'
    });
  } else {
    Object.assign(palette, {
      background: '#F6F4FB',
      surface: '#FFFFFF',
      soft_surface: '#EEEAF8',
      text_primary: '#231B36',
      text_secondary: '#6E6385',
      brand: '#6E44D9',
      brand_soft: '#E9E0FF',
      brand_ink: '#4E2B9E',
      inverse_text: '#FFFFFF',
      divider: '#E4DDF2',
      success: '#348672',
      warning: '#C9822B',
      error: '#C44D62',
      hero: '#E9E0FF',
      dock_light: '#D8C7FF',
      dock_fallback: '#EEFFFFFF',
      dock_surface: '#26FFFFFF',
      title_chip_active: '#386E44D9',
      title_chip_surface: '#33FFFFFF',
      title_scrim: '#00F6F4FB',
      canvas_surface: '#1C162B',
      workspace_rail: '#EAE4F5',
      workspace_sidebar: '#F4F0FA',
      workspace_tabs: '#F0EBF8',
      workspace_page: '#FFFFFF',
      workspace_inspector: '#FCFAFF',
      workspace_selection: '#E4D8FA',
      workspace_line: '#DDD5EA'
    });
  }
  return palette;
}

export function buildPalette(accent: string, dark: boolean, mode: 'original' | 'preset' | 'custom'): LexiThemePalette {
  if (mode === 'original' && accent.toUpperCase() === DEFAULT_ACCENT) {
    return originalPalette(dark);
  }
  return paletteFor(accent, dark);
}

const CSS_VARIABLES: Record<keyof LexiThemePalette, string> = {
  background: '--bg',
  surface: '--surface',
  soft_surface: '--soft-surface',
  text_primary: '--text',
  text_secondary: '--text-2',
  brand: '--brand',
  brand_soft: '--brand-soft',
  brand_ink: '--brand-ink',
  inverse_text: '--inverse-text',
  divider: '--divider',
  success: '--success',
  warning: '--warning',
  error: '--error',
  hero: '--hero',
  dock_light: '--dock-light',
  dock_fallback: '--dock-fallback',
  dock_surface: '--dock-surface',
  title_chip_active: '--title-chip-active',
  title_chip_surface: '--title-chip-surface',
  title_scrim: '--title-scrim',
  canvas_surface: '--canvas-surface',
  workspace_rail: '--ws-rail',
  workspace_sidebar: '--ws-sidebar',
  workspace_tabs: '--ws-tabs',
  workspace_page: '--ws-page',
  workspace_inspector: '--ws-inspector',
  workspace_selection: '--ws-selection',
  workspace_line: '--ws-line'
};

export function applyPalette(palette: LexiThemePalette, dark: boolean): void {
  const root = document.documentElement;
  for (const key of Object.keys(CSS_VARIABLES) as (keyof LexiThemePalette)[]) {
    root.style.setProperty(CSS_VARIABLES[key], palette[key]);
  }
  root.style.setProperty('--shadow-color', dark ? 'rgba(0,0,0,0.52)' : 'rgba(24,20,40,0.14)');
  root.style.setProperty('--hover', `color-mix(in srgb, ${palette.workspace_selection} ${dark ? 55 : 60}%, transparent)`);
  root.style.setProperty('--pressed', `color-mix(in srgb, ${palette.workspace_selection} ${dark ? 82 : 88}%, transparent)`);
  root.style.setProperty('--hover-surface', `color-mix(in srgb, ${palette.text_primary} ${dark ? 6 : 4}%, ${palette.surface})`);
  root.style.setProperty('--pressed-surface', `color-mix(in srgb, ${palette.text_primary} ${dark ? 11 : 8}%, ${palette.surface})`);
  root.style.setProperty('--focus-ring', `color-mix(in srgb, ${palette.brand} 42%, transparent)`);
  root.style.setProperty('--scrim', dark ? 'rgba(10, 10, 16, 0.56)' : 'rgba(20, 16, 36, 0.28)');
  root.style.setProperty('--line-strong', `color-mix(in srgb, ${palette.workspace_line} 82%, ${palette.text_primary})`);
  root.style.setProperty('--callout-bg', `color-mix(in srgb, ${palette.brand} ${dark ? 14 : 9}%, ${palette.surface})`);
  root.style.setProperty('--callout-border', `color-mix(in srgb, ${palette.brand} ${dark ? 32 : 22}%, ${palette.workspace_line})`);
  root.style.setProperty('--elev-1', dark ? '0 1px 3px rgba(0, 0, 0, 0.24)' : '0 1px 3px rgba(24, 20, 40, 0.06)');
  root.style.setProperty('--elev-2', dark ? '0 8px 20px rgba(0, 0, 0, 0.36)' : '0 4px 14px rgba(24, 20, 40, 0.12)');
  root.style.setProperty('--elev-3', dark ? '0 18px 46px rgba(0, 0, 0, 0.52)' : '0 14px 36px rgba(24, 20, 40, 0.18)');
  root.dataset.theme = dark ? 'dark' : 'light';
  document.body.classList.toggle('dark', dark);
}

export function resolveDark(mode: 'light' | 'dark' | 'system'): boolean {
  if (mode === 'dark') return true;
  if (mode === 'light') return false;
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}
