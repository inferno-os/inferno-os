# TODO: Lucipres Presentation Rendering Architecture

## Problem

lucipres has two rendering paths for tab content:

1. **App tabs** (editor, shell, fractal, etc.) — each app gets its own
   wmclient window in lucifer's preswmloop.  Visibility is managed via
   z-order: `showapp()` calls `Client.top()`, `hideapp()` calls
   `Client.bottom()`.

2. **Presentation tabs** (markdown, mermaid, images, PDF, code, etc.) —
   content is drawn directly into lucipres's own window image by
   `drawpresentation()`.

Switching between these two paths requires cross-process synchronization:
lucipres must redraw its content AND lucifer must adjust the app window's
z-order.  A race condition exists because both processes receive the
`"presentation current"` event independently with no ordering guarantee.

A workaround is in place (skip immediate redraw when leaving an app tab,
rely on the event-loop redraw), but the fundamental issue is architectural.

## Proposed Fix

Factor presentation rendering out of lucipres into its own wmclient app
("presrender" or similar).  This app would:

- Own the render registry (xenith/render.b) and all renderer modules
- Handle scroll, zoom, pan, PDF page navigation
- Receive artifact data via 9P (same as apps receive reshape/ctl)
- Participate in the z-stack as a peer to editor/shell/fractal

lucipres would become a thin coordinator: tab bar, event routing, ctl
writes.  All tab switches would use uniform z-order management.

## Scope and Risks

This is a significant refactor.  The following are tightly coupled to the
current architecture and must be carefully migrated:

### Rendering Pipeline
- `drawpresentation()` (~160 lines) — dispatches by artifact type
- Render registry (`appl/xenith/render.b`) — loaded once in lucipres
- Individual renderers: imgrender, mdrender, htmlrender, pdfrender,
  mermaidrender — each with canrender()/render() interface
- `renderartasync()` / `renderdonech` — async render with channel callback
- Back-buffer double buffering (`backbuf` in `redrawpres()`)

### State Management
- Per-artifact state in `Artifact` adt: rendimg, pdfpage, numpages,
  zoom, panx, pany, rendering flag
- Scroll position (prescroll, scrolloff)
- Tab layout and hit testing (tablayout, tabscrolloff)
- PDF page navigation controls (pdfnavprev, pdfnavnext)

### AI Agent Integration
- Veltro creates artifacts via luciuisrv 9P writes
- Artifact types: markdown (most common), mermaid, code, image, PDF,
  table, taskboard, diff, doc
- Apps are launched via `"launch"` ctl command — luciuisrv allocates an
  AppSlot and lucifer's preswmloop manages the window
- The presentation space is the primary output surface for agent work;
  any latency or visual regression will be immediately visible

### Modules Involved
- `appl/cmd/lucipres.b` — current monolith
- `appl/cmd/lucifer.b` — preswmloop, showapp/hideapp, handleprescurrent
- `appl/cmd/luciuisrv.b` — 9P server for presentation artifacts
- `appl/xenith/render.b` — render registry
- `appl/xenith/render/*.b` — individual renderers
- `module/luciui.m` — shared types (Artifact may need changes)

## Workaround in Place

The tab click handler in lucipres.b skips the immediate `redrawpres()`
call when switching away from an app tab, deferring to the event-loop
redraw.  This gives lucifer time to process `hideapp()` before lucipres
redraws.  See the comment in the tab click handler.
