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
	return "tpt";
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
	dst := Entrychan(chan of int, chan of Entry);
	spawn selectproc((hd tl args).t().i, dst, (hd args).p().i);
	return ref Value.T(dst);
}

selectproc(src, dst: Entrychan, query: Gatechan)
{
	if(<-dst.sync == 0){
		query <-= (Nilentry, nil);
		src.sync <-= 0;
		exit;
	}
	src.sync <-= 1;
	reply := chan of int;
	while((d := <-src.c).t0 != nil){
		query <-= (d, reply);
		if(<-reply)
			dst.c <-= d;
	}
	dst.c <-= Nilentry;
	query <-= (Nilentry, nil);
}
