implement Loop;

include "sys.m";
	sys: Sys;
include "draw.m";

Loop: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	t0 := sys->millisec();

	sum := 0;
	for(i := 0; i < 10000000; i++)
		sum += i;

	t1 := sys->millisec();
	sys->print("%d\n", sum);
	sys->print("%d\n", t1-t0);
}
