const test = require('node:test');
const assert = require('node:assert/strict');
const { loadTheme } = require('./lib/theme-harness.cjs');

test('presets and extreme custom colors keep text and controls readable in both modes', () => {
  const { LexiTheme } = loadTheme();
  const colors = [...LexiTheme.PRESETS.map(preset => preset.color), '#FFFFFF', '#000000', '#FFFF00', '#00FF00', '#0000FF', '#FF00FF'];
  // Include a deterministic RGB sample to exercise colors between the curated presets.
  for (let rgb = 0; rgb <= 0xFFFFFF; rgb += 0x19333) colors.push('#' + rgb.toString(16).padStart(6, '0'));
  for (const dark of [false, true]) {
    for (const color of colors) {
      const palette = LexiTheme.palette(color, dark);
      for (const background of [palette.background, palette.surface, palette.soft_surface, palette.workspace_selection, palette.workspace_page]) {
        assert.ok(LexiTheme.contrast(palette.text_primary, background) >= 4.5, `${color}: primary text in ${dark ? 'dark' : 'light'} mode`);
        assert.ok(LexiTheme.contrast(palette.text_secondary, background) >= 4.5, `${color}: secondary text`);
        assert.ok(LexiTheme.contrast(palette.brand, background) >= 4.5, `${color}: accent text on ${background}`);
      }
      assert.ok(LexiTheme.contrast(palette.inverse_text, palette.brand) >= 4.5, `${color}: button label`);
      assert.notEqual(palette.workspace_sidebar, palette.workspace_page);
    }
  }
});

test('changing color mode republishes native and custom UI tokens without losing the selected color', () => {
  const { LexiTheme, memory, nativeThemes } = loadTheme();
  memory.set('lexiAccent', '#308F70');
  memory.set('lexiColorMode', 0);
  LexiTheme.refresh();
  const light = memory.get('lexiThemePalette');
  memory.set('lexiColorMode', 1);
  LexiTheme.refresh();
  const dark = memory.get('lexiThemePalette');
  assert.notEqual(light.background, dark.background);
  assert.notEqual(light.brand, dark.brand);
  assert.equal(memory.get('lexiAccent'), '#308F70');
  assert.equal(memory.get('lexiEffectiveAccent'), dark.brand);
  assert.equal(nativeThemes.at(-1).colors.brand, dark.brand);
  assert.equal(nativeThemes.at(-1).colors.compBackgroundGray, dark.background);
  memory.set('lexiColorMode', 0);
  LexiTheme.refresh();
  assert.equal(memory.get('lexiThemePalette').background, light.background);
});

test('invalid saved colors produce the default palette', () => {
  const { LexiTheme } = loadTheme();
  assert.deepEqual(LexiTheme.palette('bad css color'), LexiTheme.palette());
});

test('original mode restores every bundled light and dark color instead of generating a tint', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const { LexiTheme } = loadTheme();
  for (const [folder, dark] of [['base', false], ['dark', true]]) {
    const values = JSON.parse(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources', folder, 'element/color.json'), 'utf8')).color;
    const palette = LexiTheme.resolvePalette(LexiTheme.colors(), dark);
    for (const { name, value } of values) {
      if (name in palette) assert.equal(palette[name], value, `${folder}: ${name}`);
    }
  }
  assert.equal(LexiTheme.colors('', '#308f70').mode, 'preset', 'migrate earlier accent choices');
  assert.equal(LexiTheme.colors('', '#6E44D9').mode, 'original');
  assert.equal(LexiTheme.colors('{invalid').mode, 'original');
});

test('custom accent, background, and foreground are independent and remain readable', () => {
  const { LexiTheme } = loadTheme();
  const colors = LexiTheme.colors(JSON.stringify({ mode: 'custom', accent: '#FF7A59', background: '#FFFFFF', foreground: '#1A1C1F' }));
  const palette = LexiTheme.resolvePalette(colors);
  assert.equal(palette.background, '#FFFFFF');
  assert.equal(palette.workspace_page, '#FFFFFF');
  assert.equal(palette.text_primary, '#1A1C1F');
  for (const background of ['#FFFFFF', '#F6F4FB', '#E8EDF4', '#111318', '#20212D']) {
    for (const accent of ['#FFFFFF', '#000000', '#FF7A59', '#308F70', '#6E44D9']) {
      colors.background = background;
      colors.accent = accent;
      colors.foreground = LexiTheme.contrast(background, '#FFFFFF') >= 4.5 ? '#FFFFFF' : '#111318';
      const resolved = LexiTheme.resolvePalette(colors);
      for (const surface of [resolved.background, resolved.surface, resolved.workspace_selection, resolved.workspace_sidebar]) {
        assert.ok(LexiTheme.contrast(resolved.text_primary, surface) >= 4.5);
        assert.ok(LexiTheme.contrast(resolved.brand, surface) >= 4.5);
      }
    }
  }
});
