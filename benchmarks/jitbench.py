#!/usr/bin/env python3
"""
jitbench.py - Python equivalent of Limbo jitbench.b

Same 6 benchmarks with identical parameters for cross-language comparison.
CPython has no JIT - this is pure interpreter baseline.

Run:
    python3 jitbench.py
"""

import time

ITERATIONS = 10000000
SMALL_ITER = 1000000

# Python has arbitrary-precision integers. To match 64-bit signed wraparound
# behavior of C/Go/Java/Limbo, we mask to 64 bits where overflow can occur.
MASK64 = 0xFFFFFFFFFFFFFFFF

def to_signed64(v):
    """Convert masked 64-bit value to signed interpretation."""
    v = v & MASK64
    if v >= 0x8000000000000000:
        v -= 0x10000000000000000
    return v


def millisec():
    return int(time.monotonic() * 1000)


def warmup():
    s = 0
    for i in range(10000):
        s += i


def bench_arithmetic():
    a, b, c = 1, 2, 3
    mask = MASK64
    for _ in range(ITERATIONS):
        a = (a + b) & mask
        b = (b * 3) & mask
        c = (c - a) & mask
        a = (a ^ b) & mask
        b = b & 0xFFFF
        c = c | 0x1
        a = (a << 1) & mask
        b = b >> 1
        c = (c + (to_signed64(a) % 17)) & mask
    return to_signed64(a + b + c)


def bench_array():
    arr = list(range(1000))
    s = 0
    for _ in range(SMALL_ITER):
        for v in arr:
            s += v
    return s


def helper_add(a, b):
    return a + b


def bench_calls():
    s = 0
    for i in range(SMALL_ITER):
        s += helper_add(i, i + 1)
    return s


def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)


def bench_fib():
    s = 0
    for _ in range(100):
        s += fib(25)
    return s


def bench_sieve():
    SIZE = 100000
    count = 0
    for _ in range(10):
        sieve = [1] * SIZE
        sieve[0] = 0
        sieve[1] = 0
        i = 2
        while i * i < SIZE:
            if sieve[i]:
                for j in range(i * i, SIZE, i):
                    sieve[j] = 0
            i += 1
        count = sum(sieve)
    return count


def bench_nested():
    s = 0
    for i in range(500):
        for j in range(500):
            for k in range(200):
                s += i + j + k
    return s


def main():
    print("=== JIT Benchmark Suite (Python) ===")
    print(f"Iterations: {ITERATIONS} (arithmetic), {SMALL_ITER} (other)\n")

    warmup()

    t0 = millisec()

    print("1. Integer Arithmetic")
    t1 = millisec()
    result = bench_arithmetic()
    t2 = millisec()
    print(f"   Result: {result}, Time: {t2 - t1} ms\n")

    print("2. Loop with Array Access")
    t1 = millisec()
    result = bench_array()
    t2 = millisec()
    print(f"   Result: {result}, Time: {t2 - t1} ms\n")

    print("3. Function Calls")
    t1 = millisec()
    result = bench_calls()
    t2 = millisec()
    print(f"   Result: {result}, Time: {t2 - t1} ms\n")

    print("4. Fibonacci (recursive)")
    t1 = millisec()
    result = bench_fib()
    t2 = millisec()
    print(f"   Result: {result}, Time: {t2 - t1} ms\n")

    print("5. Sieve of Eratosthenes")
    t1 = millisec()
    result = bench_sieve()
    t2 = millisec()
    print(f"   Result: {result} primes, Time: {t2 - t1} ms\n")

    print("6. Nested Loops")
    t1 = millisec()
    result = bench_nested()
    t2 = millisec()
    print(f"   Result: {result}, Time: {t2 - t1} ms\n")

    tend = millisec()
    print(f"=== Total Time: {tend - t0} ms ===")


if __name__ == "__main__":
    main()
