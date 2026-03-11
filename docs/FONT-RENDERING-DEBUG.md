# Font Rendering Debug Guide

**If text looks smeared, blurry, or has a ghosted shadow — read this first.**

This issue has recurred multiple times across Infernode. This document records the root cause, the diagnostic path, and the permanent fix pattern so we never spend time on it again.

---

## The Problem

Text appears smeared, blurry, or doubled — each character has a faint shadow offset by ~1-2 pixels diagonally. The effect is consistent across all text in the affected app.

This happens on **HiDPI / Retina displays** (macOS Retina, any display where SDL3 applies a 2× or greater upscale factor).

---

## Root Cause

**SDL3 bilinearly upscales 1-bit (k1 GREY1) bitmap fonts on HiDPI screens.**

Inferno font files reference *subfont* files. Each subfont has a channel format declared in its binary header:

| Header bytes | Format | Type         | Result on HiDPI         |
|-------------|--------|--------------|------------------------|
| `k1`        | GREY1  | 1-bit bitmap | **SMEARED** by bilinear scaling |
| `k8`        | GREY8  | 8-bit AA     | Renders correctly       |

When an app loads a font that is `k1` (or falls back to the system default `*default*`, which is also `k1`), SDL3's bilinear filter spreads each 1-bit pixel into grey neighbours at 2× scale. The result looks like a drop-shadow smear.

### Known offenders

| Font path | Format | Do NOT use |
|-----------|--------|------------|
| `/fonts/10646/9x15/9x15.font` and subfonts | k1 | Never for displayed text |
| `/fonts/misc/latin1.6x10.font` | k1 | Never for displayed text |
| `/fonts/misc/unicode.6x13.font` | k1 | Never for displayed text |
| `/fonts/vera/Vera/Vera.14.font` | **no ASCII subfont entry** → falls back to default k1 | Do not use |
| `*default*` (system default font) | k1 | Never for displayed text |

### Vera trap

`Vera.14.font` has subfonts only for high Unicode ranges (0xfb01+). The ASCII range (0x0020–0x007E) has **no explicit subfont entry**, so Inferno silently falls back to the system default k1 bitmap for every ASCII character. Vera looks fine on a 1× display and broken on a 2× display.

---

## The Fix

Use k8 (GREY8, 8-bit antialiased) fonts everywhere text is displayed. These render correctly under bilinear upscaling because they are already antialiased.

### Canonical paths

```
/fonts/combined/unicode.sans.14.font   ← proportional (UI text, headings, body)
/fonts/combined/unicode.14.font        ← monospace (code, terminal, pre)
```

These fonts cover the full ASCII range with k8 DejaVu subfonts and cascade to NotoSansCJK and NerdFont for extended Unicode. They are the correct choice for all new UI code.

### Fallback pattern

Always provide a fallback so the app doesn't crash if the path ever changes:

```limbo
f := Font.open(display, "/fonts/combined/unicode.sans.14.font");
if(f == nil)
    f = Font.open(display, "*default*");
```

---

## Diagnosis Checklist

If you see smeared text:

1. **Which font is the app loading?**
   - Search for `Font.open` and font path constants in the source.
   - Check `*default*` usage — that is always k1 bitmap.

2. **Check the subfont header:**
   ```sh
   xxd <subfont-file> | head -3
   ```
   Look for `k1` (bad) or `k8` (good) in the first 16 bytes.

3. **Does the font file cover ASCII (0x20–0x7E)?**
   ```sh
   grep "0x00[2-7]" <font-file>
   ```
   If no ASCII range entry exists, those characters use the k1 default.

4. **Is the font path correct?**
   A nonexistent path causes `Font.open()` to return nil and fall back to the k1 default — silently on non-default fonts. The parser also breaks on `#` comment lines in font manifest files (see below).

---

## Font Parser Comment Bug

`buildfont.c` (the Inferno font parser) does **not** handle `#` comment lines. If a `.font` manifest file contains comment lines, the parser fails with `"bad font format: number expected"` and `Font.open()` returns nil, causing silent fallback to the k1 default bitmap.

**Rule: never add `#` comments to `.font` manifest files.**

---

## Apps Fixed and When

| App | File | Fixed | Note |
|-----|------|-------|------|
| lucifer | `appl/cmd/lucifer.b` | early 2026-03 | acb4bcd5 — wrong Vera-Roman path |
| luciedit | `appl/wm/luciedit.b` | 2026-03 | c5c9568a — switched to combined fonts |
| lucishell | `appl/wm/lucishell.b` | 2026-03 | c5c9568a — switched to combined fonts |
| xenith/acme/pdf/renderers | various | 2026-03 | c5c9568a — switched to combined fonts |
| charon page text | `appl/charon/layout.b` | 2026-03 | fonts array: all sizes → combined |
| charon right-click menu | `appl/charon/gui.b` | 2026-03 | menu init: `*default*` → combined |

---

## Rule for New Code

> **Any Inferno app that draws text on a displayed image MUST use `/fonts/combined/unicode.sans.14.font` or `/fonts/combined/unicode.14.font`.
> Never use `*default*`, 9x15, 6x10, 6x13, or Vera fonts for displayed text.**

If you need a size other than 14pt and no combined font exists for it yet, use 14pt rather than falling back to a k1 bitmap. The size difference is far less jarring than smeared text.
