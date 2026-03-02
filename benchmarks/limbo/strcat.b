implement BenchStrcat;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchStrcat: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 300;
	totalLen := 0;
	for(iter := 0; iter < iterations; iter++) {
		s := "";
		for(i := 0; i < 2000; i++)
			s += "a";
		totalLen += len s;
	}
	t2 := sys->millisec();
	sys->print("BENCH strcat %d ms %d iters %d\n", t2-t1, iterations, totalLen);
}
