'use strict';

/**
 * CommonJS loader for plugin bundles.
 *
 * IMPORTANT: this is a *trusted-code* loader, NOT a sandbox. Plugin code runs in the
 * same JavaScript realm as the runtime, with the same globals. The only hard boundary is
 * that `require` may resolve exactly two ids ('obsidian' and '@lexinote/sdk'); any other
 * module name — including 'fs', 'path', 'electron', 'process', 'child_process' and
 * 'http' — is rejected with `E_UNSUPPORTED_MODULE`. Real isolation comes from running
 * the runtime inside a dedicated ArkWeb WebView with network access blocked; the loader
 * cannot and does not claim to provide security on its own.
 */

const {
  ERROR_CODES,
  createError,
  isPlainObject,
  isCodedError,
  rawErrorMessage
} = require('./util');

const ALLOWED_MODULES = Object.freeze({
  obsidian: true,
  '@lexinote/sdk': true
});

/** Host capability names. Kept in sync with PluginModels.ets / plugin-contracts. */
const CAPABILITIES = Object.freeze([
  'vault.read',
  'vault.write',
  'notes.metadata.read',
  'editor.read',
  'editor.write',
  'workspace.views',
  'ui.notice',
  'ui.modal',
  'ui.commands',
  'ai.inference',
  'ui.views',
  'plugin.storage',
  'network'
]);

const ID_PATTERN = /^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

const LEXINOTE_REQUIRED = Object.freeze([
  'format',
  'formatVersion',
  'id',
  'name',
  'version',
  'apiVersion',
  'main'
]);

const LEXINOTE_ALLOWED = Object.freeze([
  'format',
  'formatVersion',
  'id',
  'name',
  'version',
  'apiVersion',
  'main',
  'description',
  'author',
  'capabilities',
  'targets',
  'minHostVersion',
  'isDesktopOnly'
]);

const OBSIDIAN_REQUIRED = Object.freeze([
  'id',
  'name',
  'version',
  'minAppVersion',
  'description',
  'author',
  'isDesktopOnly'
]);

const OBSIDIAN_ALLOWED = Object.freeze([
  'id',
  'name',
  'version',
  'minAppVersion',
  'description',
  'author',
  'isDesktopOnly',
  'fundingUrl'
]);

function moduleValue(modules, id) {
  if (!modules || typeof modules !== 'object') {
    return { found: false, value: undefined };
  }
  if (Object.prototype.hasOwnProperty.call(modules, id)) {
    return { found: true, value: modules[id] };
  }
  // The runtime registers the SDK under its short bundle id.
  if (id === '@lexinote/sdk' && Object.prototype.hasOwnProperty.call(modules, 'sdk')) {
    return { found: true, value: modules.sdk };
  }
  return { found: false, value: undefined };
}

function createRequire(modules) {
  return function pluginRequire(name) {
    const id = typeof name === 'string' ? name : String(name);
    if (!Object.prototype.hasOwnProperty.call(ALLOWED_MODULES, id)) {
      throw createError(ERROR_CODES.UNSUPPORTED_MODULE, id);
    }
    const resolved = moduleValue(modules, id);
    if (!resolved.found) {
      throw createError(ERROR_CODES.UNSUPPORTED_MODULE, `${id}（运行时未提供该模块）`);
    }
    return resolved.value;
  };
}

/**
 * Executes one CommonJS plugin bundle.
 *
 * @param {string} source bundle text
 * @param {object} modules map of whitelisted module id -> exports
 * @param {string} [filename] `__filename` passed to the bundle
 * @returns {*} the bundle's `module.exports`
 */
function executeBundle(source, modules, filename) {
  if (typeof source !== 'string') {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, '插件源码必须是字符串');
  }
  const name = typeof filename === 'string' && filename.length > 0 ? filename : 'main.js';
  const safeName = name.replace(/[\r\n\u2028\u2029]/g, ' ');
  const module = { exports: {} };
  const requireFn = createRequire(modules);

  let factory;
  try {
    // eslint-disable-next-line no-new-func
    factory = new Function(
      'module',
      'exports',
      'require',
      '__filename',
      '__dirname',
      `${source}\n//# sourceURL=lexinote-plugin://${safeName}`
    );
  } catch (error) {
    throw wrapBundleError(error);
  }

  try {
    factory(module, module.exports, requireFn, name, '/');
  } catch (error) {
    throw wrapBundleError(error);
  }
  return module.exports;
}

/**
 * Wraps unexpected bundle failures in `E_PLUGIN_FAILED: ...`.
 *
 * Explicit `E_*` failures raised by the runtime itself (notably E_UNSUPPORTED_MODULE,
 * E_QUOTA_EXCEEDED and E_UNSUPPORTED_API) are propagated unchanged: callers need the
 * precise code to explain a refusal, and wrapping them would hide it.
 */
function wrapBundleError(error) {
  if (isCodedError(error)) {
    return error;
  }
  return createError(ERROR_CODES.PLUGIN_FAILED, rawErrorMessage(error));
}

function hasOnlyAllowedKeys(object, allowed) {
  const keys = Object.keys(object);
  const unknown = [];
  for (let index = 0; index < keys.length; index += 1) {
    if (allowed.indexOf(keys[index]) < 0) {
      unknown.push(keys[index]);
    }
  }
  return unknown;
}

function checkString(errors, object, field, required) {
  const value = object[field];
  if (value === undefined || value === null) {
    if (required) {
      errors.push(`缺少字段 ${field}`);
    }
    return;
  }
  if (typeof value !== 'string' || value.length === 0) {
    errors.push(`字段 ${field} 必须是非空字符串`);
  }
}

function manifestResult(errors, warnings, manifest, kind) {
  return {
    ok: errors.length === 0,
    valid: errors.length === 0,
    errors,
    problems: errors,
    warnings,
    manifest,
    kind
  };
}

/**
 * Validates a `lexinote-plugin` or Obsidian manifest. Invalid manifests are reported,
 * never silently normalised into something that boots.
 *
 * @param {object|string} manifest manifest object or its JSON text
 * @param {'lexinote'|'obsidian'} [kind]
 * @returns {{ok:boolean, errors:string[], warnings:string[], manifest:object|null, kind:string}}
 */
function validateManifest(manifest, kind) {
  const errors = [];
  const warnings = [];
  const expectedKind = kind === 'obsidian' ? 'obsidian' : 'lexinote';
  let value = manifest;

  if (typeof manifest === 'string') {
    if (manifest.length === 0) {
      return manifestResult(['manifest 为空'], warnings, null, expectedKind);
    }
    try {
      value = JSON.parse(manifest);
    } catch (error) {
      return manifestResult(['manifest 不是合法 JSON'], warnings, null, expectedKind);
    }
  }

  if (!isPlainObject(value)) {
    return manifestResult(['manifest 必须是对象'], warnings, null, expectedKind);
  }

  const required = expectedKind === 'obsidian' ? OBSIDIAN_REQUIRED : LEXINOTE_REQUIRED;
  const allowed = expectedKind === 'obsidian' ? OBSIDIAN_ALLOWED : LEXINOTE_ALLOWED;

  const unknown = hasOnlyAllowedKeys(value, allowed);
  for (let index = 0; index < unknown.length; index += 1) {
    errors.push(`不允许的字段 ${unknown[index]}`);
  }

  for (let index = 0; index < required.length; index += 1) {
    // formatVersion is a number and isDesktopOnly a boolean in the manifest schemas.
    if (required[index] === 'formatVersion' || required[index] === 'isDesktopOnly') {
      continue;
    }
    checkString(errors, value, required[index], true);
  }
  checkString(errors, value, 'description', false);
  checkString(errors, value, 'author', false);

  if (typeof value.id === 'string' && value.id.length > 0 && !ID_PATTERN.test(value.id)) {
    errors.push(`插件 id 非法：${value.id}`);
  }
  if (typeof value.version === 'string' && value.version.length > 0 && !VERSION_PATTERN.test(value.version)) {
    errors.push(`插件版本号非法：${value.version}`);
  }

  if (expectedKind === 'lexinote') {
    if (value.format !== undefined && value.format !== 'lexinote-plugin') {
      errors.push(`format 必须是 lexinote-plugin，实际为 ${String(value.format)}`);
    }
    if (value.formatVersion === undefined) {
      errors.push('缺少字段 formatVersion');
    } else if (value.formatVersion !== 1) {
      errors.push(`不支持的 formatVersion ${String(value.formatVersion)}`);
    }
    if (typeof value.apiVersion === 'string' && value.apiVersion.length > 0 && !/^1(?:\.\d+){0,2}$/.test(value.apiVersion)) {
      errors.push(`不支持的 apiVersion ${value.apiVersion}（本运行时为 1.x）`);
    }
    if (typeof value.main === 'string' && value.main.length > 0 && value.main.indexOf('..') >= 0) {
      errors.push('main 不能包含上级目录引用');
    }
    if (value.isDesktopOnly !== undefined && typeof value.isDesktopOnly !== 'boolean') {
      errors.push('isDesktopOnly 必须是布尔值');
    }

    if (value.capabilities !== undefined) {
      if (!Array.isArray(value.capabilities)) {
        errors.push('capabilities 必须是字符串数组');
      } else {
        const seen = {};
        for (let index = 0; index < value.capabilities.length; index += 1) {
          const capability = value.capabilities[index];
          if (typeof capability !== 'string') {
            errors.push('capabilities 必须是字符串数组');
            continue;
          }
          if (CAPABILITIES.indexOf(capability) < 0) {
            errors.push(`未知能力 ${capability}`);
            continue;
          }
          if (seen[capability]) {
            warnings.push(`能力 ${capability} 重复声明`);
          }
          seen[capability] = true;
        }
      }
    }

    if (value.targets !== undefined) {
      if (!Array.isArray(value.targets)) {
        errors.push('targets 必须是字符串数组');
      } else {
        for (let index = 0; index < value.targets.length; index += 1) {
          if (typeof value.targets[index] !== 'string' || value.targets[index].length === 0) {
            errors.push('targets 必须是字符串数组');
            break;
          }
        }
      }
    }
  } else {
    if (typeof value.minAppVersion === 'string' && value.minAppVersion.length > 0 && !VERSION_PATTERN.test(value.minAppVersion)) {
      errors.push(`minAppVersion 非法：${value.minAppVersion}`);
    }
    if (value.isDesktopOnly === undefined) {
      errors.push('缺少字段 isDesktopOnly');
    } else if (typeof value.isDesktopOnly !== 'boolean') {
      errors.push('isDesktopOnly 必须是布尔值');
    }
  }

  return manifestResult(errors, warnings, value, expectedKind);
}

/** Same validation, but throws the canonical `E_INVALID_ARGUMENT` shape on failure. */
function assertValidManifest(manifest, kind) {
  const result = validateManifest(manifest, kind);
  if (!result.ok) {
    throw createError(ERROR_CODES.INVALID_ARGUMENT, result.errors.join('；'));
  }
  return result.manifest;
}

function isValidManifest(manifest, kind) {
  return validateManifest(manifest, kind).ok;
}

function manifestProblems(manifest, kind) {
  return validateManifest(manifest, kind).errors;
}

module.exports = {
  executeBundle,
  validateManifest,
  isValidManifest,
  manifestProblems,
  assertValidManifest,
  CAPABILITIES,
  ID_PATTERN,
  VERSION_PATTERN,
  ALLOWED_MODULES
};
