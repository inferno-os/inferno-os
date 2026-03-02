implement BenchBsearch;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchBsearch: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

binarySearch(a: array of int, target: int): int
{
	lo := 0;
	hi := len a - 1;
	while(lo <= hi) {
		mid := (lo + hi) / 2;
		if(a[mid] == target)
			return mid;
		if(a[mid] < target)
			lo = mid + 1;
		else
			hi = mid - 1;
	}
	return -1;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	n := 10000;
	a := array[n] of int;
	for(i := 0; i < n; i++)
		a[i] = i * 2;

	t1 := sys->millisec();
	iterations := 100;
	found := 0;
	for(iter := 0; iter < iterations; iter++) {
		for(i := 0; i < n; i++) {
			idx := binarySearch(a, i*2);
			if(idx >= 0)
				found++;
		}
	}
	t2 := sys->millisec();
	sys->print("BENCH bsearch %d ms %d iters %d\n", t2-t1, iterations, found);
}
