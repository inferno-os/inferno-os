implement BenchChannel;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchChannel: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

producer(ch: chan of int, n: int)
{
	for(i := 0; i < n; i++)
		ch <-= i;
	ch <-= -1;  # sentinel
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 10;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		ch := chan[100] of int;
		spawn producer(ch, 10000);
		sum := 0;
		for(;;) {
			v := <-ch;
			if(v == -1)
				break;
			sum += v;
		}
		total += sum;
	}
	t2 := sys->millisec();
	sys->print("BENCH channel %d ms %d iters %d\n", t2-t1, iterations, total);
}
