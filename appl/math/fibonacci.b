implement Fibonacci;

include "sys.m";
include "draw.m";

Fibonacci: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	for(i := 0; ; i++){
		f := fibonacci(i);
		if(f < 0)
			break;
		sys->print("F(%d) = %d\n", i, f);
	}
}

FIB: exception(int, int);
HELP: con "help";

NOVAL: con -1000000000;

fibonacci(n: int): int
{
	{
		fib(1, n, 1, 1);
	}
	exception e{
		FIB =>
			(x, nil) := e;
			return x;
		* =>
			return NOVAL;
	}
	return NOVAL;
}

fib(n: int, m: int, x: int, y: int) raises (FIB)
{
	if(n >= m)
		raise FIB(x, y);

	{
		fib(n+1, m, x, y);
	}
	exception e{
		FIB =>
			(x, y) = e;
			x = x+y;
			y = x-y;
			raise FIB(x, y);
		* =>
			raise HELP;
	}
}
