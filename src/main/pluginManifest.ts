import {
  OBSIDIAN_BASELINE_CAPABILITIES,
  PluginCapability,
  PluginKind,
  type PluginKindValue,
  PluginLimits,
  type PluginManifest,
  isKnownCapability
} from '../shared/pluginTypes';

export const PLUGIN_ID_PATTERN = /^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$/;
export const PLUGIN_VERSION_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
const ACCEPTED_DESKTOP_TARGETS = new Set(['windows', 'win32', 'desktop', 'harmonyos']);

export function detectPluginKind(rawManifest: string): PluginKindValue {
  try {
    const parsed = JSON.parse(rawManifest) as Record<string, unknown>;
    return parsed && parsed.format === 'lexinote-plugin' ? PluginKind.LEXINOTE : PluginKind.OBSIDIAN;
  } catch {
    return PluginKind.OBSIDIAN;
  }
}

export function parsePluginManifest(raw: string, kind: PluginKindValue): PluginManifest {
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('manifest.json 必须是 JSON 对象');
  }
  const str = (key: string, fallback = ''): string =>
    typeof parsed[key] === 'string' ? (parsed[key] as string) : fallback;

  const capabilities = Array.isArray(parsed.capabilities)
    ? parsed.capabilities.filter((item): item is string => typeof item === 'string')
    : [];
  const targets = Array.isArray(parsed.targets)
    ? parsed.targets.filter((item): item is string => typeof item === 'string')
    : [];

  const manifest: PluginManifest = {
    format: str('format'),
    formatVersion: typeof parsed.formatVersion === 'number' ? parsed.formatVersion : 0,
    id: str('id'),
    name: str('name'),
    version: str('version'),
    apiVersion: str('apiVersion'),
    main: str('main', 'main.js') || 'main.js',
    description: str('description'),
    author: str('author'),
    capabilities,
    targets,
    minHostVersion: str('minHostVersion'),
    minAppVersion: str('minAppVersion'),
    isDesktopOnly: parsed.isDesktopOnly === true
  };

  if (kind === PluginKind.OBSIDIAN) {
    manifest.format = 'obsidian-plugin';
    manifest.apiVersion = '1.0';
    manifest.capabilities = [...OBSIDIAN_BASELINE_CAPABILITIES];
  }
  return manifest;
}

export function pluginMainProblem(main: string): string {
  if (!main) { return '清单缺少入口文件'; }
  if (!main.endsWith('.js')) { return '入口文件必须是 .js'; }
  if (main.startsWith('/') || main.includes('\\') || main.includes(':')) {
    return '入口文件必须是插件目录内的相对路径';
  }
  for (const part of main.split('/')) {
    if (part === '.' || part === '..' || part.length === 0) {
      return '入口文件路径非法';
    }
  }
  if (main.length > PluginLimits.MAX_PATH_LENGTH) {
    return '入口文件路径过长';
  }
  return '';
}

export function validatePluginManifest(manifest: PluginManifest, kind: PluginKindValue): string[] {
  const problems: string[] = [];
  if (!PLUGIN_ID_PATTERN.test(manifest.id)) {
    problems.push('插件 id 必须是小写字母、数字、点、短横线或下划线，且不能以符号开头或结尾');
  }
  if (manifest.name.trim().length === 0) {
    problems.push('插件缺少名称');
  }
  if (!PLUGIN_VERSION_PATTERN.test(manifest.version)) {
    problems.push('插件版本号必须形如 1.0.0');
  }
  if (kind === PluginKind.LEXINOTE) {
    if (manifest.format !== 'lexinote-plugin') {
      problems.push('清单 format 必须是 lexinote-plugin');
    }
    if (manifest.formatVersion !== 1) {
      problems.push(`不支持的清单版本 ${manifest.formatVersion}`);
    }
    if (!/^1(?:\.\d+){0,2}$/.test(manifest.apiVersion)) {
      problems.push(`不支持的 API 版本 ${manifest.apiVersion}`);
    }
    for (const cap of manifest.capabilities) {
      if (!isKnownCapability(cap)) {
        problems.push(`未知能力 ${cap}`);
      }
    }
    if (manifest.capabilities.includes(PluginCapability.NETWORK)) {
      problems.push('实验版不开放网络能力');
    }
    if (
      manifest.targets.length > 0 &&
      !manifest.targets.some((target) => ACCEPTED_DESKTOP_TARGETS.has(target.toLowerCase()))
    ) {
      problems.push('插件未声明支持桌面端（windows / desktop / harmonyos）');
    }
  }
  const mainProblem = pluginMainProblem(manifest.main);
  if (mainProblem) {
    problems.push(mainProblem);
  }
  return problems;
}

export function desktopOnlyNotice(manifest: PluginManifest): string {
  if (!manifest.isDesktopOnly) { return ''; }
  return '该插件声明仅支持桌面端（isDesktopOnly）：已可安装，但依赖 Node/Electron 原生模块的功能将报不支持';
}
