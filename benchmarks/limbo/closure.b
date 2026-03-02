implement BenchClosure;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchClosure: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# Limbo doesn't have closures with captured variables.
# We simulate with ADTs containing the captured state,
# which is the idiomatic Limbo approach.

Adder: adt {
	x: int;
	apply: fn(a: self ref Adder, y: int): int;
};

Adder.apply(a: self ref Adder, y: int): int
{
	return a.x + y;
}

applyN(a: ref Adder, iterations: int): int
{
	result := 0;
	for(i := 0; i < iterations; i++)
		result += a.apply(i);
	return result;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 500;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		add5 := ref Adder(5);
		add10 := ref Adder(10);
		total += applyN(add5, 10000);
		total += applyN(add10, 10000);
	}
	t2 := sys->millisec();
	sys->print("BENCH closure %d ms %d iters %d\n", t2-t1, iterations, total);
}
