# Charon HTML5/CSS Gap Analysis for Wikipedia Rendering

## Date: 2026-03-11

## Current Capabilities

Charon implements a substantial feature set:

### HTML
- HTML5 semantic elements: article, section, nav, header, footer, aside, main, figure, details, summary, dialog, figcaption, mark, meter, time, output, template, datalist, audio, video, canvas, iframe
- Full table model: table, caption, thead, tbody, tfoot, tr, td, th, col, colgroup
- Forms: form, input, select, option, textarea, button, label, fieldset, legend
- ~90 tag types total in `appl/charon/lex.m`

### CSS
- Selectors: element, class, ID, attribute (=, ~=, |=, ^=, $=, *=), pseudo-classes (:hover, :active, :visited, :focus, :first-child, :nth-child(), :nth-of-type(), :not()), pseudo-elements (::before, ::after), combinators (descendant, child, +, ~)
- Specificity calculation (element=1, class/pseudo=10, ID=100)
- Box model: margin, padding, border (width/style/color), width/height, min/max-width, min/max-height, box-sizing
- Text: color, font-family, font-size, font-style, font-weight, font-variant, text-align, text-decoration (with style/color), text-transform, text-indent, text-overflow, text-shadow, white-space, word-break, word-spacing, letter-spacing, line-height, vertical-align
- Positioning: static, relative, absolute, fixed, z-index
- Floats: float (left/right/none), clear (left/right/both)
- Display: none, block, inline, inline-block, list-item, table, table-row, table-cell, table-caption, flex, inline-flex
- Flexbox: flex-direction, flex-wrap, justify-content, align-items, align-self, flex-grow, flex-shrink, flex-basis, order, gap
- Visual: opacity, border-radius, box-shadow, overflow, visibility, outline, cursor
- Multi-column: column-count, column-width, column-gap, column-rule
- Lists: list-style-type, list-style-position
- Tables: border-collapse, border-spacing, empty-cells, table-layout
- Generated content: content (::before/::after)
- calc() - basic form only
- External stylesheet fetching (<link rel="stylesheet">) with @import support
- @media filtering (screen vs print)

### Wikipedia-Specific
- ~180 lines of hardcoded UA styles for MediaWiki classes
- Vector 2022 chrome hidden (sidebar, tabs, tools, search)
- Styles for: wikitable, infobox, navbox, toc, thumb, reflist, hatnote, ambox, sidebar, gallery, catlinks, hlist, plainlist

## Critical Gaps (Ranked by Impact on Wikipedia)

### 1. CSS Custom Properties (`var(--name)`) — CRITICAL
Wikipedia Vector 2022 uses hundreds of custom properties for all colors, sizes, spacing.
Without var() support, most CSS values resolve to nothing.
- Location to implement: `appl/charon/build.b` (property storage + var() substitution during applycssprop)

### 2. CSS Grid Layout — CRITICAL
Vector 2022 uses grid for page-level layout (sidebar + content + tools).
Charon has flexbox but no grid.
- A subset covering `grid-template-columns` with `fr` units would cover most Wikipedia needs.

### 3. Background Images via CSS — HIGH
No `background-image: url(...)` from CSS. Only works via HTML background attribute.
Wikipedia uses for icons, visual indicators, section dividers.

### 4. calc() Enhancement — HIGH
Current calc() only handles simple `100px - 20px`. Wikipedia uses nested calc(), percentage+pixel mixing, calc(var(...)).

### 5. @media Query Conditions — MODERATE
Currently filters screen vs print only. No support for `(max-width: 720px)` responsive breakpoints.

### 6. Font Size Precision — MODERATE
Only 5 discrete sizes. CSS pixel/em/rem sizes can't map precisely.
No @font-face / web fonts.

### 7. Overflow Scrolling — MODERATE
overflow property stored but scrollable containers not implemented.

### 8. ::before/::after Full Integration — MODERATE
Content strings stored in ComputedStyle but layout integration unclear.

### 9. position: sticky — LOW
Used for sticky headers. Falls back to static acceptably.

## Recommended Implementation Order

1. CSS Custom Properties (var()) — highest impact single fix
2. @media query width/height evaluation
3. Background images via CSS properties
4. CSS Grid subset (grid-template-columns, fr units)
5. Improved calc() (nested, percentage+pixel)
6. Overflow scrollable containers
7. Font size granularity
8. ::before/::after layout integration

## Alternative: Wikipedia REST API

Wikipedia offers pre-rendered HTML via REST API:
```
https://en.wikipedia.org/api/rest_v1/page/html/{title}
```
This HTML is simpler than the full skin and could render better with existing capabilities.
Could add a "simplified view" mode using this endpoint.
