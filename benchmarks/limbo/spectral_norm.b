implement BenchSpectralNorm;

include "sys.m";
	sys: Sys;

include "draw.m";

include "math.m";
	math: Math;

BenchSpectralNorm: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

evalA(i, j: int): real
{
	return 1.0 / real ((i+j)*(i+j+1)/2 + i + 1);
}

multiplyAv(n: int, v, av: array of real)
{
	for(i := 0; i < n; i++) {
		sum := 0.0;
		for(j := 0; j < n; j++)
			sum += evalA(i, j) * v[j];
		av[i] = sum;
	}
}

multiplyAtv(n: int, v, atv: array of real)
{
	for(i := 0; i < n; i++) {
		sum := 0.0;
		for(j := 0; j < n; j++)
			sum += evalA(j, i) * v[j];
		atv[i] = sum;
	}
}

multiplyAtAv(n: int, v, atav: array of real)
{
	u := array[n] of real;
	multiplyAv(n, v, u);
	multiplyAtv(n, u, atav);
}

spectralNorm(n: int): int
{
	u := array[n] of real;
	for(i := 0; i < n; i++)
		u[i] = 1.0;
	v := array[n] of real;

	for(k := 0; k < 10; k++) {
		multiplyAtAv(n, u, v);
		multiplyAtAv(n, v, u);
	}

	vBv := 0.0;
	vv := 0.0;
	for(j := 0; j < n; j++) {
		vBv += u[j] * v[j];
		vv += v[j] * v[j];
	}
	result := math->sqrt(vBv / vv);
	return int (result * 1000000.0);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;

	t1 := sys->millisec();
	iterations := 5;
	total := 0;
	for(iter := 0; iter < iterations; iter++)
		total += spectralNorm(300);
	t2 := sys->millisec();
	sys->print("BENCH spectral_norm %d ms %d iters %d\n", t2-t1, iterations, total);
}
