implement Ackermann;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;

Ackermann: module
{
        init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	argv = tl argv;		# remove program name
	m := n := 0;
	if(argv != nil){
		m = int hd argv;
		argv = tl argv;
	}
	if(m < 0)
		m = 0;
	if(argv != nil)
		n = int hd argv;
	if(n < 0)
		n = 0;
	t0 := sys->millisec();
	a := ack(m, n);
	t1 := sys->millisec();
	sys->print("A(%d, %d) = %d (t = %d ms)\n", m, n, a, t1-t0);	
}

ack(m, n: int) : int
{
        if(m == 0)
                return n+1;
        else if(n == 0)
                return ack(m-1, 1);
        else
                return ack(m-1, ack(m, n-1));
}
