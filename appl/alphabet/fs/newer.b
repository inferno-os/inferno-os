implement Newer, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Cmpchan, Option: import Fs;

Newer: module {};

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

types(): string
{
	return "m-d";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
}

# select those items in A that are newer than those in B
# or those that exist in A that don't in B.
# if -d flag is given, select all directories in A too.
run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, nil: list of ref Value): ref Value
{
	c := chan of (ref Sys->Dir, ref Sys->Dir, chan of int);
	spawn newer(c, opts != nil);
	return ref Value.Vm(c);
}

newer(c: Cmpchan, dflag: int)
{
	while(((d0, d1, reply) := <-c).t2 != nil){
		r: int;
		if(d0 == nil)
			r = 2r10;
		else if(d1 == nil)
			r = 2r01;
		else if(dflag && (d0.mode & Sys->DMDIR))
			r = 2r11;
		else {
			if(d0.mtime > d1.mtime)
				r = 2r01;
			else
				r= 2r10;
		}
		reply <-= r;
	}
}
