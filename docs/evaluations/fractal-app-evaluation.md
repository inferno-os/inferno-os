# Fractal App (wm/fractals) — Production Readiness Evaluation

**Date:** 2026-03-22
**Scope:** `appl/wm/fractals.b` (viewer), `appl/veltro/tools/fractal.b` (tool wrapper), tests, docs

## Summary

The fractal app is **production-ready** for its current scope: a Mandelbrot/Julia set browser with AI agent control. The code is clean, well-structured, thoroughly tested, documented, and integrated into the Infernode ecosystem. A few minor gaps exist around error handling and the architectural coupling between the viewer and the Veltro tool, but neither blocks a release.

**Verdict: Ready for production release**, with minor improvements recommended.

---

## Component Inventory

| Component | Path | Lines | Status |
|-----------|------|-------|--------|
| Fractal viewer (GUI) | `appl/wm/fractals.b` | 1208 | Complete |
| Veltro tool wrapper | `appl/veltro/tools/fractal.b` | 188 | Complete |
| Tool tests | `tests/fractal_tool_test.b` | 648 | Comprehensive |
| Load regression test | `tests/wm_apps_test.b` | (shared) | Passing |
| User documentation | `lib/veltro/tools/fractal.txt` | 36 | Complete |
| Interactive demo/tour | `lib/veltro/demos/tour.txt` | (Section 5) | Complete |
| Compiled bytecode | `dis/wm/fractals.dis` | 16.5 KB | Present |
| Compiled tool bytecode | `dis/veltro/tools/fractal.dis` | 3.5 KB | Present |
| Build integration | `appl/wm/mkfile` | listed in TARG | Integrated |

---

## Strengths

### 1. Clean, well-documented code
- Header comments explain provenance (ported from Vita Nuova's `mand.b`, 2000)
- Mouse controls, Veltro IPC protocol, and command format are all documented inline
- ADT design (`Fracpoint`, `Fracrect`, `Params`, `Usercmd`, `Calc`) is clear and idiomatic Limbo

### 2. Solid math foundation
- Fixed-point arithmetic with 60-bit fraction in 64-bit `big` — ~18 decimal digits of precision
- Escape radius and iteration constants are well-chosen (`MAXCOUNT=253`, `MAXDEPTH=20` → max 5060 iterations)
- Boundary-trace fill algorithm (`crawlf`/`crawlt`/`displayset`) is a proper optimization, not a shortcut — traces boundaries of same-colour regions and flood-fills interiors, avoiding per-pixel computation for large solid areas

### 3. Complete GUI implementation
- Draw-only (no Tk dependency) — lightweight and portable
- Three-button mouse interaction: drag-zoom (B1), Julia-at-cursor (B2), context menu (B3)
- Cascading popup menus via `menu.m` with generator pattern for dynamic items
- Statusbar showing mode, Julia parameter, depth, and computation status
- Live theme change listener (`/n/ui/event`)
- Window resize handled correctly with statusbar repositioning

### 4. Comprehensive Veltro integration
- Full bidirectional IPC via `/tmp/veltro/fractal/{ctl,state,view}`
- 10 commands: state, view, zoomin, center, zoomout, julia, mandelbrot, depth, fill, restart
- AI-friendly view description with notable regions and Julia preset descriptions
- Auto-activation in `launch.b` when the app starts
- 500ms tick polling for command consumption — low latency, low overhead

### 5. Thorough test coverage
- `fractal_tool_test.b` (648 lines, 18 test cases) covers:
  - Command dispatch and parsing
  - Ctl file format and roundtrip
  - State file format for both Mandelbrot and Julia modes
  - View description generation
  - Coordinate parsing (zoomin, center, julia)
  - Depth clamping (1–20 range)
  - Fill mode parsing (on/off/1/0)
  - readrmfile read-and-truncate semantics
  - Julia preset data validation
  - boolstr helper
- `wm_apps_test.b` verifies the `.dis` loads without link typecheck errors
- Tests use the project's `testing.m` framework correctly

### 6. Good user documentation
- `lib/veltro/tools/fractal.txt` provides complete command reference with examples
- Notable regions listed (Seahorse valley, Elephant valley, etc.)
- Interactive tour (Section 5 of `tour.txt`) demonstrates the workflow

---

## Issues Found

### Minor — Non-blocking

**1. Polling-based IPC has inherent race window**
The 500ms tick-based polling of `/tmp/veltro/fractal/ctl` means commands can be lost if two are written within the same tick interval. The `readrmfile` function reads once and truncates, so only the last write before a tick is consumed.
- **Impact:** Low. Veltro agents send one command at a time and wait for state changes.
- **Recommendation:** Document this single-command-per-tick constraint in the tool docs. No code change needed.

**2. No input validation on coordinate ranges in the viewer**
`checkctlfile` parses `zoomin` and `julia` coordinates as `real` without bounds checking. Extreme values (e.g., `zoomin 1e308 1e308 1e309 1e309`) could cause degenerate fixed-point arithmetic.
- **Impact:** Low. The fixed-point conversion would overflow, producing garbage rendering, but no crash. A restart command recovers.
- **Recommendation:** Add optional clamping to a reasonable range (e.g., ±4.0) in `checkctlfile`.

**3. Zoom stack is unbounded**
The `stack: list of (Fracrect, Params)` grows indefinitely as the user zooms deeper. Extremely deep zoom sessions (100+ levels) would accumulate significant memory.
- **Impact:** Very low. Users rarely zoom more than 20–30 levels, and each entry is small (~80 bytes).
- **Recommendation:** No action needed. Could add a cap of ~100 levels if desired.

**4. `center` command produces square zoom regions**
`center <re> <im> <radius>` constructs a square `(cx-r, cy-r) → (cx+r, cy+r)`, but the viewer's `correctratio` adjusts this to match the window aspect ratio. This means the actual visible region may be wider or taller than `radius` in one axis.
- **Impact:** Low. The behavior is correct (aspect correction is necessary), but the documentation could note that the visible region may not be exactly `radius` in both dimensions.
- **Recommendation:** Add a brief note to the tool documentation.

**5. Architecture coupling (known issue)**
The Veltro tool only works if the viewer is running. The architecture review (`docs/architecture-review-veltro-unification.md`) already identifies this as a known pattern and proposes a unified `/tool/{name}/` convention (Phase 2–3).
- **Impact:** None for current release. The tool returns clear error messages ("is fractals running?").
- **Recommendation:** No action for this release; tracked in the architecture review.

---

## Checklist

| Criterion | Status | Notes |
|-----------|--------|-------|
| Code compiles | Yes | Listed in `appl/wm/mkfile`, `.dis` present |
| Tests pass | Yes | 18 tests in `fractal_tool_test.b`, load test in `wm_apps_test.b` |
| No security issues | Yes | IPC uses local files only; no network exposure |
| Error handling | Good | Clear error messages with `%r` for system errors |
| Documentation | Complete | Inline comments, tool docs, tour demo |
| Resource cleanup | Good | FDs set to nil after use; process group kill on exit |
| Theme support | Yes | Live theme change listener |
| Window resize | Yes | Canvas and statusbar correctly repositioned |
| Build integration | Yes | In mkfile TARG, auto-activated on launch |
| Concurrency safety | Good | Channel-based synchronization; single-threaded event loop |

---

## Conclusion

The fractal app is a well-implemented, feature-complete Mandelbrot/Julia browser with thoughtful AI integration. The codebase demonstrates good Limbo idioms: ADT-based state management, channel-based concurrency, fixed-point arithmetic for precision, and the boundary-trace fill optimization for performance. Test coverage is thorough, documentation is complete, and the known architectural coupling is already tracked for future improvement. Ship it.
