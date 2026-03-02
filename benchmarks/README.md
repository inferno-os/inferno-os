# Benchmark Suites

Three benchmark suites measure Dis VM and cross-language performance.

## v1: JIT vs Interpreter (6 benchmarks)

**Source:** `appl/cmd/jitbench.b`
**Benchmarks:** Integer Arithmetic, Array Access, Function Calls, Fibonacci, Sieve of Eratosthenes, Nested Loops

```sh
bash benchmarks/bench-jit.sh v1 3
```

## v2: JIT vs Interpreter (26 benchmarks, 9 categories)

**Source:** `appl/cmd/jitbench2.b`
**Categories:** Integer ALU, Branch & Control, Memory Access, Function Calls, Big (64-bit), Byte Ops, List Ops, Mixed Workloads, Type Conversions

```sh
bash benchmarks/bench-jit.sh v2 3
```

## v3: Cross-Language Comparison

**Sources:** `jitbench.c`, `jitbench.go`, `JITBench.java`, plus Limbo v1
**Contestants:** C -O0, C -O2, Go, Java (HotSpot), Limbo JIT, Limbo Interpreter

Same 6 benchmarks as v1, ported to each language with matched parameters and 64-bit integer types.

```sh
bash benchmarks/run-comparison.sh 3
```

Gracefully skips contestants whose toolchains aren't available (no Go, no Java, no emulator — each is optional).

## Results

Full per-platform data in [docs/BENCHMARKS.md](../docs/BENCHMARKS.md).
