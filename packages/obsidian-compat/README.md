# `@lexinote/obsidian-compat`

Documentation and type declarations for the **supported subset** of the Obsidian plugin
API implemented by `packages/plugin-runtime-js/src/obsidian.js`. This package is not
loaded at runtime; it exists so plugin authors and reviewers can see exactly what the
shim promises.

## Level 1 — real implementation

| Area | Members |
| --- | --- |
| Files | `TAbstractFile`, `TFile`, `TFolder`, `normalizePath` |
| Vault | `getFiles`, `getMarkdownFiles`, `getAbstractFileByPath`, `getRoot`, `read`, `cachedRead`, `create`, `modify`, `append`, `delete`, `rename`, `on`, `off`, `offref` |
| Metadata | `getFileCache`, `getCache`, `getFirstLinkpathDest` (reduced cache: headings / links / tags only) |
| Events | `Events`, `EventRef` (`on()` always returns an `EventRef`) |
| Component | `registerEvent`, `registerInterval`, `registerDomEvent`, `addChild`, `removeChild`, `load`, `unload` |
| Plugin | `onload`, `onunload`, `loadData`, `saveData`, `addCommand`, `app`, `manifest` |
| Workspace | `activeEditor`, `getActiveFile`, `getActiveViewOfType`, `openLinkText`, `on('file-open' \| 'active-leaf-change')` |
| Editor | `getValue`, `getCursor`, `getSelection`, `setSelection`, `replaceSelection`, `replaceRange`, `setValue`, `getLine`, `lineCount`, `posToOffset`, `offsetToPos` |
| UI | `Notice` (forwards to `ui.notice`) |
| Platform | static flags with `isDesktopApp === false` and `isHarmonyOS === true` |

Synchronous listings read the runtime's in-memory `FileMirror`; reads and writes are
asynchronous RPCs. `TFile` / `TFolder` instances are cached per runtime, so
`file instanceof TFile` and `getAbstractFileByPath(f.path) === f` both hold.

## Deliberate differences from Obsidian

- **Delete is a soft delete.** `Vault.delete()` moves the note to the LexiNote recycle
  bin; it does not unlink a file. The `force` argument is accepted and ignored.
- **No filesystem adapter.** `Vault.adapter` throws `E_UNSUPPORTED_API`; plugins cannot
  read or write absolute paths.
- **Editor replacement is RPC-backed.** `replaceSelection` uses the host selection;
  `replaceRange`/`setValue` fall back to a whole-document `editor.replaceAll`, which may
  conflict if the note changed elsewhere (`E_EDITOR_CONFLICT`).
- **Desktop sidebar UI.** Each installed plugin has an icon next to the outline icon.
  Selecting it loads the plugin and presents its registered `ItemView`. `getRightLeaf`,
  `setViewState`, `getLeavesOfType`, `revealLeaf`, ribbon callbacks, basic settings controls
  and local modals use the dedicated runtime DOM. The single runtime unloads the previous
  plugin when switching plugins. Collapsing the sidebar or switching to outline keeps
  the current runtime alive. Headless runtimes still reject DOM APIs.
- **No renderer/editor extensions.** `registerMarkdownPostProcessor` and
  `registerEditorExtension` still throw `E_UNSUPPORTED_API`.
- **No networking.** `requestUrl` throws `E_UNSUPPORTED_API`.
- **`registerDomEvent`** only works when a real DOM element with
  `addEventListener`/`removeEventListener` is supplied; the sidebar supplies real DOM elements.
- **Metadata cache is reduced.** Only headings, links and tags are exposed; block and
  section caches are absent rather than fabricated.
- `addCommand` returns a `Disposable` (not Obsidian's `Command`) and supports
  `callback`, `editorCallback` and `checkCallback`.
- `Component.load()`/`unload()` are asynchronous; the runtime calls `onload()` and
  `onunload()` directly for plugin instances, matching Obsidian's lifecycle order.

## Level 2 — not implemented

Settings tabs, ribbon icons, custom views, Markdown post-processors, CodeMirror editor
extensions, modals, status bar items, `requestUrl`, `Vault.adapter`, `app.plugins`, leaf
management and multi-view workspace operations. Accessing these surfaces throws an
explicit `E_UNSUPPORTED_API` error rather than silently doing nothing.
