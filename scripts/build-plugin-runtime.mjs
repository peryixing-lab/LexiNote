#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT = resolve(__dirname, '..');
const SRC_DIR = join(ROOT, 'src', 'plugin-runtime', 'modules');
const OUT_FILE = join(ROOT, 'src', 'renderer', 'public', 'plugin-runtime', 'index.html');

const MODULES = [
  'util',
  'mirror',
  'bridge',
  'loader',
  'sdk',
  'ui',
  'obsidian',
  'runtime'
];

function buildRuntimeBundle() {
  const chunks = [];
  chunks.push('(function () {');
  chunks.push("  'use strict';");
  chunks.push('  var __modules = Object.create(null);');
  chunks.push('  var __cache = Object.create(null);');
  chunks.push('  function __define(id, factory) {');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__modules, id)) {');
  chunks.push("      throw new Error('E_PROTOCOL: duplicate runtime module ' + id);");
  chunks.push('    }');
  chunks.push('    __modules[id] = factory;');
  chunks.push('  }');
  chunks.push('  function __resolve(specifier) {');
  chunks.push("    if (typeof specifier !== 'string' || specifier.length === 0) {");
  chunks.push("      throw new Error('E_UNSUPPORTED_MODULE: ' + String(specifier));");
  chunks.push('    }');
  chunks.push("    if (specifier.charAt(0) === '.') {");
  chunks.push("      return specifier.replace(/^\\.\\//, '').replace(/\\.js$/, '');");
  chunks.push('    }');
  chunks.push("    throw new Error('E_UNSUPPORTED_MODULE: ' + specifier);");
  chunks.push('  }');
  chunks.push('  function __require(id) {');
  chunks.push('    if (!Object.prototype.hasOwnProperty.call(__modules, id)) {');
  chunks.push("      throw new Error('E_UNSUPPORTED_MODULE: ' + id);");
  chunks.push('    }');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__cache, id)) {');
  chunks.push('      return __cache[id].exports;');
  chunks.push('    }');
  chunks.push('    var module = { exports: {} };');
  chunks.push('    __cache[id] = module;');
  chunks.push('    __modules[id](module, module.exports, function (specifier) {');
  chunks.push('      return __require(__resolve(specifier));');
  chunks.push("    }, id + '.js', '/');");
  chunks.push('    return module.exports;');
  chunks.push('  }');

  for (const id of MODULES) {
    const file = join(SRC_DIR, `${id}.js`);
    if (!existsSync(file)) {
      throw new Error(`Missing runtime module: ${file}`);
    }
    const source = readFileSync(file, 'utf8')
      .replace(/<\/script/gi, '<\\/script');
    chunks.push('');
    chunks.push(`  // ---- module: ${id} ----`);
    chunks.push(`  __define(${JSON.stringify(id)}, function (module, exports, require, __filename, __dirname) {`);
    chunks.push(source);
    chunks.push('  });');
  }

  chunks.push('');
  chunks.push("  __require('runtime');");
  chunks.push('})();');
  return chunks.join('\n');
}

function buildHostBridgeBootstrap() {
  return `(function () {
  'use strict';
  var hostPort = null;

  function send(message) {
    if (!hostPort) { return; }
    try {
      hostPort.postMessage(message);
    } catch (error) {
      // Host port might be closed during teardown.
    }
  }

  globalThis.lexiPluginBridge = {
    request: function (payloadJson) {
      send({ type: 'rpc-request', payload: String(payloadJson || '') });
      return '{"accepted":true,"code":"","message":""}';
    },
    log: function (level, message) {
      send({ type: 'log', level: String(level || 'info'), message: String(message || '') });
    }
  };

  globalThis.__lexiDesktopUiHook = function (event) {
    send({ type: 'ui-hook', payload: event });
  };

  function applyTheme(vars, colorScheme) {
    var rootStyle = document.documentElement.style;
    if (colorScheme === 'dark' || colorScheme === 'light') {
      rootStyle.colorScheme = colorScheme;
    }
    if (vars && typeof vars === 'object') {
      var keys = Object.keys(vars);
      for (var i = 0; i < keys.length; i += 1) {
        var key = keys[i];
        if (typeof vars[key] === 'string') {
          rootStyle.setProperty(key, vars[key]);
        }
      }
    }
  }

  function handlePortMessage(event) {
    var msg = event && event.data;
    if (!msg || typeof msg !== 'object') { return; }
    var rt = globalThis.__lexiRuntime;
    if (!rt) {
      if (msg.id) {
        send({ type: 'host-reply', id: msg.id, ok: false, error: 'E_RUNTIME_UNAVAILABLE: __lexiRuntime missing' });
      }
      return;
    }
    if (msg.type === 'theme') {
      applyTheme(msg.vars, msg.colorScheme);
      return;
    }
    if (msg.type === 'response') {
      rt.receiveResponse(msg.payload);
      return;
    }
    if (msg.type === 'event') {
      rt.receiveEvent(msg.payload);
      return;
    }
    if (msg.type === 'boot') {
      Promise.resolve(rt.boot(msg.payload)).then(
        function (result) {
          send({ type: 'host-reply', id: msg.id, ok: true, result: result });
        },
        function (error) {
          send({
            type: 'host-reply',
            id: msg.id,
            ok: false,
            error: (error && error.message) || String(error || 'boot failed')
          });
        }
      );
      return;
    }
    if (msg.type === 'runCommand') {
      Promise.resolve(rt.runCommand(msg.qualifiedId)).then(
        function (result) {
          if (msg.id) { send({ type: 'host-reply', id: msg.id, ok: true, result: result }); }
        },
        function (error) {
          if (msg.id) {
            send({ type: 'host-reply', id: msg.id, ok: false, error: (error && error.message) || String(error) });
          }
        }
      );
      return;
    }
    if (msg.type === 'present') {
      Promise.resolve(rt.present(msg.viewId || '')).then(
        function (result) {
          if (msg.id) { send({ type: 'host-reply', id: msg.id, ok: true, result: result }); }
        },
        function (error) {
          if (msg.id) {
            send({ type: 'host-reply', id: msg.id, ok: false, error: (error && error.message) || String(error) });
          }
        }
      );
      return;
    }
    if (msg.type === 'triggerRibbon') {
      Promise.resolve(rt.triggerRibbon(msg.ribbonId || '')).then(
        function (result) {
          if (msg.id) { send({ type: 'host-reply', id: msg.id, ok: true, result: result }); }
        },
        function (error) {
          if (msg.id) {
            send({ type: 'host-reply', id: msg.id, ok: false, error: (error && error.message) || String(error) });
          }
        }
      );
      return;
    }
    if (msg.type === 'unload') {
      Promise.resolve(rt.unload()).then(
        function (result) {
          if (msg.id) { send({ type: 'host-reply', id: msg.id, ok: true, result: result }); }
        },
        function (error) {
          if (msg.id) {
            send({ type: 'host-reply', id: msg.id, ok: false, error: (error && error.message) || String(error) });
          }
        }
      );
      return;
    }
  }

  function onInitMessage(event) {
    if (event && event.source && window.parent && event.source !== window.parent) { return; }
    var data = event && event.data;
    if (!data || typeof data !== 'object') { return; }
    if (data.type === 'lexi-ping-port') {
      if (window.parent) {
        try {
          window.parent.postMessage({ type: 'lexi-runtime-ready' }, '*');
        } catch (error) {
          // Ignore postMessage failure during teardown.
        }
      }
      return;
    }
    if (data.type !== 'lexi-init-port') { return; }
    if (!event.ports || !event.ports[0]) { return; }
    if (hostPort && typeof hostPort.close === 'function') {
      try {
        hostPort.close();
      } catch (error) {
        // Ignore close error on superseded port.
      }
    }
    hostPort = event.ports[0];
    hostPort.onmessage = handlePortMessage;
    if (typeof hostPort.start === 'function') {
      hostPort.start();
    }
    send({ type: 'port-ready' });
  }

  window.addEventListener('message', onInitMessage);
  if (window.parent) {
    try {
      window.parent.postMessage({ type: 'lexi-runtime-ready' }, '*');
    } catch (error) {
      // Ignore postMessage failure before parent attaches listener.
    }
  }
})();`;
}

function buildHtml(scriptText) {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>LexiNote Plugin Runtime</title>
  <style>
    :root {
      color-scheme: light dark;
      --font-text-size: 13px;
      --font-interface: "Segoe UI", "Microsoft YaHei UI", sans-serif;
      --text-normal: #242129;
      --text-muted: #6f687a;
      --text-faint: #9b93a8;
      --text-accent: #6c4ef6;
      --text-error: #cf3d59;
      --background-primary: #f7f5f9;
      --background-secondary: #efecf4;
      --background-modifier-border: #e1dce8;
      --interactive-accent: #6c4ef6;
      --interactive-normal: #ebe7f2;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --text-normal: #e3dfec;
        --text-muted: #a9a1b8;
        --text-faint: #787086;
        --text-accent: #8f77ff;
        --text-error: #f16f88;
        --background-primary: #211f26;
        --background-secondary: #2a2730;
        --background-modifier-border: #3d3847;
        --interactive-accent: #7f65f8;
        --interactive-normal: #322e3a;
      }
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      color: var(--text-normal);
      background: var(--background-primary);
      font: 13px/1.5 var(--font-interface);
      overflow: hidden;
    }
    #plugin-surface {
      height: 100%;
      overflow: auto;
      padding: 12px;
    }
    .lexinote-plugin-view {
      display: flex;
      flex-direction: column;
      min-height: 100%;
    }
    .workspace-leaf-content { min-height: 100%; }
    .view-header:empty { display: none; }
    .view-content { min-height: 100%; }
    h1, h2, h3, h4 {
      margin: 0 0 8px 0;
      font-weight: 600;
      color: var(--text-normal);
    }
    p {
      margin: 0 0 8px 0;
      color: var(--text-muted);
    }
    button, input, select, textarea {
      font: inherit;
      color: inherit;
    }
    button {
      cursor: pointer;
      padding: 5px 10px;
      border: 1px solid var(--background-modifier-border);
      border-radius: 6px;
      background: var(--interactive-normal);
      color: var(--text-normal);
      margin-right: 6px;
      margin-bottom: 6px;
    }
    button:hover {
      border-color: var(--interactive-accent);
    }
    button.mod-cta {
      background: var(--interactive-accent);
      border-color: var(--interactive-accent);
      color: #ffffff;
    }
    button.mod-warning {
      color: var(--text-error);
    }
    input[type="text"], input[type="password"], input:not([type]), select, textarea {
      width: 100%;
      padding: 5px 8px;
      border: 1px solid var(--background-modifier-border);
      border-radius: 6px;
      background: var(--background-secondary);
      color: var(--text-normal);
    }
    .setting-item {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 10px 0;
      border-bottom: 1px solid var(--background-modifier-border);
    }
    .setting-item-heading {
      border-bottom: none;
      padding-bottom: 4px;
      font-weight: 600;
    }
    .setting-item-info { flex: 1; min-width: 0; }
    .setting-item-name { font-weight: 500; color: var(--text-normal); }
    .setting-item-description { font-size: 12px; color: var(--text-muted); margin-top: 2px; }
    .setting-item-control { max-width: 50%; flex-shrink: 0; }
    .modal {
      position: fixed;
      inset: 16px 12px;
      padding: 16px;
      background: var(--background-primary);
      border: 1px solid var(--background-modifier-border);
      border-radius: 8px;
      overflow: auto;
      z-index: 100;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.28);
    }
    .modal-close-button {
      position: absolute;
      right: 8px;
      top: 8px;
      width: 26px;
      height: 26px;
      padding: 0;
      margin: 0;
      line-height: 24px;
      text-align: center;
    }
  </style>
</head>
<body>
  <div id="plugin-surface"></div>
  <script>
${scriptText}
  </script>
</body>
</html>
`;
}

export function buildPluginRuntimeHtml() {
  const bundle = buildRuntimeBundle();
  const bridge = buildHostBridgeBootstrap();
  const fullScript = `${bundle}\n${bridge}`;
  const html = buildHtml(fullScript);
  mkdirSync(dirname(OUT_FILE), { recursive: true });
  writeFileSync(OUT_FILE, html, 'utf8');
  const sha = createHash('sha256').update(html).digest('hex').slice(0, 12);
  return { outFile: OUT_FILE, sha256: sha, bytes: Buffer.byteLength(html, 'utf8') };
}

if (process.argv[1] && resolve(process.argv[1]) === __filename) {
  const result = buildPluginRuntimeHtml();
  console.log(`Built plugin runtime -> ${result.outFile} (${result.bytes} bytes, sha256:${result.sha256})`);
}
