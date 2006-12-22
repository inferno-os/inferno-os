implement Entries, Fsmodule;
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

Entries: module {};

types(): string
{
	return "tx";
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
	sc := Entrychan(chan of int, chan of Entry);
	spawn entriesproc((hd args).x().i, sc);
	return ref Value.Vt(sc);
}

entriesproc(c: Fschan, sc: Entrychan)
{
	if(<-sc.sync == 0){
		(<-c).t1 <-= Quit;
		exit;
	}
	indent := 0;
	names: list of string;
	name: string;
loop:
	for(;;){
		(d, reply) := <-c;
		if(d.dir != nil){
			p: string;
			depth := indent;
			if(d.dir.mode & Sys->DMDIR){
				names = name :: names;
				if(indent == 0)
					name = d.dir.name;
				else{
					if(name[len name - 1] != '/')
						name[len name] = '/';
					name += d.dir.name;
				}
				indent++;
				reply <-= Down;
				p = name;
			}else{
				p = name;
				if(p[len p - 1] != '/')
					p[len p] = '/';
				p += d.dir.name;
				reply <-= Next;
			}
			if(p != nil)
				sc.c <-= (d.dir, p, depth);
		}else{
			reply <-= Next;
			if(d.dir == nil && d.data == nil){
				if(--indent == 0)
					break loop;
				(name, names) = (hd names, tl names);
			}
		}
	}
	sc.c <-= Nilentry;
}
