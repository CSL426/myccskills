---
name: react-bits
description: Use when building React UIs that need animated or eye-catching elements — animated text effects, hero/landing backgrounds, cursor effects, glass/glow cards, docks, galleries, or scroll animations. React Bits (reactbits.dev) offers 139 copy-paste animated components in 4 variants (JS/TS × CSS/Tailwind), installable via shadcn CLI. Consult this skill to pick the right component, get the exact install command, and fetch full source from the registry — even when the user just says "make it more dynamic/flashy" without naming the library.
---

# React Bits 動畫元件庫

[React Bits](https://reactbits.dev)(GitHub: DavidHDev/react-bits)是開源的 React 動畫元件集,共 139 個元件、四大分類:文字動畫、動畫效果、元件、背景。每個元件有 4 種變體(JS/TS × CSS/Tailwind),MIT + Commons Clause 授權(個人與商用皆免費)。

適用時機:landing page 的 hero 背景、標題文字動畫、滑鼠游標特效、卡片 hover 效果、捲動動畫等「視覺亮點」需求。它不是完整 UI 框架 — 表單、表格等基礎元件仍用一般元件庫(見 `ui-component-libraries` skill);設計品味決策仍歸 `hallmark` skill 管。

## 挑選流程

1. 依需求分類(文字動畫 / 動畫效果 / 元件 / 背景)查 `references/components.md` — 內含全部 139 個元件的一句話描述、頁面路徑與相依套件。
2. 留意相依套件成本:標 `three` / `ogl` / `postprocessing` 的是 WebGL 元件,效果強但 bundle 較重;標 `motion` / `gsap` 的較輕;標「無」的零依賴。同頁面多個元件盡量共用同一動畫引擎,避免 motion + gsap + three 全都進來。
3. 官網元件頁(`https://reactbits.dev/<分類>/<kebab-name>`)可看即時 demo 與 props 說明,但該站是 SPA,**WebFetch 抓不到內容** — 要看原始碼與 props 直接抓 registry JSON(見下)。

## 安裝方式

**shadcn CLI(建議)** — 元件名格式 `<Name>-<TS|JS>-<TW|CSS>`,依專案選變體(TypeScript + Tailwind 專案用 `-TS-TW`):

```bash
pnpm dlx shadcn@latest add @react-bits/BlurText-TS-TW
```

相依套件(motion、gsap、three 等)會由 CLI 自動裝好。也支援 jsrepo,或從官網元件頁手動複製貼上。

**直接取得原始碼**(不經 CLI、或想先看程式碼再決定):registry JSON 含完整 source 與 dependencies:

```bash
curl -sL "https://reactbits.dev/r/BlurText-TS-TW.json"
# .files[0].content = 完整元件原始碼;.dependencies = 需要的 npm 套件
```

安裝後元件是專案內的一般檔案,可自由改動 — 需要客製(改 easing、色彩、觸發條件)直接編輯,不必包一層 wrapper。

## 分類總覽

| 分類 | 數量 | 代表元件 |
|------|------|----------|
| 文字動畫 Text Animations | 23 | SplitText, BlurText, DecryptedText, RotatingText, CountUp |
| 動畫效果 Animations | 31 | AnimatedContent, ClickSpark, Magnet, SplashCursor, StarBorder |
| 元件 Components | 40 | Dock, MagicBento, SpotlightCard, TiltedCard, Carousel, Stepper |
| 背景 Backgrounds | 45 | Aurora, Particles, Silk, LightRays, Hyperspeed, Waves |

完整清單與說明:`references/components.md`。

## 注意事項

- 背景類 WebGL 元件(Aurora、Galaxy、LiquidEther 等)是全區塊 canvas,一頁放一個就好;疊多個會吃 GPU 也互相搶焦點。
- 動畫元件多依賴 client-side API — Next.js App Router 下記得 `'use client'`(CLI 裝的檔案通常已含)。
- 尊重 `prefers-reduced-motion`:大面積動態背景與游標特效對部分使用者是干擾,重要內容不要只靠動畫呈現。
