implement BenchQsort;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchQsort: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

partition(a: array of int, lo, hi: int): int
{
	pivot := a[hi];
	i := lo;
	for(j := lo; j < hi; j++) {
		if(a[j] < pivot) {
			tmp := a[i];
			a[i] = a[j];
			a[j] = tmp;
			i++;
		}
	}
	tmp := a[i];
	a[i] = a[hi];
	a[hi] = tmp;
	return i;
}

quicksort(a: array of int, lo, hi: int)
{
	if(lo < hi) {
		p := partition(a, lo, hi);
		quicksort(a, lo, p-1);
		quicksort(a, p+1, hi);
	}
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	n := 10000;
	t1 := sys->millisec();
	iterations := 50;
	checksum := 0;
	for(iter := 0; iter < iterations; iter++) {
		a := array[n] of int;
		for(i := 0; i < n; i++)
			a[i] = (n - i) * 7 % 1000;
		quicksort(a, 0, n-1);
		checksum += a[0] + a[n-1];
	}
	t2 := sys->millisec();
	sys->print("BENCH qsort %d ms %d iters %d\n", t2-t1, iterations, checksum);
}
