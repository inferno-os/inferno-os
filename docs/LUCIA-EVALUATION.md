# Lucifer GUI - Production Release Evaluation

**Date:** 2026-03-22
**Scope:** Full evaluation of Lucifer GUI and all subsystems for production readiness.
**Components evaluated:** lucifer.b, luciconv.b, lucictx.b, lucipres.b, luciuisrv.b, lucibridge.b, lucitheme.b/m, launch scripts, theme system, test suite.

---

## Executive Summary

Lucifer is a well-architected three-zone tiling GUI (~10,000 lines of Limbo) with solid 9P-based state management, comprehensive test coverage for the UI server, and a clean theme system. The codebase is clean of unresolved TODO markers (only 2 found in lucifer.b) and demonstrates strong Inferno/Limbo patterns throughout.

**Overall assessment: Near production-ready with targeted fixes needed.**

The issues found fall into three tiers:
- **P0 (Must fix):** 7 crash/data-loss bugs
- **P1 (Should fix):** 13 reliability and correctness issues
- **P2 (Nice to have):** 9 cleanup, consistency, and hardening categories

---

## P0 - Must Fix Before Release

### 1. Nil dereference crash on Lucitheme load failure

**Affected files:** `lucifer.b:327-328`, `luciconv.b:132-133`, `lucictx.b:206-207`

Three of the four zone modules load `Lucitheme` without a nil check before calling `gettheme()`. If the module fails to load (corrupted .dis, missing file, memory pressure), the zone crashes immediately.

`lucipres.b` correctly handles this (line 200-203). The other three should follow the same pattern.

**Fix:** Add nil check after `load Lucitheme` in lucifer.b, luciconv.b, and lucictx.b, falling back to hardcoded defaults or aborting gracefully.

### 2. Crashed-app slot leak exhausts MAXAPPSLOTS (lucifer.b)

**File:** `lucifer.b:1838-1841, 1956-1958`

When a GUI app crashes (no orderly exit), its `AppSlot` entry lingers with `client != nil` but a dead goroutine. There is no watchdog to reclaim dead slots. Once all 16 slots are consumed, no new apps can launch -- and the overflow path (line 1838-1841) still spawns the app without a slot, creating an untrackable resource leak.

**Fix:** Implement the watchdog described in the TODO at line 1956 -- periodically check if `client.ctl` is closed to detect dead apps and reclaim their slots. Also, when `nappslots >= MAXAPPSLOTS`, do NOT spawn the app; return an error to the user.

### 3. Goroutine + FD leak on voice timeout (luciconv.b)

**File:** `luciconv.b:816, 826-828, 841`

On voice recording timeout, `voiceworker` sets `fd = nil` but `voiceread` still holds its own reference and remains blocked on `sys->read()` indefinitely. After timeout, `voiceread` also blocks forever trying to send on `resultch` (nobody listening). Both the goroutine and the FD leak permanently.

**Fix:** Close the FD explicitly (`fd = nil` is insufficient) or use an alternate cancellation mechanism. Consider a parallel timeout goroutine that closes the FD to unblock the read.

### 4. Font nil dereference paths (lucifer.b)

**File:** `lucifer.b:340-345, 626, 683-686, 834-835, 890, 910-911`

If both font open attempts fail, `mainfont` remains nil. While `drawchrome` checks (line 590), many other code paths use `mainfont.height` and `mainfont.width` without nil guards, causing crashes on systems where fonts are missing or the font path is wrong.

**Fix:** Make font loading fatal (abort with clear error) or guard all `mainfont` uses.

### 5. Screen/Image allocation failures during resize (lucifer.b)

**File:** `lucifer.b:1047-1052`

`handleresize()` calls `Screen.allocate` and `newwindow` with no nil checks. If any allocation fails during a resize (e.g., display disconnect, memory pressure), subsequent draw operations crash.

**Fix:** Add nil checks after each allocation in `handleresize()`. If allocation fails, skip the redraw and retry on next resize event.

### 6. Unbounded data growth in luciuisrv (luciuisrv.b)

**File:** `luciuisrv.b:239-241, 1337`

`notifyq` and `toastq` queues have no size limit -- a misbehaving client can grow them without bound. Additionally, repeated `append` commands to `art.data` bypass `MAX_DATA_SIZE`, allowing unbounded artifact data growth.

**Fix:** Cap queue sizes and enforce `MAX_DATA_SIZE` on cumulative appends.

### 7. UTF-8 truncation of system prompt (lucibridge.b:272-280)

**File:** `lucibridge.b:272-280`

The system prompt is truncated by byte count (`basebytes[0:room]`), which can cut a multi-byte UTF-8 sequence in half, producing an invalid string that the LLM service may reject.

**Fix:** Truncate at a UTF-8 character boundary (find the last valid codepoint start before the limit).

---

## P1 - Should Fix for Production Quality

### 8. Race conditions on shared mutable state (lucifer.b, lucictx.b)

**lucifer.b:** `tiles[]`/`ntiles` are written by the main loop and read by `tileblinker()` (line 1330) and `mouseproc()` (lines 1446-1468) without synchronization. If `loadtiles()` reallocates the array while `tileblinker` iterates, freed memory could be read.

**lucictx.b:** Timer goroutine (lines 509-568) reads `nsmanifest`, `resources`, `lastpathsraw`, `lasttoolsraw` while the main loop writes them. String assignment is atomic, but list/array assignment may not be.

**Fix:** Use channel-based communication or protect shared state with a lock adt.

### 9. Network FD leak on mount failure (lucictx.b:1645-1652)

When `sys->dial()` succeeds but `sys->mount()` fails, `conn.dfd` is never closed, leaking a network connection.

**Fix:** Close `conn.dfd` in the mount failure path.

### 10. Drawing function mutates global state (lucictx.b:918)

`drawcontext()` sorts `activetoolset` as a side effect of rendering. Drawing should be purely visual -- state mutation belongs in the event/data layer.

**Fix:** Move the sort to the data loading path (`loadcontext` or tool change handler).

### 11. Timer/draw timeout inconsistency (lucictx.b:559 vs 955)

The timer uses 4000ms to decide whether to tick, but the draw code uses 3000ms for activity accent color. This creates a 1-second window where the timer fires but produces no visual change.

**Fix:** Unify the two constants to the same value.

### 12. `VOICE_PROC` state is dead UI code (luciconv.b:100, 445-447)

The `VOICE_PROC` constant is defined and the drawing code renders a "processing" indicator for it, but no code path ever sets `voicestate = VOICE_PROC`. The state transitions directly from `VOICE_REC` to `VOICE_IDLE`.

**Fix:** Either wire up `VOICE_PROC` in the voice worker flow or remove the dead state and its rendering code.

### 13. Tile scroll unbounded to the right (lucifer.b:1478)

Scroll-left is bounded at 0, but scroll-right has no upper bound. Users can scroll tiles infinitely rightward past all content with no visual feedback.

**Fix:** Cap `tilescrollx` at `max(0, total_tile_width - visible_width)`.

### 14. strtoint overflow at INT_MAX boundary (luciconv.b:1059, lucictx.b:2100)

The overflow check `n > 214748364` misses the case where `n == 214748364` and the next digit is > 7, silently overflowing to a negative number.

**Fix:** Add boundary digit check: `if(n == 214748364 && d > 7) return -1;`

### 15. Silent message drop at MAX_MESSAGES (luciuisrv.b:1261)

`addmessage` return value is ignored in `convctl` -- silently drops messages when `MAX_MESSAGES` is reached. The client receives no error indication.

**Fix:** Check return value and return an error to the client.

### 16. Deleted activities never freed (luciuisrv.b:1212)

Deleted activities are removed from the activity list but their data structures (messages, artifacts, resources) are never reclaimed. Long-running sessions accumulate orphaned memory.

**Fix:** Nil out internal references when deleting an activity.

### 17. Global event loss (luciuisrv.b:569-588)

`pushglobalevent` silently drops events if no reader is waiting, unlike per-activity events which buffer. A slow global event consumer misses state changes.

**Fix:** Buffer global events symmetrically with per-activity events.

### 18. Linux launch script argument parsing broken (run-lucifer-linux.sh)

`shift` inside a `for arg in "$@"` loop doesn't work in POSIX shell -- the `for` loop iterates over the original snapshot of `$@`. The `-g` geometry flag may not parse correctly.

**Fix:** Use a `while [ $# -gt 0 ]` loop with explicit `shift`.

### 19. Linux launch script forces theme on every start (run-lucifer-linux.sh:45)

`echo brimstone > "$ROOT/lib/lucifer/theme/current"` overwrites user theme preference on every launch. Neither macOS nor Windows scripts do this.

**Fix:** Only write the default if the `current` file doesn't exist.

### 20. Windows launcher missing `-l` flag (run-lucifer.ps1:28)

The Windows emulator is invoked with `sh` instead of `sh -l`, so the Inferno login profile is never sourced. This skips LLM configuration, factotum setup, and other profile-based initialization that macOS/Linux get.

**Fix:** Add `-l` flag to the `sh` invocation.

---

## P2 - Nice to Have / Cleanup

### 21. Dead code across modules

| File | Dead code | Lines |
|------|-----------|-------|
| luciconv.b | `listlen()` function never called | 1071-1077 |
| luciconv.b | `bufio.m` included but never used | 17 |
| luciconv.b | `ConvMsg.using` field stored but never displayed | 42 |
| lucictx.b | `Gap` ADT loaded/parsed but never rendered | 55-58, 114, 1449-1463 |
| lucictx.b | `catalog` loaded but never rendered | 117, 1551-1573 |
| lucictx.b | `ctxentryrects`/`nctxentryrects` allocated but never used | 158-159 |
| lucictx.b | `ALLOWED_DIS_PREFIXES` constant unused (duplicate list on 1801) | 1793 |
| lucictx.b | `revstrlist()` never called | 2148-2154 |
| lucibridge.b | `cleanresponse` + `extractsay` (74 lines dead) | 344-420 |
| lucibridge.b | `speaktext()` defined but never called | 195 |
| lucipres.b | `parseattrs`/`getattr`/`Attr` fully implemented, never called | 1904-1970 |
| lucipres.b | `plumbmod` loaded but never used | 276-280 |

### 22. Duplicated code patterns

- **Header height `40`** appears 4 times in lucifer.b (lines 503, 587, 704, 1437). Should be a `con`.
- **Zone width calculations** duplicated between `drawchrome()` and `zonerects()`.
- **`writefile()`/`writetofile()`** in lucifer.b do the same thing with slightly different signatures.
- **Logo loading code** duplicated between `init()` and `reloadlogo()` in lucifer.b.
- **`readfile()`** reimplemented in 3+ test files instead of importing from a shared module.
- **List reversal functions** (`revres`, `revgaps`, `revbg`, `revcat`, `revstrlist`) duplicated in lucictx.b.

### 23. Debug logging in production

`lucictx.b:2082-2083` logs every write to `/edit/ctl` at stderr. Should be gated behind a verbose flag.

### 24. Hardcoded array limits

| File | Limit | Risk |
|------|-------|------|
| lucictx.b | 64-entry NS/tool rect arrays | Silent truncation with large namespaces |
| lucictx.b | 512-entry file browser array | Silent truncation for large directories |
| lucifer.b | 16 app slots (MAXAPPSLOTS) | Hard limit, no error on overflow |
| lucifer.b | 16 token pending slots | Silent drop on overflow |

### 25. `sleep 1` synchronization in launch scripts

All three launch scripts (macOS, Linux, Windows) use `sleep 1` between starting services and using them. This is fragile on slow machines. Consider a readiness-check loop or a readiness file/signal.

### 26. Cross-platform tool set inconsistency

| Feature | macOS | Linux | Windows |
|---------|-------|-------|---------|
| speech9p | Yes | No | No |
| say/hear tools | Yes | Yes | No |
| exec/git/mail | Yes | No | No |
| shell/charon | Yes | Yes | No |
| JIT mode | -c1 | -c0 | -c1 |

Windows has significantly fewer tools. Linux disables JIT even on amd64 where it works.

### 27. Theme system edge cases

- `parsehex()` has zero test coverage -- malformed hex in theme files produces silent wrong colors.
- Theme files > 4096 bytes are silently truncated.
- Unknown keys in theme files are silently ignored (typos go undetected).
- Brimstone defaults use positional struct construction for 49+ fields -- fragile if fields are added.
- No `selection`, `link`, `scrollbar`, or `tooltip` theme colors.

### 28. Test coverage gaps

**Strong areas:**
- `luciuisrv_test.b`: 26 tests exercising the full 9P server -- excellent.
- `lucifer_helpers_test.b`: 48 tests for shared helpers -- solid.
- `lucifer_flicker_test.b`: Good boundary-value testing of timer predicate.
- `lucibridge_test.b`: 11 pure-function tests with edge cases.

**Gaps:**
- No tests for theme file loading from disk (only tests brimstone defaults).
- `parsehex()` completely untested.
- `lucifer_winstart_test.b` `run()` missing exception handler -- a crash aborts the entire test suite.
- Flicker test duplicates `needstick()` logic from lucifer.b -- tests stale copy if production diverges.
- No integration test for zone resize / window management.
- No test for activity deletion.
- No test for concurrent readers/writers on luciuisrv.
- Alpha invariant check covers only 5 of 49 theme fields.

### 29. Lucipres-specific issues

- **Async render race condition** (`lucipres.b:762`): `renderartasync` is spawned as a goroutine and accesses module-level globals (`rendermod`, `rlay`, `pdfmod`, color images). A theme change via `reloadcolors` could nil out or replace these mid-render.
- **`drainprogress` goroutine leak** (`lucipres.b:1302`): A new goroutine is spawned on every `renderart` call. If the renderer never closes the progress channel, the goroutine blocks forever.
- **PDF document leak on exception** (`lucipres.b:1760`): If `doc.renderpage` raises, `doc.close()` is never called.
- **O(n^2) `readfilebytes`** (`lucipres.b:2001-2020`): Repeated array allocation and copy for large files.
- **Empty `"activity "` event handler** (`lucipres.b:501-504`): Comment says "redraw taskboard" but handler returns without action -- taskboard shows stale data until next unrelated redraw.
- **Silent event drops** (`lucipres.b:486`): Buffered channel (size 8) with `alt` default silently drops events when full during rapid artifact updates.
- **Dead code**: `parseattrs`/`getattr`/`Attr` (lines 1904-1970) fully implemented but never called; `plumbmod` loaded but never used.
- **Export hardcodes `.b` extension** for code artifacts (`lucipres.b:1117`) -- assumes Limbo source for all code types.

---

## Architecture Strengths

The evaluation also revealed several noteworthy strengths:

1. **Clean 9P separation** -- All UI state lives in `luciuisrv` as a synthetic filesystem. Renderers are pure views. This enables headless testing, remote operation, and clean state inspection.

2. **Proper channel-based event routing** -- The main event loop in each zone uses `alt` on well-defined channels, keeping concurrency manageable.

3. **Theme system** -- Two complete themes (brimstone, halo) with 65 color properties and live reload capability.

4. **Double-buffered rendering** -- All zones attempt off-screen rendering with graceful fallback.

5. **Comprehensive documentation** -- Architecture, testing, and operational docs are thorough.

6. **No TODO/FIXME debt** -- Only 2 TODO comments found across ~10,000 lines (both in lucifer.b), and both describe real planned features rather than shortcuts.

---

## Recommended Priority Order

1. Fix P0 items 1-7 (crash/leak/data-loss bugs)
2. Fix P1 items 8-9, 15-20 (races, leaks, broken scripts, silent data loss)
3. Fix P1 items 10-14 (correctness/UX)
4. Address P2 items as time permits
5. Expand test coverage for theme loading and parsehex
