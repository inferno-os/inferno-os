/*
 * JITBench.java - Java equivalent of Limbo jitbench.b
 *
 * Same 6 benchmarks with identical parameters for cross-language comparison.
 * Uses long (64-bit) to match Limbo's 64-bit int.
 *
 * Compile and run:
 *   javac JITBench.java && java JITBench
 */

public class JITBench {

    static final int ITERATIONS = 10000000;
    static final int SMALL_ITER = 1000000;

    public static void main(String[] args) {
        System.out.println("=== JIT Benchmark Suite (Java) ===");
        System.out.printf("Iterations: %d (arithmetic), %d (other)%n%n", ITERATIONS, SMALL_ITER);

        warmup();

        // Warmup pass: run full suite once to let HotSpot compile hot loops
        benchArithmetic();
        benchArray();
        benchCalls();
        benchFib();
        benchSieve();
        benchNested();

        // Measurement pass
        long t0 = System.nanoTime();
        long result, t1, t2;

        System.out.println("1. Integer Arithmetic");
        t1 = System.nanoTime();
        result = benchArithmetic();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        System.out.println("2. Loop with Array Access");
        t1 = System.nanoTime();
        result = benchArray();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        System.out.println("3. Function Calls");
        t1 = System.nanoTime();
        result = benchCalls();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        System.out.println("4. Fibonacci (recursive)");
        t1 = System.nanoTime();
        result = benchFib();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        System.out.println("5. Sieve of Eratosthenes");
        t1 = System.nanoTime();
        result = benchSieve();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d primes, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        System.out.println("6. Nested Loops");
        t1 = System.nanoTime();
        result = benchNested();
        t2 = System.nanoTime();
        System.out.printf("   Result: %d, Time: %d ms%n%n", result, (t2 - t1) / 1000000);

        long tend = System.nanoTime();
        System.out.printf("=== Total Time: %d ms ===%n", (tend - t0) / 1000000);
    }

    static void warmup() {
        long sum = 0;
        for (int i = 0; i < 10000; i++)
            sum += i;
        // Prevent DCE
        if (sum == Long.MIN_VALUE) System.out.print("");
    }

    static long benchArithmetic() {
        long a = 1, b = 2, c = 3;

        for (long i = 0; i < ITERATIONS; i++) {
            a = a + b;
            b = b * 3;
            c = c - a;
            a = a ^ b;
            b = b & 0xFFFF;
            c = c | 0x1;
            a = a << 1;
            b = b >> 1;
            c = c + (a % 17);
        }
        return a + b + c;
    }

    static long benchArray() {
        long[] arr = new long[1000];

        for (int i = 0; i < 1000; i++)
            arr[i] = i;

        long sum = 0;
        for (long j = 0; j < SMALL_ITER; j++) {
            for (int i = 0; i < 1000; i++)
                sum += arr[i];
        }
        return sum;
    }

    static long helperAdd(long a, long b) {
        return a + b;
    }

    static long benchCalls() {
        long sum = 0;
        for (long i = 0; i < SMALL_ITER; i++)
            sum += helperAdd(i, i + 1);
        return sum;
    }

    static long fib(long n) {
        if (n <= 1)
            return n;
        return fib(n - 1) + fib(n - 2);
    }

    static long benchFib() {
        long sum = 0;
        for (int i = 0; i < 100; i++)
            sum += fib(25);
        return sum;
    }

    static long benchSieve() {
        final int SIZE = 100000;
        long[] sieve = new long[SIZE];
        long count = 0;

        for (int iter = 0; iter < 10; iter++) {
            for (int i = 0; i < SIZE; i++)
                sieve[i] = 1;

            sieve[0] = 0;
            sieve[1] = 0;

            for (int i = 2; (long)i * i < SIZE; i++) {
                if (sieve[i] != 0) {
                    for (int j = i * i; j < SIZE; j += i)
                        sieve[j] = 0;
                }
            }

            count = 0;
            for (int i = 0; i < SIZE; i++)
                if (sieve[i] != 0)
                    count++;
        }
        return count;
    }

    static long benchNested() {
        long sum = 0;
        for (long i = 0; i < 500; i++)
            for (long j = 0; j < 500; j++)
                for (long k = 0; k < 200; k++)
                    sum += i + j + k;
        return sum;
    }
}
