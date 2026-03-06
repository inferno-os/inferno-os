implement JitCrash;

include "sys.m";
	sys: Sys;

include "draw.m";

JitCrash: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

ITER: con 1000000;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	# Test 1: Direct fib call (should work, like v1)
	sys->print("Test 1: Direct fib(25)...\n");
	r := fib(25);
	sys->print("  Result: %d\n", r);

	# Test 2: Direct bench_fib call (should work)
	sys->print("Test 2: Direct bench_fib...\n");
	r = bench_fib();
	sys->print("  Result: %d\n", r);

	# Test 3: bench_fib via function reference (crashes in v2?)
	sys->print("Test 3: bench_fib via ref fn...\n");
	f : ref fn(): int;
	f = bench_fib;
	r = f();
	sys->print("  Result: %d\n", r);

	# Test 4: Simple function via ref fn (also crashes?)
	sys->print("Test 4: add_one via ref fn...\n");
	run_bench(bench_simple_call);
	sys->print("  Done\n");

	# Test 5: bench_fib via run_bench (most like v2)
	sys->print("Test 5: bench_fib via run_bench...\n");
	run_bench(bench_fib);
	sys->print("  Done\n");

	sys->print("All tests passed!\n");
}

run_bench(f: ref fn(): int)
{
	r := f();
	sys->print("  Result: %d\n", r);
}

fib(n: int): int
{
	if (n <= 1) return n;
	return fib(n-1) + fib(n-2);
}

bench_fib(): int
{
	sum := 0;
	for (i := 0; i < 50; i++)
		sum += fib(25);
	return sum;
}

bench_simple_call(): int
{
	sum := 0;
	for (i := 0; i < ITER; i++)
		sum += add_one(i);
	return sum;
}

add_one(x: int): int
{
	return x + 1;
}
