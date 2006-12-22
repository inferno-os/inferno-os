implement Path, Fsmodule;
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

Path: module {};

types(): string
{
	return "pss*-x";
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
			opts: list of Option, args: list of ref Value): ref Value
{
	# XXX cleanname all paths?
	c := chan of Gatequery;
	p: list of string;
	for(; args != nil; args = tl args)
		p = (hd args).s().i :: p;
	spawn pathgate(c, opts != nil, p);
	return ref Value.Vp(c);
}

pathgate(c: Gatechan, xflag: int, paths: list of string)
{
	if(xflag){
		while((((d, path, nil), reply) := <-c).t0.t0 != nil){
			for(q := paths; q != nil; q = tl q){
				r := 1;
				p := hd q;
				if(len path > len p)
					r = path[len p] != '/' || path[0:len p] != p;
				else if(len path == len p)
					r = path != p;
				if(r == 0)
					break;
			}
			reply <-= q == nil;
		}
	}else{
		while((((d, path, nil), reply) := <-c).t0.t0 != nil){
			for(q := paths; q != nil; q = tl q){
				r := 0;
				p := hd q;
				if(len path > len p)
					r = path[len p] == '/' && path[0:len p] == p;
				else if(len path == len p)
					r = path == p;
				else
					r = p[len path] == '/' && p[0:len path] == path;
				if(r)
					break;
			}
			reply <-= q != nil;
		}
	}
}
