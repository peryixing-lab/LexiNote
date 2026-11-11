import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { webview } from '@kit.ArkWeb';

export class LexiMathBitmapResult {
  width: number = 0;
  height: number = 0;
  data: string = '';
}

class LexiMathBitmapJob {
  key: string = '';
  source: string = '';
  display: boolean = false;
  dark: boolean = false;
  directory: string = '';
  callbacks: Array<(result: LexiMathBitmapResult | undefined) => void> = [];
}

/** Content-addressed, versioned images survive process restarts and never modify notes. */
export class LexiMathBitmapCache {
  private static controller: webview.WebviewController | undefined = undefined;
  private static jobs: LexiMathBitmapJob[] = [];
  private static active: LexiMathBitmapJob | undefined = undefined;
  private static memory: Map<string, LexiMathBitmapResult> = new Map<string, LexiMathBitmapResult>();
  private static timeout: number = -1;

  static register(controller: webview.WebviewController): void { LexiMathBitmapCache.controller = controller; LexiMathBitmapCache.drain(); }
  static unregister(controller: webview.WebviewController): void {
    if (LexiMathBitmapCache.controller !== controller) { return; }
    LexiMathBitmapCache.controller = undefined;
    if (LexiMathBitmapCache.active) {
      LexiMathBitmapCache.jobs.unshift(LexiMathBitmapCache.active); LexiMathBitmapCache.active = undefined;
      if (LexiMathBitmapCache.timeout >= 0) { clearTimeout(LexiMathBitmapCache.timeout); LexiMathBitmapCache.timeout = -1; }
    }
  }

  static async request(context: common.UIAbilityContext, source: string, display: boolean, dark: boolean,
    callback: (result: LexiMathBitmapResult | undefined) => void): Promise<void> {
    try {
      const input = `mathjax-3.2.2-v2\n${display}\n${dark}\n${source}`;
      const digest = cryptoFramework.createMd('SHA256');
      digest.updateSync({ data: new util.TextEncoder().encodeInto(input) });
      const bytes = digest.digestSync().data;
      let key = '';
      for (const byte of bytes) { key += byte.toString(16).padStart(2, '0'); }
      const hit = LexiMathBitmapCache.memory.get(key);
      if (hit) { callback(hit); return; }
      const directory = `${context.filesDir}/math-bitmap-cache-v2`;
      try {
        const cached = JSON.parse(await fs.readText(`${directory}/${key}.json`)) as LexiMathBitmapResult;
        if (LexiMathBitmapCache.valid(cached)) { LexiMathBitmapCache.remember(key, cached); callback(cached); return; }
      } catch (_) {}
      const existing = LexiMathBitmapCache.active?.key === key ? LexiMathBitmapCache.active :
        LexiMathBitmapCache.jobs.find((job: LexiMathBitmapJob): boolean => job.key === key);
      if (existing) { existing.callbacks.push(callback); return; }
      const job = new LexiMathBitmapJob();
      job.key = key; job.source = source; job.display = display; job.dark = dark; job.directory = directory;
      job.callbacks.push(callback); LexiMathBitmapCache.jobs.push(job);
      AppStorage.setOrCreate<boolean>('lexiMathBitmapNeeded', true);
      LexiMathBitmapCache.drain();
    } catch (_) { callback(undefined); }
  }

  private static valid(result: LexiMathBitmapResult): boolean {
    return !!result && result.width > 0 && result.width <= 4096 && result.height > 0 && result.height <= 2048 &&
      typeof result.data === 'string' && result.data.length > 0 && result.data.length <= 16000000;
  }
  private static remember(key: string, result: LexiMathBitmapResult): void {
    if (LexiMathBitmapCache.memory.size >= 128) {
      const oldest = LexiMathBitmapCache.memory.keys().next().value as string;
      LexiMathBitmapCache.memory.delete(oldest);
    }
    LexiMathBitmapCache.memory.set(key, result);
  }
  private static drain(): void {
    if (!LexiMathBitmapCache.controller || LexiMathBitmapCache.active || !LexiMathBitmapCache.jobs.length) { return; }
    const job = LexiMathBitmapCache.jobs.shift(); if (!job) { return; }
    LexiMathBitmapCache.active = job;
    const args = [JSON.stringify(job.key), JSON.stringify(job.source), String(job.display), String(job.dark)].join(',')
      .replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    LexiMathBitmapCache.timeout = setTimeout((): void => { LexiMathBitmapCache.complete(job.key, ''); }, 12000);
    LexiMathBitmapCache.controller.runJavaScript(`window.lexiBitmap(${args});`).catch((): void => {
      LexiMathBitmapCache.complete(job.key, '');
    });
  }
  static complete(key: string, raw: string): void {
    const job = LexiMathBitmapCache.active; if (!job || job.key !== key) { return; }
    if (LexiMathBitmapCache.timeout >= 0) { clearTimeout(LexiMathBitmapCache.timeout); LexiMathBitmapCache.timeout = -1; }
    LexiMathBitmapCache.active = undefined;
    let result: LexiMathBitmapResult | undefined = undefined;
    try { const parsed = JSON.parse(raw) as LexiMathBitmapResult; if (LexiMathBitmapCache.valid(parsed)) { result = parsed; } } catch (_) {}
    if (result) {
      LexiMathBitmapCache.remember(key, result);
      LexiMathBitmapCache.write(job.directory, key, raw);
    }
    for (const callback of job.callbacks) { callback(result); }
    LexiMathBitmapCache.drain();
  }
  private static async write(directory: string, key: string, raw: string): Promise<void> {
    try {
      await fs.mkdir(directory, true);
      const file = await fs.open(`${directory}/${key}.json`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { await fs.write(file.fd, raw); } finally { await fs.close(file); }
    } catch (_) { /* Cache failures leave the source editable and allow later retries. */ }
  }
}
