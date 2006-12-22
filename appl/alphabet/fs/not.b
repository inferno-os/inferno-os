implement Not, Fsmodule;
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

Not: module {};

types(): string
{
	return "pp";
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
	c := chan of Gatequery;
	spawn notgate(c, (hd args).p().i);
	return ref Value.Vp(c);
}

notgate(c, sub: Gatechan)
{
	myreply := chan of int;
	while(((d, reply) := <-c).t0.t0 != nil){
		sub <-= (d, myreply);
		reply <-= !<-myreply;
	}
	sub <-= (Nilentry, nil);
}
