# Third-party notices

知萤 LexiNote · Windows 版 (LexiNote for Windows) is a desktop port of the
HarmonyOS application **LexiNote** by the peryixing-lab project and is distributed
under the GNU General Public License v3.0 (see `LICENSE`).

## Upstream project

- **LexiNote (知萤)** — https://github.com/peryixing-lab/LexiNote — GPL-3.0.
  The desktop port reuses the upstream product name, interface copy, brand
  assets (`lexi_logo.svg`, application icon) and the SVG icon set under
  `entry/src/main/resources/base/media/`.
- Product plans and design notes in the upstream repository remain the property
  of their authors.

## Runtime dependencies

| Component | Version | License | Usage |
| --- | --- | --- | --- |
| Electron | 36.x | MIT | Desktop shell, Chromium renderer |
| React / React DOM | 18.3 | MIT | Renderer UI |
| KaTeX | 0.16 | MIT | Offline math typesetting (bundled fonts) |
| highlight.js | 11.11 | BSD-3-Clause | Code block highlighting |

Chromium and its third-party components are covered by the licenses shipped in
`LICENSES.chromium.html` and `LICENSE.electron.txt` inside the packaged
application directory. KaTeX's own notice is reproduced in
`third-party-katex-LICENSE.txt`.

## Build-time dependencies

Vite, esbuild, TypeScript, electron-builder, @vitejs/plugin-react and related
packages are used only to build the application and are not redistributed in
the runtime payload (with the exception of Electron's own binaries).

## Fonts

The interface uses the operating system's UI font stack (`Segoe UI`,
`Microsoft YaHei UI`, `HarmonyOS Sans SC` when installed, `PingFang SC`).
No font files are redistributed by this project. KaTeX web fonts are embedded
through the KaTeX package under its MIT license.
