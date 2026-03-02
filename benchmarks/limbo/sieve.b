implement BenchSieve;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchSieve: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

sieve(limit: int): int
{
	s := array[limit+1] of {* => 0};
	count := 0;
	for(i := 2; i <= limit; i++) {
		if(s[i] == 0) {
			count++;
			for(j := i+i; j <= limit; j += i)
				s[j] = 1;
		}
	}
	return count;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	result := 0;
	iterations := 50;
	for(i := 0; i < iterations; i++)
		result = sieve(50000);
	t2 := sys->millisec();
	sys->print("BENCH sieve %d ms %d iters %d\n", t2-t1, iterations, result);
}
