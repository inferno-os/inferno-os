# SonarQube Issue Resolution — Work Log

Last updated: 2026-03-12

Project: `NERVsystems_infernode`

## Summary

Starting count: ~2,787 issues. After batches 1–5: ~2,640 remaining.
Most remaining issues are false positives, architectural complexity in the Go
compiler (godis), FIPS-mandated crypto structure, or Windows NT platform code.

---

## Completed Batches

### Batch 1–2 (initial session)
- Shell test helpers: added `local` vars, explicit `return 0`, stderr redirects
  (S7679, S7682, S7677) in `tests/host/tools9p_integration_test.sh`,
  `tests/host/pathmanage_test.sh`

### Batch 3
- `libsec/mlkem.c`: extracted `nonce++` side effects from function arguments
  (S1121) — 3 loops in `cpapke_keygen`, 3 loops + 1 call in `cpapke_enc`
- `libsec/mldsa.c`: same `nonce++` extraction in 2 loops in
  `mldsa_keygen_internal`
- `libsec/slhdsa_fors.c`: removed unused static `fors_treehash` (S1144)
- `libsec/slhdsa_wots.c`: removed unnecessary `USED(n)` (S1172)
- `libsec/slhdsa.c`: merged nested if-statements in `split_digest` (S1066),
  removed unused parameter `d` from `split_digest` (S1172)

### Batch 4
- `emu/Nt/os.c`: replaced nested ternary with if/else (S3358), added
  `const` to pointer variables (S5350)
- `emu/port/devssl.c`: changed `uchar *db` to `const uchar *db` (S5350)
- `libkeyring/slhdsaalg.c`: changed `char *ep` to `const char *ep` in
  `sk2str`, `pk2str`, `sig2str` (S5350)

### Batch 5
- `formal-verification/spin/verify-all.sh`: added explicit `return 0` to
  3 functions (S7682)
- `tools/godis/testdata/bench/run_bench.sh`: added explicit `return 0` to
  `run_bench` (S7682)
- `tests/host/llmsrv_tooluse_test.sh`: added default `*)` case to case
  statement at line 350 (S131)
- `formal-verification/cbmc/stubs.h`: suppressed unused parameter `msg` in
  `error()` stub with `(void)msg` (S1172)

---

## False Positives — Mark in SonarQube UI

These should NOT be fixed in code. Mark as "Won't Fix" or "False Positive"
in SonarQube.

### CBMC Formal Verification — S836 (garbage value), S2259 (null deref)
~20+ instances in `formal-verification/cbmc/harness_*.c` and `stubs.h`.
CBMC harnesses intentionally use unconstrained symbolic values — that's how
formal verification works. Null pointer derefs in harnesses are intentional
test paths.

### emu/Nt/os.c:84 — S2259 (null pointer deref)
SonarQube claims "Access to field 'user' results in a dereference of a null
pointer (loaded from variable 'e')" but `e->user` (line 82) is inside an
`if(e != nil)` guard (line 77). Line 84 (`free(p->prog)`) doesn't use `e`.
This is a false positive.

### S125 (commented-out code) in crypto files
FIPS algorithm documentation in comments uses mathematical notation
(`=`, `+`, `||`, `*`) that SonarQube misidentifies as commented-out C code.
These are specification references required for audit/review.

### S1905 (redundant cast) in libsec/aesgcm.c
~30 instances of casts like `(u64int)naad*8`. These are NOT redundant —
`ulong` is 32-bit on some Inferno platforms. Without the cast, the
multiplication overflows on 32-bit targets. Required for portability.

### S5955 (declare loop variable in for) / S1659 (separate declarations)
Plan 9 / Inferno uses C89 style: all variables declared at the top of the
block (`int i, j;`). This is a project-wide convention, not a bug.

### S924 (goto nesting) — waserror/nexterror
Inferno's `waserror()`/`nexterror()` is a longjmp-based error handling
pattern inherited from Plan 9. SonarQube sees `goto`-like control flow and
flags nesting. This is the kernel's error model — do not refactor.

### xec.c — S2681 (conditional execution)
6 instances caused by macro expansion patterns in the Dis VM interpreter.
The macros expand to multiple statements that look like unbraced
conditionals. False positive.

### keyring.c — S824 (block scope declaration)
Plan 9 C idiom. Not a bug.

### vlrt.c — S3687 (volatile)
Windows NT kernel pattern. Leave for Windows session.

### win.c / comp-amd64.c — S836 (garbage value)
Windows platform code and JIT compiler patterns. Not actual bugs.

---

## Remaining Issues — Not Actionable Without Major Refactoring

### S3776 (cognitive complexity) / S134 (deep nesting)

These are the bulk of remaining HIGH issues. Refactoring would be high-risk
and low-value.

| File | Lines | Complexity | Notes |
|------|-------|-----------|-------|
| `libinterp/load.c:138` | — | 181 vs 25 | Dis module loader, core kernel |
| `emu/port/draw-sdl3.c:982` | — | 117 vs 25 | SDL3 draw backend |
| `emu/port/draw-sdl3.c:555` | — | 71 vs 25 | SDL3 draw backend |
| `emu/Hp/devaudio.c:350` | — | 106 vs 25 | HP-UX audio driver |
| `fonts/dejavu/ttf2subfont.c:63` | — | 102 vs 25 | Font conversion tool |
| `libsec/mldsa.c:297` | — | 76 vs 25 | FIPS 204 (ML-DSA), spec-aligned |
| `emu/port/devcmd.c:438` | — | 49 vs 25 | Command device |
| `libinterp/comp-arm64.c:2550` | — | 44 vs 25 | ARM64 JIT compiler |
| `libinterp/comp-amd64.c:2624` | — | 37 vs 25 | AMD64 JIT compiler |
| `emu/Nt/win.c:199` | — | 26 vs 25 | Windows GUI (fix in Windows session) |
| `libsec/mldsa.c:561` | — | 28 vs 25 | FIPS 204 (ML-DSA) |
| `libsec/mldsa_poly.c:165` | — | 26 vs 25 | FIPS 204 polynomial ops |
| `libsec/mlkem_poly.c:162` | — | 27 vs 25 | FIPS 203 polynomial ops |
| `tools/godis/compiler/*.go` | many | 15–115 | Go-to-Dis compiler, ~40 functions |

**Crypto (mldsa, mlkem, slhdsa):** Function structure follows FIPS 203/204/205
algorithm numbering. Splitting functions would break correspondence with the
spec, making audit harder.

**Kernel/JIT (load.c, comp-*.c):** These are switch-heavy instruction
dispatch functions. Refactoring would risk correctness in critical code paths.

**godis compiler:** The Go-to-Dis compiler has ~40 functions exceeding the
complexity threshold. These are large switch/case lowering functions — each
case handles a different Go stdlib function or SSA instruction. Refactoring
into smaller pieces is possible but would be a multi-day effort.

### S1871 (duplicate branches) — tools/godis/compiler/lower_stubs.go
~70 instances. Switch cases have identical bodies because each case stubs a
semantically different Go stdlib function with the same placeholder
implementation (e.g., `IMOVW(0)`). This is intentional — the cases must
remain separate for when real implementations are added.

### S1192 (duplicate string literals) — tools/godis/compiler/compiler_test.go
Test code reuses format strings like `"compile: %v"` and `"encode: %v"`.
Extracting constants would reduce readability in test code. Low value.

### S107 (too many parameters) — crypto functions
FIPS spec alignment requires these function signatures. The parameters map
directly to algorithm inputs defined in NIST standards.

---

## Windows NT Issues — Defer to Windows Session

These files are Windows-only (`emu/Nt/`) and should be fixed and tested on
a Windows build environment:

| File | Rule | Issue |
|------|------|-------|
| `emu/Nt/vlrt.c:190` | S3518 | Division by zero |
| `emu/Nt/vlrt.c:537` | S1767 | Pointer truncation (integral type too small) |
| `emu/Nt/win.c:199` | S3776 | Cognitive complexity 26 vs 25 (borderline) |
| `emu/Nt/vlrt.c` | S3687 | Volatile usage (Windows NT kernel pattern) |
| `emu/Nt/os.c:84` | S2259 | False positive (mark in UI) |

---

## How to Continue This Work

### Environment setup
```sh
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH
```

### Build verification after C changes
```sh
# libsec
cd $ROOT/libsec && mk install

# emu
cd $ROOT/emu && mk install

# libkeyring
cd $ROOT/libkeyring && mk install
```

### Query SonarQube for remaining issues
Use the MCP tool `search_sonar_issues_in_projects` with:
- `projects: ["NERVsystems_infernode"]`
- `issueStatuses: ["OPEN"]`
- `severities: ["HIGH"]` or `["MEDIUM"]`
- Page through with `p: 1`, `p: 2`, etc.

### Rules to focus on (actionable)
- **S7682** — missing explicit return in shell functions
- **S7679** — positional parameters without `local`
- **S7677** — error messages not redirected to stderr
- **S131** — missing default case in switch/case
- **S1121** — assignment used as expression (side effects in args)
- **S1066** — collapsible nested if statements
- **S1144** — unused private functions
- **S1172** — unused function parameters
- **S5350** — pointer-to-const opportunities
- **S3358** — nested ternary operators

### Rules that are mostly false positives (skip or mark)
- **S836** — garbage values (CBMC harnesses)
- **S2259** — null pointer deref (CBMC harnesses, false analysis)
- **S125** — commented-out code (FIPS spec references)
- **S1905** — redundant cast (32-bit portability)
- **S5955** — loop variable declaration (C89 convention)
- **S1659** — separate declarations (C89 convention)
- **S924** — goto nesting (waserror/nexterror pattern)
- **S2681** — conditional execution (macro expansion)
- **S107** — too many parameters (FIPS signatures)
- **S1871** — duplicate branches (stub pattern)
- **S3776/S134** — complexity/nesting (architectural)
