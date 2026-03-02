implement BenchMatrix;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchMatrix: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

matmul(n: int): int
{
	a := array[n*n] of int;
	b := array[n*n] of int;
	c := array[n*n] of int;

	for(ii := 0; ii < n*n; ii++) {
		a[ii] = ii + 1;
		b[ii] = ii * 2;
	}

	for(i := 0; i < n; i++) {
		for(j := 0; j < n; j++) {
			sum := 0;
			for(k := 0; k < n; k++)
				sum += a[i*n+k] * b[k*n+j];
			c[i*n+j] = sum;
		}
	}
	return c[0] + c[n*n-1];
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 10;
	result := 0;
	for(iter := 0; iter < iterations; iter++)
		result += matmul(120);
	t2 := sys->millisec();
	sys->print("BENCH matrix %d ms %d iters %d\n", t2-t1, iterations, result);
}
