# 知萤 LexiNote — 主题与设置规格（HarmonyOS ArkTS → macOS SwiftUI）

本文是**移植规格提取**，不含应用代码。所有色值、数值、文案均照抄源码；文案保留中文原文（引号内），
并在有对应英文词条时给出英文，供 SwiftUI 本地化使用。

- 源码根：`entry/src/main/ets/`
- 快照时间：2026-11-12（文件 mtime 2026-11-12 21:09）
- 约定：`vp` = ArkUI 虚拟像素；ArkUI 的 8 位色是 `#AARRGGBB`（alpha 在前）。

## 0. 证据索引

| 主题/设置域 | 文件 | 关键行 |
| --- | --- | --- |
| 色板类、28 键 | `core/LexiTheme.ets` | 4–33 |
| 预设强调色、算法 | `core/LexiTheme.ets` | 51–148 |
| 原始亮/暗色板 | `core/LexiTheme.ets` | 150–212 |
| 三种模式解析 | `core/LexiTheme.ets` | 213–256 |
| 主题刷新与原生注入 | `core/LexiTheme.ets` | 258–293 |
| 外观持久化（字号/缩放/CSS） | `core/LexiAppearanceSettings.ets` | 31–133 |
| 编辑器设置 | `core/LexiEditorSettings.ets` | 8–39 |
| 界面设置（缩放/侧栏/功能项） | `core/LexiInterfaceSettings.ets` | 11–114 |
| 快捷键默认值与键名 | `core/LexiHotkeySettings.ets` | 49–160 |
| 快捷键录制 | `core/LexiHotkeyRecorder.ets` | 26–80 |
| 系统保留键 | `core/LexiSystemShortcuts.ets` | 16–31 |
| 设置窗口全部 UI | `components/LexiSettingsWindow.ets` | 120–1184 |
| 明暗三段选择器 | `components/LexiAppearancePicker.ets` | 16–85 |
| 主题/强调色选择器 | `components/LexiThemePicker.ets` | 79–198 |
| 欢迎引导 | `components/LexiWelcomeGuide.ets` | 50–178 |
| 内置模板 | `core/LexiTemplateLibrary.ets` | 33–48 |
| 模板变量替换 | `core/LexiTemplates.ets` | 8–16 |
| 语言机制 | `core/LexiI18n.ets` | 7–45 |
| 英文词条（512 条） | `core/LexiEnglish.ets` | 1–516 |
| 设置面板尺寸 | `pages/Index.ets` | 1717–1726 |

---

## 1. 主题色板

### 1.1 原始亮/暗色：`LexiThemePalette` 全部 28 个键

`originalPalette(dark)` 是硬编码常量表，与强调色无关。顺序即类字段声明顺序。

| # | 键 | 亮色 (`dark=false`) | 暗色 (`dark=true`) | 语义 / 用途 |
| --- | --- | --- | --- | --- |
| 1 | `background` | `#F6F4FB` | `#12131B` | 应用窗口底色、滚动容器底 |
| 2 | `surface` | `#FFFFFF` | `#20212D` | 卡片、浮层、输入框底色 |
| 3 | `soft_surface` | `#EEEAF8` | `#2D2F3E` | 设置卡片底、次级容器 |
| 4 | `text_primary` | `#231B36` | `#F5F3FB` | 主文字 |
| 5 | `text_secondary` | `#6E6385` | `#C6C2D4` | 说明文字、占位符 |
| 6 | `brand` | `#6E44D9` | `#C7B3FF` | 强调色/按钮/链接（原始表中为硬编码常量，非算法产物） |
| 7 | `brand_soft` | `#E9E0FF` | `#3A3157` | 强调色淡底（选中胶囊、次按钮） |
| 8 | `brand_ink` | `#4E2B9E` | `#E0D4FF` | 淡底上的强调色文字 |
| 9 | `inverse_text` | `#FFFFFF` | `#20162E` | 强调色实底上的反白文字 |
| 10 | `divider` | `#E4DDF2` | `#4B465F` | 分隔线 |
| 11 | `success` | `#348672` | `#86CDB5` | 成功态 |
| 12 | `warning` | `#C9822B` | `#F0B86E` | 警告态 |
| 13 | `error` | `#C44D62` | `#FF9EAB` | 错误态 |
| 14 | `hero` | `#E9E0FF` | `#29233D` | 语义为首屏/引导大色块；原始表中独立于 `brand_soft`，生成表中恒等于它。当前代码中无组件引用 |
| 15 | `dock_light` | `#D8C7FF` | `#B9A1EB` | 材质高光色（沉浸光感的 lightEffect） |
| 16 | `dock_fallback` | `#EEFFFFFF` | `#F020212D` | 底部 dock 无材质时的兜底底（α `EE`/`F0`） |
| 17 | `dock_surface` | `#26FFFFFF` | `#D920212D` | dock 材质染色（α `26`≈15% / `D9`≈85%） |
| 18 | `title_chip_active` | `#386E44D9` | `#CC4B396E` | 标题栏激活胶囊材质染色（α `38`≈22% / `CC`=80%） |
| 19 | `title_chip_surface` | `#33FFFFFF` | `#CC2A2B3A` | 标题栏普通胶囊材质染色（α `33`=20% / `CC`） |
| 20 | `title_scrim` | `#00F6F4FB` | `#E612131B` | 标题栏渐变遮罩（亮色全透明起步 / 暗色 90%） |
| 21 | `canvas_surface` | `#1C162B` | `#181A24` | 白板/导图画布背景（亮色下也刻意深色） |
| 22 | `workspace_rail` | `#EAE4F5` | `#1D1A29` | 最左竖条功能区（ribbon） |
| 23 | `workspace_sidebar` | `#F4F0FA` | `#242030` | 左侧知识库栏、设置窗口左栏 |
| 24 | `workspace_tabs` | `#F0EBF8` | `#211E2C` | 标签条 |
| 25 | `workspace_page` | `#FFFFFF` | `#191822` | 编辑/设置内容页底 |
| 26 | `workspace_inspector` | `#FCFAFF` | `#1E1C29` | 右侧检查器 |
| 27 | `workspace_selection` | `#E4D8FA` | `#403355` | 选中行/选中段底 |
| 28 | `workspace_line` | `#DDD5EA` | `#3B354C` | 工作区分隔线 |

> 注意：`canvas_surface` 在亮色下是 `#1C162B`（深紫），不是 `background`；不要跟着亮暗整体反转。
> `hero` 在原始色板中是独立常量，在生成色板中恒等于 `brand_soft`。

### 1.2 六个预设强调色

`LexiTheme.PRESETS`（`core/LexiTheme.ets:52`）。默认强调色 `DEFAULT_ACCENT = #6E44D9`（鸢尾紫）。

| 顺序 | 名称 | 英文 | 色值 |
| --- | --- | --- | --- |
| 1 | 鸢尾紫 | Iris | `#6E44D9` |
| 2 | 玫瑰粉 | Rose | `#D94B73` |
| 3 | 暖杏橙 | Apricot | `#DC8137` |
| 4 | 森林绿 | Forest | `#308F70` |
| 5 | 晴空蓝 | Sky | `#3688CD` |
| 6 | 石墨灰 | Graphite | `#68738A` |

英文名来自 `core/LexiEnglish.ets:11–16`。

### 1.3 颜色算法：mix / luminance / contrast / readable

#### 1.3.1 合法性

合法色 = 正则 `^#[0-9a-fA-F]{6}$`；解析后一律 `.toUpperCase()` 存储。默认 `#6E44D9`。

#### 1.3.2 `mix(base, tint, amount)`

逐通道（R、G、B，各取 `#RRGGBB` 的两位十六进制）：

```
out_c = round(base_c * (1 - amount) + tint_c * amount)
```

- `round` 为四舍五入（JS `Math.round`，.5 向上）。
- `amount ∈ [0, 1]`。
- 输出固定 `#` + 6 位大写十六进制（每通道 `padStart(2,'0')`）。
- 不做 gamma / OKLab 校正，是**线性 sRGB 通道插值**。

#### 1.3.3 `luminance(color)`（WCAG 相对亮度）

```
c_srgb = channel / 255
c_lin  = c_srgb <= 0.04045 ? c_srgb / 12.92 : ((c_srgb + 0.055) / 1.055) ^ 2.4
L      = 0.2126*R_lin + 0.7152*G_lin + 0.0722*B_lin
```

#### 1.3.4 `contrast(a, b)`

```
C = (max(La, Lb) + 0.05) / (min(La, Lb) + 0.05)
```

#### 1.3.5 `readable(accent, background, dark)`

```
target = dark ? #FFFFFF : #000000
for step = 0 … 100:
    adjusted = mix(accent, target, step / 100)
    if contrast(adjusted, background) >= 4.5: return adjusted
return target
```

- 阈值 **4.5:1**（WCAG AA 正文）。
- 步进 **1%**，最多 101 次；必然终止。
- 方向：暗色主题向白靠，亮色主题向黑靠。

#### 1.3.6 `fitText(color, surfaces[], dark)`（仅自定义模式）

与 `readable` 同构，但要求 `adjusted` 对**每一个** `surface` 的对比度都 ≥ 4.5，否则继续加白/加黑，
全部失败则返回纯白/纯黑。

#### 1.3.7 `palette(accent, dark)` 的逐键生成顺序

严格按下列顺序执行（后面的键依赖前面已算出的键）：

| 步骤 | 键 | 底/base（亮 / 暗） | amount（亮 / 暗） |
| --- | --- | --- | --- |
| 1 | `background` | `#F7F8FA` / `#111318` | 0.035 / 0.07 |
| 2 | `surface` | `#FFFFFF` / `#202229` | 0.012 / 0.08 |
| 3 | `soft_surface` | `#EEF0F4` / `#2B2D35` | 0.05 / 0.10 |
| 4 | `text_primary` | `#1A1D24` / `#F5F6FA` | 0.08 / 0.025 |
| 5 | `text_secondary` | `#535863` / `#C6CAD4` | 0.10 / 0.10 |
| 6 | `brand_soft` | `#EDF0F5` / `#292C34` | 0.08 / 0.23 |
| 7 | `workspace_selection` | `#E2E5EC` / `#30333B` | 0.12 / 0.30 |
| 8 | `text_primary`（覆盖） | `readable(readable(步骤 4 的值, workspace_selection, dark), soft_surface, dark)` | — |
| 9 | `text_secondary`（覆盖） | `readable(readable(步骤 5 的值, workspace_selection, dark), soft_surface, dark)` | — |
| 10 | `brand` | `readable(readable(tint, workspace_selection, dark), soft_surface, dark)` | — |
| 11 | `brand_ink` | `= brand` | — |
| 12 | `inverse_text` | `contrast(#FFFFFF, brand) >= 4.5 ? #FFFFFF : #111318` | — |
| 13 | `divider` | `#E5E7EC` / `#41444D` | 0.12 / 0.12 |
| 14 | `success` | `#348672` / `#86CDB5`（常量） | — |
| 15 | `warning` | `#C9822B` / `#F0B86E`（常量） | — |
| 16 | `error` | `#C44D62` / `#FF9EAB`（常量） | — |
| 17 | `hero` | `= brand_soft` | — |
| 18 | `dock_light` | `mix(tint, #FFFFFF, 0.68 / 0.45)` | — |
| 19 | `dock_fallback` | 前缀 `#EE` / `#F0` + `surface` 的 6 位 | — |
| 20 | `dock_surface` | 前缀 `#70` / `#D9` + `surface` 的 6 位 | — |
| 21 | `title_chip_active` | 前缀 `#38` / `#CC` + **原始 tint** 的 6 位 | — |
| 22 | `title_chip_surface` | 前缀 `#66` / `#CC` + `surface` 的 6 位 | — |
| 23 | `title_scrim` | 前缀 `#00` / `#E6` + `background` 的 6 位 | — |
| 24 | `canvas_surface` | `= background` | — |
| 25 | `workspace_rail` | `#E8EBF0` / `#1A1C23` | 0.07 / 0.12 |
| 26 | `workspace_sidebar` | `#F4F5F7` / `#21232B` | 0.05 / 0.10 |
| 27 | `workspace_tabs` | `#EEF0F4` / `#1D1F27` | 0.06 / 0.10 |
| 28 | `workspace_page` | `#FFFFFF` / `#17191F` | 0.004 / 0.06 |
| 29 | `workspace_inspector` | `#FFFFFF` / `#1D1F26` | 0.025 / 0.08 |
| 30 | `workspace_line` | `= divider` | — |

要点：

1. **`text_primary` / `text_secondary` / `brand` 都经过双重 `readable`**：先对 `workspace_selection`（最浓的
   选中底）满足 4.5，再对 `soft_surface` 满足 4.5。
2. **`brand` 是从原始 tint 出发做可读化，不是直接用 tint**。所以 6 个预设的最终强调色都与预设色不同（见 1.4）。
3. `title_chip_active` 用的是**未可读化的原始 tint**，与 `brand` 可能不同色。
4. 所有 8 位色都是「alpha + 6 位色」字符串直接拼接，不经过任何混合。

#### 1.3.8 模式分派 `resolvePalette(colors, dark)`

| `colors.mode` | 结果 |
| --- | --- |
| `original` | `originalPalette(dark)`（1.1 的常量表，忽略 accent） |
| `preset`（缺省/未知也走这里） | `palette(colors.accent, dark)`（1.3.7） |
| `custom` | 见 1.3.9 |

`colors()` 解析规则（`core/LexiTheme.ets:60`）：

- 空字符串 → accent 取 `legacyAccent`（合法则大写，否则 `#6E44D9`）；`mode = accent == #6E44D9 ? 'original' : 'preset'`。
- JSON 解析失败、`mode` 不在 `original|preset|custom` → 返回默认（`mode='original'`, `accent='#6E44D9'`）。
- `background`/`foreground` 非法或缺失 → 置空字符串 `''`（表示"未自定义"）。

#### 1.3.9 `custom` 模式（自定义背景/前景）

```
fallback   = palette(accent, dark)          // 仅用于取缺省值
background = 自定义背景 或 fallback.background
foreground = 自定义前景 或 fallback.text_primary
canvasDark = luminance(background) < 0.179   // 由背景亮度决定明暗，而不是系统主题
base       = palette(accent, canvasDark)     // 用推导出的暗/亮重算一遍
```

随后逐键覆盖：

| 键 | 表达式 |
| --- | --- |
| `background` | 自定义背景（原样，不做可读化） |
| `workspace_page` | `= background` |
| `surface` | `mix(background, #FFFFFF, canvasDark ? 0.07 : 0.65)` |
| `soft_surface` | `mix(background, foreground, 0.055)` |
| `workspace_rail` | `mix(background, accent, 0.09)` |
| `workspace_sidebar` | `mix(background, accent, 0.045)` |
| `workspace_tabs` | `mix(background, accent, 0.065)` |
| `workspace_inspector` | `mix(background, accent, 0.025)` |
| `workspace_selection` | `mix(background, accent, canvasDark ? 0.25 : 0.14)` |
| `brand_soft` | `mix(background, accent, canvasDark ? 0.20 : 0.10)` |
| `hero` | `= brand_soft` |
| `divider` | `mix(background, foreground, 0.16)` |
| `workspace_line` | `= divider` |
| `text_primary` | `fitText(foreground, S, canvasDark)` |
| `text_secondary` | `fitText(mix(foreground, background, 0.25), S, canvasDark)` |
| `brand` | `fitText(accent, S, canvasDark)` |
| `brand_ink` | `= brand` |
| `inverse_text` | `contrast(#FFFFFF, brand) >= 4.5 ? #FFFFFF : #111318` |
| `canvas_surface` | `= background` |
| `dock_fallback` | 前缀 `#F0`/`#EE`（按 canvasDark） + `surface` |
| `dock_surface` | 前缀 `#D9`/`#70` + `surface` |
| `title_chip_surface` | 前缀 `#CC`/`#66` + `surface` |
| `title_scrim` | 前缀 `#E6`/`#00` + `background` |

其中 `S = [background, surface, soft_surface, workspace_selection, workspace_sidebar, workspace_inspector, brand_soft]`（7 个面）。

> **实现差异点（需在 macOS 端决定是否复刻）**：custom 分支**没有重算** `title_chip_active`、`dock_light`、
> `success/warning/error`；它们继承自 `palette(accent, canvasDark)`，即 `title_chip_active` 仍是
> `#38/#CC + accent`，与自定义背景无联动。建议 macOS 端保持一致，或显式修正并记录。

自定义模式的校验（写入时）：

- 非法色 → 抛 `请输入 6 位十六进制颜色，如 #6E44D9`。
- `contrast(background, foreground) < 4.5` → 抛 `前景色与背景色对比度不足，请调整颜色`（该文案会被翻译，见 8.2）。

#### 1.3.10 状态与刷新

- `LexiTheme.refresh()` 读 `AppStorage['lexiAccent']`、`lexiColorMode`（1 = 暗）、`lexiThemeColors`（JSON 字符串）。
- 用 `${JSON.stringify(colors)}:${dark}` 做签名去重，签名不变则**什么都不做**。
- 变更后：写入 `AppStorage['lexiThemePalette']`、`AppStorage['lexiEffectiveAccent'] = palette.brand`，
  调用 `ThemeControl.setDefaultTheme(nativeTheme(palette))`，并 `window.setWindowBackgroundColor(palette.background)`。
- `nativeTheme` 的映射（供 macOS `NSApp.appearance` / 控件 tint 参考）：
  `brand←brand`、`fontPrimary←text_primary`、`fontSecondary←text_secondary`、`fontEmphasize←brand`、
  `fontOnPrimary←inverse_text`、`iconPrimary/Secondary/Emphasize` 同上三色、
  `backgroundPrimary←background`、`backgroundSecondary←surface`、`backgroundEmphasize←brand`、
  `compBackgroundPrimary←surface`、`compBackgroundGray←background`、`compBackgroundSecondary←soft_surface`、
  `compBackgroundEmphasize←brand`、`compEmphasizeSecondary←brand_soft`、`compDivider←divider`、
  `interactiveFocus←brand`、`interactiveActive←brand`、`interactiveSelect←workspace_selection`。

### 1.4 计算示例（可用于视觉回归基线）

以下数值由 1.3 的算法按同一实现复算，`accent = #6E44D9`，左列为亮色、右列为暗色：

| 键 | 生成色板（亮） | 生成色板（暗） |
| --- | --- | --- |
| `background` | `#F2F2F9` | `#181626` |
| `surface` | `#FDFDFF` | `#262537` |
| `soft_surface` | `#E8E7F3` | `#322F45` |
| `text_primary` | `#212032` | `#F2F2F9` |
| `text_secondary` | `#56566F` | `#BDBDD5` |
| `brand` | `#663FCA` | `#B5A0EC` |
| `brand_soft` | `#E3E2F3` | `#39325A` |
| `brand_ink` | `#663FCA` | `#B5A0EC` |
| `inverse_text` | `#FFFFFF` | `#111318` |
| `divider` | `#D7D3EA` | `#46445E` |
| `success` | `#348672` | `#86CDB5` |
| `warning` | `#C9822B` | `#F0B86E` |
| `error` | `#C44D62` | `#FF9EAB` |
| `hero` | `#E3E2F3` | `#39325A` |
| `dock_light` | `#D1C3F3` | `#AF98EA` |
| `dock_fallback` | `#EEFDFDFF` | `#F0262537` |
| `dock_surface` | `#70FDFDFF` | `#D9262537` |
| `title_chip_active` | `#386E44D9` | `#CC6E44D9` |
| `title_chip_surface` | `#66FDFDFF` | `#CC262537` |
| `title_scrim` | `#00F2F2F9` | `#E6181626` |
| `canvas_surface` | `#F2F2F9` | `#181626` |
| `workspace_rail` | `#DFDFEE` | `#242139` |
| `workspace_sidebar` | `#EDECF5` | `#29263C` |
| `workspace_tabs` | `#E6E6F2` | `#252339` |
| `workspace_page` | `#FEFEFF` | `#1C1C2A` |
| `workspace_inspector` | `#FBFAFE` | `#232234` |
| `workspace_selection` | `#D4D2EA` | `#43386A` |
| `workspace_line` | `#D7D3EA` | `#46445E` |

6 个预设经双重 `readable` 后的 `brand` 与推导出的 `background`：

| 预设 | 原始色 | 亮 `brand` | 亮 `background` | 暗 `brand` | 暗 `background` |
| --- | --- | --- | --- | --- | --- |
| 鸢尾紫 | `#6E44D9` | `#663FCA` | `#F2F2F9` | `#B5A0EC` | `#181626` |
| 玫瑰粉 | `#D94B73` | `#A13855` | `#F6F2F5` | `#EBA0B5` | `#1F171E` |
| 暖杏橙 | `#DC8137` | `#8B5123` | `#F6F4F3` | `#EBB78D` | `#1F1B1A` |
| 森林绿 | `#308F70` | `#246A53` | `#F0F4F5` | `#8FC3B2` | `#131C1E` |
| 晴空蓝 | `#3688CD` | `#276294` | `#F0F4F8` | `#92BFE4` | `#141B25` |
| 石墨灰 | `#68738A` | `#555E71` | `#F2F3F6` | `#AFB5C1` | `#171A20` |

`brand` 对 `background` 的对比度落在 5.8–9.5:1，全部 ≥ 4.5（符合设计意图）。

---

## 2. 外观设置：全部选项与默认值

### 2.1 明暗模式：跟随系统 / 浅色 / 深色

- 控件：`LexiAppearancePicker`，三个等宽分段按钮；容器 `padding 4`、`radius 16`、底 `soft_surface`；
  单个按钮 `minHeight 44`、`radius 12`、选中底 `brand_soft`、选中文字色 `= lexiEffectiveAccent` 且 `Medium`，
  未选中文字 `text_secondary`、`Regular`；文字 13。**不是 iOS 风格滑动的 Segmented，而是三个独立按钮。**
- 文案：`跟随系统`（System）/ `浅色`（Light）/ `深色`（Dark）。
- 无障碍：`外观：跟随系统` / `外观：浅色` / `外观：深色`，并带 `accessibilitySelected`。
- 存储：`theme` = `system` | `light` | `dark`，默认 **`system`**。
- 生效方式：调用系统级 `setColorMode(COLOR_MODE_NOT_SET | LIGHT | DARK)`；`system` 即交还系统。
  **它不影响 `lexiThemeColors.mode`（原配/预设/自定义是独立的第二维度）。**

### 2.2 强调色 / 全局色调

- `LexiThemePicker`，标题 `全局色调` + 右侧当前模式标签（`原配色调` / 预设名 / `自定义`）。
- 说明：`统一调整背景、侧栏、按钮和笔记链接，选择后自动保存。`
- 预览卡：`100% × 132`、`radius 10`、1px `workspace_line` 边框；左栏 32% 宽用 `workspace_sidebar`，
  内含 `知萤`、选中的 `笔记` 行（`workspace_selection` 底）、`文件夹`；右栏 `workspace_page`，
  含 `主题预览`、`●`（brand）、分隔线、`让灵感拥有你的颜色`、`[[ 双向链接 ]]`（brand 色）。
- `原配色调` 行：高 44、`radius 14`、左侧 22×22 圆点恒为 `#6E44D9`、右侧 `checkmark`（选中时可见）；
  选中态底 `workspace_selection` + 1px `brand` 边，未选中底 `surface` + 1px `divider`。
- 预设网格：3 列 × 2 行、总高 152、`columnsGap/rowsGap = 10`、单项 `radius 14`；色块 26×26 圆形，
  勾选图标颜色按 `contrast(#FFFFFF, preset) >= 4.5 ? #FFFFFF : #111318` 切换；名称 12 号、选中色 `brand`。
  切换动画 `duration 140, Curve.EaseOut`。
- 自定义三行：`强调色` / `背景` / `前景`，行高 48；右侧胶囊（高 34、`radius 17`、`surface` 底、0.5px `divider` 边）
  内含 12×12 圆点预览、宽 92 高 32 的等宽 12 号输入框（`maxLength 7`）、强调色行额外一个 `chevron_down` 菜单按钮
  （菜单列出 6 个预设名）。
- 提示：`输入颜色后按回车或离开输入框，即可保存。`（11 号）
- 校验提示：`请输入 6 位十六进制颜色，如 #6E44D9`；`前景色与背景色对比度不足，请调整颜色`；
  保存失败：`外观设置保存失败`。

### 2.3 字号（笔记字号）与快速缩放

| 项 | 字段 | 默认 | 范围/行为 |
| --- | --- | --- | --- |
| 字体大小 | `appearanceFontSize` | `16` | 10–32，整数（`Math.round`），滑块 step 1；非法 → 16 |
| 快速调整字体大小 | `appearanceQuickZoom` | `false` | 开启后 Ctrl+滚轮改字号；每格 ±1 |
| 重置 | — | — | 按钮 `重置`，写回 16 |

- 文案：`字体大小` / `调整笔记编辑与预览中的文字大小。` / `重置`；
  `快速调整字体大小` / `开启后，在笔记中使用 Ctrl 与鼠标滚轮调整字号。`
- 滑块为 `SliderStyle.OutSet`，`selectedColor = brand`，仅在 `End` / `Click` 时提交。
- 滚轮锁：`AppStorage['lexiWheelZoomLock']`，缩放连发窗口 `400ms`，Ctrl 看门狗 `6000ms`（防止窗口切换吞掉 key-up 后无法滚动）。
- 该字号同时驱动：编辑正文、阅读预览、代码块（按 `noteFontSize/16` 等比缩放）。

### 2.4 CSS 样式代码片段（仅增强编辑器生效）

- 卡片标题 `CSS 样式代码片段`；副标题 `已启用 {0} 个 · 应用于增强编辑器`（`{0}` = 启用数量）。
- 按钮：`管理` / `收起`（`ButtonStyleMode.TEXTUAL`）。
- 列表项：名称 13 号 + `Toggle`（`selectedColor = brand`）+ `编辑` + `删除`。
- 编辑区：`TextInput` 占位 `片段名称`；`TextArea` 高 140、等宽 12 号、占位
  `输入 CSS，例如：.markdown-preview-view { line-height: 1.8; }`。
- 按钮：`添加片段` / `保存修改`（`brand` 底 + `inverse_text` 字），编辑态额外 `取消`。
- 校验：名称或 CSS 为空 → toast `请填写片段名称和 CSS 代码`。
- 数据结构：`{ id, name, css, enabled }`，`id = ${Date.now()}-${random(0..999999)}`，`enabled` 默认 `true`。
- 仅在 ArkWeb 笔记工作区生效（`LexiCssSnippet` 注释明确）。

### 2.5 界面整体缩放

| 项 | 字段 | 默认 | 范围 |
| --- | --- | --- | --- |
| 缩放比例 | `interfaceZoom` | `100`（%） | 75–150，整数；非法 → 100 |

- 文案：`缩放比例` / `控制应用程序的整体缩放比例`；重置按钮 `↺`（20 号，无障碍 `重置缩放比例`）。
- 数值文本 `${zoom}%`（13 号）。
- 滑块宽 120（窄窗 < 560 时 68），`min 75, max 150, step 1`，`selectedColor = brand`。
- 实现：`setCustomDensity(屏幕 density × zoom / 100, true)` —— **macOS 没有等价 API**，见 9.6。

### 2.6 侧栏宽度

**设置窗口中没有侧栏宽度输入项**（只有拖拽分隔条），字段与默认值如下：

| 字段 | 默认 | 硬范围 | 动态上限 | 保存失败文案 |
| --- | --- | --- | --- | --- |
| `interfaceSidebarWidth`（左/知识库栏） | `244` | 200–480 | `min(clamp(w), max(200, 工作区宽 - ribbon宽 - inspector宽 - 420))` | `侧栏宽度保存失败，请重试。` |
| `interfaceRightSidebarWidth`（右/检查器） | `280` | 232–560 | `min(clamp(w), max(232, 工作区宽 - ribbon宽 - (左栏开?200:0) - 420))` | 同上 |

- 拖动时只改本地临时宽度，`onActionEnd` 才落库。
- 无障碍文案：`拖动调整知识库侧栏宽度` / `拖动调整右侧栏宽度`；折叠按钮 `展开或收起知识库侧栏`。

### 2.7 标签栏、功能区、工具栏密度

| 项 | 字段 | 默认 | 说明 |
| --- | --- | --- | --- |
| 显示标签页标题栏 | `interfaceTabHeaders` | `true` | 文案 `显示标签页标题栏` / `在每个标签页上方显示标题栏。` |
| 显示功能区 | `interfaceRibbon` | `true` | 文案 `显示功能区` / `显示窗口最左侧的功能区，以便快速执行命令。` |
| 功能区命令显隐 | `interfaceHiddenCommands`（JSON 数组） | `[]` | 5 个命令，见 4.5 |
| **工具栏密度** | — | — | **源码中不存在该设置**（全仓无 `紧凑`/`密度`/`density` 设置项；仅 `densityPixels` 用于缩放换算）。功能区宽度固定 56，工具按钮固定 40×40。 |

标签条实测参数（`core/LexiTabStripLayout.ets`）：tab 间距 `3`，最小宽 `104`，首选宽 `196`；
标签高 `40`，选中标签顶边 2px `brand`、底 `workspace_page`、上圆角 `8`；整条高 `52 + topInset`，
底 `workspace_tabs`、底边 0.5px `workspace_line`。新建按钮 76×36、`workspace_selection` 底、`radius 7`。

### 2.8 毛玻璃 / 材质相关开关

**没有任何用户可见的材质开关**。材质是否启用由运行时能力探测决定：

- `uiMaterial.isImmersiveMaterialSupported()`（`pages/Index.ets:202`、`LexiNavigation`、`LexiBackHeader`）。
- 支持 → 使用 `uiMaterial.ImmersiveMaterial`（`ULTRA_THIN` / `THIN` + `materialColor` + `interactive` +
  `applyShadow` + `lightEffect.color`）；不支持 → 退回纯色 token（`brand_soft` / `surface` / `dock_fallback`）。
- 因此**没有 `materialEnabled`、`glass`、`blur` 之类的持久化字段**；不要凭空造设置项。
  若 macOS 端要做"降低透明度"开关，应新增字段（建议 `appearanceReduceTransparency`，默认 `false`），并注明为移植新增。

### 2.9 外观/界面字段总表（含作用域）

作用域说明：`LexiWorkspacePreferences.keys` 列出的键是**按工作区**存储（`workspace:<vaultId>:setting:<key>`），其余全局。

| 存储键 | AppStorage 键 | 类型 | 默认 | 作用域 |
| --- | --- | --- | --- | --- |
| `theme` | 组件 `@Prop theme` | string | `system` | 工作区 |
| `appearanceAccent` | `lexiAccent` | string | `#6E44D9` | 工作区 |
| `appearanceThemeColors` | `lexiThemeColors` | JSON string | `''` | 工作区 |
| `appearanceFontSize` | `lexiFontSize` | number | `16` | 工作区 |
| `appearanceQuickZoom` | `lexiQuickZoom` | boolean | `false` | 工作区 |
| `appearanceSnippets` | `lexiCssSnippets` | JSON string | `[]` | 工作区 |
| `interfaceTabHeaders` | `lexiTabHeaders` | boolean | `true` | 工作区 |
| `interfaceRibbon` | `lexiShowRibbon` | boolean | `true` | 工作区 |
| `interfaceHiddenCommands` | `lexiHiddenRibbonCommands` | JSON string | `[]` | 工作区 |
| `interfaceZoom` | `lexiInterfaceZoom` | number | `100` | 工作区 |
| `interfaceSidebarWidth` | `lexiSidebarWidth` | number | `244` | 工作区 |
| `interfaceRightSidebarWidth` | `lexiRightSidebarWidth` | number | `280` | 工作区 |
| `language` | `lexiLanguage` | string | 系统语言（`en` 或 `zh-Hans`） | 工作区 |
| `defaultTier` | —（`@Prop`） | string | `simple` | 工作区 |
| `workspaceOpenMode` | `lexiWorkspaceOpenMode` | string | `ask` | 全局 |
| `hotkeyOverrides` | `lexiHotkeyOverrides` | JSON string | `[]` | 工作区 |
| `editorDefaultView` | `lexiEditorDefaultView` | string | `edit` | 工作区 |
| `editorDefaultMode` | `lexiEditorDefaultMode` | string | `live` | 工作区 |
| `editorShowTitle` | `lexiEditorShowTitle` | boolean | `true` | 工作区 |
| `editorLimitWidth` | `lexiEditorLimitWidth` | boolean | `true` | 工作区 |
| `editorViewStatus` | `lexiEditorViewStatus` | boolean | `true` | 工作区 |

`lexiColorMode`（0/1）不是设置项，是系统明暗的运行时镜像（由 `Configuration.colorMode` 写入）。

---

## 3. 编辑器设置

### 3.1 持久化字段

`core/LexiEditorSettings.ets:8`，全部按工作区存储。

| 存储键 | AppStorage | 默认 | 含义 | 界面文案 |
| --- | --- | --- | --- | --- |
| `editorDefaultView` | `lexiEditorDefaultView` | `edit` | 新标签页默认视图（`edit` / `preview`） | `新标签页的默认视图`，选项 `编辑视图` / `阅读视图` |
| `editorDefaultMode` | `lexiEditorDefaultMode` | `live` | 编辑视图内的模式（`live` / `source`） | `默认编辑模式`，选项 `实时预览` / `源码模式` |
| `editorShowTitle` | `lexiEditorShowTitle` | `true` | 正文上方的可编辑标题 | `页面内标题` |
| `editorLimitWidth` | `lexiEditorLimitWidth` | `true` | 限制正文宽度 | `限制行宽` |
| `editorViewStatus` | `lexiEditorViewStatus` | `true` | 状态栏显示当前视图并可点按切换 | `视图状态` |
| `workspaceOpenMode` | `lexiWorkspaceOpenMode` | `ask` | 工作区打开方式（全局）：`ask` / `current` / `new` | `工作区打开方式（全局）` |

其他编辑器相关但不在"编辑器"页的字段：字号 `appearanceFontSize`（在"外观"页）、`defaultTier`（本页底部）。

### 3.2 字号 / 行高 / 字体 / 行宽（实测值）

| 项 | 取值 | 证据 |
| --- | --- | --- |
| 正文字号 | `noteFontSize`（默认 16，10–32） | `components/LexiWorkspaceEditor.ets:1114` |
| 正文行高 | `noteFontSize × 1.75`（16 → **28**） | 同上 `.lineHeight(this.noteFontSize * 1.75)` |
| 正文最大宽 | `editorLimitWidth ? 800 : 10000` | `LexiWorkspaceEditor.ets:1142` |
| 笔记标题字号/行高 | `30 / 40`，`FontWeight.Bold` | `LexiWorkspaceEditor.ets:1082` |
| 代码块字号 | `13 × noteFontSize / 16` | `LexiEditorPanels.ets:323` |
| 代码块行高 | `21 × noteFontSize / 16` | 同上 |
| 正文字体 | **无字体选择器**；正文用系统默认字体 | 全仓仅 6 处 `fontFamily`，只出现 `HarmonyOS Sans` 与 `monospace` |
| 预览/卡片正文字体 | `HarmonyOS Sans`（非代码段）、`monospace`（代码段） | `LexiNoteCard.ets:183`、`LexiEditorPanels.ets:270,323` |
| 等宽场景 | CSS 片段输入、主题色输入、代码 | `LexiSettingsWindow.ets:278`、`LexiThemePicker.ets:98` |

> 结论：**没有"字体家族"设置**，也没有"行高倍数"设置。若 macOS 端要加字体选择，属于新增功能。
> 字号是绝对 vp，不随 Dynamic Type 缩放。

### 3.3 拼写检查

- **不是持久化设置**，没有开关字段；每次会话由命令 `spellcheck`（标题 `开启/关闭英文拼写检查`）切换
  只读面板的展开状态（`spellingOpen`）。
- 面板文案：`英文拼写检查`、`重新检查`、建议词按钮、`取消多光标`、`{n} 个输入光标`（多光标数量）等。
- 引擎 `LexiSpellcheck` 基于内置英文词典 + 编辑距离（相邻交换、删/插/替换）。
- 触发：打开面板时检查一次；保存成功后若面板开着会再检查一次。

### 3.4 自动保存

- **始终开启，没有开关**。
- 输入变化 → `statusText = '正在自动保存…'`，400ms 防抖后 `flush()`。
- 失败 → `statusText = '保存失败 · 点击重试'`。
- 状态栏另显示 `${字符数} 字符`、`${n} 个反向链接`。
- 关闭标签前会 `保存并关闭当前标签`（命令 `close-tab`）。

### 3.5 编辑器页其余控件

- `默认编辑工具` 三选一：`简洁`（simple）/ `学习`（study）/ `专业`（pro），按钮高 40、`radius 12`，
  选中 `brand` 底 + `inverse_text` 字，未选中 `workspace_page` 底。
- 默认值 `defaultTier = simple`。
- 说明：`以下视图和显示选项适用于标准编辑器。`、`编辑器设置仅应用于工作区「{0}」。`（`{0}` = 工作区名）。

---

## 4. 设置窗口结构

### 4.1 窗口尺寸与容器

设置以**居中 sheet**呈现（`pages/Index.ets:1717`）：

| 项 | 值 |
| --- | --- |
| 宽 | `wide ? max(480, min(920, viewportWidth - 64)) : 1`（`wide` = 视口 ≥ 840） |
| 高 | `wide ? max(320, min(640, viewportHeight - 120)) : 1` |
| 类型 | `SheetType.CENTER`，`dragBar: false`，`showClose: false` |
| 圆角 | `12` |
| 底色 | `palette.workspace_page` |
| 关闭 | Esc 键（`keyCode 2070`）关闭；右上 `关闭` 文本按钮 |

窗口内部（`LexiSettingsWindow.build`）：

- 根 `100% × 100%`，`clip(true)`，`focusable`，`defaultFocus`，圆角 `12`（手机布局为 0）。
- 顶部标题栏：高 **38**，底 `workspace_sidebar`，底边 0.5px `workspace_line`；
  居中标题 `设置`（13 号 Medium）；右侧 `关闭`（12 号，高 26，左右 padding 8，`radius 6`）。
- 主体 `Row`：左导航 **216** 宽（`padding {left:12,right:10,top:12,bottom:8}`，底 `workspace_sidebar`，
  右边 0.5px `workspace_line`）+ 右滚动内容区（`layoutWeight(1)`，底 `workspace_page`）。
- 内容列：`constraintSize({maxWidth: 820})`，`padding {left:28,right:28,top:22,bottom:28}`。
- 左栏顶部搜索框：高 32、`radius 16`、底 `workspace_page`、1px `workspace_line` 边、左侧 `search` 图标 14；
  输入框 12 号、占位 `搜索设置...`、caret `brand`。
- 分组标题 `选项`：11 号 Medium、`text_secondary`、`padding {left:8,top:6,bottom:4}`。
- 导航项：高 **32**（当宽度 < 560 且语言为 `en` 时 44），`padding {left:10,right:8}`，`radius 6`，
  图标 15，文字 13；选中底 `workspace_selection` + 文字 `text_primary` + `Medium`，未选中 `Regular` + `text_secondary`。
- 搜索只过滤**分类名**（`visibleCategories`），不搜索条目。

### 4.2 左侧分类导航（7 项，顺序即显示顺序）

| id | 名称 | 英文 | 图标资源 | 备用字形 |
| --- | --- | --- | --- | --- |
| `about` | 关于 | About | `profile`（`app.media.ic_dock_profile`） | `◎` |
| `appearance` | 外观 | Appearance | `sun`（`ic_sun`） | `◐` |
| `interface` | 界面 | Interface | `canvas`（`ic_canvas`） | `▭` |
| `editor` | 编辑器 | Editor | `note`（`ic_note`） | `✎` |
| `data` | 文件与链接 | Files and links | `folder`（`ic_folder`） | `❐` |
| `plugins` | 插件 | Plugins | `spark`（= `ic_star`） | `⧉` |
| `hotkeys` | 快捷键 | Keyboard shortcuts | `spark`（= `ic_star`） | `⌘` |

图标是单色 SVG（`supportSvg2`），用 `colorFilter` 染色：选中 = `brand`，未选中 = `text_secondary`。

另有隐藏子页 `ribbon-settings`，标题 `功能区`，不在导航里列出（从"界面"页进入，带返回）。

初始分类：`initialCategory` 默认 `about`；工作区"设置"入口传 `about`，"管理插件"入口传 `plugins`。

### 4.3 关于（`about`，默认页，无页面大标题）

按顺序：

1. 行 `版本`（14 Medium，左）+ 右侧版本号（13，`text_secondary`；取不到时显示 `—`）。行内上下 padding 16。
2. `Divider`（`workspace_line`，0.5px）。
3. **存储区块**：
   - 标题行：`保存位置：文档目录` / `保存位置：应用内部`（13，`text_primary`）。
   - 说明：外部 → `笔记以 Markdown 文件保存在文档目录；如授权失效，可重新授权。`；
     内部 → `未授权文档目录，笔记仍可正常保存。卸载应用前请先导出备份。`（12，`text_secondary`）。
   - 不可选目录的设备额外显示：`此设备使用系统提供的应用文档目录，无需手动选择文件夹。`
   - 按钮（宽 100%、高 42、`radius 12`、`brand_soft` 底、`brand` 字、13 号）：
     忙碌 `正在设置保存位置…`；外部且可选 `更改文档目录`；外部且不可选 `重新授权文档目录`；内部 `授权文档目录`。
     禁用条件：`busy || storageAccessBusy`。
4. `Divider`。
5. **语言**：`语言`（14 Medium）+ `Select`：`简体中文` / `English`（13 号，`text_secondary`）。
   失败 toast：`语言切换失败，请重试。`
6. `Divider`。
7. **使用帮助**：`使用帮助`（14 Medium）+ 右侧按钮 `打开`（高 32、左右 padding 16、`radius 7`、
   `workspace_selection` 底、`text_primary` 字、12 号）。
8. 整页容器：`padding {left:20,right:20}`、底 `soft_surface`、`radius 12`。

### 4.4 外观（`appearance`）

页标题 `外观`（18 Bold，仅桌面布局显示）。

**卡片 A：基础颜色**（`padding 16`、底 `soft_surface`、`radius 12`、内部纵向间距 10）

1. `基础颜色`（14 Medium）。
2. `设置应用的明暗外观。`（12）。
3. 三段选择器（见 2.1）。
4. `Divider`。
5. 主题/强调色选择器（见 2.2）。
6. `Divider`。
7. `CSS 样式代码片段`（14 Medium）+ `已启用 {0} 个 · 应用于增强编辑器`（12）+ 右侧 `管理` / `收起`。
8. 展开后：片段列表、`编辑`、`删除`、`片段名称` 输入、CSS 文本域、`添加片段` / `保存修改`、`取消`（见 2.4）。

**区块标题 `字体`（16 Bold）**

**卡片 B：字体**（同卡片样式）

1. `字体大小`（14 Medium）+ `调整笔记编辑与预览中的文字大小。`（12）+ 右侧 `重置` + 数值 `${fontSize}`（13）。
2. 滑块 10–32，step 1。
3. `Divider`。
4. `快速调整字体大小`（14 Medium）+ `开启后，在笔记中使用 Ctrl 与鼠标滚轮调整字号。`（12）+ 右侧 Toggle。

### 4.5 界面（`interface`）与功能区子页

页标题 `界面`（18 Bold）。

**卡片 A**（底 `soft_surface`、`radius 12`、左右 padding 20，行内上下 padding 16，行间 `Divider`）

1. `显示标签页标题栏`（14）+ `在每个标签页上方显示标题栏。`（12）+ Toggle。
2. `显示功能区`（14）+ `显示窗口最左侧的功能区，以便快速执行命令。`（12）+ Toggle。
3. 可点行（高 72，透明底）：`功能区`（14）+ `设置哪些命令需要显示在功能区上。`（12）+
   右侧 `chevron_right` 12 → 进入 `ribbon-settings`。

**区块标题 `高级`（15 Bold）**

**卡片 B**：`缩放比例`（14）+ `控制应用程序的整体缩放比例`（12）+ 右侧 `↺` / `${zoom}%` / 滑块。
窗口宽 < 700 时改为上下两行布局。

**功能区子页（`ribbon-settings`）**

1. 返回按钮：`‹  界面`（13，`brand` 色，透明底）。
2. 标题 `功能区`（18 Bold，桌面布局）。
3. 说明：`选择要显示在功能区上的命令。设置入口始终可用。`（12）。
4. 5 行开关（底 `soft_surface`、`radius 12`、左右 padding 20、行内上下 padding 14）：

| id | 名称 | 英文 |
| --- | --- | --- |
| `vault` | 知识库 | — |
| `switcher` | 快速切换文档 | — |
| `commands` | 命令面板 | — |
| `reading` | 切换编辑与阅读 | — |
| `graph` | 笔记关联 | — |

开关状态 = `!interfaceHiddenCommands.includes(id)`；写库时维护黑名单数组。

### 4.6 编辑器（`editor`）

1. `以下视图和显示选项适用于标准编辑器。`（12）
2. `编辑器设置仅应用于工作区「{0}」。`（12，`id = settings-workspace-scope`）
3. **工作区打开方式（全局）** 卡片（`padding 20`、`soft_surface`、`radius 12`）：
   `工作区打开方式（全局）`（14 Medium）+ `所有工作区共用此打开方式；选择“每次询问”可恢复提示。`（12）+
   `Select`：`每次询问` / `在当前窗口打开` / `在新窗口打开`。
4. **视图卡片**（`soft_surface`、`radius 12`、左右 padding 20，行内上下 16，`Divider` 0.5px）
   - `新标签页的默认视图` + `设置新打开笔记的默认视图。` + `Select`：`编辑视图` / `阅读视图`。
   - `默认编辑模式` + `编辑视图中，新打开笔记采用的编辑模式。` + `Select`：`实时预览` / `源码模式`。
   - `视图状态`（14 Medium）+ `在状态栏显示当前视图，并点击切换阅读和编辑。`（12）+ Toggle。
5. **区块 `显示`（16 Bold）** → 卡片：
   - `页面内标题` + `在正文上方显示可编辑的笔记标题。` + Toggle
   - `限制行宽` + `限制正文宽度，让较长的段落更易阅读。` + Toggle
6. **区块 `编辑器类型`（16 Bold）** → 卡片（`padding 20`）：
   - `默认编辑工具`（14 Medium）
   - 三个等宽按钮：`简洁` / `学习` / `专业`（高 40、`radius 12`）
7. 失败 toast：`编辑器设置保存失败，请重试。`

### 4.7 文件与链接（`data`）

1. 区块标题 `数据与备份`（15 Bold）。
2. 存储区块（与"关于"页同一 Builder，文案见 4.3-3）。
3. 若存在备份：`最近备份：{0}`（12，`brand` 色）。
4. 若 `dataStatus` 非空：一段 12 号 `text_secondary` 文本，`padding 10`、`soft_surface` 底、`radius 10`。
5. `导出完整备份 (.json)`：宽 100%、高 42、`radius 12`、`brand` 底、`inverse_text` 字、13 号。
6. `导出 Markdown 合集 (.md)`：同尺寸、`brand_soft` 底、`brand` 字。
7. 一行两个按钮（各占一半、高 40、`radius 10`、`soft_surface` 底、`text_primary` 字、12 号）：
   `导入 / 恢复备份`、`重建索引`。

### 4.8 插件（`plugins`）

1. 顶部说明：`插件启用状态与插件设置仅应用于工作区「{0}」。`（12，`id = settings-plugin-workspace-scope`）
2. 插件面板（**硬编码中文，未走 i18n**）：
   - `插件`（18）
   - `兼容 LexiNote 协议和 Obsidian 协议。`（13）
   - `已安装插件在所有工作区中可见，启用和停用状态由各工作区独立保存。`（12）
   - `实验性插件支持：仅安装你自己编写或已审查的插件。Obsidian 兼容层只覆盖已测试的 API 子集，未实现的能力会返回明确错误。`（12）
   - `运行时：${runtimeLabel}`、`已安装 ${n} 个`、按钮 `从本地安装 ZIP…`
   - 空态：`尚未安装插件。请自行下载插件，再通过「从本地安装 ZIP…」导入。`
   - 每张插件卡：状态徽标（`minWidth 52`、`radius 10`、启用 `success`）、名称（14 Medium）、
     `${id} · v${version} · ${kindLabel}`（11）、Toggle `授予全部权限` + `仅对当前插件生效；关闭将撤回全部权限并停用。`
     （11）、错误行、按钮 `启用`/`停用`、`能力与诊断`/`收起权限`、`卸载`；
     展开后 `能力授权（取消勾选立即生效）`、逐能力 Toggle、`该插件未声明任何能力`、`诊断日志`、`暂无日志`。
   - 底部固定说明：`模型能力说明：…`（仅当有 AI 能力插件时）、
     `安全说明：插件只能通过受控 RPC 访问当前授权的知识库；不支持 Node.js/Electron 模块、绝对路径或网络能力。禁用插件会立即释放其事件、命令与运行时资源。`

### 4.9 快捷键（`hotkeys`）

见第 5 章。页内顺序：标题 `快捷键`（16 Bold）→ 说明 → 搜索框（高 36、13 号）→ 反馈文本 → 命令行列表。

### 4.10 未知分类的兜底页

`{0}选项`（14 Medium）+ `配置与管理「{0}」相关偏好设置。`（12）+ 按钮 `配置`（高 32、左右 padding 14、
`radius 7`、`workspace_selection` 底）。仅当传入未知 `category` 时出现。

### 4.11 手机 / 窄窗布局（< 560）

- `phoneLayout() = min(settingsWidth, viewportWidth) < 560`。
- 顶部栏高 `48 + topInset`（`pageMode` 用 `LexiBackHeader` 时为 `56 + topInset`）：
  左返回圆钮 40×40（`chevron_left` 20，无障碍 `返回设置`）或 40 宽占位；中标题 17 Bold（根页 `设置`，
  子页为分类名）；右关闭圆钮（`xmark` 17，无障碍 `关闭`）。底 `workspace_sidebar`、底边 0.5px。
- 根页为分类列表：`选项`（12 Medium）+ 卡片（36×36 图标盒、`radius 10`、`brand_soft` 底、
  文字 15、`chevron_right` 12、卡片 `radius 14`、`surface` 底、内 padding `{12,12,10,10}`）。
- 列表**不显示** `interface` 与 `hotkeys` 两项（`phoneCategories()` 过滤）。
- 进入子页有 `move(START)+OPACITY` 入场动画 220ms `FastOutSlowIn`；子页为 `move(END)` 240ms。
- 子页标题栏使用 `Navigation` + `titleMode Mini` + `ScrollEffectType.GRADUAL_BLUR`。
- 内容 padding 变为 `{left:16,right:16,top:18,bottom:24+bottomInset}`。
- `pageMode`（独立路由页）时根页副标题：`外观、编辑器、插件与数据`。

---

## 5. 快捷键设置

### 5.1 规范与显示

- 绑定字符串格式：`Ctrl+Meta+Alt+Shift+KEY`（按 Ctrl → Meta → Alt → Shift → 键名 顺序拼接，`+` 分隔）。
- 键名大写：`A`–`Z`、`0`–`9`、`F1`–`F12`、`ARROWUP/DOWN/LEFT/RIGHT`、`ENTER`、`TAB`、`SPACE`、
  `ESCAPE`、`BACKSPACE`、`DELETE`、`INSERT`、`HOME`、`END`、`PAGEUP`、`PAGEDOWN`、`PRINTSCREEN`、
  `,` `.` `` ` `` `-` `=` `[` `]` `\` `;` `'` `/`。
- 修饰键本身（`isModifierCode`）永不作为绑定；无修饰键且非 F1–F12 的按键不产生绑定。
- 界面直接显示原始字符串（如 `Ctrl+ENTER`、`Ctrl+Alt+ARROWLEFT`），**不做 ⌘/⌥ 符号美化**。

### 5.2 默认绑定（`LexiHotkeySettings.defaults`）

共 38 条；其余命令默认"未设置"。

| 动作 id | 命令标题（中文原文） | 默认组合键 |
| --- | --- | --- |
| `link-open` | 打开光标处的链接 | `Alt+ENTER` |
| `link-open-tab` | 在新标签页中打开光标处链接 | `Ctrl+ENTER` |
| `link-open-group` | 在新标签组中打开光标处链接 | `Ctrl+Alt+ENTER` |
| `link-open-window` | 在新窗口中打开光标处链接 | `Ctrl+Alt+Shift+ENTER` |
| `rename` | 编辑文件名 | `F2` |
| `find` | 在当前笔记中查找 | `Ctrl+F` |
| `replace` | 在当前笔记中查找并替换 | `Ctrl+Alt+F` |
| `search-all` | 搜索：在所有文件中搜索 | `Ctrl+Shift+F` |
| `editor-link` | 插入链接 | `Ctrl+K` |
| `editor-comment` | 注释/取消注释 | `Ctrl+/` |
| `editor-todo` | 插入待办事项 | `Ctrl+L` |
| `editor-delete-paragraph` | 删除段落 | `Ctrl+D` |
| `property-add` | 增加笔记属性 | `Ctrl+;` |
| `tab-reopen` | 重新打开标签页 | `Ctrl+Shift+T` |
| `back` | 返回 | `Ctrl+Alt+ARROWLEFT` |
| `forward` | 前进 | `Ctrl+Alt+ARROWRIGHT` |
| `switcher` | 快速切换文档 | `Ctrl+O` |
| `palette` | 打开命令面板 | `Ctrl+P` |
| `reading` | 切换编辑与阅读 | `Ctrl+E` |
| `editor-bold` | 加粗/取消加粗 | `Ctrl+B` |
| `editor-italic` | 倾斜/取消倾斜 | `Ctrl+I` |
| `new` | 新建 Markdown 笔记 | `Ctrl+N` |
| `save` | 保存当前文件 | `Ctrl+S` |
| `close-tab` | 保存并关闭当前标签 | `Ctrl+W` |
| `graph` | 打开笔记关联 | `Ctrl+G` |
| `settings` | 打开设置 | `Ctrl+,` |
| `help` | 打开使用说明 | `F1` |
| `tab-prev` | 转到上一个标签页 | `Ctrl+Shift+TAB` |
| `tab-next` | 转到下一个标签页 | `Ctrl+TAB` |
| `tab-1`…`tab-8` | 转到标签页 #1…#8 | `Ctrl+1`…`Ctrl+8` |
| `tab-9` | 转到最后一个标签页 | `Ctrl+9` |

不会自动绑定、但存在于命令表的关键命令：`save-template`、`daily`、`templates`、`theme-picker`、
`zoom-in/out/reset`、`font-increase/decrease`、`width-toggle`、`source-toggle`、`spellcheck` 等。

### 5.3 录制交互

1. 每行右侧 `+` 按钮（高 30、左右 padding 9、`soft_surface` 底）；点击进入录制。
2. 录制中：按钮文案变 `按下快捷键…`，按钮底 `workspace_selection`，整行底也变 `workspace_selection`；
   顶部反馈区显示 `请按下要绑定的组合键，Esc 取消。`
3. 再次点同一按钮 = 取消。
4. 点击窗口任意位置（`TouchType.Down`）取消录制；退出设置页/窗口消失也取消。
5. Esc（`2070`）取消；纯修饰键按下被吞掉且不报错。
6. 无修饰键且非功能键 → `请同时按下修饰键（Ctrl / Alt / Shift）与按键，或直接按 F1–F12。`
7. 命中系统保留组合 → `与系统快捷键冲突：{0}（{1}），请换一个组合键。`（`{1}` 为原因，如 `复制`）。
8. 已被其他命令占用 → `快捷键已被占用：` + 该命令标题 + ` · ` + 绑定。
9. 与自身现有绑定重复 → 静默取消录制。
10. 成功 → 追加该绑定（**一个命令可多绑定**），反馈 `已绑定` + 空格 + 绑定，录制结束。
11. 失败 → `快捷键保存失败，请重试。`
12. 已有绑定以胶囊显示：`${binding} ×`（高 28、左右 padding 7、`radius 14`），点击即删除该条并清空反馈。
13. `重置`（11 号文本按钮）：恢复默认；若默认键已被**其他命令**占用，则提示 `快捷键已被占用：` + 对方标题，不重置。
14. 无绑定显示 `未设置`（11，`text_secondary`）。
15. 与其它命令共用同一键 → 行内标 `冲突`（11，`brand` 色）；命中系统保留 → 标 `系统冲突`，
    无障碍文案附带原因。

### 5.4 系统保留组合（`LexiSystemShortcuts.RESERVED`）

| 组合 | 原因 | 英文 |
| --- | --- | --- |
| `Alt+F4` | 关闭窗口 | close window |
| `Alt+TAB` | 切换窗口 | switch window |
| `Alt+Shift+TAB` | 切换窗口 | switch window |
| `Alt+SPACE` | 窗口菜单 | window menu |
| `Ctrl+Alt+DELETE` | 系统安全 | system security |
| `Ctrl+Shift+ESCAPE` | 任务管理器 | task manager |
| `Ctrl+SPACE` | 输入法切换 | input method switch |
| `PRINTSCREEN` | 屏幕截图 | screen capture |
| `Ctrl+C` | 复制 | copy |
| `Ctrl+V` | 粘贴 | paste |
| `Ctrl+X` | 剪切 | cut |
| `Ctrl+Z` | 撤销 | undo |
| `Ctrl+Shift+Z` | 重做 | redo |
| `Ctrl+Y` | 重做 | redo |
| `Ctrl+A` | 全选 | select all |
| 任何 `Meta+…` | 系统按键 | system key |

> macOS 端需替换为 `⌘` 语义：`⌘C/⌘V/⌘X/⌘Z/⇧⌘Z/⌘A`、`⌘Q`、`⌘W`、`⌘M`、`⌘Tab`、`⌘Space`、`⇧⌘3/4/5` 等。
> 建议保留"冲突检测 + 原因文案"这套机制，只换表。

### 5.5 设置页搜索与列表

- 说明：`搜索命令，点击「+」后按下组合键；Esc 取消录制。`
- 搜索框占位 `搜索命令或快捷键`，匹配标题、来源、id、当前绑定（全部小写包含）。
- 列表按标题 `localeCompare` 升序；每行底部 0.5px `workspace_line`；行内 padding `{left:6,right:6,top:8,bottom:8}`、`radius 6`。
- 来源列显示 `知萤`（英文 `LexiNote`）；当来源 ≠ `知萤` 时额外显示来源小字（10 号）。
- 存储：`hotkeyOverrides` = `[{ id, bindings: string[] }]`，按工作区。

---

## 6. 欢迎引导（3 步）

容器：`100% × 100%`，底 `workspace_page`，`padding {top: topInset, bottom: bottomInset}`。

顶部栏（高 58，左右 padding 24 / 24+窗口按钮内缩）：
- 应用图标 `lexi_logo` 28×28、`radius 7`；标题 `知萤 LexiNote`（16 Medium，英文 `LexiNote`）。
- 右侧 `跳过`（文本按钮，高 44，13 号，`text_secondary`）→ 直接结束。

内容列：`maxWidth 480`，`padding {24,24,24,36}`，纵向间距 20。

演示区：`100% × 260`、底 `workspace_sidebar`、`radius 28`，`accessibilityLevel('no-hide-descendants')`。

分页点：当前 `24×7`（`radius 4`，`brand`），其余 `7×7`（`workspace_line`）；动画 180ms（减动效时 0）；
无障碍 `第 {0} 步，共 3 步`。

| 步骤 | 标题 | 正文 | 演示区内容 |
| --- | --- | --- | --- |
| 1 | `从一条想法开始` | `点击「新建」写下第一条笔记。` | 笔记卡（`你的第一条想法` + 3 条骨架线，248 宽、`padding 24`、`radius 22`、`surface` 底）+ 悬浮按钮 `新建` |
| 2 | `用文件夹收纳项目` | 宽屏：`在左下角打开「工作区与项目」，绑定本地文件夹与项目。`<br>窄屏：`在「知识库」打开「工作区与项目」，绑定本地文件夹与项目。` | `我的工作区` 卡 + `项目一` / `项目二` 两个文件夹块 |
| 3 | `让想法自由连接` | `用导图整理分支，用白板摆放卡片，拖动即可调整位置。` | `一个想法`（mindmap）与 `新的连接`（canvas）两张卡 + `plus` 图标，带位移动画 |

标题：28 Bold、`text_primary`、居中。正文：15 号、`lineHeight 25`、`text_secondary`、居中、`minHeight 76`。

底部按钮区（间距 12）：
- 步骤 > 0 时显示 `上一步`（文本按钮，高 48，14 号，`text_secondary`）。
- 主按钮：步骤 1、2 为 `下一步`；步骤 3 为 `进入工作区`。高 48、`layoutWeight(1)`、`radius 14`、
  `brand` 底、`inverse_text` 字、15 号。

动效：弹簧 `springMotion(0.42, 0.86)`；减动效时直接把动画相位设为 1（无位移）。

---

## 7. 模板库

### 7.1 数据模型

`LexiTemplateItem`：`{ id, title, content, category, tags[], properties[], builtIn, sourceNoteId, createdAt, updatedAt }`。
`LexiTemplateLibraryState`：`{ version: 1, templates[], defaultDailyId: 'builtin-daily', legacyImported: false }`。

- 内置模板 `builtIn = true`，id 前缀 `builtin-`。
- **没有"描述"字段**；卡片上的描述文本是正文首段的摘要（`MarkdownEngine.extractSnippet`，最多 3 行），
  空正文时显示 `空白模板`。
- 变量：`{{date}}` → `YYYY-MM-DD`；`{{time}}` → `HH:mm`；`{{weekday}}` → `星期日`…`星期六`（硬编码中文）；
  `{{title}}` → 笔记标题。未匹配的 token 原样保留。

### 7.2 六个内置模板

| id | 名称 | 分类 | 标签 |
| --- | --- | --- | --- |
| `builtin-daily` | 每日记录 | 日常 | `日记` |
| `builtin-schedule` | 日程计划 | 计划 | `计划` |
| `builtin-code` | 代码笔记 | 代码 | `代码` |
| `builtin-study` | 学习笔记 | 学习 | `学习` |
| `builtin-meeting` | 会议纪要 | 会议 | `会议` |
| `builtin-project` | 项目规划 | 项目 | `项目` |

正文骨架（逐字）：

`builtin-daily` 每日记录：

```markdown
# {{date}} {{weekday}}

## 今日重点

- [ ]

## 随手记录



## 今日回顾

- 今天完成了什么：
- 明天想继续什么：
```

`builtin-schedule` 日程计划：

```markdown
# {{title}}

日期：{{date}} {{weekday}}

## 时间安排

| 时间 | 事项 | 备注 |
| --- | --- | --- |
| 上午 |  |  |
| 下午 |  |  |
| 晚间 |  |  |

## 待办清单

- [ ]

## 调整与提醒

```

`builtin-code` 代码笔记（模板正文自身含一对空代码围栏，故用四反引号包裹）：

````markdown
# {{title}}

记录时间：{{date}} {{time}}

## 问题与目标



## 代码

```

```

## 实现说明

## 验证结果

- 输入与环境：
- 预期结果：
- 实际结果：

## 后续改进

- [ ]
````

`builtin-study` 学习笔记：

```markdown
# {{title}}

学习日期：{{date}} {{weekday}}

## 学习目标

- [ ]

## 核心概念



## 示例与理解



## 疑问与关联



## 复习清单

- [ ] 用自己的话解释核心概念
- [ ] 完成一次练习
```

`builtin-meeting` 会议纪要：

```markdown
# {{title}}

会议时间：{{date}} {{time}}
参会人员：

## 议题

1.

## 讨论记录



## 决定事项



## 后续行动

| 事项 | 负责人 | 截止时间 | 状态 |
| --- | --- | --- | --- |
|  |  |  | 待办 |

## 下次跟进

```

`builtin-project` 项目规划：

```markdown
# {{title}}

创建日期：{{date}}

## 目标与范围

- 项目目标：
- 交付内容：
- 验收标准：

## 里程碑

| 阶段 | 交付物 | 计划完成时间 |
| --- | --- | --- |
| 准备 |  |  |
| 实施 |  |  |
| 验收 |  |  |

## 当前任务

- [ ]

## 风险与依赖



## 进展记录

### {{date}} {{time}}

```

### 7.3 模板库界面文案

- 顶部说明：`选择一个模板开始记录，也可以编辑内置模板，或创建自己的模板。`
- 标题输入占位：`新笔记标题（可选）`。
- 按钮：`新建模板`、`清除日记默认`、`使用模板`、`编辑`、`删除`、`设为日记默认` / `日记默认 ✓`。
- 徽标：`内置` / `自建`、分类名、`日记默认`（当前默认）。
- 空态：`模板库还没有内容。点击「新建模板」开始，或将已有笔记保存为模板。`
- 删除确认：标题 `删除「${title}」？`，正文 `此操作只删除模板，不影响已经用它创建的笔记。` +
  （内置时）`内置模板删除后也不会自动恢复。` + （当前默认时）`当前日记默认模板也会被清除。`；
  按钮 `取消` / `删除模板`。

---

## 8. 界面语言机制与文案

### 8.1 机制

- 只有两个语言：`zh-Hans`（源语言）与 `en`。
- 存储键 `language`（**按工作区**），默认取系统：`getAppPreferredLanguage()`（非 `default` 时）否则
  `getSystemLanguage()`；以 `en` 开头 → `en`，其余 → `zh-Hans`。异常回退 `zh-Hans`。
- 运行时镜像：`AppStorage['lexiLanguage']`。
- 取词：`LexiI18n.text(source, language?, args?)`：
  1. `en` → 查 `LEXI_ENGLISH` 表，缺失则回退中文原文；
  2. `zh-Hans` → 直接用中文原文；
  3. 依次把 `{0}`,`{1}`,… 替换为 `args`（简单 `split/join`，无复数、无日期格式）。
- 英文词条 512 条，键是**中文原文**（所以中文即 key，改中文等于改 key）。
- **不翻译**：笔记内容、文件名、插件自带文案、模板标题与正文、`{{weekday}}` 星期名、
  以及插件设置面板的硬编码中文。
- 切换入口：设置 → 关于 → `语言`（`简体中文` / `English`）；失败提示 `语言切换失败，请重试。`

### 8.2 中英文对照示例（设置域）

| 中文（原文 key） | 英文 |
| --- | --- |
| 设置 | Settings |
| 关于 | About |
| 外观 | Appearance |
| 界面 | Interface |
| 编辑器 | Editor |
| 文件与链接 | Files and links |
| 插件 | Plugins |
| 快捷键 | Keyboard shortcuts |
| 跟随系统 | System |
| 浅色 | Light |
| 深色 | Dark |
| 外观：跟随系统 | Appearance: system |
| 外观：浅色 | Appearance: light |
| 外观：深色 | Appearance: dark |
| 全局色调 | Color palette |
| 原配色调 | Original colors |
| 强调色 | Accent |
| 背景 | Background |
| 前景 | Foreground |
| 主题预览 | Theme preview |
| 让灵感拥有你的颜色 | Give your ideas a little color |
| 统一调整背景、侧栏、按钮和笔记链接，选择后自动保存。 | Colors backgrounds, sidebars, buttons, and note links. Saves automatically. |
| 输入颜色后按回车或离开输入框，即可保存。 | Press Enter or leave the field to save the color. |
| 前景色与背景色对比度不足，请调整颜色 | Foreground and background need more contrast. Please adjust the colors. |
| 字体大小 | Font size |
| 鸢尾紫 / 玫瑰粉 / 暖杏橙 | Iris / Rose / Apricot |
| 森林绿 / 晴空蓝 / 石墨灰 | Forest / Sky / Graphite |
| 显示标签页标题栏 | Show tab headers |
| 显示功能区 | Show ribbon |
| 缩放比例 | Zoom level |
| 数据与备份 | Data and backups |
| 导出完整备份 (.json) | Export full backup (.json) |
| 导入 / 恢复备份 | Import / restore backup |
| 版本 | Version |
| 语言 | Language |
| 使用帮助 | Help |
| 搜索设置... | Search settings… |
| 选项 | Options |
| 第 {0} 步，共 3 步 | （无英文词条，英文界面下仍显示中文） |
| 从一条想法开始 | Start with an idea |
| 用文件夹收纳项目 | Organize projects with folders |
| 让想法自由连接 | Connect your ideas |
| 点击「新建」写下第一条笔记。 | Click “New” to write your first note. |
| 跳过 / 上一步 / 下一步 / 进入工作区 | Skip / Previous / Next / Enter workspace |
| 知萤 LexiNote | LexiNote |
| 知萤 | LexiNote |

### 8.3 已发现的 i18n 缺口（移植时应补齐）

1. `第 {0} 步，共 3 步` 无英文词条。
2. `{{weekday}}` 恒为中文星期名。
3. 模板的 `title` / `category` / `tags` 不翻译。
4. 插件设置面板整页硬编码中文。
5. 部分 toast/内联错误（如编辑器的 `英文拼写检查`、`正在自动保存…`、`保存失败 · 点击重试`）未走 `tr()`。
6. 快捷键绑定的显示不本地化（`Ctrl+` 前缀在英文下仍是 `Ctrl`；macOS 建议显示 ⌘/⌥/⇧）。

---

## 9. 依赖 HarmonyOS HDS 材质 / 沉浸光感的元素与 macOS 替代

### 9.1 沉浸材质（`uiMaterial.ImmersiveMaterial`）

统一结构：`style` + `materialColor` + `interactive` + `applyShadow` + `lightEffect.color = dock_light`；
由 `uiMaterial.isImmersiveMaterialSupported()` 决定启用，失败时退回纯色。

| 元素 | 位置 | 材质参数 | 带回退色 |
| --- | --- | --- | --- |
| 底部 dock（手机/窄窗） | `pages/Index.ets:185` | `THIN` + `dock_surface` + shadow + 光感 | `barBackgroundColor = dock_fallback` |
| 标题栏激活胶囊 | `pages/Index.ets:176` | `ULTRA_THIN` + `title_chip_active` + shadow + 光感 | `brand_soft` |
| 顶部导航胶囊（激活/未激活） | `LexiNavigation.ets:18` | `ULTRA_THIN` + `title_chip_active` / 无 materialColor；未激活无 shadow | 激活 `brand_soft`，未激活透明 |
| 返回/操作圆钮 | `LexiBackHeader.ets:19` | `ULTRA_THIN` + `title_chip_surface` / `title_chip_active` + shadow | `surface` / `brand_soft` |

macOS 替代建议：

- `THIN` → `NSVisualEffectView.Material.underWindowBackground` / SwiftUI `.thinMaterial`；
- `ULTRA_THIN` → `.underWindowBackground` + `blendingMode = .behindWindow` / SwiftUI `.ultraThinMaterial`；
- `materialColor`（带 alpha 的 tint）→ 在材质上叠一层 `Color(hex).opacity(alpha/255)` 的 overlay；
  若用 `NSVisualEffectView`，则在其上叠一个同 alpha 的 `NSView`/`CALayer` 背景，不要改 `material` 本身；
- `interactive` → macOS 无直接对应，可用 hover 时 `material` 亮度/缩放微变（0.98→1.0）替代；
- `applyShadow` → `.shadow(color: .black.opacity(0.12), radius: 10, y: 4)`；
- `lightEffect`（高光）→ 可省略，或用 1px 顶部内高光 `LinearGradient(#FFFFFF22 → clear)`；
- 若系统开启"降低透明度"（Accessibility → Display → Reduce transparency），直接用回退纯色 token（表中最后一列），保持视觉一致。

### 9.2 标题栏渐变遮罩（`LexiTitleBackdrop`）

- `linearGradient(angle: 180)`，高度 `56 + topInset`；色标：
  `title_scrim` 0 → `title_scrim` 在 `(48+topInset)/(56+topInset)` → `Color.Transparent` 1。
- macOS：`LinearGradient(colors: [scrim, scrim, .clear], startPoint: .top, endPoint: .bottom)`
  放在 `safeAreaInset(edge: .top)` 的 header 背后；亮色主题 `title_scrim` alpha 为 0（`#00…`，等于无遮罩）。

### 9.3 滚动边缘渐进模糊（`ScrollEffectType.GRADUAL_BLUR`）

- 用于 `Navigation` 标题栏：设置页、帮助页、导图页、白板页、主页面（`Index.ets:1488`）。
- macOS：优先 `.scrollEdgeEffectStyle(.soft, for: .top)`（macOS 26+）；
  低版本用粘性 header + `.ultraThinMaterial` + 顶部 `.mask` 线性渐变模拟。

### 9.4 窗口级沉浸

- `setWindowDecorVisible(false)` + `setWindowDecorHeight(52)` + `setDecorButtonStyle({buttonBackgroundSize:32, buttonIconSize:18})`
  + `getTitleButtonRect()` → `windowButtonsInset`（仅 2in1 PC）。
- `setWindowBackgroundColor(palette.background)`；系统栏透明 + 前景色随主题。
- `expandSafeArea(SYSTEM, [TOP, BOTTOM])`、`ignoreLayoutSafeArea`、`LexiTopInset` / `LexiBottomInset` / `LexiViewportWidth`。
- macOS：`NSWindow.titlebarAppearsTransparent = true`、`.windowStyle(.hiddenTitleBar)`、
  `titlebarSeparatorStyle = .none`、`toolbarStyle = .unified`；用 `safeAreaInsets` 替代 topInset；
  交通灯预留宽度（约 78pt）对应 `windowButtonsInset`；自定义 52pt 头部与交通灯垂直居中。

### 9.5 原生控件主题注入

- `ThemeControl.setDefaultTheme({ colors: {...} })`（20 个语义槽，见 1.3.10）影响 ArkUI 原生控件。
- macOS：`NSApp.appearance`（明暗）、`.tint(palette.brand)`、`.accentColor`、`NSColor` 语义色覆盖；
  `interactiveSelect` → `NSColor.selectedContentBackgroundColor`。

### 9.6 界面缩放（`setCustomDensity`）

- ArkUI 用 `setCustomDensity(density × zoom/100, true)` 全局缩放 75%–150%。
- macOS 没有等价 API。可选方案（按推荐度）：
  1. 全局字号 + 间距系数 `k = zoom/100`，在根部 `Environment` 注入，所有 pt 值乘 k；
  2. 文本用 `.dynamicTypeSize` 映射（会改变断行，与"整体缩放"语义不同）；
  3. `scaleEffect(k)` 仅作最后手段（模糊、命中区域错位）。
- 需注意：原实现缩放的是**整个窗口内容**（含侧栏、标签），不是只放大文字。

### 9.7 其它平台专属、需替换的 API

| ArkTS | 用途 | macOS 建议 |
| --- | --- | --- |
| `SymbolGlyph(sys.symbol.*)` | chevron/checkmark/xmark/gearshape/list_bullet | SF Symbols（`chevron.right`、`checkmark`、`xmark`、`gearshape`、`list.bullet`） |
| `Toggle(ToggleType.Switch)` | 所有开关 | `Toggle().toggleStyle(.switch)`（注意 macOS 开关更小） |
| `Slider(SliderStyle.OutSet)` | 字号/缩放 | `Slider` + `.controlSize(.small)` |
| `Select([{value}])` | 视图/模式/语言 | `Picker` + `.menu` 样式 |
| `bindSheet(SheetType.CENTER)` | 设置窗口 | 独立 `NSWindow`/`Window` 场景（macOS 惯例是设置窗口而非 sheet）或 `.sheet` |
| `ButtonStyleMode.TEXTUAL` | 文本按钮 | `.buttonStyle(.plain)` / `.link` |
| `getPromptAction().showToast` | 错误提示 | `NSBeep` + 行内错误文本，或自定义 toast |
| `expandSafeArea` | 全屏沉浸 | `ignoresSafeArea` + 安全区读取 |
| `setWindowSystemBarProperties` | 状态栏 | 不适用（macOS 无系统状态栏） |

---

## 10. 移植时必须保留的"硬约束"

1. 色板永远是一个**不可变快照**（28 键整体替换），不是逐像素计算；切换主题 = 换快照。
2. 生成色板必须保留 `readable` 的 4.5 阈值与「先选中底、再 soft_surface」的双重校验顺序，
   否则 `text_*` / `brand` 会与原型不一致。
3. `title_chip_active` / `dock_*` / `title_scrim` 的 alpha 前缀是**按亮暗写死**的，不要用通用不透明度推导。
4. `inverse_text` 只用 `#FFFFFF` / `#111318` 两个候选。
5. 自定义模式用 `luminance(background) < 0.179` 判定画布明暗，而不是跟随系统主题。
6. 设置项默认值、范围、非法值回退（16 / 100 / 244 / 280 / 10–32 / 75–150 / 200–480 / 232–560）需逐一对齐。
7. 快捷键是"多绑定"模型（一个动作可有多条），存储为覆盖表；重置 = 删除覆盖行。
8. 设置窗口左栏 216、标题栏 38、内容最大宽 820、圆角 12、sheet 尺寸公式见 4.1。
9. 分类型页面里，`interface` 与 `hotkeys` 在窄窗（< 560）**不出现**。
10. 语言键是中文原文，英文表 512 条；缺失词条回退中文。
