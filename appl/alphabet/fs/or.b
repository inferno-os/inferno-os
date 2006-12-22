implement Or, Fsmodule;
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

Or: module {};

types(): string
{
	return "pppp*";
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
	spawn orgate(c, args);
	return ref Value.Vp(c);
}

orgate(c: Gatechan, args: list of ref Value)
{
	sub: list of Gatechan;
	for(; args != nil; args = tl args)
		sub = (hd args).p().i :: sub;
	sub = rev(sub);
	myreply := chan of int;
	while(((d, reply) := <-c).t0.t0 != nil){
		for(l := sub; l != nil; l = tl l){
			(hd l) <-= (d, myreply);
			if(<-myreply)
				break;
		}
		reply <-= l != nil;
	}
	for(; sub != nil; sub = tl sub)
		hd sub <-= (Nilentry, nil);
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}
