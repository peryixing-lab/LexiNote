import { LexiTheme, LexiThemePalette } from './LexiTheme';

export interface LexiShadowSpec {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

export class LexiTokens {
  // Spacing scale (4pt grid + hairline 2vp step)
  static readonly SPACE_1: number = 2;
  static readonly SPACE_2: number = 4;
  static readonly SPACE_3: number = 8;
  static readonly SPACE_4: number = 12;
  static readonly SPACE_5: number = 16;
  static readonly SPACE_6: number = 20;
  static readonly SPACE_7: number = 24;
  static readonly SPACE_8: number = 32;
  static readonly SPACE_9: number = 40;
  static readonly SPACE_10: number = 48;

  // Radius scale
  static readonly RADIUS_XS: number = 6;
  static readonly RADIUS_SM: number = 8;
  static readonly RADIUS_MD: number = 12;
  static readonly RADIUS_LG: number = 16;
  static readonly RADIUS_FULL: number = 999;

  // Typography scale
  static readonly TYPE_DISPLAY: number = 30;
  static readonly LH_DISPLAY: number = 40;
  static readonly TYPE_H1: number = 24;
  static readonly LH_H1: number = 34;
  static readonly TYPE_H2: number = 20;
  static readonly LH_H2: number = 30;
  static readonly TYPE_H3: number = 17;
  static readonly LH_H3: number = 26;
  static readonly TYPE_BODY: number = 16;
  static readonly LH_BODY: number = 28;
  static readonly TYPE_UI: number = 13;
  static readonly LH_UI: number = 20;
  static readonly TYPE_PHONE_UI: number = 15;
  static readonly LH_PHONE_UI: number = 22;
  static readonly TYPE_PHONE_CAPTION: number = 13;
  static readonly LH_PHONE_CAPTION: number = 18;
  static readonly TYPE_CAPTION: number = 12;
  static readonly LH_CAPTION: number = 16;
  static readonly TYPE_MICRO: number = 11;
  static readonly LH_MICRO: number = 14;

  // Layout geometry metrics
  static readonly LAYOUT_RAIL_WIDTH: number = 52;
  static readonly LAYOUT_PAGE_PAD_X: number = 56;
  static readonly LAYOUT_PHONE_HEADER: number = 56;
  static readonly LAYOUT_SIDEBAR_WIDTH: number = 244;
  static readonly LAYOUT_RIGHT_WIDTH: number = 280;
  static readonly LAYOUT_TAB_HEIGHT: number = 40;
  static readonly LAYOUT_PAGE_MAX_WIDTH: number = 760;
  static readonly LAYOUT_STATUS_HEIGHT: number = 32;
  static readonly LAYOUT_ICON_BTN: number = 32;
  static readonly LAYOUT_ICON_RAIL: number = 36;

  static isDark(palette: LexiThemePalette): boolean {
    return LexiTheme.contrast('#FFFFFF', palette.background) > LexiTheme.contrast('#111111', palette.background);
  }

  static withAlpha(hex: string, alpha: number): string {
    const clean: string = hex.replace('#', '').trim();
    const rgb: string = clean.length === 8 ? clean.slice(2) : (clean.length === 6 ? clean : '000000');
    const clamped: number = Math.max(0, Math.min(1, alpha));
    const byte: number = Math.round(clamped * 255);
    const alphaHex: string = byte.toString(16).toUpperCase().padStart(2, '0');
    return `#${alphaHex}${rgb.toUpperCase()}`;
  }

  static hoverBg(palette: LexiThemePalette): string {
    return LexiTokens.withAlpha(palette.text_primary, LexiTokens.isDark(palette) ? 0.08 : 0.05);
  }

  static pressedBg(palette: LexiThemePalette): string {
    return LexiTokens.withAlpha(palette.text_primary, LexiTokens.isDark(palette) ? 0.14 : 0.09);
  }

  static hoverSurface(palette: LexiThemePalette): string {
    return LexiTheme.mix(palette.surface, palette.text_primary, LexiTokens.isDark(palette) ? 0.08 : 0.04);
  }

  static pressedSurface(palette: LexiThemePalette): string {
    return LexiTheme.mix(palette.surface, palette.text_primary, LexiTokens.isDark(palette) ? 0.14 : 0.08);
  }

  static focusRing(palette: LexiThemePalette): string {
    return LexiTokens.withAlpha(palette.brand, 0.40);
  }

  static scrim(palette: LexiThemePalette): string {
    return LexiTokens.isDark(palette) ? '#8508090F' : '#47120F1B';
  }

  static lineStrong(palette: LexiThemePalette): string {
    return LexiTheme.mix(palette.workspace_line, palette.text_secondary, 0.35);
  }

  static calloutBg(palette: LexiThemePalette): string {
    const amount: number = LexiTokens.isDark(palette) ? 0.30 : 0.52;
    return LexiTheme.mix(palette.workspace_page, palette.brand_soft, amount);
  }

  static calloutBorder(palette: LexiThemePalette): string {
    return LexiTokens.withAlpha(palette.brand, LexiTokens.isDark(palette) ? 0.28 : 0.18);
  }

  static cardSurface(palette: LexiThemePalette): string {
    return LexiTokens.isDark(palette) ? palette.surface : palette.surface;
  }

  static elev0(): LexiShadowSpec {
    return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
  }

  static elev1(palette: LexiThemePalette): LexiShadowSpec {
    const dark: boolean = LexiTokens.isDark(palette);
    return {
      radius: dark ? 6 : 4,
      color: dark ? '#2E000000' : '#0F181428',
      offsetX: 0,
      offsetY: dark ? 2 : 1
    };
  }

  static elev2(palette: LexiThemePalette): LexiShadowSpec {
    const dark: boolean = LexiTokens.isDark(palette);
    return {
      radius: dark ? 16 : 12,
      color: dark ? '#52000000' : '#1F181428',
      offsetX: 0,
      offsetY: dark ? 6 : 4
    };
  }

  static elev3(palette: LexiThemePalette): LexiShadowSpec {
    const dark: boolean = LexiTokens.isDark(palette);
    return {
      radius: dark ? 32 : 28,
      color: dark ? '#7A000000' : '#2E181428',
      offsetX: 0,
      offsetY: dark ? 14 : 12
    };
  }
}
