implement BenchInterface;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchInterface: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# Limbo uses pick ADTs for polymorphism (equivalent to interfaces)
Shape: adt {
	pick {
	Rect =>
		w, h: int;
	Circle =>
		r: int;
	}
};

area(s: ref Shape): int
{
	pick p := s {
	Rect =>
		return p.w * p.h;
	Circle =>
		return p.r * p.r * 3;
	}
	return 0;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	iterations := 1000;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		shapes := array[2000] of ref Shape;
		for(i := 0; i < 2000; i++) {
			if(i % 2 == 0)
				shapes[i] = ref Shape.Rect(i, i+1);
			else
				shapes[i] = ref Shape.Circle(i);
		}
		sum := 0;
		for(j := 0; j < len shapes; j++)
			sum += area(shapes[j]);
		total += sum;
	}
	t2 := sys->millisec();
	sys->print("BENCH interface %d ms %d iters %d\n", t2-t1, iterations, total);
}
