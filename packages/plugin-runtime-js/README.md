# `@lexinote/plugin-runtime-js`

CommonJS JavaScript runtime that runs inside the LexiNote ArkWeb WebView. It is bundled
into `entry/src/main/resources/rawfile/plugin-runtime/runtime.bundle.js` by
`scripts/build-plugin-runtime.cjs`; the source is also directly require-able by Node 18+
for tests.

## Modules

| Module | Responsibility |
| --- | --- |
| `util.js` | small helpers, canonical `E_*` errors, path/JSON/UTF-8 utilities |
| `mirror.js` | in-memory files, active file, editor, workspace, metadata, storage cache |
| `bridge.js` | RPC promises over `window.lexiPluginBridge.request`, timeout, in-flight cap, id correlation, plugin-id/token binding |
| `loader.js` | trusted-code CommonJS bundle loader (two whitelisted modules, no separate source-size cap), manifest validation |
| `sdk.js` | `definePlugin()` and the LexiNote context object |
| `ui.js` | local sidebar DOM helpers, basic settings controls and modals |
| `obsidian.js` | partial Obsidian API shim (real classes, per-runtime identity) |
| `runtime.js` | `window.__lexiRuntime` entry point; `present()` also mounts native `ctx.views` |

## Wire notes that matter for the ArkTS host

- **`params` is JSON text on the wire.** The host's `PluginRpcRequest.params` is a
  `string` and each dispatcher calls `JSON.parse` on it. SDK callers pass plain objects;
  `bridge.js` serialises before calling the proxy. The test harness decodes it again so
  assertions can compare objects.
- **Responses** are `{protocol:1,id,ok,result:"<json>",error:{code,message,details}}`.
  `result` is parsed with `JSON.parse` (an empty string is treated as `null`).
- **Acks are ignored.** `lexiPluginBridge.request()` may return `{accepted,...}`; the
  real result always arrives later through `receiveResponse`.
- **Events accept two shapes.** The documented envelope
  `{protocol:1,type:'event',pluginId,event,seq,payload:"<json>"}` and the shape the
  current ArkTS host emits, `{event,seq,fileId,path,oldPath,vaultId,revision}`. Top-level
  core-event fields are lifted into the handler payload.
- **Obsidian event registrations create host subscriptions.** `vault.on('create')` sends
  `events.on {event:'vault.created'}` (one shared subscription per core event) and
  releases it when the last local handler goes away.

## API 1.1 additions

- `ctx.ai` (`ai.inference`): `status()` / `configure()` / `chat()`. Requests are executed by
  the ArkTS host (`PluginAiService`), so the page keeps `connect-src 'none'`; the API key is
  stored by the host and never returned to JavaScript.
- `ctx.views` (`ui.views`): `register({ id, title, render })` / `open(id?)`. The renderer owns
  a DOM node inside this WebView only; the host never mixes plugin DOM into ArkUI.

## Security model

The loader is **not** a sandbox. Plugin code runs in the same realm as the runtime.
`require` only resolves `obsidian` and `@lexinote/sdk`; every other id, including
`fs`, `path`, `electron`, `process`, `child_process` and `http`, fails with
`E_UNSUPPORTED_MODULE`. Isolation depends on the dedicated ArkWeb WebView
(`fileAccess(false)`, `blockNetwork(true)`, no geolocation, no DOM storage) and on the
host validating every request.

## Tests

```sh
NODE=/Applications/DevEco-Studio.app/Contents/tools/node/bin/node
$NODE scripts/build-plugin-runtime.cjs --check
$NODE scripts/tests/plugin-runtime-regression.cjs
$NODE scripts/tests/plugin-obsidian-regression.cjs
$NODE scripts/tests/plugin-security-regression.cjs
```

`__lexiRuntime.present()` opens the active plugin’s registered view (or its own commands/settings for a command-only plugin). Boot accepts optional `stylesCss`; styles and view resources are removed on unload. Source and default class exports are instantiated with the app and manifest.
