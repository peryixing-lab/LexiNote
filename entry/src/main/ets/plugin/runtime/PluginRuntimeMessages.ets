/**
 * Names of the functions the host calls inside the sandbox page, plus the tiny amount of
 * escaping needed to pass JSON text as a JavaScript string literal.
 *
 * Everything crossing the boundary is a JSON string; no ArkTS object is ever handed to the
 * page, and no page value is ever trusted as an object.
 */
export class PluginRuntimeScript {
  static bootCall(json: string): string {
    return `window.__lexiRuntime && window.__lexiRuntime.boot(${JSON.stringify(json)});`;
  }

  static responseCall(json: string): string {
    return `window.__lexiRuntime && window.__lexiRuntime.receiveResponse(${JSON.stringify(json)});`;
  }

  static eventCall(json: string): string {
    return `window.__lexiRuntime && window.__lexiRuntime.receiveEvent(${JSON.stringify(json)});`;
  }

  static commandCall(qualifiedId: string): string {
    return `window.__lexiRuntime && window.__lexiRuntime.runCommand(${JSON.stringify(qualifiedId)});`;
  }

  static unloadCall(): string {
    return 'window.__lexiRuntime && window.__lexiRuntime.unload();';
  }

  static probeCall(): string {
    return 'typeof window.__lexiRuntime === "object"';
  }
}

export class PluginRuntimeState {
  static readonly ABSENT: string = 'absent';
  static readonly LOADING: string = 'loading';
  static readonly READY: string = 'ready';
  static readonly FAILED: string = 'failed';
}
