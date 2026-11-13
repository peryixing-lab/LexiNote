/**
 * Error encoding shared by ArkTS and JavaScript.
 *
 * ArkTS cross-boundary errors are plain `Error` messages shaped `CODE: message` so the
 * same value survives JSON serialization, the ArkWeb bridge and the regression scripts.
 * `E_` prefixes are reserved: PluginErrors.codeOf() only accepts them.
 */
export class PluginErrorCode {
  static readonly INVALID_ARGUMENT: string = 'E_INVALID_ARGUMENT';
  static readonly INVALID_PATH: string = 'E_INVALID_PATH';
  static readonly PATH_EXISTS: string = 'E_PATH_EXISTS';
  static readonly NOT_FOUND: string = 'E_NOT_FOUND';
  static readonly VAULT_FORBIDDEN: string = 'E_VAULT_FORBIDDEN';
  static readonly PERMISSION_DENIED: string = 'E_PERMISSION_DENIED';
  static readonly CONFLICT: string = 'E_CONFLICT';
  static readonly EDITOR_CONFLICT: string = 'E_EDITOR_CONFLICT';
  static readonly EDITOR_READONLY: string = 'E_EDITOR_READONLY';
  static readonly UNSUPPORTED_API: string = 'E_UNSUPPORTED_API';
  /** Model service not configured, unreachable, or returned a non-2xx reply. */
  static readonly MODEL_UNAVAILABLE: string = 'E_MODEL_UNAVAILABLE';
  /** No credential is stored for the requested provider profile. */
  static readonly MISSING_CREDENTIAL: string = 'E_MISSING_CREDENTIAL';
  /** A stored credential cannot travel in an HTTP header (blank or non-printable-ASCII). */
  static readonly INVALID_CREDENTIAL: string = 'E_INVALID_CREDENTIAL';
  static readonly UNSUPPORTED_MODULE: string = 'E_UNSUPPORTED_MODULE';
  static readonly PLUGIN_DISABLED: string = 'E_PLUGIN_DISABLED';
  static readonly PLUGIN_FAILED: string = 'E_PLUGIN_FAILED';
  static readonly QUOTA_EXCEEDED: string = 'E_QUOTA_EXCEEDED';
  static readonly TIMEOUT: string = 'E_TIMEOUT';
  static readonly CANCELLED: string = 'E_CANCELLED';
  static readonly RUNTIME_UNAVAILABLE: string = 'E_RUNTIME_UNAVAILABLE';
  static readonly RATE_LIMITED: string = 'E_RATE_LIMITED';
  static readonly INSTALL_REJECTED: string = 'E_INSTALL_REJECTED';
  static readonly DESKTOP_ONLY: string = 'E_DESKTOP_ONLY';
  static readonly DUPLICATE_PLUGIN: string = 'E_DUPLICATE_PLUGIN';
  static readonly PROTOCOL: string = 'E_PROTOCOL';
  static readonly IO: string = 'E_IO';
  static readonly UNKNOWN: string = 'E_UNKNOWN';
}

export class PluginErrors {
  /** Builds the single canonical error shape. Callers always `throw` the result. */
  static raise(code: string, message: string): Error {
    return new Error(`${code}: ${message}`);
  }

  /** Extracts `E_*` code from any thrown value; unknown errors map to E_UNKNOWN. */
  static codeOf(error: Object | undefined): string {
    // Must read the raw message: messageOf() intentionally strips the code.
    const text = PluginErrors.rawOf(error);
    const colon = text.indexOf(':');
    if (colon <= 0) { return PluginErrorCode.UNKNOWN; }
    const head = text.substring(0, colon).trim();
    return /^E_[A-Z_]+$/.test(head) ? head : PluginErrorCode.UNKNOWN;
  }

  /** Human readable message without the leading code. */
  static messageOf(error: Object | undefined): string {
    const text = PluginErrors.rawOf(error);
    const colon = text.indexOf(':');
    if (colon > 0 && /^E_[A-Z_]+$/.test(text.substring(0, colon).trim())) {
      return text.substring(colon + 1).trim();
    }
    if (text === 'DOCUMENT_CHANGED_ELSEWHERE') { return '正文已在其他位置被修改'; }
    if (text === '笔记不存在') { return '笔记不存在或已删除'; }
    return text;
  }

  /** Original thrown text, before any code stripping. */
  static rawOf(error: Object | undefined): string {
    if (!error) { return '未知错误'; }
    const anyError = error as Error;
    if (anyError && typeof anyError.message === 'string' && anyError.message.length > 0) { return anyError.message; }
    return String(error);
  }

  /** Maps storage-layer errors onto plugin codes without hiding the original text. */
  static normalize(error: Object | undefined): string {
    const code = PluginErrors.codeOf(error);
    if (code !== PluginErrorCode.UNKNOWN) { return `${code}: ${PluginErrors.messageOf(error)}`; }
    const raw = PluginErrors.rawOf(error);
    if (raw === 'DOCUMENT_CHANGED_ELSEWHERE') {
      return `${PluginErrorCode.CONFLICT}: 正文已被其他操作修改，请重新读取后再写入`;
    }
    if (raw === '笔记不存在') { return `${PluginErrorCode.NOT_FOUND}: 笔记不存在或已移入回收站`; }
    if (/授权|permission|denied/i.test(raw)) { return `${PluginErrorCode.PERMISSION_DENIED}: ${raw}`; }
    return `${PluginErrorCode.IO}: ${raw}`;
  }
}
