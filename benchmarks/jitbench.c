/*
 * jitbench.c - C equivalent of Limbo jitbench.b
 *
 * Same 6 benchmarks with identical parameters for cross-language comparison.
 * Uses int64_t to match Limbo's 64-bit int (WORD is intptr on 64-bit Inferno).
 *
 * Compile:
 *   cc -O0 -o jitbench_O0 jitbench.c    # unoptimized baseline
 *   cc -O2 -o jitbench_O2 jitbench.c    # production optimization
 */

#include <stdio.h>
#include <stdint.h>
#include <time.h>

#define ITERATIONS  10000000
#define SMALL_ITER  1000000

static int64_t millisec(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void warmup(void)
{
	volatile int64_t sum = 0;
	for (int i = 0; i < 10000; i++)
		sum += i;
}

static int64_t bench_arithmetic(void)
{
	int64_t a = 1, b = 2, c = 3;

	for (int64_t i = 0; i < ITERATIONS; i++) {
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

static int64_t bench_array(void)
{
	int64_t arr[1000];

	for (int i = 0; i < 1000; i++)
		arr[i] = i;

	int64_t sum = 0;
	for (int64_t j = 0; j < SMALL_ITER; j++) {
		for (int i = 0; i < 1000; i++)
			sum += arr[i];
	}
	return sum;
}

static int64_t helper_add(int64_t a, int64_t b)
{
	return a + b;
}

static int64_t bench_calls(void)
{
	int64_t sum = 0;
	for (int64_t i = 0; i < SMALL_ITER; i++)
		sum += helper_add(i, i + 1);
	return sum;
}

static int64_t fib(int64_t n)
{
	if (n <= 1)
		return n;
	return fib(n - 1) + fib(n - 2);
}

static int64_t bench_fib(void)
{
	int64_t sum = 0;
	for (int i = 0; i < 100; i++)
		sum += fib(25);
	return sum;
}

static int64_t bench_sieve(void)
{
	#define SIZE 100000
	int64_t sieve[SIZE];
	int64_t count = 0;

	for (int iter = 0; iter < 10; iter++) {
		for (int i = 0; i < SIZE; i++)
			sieve[i] = 1;

		sieve[0] = 0;
		sieve[1] = 0;

		for (int i = 2; (int64_t)i * i < SIZE; i++) {
			if (sieve[i]) {
				for (int j = i * i; j < SIZE; j += i)
					sieve[j] = 0;
			}
		}

		count = 0;
		for (int i = 0; i < SIZE; i++)
			if (sieve[i])
				count++;
	}
	return count;
	#undef SIZE
}

static int64_t bench_nested(void)
{
	int64_t sum = 0;
	for (int64_t i = 0; i < 500; i++)
		for (int64_t j = 0; j < 500; j++)
			for (int64_t k = 0; k < 200; k++)
				sum += i + j + k;
	return sum;
}

int main(void)
{
	int64_t t0, t1, t2, tend;
	int64_t result;

	printf("=== JIT Benchmark Suite (C) ===\n");
	printf("Iterations: %d (arithmetic), %d (other)\n\n", ITERATIONS, SMALL_ITER);

	warmup();

	t0 = millisec();

	printf("1. Integer Arithmetic\n");
	t1 = millisec();
	result = bench_arithmetic();
	t2 = millisec();
	printf("   Result: %lld, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	printf("2. Loop with Array Access\n");
	t1 = millisec();
	result = bench_array();
	t2 = millisec();
	printf("   Result: %lld, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	printf("3. Function Calls\n");
	t1 = millisec();
	result = bench_calls();
	t2 = millisec();
	printf("   Result: %lld, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	printf("4. Fibonacci (recursive)\n");
	t1 = millisec();
	result = bench_fib();
	t2 = millisec();
	printf("   Result: %lld, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	printf("5. Sieve of Eratosthenes\n");
	t1 = millisec();
	result = bench_sieve();
	t2 = millisec();
	printf("   Result: %lld primes, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	printf("6. Nested Loops\n");
	t1 = millisec();
	result = bench_nested();
	t2 = millisec();
	printf("   Result: %lld, Time: %lld ms\n\n", (long long)result, (long long)(t2 - t1));

	tend = millisec();
	printf("=== Total Time: %lld ms ===\n", (long long)(tend - t0));

	return 0;
}
