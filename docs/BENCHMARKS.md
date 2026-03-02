# InferNode Performance Benchmarks

## Test Platforms

| Platform | CPU | Cores | RAM | OS |
|----------|-----|-------|-----|-----|
| **AMD64 Linux** | AMD Ryzen 7 H 255 | 16 | 21 GB | Linux 6.14.0 (x86_64) |
| **ARM64 macOS** | Apple M4 | 10 (4P+6E) | 32 GB | macOS 15.4 (Darwin 24.6.0) |
| **ARM64 Linux** | ARM Cortex-A78AE | 12 | 64 GB | Linux 5.15.148-tegra (Jetson AGX Orin) |

## JIT Compiler Performance

Both AMD64 and ARM64 JIT compilers translate Dis VM bytecode to native machine code at module load time. The AMD64 JIT (`comp-amd64.c`) targets x86-64 with System V ABI. The ARM64 JIT (`comp-arm64.c`) targets ARMv8-A with AAPCS64 ABI. On macOS, JIT code buffers use `mmap(MAP_JIT)` with `pthread_jit_write_protect_np()` for W^X compliance; Linux uses `mmap(MAP_ANON)`.

### Cross-Platform Summary

Two benchmark suites measure JIT speedup: **v1** (6 compute-intensive benchmarks) and **v2** (26 benchmarks across 9 categories including function calls and list operations which have lower JIT gains).

| Platform | v1 Interp | v1 JIT | v1 Speedup | v2 Interp | v2 JIT | v2 Speedup |
|----------|-----------|--------|------------|-----------|--------|------------|
| AMD64 Linux | 21,255 ms | 1,500 ms | **14.2x** | 1,504 ms | 263 ms | **5.7x** |
| ARM64 macOS | 16,697 ms | 1,735 ms | **9.6x** | 1,086 ms | 413 ms | **2.6x** |
| ARM64 Linux | 38,320 ms | 4,615 ms | **8.3x** | 2,743 ms | 938 ms | **2.9x** |

The AMD64 JIT achieves the highest speedup ratios (14.2x on v1) due to efficient x86-64 instruction encoding for the Dis VM's register-based bytecode. In absolute terms, AMD64 and Apple M4 JIT performance are comparable (1,500 ms vs 1,735 ms on v1) despite different architectures. The Jetson Cortex-A78AE is roughly 2.5x slower in absolute terms but achieves similar JIT-over-interpreter ratios, confirming the ARM64 JIT generates efficient code on both microarchitectures.

The v1-to-v2 speedup reduction reflects benchmark composition: v2 includes function calls (recursive Fibonacci, mutual recursion) where the JIT must still pay runtime overhead for frame allocation, type checking, and garbage collector interaction. v1 is dominated by tight loops where eliminating interpreter dispatch yields the greatest gains.

### v1 Per-Benchmark Results (best-of-3)

| Benchmark | AMD64 JIT | AMD64 Interp | Speedup | M4 JIT | M4 Interp | Speedup | Jetson JIT | Jetson Interp | Speedup |
|-----------|-----------|-------------|---------|--------|-----------|---------|------------|---------------|---------|
| Integer Arithmetic | 23 ms | 466 ms | 20.3x | 29 ms | 354 ms | 12.2x | 119 ms | 856 ms | 7.2x |
| Array Access | 1,131 ms | 18,284 ms | 16.2x | 1,317 ms | 14,496 ms | 11.0x | 3,666 ms | 33,708 ms | 9.2x |
| Function Calls | 1 ms | 20 ms | 20.0x | 1 ms | 18 ms | 18.0x | 4 ms | 38 ms | 9.5x |
| Fibonacci | 243 ms | 777 ms | 3.2x | 220 ms | 786 ms | 3.6x | 633 ms | 1,671 ms | 2.6x |
| Sieve | 5 ms | 74 ms | 14.8x | 5 ms | 51 ms | 10.2x | 16 ms | 136 ms | 8.5x |
| Nested Loops | 65 ms | 1,152 ms | 17.7x | 54 ms | 990 ms | 18.3x | 169 ms | 1,911 ms | 11.3x |

Fibonacci shows the lowest speedup across all platforms (2.6-3.6x) because recursive function calls involve frame allocation, module pointer validation, and type checking at each call site — operations the JIT cannot eliminate.

### v2 Category Aggregates (AMD64 Linux, best-of-3)

| Category | JIT (ms) | Interp (ms) | Speedup |
|----------|----------|-------------|---------|
| Branch & Control | 2 | 72 | 36.0x |
| Memory Access | 5 | 111 | 22.2x |
| Integer ALU | 10 | 139 | 13.9x |
| Mixed Workloads | 25 | 382 | 15.3x |
| Byte Ops | 7 | 88 | 12.6x |
| Type Conversions | 6 | 51 | 8.5x |
| Big (64-bit) | 18 | 135 | 7.5x |
| List Ops | 4 | 23 | 5.8x |
| Function Calls | 164 | 455 | 2.8x |

Branch and control flow operations see the largest speedup (36x) because the interpreter's dispatch loop overhead is most pronounced for simple, fast instructions. Function calls remain the bottleneck (2.8x) due to non-eliminable runtime overhead.

## Cross-Language Comparison

Six benchmarks (Integer Arithmetic, Array Access, Function Calls, Fibonacci, Sieve, Nested Loops) ported to C, Go, Java, Python, and Limbo with matched parameters and 64-bit integer types.

### ARM64 macOS (Apple M4, best-of-3)

| Benchmark | C -O2 | C -O0 | Go | Java | Limbo JIT | Limbo Interp | Python |
|-----------|-------|-------|-----|------|-----------|-------------|--------|
| Integer Arithmetic | 10 ms | 44 ms | 14 ms | 11 ms | 25 ms | 279 ms | 2,882 ms |
| Array Access | 70 ms | 567 ms | 263 ms | 252 ms | 1,039 ms | 10,208 ms | 10,382 ms |
| Function Calls | 0 ms | 1 ms | 0 ms | 0 ms | 1 ms | 13 ms | 60 ms |
| Fibonacci | 0 ms | 28 ms | 16 ms | 9 ms | 210 ms | 615 ms | 554 ms |
| Sieve | 1 ms | 4 ms | 2 ms | 1 ms | 5 ms | 45 ms | 24 ms |
| Nested Loops | 0 ms | 32 ms | 15 ms | 14 ms | 51 ms | 717 ms | 1,136 ms |
| **Total** | **81 ms** | **676 ms** | **310 ms** | **292 ms** | **1,331 ms** | **11,877 ms** | **15,038 ms** |

### ARM64 Linux (Jetson AGX Orin, best-of-3)

No Java toolchain on this platform.

| Benchmark | C -O2 | C -O0 | Go | Python 3.12 | Limbo JIT | Limbo Interp |
|-----------|-------|-------|-----|-------------|-----------|-------------|
| Integer Arithmetic | 39 ms | 105 ms | 40 ms | 9,379 ms | 122 ms | 856 ms |
| Array Access | 518 ms | 2,892 ms | 523 ms | 39,996 ms | 3,655 ms | 33,259 ms |
| Function Calls | 0 ms | 3 ms | 1 ms | 163 ms | 5 ms | 38 ms |
| Fibonacci | 26 ms | 49 ms | 36 ms | 1,522 ms | 627 ms | 1,710 ms |
| Sieve | 5 ms | 13 ms | 4 ms | 74 ms | 16 ms | 136 ms |
| Nested Loops | 0 ms | 136 ms | 32 ms | 4,317 ms | 169 ms | 1,887 ms |
| **Total** | **588 ms** | **3,198 ms** | **637 ms** | **55,451 ms** | **4,594 ms** | **37,886 ms** |

### Relative Performance — Apple M4 (total time)

| Contestant | Total | vs C -O2 | vs C -O0 |
|------------|-------|----------|----------|
| C -O2 | 81 ms | 1.0x | 8.3x faster |
| Java (HotSpot) | 292 ms | 3.6x slower | 2.3x faster |
| Go | 310 ms | 3.8x slower | 2.2x faster |
| C -O0 | 676 ms | 8.3x slower | 1.0x |
| **Limbo JIT** | **1,331 ms** | **16.4x slower** | **2.0x slower** |
| Limbo Interpreter | 11,877 ms | 147x slower | 17.6x slower |
| Python 3.11 | 15,038 ms | 186x slower | 22.2x slower |

### Relative Performance — Jetson AGX Orin (total time)

| Contestant | Total | vs C -O0 |
|------------|-------|----------|
| C -O2 | 588 ms | 5.4x faster |
| Go | 637 ms | 5.0x faster |
| C -O0 | 3,198 ms | 1.0x |
| **Limbo JIT** | **4,594 ms** | **1.4x slower** |
| Limbo Interpreter | 37,886 ms | 11.8x slower |
| Python 3.12 | 55,451 ms | 17.3x slower |

Limbo JIT reaches 69% of unoptimized C throughput on the Jetson — closer to native performance than on the M4, reflecting the Cortex-A78AE's narrower execution pipelines where the JIT's simpler code generation is less of a disadvantage.

### Analysis

**Limbo JIT vs native languages.** On the M4, JIT-compiled Limbo is 16x slower than optimized C and 2x slower than unoptimized C. On the Jetson, the gap narrows to 1.4x slower than C -O0 — the simpler Cortex-A78AE pipelines penalize the JIT's unoptimized code less than the M4's wide out-of-order core. The remaining gap reflects fundamental Dis VM constraints: memory-to-memory architecture (no register file), garbage collector invariants, and mandatory bounds checking on every array access.

**Limbo JIT vs managed languages.** Java HotSpot (3.6x faster on M4) and Go (3.8x faster on M4, 5.0x on Jetson) outperform Limbo JIT. Both benefit from decades of optimization work, profile-guided compilation (Java), and register-allocated intermediate representations. The Dis JIT is a single-pass translator with no optimization passes.

**Limbo JIT vs interpreter.** The JIT provides an 8.9x speedup over the Dis interpreter on the M4 and 8.2x on the Jetson, consistent with the v1 benchmark results. This is the JIT's primary value proposition: making compute-bound Limbo code practical without rewriting in a native language.

**Limbo vs Python.** JIT-compiled Limbo is 11.3x faster than CPython 3.11 (M4) and 12.1x faster than CPython 3.12 (Jetson). Even the Dis interpreter matches or beats Python on array-heavy workloads where Python's per-element overhead dominates.

**Where Limbo JIT excels.** Integer arithmetic (25 ms vs 279 ms interpreter = 11x), nested loops (51 ms vs 717 ms = 14x), and sieve (5 ms vs 45 ms = 9x) show the strongest JIT gains — tight loops with simple operations where eliminating interpreter dispatch overhead matters most.

**Where Limbo JIT struggles.** Recursive Fibonacci (210 ms JIT vs 9 ms Java) highlights the cost of Dis frame allocation. Each recursive call allocates a new frame, checks module pointers, and validates types. Java's HotSpot inlines these calls; the Dis JIT cannot, because frame layout is determined at compile time by the Limbo compiler, not the JIT.

## Methodology

- **Protocol:** Best-of-N reported (N=3 or N=4 depending on suite). System idle during runs.
- **JIT benchmarks:** `appl/cmd/jitbench.b` (v1, 6 benchmarks), `appl/cmd/jitbench2.b` (v2, 26 benchmarks). Run via `emu -c0` (interpreter) and `emu -c1` (JIT).
- **Cross-language:** `benchmarks/run-comparison.sh`. Same algorithms with matched parameters and 64-bit integers. C compiled with `cc` (Apple Clang on macOS, GCC on Linux). Go, Java HotSpot (where available), CPython. Run on Apple M4 and Jetson AGX Orin.
- **Correctness:** 181/181 JIT correctness tests pass on all three platforms. Benchmark result values match between JIT and interpreter.
- **Variation:** JIT run-to-run variance <5% on macOS, <1% on Linux. Interpreter variance <5% on all platforms.

## Detailed Results

Per-platform breakdowns with all individual runs and v2 per-benchmark data:

- [AMD64 Linux](arm64-jit/BENCHMARK-amd64-Linux.md)
- [ARM64 macOS](arm64-jit/BENCHMARK-arm64-macOS.md)
- [ARM64 Linux](arm64-jit/BENCHMARK-arm64-Linux.md)

Benchmark source code and runner scripts: `benchmarks/`.
