/** Serializes Web startup and waits for scrolling to settle before mounting. */
export class LexiMathViewport {
  private static queue: LexiMathViewport[] = [];
  private static loading: LexiMathViewport | undefined = undefined;
  private static loadingTimer: number = -1;
  private mounted: boolean = false;
  private visible: boolean = false;
  private timer: number = -1;
  private onMount: () => void;
  private onUnmount: () => void;

  constructor(onMount: () => void, onUnmount: () => void) {
    this.onMount = onMount;
    this.onUnmount = onUnmount;
  }

  private static drain(): void {
    if (LexiMathViewport.loading) { return; }
    while (LexiMathViewport.queue.length > 0) {
      const next = LexiMathViewport.queue.shift();
      if (!next || !next.visible || next.mounted) { continue; }
      LexiMathViewport.loading = next;
      next.mounted = true;
      // A failed Web load must not prevent later formulas from being rendered.
      LexiMathViewport.loadingTimer = setTimeout((): void => { next.ready(); }, 5000);
      next.onMount();
      return;
    }
  }

  ready(): void {
    if (LexiMathViewport.loading !== this) { return; }
    if (LexiMathViewport.loadingTimer >= 0) { clearTimeout(LexiMathViewport.loadingTimer); }
    LexiMathViewport.loadingTimer = -1;
    LexiMathViewport.loading = undefined;
    LexiMathViewport.drain();
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    LexiMathViewport.queue = LexiMathViewport.queue.filter((item: LexiMathViewport): boolean => item !== this);
    if (visible && !this.mounted) {
      this.timer = setTimeout((): void => {
        this.timer = -1;
        if (!this.visible || this.mounted) { return; }
        LexiMathViewport.queue.push(this);
        LexiMathViewport.drain();
      }, 180);
    } else if (!visible && this.mounted) {
      this.timer = setTimeout((): void => {
        this.timer = -1;
        this.mounted = false;
        this.onUnmount();
        this.ready();
      }, 3000);
    }
  }

  dispose(): void {
    this.visible = false;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    LexiMathViewport.queue = LexiMathViewport.queue.filter((item: LexiMathViewport): boolean => item !== this);
    this.mounted = false;
    this.ready();
  }
}
