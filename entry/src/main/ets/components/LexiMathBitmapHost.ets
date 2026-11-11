import { webview } from '@kit.ArkWeb';
import { LexiMathBitmapCache } from '../core/LexiMathBitmapCache';

class LexiMathBitmapBridge {
  complete(key: string, raw: string): void { LexiMathBitmapCache.complete(key, raw); }
}

/** A single shared off-screen ArkWeb instance renders and caches every formula. */
@Component
export struct LexiMathBitmapHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: LexiMathBitmapBridge = new LexiMathBitmapBridge();
  aboutToDisappear(): void { LexiMathBitmapCache.unregister(this.controller); }
  build() {
    Web({ src: $rawfile('lexi-math/svg/index.html'), controller: this.controller, renderMode: RenderMode.ASYNC_RENDER })
      .width(1).height(1).opacity(0.01).hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true).fileAccess(false).blockNetwork(true).onlineImageAccess(true).domStorageAccess(false)
      .javaScriptProxy({ object: this.bridge, name: 'lexiBitmapBridge', methodList: ['complete'], controller: this.controller })
      .onPageEnd((): void => { LexiMathBitmapCache.register(this.controller); })
      .onRenderExited((): void => { LexiMathBitmapCache.unregister(this.controller); })
  }
}
