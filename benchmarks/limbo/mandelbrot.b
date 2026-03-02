implement BenchMandelbrot;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchMandelbrot: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

mandelbrot(size, maxiter: int): int
{
	sum := 0;
	for(y := 0; y < size; y++) {
		for(x := 0; x < size; x++) {
			cr := 2.0 * real x / real size - 1.5;
			ci := 2.0 * real y / real size - 1.0;
			zr := 0.0;
			zi := 0.0;
			iter := 0;
			while(iter < maxiter) {
				if(zr*zr + zi*zi > 4.0)
					break;
				tr := zr*zr - zi*zi + cr;
				zi = 2.0*zr*zi + ci;
				zr = tr;
				iter++;
			}
			sum += iter;
		}
	}
	return sum;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 5;
	total := 0;
	for(iter := 0; iter < iterations; iter++)
		total += mandelbrot(200, 200);
	t2 := sys->millisec();
	sys->print("BENCH mandelbrot %d ms %d iters %d\n", t2-t1, iterations, total);
}
