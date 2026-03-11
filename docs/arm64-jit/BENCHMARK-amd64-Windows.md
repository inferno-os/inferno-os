# AMD64 JIT Benchmark Results — Windows

## Platform
- **Hardware:** Beelink SER9 Pro
- **CPU:** AMD Ryzen 7 255 w/ Radeon 780M Graphics (16 cores)
- **RAM:** 28 GB
- **OS:** Windows 11 Pro 10.0.26100

**Note:** Windows system timer resolution is ~15.6 ms (`GetTickCount`). Benchmarks completing in < 16 ms report as 0 ms. The same CPU on Linux (see [AMD64 Linux](BENCHMARK-amd64-Linux.md)) has 1 ms timer resolution, providing finer granularity for fast benchmarks. Total times and longer benchmarks are unaffected.

---

## AMD64 JIT (windows-port branch)

**Date:** 2026-03-06

The AMD64 JIT compiler (`comp-amd64.c`) on Windows uses the Windows x64 ABI
(callee-saved RSI/RDI, 32-byte shadow space). JIT code buffers use
`VirtualAlloc(PAGE_READWRITE)` with W^X discipline via `VirtualProtect(PAGE_EXECUTE_READ)`
after code generation. Built with MSVC (`/O2 /MT`).

### jitbench v1 — Totals (3 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |      19,344 |    1,422 |  13.60x |
| 2   |      19,141 |    1,437 |  13.32x |
| 3   |      18,860 |    1,453 |  12.98x |
| **Avg** | **19,115** | **1,437** | **13.30x** |

### jitbench v1 — Per-benchmark breakdown (best of 3)

| Benchmark              | Interp (ms) | JIT (ms) | Speedup |
|------------------------|-------------|----------|---------|
| Integer Arithmetic     |         781 |       15 |  52.1x |
| Loop with Array Access |      16,312 |    1,109 |  14.7x |
| Function Calls         |          16 |      < 16 |    — |
| Fibonacci (recursive)  |         734 |      219 |   3.4x |
| Sieve of Eratosthenes  |          62 |      < 16 |    — |
| Nested Loops           |         953 |       62 |  15.4x |

### jitbench v2 — Totals (3 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |       1,484 |      250 |   5.94x |
| 2   |       1,438 |      266 |   5.41x |
| 3   |       1,469 |      266 |   5.52x |
| **Avg** | **1,464** | **261** | **5.61x** |

### jitbench v2 — Per-category breakdown (best of 3)

Timer resolution limits per-benchmark precision. Where JIT completes in < 16 ms, individual speedups are not meaningful; category aggregates and totals provide reliable comparison.

| Benchmark                | Interp (ms) | JIT (ms) | Speedup |
|--------------------------|-------------|----------|---------|
| **Integer ALU**          |             |          |         |
| 1a. ADD/SUB chain        |          31 |      < 16 |    — |
| 1b. MUL/DIV/MOD          |          15 |      < 16 |    — |
| 1c. Bitwise ops          |          47 |       16 |   2.9x |
| 1d. Shift ops            |          31 |      < 16 |    — |
| 1e. Mixed ALU            |          47 |      < 16 |    — |
| **Branch & Control**     |             |          |         |
| 2a. Simple branch        |          16 |      < 16 |    — |
| 2b. Compare chain        |          31 |      < 16 |    — |
| 2c. Nested branches      |       < 16 |      < 16 |    — |
| 2d. Loop countdown       |          15 |      < 16 |    — |
| **Memory Access**        |             |          |         |
| 3a. Sequential read      |          15 |      < 16 |    — |
| 3b. Sequential write     |          16 |      < 16 |    — |
| 3c. Stride access        |          16 |      < 16 |    — |
| 3d. Small array hot      |          16 |      < 16 |    — |
| **Function Calls**       |             |          |         |
| 4a. Simple call          |          16 |      < 16 |    — |
| 4b. Recursive fib        |         375 |      156 |   2.4x |
| 4c. Mutual recursion     |          15 |      < 16 |    — |
| 4d. Deep call chain      |          15 |      < 16 |    — |
| **Big (64-bit)**         |             |          |         |
| 5a. Big add/sub          |          15 |      < 16 |    — |
| 5b. Big bitwise          |          31 |      < 16 |    — |
| 5c. Big shifts           |          31 |      < 16 |    — |
| 5d. Big comparisons      |          31 |      < 16 |    — |
| **Byte Ops**             |             |          |         |
| 6a. Byte arithmetic      |          32 |      < 16 |    — |
| 6b. Byte array           |          46 |      < 16 |    — |
| **List Ops**             |             |          |         |
| 7a. List build           |       < 16 |      < 16 |    — |
| 7b. List traverse        |       < 16 |      < 16 |    — |
| **Mixed Workloads**      |             |          |         |
| 8a. Sieve                |          62 |      < 16 |    — |
| 8b. Matrix multiply      |         156 |      < 16 |    — |
| 8c. Bubble sort          |         125 |       15 |   8.3x |
| 8d. Binary search        |          31 |      < 16 |    — |
| **Type Conversions**     |             |          |         |
| 9a. int<->big            |          16 |      < 16 |    — |
| 9b. int<->byte           |          15 |      < 16 |    — |

---

## Cross-Platform Comparison (same CPU: AMD Ryzen 7 255)

This system runs the same CPU as the [AMD64 Linux](BENCHMARK-amd64-Linux.md) benchmark platform, enabling a direct Windows-vs-Linux comparison of the JIT compiler.

| Metric | Windows | Linux | Notes |
|--------|---------|-------|-------|
| v1 JIT best | 1,422 ms | 1,472 ms | Within 3% — near identical |
| v1 Interp best | 18,860 ms | 20,872 ms | Windows 10% faster |
| v1 Speedup (avg) | 13.3x | 14.2x | Linux slightly higher ratio |
| v2 JIT best | 250 ms | 253 ms | Within 1% — near identical |
| v2 Interp best | 1,438 ms | 1,473 ms | Within 2% |
| v2 Speedup (avg) | 5.6x | 5.7x | Near identical |

JIT absolute performance is essentially identical across Windows and Linux on the same hardware. The W^X `VirtualAlloc`/`VirtualProtect` path on Windows performs comparably to Linux's `mmap`/`mprotect`.
