import { accessibility } from '@kit.AccessibilityKit';
import { curves } from '@kit.ArkUI';

export class LexiMotion {
  static readonly DUR_MICRO: number = 100;
  static readonly DUR_FAST: number = 160;
  static readonly DUR_BASE: number = 220;
  static readonly DUR_SLOW: number = 300;
  static readonly DUR_PALETTE: number = 120;
  static readonly EXIT_FACTOR: number = 0.7;

  static readonly PRESS_SCALE: number = 0.97;
  static readonly POPOVER_SCALE: number = 0.96;
  static readonly MODAL_SCALE: number = 0.96;
  static readonly DRAWER_TRANSLATE: number = 24;
  static readonly STAGGER_STEP_MS: number = 30;
  static readonly STAGGER_MAX_ITEMS: number = 8;

  static reduced(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch {
      return false;
    }
  }

  static duration(ms: number, overrideReduced?: boolean): number {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (!isReduced) {
      return ms;
    }
    return ms <= 0 ? 0 : Math.min(ms, 120);
  }

  static exitDuration(ms: number, overrideReduced?: boolean): number {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced) {
      return 0;
    }
    return Math.round(ms * LexiMotion.EXIT_FACTOR);
  }

  static pressScale(pressed: boolean, overrideReduced?: boolean): number {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced || !pressed) {
      return 1;
    }
    return LexiMotion.PRESS_SCALE;
  }

  static easeOut(): curves.ICurve {
    return curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  }

  static easeInOut(): curves.ICurve {
    return curves.cubicBezierCurve(0.65, 0, 0.35, 1);
  }

  static easeDrawer(): curves.ICurve {
    return curves.cubicBezierCurve(0.32, 0.72, 0, 1);
  }

  static spring(): curves.ICurve {
    return curves.springMotion(0.35, 0.86);
  }

  static param(durationMs: number, curve: curves.ICurve, overrideReduced?: boolean): AnimateParam {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced) {
      return { duration: Math.min(durationMs, 120), curve: Curve.Linear };
    }
    return { duration: durationMs, curve };
  }

  static springParam(overrideReduced?: boolean): AnimateParam {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced) {
      return { duration: 120, curve: Curve.Linear };
    }
    return { duration: LexiMotion.DUR_BASE, curve: LexiMotion.spring() };
  }

  static popoverTransition(overrideReduced?: boolean): TransitionEffect {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: LexiMotion.POPOVER_SCALE, y: LexiMotion.POPOVER_SCALE }))
      .animation({ duration: LexiMotion.DUR_FAST, curve: LexiMotion.easeOut() });
  }

  static modalTransition(overrideReduced?: boolean): TransitionEffect {
    const isReduced: boolean = overrideReduced !== undefined ? overrideReduced : LexiMotion.reduced();
    if (isReduced) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: LexiMotion.MODAL_SCALE, y: LexiMotion.MODAL_SCALE }))
      .animation({ duration: LexiMotion.DUR_BASE, curve: LexiMotion.easeOut() });
  }

  static animate(context: UIContext | undefined, param: AnimateParam, action: () => void): void {
    if (context) {
      context.animateTo(param, action);
      return;
    }
    action();
  }
}
