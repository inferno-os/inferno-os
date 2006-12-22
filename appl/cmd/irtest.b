implement Irtest;

include "sys.m";
	sys: Sys;
include "draw.m";
include "ir.m";
	ir: Ir;

Irtest: module
{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, nil: list of string)
{
	x := chan of int;
	p := chan of int;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	ir = load Ir Ir->PATH;
	if(ir == nil)
		ir = load Ir Ir->SIMPATH;
	if(ir == nil) {
		sys->fprint(stderr, "load ir: %r\n");
		return;
	}

	if(ir->init(x,p) != 0) {
		sys->fprint(stderr, "Ir->init: %r\n");
		return;
	}
	<-p;

	names := array[] of {
		"Zero",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"ChanUP",
		"ChanDN",
		"VolUP",
		"VolDN",
		"FF",
		"Rew",
		"Up",
		"Dn",
		"Select",
		"Power",
	};

	while((c := <-x) != Ir->EOF){
		c = ir->translate(c);
		if(c == ir->Error)
			sys->print("Error\n");
		else if(c >= len names)
			sys->print("unknown %d\n", c);
		else
			sys->print("%s\n", names[c]);
	}	
}
