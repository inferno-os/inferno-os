implement BenchFib;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchFib: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

fib(n: int): int
{
	if(n <= 1)
		return n;
	return fib(n-1) + fib(n-2);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	result := 0;
	iterations := 10;
	for(i := 0; i < iterations; i++)
		result = fib(30);
	t2 := sys->millisec();
	sys->print("BENCH fib %d ms %d iters %d\n", t2-t1, iterations, result);
}
