implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

types(): string
{
	return "ps";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
}

run(nil: ref Draw->Context, nil: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	d := int (hd args).s().i;
	if(d <= 0){
		sys->fprint(sys->fildes(2), "fs: depth: invalid depth\n");
		return nil;
	}
	c := chan of Gatequery;
	spawn depthgate(c, d);
	return ref Value.P(c);
}

depthgate(c: Gatechan, d: int)
{
	while((((dir, nil, depth), reply) := <-c).t0.t0 != nil)
		reply <-= depth <= d;
}
