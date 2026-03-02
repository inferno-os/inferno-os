implement BenchNbody;

include "sys.m";
	sys: Sys;

include "draw.m";

include "math.m";
	math: Math;

BenchNbody: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

nbody(steps: int): int
{
	size := 5;
	px := array[size] of real;
	py := array[size] of real;
	vx := array[size] of real;
	vy := array[size] of real;
	mass := array[size] of real;

	px[0] = 0.0; py[0] = 0.0; vx[0] = 0.0; vy[0] = 0.0; mass[0] = 1000.0;
	px[1] = 100.0; py[1] = 0.0; vx[1] = 0.0; vy[1] = 10.0; mass[1] = 1.0;
	px[2] = 200.0; py[2] = 0.0; vx[2] = 0.0; vy[2] = 7.0; mass[2] = 1.0;
	px[3] = 0.0; py[3] = 150.0; vx[3] = 8.0; vy[3] = 0.0; mass[3] = 1.0;
	px[4] = 0.0; py[4] = 250.0; vx[4] = 6.0; vy[4] = 0.0; mass[4] = 1.0;

	dt := 0.01;

	for(step := 0; step < steps; step++) {
		for(i := 0; i < size; i++) {
			for(j := i+1; j < size; j++) {
				dx := px[j] - px[i];
				dy := py[j] - py[i];
				dist := math->sqrt(dx*dx + dy*dy);
				if(dist < 0.001)
					dist = 0.001;
				force := mass[i] * mass[j] / (dist * dist);
				fx := force * dx / dist;
				fy := force * dy / dist;
				vx[i] += dt * fx / mass[i];
				vy[i] += dt * fy / mass[i];
				vx[j] -= dt * fx / mass[j];
				vy[j] -= dt * fy / mass[j];
			}
		}
		for(k := 0; k < size; k++) {
			px[k] += dt * vx[k];
			py[k] += dt * vy[k];
		}
	}
	return int (px[0] * 1000.0) + int (py[0] * 1000.0) +
		int (px[1] * 1000.0) + int (py[1] * 1000.0);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;

	t1 := sys->millisec();
	iterations := 10;
	result := 0;
	for(iter := 0; iter < iterations; iter++)
		result += nbody(5000);
	t2 := sys->millisec();
	sys->print("BENCH nbody %d ms %d iters %d\n", t2-t1, iterations, result);
}
