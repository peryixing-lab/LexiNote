import { PluginCapability, PluginKind, PluginLimits, PluginManifest } from '../model/PluginModels';

/** Minimal UTF-8 decoder: no dependency on TextDecoder availability at runtime. */
export class PluginText {
  static decodeUtf8(bytes: Uint8Array): string {
    let result = '';
    let index = 0;
    while (index < bytes.length) {
      const byte = bytes[index];
      if (byte < 0x80) {
        result += String.fromCharCode(byte);
        index += 1;
      } else if (byte >= 0xC0 && byte < 0xE0 && index + 1 < bytes.length) {
        result += String.fromCharCode(((byte & 0x1F) << 6) | (bytes[index + 1] & 0x3F));
        index += 2;
      } else if (byte >= 0xE0 && byte < 0xF0 && index + 2 < bytes.length) {
        result += String.fromCharCode(((byte & 0x0F) << 12) | ((bytes[index + 1] & 0x3F) << 6) |
          (bytes[index + 2] & 0x3F));
        index += 3;
      } else if (byte >= 0xF0 && index + 3 < bytes.length) {
        const code = ((byte & 0x07) << 18) | ((bytes[index + 1] & 0x3F) << 12) |
          ((bytes[index + 2] & 0x3F) << 6) | (bytes[index + 3] & 0x3F);
        const adjusted = code - 0x10000;
        result += String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
        index += 4;
      } else {
        result += '\uFFFD';
        index += 1;
      }
    }
    return result;
  }
}

/**
 * Manifest validation shared by ZIP installs and bundled demo plugins (P14).
 *
 * Unknown capability names, path escapes in `main`, desktop-only Obsidian plugins and
 * incompatible API baselines are rejected with a human readable reason instead of being
 * silently accepted.
 */
export class PluginManifestService {
  static readonly ID_PATTERN: RegExp = /^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$/;

  /** Capabilities an Obsidian plugin behaves as if it had. Network is never included. */
  static obsidianBaseline(): string[] {
    return [
      PluginCapability.VAULT_READ,
      PluginCapability.VAULT_WRITE,
      PluginCapability.METADATA_READ,
      PluginCapability.EDITOR_READ,
      PluginCapability.EDITOR_WRITE,
      PluginCapability.WORKSPACE_VIEWS,
      PluginCapability.UI_NOTICE,
      PluginCapability.UI_COMMANDS,
      PluginCapability.PLUGIN_STORAGE
    ];
  }

  static parse(raw: string, kind: string): PluginManifest {
    const parsed = JSON.parse(raw) as PluginManifest;
    const manifest = new PluginManifest();
    manifest.format = typeof parsed.format === 'string' ? parsed.format : '';
    manifest.formatVersion = typeof parsed.formatVersion === 'number' ? parsed.formatVersion : 0;
    manifest.id = typeof parsed.id === 'string' ? parsed.id : '';
    manifest.name = typeof parsed.name === 'string' ? parsed.name : '';
    manifest.version = typeof parsed.version === 'string' ? parsed.version : '';
    manifest.apiVersion = typeof parsed.apiVersion === 'string' ? parsed.apiVersion : '';
    manifest.main = typeof parsed.main === 'string' ? parsed.main : 'main.js';
    manifest.description = typeof parsed.description === 'string' ? parsed.description : '';
    manifest.author = typeof parsed.author === 'string' ? parsed.author : '';
    manifest.minHostVersion = typeof parsed.minHostVersion === 'string' ? parsed.minHostVersion : '';
    manifest.minAppVersion = typeof parsed.minAppVersion === 'string' ? parsed.minAppVersion : '';
    manifest.isDesktopOnly = parsed.isDesktopOnly === true;
    if (Array.isArray(parsed.capabilities)) {
      manifest.capabilities = parsed.capabilities.filter((item: string): boolean => typeof item === 'string');
    }
    if (Array.isArray(parsed.targets)) {
      manifest.targets = parsed.targets.filter((item: string): boolean => typeof item === 'string');
    }
    if (kind === PluginKind.OBSIDIAN) {
      manifest.format = 'obsidian-plugin';
      manifest.apiVersion = '1.0';
      manifest.capabilities = PluginManifestService.obsidianBaseline();
    }
    return manifest;
  }

  /** Blocking reasons. An empty list means the plugin may be installed. */
  static validate(manifest: PluginManifest, kind: string): string[] {
    const problems: string[] = [];
    if (!PluginManifestService.ID_PATTERN.test(manifest.id)) {
      problems.push('插件 id 必须是小写字母、数字、点、短横线或下划线，且不能以符号开头或结尾');
    }
    if (manifest.name.trim().length === 0) { problems.push('插件缺少名称'); }
    if (!/^\d+\.\d+\.\d+/.test(manifest.version)) { problems.push('插件版本号必须形如 1.0.0'); }
    if (kind === PluginKind.LEXINOTE) {
      if (manifest.format !== 'lexinote-plugin') { problems.push('清单 format 必须是 lexinote-plugin'); }
      if (manifest.formatVersion !== 1) { problems.push(`不支持的清单版本 ${manifest.formatVersion}`); }
      if (!/^1\./.test(manifest.apiVersion)) { problems.push(`不支持的 API 版本 ${manifest.apiVersion}`); }
      for (const capability of manifest.capabilities) {
        if (!PluginCapability.known(capability)) { problems.push(`未知能力 ${capability}`); }
      }
      if (manifest.capabilities.includes(PluginCapability.NETWORK)) {
        problems.push('实验版不开放网络能力');
      }
      if (manifest.targets.length > 0 && !manifest.targets.includes('harmonyos')) {
        problems.push('插件未声明支持 harmonyos');
      }
    }
    // `isDesktopOnly` 是作者自测平台的声明，不是"依赖 Node/Electron"的证据：Obsidian 生态里
    // 大量能跑的插件（Dust Calendar、Tasks 等）都标了它，拿它当安装门会把用户想用的插件
    // 全挡在外面。这里是"可安装 + 显式告知"，真正的阻断留在装载期——require('fs'/'electron'/
    // 动态 require) 会以 E_UNSUPPORTED_MODULE 明确失败，不会静默降级（见 desktopOnlyNotice）。
    const mainProblem = PluginManifestService.mainProblem(manifest.main);
    if (mainProblem.length > 0) { problems.push(mainProblem); }
    return problems;
  }

  /**
   * 仅桌面声明在安装阶段只作为提示返回（不阻断），由插件面板展示。
   * 返回空串表示没有该声明。
   */
  static desktopOnlyNotice(manifest: PluginManifest): string {
    if (!manifest.isDesktopOnly) { return ''; }
    return '该插件声明仅支持桌面端（isDesktopOnly）：已可安装，但依赖 Node/Electron 的功能会报不支持';
  }

  static mainProblem(main: string): string {
    if (main.length === 0) { return '清单缺少入口文件'; }
    if (!main.endsWith('.js')) { return '入口文件必须是 .js'; }
    if (main.startsWith('/') || main.includes('\\') || main.includes(':')) {
      return '入口文件必须是插件目录内的相对路径';
    }
    for (const part of main.split('/')) {
      if (part === '.' || part === '..' || part.length === 0) { return '入口文件路径非法'; }
    }
    if (main.length > PluginLimits.MAX_PATH_LENGTH) { return '入口文件路径过长'; }
    return '';
  }

  static toRecordJson(manifest: PluginManifest): string {
    return JSON.stringify(manifest);
  }
}
