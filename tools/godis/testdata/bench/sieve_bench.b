implement Sieve;

include "sys.m";
	sys: Sys;
include "draw.m";

Sieve: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	n := 10000;
	iters := 100;
	t0 := sys->millisec();

	count := 0;
	for(iter := 0; iter < iters; iter++){
		sieve := array[n] of {* => 0};
		for(i := 2; i*i < n; i++){
			if(sieve[i] == 0){
				for(j := i*i; j < n; j += i)
					sieve[j] = 1;
			}
		}

		count = 0;
		for(i = 2; i < n; i++){
			if(sieve[i] == 0)
				count++;
		}
	}

	t1 := sys->millisec();
	sys->print("%d\n", count);
	sys->print("%d\n", t1-t0);
}
