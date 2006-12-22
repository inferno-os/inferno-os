implement Select, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Select: module {};
types(): string
{
	return "ttp";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
}

run(nil: ref Draw->Context, nil: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	dst := Entrychan(chan of int, chan of Entry);
	spawn selectproc((hd args).t().i, dst, (hd tl args).p().i);
	return ref Value.Vt(dst);
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
