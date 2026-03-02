# AMD64 JIT Benchmark Results — Linux

## Platform
- **Hardware:** Beelink SER9 Pro
- **CPU:** AMD Ryzen 7 H 255 (16 cores)
- **RAM:** 21 GB
- **OS:** Linux 6.14.0-37-generic (x86_64)

---

## AMD64 JIT (master branch)

**Date:** 2026-02-09

The AMD64 JIT compiler (`comp-amd64.c`) translates Dis VM bytecode directly
to x86-64 machine code at module load time using the System V AMD64 ABI.
All data operations (integer, float, memory, branch) are compiled inline.

### jitbench v1 — Totals (3 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |      21,081 |    1,545 |  13.64x |
| 2   |      21,813 |    1,484 |  14.70x |
| 3   |      20,872 |    1,472 |  14.18x |
| **Avg** | **21,255** | **1,500** | **14.17x** |

### jitbench v1 — Per-benchmark breakdown (best of 3)

| Benchmark              | Interp (ms) | JIT (ms) | Speedup |
|------------------------|-------------|----------|---------|
| Integer Arithmetic     |         466 |       23 |  20.3x |
| Loop with Array Access |      18,284 |    1,131 |  16.2x |
| Function Calls         |          20 |        1 |  20.0x |
| Fibonacci (recursive)  |         777 |      243 |   3.2x |
| Sieve of Eratosthenes  |          74 |        5 |  14.8x |
| Nested Loops           |       1,152 |       65 |  17.7x |

### jitbench v2 — Totals (3 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |       1,534 |      262 |   5.86x |
| 2   |       1,505 |      273 |   5.51x |
| 3   |       1,473 |      253 |   5.82x |
| **Avg** | **1,504** | **263** | **5.72x** |

### jitbench v2 — Per-category breakdown (best of 3)

| Benchmark                | Interp (ms) | JIT (ms) | Speedup |
|--------------------------|-------------|----------|---------|
| **Integer ALU**          |             |          |         |
| 1a. ADD/SUB chain        |          30 |        1 |  30.0x |
| 1b. MUL/DIV/MOD          |           3 |        1 |   3.0x |
| 1c. Bitwise ops          |          36 |        2 |  18.0x |
| 1d. Shift ops            |          29 |        2 |  14.5x |
| 1e. Mixed ALU            |          41 |        4 |  10.3x |
| **Branch & Control**     |             |          |         |
| 2a. Simple branch        |          24 |        1 |  24.0x |
| 2b. Compare chain        |          31 |        1 |  31.0x |
| 2c. Nested branches      |           3 |        0 |      — |
| 2d. Loop countdown       |          14 |        0 |      — |
| **Memory Access**        |             |          |         |
| 3a. Sequential read      |          19 |        1 |  19.0x |
| 3b. Sequential write     |          20 |        1 |  20.0x |
| 3c. Stride access        |          39 |        2 |  19.5x |
| 3d. Small array hot      |          33 |        1 |  33.0x |
| **Function Calls**       |             |          |         |
| 4a. Simple call          |          16 |        1 |  16.0x |
| 4b. Recursive fib        |         397 |      157 |   2.5x |
| 4c. Mutual recursion     |          20 |        3 |   6.7x |
| 4d. Deep call chain      |          22 |        3 |   7.3x |
| **Big (64-bit)**         |             |          |         |
| 5a. Big add/sub          |          22 |        2 |  11.0x |
| 5b. Big bitwise          |          35 |        9 |   3.9x |
| 5c. Big shifts           |          39 |        5 |   7.8x |
| 5d. Big comparisons      |          39 |        2 |  19.5x |
| **Byte Ops**             |             |          |         |
| 6a. Byte arithmetic      |          30 |        4 |   7.5x |
| 6b. Byte array           |          58 |        3 |  19.3x |
| **List Ops**             |             |          |         |
| 7a. List build           |           3 |        2 |   1.5x |
| 7b. List traverse        |          20 |        2 |  10.0x |
| **Mixed Workloads**      |             |          |         |
| 8a. Sieve                |          75 |        4 |  18.8x |
| 8b. Matrix multiply      |         161 |        9 |  17.9x |
| 8c. Bubble sort          |          93 |        5 |  18.6x |
| 8d. Binary search        |          53 |        7 |   7.6x |
| **Type Conversions**     |             |          |         |
| 9a. int<->big            |          26 |        5 |   5.2x |
| 9b. int<->byte           |          25 |        1 |  25.0x |

### v2 Category Aggregates (sum of best-of-3, in ms)

| Category           | JIT | Interp | Speedup |
|--------------------|----:|-------:|--------:|
| Integer ALU        |  10 |    139 |  13.9x |
| Branch & Control   |   2 |     72 |  36.0x |
| Memory Access      |   5 |    111 |  22.2x |
| Function Calls     | 164 |    455 |   2.8x |
| Big (64-bit)       |  18 |    135 |   7.5x |
| Byte Ops           |   7 |     88 |  12.6x |
| List Ops           |   4 |     23 |   5.8x |
| Mixed Workloads    |  25 |    382 |  15.3x |
| Type Conversions   |   6 |     51 |   8.5x |

---

## Cross-Platform Comparison (JIT vs Interpreter)

| Metric                    | AMD64 Linux  | Jetson Orin (ARM64) | Apple M4 (ARM64) |
|---------------------------|--------------|---------------------|----------------------|
| jitbench v1 interp        |   21,255 ms  |        38,320 ms    |         16,697 ms    |
| jitbench v1 JIT (avg)     |    1,500 ms  |         4,615 ms    |          1,735 ms    |
| jitbench v1 speedup       |     14.2x    |           8.3x      |            9.6x      |
| jitbench v2 interp        |    1,504 ms  |         2,743 ms    |          1,086 ms    |
| jitbench v2 JIT (avg)     |      263 ms  |           938 ms    |            413 ms    |
| jitbench v2 speedup       |      5.7x    |           2.9x      |            2.6x      |

The AMD64 JIT achieves the highest speedup ratios (14.2x on v1, 5.7x on v2),
reflecting the efficiency of native x86-64 code generation for the Dis VM's
register-based bytecode. The v1 speedup is particularly strong because the
v1 suite is dominated by tight computational loops where eliminating
interpreter dispatch overhead yields the greatest gains.

In absolute terms, AMD64 JIT is comparable to Apple M4 JIT (1,500 vs
1,735 ms on v1) despite different architectures, confirming the AMD64 JIT
generates efficient native code.

## Test Results

All tests pass with JIT enabled (`-c1`):

| Test Suite               | Result |
|--------------------------|--------|
| hello_test               | 4/4 PASS |
| agent_test               | 12/12 PASS |
| 9p_export_test           | 3/3 PASS |
| stderr_test              | 6/6 PASS |
| edit_test                | 9/9 PASS |
| example_test             | 4/4 PASS, 1 skip |
| jit_test                 | 181/181 PASS |
| veltro_test              | 13/13 PASS, 2 skip |
| veltro_tools_test        | 8/8 PASS |
| xenith_concurrency_test  | 10/10 PASS |
| xenith_exit_test         | 6/6 PASS |
| tcp_test                 | 3/3 PASS, 2 skip |

## Notes
- Run-to-run variation: V1 JIT 5.0%, V2 JIT 7.9%, V1 Interp 4.5%, V2 Interp 4.1%
- System was idle during benchmarks (no competing workloads)
- Benchmarks: `dis/jitbench.dis`, `dis/jitbench2.dis`
- Source: `appl/cmd/jitbench.b`, `appl/cmd/jitbench2.b`
- Interpreter: `emu -c0`, JIT: `emu -c1`
- Tests: 181/181 JIT correctness tests pass (jit_test.dis)
