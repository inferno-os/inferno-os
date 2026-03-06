implement Sort;

include "sys.m";
	sys: Sys;
include "draw.m";

Sort: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

qsort(a: array of int, lo, hi: int)
{
	if(lo >= hi)
		return;
	pivot := a[lo];
	i := lo + 1;
	j := hi;
	while(i <= j){
		while(i <= hi && a[i] <= pivot)
			i++;
		while(j > lo && a[j] > pivot)
			j--;
		if(i < j){
			tmp := a[i]; a[i] = a[j]; a[j] = tmp;
		}
	}
	tmp := a[lo]; a[lo] = a[j]; a[j] = tmp;
	qsort(a, lo, j-1);
	qsort(a, j+1, hi);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	n := 10000;
	t0 := sys->millisec();

	a := array[n] of int;
	x := 12345;
	for(i := 0; i < n; i++){
		x = (x*1103515245 + 12345) % 16r7FFFFFFF;
		if(x < 0)
			x = -x;
		a[i] = x % 100000;
	}

	qsort(a, 0, n-1);

	sorted := 1;
	for(i = 1; i < n; i++){
		if(a[i] < a[i-1])
			sorted = 0;
	}

	t1 := sys->millisec();
	sys->print("%d\n", sorted);
	sys->print("%d\n", t1-t0);
}
