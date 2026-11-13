# Third-party notices

LexiNote's own source is licensed under GPL-3.0; third-party components retain their respective licenses. This file describes the checked-in runtime bundles and test fixtures, rather than claiming that every development dependency is shipped in the app.

## Runtime editor and Markdown bundles

The exact npm package versions below come from `tools/reading-bundle/package-lock.json`. Their license files were extracted from the corresponding npm archives after verifying the recorded SHA-512 integrity. Full copyright and permission texts are included in [`entry/src/main/resources/rawfile/third_party_licenses.txt`](entry/src/main/resources/rawfile/third_party_licenses.txt), which is packaged with the application. The reading build script currently removes inline legal comments; retain this separate resource when rebuilding or redistributing the bundle.

### Markdown reader

Embedded in `tools/reading-bundle/bundles/reading.js` and `lexinote_reading.js`:

- `entities@4.5.0` — BSD-2-Clause. [Exact source archive](https://registry.npmjs.org/entities/-/entities-4.5.0.tgz).
- `linkify-it@5.0.2` — MIT. [Exact source archive](https://registry.npmjs.org/linkify-it/-/linkify-it-5.0.2.tgz).
- `markdown-it@14.1.0` — MIT. [Exact source archive](https://registry.npmjs.org/markdown-it/-/markdown-it-14.1.0.tgz).
- `markdown-it-footnote@4.0.0` — MIT. [Exact source archive](https://registry.npmjs.org/markdown-it-footnote/-/markdown-it-footnote-4.0.0.tgz).
- `markdown-it-task-lists@2.1.1` — ISC. [Exact source archive](https://registry.npmjs.org/markdown-it-task-lists/-/markdown-it-task-lists-2.1.1.tgz).
- `mdurl@2.1.0` — MIT. [Exact source archive](https://registry.npmjs.org/mdurl/-/mdurl-2.1.0.tgz).
- `punycode.js@2.3.1` — MIT. [Exact source archive](https://registry.npmjs.org/punycode.js/-/punycode.js-2.3.1.tgz).
- `uc.micro@2.1.0` — MIT. [Exact source archive](https://registry.npmjs.org/uc.micro/-/uc.micro-2.1.0.tgz).

`argparse@2.0.1` is recorded by the reader lockfile under **Python-2.0**, not MIT. It serves markdown-it's Node command-line interface and is not imported by the browser reader entry point; it is not included in the runtime license resource. Its [exact npm archive](https://registry.npmjs.org/argparse/-/argparse-2.0.1.tgz) contains the complete Python license and attribution. Build and test tools, including esbuild, TypeScript and jsdom, retain the licenses in their installed packages and are not application runtime bundles.

## Existing offline mathematics assets

- **KaTeX 0.19.1** — MIT. JavaScript, CSS and WOFF2 fonts are under `entry/src/main/resources/rawfile/lexi-math/katex/`. The retained [LICENSE](entry/src/main/resources/rawfile/lexi-math/katex/LICENSE) includes the Khan Academy and contributors copyright. The adjacent README records the exact npm source archive and integrity. [Upstream](https://github.com/KaTeX/KaTeX).
- **MathJax 3.2.2** — Apache-2.0. Retained assets are under `entry/src/main/resources/rawfile/lexi-math/svg/`; retain their [LICENSE](entry/src/main/resources/rawfile/lexi-math/svg/LICENSE) and source/integrity README. These are distinct from KaTeX and do not become MIT because another renderer is used. [Upstream](https://github.com/mathjax/MathJax-src/tree/3.2.2).

## Updating bundles

When a runtime lockfile or checked-in third-party bundle changes, regenerate the relevant license resource from the exact version's upstream license, retain every copyright and license condition, and review the fixture header notices separately. New dependencies can introduce licenses other than MIT. This inventory is based on the source and metadata listed above.


## Offline English dictionary

The bundled `lexinote_spell_en.txt` is the Berkeley/FreeBSD web2 word list from `/usr/share/dict/web2`. Its upstream provenance and copyright-status notice is included as `lexinote_spell_en_NOTICE.txt`. The word list is based on Webster’s Second International and may include archaic spellings.
