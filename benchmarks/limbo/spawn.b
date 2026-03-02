implement BenchSpawn;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchSpawn: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

worker(ch: chan of int)
{
	ch <-= 1;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 15;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		n := 1500;
		ch := chan[n] of int;
		for(i := 0; i < n; i++)
			spawn worker(ch);
		sum := 0;
		for(j := 0; j < n; j++)
			sum += <-ch;
		total += sum;
	}
	t2 := sys->millisec();
	sys->print("BENCH spawn %d ms %d iters %d\n", t2-t1, iterations, total);
}
