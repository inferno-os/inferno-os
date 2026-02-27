implement Fib;

include "sys.m";
	sys: Sys;
include "draw.m";

Fib: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

fib(n: int): int
{
	if(n < 2)
		return n;
	return fib(n-1) + fib(n-2);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	t0 := sys->millisec();
	result := fib(35);
	t1 := sys->millisec();
	sys->print("%d\n", result);
	sys->print("%d\n", t1-t0);
}
