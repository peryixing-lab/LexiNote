import { CustomTheme, ThemeControl, window } from '@kit.ArkUI';

/** A complete, immutable snapshot; replacing it refreshes every native surface. */
export class LexiThemePalette {
  background: string = '';
  surface: string = '';
  soft_surface: string = '';
  text_primary: string = '';
  text_secondary: string = '';
  brand: string = '';
  brand_soft: string = '';
  brand_ink: string = '';
  inverse_text: string = '';
  divider: string = '';
  success: string = '';
  warning: string = '';
  error: string = '';
  hero: string = '';
  dock_light: string = '';
  dock_fallback: string = '';
  dock_surface: string = '';
  title_chip_active: string = '';
  title_chip_surface: string = '';
  title_scrim: string = '';
  canvas_surface: string = '';
  workspace_rail: string = '';
  workspace_sidebar: string = '';
  workspace_tabs: string = '';
  workspace_page: string = '';
  workspace_inspector: string = '';
  workspace_selection: string = '';
  workspace_line: string = '';
}

export class LexiThemePreset {
  color: string;
  label: string;
  constructor(color: string, label: string) { this.color = color; this.label = label; }
}

export class LexiThemeColors {
  mode: string = 'original';
  accent: string = '#6E44D9';
  background: string = '';
  foreground: string = '';
}

export class LexiTheme {
  private static nativeWindow: window.Window | undefined;
  private static signature: string = '';
  static readonly DEFAULT_ACCENT: string = '#6E44D9';
  static readonly PRESETS: LexiThemePreset[] = [
    new LexiThemePreset('#6E44D9', '鸢尾紫'), new LexiThemePreset('#D94B73', '玫瑰粉'),
    new LexiThemePreset('#DC8137', '暖杏橙'), new LexiThemePreset('#308F70', '森林绿'),
    new LexiThemePreset('#3688CD', '晴空蓝'), new LexiThemePreset('#68738A', '石墨灰')
  ];

  static validAccent(color: string): boolean { return /^#[0-9a-fA-F]{6}$/.test(color); }

  static colors(raw: string = '', legacyAccent: string = LexiTheme.DEFAULT_ACCENT): LexiThemeColors {
    const colors = new LexiThemeColors();
    if (raw.length === 0) {
      colors.accent = LexiTheme.validAccent(legacyAccent) ? legacyAccent.toUpperCase() : LexiTheme.DEFAULT_ACCENT;
      colors.mode = colors.accent === LexiTheme.DEFAULT_ACCENT ? 'original' : 'preset';
      return colors;
    }
    try {
      const parsed = JSON.parse(raw) as LexiThemeColors;
      if (!parsed || (parsed.mode !== 'original' && parsed.mode !== 'preset' && parsed.mode !== 'custom')) { return colors; }
      colors.mode = parsed.mode;
      colors.accent = typeof parsed.accent === 'string' && LexiTheme.validAccent(parsed.accent) ? parsed.accent.toUpperCase() : LexiTheme.DEFAULT_ACCENT;
      colors.background = typeof parsed.background === 'string' && LexiTheme.validAccent(parsed.background) ? parsed.background.toUpperCase() : '';
      colors.foreground = typeof parsed.foreground === 'string' && LexiTheme.validAccent(parsed.foreground) ? parsed.foreground.toUpperCase() : '';
    } catch { return colors; }
    return colors;
  }

  static mix(base: string, tint: string, amount: number): string {
    let result = '#';
    for (let channel = 0; channel < 3; channel++) {
      const offset = 1 + channel * 2;
      const first = parseInt(base.substring(offset, offset + 2), 16);
      const second = parseInt(tint.substring(offset, offset + 2), 16);
      result += Math.round(first * (1 - amount) + second * amount).toString(16).padStart(2, '0');
    }
    return result.toUpperCase();
  }

  private static luminance(color: string): number {
    const channels: number[] = [];
    for (let index = 0; index < 3; index++) {
      const channel = parseInt(color.substring(1 + index * 2, 3 + index * 2), 16) / 255;
      channels.push(channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4));
    }
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  }

  static contrast(first: string, second: string): number {
    const a = LexiTheme.luminance(first);
    const b = LexiTheme.luminance(second);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  }

  private static readable(accent: string, background: string, dark: boolean): string {
    const target = dark ? '#FFFFFF' : '#000000';
    for (let step = 0; step <= 100; step++) {
      const adjusted = LexiTheme.mix(accent, target, step / 100);
      if (LexiTheme.contrast(adjusted, background) >= 4.5) { return adjusted; }
    }
    return target;
  }

  static palette(accent: string = LexiTheme.DEFAULT_ACCENT, dark: boolean = false): LexiThemePalette {
    const tint = LexiTheme.validAccent(accent) ? accent : LexiTheme.DEFAULT_ACCENT;
    const palette = new LexiThemePalette();
    palette.background = LexiTheme.mix(dark ? '#111318' : '#F7F8FA', tint, dark ? 0.07 : 0.035);
    palette.surface = LexiTheme.mix(dark ? '#202229' : '#FFFFFF', tint, dark ? 0.08 : 0.012);
    palette.soft_surface = LexiTheme.mix(dark ? '#2B2D35' : '#EEF0F4', tint, dark ? 0.10 : 0.05);
    palette.text_primary = LexiTheme.mix(dark ? '#F5F6FA' : '#1A1D24', tint, dark ? 0.025 : 0.08);
    palette.text_secondary = LexiTheme.mix(dark ? '#C6CAD4' : '#535863', tint, 0.10);
    palette.brand_soft = LexiTheme.mix(dark ? '#292C34' : '#EDF0F5', tint, dark ? 0.23 : 0.08);
    palette.workspace_selection = LexiTheme.mix(dark ? '#30333B' : '#E2E5EC', tint, dark ? 0.30 : 0.12);
    palette.text_primary = LexiTheme.readable(LexiTheme.readable(palette.text_primary, palette.workspace_selection, dark), palette.soft_surface, dark);
    palette.text_secondary = LexiTheme.readable(LexiTheme.readable(palette.text_secondary, palette.workspace_selection, dark), palette.soft_surface, dark);
    // Links also occur on selected rows, so meet text contrast on the strongest tint.
    palette.brand = LexiTheme.readable(LexiTheme.readable(tint, palette.workspace_selection, dark), palette.soft_surface, dark);
    palette.brand_ink = palette.brand;
    palette.inverse_text = LexiTheme.contrast('#FFFFFF', palette.brand) >= 4.5 ? '#FFFFFF' : '#111318';
    palette.divider = LexiTheme.mix(dark ? '#41444D' : '#E5E7EC', tint, 0.12);
    palette.success = dark ? '#86CDB5' : '#348672';
    palette.warning = dark ? '#F0B86E' : '#C9822B';
    palette.error = dark ? '#FF9EAB' : '#C44D62';
    palette.hero = palette.brand_soft;
    palette.dock_light = LexiTheme.mix(tint, '#FFFFFF', dark ? 0.45 : 0.68);
    palette.dock_fallback = (dark ? '#F0' : '#EE') + palette.surface.substring(1);
    palette.dock_surface = (dark ? '#D9' : '#70') + palette.surface.substring(1);
    palette.title_chip_active = (dark ? '#CC' : '#38') + tint.substring(1);
    palette.title_chip_surface = (dark ? '#CC' : '#66') + palette.surface.substring(1);
    palette.title_scrim = (dark ? '#E6' : '#00') + palette.background.substring(1);
    palette.canvas_surface = palette.background;
    palette.workspace_rail = LexiTheme.mix(dark ? '#1A1C23' : '#E8EBF0', tint, dark ? 0.12 : 0.07);
    palette.workspace_sidebar = LexiTheme.mix(dark ? '#21232B' : '#F4F5F7', tint, dark ? 0.10 : 0.05);
    palette.workspace_tabs = LexiTheme.mix(dark ? '#1D1F27' : '#EEF0F4', tint, dark ? 0.10 : 0.06);
    palette.workspace_page = LexiTheme.mix(dark ? '#17191F' : '#FFFFFF', tint, dark ? 0.06 : 0.004);
    palette.workspace_inspector = LexiTheme.mix(dark ? '#1D1F26' : '#FFFFFF', tint, dark ? 0.08 : 0.025);
    palette.workspace_line = palette.divider;
    return palette;
  }

  static originalPalette(dark: boolean = false): LexiThemePalette {
    const palette = new LexiThemePalette();
    if (dark) {
      palette.background = '#12131B';
      palette.surface = '#20212D';
      palette.soft_surface = '#2D2F3E';
      palette.text_primary = '#F5F3FB';
      palette.text_secondary = '#C6C2D4';
      palette.brand = '#C7B3FF';
      palette.brand_soft = '#3A3157';
      palette.brand_ink = '#E0D4FF';
      palette.inverse_text = '#20162E';
      palette.divider = '#4B465F';
      palette.success = '#86CDB5';
      palette.warning = '#F0B86E';
      palette.error = '#FF9EAB';
      palette.hero = '#29233D';
      palette.dock_light = '#B9A1EB';
      palette.dock_fallback = '#F020212D';
      palette.dock_surface = '#D920212D';
      palette.title_chip_active = '#CC4B396E';
      palette.title_chip_surface = '#CC2A2B3A';
      palette.title_scrim = '#E612131B';
      palette.canvas_surface = '#181A24';
      palette.workspace_rail = '#1D1A29';
      palette.workspace_sidebar = '#242030';
      palette.workspace_tabs = '#211E2C';
      palette.workspace_page = '#191822';
      palette.workspace_inspector = '#1E1C29';
      palette.workspace_selection = '#403355';
      palette.workspace_line = '#3B354C';
    } else {
      palette.background = '#F6F4FB';
      palette.surface = '#FFFFFF';
      palette.soft_surface = '#EEEAF8';
      palette.text_primary = '#231B36';
      palette.text_secondary = '#6E6385';
      palette.brand = '#6E44D9';
      palette.brand_soft = '#E9E0FF';
      palette.brand_ink = '#4E2B9E';
      palette.inverse_text = '#FFFFFF';
      palette.divider = '#E4DDF2';
      palette.success = '#348672';
      palette.warning = '#C9822B';
      palette.error = '#C44D62';
      palette.hero = '#E9E0FF';
      palette.dock_light = '#D8C7FF';
      palette.dock_fallback = '#EEFFFFFF';
      palette.dock_surface = '#26FFFFFF';
      palette.title_chip_active = '#386E44D9';
      palette.title_chip_surface = '#33FFFFFF';
      palette.title_scrim = '#00F6F4FB';
      palette.canvas_surface = '#1C162B';
      palette.workspace_rail = '#EAE4F5';
      palette.workspace_sidebar = '#F4F0FA';
      palette.workspace_tabs = '#F0EBF8';
      palette.workspace_page = '#FFFFFF';
      palette.workspace_inspector = '#FCFAFF';
      palette.workspace_selection = '#E4D8FA';
      palette.workspace_line = '#DDD5EA';
    }
    return palette;
  }
  static resolvePalette(colors: LexiThemeColors, dark: boolean = false): LexiThemePalette {
    if (colors.mode === 'original') { return LexiTheme.originalPalette(dark); }
    if (colors.mode !== 'custom') { return LexiTheme.palette(colors.accent, dark); }
    const fallback = LexiTheme.palette(colors.accent, dark);
    const background = colors.background || fallback.background;
    const foreground = colors.foreground || fallback.text_primary;
    const canvasDark = LexiTheme.luminance(background) < 0.179;
    const palette = LexiTheme.palette(colors.accent, canvasDark);
    palette.background = background;
    palette.workspace_page = background;
    palette.surface = LexiTheme.mix(background, '#FFFFFF', canvasDark ? 0.07 : 0.65);
    palette.soft_surface = LexiTheme.mix(background, foreground, 0.055);
    palette.workspace_rail = LexiTheme.mix(background, colors.accent, 0.09);
    palette.workspace_sidebar = LexiTheme.mix(background, colors.accent, 0.045);
    palette.workspace_tabs = LexiTheme.mix(background, colors.accent, 0.065);
    palette.workspace_inspector = LexiTheme.mix(background, colors.accent, 0.025);
    palette.workspace_selection = LexiTheme.mix(background, colors.accent, canvasDark ? 0.25 : 0.14);
    palette.brand_soft = LexiTheme.mix(background, colors.accent, canvasDark ? 0.20 : 0.10);
    palette.hero = palette.brand_soft;
    palette.divider = LexiTheme.mix(background, foreground, 0.16);
    palette.workspace_line = palette.divider;
    const surfaces: string[] = [background, palette.surface, palette.soft_surface, palette.workspace_selection,
      palette.workspace_sidebar, palette.workspace_inspector, palette.brand_soft];
    palette.text_primary = LexiTheme.fitText(foreground, surfaces, canvasDark);
    palette.text_secondary = LexiTheme.fitText(LexiTheme.mix(foreground, background, 0.25), surfaces, canvasDark);
    palette.brand = LexiTheme.fitText(colors.accent, surfaces, canvasDark);
    palette.brand_ink = palette.brand;
    palette.inverse_text = LexiTheme.contrast('#FFFFFF', palette.brand) >= 4.5 ? '#FFFFFF' : '#111318';
    palette.canvas_surface = background;
    palette.dock_fallback = (canvasDark ? '#F0' : '#EE') + palette.surface.substring(1);
    palette.dock_surface = (canvasDark ? '#D9' : '#70') + palette.surface.substring(1);
    palette.title_chip_surface = (canvasDark ? '#CC' : '#66') + palette.surface.substring(1);
    palette.title_scrim = (canvasDark ? '#E6' : '#00') + background.substring(1);
    return palette;
  }

  private static fitText(color: string, surfaces: string[], dark: boolean): string {
    const target = dark ? '#FFFFFF' : '#000000';
    for (let step = 0; step <= 100; step++) {
      const adjusted = LexiTheme.mix(color, target, step / 100);
      if (surfaces.every((surface: string): boolean => LexiTheme.contrast(adjusted, surface) >= 4.5)) { return adjusted; }
    }
    return target;
  }

  static current(): LexiThemePalette {
    return AppStorage.get<LexiThemePalette>('lexiThemePalette') ?? LexiTheme.originalPalette(false);
  }

  static bindWindow(nativeWindow: window.Window | undefined): void {
    LexiTheme.nativeWindow = nativeWindow;
    try { nativeWindow?.setWindowBackgroundColor(LexiTheme.current().background); } catch { /* Window may be closing. */ }
  }

  static nativeTheme(palette: LexiThemePalette): CustomTheme {
    return { colors: {
      brand: palette.brand, fontPrimary: palette.text_primary, fontSecondary: palette.text_secondary,
      fontEmphasize: palette.brand, fontOnPrimary: palette.inverse_text,
      iconPrimary: palette.text_primary, iconSecondary: palette.text_secondary, iconEmphasize: palette.brand,
      backgroundPrimary: palette.background, backgroundSecondary: palette.surface,
      backgroundEmphasize: palette.brand, compBackgroundPrimary: palette.surface,
      compBackgroundGray: palette.background, compBackgroundSecondary: palette.soft_surface,
      compBackgroundEmphasize: palette.brand, compEmphasizeSecondary: palette.brand_soft,
      compDivider: palette.divider, interactiveFocus: palette.brand, interactiveActive: palette.brand,
      interactiveSelect: palette.workspace_selection
    } };
  }

  static refresh(): void {
    const accent = AppStorage.get<string>('lexiAccent') ?? LexiTheme.DEFAULT_ACCENT;
    const dark = AppStorage.get<number>('lexiColorMode') === 1;
    const colors = LexiTheme.colors(AppStorage.get<string>('lexiThemeColors') ?? '', accent);
    const signature = `${JSON.stringify(colors)}:${dark}`;
    if (signature === LexiTheme.signature) { return; }
    LexiTheme.signature = signature;
    const palette = LexiTheme.resolvePalette(colors, dark);
    AppStorage.setOrCreate('lexiThemePalette', palette);
    AppStorage.setOrCreate('lexiEffectiveAccent', palette.brand);
    ThemeControl.setDefaultTheme(LexiTheme.nativeTheme(palette));
    try { LexiTheme.nativeWindow?.setWindowBackgroundColor(palette.background); } catch { /* Window may be closing. */ }
  }
}
