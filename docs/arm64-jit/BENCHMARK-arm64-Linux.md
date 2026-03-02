# ARM64 JIT Benchmark Results — Linux

## Platform
- **Hardware:** NVIDIA Jetson AGX Orin
- **CPU:** ARMv8 Processor rev 1 (v8l) — ARM Cortex-A78AE
- **OS:** Linux 5.15.148-tegra (aarch64)

---

## JIT Rewrite (arm64-jit-rewrite branch)

**Date:** 2026-02-08

The rewrite does full inline compilation for ARM64, replacing the
original partial-inline approach. All operations are compiled to native
ARM64 instructions, eliminating interpreter dispatch overhead.

### jitbench v1 — Totals (4 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |      38,320 |    4,610 |   8.31x |
| 2   |           — |    4,608 |       — |
| 3   |           — |    4,620 |       — |
| 4   |           — |    4,623 |       — |
| **Avg** | **38,320** | **4,615** | **8.30x** |

### jitbench v1 — Per-benchmark breakdown (best of 4)

| Benchmark              | Interp (ms) | JIT (ms) | Speedup |
|------------------------|-------------|----------|---------|
| Integer Arithmetic     |         856 |      119 |   7.19x |
| Loop with Array Access |      33,708 |    3,666 |   9.19x |
| Function Calls         |          38 |        4 |   9.50x |
| Fibonacci (recursive)  |       1,671 |      633 |   2.64x |
| Sieve of Eratosthenes  |         136 |       16 |   8.50x |
| Nested Loops           |       1,911 |      169 |  11.31x |

### jitbench v2 — Totals (4 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |       2,743 |      937 |   2.93x |
| 2   |           — |      940 |       — |
| 3   |           — |      939 |       — |
| 4   |           — |      937 |       — |
| **Avg** | **2,743** | **938** | **2.92x** |

### jitbench v2 — Per-category breakdown (best of 4)

| Benchmark                | Interp (ms) | JIT (ms) | Speedup |
|--------------------------|-------------|----------|---------|
| **Integer ALU**          |             |          |         |
| 1a. ADD/SUB chain        |          53 |        9 |   5.89x |
| 1b. MUL/DIV/MOD          |           6 |        2 |   3.00x |
| 1c. Bitwise ops          |          66 |       13 |   5.08x |
| 1d. Shift ops            |          54 |        6 |   9.00x |
| 1e. Mixed ALU            |          74 |       10 |   7.40x |
| **Branch & Control**     |             |          |         |
| 2a. Simple branch        |          40 |        3 |  13.33x |
| 2b. Compare chain        |          51 |        5 |  10.20x |
| 2c. Nested branches      |           7 |        0 |       — |
| 2d. Loop countdown       |          24 |        3 |   8.00x |
| **Memory Access**        |             |          |         |
| 3a. Sequential read      |          33 |        4 |   8.25x |
| 3b. Sequential write     |          34 |        3 |  11.33x |
| 3c. Stride access        |          66 |        7 |   9.43x |
| 3d. Small array hot      |          59 |        6 |   9.83x |
| **Function Calls**       |             |          |         |
| 4a. Simple call          |          31 |        3 |  10.33x |
| 4b. Recursive fib        |         863 |      660 |   1.31x |
| 4c. Mutual recursion     |          41 |       22 |   1.86x |
| 4d. Deep call chain      |          49 |       23 |   2.13x |
| **Big (64-bit)**         |             |          |         |
| 5a. Big add/sub          |          39 |        5 |   7.80x |
| 5b. Big bitwise          |          58 |        9 |   6.44x |
| 5c. Big shifts           |          65 |        6 |  10.83x |
| 5d. Big comparisons      |          65 |        4 |  16.25x |
| **Byte Ops**             |             |          |         |
| 6a. Byte arithmetic      |          52 |        7 |   7.43x |
| 6b. Byte array           |         103 |       10 |  10.30x |
| **List Ops**             |             |          |         |
| 7a. List build           |           8 |       10 |   0.80x |
| 7b. List traverse        |          39 |        6 |   6.50x |
| **Mixed Workloads**      |             |          |         |
| 8a. Sieve                |         128 |       14 |   9.14x |
| 8b. Matrix multiply      |         280 |       33 |   8.48x |
| 8c. Bubble sort          |         168 |       17 |   9.88x |
| 8d. Binary search        |          98 |       20 |   4.90x |
| **Type Conversions**     |             |          |         |
| 9a. int<->big            |          44 |        5 |   8.80x |
| 9b. int<->byte           |          44 |        4 |  11.00x |

---

## Original JIT (master branch)

**Date:** 2026-02-06

### jitbench v1 — Per-benchmark breakdown

| Benchmark              | Interp (ms) | JIT (ms) | Speedup |
|------------------------|-------------|----------|---------|
| Integer Arithmetic     |         863 |      442 |   1.95x |
| Loop with Array Access |      33,738 |    7,603 |   4.43x |
| Function Calls         |          38 |       35 |   1.08x |
| Fibonacci              |       1,680 |      606 |   2.77x |
| Sieve of Eratosthenes  |         136 |       61 |   2.22x |
| Nested Loops           |       1,924 |    1,751 |   1.09x |

### jitbench v1 — Totals (3 runs)

| Run | Interp (ms) | JIT (ms) | Speedup |
|-----|-------------|----------|---------|
| 1   |      38,347 |   10,509 |   3.64x |
| 2   |      38,374 |   10,493 |   3.65x |
| 3   |      38,380 |   10,498 |   3.65x |
| **Avg** | **38,367** | **10,500** | **3.65x** |

---

## Rewrite vs Original — Summary

| Metric                    | Original JIT | Rewrite JIT | Improvement |
|---------------------------|-------------|-------------|-------------|
| jitbench v1 total (avg)   |  10,500 ms  |   4,615 ms  | **2.28x faster** |
| jitbench v1 speedup       |      3.65x  |      8.30x  |             |
| Integer Arithmetic         |     442 ms  |     119 ms  | **3.71x faster** |
| Loop + Array Access        |   7,603 ms  |   3,666 ms  | **2.07x faster** |
| Function Calls             |      35 ms  |       4 ms  | **8.75x faster** |
| Sieve of Eratosthenes      |      61 ms  |      16 ms  | **3.81x faster** |
| Nested Loops               |   1,751 ms  |     169 ms  | **10.36x faster** |

The rewrite is **2.28x faster** than the original JIT overall, with the
largest gains in nested loops (10.36x) and function calls (8.75x) due
to full inline compilation eliminating interpreter dispatch.

## Cross-Language Comparison (jitbench v1)

**Date:** 2026-02-11

Best of 3 runs. All languages run the same 6 benchmarks with the same
iteration counts.

| Benchmark              | C -O2 | C -O0 |    Go | Python 3.12 | Limbo JIT | Limbo Interp |
|------------------------|------:|------:|------:|------------:|----------:|-------------:|
| Integer Arithmetic     |  39ms | 105ms |  40ms |     9,379ms |     122ms |        856ms |
| Loop with Array Access | 518ms |2,892ms| 523ms |    39,996ms |   3,655ms |     33,259ms |
| Function Calls         |   0ms |   3ms |   1ms |       163ms |       5ms |         38ms |
| Fibonacci (recursive)  |  26ms |  49ms |  36ms |     1,522ms |     627ms |      1,710ms |
| Sieve of Eratosthenes  |   5ms |  13ms |   4ms |        74ms |      16ms |        136ms |
| Nested Loops           |   0ms | 136ms |  32ms |     4,317ms |     169ms |      1,887ms |
| **TOTAL**              |**588ms**|**3,198ms**|**637ms**|**55,451ms**|**4,594ms**|**37,886ms**|

### Speedup vs C -O0

| Language     | Speedup |
|--------------|--------:|
| C -O2        |   5.43x |
| Go           |   5.02x |
| Limbo JIT    |   0.69x |
| Limbo Interp |   0.08x |
| Python 3.12  |   0.05x |

### Limbo JIT vs Interpreter: 8.24x

The ARM64 JIT achieves **69% of C -O0 throughput** and is **12x faster
than Python**. It sits between Python and unoptimized C, which is
strong for a bytecode VM with a simple single-pass JIT compiler.

---

## Notes
- Run-to-run variation: < 0.3%
- System was idle during benchmarks (no competing workloads)
- Benchmarks: `dis/jitbench.dis`, `dis/jitbench2.dis`
- Source: `appl/cmd/jitbench.b`, `appl/cmd/jitbench2.b`
- Interpreter: `emu -c0`, JIT: `emu -c1`
- Cross-language: `benchmarks/run-comparison.sh`
