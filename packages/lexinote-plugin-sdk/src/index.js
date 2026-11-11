'use strict';

/**
 * Public LexiNote plugin SDK surface.
 *
 * On a developer machine this file re-exports the implementation from
 * `packages/plugin-runtime-js/src/sdk.js`. Inside the ArkWeb runtime bundle the id `sdk`
 * is provided directly by `runtime.js`, so this wrapper is only used by Node tooling and
 * type-checking. The fallback exists so requiring the package never returns a module
 * that silently pretends to work: `definePlugin` throws `E_RUNTIME_UNAVAILABLE`.
 */

let implementation = null;
let loadError = null;

try {
  implementation = require('../../plugin-runtime-js/src/sdk.js');
} catch (error) {
  loadError = error;
  try {
    // Only resolvable when a host bundle maps this bare id; kept for WebView parity.
    implementation = require('sdk');
  } catch (innerError) {
    implementation = null;
  }
}

function unavailable(what) {
  const error = new Error(`E_RUNTIME_UNAVAILABLE: ${what}`);
  error.code = 'E_RUNTIME_UNAVAILABLE';
  return error;
}

const api = implementation || {
  definePlugin() {
    throw unavailable('SDK 实现未加载（需要 plugin-runtime-js/src/sdk.js）');
  },
  createContext() {
    throw unavailable('SDK 实现未加载（需要 plugin-runtime-js/src/sdk.js）');
  },
  apiVersion: '1.1',
  runtimeVersion: '1',
  DISPOSABLE() {
    throw unavailable('SDK 实现未加载（需要 plugin-runtime-js/src/sdk.js）');
  }
};

module.exports = {
  definePlugin: api.definePlugin,
  apiVersion: api.apiVersion,
  runtimeVersion: api.runtimeVersion,
  DISPOSABLE: api.DISPOSABLE,
  // Developer-tooling only; plugin bundles should not need it.
  createContext: api.createContext,
  loadError
};
