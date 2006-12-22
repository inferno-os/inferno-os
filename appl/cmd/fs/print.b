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
	return "vt";
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

run(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	sync := chan of int;
	spawn printproc(sync, (hd args).t().i, report.start("print"));
	return ref Value.V(sync);
}

printproc(sync: chan of int, c: Entrychan, errorc: chan of string)
{
	if(<-sync == 0){
		c.sync <-= 0;
		quit(errorc);
		exit;
	}
	c.sync <-= 1;
	while(((d, p, nil) := <-c.c).t0 != nil)
		sys->print("%s\n", p);
	quit(errorc);
}
