implement Primes;

include "draw.m";

Primes: module
{
	init: fn(nil: ref Draw->Context, argl: list of string);
};

include "sys.m";
	sys: Sys;
include "arg.m";
	arg: Arg;

LIM: con 1729;
MAX: con 1000000;
BUFSZ: con 256;

init(nil: ref Draw->Context, argl: list of string)
{
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;
	arg->init(argl);
	quiet := 0;
	lim := LIM;
	while((ch := arg->opt()) != 0){
		case (ch){
			'q' =>
				quiet = 1;
			* =>
				;
		}
	}
	argv := arg->argv();
	if(argv != nil)
		lim = int hd argv;
	if(lim < 2)
		lim = 2;
	if(lim > MAX)
		lim = MAX;
	c := chan[BUFSZ] of int;
	spawn prime(c, !quiet);
	for(n := 2; n <= lim; n++)
		c <-= n;
	c <-= 1;
}

prime(c: chan of int, pr: int)
{
	p := <-c;
	if(p == 1)
		exit;
	if(pr)
		sys->print("%d\n", p);
	nc := chan[BUFSZ] of int;
	spawn prime(nc, pr);
	for(;;){
		n := <-c;
		if(n%p)
			nc <-= n;
		if(n == 1)
			exit;
	}
}
