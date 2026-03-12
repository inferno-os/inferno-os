# Charon HTML5/CSS Gap Analysis for Wikipedia Rendering

## Date: 2026-03-12 (updated)

## Current Capabilities

Charon implements a substantial feature set:

### HTML
- HTML5 semantic elements: article, section, nav, header, footer, aside, main, figure, details, summary, dialog, figcaption, mark, meter, time, output, template, datalist, audio, video, canvas, iframe
- Full table model: table, caption, thead, tbody, tfoot, tr, td, th, col, colgroup
- Forms: form, input (15+ types), select, option, textarea, button, label, fieldset, legend
- ~90 tag types total in `appl/charon/lex.m`

### CSS
- Selectors: element, class, ID, attribute (=, ~=, |=, ^=, $=, *=), pseudo-classes (:hover, :active, :visited, :focus, :first-child, :nth-child(), :nth-of-type(), :not()), pseudo-elements (::before, ::after), combinators (descendant, child, +, ~)
- Specificity calculation (element=1, class/pseudo=10, ID=100)
- Box model: margin, padding, border (width/style/color), width/height, min/max-width, min/max-height, box-sizing
- Text: color, font-family, font-size (keywords + numeric px/em/rem/pt/%), font-style, font-weight, font-variant, text-align, text-decoration (with style/color), text-transform, text-indent, text-overflow, text-shadow, white-space, word-break, word-spacing, letter-spacing, line-height, vertical-align
- Positioning: static, relative, absolute, fixed, sticky, z-index
- Floats: float (left/right/none), clear (left/right/both)
- Display: none, block, inline, inline-block, list-item, table, table-row, table-cell, table-caption, flex, inline-flex, grid, inline-grid
- Flexbox: flex-direction, flex-wrap, justify-content, align-items, align-self, flex-grow, flex-shrink, flex-basis, order, gap
- CSS Grid: grid-template-columns/rows (fr, auto, px, %, repeat()), grid-column-start/end, grid-row-start/end (explicit placement with spanning), grid-gap
- Visual: opacity, border-radius, box-shadow, overflow (with clipping), visibility, outline, cursor
- Multi-column: column-count, column-width, column-gap, column-rule
- Lists: list-style-type, list-style-position
- Tables: border-collapse, border-spacing, empty-cells, table-layout
- Generated content: content (::before/::after) with text and quote values
- CSS Custom Properties: var(--name, fallback) with inheritance, multi-pass resolution, recursion limits
- calc(): full arithmetic (+, -, *, /), nested calc(), decimal numbers, mixed units (px, %, em, rem, pt, vw, vh), context-aware percentage resolution
- Background: background-color, background-image (url()), background-repeat, background-position, background-size (cover, contain, px)
- @media queries: viewport dimensions (min/max-width/height), orientation, prefers-color-scheme, prefers-reduced-motion
- External stylesheet fetching (<link rel="stylesheet">) with @import support

### Wikipedia-Specific
- ~185 lines of hardcoded UA styles for MediaWiki classes
- Vector 2022 chrome hidden (sidebar, tabs, tools, search, CDX components)
- Styles for: wikitable, infobox, navbox, toc, thumb, reflist, hatnote, ambox, sidebar, gallery, catlinks, hlist, plainlist, succession-box, quote-box

## Remaining Gaps (Low Priority)

### 1. Background Image Fetch Integration — MODERATE
Background image rendering infrastructure is complete (drawbgimage with repeat, position, size). The image fetch pipeline needs integration with the async CImage system to actually load `background-image: url(...)` images from the network.

### 2. Font Size Granularity Limitation — LOW
Font sizes map to 5 discrete levels (Tiny/Small/Normal/Large/Verylarge). Numeric CSS values are mapped to the nearest level. True pixel-level font sizing would require loading additional font files at more point sizes.

### 3. No Web Fonts (@font-face) — LOW
Inferno uses bitmap fonts at fixed point sizes. No support for downloading or rendering web fonts.

### 4. Overflow Scrolling — LOW
overflow: hidden clips content correctly. overflow: scroll/auto clips but does not render scrollbars or support scroll interaction. Content that overflows is simply hidden.

### 5. No SVG, WebP, AVIF — LOW
Image format support limited to GIF, JPEG, PNG, XBitmap, and Inferno BIT.

### 6. Transforms and Animations — LOW
CSS transform and transition properties are parsed and stored but not rendered.

## Alternative: Wikipedia REST API

Wikipedia offers pre-rendered HTML via REST API:
```
https://en.wikipedia.org/api/rest_v1/page/html/{title}
```
This HTML is simpler than the full skin and could render better with existing capabilities.
Could add a "simplified view" mode using this endpoint.
